import AppKit
import Darwin
import QuartzCore

typealias WindowSnapshotLoader = @Sendable (CGFloat) -> Result<[DetectedWindow], WindowDetectionError>
typealias WindowImageLoader = @Sendable (CGWindowID, NSSize) async throws -> NSImage?

/// Holds the single system-cursor hide that the self-drawn selection pointer
/// needs, and guarantees it is undone exactly once.
///
/// The WindowServer paints the hardware cursor at its own cadence; an AppKit
/// layer update trails it by a display frame, which is what "the guides chase
/// the pointer" looks like. The overlay therefore paints the pointer itself and
/// hides the system one — but hide/unhide are reference counted, so a second
/// `unhide()` would steal a hide that belongs to someone else, while a missing
/// one leaves the user without a cursor.
///
/// Three layers keep that balance from either side:
///
/// 1. **Counting.** `hideDepth` is a 0/1 state machine: one *confirmed*
///    `NSCursor.hide()` is on the books exactly while it is 1, `hide()` can
///    never issue a second one, and `performUnhide()` is the only way down and
///    refuses to run at 0. Every path calls `restore()`; repeats are no-ops.
/// 2. **Activation.** AppKit drops cursor calls while another app owns the
///    foreground. `restore()` while inactive therefore keeps the hide on the
///    books and finishes it on the next `didBecomeActive` — otherwise the
///    unhide is silently lost, the counter says "restored", and the cursor
///    stays hidden until another app takes the foreground.
/// 3. **Watchdog.** After a session closes, one delayed read-back of
///    `CGCursorIsVisible()` proves the cursor came back; if it did not (or the
///    read-back is unavailable), exactly one extra `unhide()` is forced and
///    logged. A stray extra cursor is the cheaper failure than a user with no
///    pointer.
///
/// Hiding is only half the job: if it cannot be *confirmed*, the overlay must
/// not paint a second pointer on top of the system one. `CGCursorIsVisible()`
/// is the only public read-back for "is a cursor being drawn"; it is marked
/// unavailable in the SDK, so it is resolved by symbol name and treated as "no
/// evidence" when absent — the caller then falls back to guides only.
final class SystemCursorHider {
    struct Drivers {
        var hide: () -> Void = { NSCursor.hide() }
        var unhide: () -> Void = { NSCursor.unhide() }
        /// `nil` when the read-back is unavailable on this system.
        var isCursorVisible: () -> Bool? = { SystemCursorHider.windowServerCursorIsVisible() }
        /// AppKit ignores cursor changes from an app that does not own the
        /// foreground. Defaults to the process's real activation state.
        var isAppActive: () -> Bool = { NSApp?.isActive ?? false }
        /// Waits for the next "this app became active" moment; the returned
        /// closure cancels the wait. Observes `didBecomeActive` by default.
        var waitForActivation: (@escaping () -> Void) -> () -> Void = { body in
            SystemCursorHider.observeNextActivation(body)
        }
    }

    private let drivers: Drivers
    private let log: (String) -> Void
    /// How long after a closed session the watchdog reads the cursor back.
    private let watchdogDelay: TimeInterval

    /// 0/1: one confirmed hide is on the books exactly while this is 1.
    private(set) var hideDepth = 0
    var isHidden: Bool { hideDepth > 0 }
    /// Set after a hide that could not be confirmed: this session keeps the
    /// system cursor and draws the guides only.
    private(set) var isUnavailable = false
    /// Failed confirmations so far; `NSCursor.hide()` is a no-op while another
    /// app owns the foreground, so one retry after activation is worth it.
    private(set) var attempts = 0
    /// Every `restore()` request, including harmless repeats. The exit paths
    /// must really reach it; the harness asserts on this.
    private(set) var restoreRequests = 0
    /// Extra unhides the watchdog had to force (bounded: at most one per close).
    private(set) var forcedUnhides = 0
    /// A hide was confirmed in this session, so a final blind unhide is allowed.
    private(set) var everHid = false

    /// Cancellation for the deferred restore, while it waits for activation.
    private var pendingActivationRestore: (() -> Void)?
    private var watchdog: DispatchWorkItem?
    /// Bumped on every schedule/cancel so a stale item cannot fire twice.
    private var watchdogGeneration = 0

    /// `NSCursor.hide()`/`unhide()` are a single process-wide counter, so a
    /// retry that outlives its hider must not undo a hide that a live session
    /// now owns. This is the app-wide view of "we still own a hide".
    private static let ownershipLock = NSLock()
    private static var ownedHides = 0

    private static func noteOwnedHide(_ delta: Int) {
        ownershipLock.lock()
        ownedHides = max(0, ownedHides + delta)
        ownershipLock.unlock()
    }

    static var hasLiveOwnedHide: Bool {
        ownershipLock.lock()
        defer { ownershipLock.unlock() }
        return ownedHides > 0
    }

    init(
        drivers: Drivers = Drivers(),
        watchdogDelay: TimeInterval = 0.5,
        log: @escaping (String) -> Void = { NSLog("%@", $0) }
    ) {
        self.drivers = drivers
        self.watchdogDelay = watchdogDelay
        self.log = log
    }

    /// Hides the system cursor and confirms the WindowServer stopped drawing it.
    /// A `false` return means the overlay must not draw its own pointer.
    @discardableResult
    func hide() -> Bool {
        // Never past one: a second hide would need a second unhide, and one of
        // those would steal a hide that belongs to another session.
        if hideDepth > 0 { return true }
        guard !isUnavailable else { return false }

        // A probe that reports "not visible" *before* we asked cannot prove
        // anything: it would also report that when it is broken. Only a visible
        // baseline turning invisible is evidence.
        let baseline = drivers.isCursorVisible()
        drivers.hide()
        var confirmed = false
        if baseline == true {
            // Measured on this machine the state flips in under 1 ms; poll a
            // few times so one slow window-server round trip is not a failure.
            for _ in 0..<8 {
                if drivers.isCursorVisible() == false {
                    confirmed = true
                    break
                }
                usleep(1_000)
            }
        }
        guard confirmed else {
            // Balance the hide we just made and stay on the system cursor.
            // (An ignored hide is balanced as well: an unhide too many only
            // shows a cursor, a hide too many hides it.)
            drivers.unhide()
            attempts += 1
            // `NSCursor.hide()` is only honoured while this app owns the
            // foreground, so the first attempt can fail before activation
            // lands. Give the caller a couple of chances, then stop asking.
            if baseline == nil || attempts >= 3 {
                isUnavailable = true
            }
            if attempts == 1 || isUnavailable {
                log("BlinkClip: system cursor could not be hidden"
                    + " (read-back \(baseline.map { $0 ? "visible" : "not visible" } ?? "unavailable"));"
                    + " keeping the system cursor and drawing the guides only")
            }
            return false
        }
        hideDepth = 1
        everHid = true
        Self.noteOwnedHide(1)
        // A restore that was waiting for activation would undo this fresh hide
        // the moment activation landed; the caller asked to hide again instead.
        cancelActivationRestore()
        return true
    }

    /// Restores the system cursor exactly once. Safe from every exit path:
    /// selection lock, teardown, lost activation, window close, termination,
    /// `deinit`.
    func restore() {
        restoreRequests += 1
        guard hideDepth > 0 else { return }
        if drivers.isAppActive() {
            cancelActivationRestore()
            performUnhide()
            return
        }
        // An unhide issued right now would be dropped by AppKit, and the 0/1
        // counter would claim a restored cursor that is still not drawn. Keep
        // the hide on the books and finish it on the next activation.
        armActivationRestore()
    }

    /// After the overlay closed: one delayed read-back that proves the cursor
    /// came back. Schedules at most one check per call.
    ///
    /// The item holds the hider *strongly*: the controller usually deallocates
    /// right after `tearDown`, and a weakly captured watchdog would be gone
    /// with it — the exact hole this net exists to close.
    func scheduleRestoreWatchdog() {
        guard everHid else { return }
        cancelRestoreWatchdog()
        watchdogGeneration += 1
        let generation = watchdogGeneration
        let item = DispatchWorkItem { [self] in
            guard watchdogGeneration == generation else { return }
            runRestoreWatchdog()
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + watchdogDelay, execute: item)
    }

    func cancelRestoreWatchdog() {
        watchdogGeneration += 1
        watchdog?.cancel()
        watchdog = nil
    }

    /// The delayed verification itself (also callable directly by the harness).
    /// It balances a restore that never got its activation, then forces at most
    /// one extra unhide if the WindowServer still draws no cursor.
    func runRestoreWatchdog() {
        watchdog = nil
        guard everHid else {
            // Nothing was ever hidden here: never steal another app's unhide.
            cancelActivationRestore()
            return
        }
        if hideDepth > 0 {
            // Activation never arrived after the overlay closed; leaving the
            // counter at 1 would outlive this session. Balance it now.
            performUnhide()
        }
        var visible = drivers.isCursorVisible()
        // A read-back taken right after an unhide can trail it by a moment;
        // the poll only keeps that from becoming a false alarm.
        var polls = 0
        while visible == false, polls < 8 {
            usleep(1_000)
            visible = drivers.isCursorVisible()
            polls += 1
        }
        switch visible {
        case .some(true):
            cancelActivationRestore()
            log("BlinkClip: cursor-restore watchdog: system cursor visible after the overlay closed")
        case .some(false):
            // The counter is balanced but no cursor is drawn: the unhide was
            // dropped (background app) or the hide was never really ours.
            // One bounded extra unhide, then keep retrying on activation.
            drivers.unhide()
            forcedUnhides += 1
            // Only a background app needs the extra activation retry; when this
            // app is frontmost the unhide above is the one that lands.
            if !drivers.isAppActive() {
                armActivationRestore()
            }
            log("BlinkClip: cursor-restore watchdog still saw a hidden system cursor; forced one unhide")
        case .none:
            // No read-back: cannot verify. Restore visibility unconditionally —
            // one extra cursor is the cheaper failure.
            drivers.unhide()
            forcedUnhides += 1
            log("BlinkClip: no cursor read-back after the overlay closed; forced one unhide (verification unavailable)")
        }
    }

    /// `NSApp` is terminating: there is no later run-loop turn, so this must be
    /// synchronous, and it must not leave a pending watchdog behind.
    func forceRestoreForTermination() {
        cancelRestoreWatchdog()
        cancelActivationRestore()
        if performUnhide() {
            log("BlinkClip: system cursor restored before the app terminated")
        }
        guard everHid, drivers.isCursorVisible() == false else { return }
        drivers.unhide()
        forcedUnhides += 1
        log("BlinkClip: system cursor was still hidden at termination; forced one unhide")
    }

    deinit {
        cancelRestoreWatchdog()
        cancelActivationRestore()
        let wasHidden = hideDepth > 0
        if wasHidden {
            // Last-resort net: a controller that dies without `tearDown` must
            // not leave the user without a cursor. There is no run loop left to
            // wait on, so balance now.
            hideDepth = 0
            Self.noteOwnedHide(-1)
            drivers.unhide()
        }
        guard everHid else { return }
        guard wasHidden || !drivers.isAppActive() || drivers.isCursorVisible() == false else { return }
        // When another app owns the foreground the unhide above can be dropped.
        // Leave one activation retry that does not need this object to survive,
        // but never let it undo a hide that a live session has taken over.
        let drivers = self.drivers
        let log = self.log
        _ = drivers.waitForActivation {
            guard !SystemCursorHider.hasLiveOwnedHide,
                  drivers.isCursorVisible() == false else { return }
            drivers.unhide()
            log("BlinkClip: activation retry after the cursor hider was released; forced one unhide")
        }
    }

    private func performUnhide() -> Bool {
        guard hideDepth > 0 else { return false }
        hideDepth = 0
        Self.noteOwnedHide(-1)
        drivers.unhide()
        return true
    }

    private func armActivationRestore() {
        guard pendingActivationRestore == nil else { return }
        log("BlinkClip: system cursor restore deferred until this app is active again")
        pendingActivationRestore = drivers.waitForActivation { [weak self] in
            guard let self else { return }
            self.pendingActivationRestore = nil
            if self.performUnhide() {
                self.log("BlinkClip: system cursor restored after activation returned")
                return
            }
            // The watchdog already balanced the counter, but its unhide can be
            // dropped while the app is in the background; verify on activation.
            if self.drivers.isCursorVisible() == false {
                self.drivers.unhide()
                self.forcedUnhides += 1
                self.log("BlinkClip: activation retry found the system cursor still hidden; forced one unhide")
            }
        }
    }

    private func cancelActivationRestore() {
        pendingActivationRestore?()
        pendingActivationRestore = nil
    }

    /// One-shot `didBecomeActive` wait; the returned closure cancels it.
    static func observeNextActivation(_ body: @escaping () -> Void) -> () -> Void {
        let observation = ActivationObservation()
        observation.token = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            observation.cancel()
            body()
        }
        return { observation.cancel() }
    }

    private final class ActivationObservation {
        var token: NSObjectProtocol?

        func cancel() {
            if let token { NotificationCenter.default.removeObserver(token) }
            token = nil
        }
    }

    /// `CGCursorIsVisible()` reached by symbol name, because the SDK marks it
    /// unavailable. Returns `nil` when the symbol is gone (then no hide can be
    /// confirmed).
    static func windowServerCursorIsVisible() -> Bool? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGCursorIsVisible") else {
            return nil
        }
        typealias Function = @convention(c) () -> UInt32
        return unsafeBitCast(symbol, to: Function.self)() != 0
    }
}

struct CaptureResult {
    let rect: CGRect       // In CG coordinates (top-left origin) for capture
    let screen: NSScreen   // The screen where selection was made
    let screenRect: NSRect // In AppKit coordinates for editor positioning
}

class OverlayWindowController {
    /// Where a preset image came from — drives the source-specific edit hint.
    enum PresetSource {
        case finder
        case clipboard
        case pin
        case merge
        case fullScreen
    }

    enum PostCaptureAction {
        case edit
        case quickPin
        case textRecognition
        case copyImageText
        case screenshotTranslation
        case record

        var cursorChipText: String {
            switch self {
            case .record:
                return L10n.dragToRecord
            case .edit:
                return L10n.dragToScreenshot
            case .quickPin:
                return L10n.dragToQuickPin
            case .textRecognition:
                return L10n.dragToTextRecognition
            case .copyImageText:
                return L10n.dragToCopyImageText
            case .screenshotTranslation:
                return L10n.dragToScreenshotTranslation
            }
        }
    }

    struct SuspendedEditDraft {
        let captureRect: CGRect
        let screenDisplayID: CGDirectDisplayID?
        let screenFrame: NSRect
        let selectionRect: NSRect
        let selectionViewRect: NSRect
        let selectionSizeLabelOverride: String?
        let selectionLocked: Bool
        let selectionInteractionEnabled: Bool
        let selectionAdjustmentBounds: NSRect?
        let preSnapshot: CGImage?
        let overrideBaseImage: NSImage?
        let windowBaseImage: NSImage?
        let isWindowCapture: Bool
        let editorState: EditWindowController.RestorableState
        let keepsEditorAcrossSpaces: Bool
    }

    private var windows: [NSWindow] = []
    private var preparedOverlayPanels: [CGDirectDisplayID: OverlayPanel] = [:]
    private var chipWindow: CursorChipWindow?
    private var magnifierLensPanel: MagnifierLensPanelWindow?
    private var magnifierLensPanelFormat: MagnifierLensPanelWindow.Format = .hex
    private var mouseMovedLocalMonitor: Any?
    private var mouseMovedGlobalMonitor: Any?
    private var magnifierLensPanelKeyDownGlobalMonitor: Any?
    private var magnifierLensPanelActive: Bool { magnifierLensPanel != nil }
    private var screenFramesByDisplayID: [CGDirectDisplayID: NSRect] = [:]
    private var escLocalMonitor: Any?
    private var escGlobalMonitor: Any?
    private var leftMouseLocalMonitor: Any?
    private var rightMouseLocalMonitor: Any?
    private var rightMouseGlobalMonitor: Any?
    private var editController: EditWindowController?
    private var activeSelectionView: SelectionView?
    private var activeScreen: NSScreen?
    private var historyEntries: [HistoryEntry] = []
    private var historyEntryIndex: Int?
    private var historyEditorDrafts: [URL: EditWindowController.RestorableState] = [:]
    private var activeEditorContext: ActiveEditorContext?
    private var currentEditHistoryDraft: CurrentEditHistoryDraft?
    private let windowDetector = WindowDetector()
    private let windowSnapshotLoader: WindowSnapshotLoader
    private let windowImageLoader: WindowImageLoader
    private let snapshotProvider: ScreenSnapshotProviding
    private let eventTrackingStateProvider: () -> Bool
    private let eventTrackingDismissal: () -> Void
    private let colorSamplerActiveProvider: () -> Bool
    private let modalWindowProvider: () -> NSWindow?
    private let modalWindowDismissal: (NSWindow) -> Void
    private let triggerContext: CaptureTriggerContext?
    private let onFirstFramePresented: (() -> Void)?
    private var screenSnapshots: [CGDirectDisplayID: CGImage] = [:]
    private var selectionViewsByDisplayID: [CGDirectDisplayID: SelectionView] = [:]
    private var expectedSnapshotDisplayIDs = Set<CGDirectDisplayID>()
    private var failedSnapshotDisplayIDs = Set<CGDirectDisplayID>()
    private var snapshotCancellation: ScreenSnapshotCancellation?
    private var snapshotDeadline: DispatchWorkItem?
    private var snapshotTimeout: TimeInterval = 8
    private var windowCaptureTimeout: TimeInterval = 2
    private var windowCaptureTask: Task<Void, Never>?
    private var pendingWindowCapture: PendingWindowCapture?
    private var prefetchedWindow: DetectedWindow?
    private var windowPrefetchTask: Task<NSImage?, Never>?
    private var snapshotCaptureFinished = false
    private var pendingFocusSensitiveForegroundClaim = false
    private var pendingFocusSensitiveSnapshotDisplayIDs = Set<CGDirectDisplayID>()
    private var pendingSelection: PendingSelection?
    private let onComplete: (NSImage?) -> Void
    private let onRequestFocusReturn: (() -> Void)?
    private let onRecordingSelection: ((NSRect, NSScreen) -> Void)?
    private let onSuspend: ((SuspendedEditDraft) -> Void)?
    private let postCaptureAction: PostCaptureAction

    /// Image-edit mode: when set, `activate()` skips the user's drag-to-select
    /// step and immediately opens the editor on the supplied image, sized to
    /// fit the screen with margins.
    private let presetImage: NSImage?
    /// In image-edit mode, where `presetImage` came from. nil otherwise.
    private let presetSource: PresetSource?
    private let suspendedDraft: SuspendedEditDraft?
    private let keepsEditorAcrossSpaces: Bool
    private var presentationScheduled = false
    /// Bumped whenever a presentation starts or ends so stale asynchronous
    /// snapshot/window-list callbacks cannot mutate a newer overlay session.
    private var presentationGeneration = 0
    private var sessionEnded = false
    private var deferredPresentationBlocker: PresentationBlocker?
    private var firstFrameReported = false
    private var firstFrameTargetDisplayID: CGDirectDisplayID?

    private enum PresentationBlocker {
        case eventTracking
        case applicationModal(NSWindow)
    }

    private struct ActiveEditorContext {
        let captureRect: CGRect
        let screen: NSScreen
        let selectionRect: NSRect
        let selectionViewRect: NSRect
        weak var hostSelectionView: SelectionView?
        let selectionViewState: SelectionViewState
        let preSnapshot: CGImage?
        let overrideBaseImage: NSImage?
        let windowBaseImage: NSImage?
        let isWindowCapture: Bool
    }

    private struct CurrentEditHistoryDraft {
        let captureRect: CGRect
        let screen: NSScreen
        let selectionRect: NSRect
        let selectionViewRect: NSRect
        weak var hostSelectionView: SelectionView?
        let selectionViewState: SelectionViewState
        let preSnapshot: CGImage?
        let overrideBaseImage: NSImage?
        let windowBaseImage: NSImage?
        let isWindowCapture: Bool
        var editorState: EditWindowController.RestorableState?
    }

    private struct SelectionViewState {
        let selectionSizeLabelOverride: String?
        let selectionLocked: Bool
        let selectionInteractionEnabled: Bool
        let selectionAdjustmentBounds: NSRect?

        init(selectionView: SelectionView) {
            selectionSizeLabelOverride = selectionView.selectionSizeLabelOverride
            selectionLocked = selectionView.selectionLocked
            selectionInteractionEnabled = selectionView.selectionInteractionEnabled
            selectionAdjustmentBounds = selectionView.selectionAdjustmentBounds
        }

        init(
            selectionSizeLabelOverride: String?,
            selectionLocked: Bool,
            selectionInteractionEnabled: Bool,
            selectionAdjustmentBounds: NSRect? = nil
        ) {
            self.selectionSizeLabelOverride = selectionSizeLabelOverride
            self.selectionLocked = selectionLocked
            self.selectionInteractionEnabled = selectionInteractionEnabled
            self.selectionAdjustmentBounds = selectionAdjustmentBounds
        }

        func apply(to selectionView: SelectionView) {
            selectionView.selectionSizeLabelOverride = selectionSizeLabelOverride
            selectionView.selectionLocked = selectionLocked
            selectionView.selectionInteractionEnabled = selectionInteractionEnabled
            selectionView.selectionAdjustmentBounds = selectionAdjustmentBounds
        }
    }

    private struct PendingSelection {
        let rect: NSRect
        let screenRect: NSRect
        let captureRect: CGRect
        let screen: NSScreen
        let selectionView: SelectionView
        let displayID: CGDirectDisplayID
        let isWindowSelection: Bool
        let windowID: CGWindowID?
    }

    private struct PendingWindowCapture {
        let id: UUID
        let generation: Int
        let request: PendingSelection
        let preSnapshot: CGImage?
    }

    /// Route the default copy-to-clipboard hotkey (double-tap ⌘) into the
    /// editor while the overlay is active. No-op when the editor isn't up yet.
    func confirmFromKeyboard() {
        editController?.confirmFromKeyboard()
    }

    @discardableResult
    func pinFromKeyboard() -> Bool {
        editController?.pinFromKeyboard() ?? false
    }

    static func prewarmPresentationSurfaces() {
        OverlayPanelPool.shared.prewarm(screens: NSScreen.screens)
    }

    static func invalidateAndPrewarmPresentationSurfaces() {
        OverlayPanelPool.shared.invalidateAndPrewarm(screens: NSScreen.screens)
    }

    func screenParametersDidChange() {
        guard presentationScheduled,
              !sessionEnded,
              editController == nil else { return }
        cancel()
    }

    init(
        postCaptureAction: PostCaptureAction = .edit,
        triggerContext: CaptureTriggerContext = CaptureTriggerContext(source: .programmatic),
        snapshotProvider: ScreenSnapshotProviding = ScreenSnapshotProvider.shared,
        // Injectable so the harness can exercise the "hide not confirmed" path
        // without touching the real cursor.
        cursorHider: SystemCursorHider = SystemCursorHider(),
        windowSnapshotLoader: @escaping WindowSnapshotLoader = {
            WindowDetector.snapshot(primaryScreenArea: $0)
        },
        windowImageLoader: WindowImageLoader? = nil,
        snapshotTimeout: TimeInterval = 8,
        windowCaptureTimeout: TimeInterval = 2,
        eventTrackingStateProvider: @escaping () -> Bool = {
            OverlayWindowController.isRunningEventTrackingMode
        },
        eventTrackingDismissal: @escaping () -> Void = {
            OverlayWindowController.dismissActiveEventTrackingSurface()
        },
        colorSamplerActiveProvider: @escaping () -> Bool = {
            ColorPickerRunner.shared.isActive
        },
        modalWindowProvider: @escaping () -> NSWindow? = {
            OverlayWindowController.currentApplicationModalWindow()
        },
        modalWindowDismissal: @escaping (NSWindow) -> Void = { window in
            OverlayWindowController.abortApplicationModalSession(for: window)
        },
        onFirstFramePresented: (() -> Void)? = nil,
        onRecordingSelection: ((NSRect, NSScreen) -> Void)? = nil,
        onRequestFocusReturn: (() -> Void)? = nil,
        onSuspend: ((SuspendedEditDraft) -> Void)? = nil,
        onComplete: @escaping (NSImage?) -> Void
    ) {
        self.presetImage = nil
        self.presetSource = nil
        self.suspendedDraft = nil
        self.keepsEditorAcrossSpaces = false
        self.postCaptureAction = postCaptureAction
        self.triggerContext = triggerContext
        self.snapshotProvider = snapshotProvider
        self.systemCursor = cursorHider
        self.windowSnapshotLoader = windowSnapshotLoader
        self.windowImageLoader = windowImageLoader ?? WindowCaptureSource.makeLoader()
        self.snapshotTimeout = snapshotTimeout
        self.windowCaptureTimeout = windowCaptureTimeout
        self.eventTrackingStateProvider = eventTrackingStateProvider
        self.eventTrackingDismissal = eventTrackingDismissal
        self.colorSamplerActiveProvider = colorSamplerActiveProvider
        self.modalWindowProvider = modalWindowProvider
        self.modalWindowDismissal = modalWindowDismissal
        self.onFirstFramePresented = onFirstFramePresented
        self.onRecordingSelection = onRecordingSelection
        self.onRequestFocusReturn = onRequestFocusReturn
        self.onSuspend = onSuspend
        self.onComplete = onComplete
    }

    init(
        presetImage: NSImage,
        presetSource: PresetSource,
        keepsEditorAcrossSpaces: Bool = false,
        onRequestFocusReturn: (() -> Void)? = nil,
        onSuspend: ((SuspendedEditDraft) -> Void)? = nil,
        onComplete: @escaping (NSImage?) -> Void
    ) {
        self.presetImage = presetImage
        self.presetSource = presetSource
        self.suspendedDraft = nil
        self.keepsEditorAcrossSpaces = keepsEditorAcrossSpaces
        self.postCaptureAction = .edit
        self.triggerContext = nil
        self.snapshotProvider = ScreenSnapshotProvider.shared
        self.windowSnapshotLoader = { WindowDetector.snapshot(primaryScreenArea: $0) }
        self.windowImageLoader = { windowID, pointSize in
            try await ScreenCapturer.captureWindowAsync(
                windowID: windowID,
                pointSize: pointSize
            )
        }
        self.eventTrackingStateProvider = {
            OverlayWindowController.isRunningEventTrackingMode
        }
        self.eventTrackingDismissal = {
            OverlayWindowController.dismissActiveEventTrackingSurface()
        }
        self.colorSamplerActiveProvider = { ColorPickerRunner.shared.isActive }
        self.modalWindowProvider = {
            OverlayWindowController.currentApplicationModalWindow()
        }
        self.modalWindowDismissal = { window in
            OverlayWindowController.abortApplicationModalSession(for: window)
        }
        self.onFirstFramePresented = nil
        self.onRecordingSelection = nil
        self.onRequestFocusReturn = onRequestFocusReturn
        self.onSuspend = onSuspend
        self.onComplete = onComplete
    }

    init(
        suspendedDraft: SuspendedEditDraft,
        onRecordingSelection: ((NSRect, NSScreen) -> Void)? = nil,
        onRequestFocusReturn: (() -> Void)? = nil,
        onSuspend: ((SuspendedEditDraft) -> Void)? = nil,
        onComplete: @escaping (NSImage?) -> Void
    ) {
        self.presetImage = nil
        self.presetSource = nil
        self.suspendedDraft = suspendedDraft
        self.keepsEditorAcrossSpaces = suspendedDraft.keepsEditorAcrossSpaces
        self.postCaptureAction = .edit
        self.triggerContext = nil
        self.snapshotProvider = ScreenSnapshotProvider.shared
        self.windowSnapshotLoader = { WindowDetector.snapshot(primaryScreenArea: $0) }
        self.windowImageLoader = { windowID, pointSize in
            try await ScreenCapturer.captureWindowAsync(
                windowID: windowID,
                pointSize: pointSize
            )
        }
        self.eventTrackingStateProvider = {
            OverlayWindowController.isRunningEventTrackingMode
        }
        self.eventTrackingDismissal = {
            OverlayWindowController.dismissActiveEventTrackingSurface()
        }
        self.colorSamplerActiveProvider = { ColorPickerRunner.shared.isActive }
        self.modalWindowProvider = {
            OverlayWindowController.currentApplicationModalWindow()
        }
        self.modalWindowDismissal = { window in
            OverlayWindowController.abortApplicationModalSession(for: window)
        }
        self.onFirstFramePresented = nil
        self.onRecordingSelection = onRecordingSelection
        self.onRequestFocusReturn = onRequestFocusReturn
        self.onSuspend = onSuspend
        self.onComplete = onComplete
    }

    func activate() {
        guard !presentationScheduled else { return }
        presentationScheduled = true
        triggerContext?.mark(.activateRequested)
        ToastWindow.dismiss()
        beginOverlaySession()
    }

    var isOverlayPresented: Bool {
        !windows.isEmpty && windows.allSatisfy(\.isVisible)
    }

    var isMagnifierLensPanelPresented: Bool {
        magnifierLensPanelActive
    }

    var currentMagnifierLensPanelFormat: MagnifierLensPanelWindow.Format {
        magnifierLensPanelFormat
    }

    var isSelectionInteractive: Bool {
        windows.compactMap { $0.contentView as? SelectionView }
            .contains(where: \.selectionInteractionEnabled)
    }

    var activeSelectionViews: [SelectionView] {
        windows.compactMap { $0.contentView as? SelectionView }
    }

    var isWaitingForSnapshot: Bool { pendingSelection != nil }
    var isWaitingForWindowCapture: Bool { pendingWindowCapture != nil }
    var appliedSnapshotCount: Int { screenSnapshots.count }
    var hasActiveEditor: Bool { editController != nil }
    var isCaptureSessionEnded: Bool { sessionEnded }

    private func beginOverlaySession() {
        presentationGeneration += 1
        let generation = presentationGeneration
        sessionEnded = false
        screenSnapshots.removeAll()
        selectionViewsByDisplayID.removeAll()
        failedSnapshotDisplayIDs.removeAll()
        snapshotCaptureFinished = false
        pendingSelection = nil
        firstFrameReported = false

        let targets = Self.snapshotTargets()
        pendingFocusSensitiveSnapshotDisplayIDs = shouldCaptureSnapshots
            ? WindowDetector.displaysWithFocusSensitiveWindows(in: targets)
            : []
        pendingFocusSensitiveForegroundClaim = !pendingFocusSensitiveSnapshotDisplayIDs.isEmpty
        expectedSnapshotDisplayIDs = Set(targets.map(\.displayID))
        firstFrameTargetDisplayID = Self.displayIDUnderPointer()
            ?? targets.first?.displayID
        let presentationBlocker = activePresentationBlocker()
        deferredPresentationBlocker = shouldCaptureSnapshots
            ? presentationBlocker
            : nil
        triggerContext?.mark(.backgroundPreparationStarted)

        if shouldCaptureSnapshots {
            for screen in NSScreen.screens {
                guard let displayID = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? CGDirectDisplayID else { continue }
                preparedOverlayPanels[displayID] = OverlayPanelPool.shared.lease(for: screen)
            }
        }
        // Register every capture-only window with ScreenCaptureKit before its
        // asynchronous snapshot starts. The HUD is shown immediately afterward,
        // so sharingType alone cannot keep it out of the in-flight screenshot.
        if shouldCaptureSnapshots {
            if shouldShowMagnifierLensPanel {
                magnifierLensPanel = MagnifierLensPanelWindow()
                magnifierLensPanelFormat = .hex
            } else {
                chipWindow = CursorChipWindow(text: currentCursorChipText)
            }
        }
        startWindowEnumeration(generation: generation)
        startSnapshotCapture(targets: targets, generation: generation)
        if let presentationBlocker {
            if !shouldCaptureSnapshots {
                dismissPresentationBlockerIfActive(presentationBlocker)
                scheduleOverlayPresentation(generation: generation)
            }
        } else {
            presentOverlay(generation: generation)
        }
    }

    private func startSnapshotCapture(
        targets: [ScreenSnapshotTarget],
        generation: Int
    ) {
        guard shouldCaptureSnapshots,
              generation == presentationGeneration,
              !sessionEnded else { return }
        triggerContext?.mark(.snapshotCaptureStarted)
        let context = triggerContext
        let deadline = DispatchWorkItem { [weak self] in
            guard let self, self.presentationGeneration == generation,
                  !self.sessionEnded, !self.snapshotCaptureFinished else { return }
            self.snapshotCancellation?()
            self.snapshotCancellation = nil
            self.handleSnapshotEvent(.finished, generation: generation)
        }
        snapshotDeadline = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + snapshotTimeout, execute: deadline)
        let captureChrome = [magnifierLensPanel, chipWindow].compactMap { $0 }
        // Display capture composites every process's windows, and
        // `SCContentFilter`'s exclusion list is the only way to omit them. A
        // *second* BlinkClip instance (installed app + a dev build, or an agent
        // fixture instance) shows its own cursor HUD at a floating-or-above
        // level; without this it is baked into the frozen desktop and the user
        // sees the crosshair/info panel inside the screenshot.
        let twinInstanceChrome = Self.twinInstanceChromeWindowNumbers()
        let excludedWindowIDs = Set((windows + Array(preparedOverlayPanels.values) + captureChrome).compactMap { window in
            window.windowNumber > 0 ? CGWindowID(window.windowNumber) : nil
        }).union(twinInstanceChrome)
        snapshotCancellation = snapshotProvider.capture(targets: targets, excludingWindowIDs: excludedWindowIDs) { [weak self] event in
            context?.mark(.snapshotResultReady)
            MainRunLoopScheduler.perform {
                self?.handleSnapshotEvent(event, generation: generation)
            }
        }
    }

    /// On-screen windows that belong to *another process of this same product*
    /// (same bundle identifier) and sit at a floating-or-above level. Those are
    /// exactly the cursor HUDs / hint chips of a twin instance — never document
    /// content — so they are safe to omit from the frozen desktop.
    private static func twinInstanceChromeWindowNumbers() -> Set<CGWindowID> {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var result: Set<CGWindowID> = []
        for entry in info {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID != ownPID,
                  let number = entry[kCGWindowNumber as String] as? Int, number > 0,
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  layer >= Int(NSWindow.Level.floating.rawValue),
                  NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier == bundleID
            else { continue }
            result.insert(CGWindowID(number))
        }
        return result
    }

    private static func snapshotTargets() -> [ScreenSnapshotTarget] {
        NSScreen.screens.compactMap { screen in
            guard let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID else { return nil }
            return ScreenSnapshotTarget(
                displayID: displayID,
                bounds: CGDisplayBounds(displayID),
                scale: screen.backingScaleFactor
            )
        }
    }

    private var shouldCaptureSnapshots: Bool {
        guard presetImage == nil, suspendedDraft == nil else { return false }
        if case .record = postCaptureAction { return false }
        return true
    }

    private func startWindowEnumeration(generation: Int) {
        guard presetImage == nil,
              suspendedDraft == nil,
              let primaryFrame = NSScreen.screens.first?.frame else { return }
        let primaryScreenArea = primaryFrame.width * primaryFrame.height

        let snapshotLoader = windowSnapshotLoader
        let context = triggerContext
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = snapshotLoader(primaryScreenArea)
            context?.mark(.windowEnumerationReady)
            MainRunLoopScheduler.perform {
                guard let self,
                      generation == self.presentationGeneration,
                      !self.sessionEnded else { return }
                self.triggerContext?.mark(.windowEnumerationApplied)
                switch result {
                case .success(let windows):
                    self.windowDetector.apply(windows)
                    for selectionView in self.selectionViewsByDisplayID.values {
                        selectionView.refreshHoverAtCurrentMouseLocation()
                    }
                case .failure:
                    break
                }
            }
        }
    }

    private func handleSnapshotEvent(_ event: ScreenSnapshotEvent, generation: Int) {
        guard generation == presentationGeneration, !sessionEnded,
              !snapshotCaptureFinished else { return }
        triggerContext?.mark(.snapshotResultApplied)

        switch event {
        case .image(let displayID, let image):
            screenSnapshots[displayID] = image
            if magnifierLensPanel != nil {
                refreshMagnifierLensPanelContent()
            }
            if let selectionView = selectionViewsByDisplayID[displayID] {
                selectionView.setBackgroundSnapshot(
                    cgImage: image,
                    pointSize: selectionView.bounds.size
                )
            }
            focusSensitiveSnapshotResolved(displayID: displayID)
            resumePendingSelectionIfReady(displayID: displayID)
            finishDeferredPresentationIfReady(
                displayID: displayID,
                generation: generation
            )
        case .failure(let displayID, _):
            failedSnapshotDisplayIDs.insert(displayID)
            if pendingSelection?.displayID == displayID {
                finishSelectionCaptureFailure()
            }
            focusSensitiveSnapshotResolved(displayID: displayID)
            finishDeferredPresentationIfReady(
                displayID: displayID,
                generation: generation
            )
        case .finished:
            snapshotDeadline?.cancel()
            snapshotDeadline = nil
            snapshotCaptureFinished = true
            pendingFocusSensitiveSnapshotDisplayIDs.removeAll()
            if let pendingSelection {
                resumePendingSelectionIfReady(displayID: pendingSelection.displayID)
            }
            if let pendingSelection,
               screenSnapshots[pendingSelection.displayID] == nil {
                finishSelectionCaptureFailure()
            }
            finishDeferredPresentationIfReady(
                generation: generation,
                force: true
            )
            claimForegroundAfterFocusSensitiveSnapshotIfNeeded()
        }
    }

    private func finishDeferredPresentationIfReady(
        displayID: CGDirectDisplayID? = nil,
        generation: Int,
        force: Bool = false
    ) {
        guard let presentationBlocker = deferredPresentationBlocker,
              generation == presentationGeneration,
              !sessionEnded else { return }
        if !force,
           let firstFrameTargetDisplayID,
           displayID != firstFrameTargetDisplayID {
            return
        }

        deferredPresentationBlocker = nil
        dismissPresentationBlockerIfActive(presentationBlocker)
        scheduleOverlayPresentation(generation: generation)
    }

    private func activePresentationBlocker() -> PresentationBlocker? {
        if let modalWindow = modalWindowProvider() {
            return .applicationModal(modalWindow)
        }
        if eventTrackingStateProvider() {
            return .eventTracking
        }
        return nil
    }

    private func dismissPresentationBlockerIfActive(_ blocker: PresentationBlocker) {
        switch blocker {
        case .eventTracking:
            if eventTrackingStateProvider() {
                eventTrackingDismissal()
            }
        case .applicationModal(let modalWindow):
            if modalWindowProvider() === modalWindow {
                modalWindowDismissal(modalWindow)
            }
        }
    }

    private func scheduleOverlayPresentation(generation: Int) {
        MainRunLoopScheduler.performInDefaultMode { [weak self] in
            guard let self,
                  generation == self.presentationGeneration,
                  !self.sessionEnded else { return }
            self.presentOverlay(generation: generation)
        }
    }

    private static func currentApplicationModalWindow() -> NSWindow? {
        NSApp.modalWindow
    }

    private static func abortApplicationModalSession(for window: NSWindow) {
        guard NSApp.modalWindow === window else { return }
        NSApp.abortModal()
    }

    private func presentOverlay(generation: Int) {
        guard windows.isEmpty else { return }

        // Cache each screen's AppKit frame so the magnifier lens panel can map a
        // global mouse location onto the matching snapshot's pixel coords.
        screenFramesByDisplayID.removeAll(keepingCapacity: true)
        for screen in NSScreen.screens {
            if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                screenFramesByDisplayID[displayID] = screen.frame
            }
        }

        // The transparent selection shell is deliberately created without
        // waiting for frozen pixels. Until a snapshot arrives, AppKit simply
        // reveals the live desktop through the clear panel.
        for screen in NSScreen.screens {
            let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID
            let window = displayID.flatMap { preparedOverlayPanels.removeValue(forKey: $0) }
                ?? OverlayPanelPool.shared.lease(for: screen)
            let surfacePresentationToken = window.surfacePresentationToken
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.sharingType = OverlayPanelPool.overlaySharingType
            window.acceptsMouseMovedEvents = true
            window.animationBehavior = .none

            let selectionView = SelectionView(frame: screen.frame)
            selectionView.mayActivateAppForCursor = !pendingFocusSensitiveForegroundClaim
            selectionView.delegate = self
            selectionView.windowDetector = windowDetector
            // The pointer guide is a desktop-wide reference: whichever display
            // sees the mouse movement mirrors the screen point into every
            // overlay, so the horizontal line continues over the neighbouring
            // display instead of stopping at this screen's edge.
            selectionView.onCrosshairMoved = { [weak self] screenPoint in
                guard let self else { return }
                for view in self.selectionViewsByDisplayID.values {
                    view.updateCrosshair(globalPoint: screenPoint)
                }
            }
            // The overlay tells the controller when it starts/stops painting the
            // pointer; the controller owns the system cursor's hide/restore.
            selectionView.onPointerCursorDrawnChanged = { [weak self] _ in
                self?.pointerCursorDrawnStateChanged()
            }
            selectionView.aspectRatio = usesAspectRatioSelection ? Self.persistedSelectionAspectRatio : nil
            selectionView.onFirstDrawCompleted = { [weak self] in
                self?.recordFirstDraw(generation: generation)
            }
            selectionView.onFirstFramePresented = { [weak self] in
                guard OverlayPanelPool.shared.markSurfacePresented(
                    window,
                    for: screen,
                    presentationToken: surfacePresentationToken
                ) else { return }
                let displayID = screen.deviceDescription[
                    NSDeviceDescriptionKey("NSScreenNumber")
                ] as? CGDirectDisplayID
                self?.recordFirstFrame(
                    generation: generation,
                    displayID: displayID
                )
            }
            if let draft = suspendedDraft,
               screen == screenForSuspendedDraft(draft),
               let snapshot = draft.preSnapshot {
                // Restore the frozen desktop before presenting the overlay. The
                // editor exports from this same snapshot, not the live windows
                // that may have moved or scrolled while the draft was suspended.
                selectionView.setBackgroundSnapshot(cgImage: snapshot, pointSize: screen.frame.size)
            } else if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let snapshot = screenSnapshots[displayID] {
                selectionView.setBackgroundSnapshot(cgImage: snapshot, pointSize: screen.frame.size)
            }
            window.contentView = selectionView
            window.initialFirstResponder = selectionView

            if let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID {
                selectionViewsByDisplayID[displayID] = selectionView
            }

            windows.append(window)
        }

        // Show all overlay windows in one batch with animations disabled.
        triggerContext?.mark(.overlayInitialized)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for window in windows {
            window.orderFrontRegardless()
        }
        CATransaction.commit()
        triggerContext?.mark(.overlayOrderedFront)

        // Seed the guides at the pointer location the overlay opened at, so the
        // crosshair is there before the first mouse move arrives.
        let pointerAtPresentation = NSEvent.mouseLocation
        for view in selectionViewsByDisplayID.values {
            view.updateCrosshair(globalPoint: pointerAtPresentation)
        }

        if shouldShowMagnifierLensPanel {
            // Lens replaces the drag-to-screenshot hint while the overlay is
            // sitting in the idle state. Chip stays nil so its text doesn't
            // double up with the lens.
            setupMagnifierLensPanel()
        } else {
            if chipWindow == nil {
                chipWindow = CursorChipWindow(text: currentCursorChipText)
            }
            chipWindow?.show()
        }

        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.editController?.handleWindowCaptureWaitKeyDown(event) == true { return nil }
            if self?.editController?.isTextEditing == true {
                return event
            }
            if self?.toggleMagnifierLensPanelFormatFromKeyboard(for: event) == true {
                return nil
            }
            if self?.handleMagnifierLensPanelCopyShortcut(for: event, allowsPlainC: true) == true {
                return nil
            }
            if self?.editController?.confirmCropFromKeyboard(for: event) == true {
                return nil
            }
            if self?.editController?.undoFromKeyboard(for: event) == true {
                return nil
            }
            if self?.editController?.redoFromKeyboard(for: event) == true {
                return nil
            }
            if self?.editController?.handleAnnotationClipboardShortcutFromKeyboard(for: event) == true {
                return nil
            }
            if self?.editController?.nudgeSelectedAnnotationFromKeyboard(for: event) == true {
                return nil
            }
            if self?.editController?.deleteSelectedAnnotationFromKeyboard(for: event) == true {
                return nil
            }
            if self?.switchHistoryImageFromKeyboard(for: event) == true {
                return nil
            }
            if event.keyCode == 53 { // Escape
                if self?.colorSamplerActiveProvider() == true {
                    return event
                }
                self?.cancel()
                return nil
            }
            if self?.cycleSelectionAspectRatioFromKeyboard(for: event) == true {
                return nil
            }
            if HotkeyManager.eventMatchesClipboardHotkey(event) {
                self?.editController?.confirmFromKeyboard()
                return nil
            }
            if HotkeyManager.eventMatchesFileSaveHotkey(event) {
                self?.editController?.saveFromKeyboard()
                return nil
            }
            if self?.editController?.handleEditorShortcutFromKeyboard(for: event) == true {
                return nil
            }
            return event
        }
        leftMouseLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if self?.editController?.isWaitingForWindowCaptureOutput == true { return event }
            guard self?.editController?.handleCanvasConfirmDoubleClick(event) == true else {
                return event
            }
            self?.editController?.confirmFromKeyboard()
            return nil
        }
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.editController?.isTextEditing == true {
                return
            }
            if event.keyCode == 53 {
                guard self?.colorSamplerActiveProvider() != true else { return }
                self?.cancel()
            }
        }
        // The overlay is a non-activating panel, so keyboard events routed
        // to the foreground app never reach our local monitor. Mirror the
        // legacy ⌘+C handling with a global monitor so it still fires when
        // another app is focused underneath.
        magnifierLensPanelKeyDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleMagnifierLensPanelCopyShortcut(for: event, allowsPlainC: false)
        }
        mouseMovedLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.refreshMagnifierLensPanelContent()
            return event
        }
        mouseMovedGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.refreshMagnifierLensPanelContent()
        }
        rightMouseLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            if self?.editController?.isTextEditing == true {
                return event
            }
            self?.cancel()
            return nil
        }
        rightMouseGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            if self?.editController?.isTextEditing == true {
                return
            }
            self?.cancel()
        }

        if presetImage == nil, suspendedDraft == nil {
            NSCursor.crosshair.push()
            cursorWasPushed = true
            installActivationObserverIfNeeded()
            if !pendingFocusSensitiveForegroundClaim || pendingFocusSensitiveSnapshotDisplayIDs.isEmpty {
                claimSelectionForeground()
            }
        } else {
            // Skip cursor push so tearDown's pop doesn't strip an unrelated cursor.
            cursorPopped = true
            // The chip is a "drag to select" hint — irrelevant in image-edit mode.
            chipWindow?.dismiss()
            chipWindow = nil
            if suspendedDraft != nil {
                enterSuspendedSelection()
            } else {
                enterPresetSelection()
            }
        }
    }

    private func claimForegroundAfterFocusSensitiveSnapshotIfNeeded() {
        guard pendingFocusSensitiveForegroundClaim, pendingFocusSensitiveSnapshotDisplayIDs.isEmpty,
              !windows.isEmpty else { return }
        pendingFocusSensitiveForegroundClaim = false
        guard !sessionEnded, editController == nil, pendingSelection == nil,
              cursorWasPushed, !cursorPopped else { return }
        claimSelectionForeground()
    }

    private func focusSensitiveSnapshotResolved(displayID: CGDirectDisplayID) {
        guard pendingFocusSensitiveSnapshotDisplayIDs.remove(displayID) != nil,
              pendingFocusSensitiveSnapshotDisplayIDs.isEmpty else { return }
        if let pendingSelection {
            resumePendingSelectionIfReady(displayID: pendingSelection.displayID)
        }
        claimForegroundAfterFocusSensitiveSnapshotIfNeeded()
    }

    private func claimSelectionForeground() {
        pendingFocusSensitiveForegroundClaim = false
        pendingFocusSensitiveSnapshotDisplayIDs.removeAll()
        activeSelectionViews.forEach { $0.mayActivateAppForCursor = true }
        claimSelectionKeyboardFocus()
        refreshSelectionCursor()
        NSCursor.crosshair.set()
        NSApp.activate(ignoringOtherApps: true)
        // `NSCursor.hide()` only takes effect while this app owns the foreground,
        // so the self-drawn pointer starts here, after the activation — and once
        // more on the next run-loop turn in case the activation is still landing.
        beginSelfDrawnPointer()
        DispatchQueue.main.async { [weak self] in
            self?.beginSelfDrawnPointer()
        }
    }

    /// Make the nonactivating selection panel own key events before capcap is
    /// activated for cursor ownership. This prevents a previously focused text
    /// field from receiving capture shortcuts such as R.
    private func claimSelectionKeyboardFocus() {
        let targetView = firstFrameTargetDisplayID
            .flatMap { selectionViewsByDisplayID[$0] }
            ?? activeSelectionViews.first
        guard let targetView, let targetWindow = targetView.window else { return }
        targetWindow.makeKeyAndOrderFront(nil)
        targetWindow.makeFirstResponder(targetView)
    }

    /// Refresh the selection cursor after capcap claims activation.
    ///
    /// AppKit cursor APIs are ignored while another app is frontmost. Once
    /// presentOverlay activates capcap, invalidating cursor rects lets
    /// WindowServer re-evaluate the full-view crosshair rect registered by
    /// SelectionView.resetCursorRects.
    private func refreshSelectionCursor() {
        activeSelectionViews.forEach { $0.refreshCursorRects() }
    }

    private func recordFirstDraw(generation: Int) {
        guard generation == presentationGeneration, !sessionEnded else { return }
        triggerContext?.mark(.firstDrawCompleted)
    }

    private func recordFirstFrame(
        generation: Int,
        displayID: CGDirectDisplayID?
    ) {
        guard generation == presentationGeneration,
              !sessionEnded,
              !firstFrameReported,
              firstFrameTargetDisplayID == nil
                || displayID == firstFrameTargetDisplayID else { return }
        firstFrameReported = true
        triggerContext?.mark(.firstFrame)
        triggerContext?.finish(.presented)
        onFirstFramePresented?()
    }

    private static func displayIDUnderPointer() -> CGDirectDisplayID? {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        return screen?.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID
    }

    private static var isRunningEventTrackingMode: Bool {
        guard let mode = CFRunLoopCopyCurrentMode(CFRunLoopGetMain()) else {
            return false
        }
        return mode.rawValue as String == RunLoop.Mode.eventTracking.rawValue
    }

    private static func dismissActiveEventTrackingSurface() {
        NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: nil)

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)
        keyDown?.flags = []
        keyUp?.flags = []
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static var persistedSelectionAspectRatio: CGFloat? {
        guard Defaults.hasSelectionAspectRatio else { return nil }
        let ratio = Defaults.selectionAspectRatio
        guard ratio > 0, ratio.isFinite else { return nil }
        return CGFloat(ratio)
    }

    private var currentCursorChipText: String {
        if usesAspectRatioSelection {
            return Self.aspectRatioCursorChipText(
                for: postCaptureAction,
                aspectRatio: Self.persistedSelectionAspectRatio
            )
        }
        return postCaptureAction.cursorChipText
    }

    private var usesAspectRatioSelection: Bool {
        guard presetImage == nil, suspendedDraft == nil else { return false }
        switch postCaptureAction {
        case .edit, .record:
            return true
        case .quickPin, .textRecognition, .copyImageText, .screenshotTranslation:
            return false
        }
    }

    private static func aspectRatioCursorChipText(for action: PostCaptureAction, aspectRatio: CGFloat?) -> String {
        switch action {
        case .edit:
            guard let aspectRatio else { return L10n.dragToScreenshotAspectFree }
            return L10n.dragToScreenshotAspect(aspectRatioLabel(for: aspectRatio))
        case .quickPin:
            return action.cursorChipText
        case .record:
            guard let aspectRatio else { return L10n.dragToRecordAspectFree }
            return L10n.dragToRecordAspect(aspectRatioLabel(for: aspectRatio))
        case .textRecognition, .copyImageText, .screenshotTranslation:
            return action.cursorChipText
        }
    }

    private static func aspectRatioLabel(for aspectRatio: CGFloat) -> String {
        let presets: [(CGFloat, String)] = [
            (1.0, "1:1"),
            (2.35, "2.35:1"),
            (3.0, "3:1"),
            (3.0 / 2.0, "3:2"),
            (4.0 / 3.0, "4:3"),
            (9.0 / 16.0, "9:16"),
            (16.0 / 9.0, "16:9"),
        ]
        if let preset = presets.first(where: { abs($0.0 - aspectRatio) < 0.000_001 }) {
            return preset.1
        }
        return String(format: "%.2f:1", Double(aspectRatio))
    }

    private func cycleSelectionAspectRatioFromKeyboard(for event: NSEvent) -> Bool {
        guard usesAspectRatioSelection else { return false }
        guard editController == nil, event.keyCode == 15 else { return false }
        let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(modifierMask).isEmpty else { return false }

        let presets = Defaults.selectionAspectRatioPresets
        let currentModeIndex: Int
        if Defaults.hasSelectionAspectRatio {
            let currentRatio = CGFloat(Defaults.selectionAspectRatio)
            let presetIndex = presets.firstIndex { abs($0 - currentRatio) < 0.000_001 }
            currentModeIndex = presetIndex.map { $0 + 1 } ?? 0
        } else {
            currentModeIndex = 0
        }

        let nextModeIndex = (currentModeIndex + 1) % (presets.count + 1)
        let nextAspectRatio: CGFloat?
        if nextModeIndex == 0 {
            Defaults.clearSelectionAspectRatio()
            nextAspectRatio = nil
        } else {
            let ratio = presets[nextModeIndex - 1]
            Defaults.selectionAspectRatio = Double(ratio)
            nextAspectRatio = ratio
        }
        applySelectionAspectRatio(nextAspectRatio)
        if usesAspectRatioSelection {
            chipWindow?.updateText(Self.aspectRatioCursorChipText(for: postCaptureAction, aspectRatio: nextAspectRatio))
            magnifierLensPanel?.refreshDisplay()
        }
        return true
    }

    private func applySelectionAspectRatio(_ aspectRatio: CGFloat?) {
        for case let selectionView as SelectionView in windows.compactMap(\.contentView) {
            selectionView.aspectRatio = aspectRatio
        }
        activeSelectionView?.aspectRatio = aspectRatio
    }

    /// Image-edit mode: pick the screen under the cursor, place a centered
    /// selection sized to the supplied image, lock interaction, and hand off
    /// to the editor.
    private func enterPresetSelection() {
        guard let presetImage else { return }
        let cursorPoint = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(cursorPoint) })
            ?? NSScreen.screens.first
        guard let screen = targetScreen else { return }
        guard let window = windows.first(where: { $0.screen == screen }),
              let selectionView = window.contentView as? SelectionView else { return }

        let displayMetrics = Self.displayMetrics(for: presetImage.size, on: screen)
        let imageSize = displayMetrics.viewportSize
        let visibleRect = Self.visibleRectInSelectionView(for: screen)
        let centeredOrigin = NSPoint(
            x: visibleRect.midX - imageSize.width / 2,
            y: visibleRect.midY - imageSize.height / 2
        )
        let viewRect = NSRect(origin: centeredOrigin, size: imageSize)

        selectionView.updateSelectionRect(viewRect)
        selectionView.selectionSizeLabelOverride = Self.scaleLabelText(
            imageSize: presetImage.size,
            displaySize: displayMetrics.canvasSize
        )
        // Keep clicks outside the image from starting a new selection. For a
        // fixed image the existing frame remains adjustable, and its original
        // bounds cap how far crop handles can reveal content.
        selectionView.selectionLocked = true
        selectionView.selectionInteractionEnabled = true
        selectionView.selectionAdjustmentBounds = viewRect

        // Drive the same path as a real selection completion. The captureRect
        // is irrelevant because the editor uses overrideBaseImage, but we
        // pass a sensible value derived from the selection rect.
        selectionDidComplete(rect: viewRect, inView: selectionView, isWindowSelection: false, windowID: nil)

        // Pin a hint to the center of the loaded image: X exits editing.
        let anchorRect = convertToScreenRect(viewRect, view: selectionView)
        let hint: String
        switch presetSource {
        case .clipboard:
            hint = L10n.clipboardEditExitHint
        case .pin:
            hint = L10n.pinEditExitHint
        case .fullScreen:
            hint = L10n.fullScreenEditExitHint
        case .merge:
            hint = L10n.mergeEditExitHint
        case .finder, nil:
            hint = L10n.finderEditExitHint
        }
        ToastWindow.show(
            message: hint,
            centerAnchor: NSPoint(x: anchorRect.midX, y: anchorRect.midY),
            duration: 3.0
        )
    }

    private func enterSuspendedSelection() {
        guard let suspendedDraft else { return }
        let screen = screenForSuspendedDraft(suspendedDraft)
        guard let window = windows.first(where: { $0.screen == screen }),
              let selectionView = window.contentView as? SelectionView
        else { return }

        for existingWindow in windows where existingWindow != window {
            existingWindow.orderOut(nil)
        }

        selectionView.updateSelectionRect(suspendedDraft.selectionViewRect)
        selectionView.selectionSizeLabelOverride = suspendedDraft.selectionSizeLabelOverride
        selectionView.selectionLocked = suspendedDraft.selectionLocked
        selectionView.selectionInteractionEnabled = suspendedDraft.selectionInteractionEnabled
        selectionView.selectionAdjustmentBounds = suspendedDraft.selectionAdjustmentBounds

        activeSelectionView = selectionView
        activeScreen = screen

        showEditor(
            captureRect: suspendedDraft.captureRect,
            screen: screen,
            selectionRect: suspendedDraft.selectionRect,
            selectionViewRect: suspendedDraft.selectionViewRect,
            hostSelectionView: selectionView,
            preSnapshot: suspendedDraft.preSnapshot,
            overrideBaseImage: suspendedDraft.overrideBaseImage,
            windowBaseImage: suspendedDraft.windowBaseImage,
            isWindowCapture: suspendedDraft.isWindowCapture
        )
        editController?.restoreState(suspendedDraft.editorState)

        let anchorRect = convertToScreenRect(suspendedDraft.selectionViewRect, view: selectionView)
        ToastWindow.show(
            message: L10n.editSuspendedResumeToast,
            centerAnchor: NSPoint(x: anchorRect.midX, y: anchorRect.midY),
            duration: 3.0
        )
    }

    private func screenForSuspendedDraft(_ draft: SuspendedEditDraft) -> NSScreen {
        if let displayID = draft.screenDisplayID,
           let screen = NSScreen.screens.first(where: {
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
           }) {
            return screen
        }
        if let screen = NSScreen.screens.first(where: { $0.frame == draft.screenFrame }) {
            return screen
        }
        return screenForMouseLocation() ?? NSScreen.main ?? NSScreen.screens.first!
    }

    private func screenForMouseLocation() -> NSScreen? {
        let cursorPoint = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(cursorPoint) })
    }

    private static func scaleLabelText(imageSize: NSSize, displaySize: NSSize) -> String? {
        guard imageSize.width > 0, imageSize.height > 0,
              displaySize.width > 0, displaySize.height > 0
        else {
            return nil
        }
        let ratio = min(displaySize.width / imageSize.width, displaySize.height / imageSize.height)
        let width = Int(round(imageSize.width))
        let height = Int(round(imageSize.height))
        guard ratio < 0.999 else {
            return "\(width) × \(height)"
        }
        let percent = max(1, Int(round(ratio * 100)))
        return "\(width) × \(height) (\(percent)%)"
    }

    private struct PresetDisplayMetrics {
        let viewportSize: NSSize
        let canvasSize: NSSize
    }

    private static func displayMetrics(for imageSize: NSSize, on screen: NSScreen) -> PresetDisplayMetrics {
        let frame = screen.visibleFrame
        let maxWidthFraction: CGFloat = 0.70
        let verticalMargin: CGFloat = 120 // leave room for toolbar above/below

        guard imageSize.width > 0, imageSize.height > 0 else {
            return PresetDisplayMetrics(viewportSize: imageSize, canvasSize: imageSize)
        }
        let maxWidth = max(1, floor(frame.width * maxWidthFraction))
        let maxViewportHeight = max(1, floor(frame.height - verticalMargin))
        let ratio = min(1.0, maxWidth / imageSize.width)
        let canvasSize = NSSize(
            width: max(1, floor(imageSize.width * ratio)),
            height: max(1, floor(imageSize.height * ratio))
        )
        let viewportSize = NSSize(
            width: canvasSize.width,
            height: min(canvasSize.height, maxViewportHeight)
        )
        return PresetDisplayMetrics(viewportSize: viewportSize, canvasSize: canvasSize)
    }

    private static func visibleRectInSelectionView(for screen: NSScreen) -> NSRect {
        let screenFrame = screen.frame
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.minX - screenFrame.minX,
            y: visible.minY - screenFrame.minY,
            width: visible.width,
            height: visible.height
        )
    }

    func cancel() {
        if editController?.cancelWindowCaptureOutput() == true { return }
        guard !sessionEnded else { return }
        triggerContext?.finish(.cancelled)
        editController?.tearDown()
        editController = nil
        tearDown()
        onComplete(nil)
        onRequestFocusReturn?()
    }

    private func suspendCurrentEditFromMask() {
        guard let draft = makeSuspendedEditDraft() else { return }
        editController?.tearDown()
        editController = nil
        tearDown()
        onRequestFocusReturn?()
        onSuspend?(draft)
    }

    private func makeSuspendedEditDraft() -> SuspendedEditDraft? {
        guard let editController,
              !editController.blocksHistoryNavigation,
              let context = activeEditorContext,
              let editorState = editController.restorableState()
        else { return nil }

        let selectionViewState = context.hostSelectionView.map { SelectionViewState(selectionView: $0) }
            ?? context.selectionViewState
        let displayID = context.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        return SuspendedEditDraft(
            captureRect: editorState.captureRect,
            screenDisplayID: displayID,
            screenFrame: context.screen.frame,
            selectionRect: editorState.selectionRect,
            selectionViewRect: editorState.selectionViewRect,
            selectionSizeLabelOverride: selectionViewState.selectionSizeLabelOverride,
            selectionLocked: selectionViewState.selectionLocked,
            selectionInteractionEnabled: selectionViewState.selectionInteractionEnabled,
            selectionAdjustmentBounds: selectionViewState.selectionAdjustmentBounds,
            preSnapshot: context.preSnapshot,
            overrideBaseImage: editorState.overrideBaseImage,
            windowBaseImage: context.windowBaseImage,
            isWindowCapture: editController.isWindowCapture,
            editorState: editorState,
            keepsEditorAcrossSpaces: keepsEditorAcrossSpaces
        )
    }

    private var cursorPopped = false
    private var cursorWasPushed = false
    /// Owns this session's single system-cursor hide. The overlay paints the
    /// pointer itself while it is hidden, so pointer and guides share one layer
    /// update instead of the guides trailing the hardware cursor.
    private var systemCursor: SystemCursorHider = SystemCursorHider()
    /// One unconfirmed hide (or one lost activation) is enough: this session
    /// then keeps the system cursor and draws the guides only, so the user never
    /// sees two pointers.
    private var suppressesSelfDrawnPointer = false
    private var isUpdatingPointerCursor = false
    private var pendingSystemCursorRestore: DispatchWorkItem?
    private var activationObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?
    private var windowCloseObserver: NSObjectProtocol?

    deinit {
        // Last-resort net: a controller that dies without `tearDown` must not
        // leave the user without a cursor.
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
        }
        systemCursor.restore()
    }

    // MARK: - Self-drawn pointer

    /// Starts painting the pointer inside the overlays. The system cursor is
    /// hidden *first*: if the hide cannot be confirmed, nothing is drawn and this
    /// session stays on the system cursor plus guides.
    private func beginSelfDrawnPointer() {
        guard !suppressesSelfDrawnPointer, !isUpdatingPointerCursor else { return }
        guard systemCursor.hide() else {
            // No confirmed hide: keep the system cursor and the guides only, so
            // the user never sees two pointers. The hider bounds its own retries
            // (a first attempt can lose to the activation still landing).
            activeSelectionViews.forEach { $0.drawsPointerCursor = false }
            return
        }
        activeSelectionViews.forEach { $0.drawsPointerCursor = true }
    }

    /// One overlay started or stopped painting the pointer. Only state changes
    /// reach this — never pointer motion — so the hide/show pair never sits on
    /// the per-event path.
    private func pointerCursorDrawnStateChanged() {
        guard !sessionEnded, !suppressesSelfDrawnPointer, !isUpdatingPointerCursor else { return }
        isUpdatingPointerCursor = true
        defer { isUpdatingPointerCursor = false }

        let drawsItsOwnPointer = activeSelectionViews.contains(where: \.isDrawingPointerCursor)
        guard drawsItsOwnPointer else {
            // A pointer crossing displays hides one overlay and reveals the next
            // in the same event batch; restoring on the next run-loop turn keeps
            // that from turning into a visible show/hide/show flicker.
            scheduleSystemCursorRestore()
            return
        }
        cancelPendingSystemCursorRestore()
        guard !systemCursor.isHidden else { return }
        _ = systemCursor.hide()
    }

    private func scheduleSystemCursorRestore() {
        guard systemCursor.isHidden else { return }
        cancelPendingSystemCursorRestore()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingSystemCursorRestore = nil
            guard !self.activeSelectionViews.contains(where: \.isDrawingPointerCursor) else { return }
            self.systemCursor.restore()
        }
        pendingSystemCursorRestore = item
        DispatchQueue.main.async(execute: item)
    }

    private func cancelPendingSystemCursorRestore() {
        pendingSystemCursorRestore?.cancel()
        pendingSystemCursorRestore = nil
    }

    /// Ends the self-drawn pointer: the system cursor comes back and no overlay
    /// paints a pointer any more. Idempotent; called from every exit path. A
    /// watchdog is always armed afterwards: if the unhide was dropped (the app
    /// was in the background) or never happened, it forces the cursor back.
    private func restoreSystemCursorNow() {
        cancelPendingSystemCursorRestore()
        let wasHidden = systemCursor.isHidden
        activeSelectionViews.forEach { $0.drawsPointerCursor = false }
        systemCursor.restore()
        systemCursor.scheduleRestoreWatchdog()
        if wasHidden {
            NSLog("%@", "BlinkClip: system cursor restored after the selection overlay")
        }
    }

    /// A capture overlay that loses activation can still be on screen (snapshot
    /// or window-capture wait, editor hand-off). Whatever the user does next must
    /// have a visible cursor, so this session falls back to guides only. The
    /// unhide is usually deferred to the next activation (AppKit drops cursor
    /// calls from a background app), so the watchdog is the second net.
    private func handleApplicationWillResignActive() {
        guard !sessionEnded else { return }
        guard systemCursor.isHidden || activeSelectionViews.contains(where: \.drawsPointerCursor) else {
            return
        }
        suppressesSelfDrawnPointer = true
        cancelPendingSystemCursorRestore()
        activeSelectionViews.forEach { $0.drawsPointerCursor = false }
        systemCursor.restore()
        systemCursor.scheduleRestoreWatchdog()
        NSLog("%@", "BlinkClip: overlay lost activation; restored the system cursor and stopped drawing the pointer")
    }

    /// `NSApp` is terminating: no run loop is left for the watchdog, so the
    /// cursor is forced back synchronously.
    private func handleApplicationWillTerminate() {
        cancelPendingSystemCursorRestore()
        activeSelectionViews.forEach { $0.drawsPointerCursor = false }
        systemCursor.forceRestoreForTermination()
    }

    /// One of this session's surfaces went away without the normal exit path.
    /// The user must not be left without a cursor: restore now and let the
    /// watchdog prove it took effect.
    private func handleOverlayWindowWillClose(_ window: NSWindow) {
        guard !sessionEnded, windows.contains(where: { $0 === window }) else { return }
        restoreSystemCursorNow()
    }

    private func installActivationObserverIfNeeded() {
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleApplicationWillResignActive()
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleApplicationWillTerminate()
        }
        windowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            self?.handleOverlayWindowWillClose(window)
        }
    }

    private func tearDown() {
        guard !sessionEnded else { return }
        sessionEnded = true
        presentationGeneration += 1
        snapshotCancellation?()
        snapshotCancellation = nil
        snapshotDeadline?.cancel()
        snapshotDeadline = nil
        windowCaptureTask?.cancel()
        windowCaptureTask = nil
        windowPrefetchTask?.cancel()
        windowPrefetchTask = nil
        prefetchedWindow = nil
        pendingWindowCapture = nil
        pendingSelection = nil
        ToastWindow.dismiss()

        if cursorWasPushed, !cursorPopped {
            NSCursor.pop()
            cursorPopped = true
        }
        cursorWasPushed = false
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        if let windowCloseObserver {
            NotificationCenter.default.removeObserver(windowCloseObserver)
            self.windowCloseObserver = nil
        }
        // The selection is over (or the session failed): the user gets the
        // system cursor back before anything else happens, and a watchdog is
        // armed to prove it (the unhide can be dropped while the app is in the
        // background, and this is the last exit path that can catch it).
        restoreSystemCursorNow()

        chipWindow?.dismiss()
        chipWindow = nil

        magnifierLensPanel?.dismiss()
        magnifierLensPanel = nil
        magnifierLensPanelFormat = .hex

        if let m = escLocalMonitor { NSEvent.removeMonitor(m); escLocalMonitor = nil }
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m); escGlobalMonitor = nil }
        if let m = magnifierLensPanelKeyDownGlobalMonitor { NSEvent.removeMonitor(m); magnifierLensPanelKeyDownGlobalMonitor = nil }
        if let m = mouseMovedLocalMonitor { NSEvent.removeMonitor(m); mouseMovedLocalMonitor = nil }
        if let m = mouseMovedGlobalMonitor { NSEvent.removeMonitor(m); mouseMovedGlobalMonitor = nil }
        if let m = leftMouseLocalMonitor { NSEvent.removeMonitor(m); leftMouseLocalMonitor = nil }
        if let m = rightMouseLocalMonitor { NSEvent.removeMonitor(m); rightMouseLocalMonitor = nil }
        if let m = rightMouseGlobalMonitor { NSEvent.removeMonitor(m); rightMouseGlobalMonitor = nil }

        for window in windows {
            (window.contentView as? SelectionView)?.cancelFirstFramePresentationTracking()
            OverlayPanelPool.shared.recycle(window)
        }
        windows.removeAll()
        preparedOverlayPanels.values.forEach { OverlayPanelPool.shared.recycle($0) }
        preparedOverlayPanels.removeAll()
        screenSnapshots.removeAll()
        selectionViewsByDisplayID.removeAll()
        expectedSnapshotDisplayIDs.removeAll()
        failedSnapshotDisplayIDs.removeAll()
        snapshotCaptureFinished = false
        pendingFocusSensitiveForegroundClaim = false
        pendingFocusSensitiveSnapshotDisplayIDs.removeAll()
        deferredPresentationBlocker = nil
        firstFrameTargetDisplayID = nil
        activeSelectionView = nil
        activeScreen = nil
        activeEditorContext = nil
        currentEditHistoryDraft = nil
        historyEditorDrafts.removeAll()
        historyEntries.removeAll()
        historyEntryIndex = nil
    }

    // MARK: - Coordinate Conversion

    private func convertToScreenRect(_ viewRect: NSRect, view: NSView) -> NSRect {
        guard let window = view.window else { return viewRect }
        return window.convertToScreen(view.convert(viewRect, to: nil))
    }

    private func convertToCGRect(_ screenRect: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens[0].frame.height
        return CGRect(
            x: screenRect.origin.x,
            y: primaryHeight - screenRect.origin.y - screenRect.height,
            width: screenRect.width,
            height: screenRect.height
        )
    }

    // MARK: - Magnifier lens panel

    private var shouldShowMagnifierLensPanel: Bool {
        guard presetImage == nil,
              suspendedDraft == nil else { return false }
        return postCaptureAction == .edit || postCaptureAction == .quickPin
    }

    private func setupMagnifierLensPanel() {
        if magnifierLensPanel == nil {
            magnifierLensPanel = MagnifierLensPanelWindow()
            magnifierLensPanelFormat = .hex
        }
        magnifierLensPanel?.show()
        refreshMagnifierLensPanelContent()
    }

    private func refreshMagnifierLensPanelContent() {
        guard let lens = magnifierLensPanel else { return }
        let mouseLocation = NSEvent.mouseLocation
        // CGRect.contains uses a half-open [min, max) interval so a cursor
        // sitting on the top or right screen edge is treated as outside.
        // Use an inclusive test instead so the lens still resolves a
        // snapshot at extreme boundaries.
        guard let screen = NSScreen.screens.first(where: { screen in
            let f = screen.frame
            return mouseLocation.x >= f.minX && mouseLocation.x <= f.maxX
                && mouseLocation.y >= f.minY && mouseLocation.y <= f.maxY
        }),
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let snapshot = screenSnapshots[displayID],
              let screenFrame = screenFramesByDisplayID[displayID] else {
            lens.update(snapshot: nil, screenFrame: .zero, mouseLocation: mouseLocation, format: magnifierLensPanelFormat)
            return
        }
        lens.update(
            snapshot: snapshot,
            screenFrame: screenFrame,
            mouseLocation: mouseLocation,
            format: magnifierLensPanelFormat
        )
    }

    private func toggleMagnifierLensPanelFormatFromKeyboard(for event: NSEvent) -> Bool {
        guard magnifierLensPanelActive else { return false }
        guard event.keyCode == 3 else { return false } // kVK_ANSI_F
        let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        guard event.modifierFlags.intersection(modifierMask).isEmpty else { return false }
        if !event.isARepeat {
            toggleMagnifierLensPanelFormat()
        }
        return true
    }

    private func toggleMagnifierLensPanelFormat() {
        magnifierLensPanelFormat = (magnifierLensPanelFormat == .hex) ? .rgb : .hex
        magnifierLensPanel?.setFormat(magnifierLensPanelFormat)
    }

    /// Returns `true` when the event represents C (locally) or legacy ⌘+C.
    /// Plain C is never claimed from the global monitor because that would also
    /// type into whichever source app remains active beneath the overlay.
    private func handleMagnifierLensPanelCopyShortcut(
        for event: NSEvent,
        allowsPlainC: Bool
    ) -> Bool {
        guard magnifierLensPanelActive else { return false }
        guard event.keyCode == 8 else { return false } // kVK_ANSI_C
        let mods = event.modifierFlags.intersection([.command, .option, .control])
        let isLegacyCommandC = mods == .command
        let isPlainC = allowsPlainC
            && mods.isEmpty
            && !event.modifierFlags.contains(.shift)
        guard isPlainC || isLegacyCommandC else { return false }
        guard let lens = magnifierLensPanel, let sample = lens.currentSample else { return false }
        copyMagnifierLensPanelColor(sample)
        return true
    }

    private func copyMagnifierLensPanelColor(_ sample: MagnifierLensPanelWindow.Sample) {
        let hex = String(format: "#%02X%02X%02X", sample.r, sample.g, sample.b)
        let rgb = L10n.magnifierLensPanelRgbString(r: sample.r, g: sample.g, b: sample.b)
        let value: String
        switch magnifierLensPanelFormat {
        case .hex:
            value = hex
            ClipboardManager.copyColorToClipboard(hex: hex)
        case .rgb:
            value = rgb
            ClipboardManager.copyToClipboard(text: rgb, skipHistory: true)
        }
        if Defaults.historyCacheEnabled {
            HistoryManager.shared.addColor(hex: hex)
            Defaults.lastPickedColorHex = hex
        }
        let toastScreen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        ToastWindow.show(message: L10n.colorCopied(value), on: toastScreen)
    }
}

// MARK: - SelectionViewDelegate

extension OverlayWindowController: SelectionViewDelegate {
    func selectionDidHoverWindow(_ window: DetectedWindow?) {
        guard editController == nil, pendingWindowCapture == nil, !sessionEnded else { return }
        if prefetchedWindow?.windowID == window?.windowID,
           prefetchedWindow?.frame == window?.frame { return }
        windowPrefetchTask?.cancel()
        windowPrefetchTask = nil
        prefetchedWindow = nil
        guard let window, !window.usesCompositedScreenBackdrop else { return }
        // The common display-filling case never uses independent alpha.
        if NSScreen.screens.contains(where: { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            let bounds = CGDisplayBounds(displayID)
            return bounds.contains(window.frame)
                && !WindowEffects.shouldBorrowDirectWindowAlpha(captureRect: window.frame, displayBounds: bounds)
        }) { return }
        prefetchedWindow = window
        windowPrefetchTask = WindowCapturePreparation.capture(
            windowID: window.windowID,
            pointSize: window.frame.size,
            timeout: windowCaptureTimeout,
            loader: windowImageLoader,
            debounce: true
        )
    }

    private func takeWindowCaptureTask(windowID: CGWindowID, request: PendingSelection) -> Task<NSImage?, Never> {
        if prefetchedWindow?.windowID == windowID,
           prefetchedWindow?.frame == request.captureRect,
           let task = windowPrefetchTask {
            windowPrefetchTask = nil
            prefetchedWindow = nil
            return task
        }
        windowPrefetchTask?.cancel()
        windowPrefetchTask = nil
        prefetchedWindow = nil
        return WindowCapturePreparation.capture(
            windowID: windowID,
            pointSize: request.rect.size,
            timeout: windowCaptureTimeout,
            loader: windowImageLoader
        )
    }

    func selectionDidStart(reason: SelectionStartReason) {
        chipWindow?.dismiss()
        chipWindow = nil
        // The magnifier belongs to the initial selection gesture only. Once a
        // selection exists, resizing or moving it should preserve the frame's
        // own cursor affordances instead of restoring the startup lens.
        if reason == .newSelection,
           magnifierLensPanel == nil,
           shouldShowMagnifierLensPanel {
            setupMagnifierLensPanel()
        }
    }

    func selectionMaskDidDoubleClick(inView view: NSView) {
        suspendCurrentEditFromMask()
    }

    func selectionDidDoubleClickInsideSelection(inView view: NSView) {
        confirmFromKeyboard()
    }

    func selectionDidComplete(rect: NSRect, inView view: NSView, isWindowSelection: Bool, windowID: CGWindowID?) {
        // Selection is done — the lens has served its purpose during drag.
        magnifierLensPanel?.dismiss()
        magnifierLensPanel = nil

        guard let window = view.window, let screen = window.screen else {
            cancel()
            return
        }

        guard let selectionView = view as? SelectionView else {
            cancel()
            return
        }
        activeSelectionView = selectionView
        activeScreen = screen

        let screenRect = convertToScreenRect(rect, view: view)
        let cgRect = convertToCGRect(screenRect)

        if editController != nil {
            // Selection was adjusted — it no longer matches the clicked
            // window's bounds, so window-only effects no longer apply.
            historyEntryIndex = nil
            currentEditHistoryDraft = nil
            historyEditorDrafts.removeAll()
            editController?.isWindowCapture = false
            editController?.updateLayout(
                selectionRect: screenRect,
                selectionViewRect: rect,
                captureRect: cgRect
            )
            return
        }

        guard !sessionEnded else { return }
        lockSelectionForCompletion(activeWindow: window)

        guard let displayID = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")
        ] as? CGDirectDisplayID else {
            finishSelectionCaptureFailure()
            return
        }

        let request = PendingSelection(
            rect: rect,
            screenRect: screenRect,
            captureRect: cgRect,
            screen: screen,
            selectionView: selectionView,
            displayID: displayID,
            isWindowSelection: isWindowSelection,
            windowID: windowID
        )

        guard shouldCaptureSnapshots else {
            completeInitialSelection(request, preSnapshot: nil)
            return
        }
        if let snapshot = screenSnapshots[displayID],
           pendingFocusSensitiveSnapshotDisplayIDs.isEmpty {
            completeInitialSelection(request, preSnapshot: snapshot)
            return
        }
        guard expectedSnapshotDisplayIDs.contains(displayID),
              !failedSnapshotDisplayIDs.contains(displayID),
              !snapshotCaptureFinished else {
            finishSelectionCaptureFailure()
            return
        }

        selectionView.selectionInteractionEnabled = false
        pendingSelection = request
    }

    private func lockSelectionForCompletion(activeWindow: NSWindow) {
        for case let selectionView as SelectionView in windows.compactMap(\.contentView) {
            selectionView.selectionLocked = true
        }
        for existingWindow in windows where existingWindow != activeWindow {
            existingWindow.orderOut(nil)
        }
        if cursorWasPushed, !cursorPopped {
            NSCursor.pop()
            cursorPopped = true
        }
        // The frame is committed: from here on the editor (or the snapshot /
        // window-capture wait) needs a real, visible pointer.
        restoreSystemCursorNow()
    }

    private func resumePendingSelectionIfReady(displayID: CGDirectDisplayID) {
        guard pendingFocusSensitiveSnapshotDisplayIDs.isEmpty else { return }
        guard let request = pendingSelection,
              request.displayID == displayID,
              let snapshot = screenSnapshots[displayID] else { return }
        pendingSelection = nil
        request.selectionView.selectionInteractionEnabled = true
        completeInitialSelection(request, preSnapshot: snapshot)
    }

    private func completeInitialSelection(
        _ request: PendingSelection,
        preSnapshot: CGImage?
    ) {
        guard !sessionEnded else { return }
        if let windowID = directWindowCaptureID(for: request, preSnapshot: preSnapshot) {
            startWindowCapture(
                windowID: windowID,
                request: request,
                preSnapshot: preSnapshot
            )
            return
        }
        finishInitialSelection(request, preSnapshot: preSnapshot, directWindowImage: nil)
    }

    private func directWindowCaptureID(
        for request: PendingSelection,
        preSnapshot: CGImage?
    ) -> CGWindowID? {
        guard request.isWindowSelection, let windowID = request.windowID else { return nil }
        if preSnapshot != nil,
           windowDetector.usesCompositedScreenBackdrop(forWindowID: windowID) {
            return nil
        }
        // Display-filling windows deliberately use the frozen screen pixels
        // and synthesized corners. Their independent image cannot contribute
        // an alpha mask, so do not wait for a capture that would be discarded.
        if preSnapshot != nil,
           CGDisplayBounds(request.displayID).contains(request.captureRect),
           !WindowEffects.shouldBorrowDirectWindowAlpha(
               captureRect: request.captureRect,
               displayBounds: CGDisplayBounds(request.displayID)
           ) {
            return nil
        }
        return windowID
    }

    private func startWindowCapture(
        windowID: CGWindowID,
        request: PendingSelection,
        preSnapshot: CGImage?
    ) {
        let captureTask = takeWindowCaptureTask(windowID: windowID, request: request)
        if postCaptureAction == .edit,
           let snapshotImage = preSnapshotImage(
               captureRect: request.captureRect, screen: request.screen, preSnapshot: preSnapshot
           ) {
            let preparation = WindowCapturePreparation(
                snapshotImage: snapshotImage,
                captureRect: request.captureRect,
                displayBounds: CGDisplayBounds(request.displayID),
                captureTask: captureTask
            )
            request.selectionView.selectionInteractionEnabled = true
            showEditor(
                captureRect: request.captureRect,
                screen: request.screen,
                selectionRect: request.screenRect,
                selectionViewRect: request.rect,
                hostSelectionView: request.selectionView,
                preSnapshot: preSnapshot,
                overrideBaseImage: presetImage,
                windowBaseImage: snapshotImage,
                isWindowCapture: true
            )
            editController?.attachWindowCapturePreparation(preparation)
            return
        }

        // The snapshot cannot supply off-screen pixels. Show an honest busy
        // state until the complete source exists, then create a usable editor.
        request.selectionView.selectionInteractionEnabled = false
        ToastWindow.show(message: L10n.windowCapturePreparing, on: request.screen, duration: 60)
        let generation = presentationGeneration
        let captureID = UUID()
        pendingWindowCapture = PendingWindowCapture(
            id: captureID, generation: generation, request: request, preSnapshot: preSnapshot
        )
        let snapshotImage = preSnapshotImage(
            captureRect: request.captureRect, screen: request.screen, preSnapshot: preSnapshot
        )
        let captureRect = request.captureRect
        let displayBounds = CGDisplayBounds(request.displayID)
        windowCaptureTask = Task.detached(priority: .userInitiated) { [weak self] in
            let directImage = await withTaskCancellationHandler {
                await captureTask.value
            } onCancel: {
                captureTask.cancel()
            }
            guard !Task.isCancelled else { return }
            let usableImage = directImage.flatMap {
                ScreenCapturer.isEffectivelyTransparent($0) ? nil : $0
            }
            let image = snapshotImage.map {
                WindowEffects.compositedWindowImage(
                    snapshotImage: $0, directWindowImage: usableImage,
                    captureRect: captureRect, displayBounds: displayBounds
                )
            } ?? usableImage
            guard !Task.isCancelled else { return }
            MainRunLoopScheduler.perform {
                self?.finishWindowCapture(image, captureID: captureID, generation: generation)
            }
        }
    }

    private func finishWindowCapture(
        _ image: NSImage?,
        captureID: UUID,
        generation: Int
    ) {
        guard generation == presentationGeneration,
              !sessionEnded,
              let pendingWindowCapture,
              pendingWindowCapture.id == captureID,
              pendingWindowCapture.generation == generation else { return }
        windowCaptureTask = nil
        self.pendingWindowCapture = nil
        ToastWindow.dismiss()
        let request = pendingWindowCapture.request
        request.selectionView.selectionInteractionEnabled = true
        guard let image else {
            finishSelectionCaptureFailure()
            return
        }
        presentInitialSelection(request, preSnapshot: pendingWindowCapture.preSnapshot, windowBaseImage: image)
    }

    private func finishInitialSelection(
        _ request: PendingSelection,
        preSnapshot: CGImage?,
        directWindowImage: NSImage?
    ) {
        let windowBaseImage = imageForWindowSelection(
            isWindowSelection: request.isWindowSelection,
            captureRect: request.captureRect,
            screen: request.screen,
            preSnapshot: preSnapshot,
            directWindowImage: directWindowImage
        )
        presentInitialSelection(request, preSnapshot: preSnapshot, windowBaseImage: windowBaseImage)
    }

    private func presentInitialSelection(
        _ request: PendingSelection,
        preSnapshot: CGImage?,
        windowBaseImage: NSImage?
    ) {
        let shouldApplyWindowEffects = request.isWindowSelection && windowBaseImage != nil

        switch postCaptureAction {
        case .edit:
            showEditor(
                captureRect: request.captureRect,
                screen: request.screen,
                selectionRect: request.screenRect,
                selectionViewRect: request.rect,
                hostSelectionView: request.selectionView,
                preSnapshot: preSnapshot,
                overrideBaseImage: presetImage,
                windowBaseImage: windowBaseImage,
                isWindowCapture: shouldApplyWindowEffects
            )
        case .quickPin, .textRecognition, .copyImageText, .screenshotTranslation:
            completeImmediateAction(request, preSnapshot: preSnapshot, windowBaseImage: windowBaseImage)
        case .record:
            tearDown()
            onComplete(nil)
            onRecordingSelection?(request.screenRect, request.screen)
        }
    }

    private func completeImmediateAction(
        _ request: PendingSelection,
        preSnapshot: CGImage?,
        windowBaseImage: NSImage?
    ) {
        let baseImage = imageForImmediateAction(
            captureRect: request.captureRect,
            screen: request.screen,
            preSnapshot: preSnapshot,
            windowBaseImage: windowBaseImage
        )
        tearDown()
        onComplete(nil)
        guard let baseImage else {
            ToastWindow.show(message: L10n.fullScreenScreenshotFailed)
            return
        }

        switch postCaptureAction {
        case .quickPin:
            PinLauncher.pin(image: baseImage, at: request.screenRect.origin)
        case .textRecognition:
            OCRTranslatePanel.presentTextRecognition(
                image: baseImage,
                anchorRect: request.screenRect,
                screen: request.screen
            )
        case .copyImageText:
            copyRecognizedTextToClipboard(
                from: baseImage,
                screen: request.screen,
                anchorRect: request.screenRect
            )
        case .screenshotTranslation:
            OCRTranslatePanel.presentScreenshotTranslation(
                image: baseImage,
                anchorRect: request.screenRect,
                screen: request.screen
            )
        case .edit, .record:
            break
        }
    }

    private func finishSelectionCaptureFailure() {
        guard !sessionEnded else { return }
        triggerContext?.finish(.failed)
        tearDown()
        onComplete(nil)
        onRequestFocusReturn?()
        ToastWindow.show(message: L10n.fullScreenScreenshotFailed)
    }

    private func showEditor(
        captureRect: CGRect,
        screen: NSScreen,
        selectionRect: NSRect,
        selectionViewRect: NSRect,
        hostSelectionView: SelectionView,
        preSnapshot: CGImage?,
        overrideBaseImage: NSImage?,
        windowBaseImage: NSImage?,
        isWindowCapture: Bool
    ) {
        activeEditorContext = ActiveEditorContext(
            captureRect: captureRect,
            screen: screen,
            selectionRect: selectionRect,
            selectionViewRect: selectionViewRect,
            hostSelectionView: hostSelectionView,
            selectionViewState: SelectionViewState(selectionView: hostSelectionView),
            preSnapshot: preSnapshot,
            overrideBaseImage: overrideBaseImage,
            windowBaseImage: windowBaseImage,
            isWindowCapture: isWindowCapture
        )
        editController = EditWindowController(
            captureRect: captureRect,
            screen: screen,
            selectionRect: selectionRect,
            selectionViewRect: selectionViewRect,
            hostSelectionView: hostSelectionView,
            preSnapshot: preSnapshot,
            overrideBaseImage: overrideBaseImage,
            windowBaseImage: windowBaseImage,
            isWindowCapture: isWindowCapture,
            onRecordingSelection: onRecordingSelection,
            onRequestFocusReturn: onRequestFocusReturn,
            keepsHostWindowAcrossSpaces: keepsEditorAcrossSpaces
        ) { [weak self] finalImage in
            self?.tearDown()
            self?.onComplete(finalImage)
        }
        editController?.show()
    }

    private func switchHistoryImageFromKeyboard(for event: NSEvent) -> Bool {
        guard postCaptureAction == .edit,
              let editController,
              !editController.blocksHistoryNavigation
        else {
            return false
        }
        if HotkeyManager.eventMatchesPreviousHistoryImageHotkey(event) {
            return switchHistoryImage(offset: 1)
        }
        if HotkeyManager.eventMatchesNextHistoryImageHotkey(event) {
            return switchHistoryImage(offset: -1)
        }
        return false
    }

    private func switchHistoryImage(offset: Int) -> Bool {
        refreshHistoryEntriesIfNeeded()
        guard !historyEntries.isEmpty else { return false }

        if historyEntryIndex == nil {
            guard offset > 0 else { return true }
            captureCurrentEditHistoryDraftIfNeeded()
        } else if historyEntryIndex == currentEditDraftIndex {
            currentEditHistoryDraft?.editorState = editController?.restorableState()
        } else {
            captureCurrentHistoryEditorDraftIfNeeded()
        }

        var nextIndex: Int
        if let currentIndex = historyEntryIndex {
            nextIndex = currentIndex + offset
        } else {
            guard offset > 0 else { return true }
            nextIndex = 0
        }
        let minimumIndex = currentEditHistoryDraft == nil ? 0 : -1
        guard nextIndex >= minimumIndex, nextIndex < historyEntries.count else { return true }

        if nextIndex == currentEditDraftIndex {
            return restoreCurrentEditHistoryDraft(at: nextIndex)
        }

        var image: NSImage?
        while nextIndex >= 0, nextIndex < historyEntries.count {
            image = HistoryManager.shared.image(for: historyEntries[nextIndex])
            if image != nil {
                break
            }
            nextIndex += offset
        }
        if nextIndex == currentEditDraftIndex {
            return restoreCurrentEditHistoryDraft(at: nextIndex)
        }
        guard let image else {
            return true
        }
        guard let screen = activeScreen ?? NSScreen.screens.first,
              let window = windows.first(where: { $0.screen == screen }),
              let selectionView = window.contentView as? SelectionView
        else { return false }

        editController?.tearDown()
        editController = nil

        let displayMetrics = Self.displayMetrics(for: image.size, on: screen)
        let visibleRect = Self.visibleRectInSelectionView(for: screen)
        let viewRect = NSRect(
            x: visibleRect.midX - displayMetrics.viewportSize.width / 2,
            y: visibleRect.midY - displayMetrics.viewportSize.height / 2,
            width: displayMetrics.viewportSize.width,
            height: displayMetrics.viewportSize.height
        )
        let screenRect = convertToScreenRect(viewRect, view: selectionView)
        let cgRect = convertToCGRect(screenRect)

        selectionView.updateSelectionRect(viewRect)
        selectionView.selectionSizeLabelOverride = Self.scaleLabelText(
            imageSize: image.size,
            displaySize: displayMetrics.canvasSize
        )
        selectionView.selectionLocked = true
        selectionView.selectionInteractionEnabled = true
        selectionView.selectionAdjustmentBounds = viewRect

        activeSelectionView = selectionView
        activeScreen = screen
        historyEntryIndex = nextIndex
        let historyDraft = historyEditorDrafts[historyEntries[nextIndex].fileURL]

        showEditor(
            captureRect: cgRect,
            screen: screen,
            selectionRect: screenRect,
            selectionViewRect: viewRect,
            hostSelectionView: selectionView,
            preSnapshot: nil,
            overrideBaseImage: image,
            windowBaseImage: nil,
            isWindowCapture: false
        )
        if let historyDraft {
            editController?.restoreState(historyDraft)
        }
        return true
    }

    private var currentEditDraftIndex: Int? {
        currentEditHistoryDraft == nil ? nil : -1
    }

    private func captureCurrentEditHistoryDraftIfNeeded() {
        guard currentEditHistoryDraft == nil,
              let editController,
              let context = activeEditorContext,
              let activeSelectionView = context.hostSelectionView
        else { return }

        currentEditHistoryDraft = CurrentEditHistoryDraft(
            captureRect: context.captureRect,
            screen: context.screen,
            selectionRect: context.selectionRect,
            selectionViewRect: context.selectionViewRect,
            hostSelectionView: activeSelectionView,
            selectionViewState: SelectionViewState(selectionView: activeSelectionView),
            preSnapshot: context.preSnapshot,
            overrideBaseImage: context.overrideBaseImage,
            windowBaseImage: context.windowBaseImage,
            isWindowCapture: editController.isWindowCapture,
            editorState: editController.restorableState()
        )
    }

    private func captureCurrentHistoryEditorDraftIfNeeded() {
        guard let historyEntryIndex,
              historyEntryIndex >= 0,
              historyEntryIndex < historyEntries.count,
              let editorState = editController?.restorableState()
        else { return }

        historyEditorDrafts[historyEntries[historyEntryIndex].fileURL] = editorState
    }

    private func restoreCurrentEditHistoryDraft(at index: Int) -> Bool {
        guard let draft = currentEditHistoryDraft,
              let selectionView = draft.hostSelectionView
        else { return true }

        editController?.tearDown()
        editController = nil

        selectionView.updateSelectionRect(draft.selectionViewRect)
        draft.selectionViewState.apply(to: selectionView)

        activeSelectionView = selectionView
        activeScreen = draft.screen
        historyEntryIndex = index

        showEditor(
            captureRect: draft.captureRect,
            screen: draft.screen,
            selectionRect: draft.selectionRect,
            selectionViewRect: draft.selectionViewRect,
            hostSelectionView: selectionView,
            preSnapshot: draft.preSnapshot,
            overrideBaseImage: draft.overrideBaseImage,
            windowBaseImage: draft.windowBaseImage,
            isWindowCapture: draft.isWindowCapture
        )
        if let editorState = draft.editorState {
            editController?.restoreState(editorState)
        }
        return true
    }

    private func refreshHistoryEntriesIfNeeded() {
        guard historyEntries.isEmpty else { return }
        historyEntries = HistoryManager.shared.imageEntries()
    }

    func selectionDidChange(rect: NSRect, inView view: NSView) {
        guard let _ = view.window else { return }
        // A resize/move drag changes the rect away from the clicked window.
        historyEntryIndex = nil
        currentEditHistoryDraft = nil
        historyEditorDrafts.removeAll()
        editController?.isWindowCapture = false
        let screenRect = convertToScreenRect(rect, view: view)
        let cgRect = convertToCGRect(screenRect)
        if let context = activeEditorContext {
            activeEditorContext = ActiveEditorContext(
                captureRect: cgRect,
                screen: context.screen,
                selectionRect: screenRect,
                selectionViewRect: rect,
                hostSelectionView: context.hostSelectionView,
                selectionViewState: SelectionViewState(
                    selectionSizeLabelOverride: nil,
                    selectionLocked: false,
                    selectionInteractionEnabled: true,
                    selectionAdjustmentBounds: context.selectionViewState.selectionAdjustmentBounds
                ),
                preSnapshot: context.preSnapshot,
                overrideBaseImage: context.overrideBaseImage,
                windowBaseImage: nil,
                isWindowCapture: false
            )
        }
        editController?.updateLayout(
            selectionRect: screenRect,
            selectionViewRect: rect,
            captureRect: cgRect
        )
    }

    private func imageForImmediateAction(
        captureRect: CGRect,
        screen: NSScreen,
        preSnapshot: CGImage?,
        windowBaseImage: NSImage?
    ) -> NSImage? {
        if let windowBaseImage {
            return windowBaseImage
        }
        if let preSnapshot {
            return ScreenCapturer.crop(from: preSnapshot, captureRect: captureRect, screen: screen)
        }
        return nil
    }

    private func copyRecognizedTextToClipboard(from image: NSImage, screen: NSScreen, anchorRect: NSRect) {
        let centerAnchor = NSPoint(x: anchorRect.midX, y: anchorRect.midY)
        ToastWindow.show(
            message: L10n.copyImageTextCopying,
            on: screen,
            centerAnchor: centerAnchor,
            duration: 60
        )

        Task { @MainActor in
            let text: String
            do {
                text = try await OCRService.recognizeResult(image: image).text
            } catch {
                guard !Task.isCancelled else { return }
                ToastWindow.show(message: error.localizedDescription, on: screen,
                                 centerAnchor: centerAnchor, duration: 2.5)
                return
            }
            guard !Task.isCancelled else { return }
            if text.isEmpty {
                ToastWindow.show(
                    message: L10n.copyImageTextNoText,
                    on: screen,
                    centerAnchor: centerAnchor,
                    duration: 1.5
                )
            } else {
                ClipboardManager.copyToClipboard(text: text)
                ToastWindow.show(
                    message: L10n.copyImageTextCopied,
                    on: screen,
                    centerAnchor: centerAnchor,
                    duration: 1.5
                )
            }
        }
    }

    private func imageForWindowSelection(
        isWindowSelection: Bool,
        captureRect: CGRect,
        screen: NSScreen,
        preSnapshot: CGImage?,
        directWindowImage: NSImage?
    ) -> NSImage? {
        guard isWindowSelection else { return nil }
        let usableDirectImage = directWindowImage.flatMap { image in
            ScreenCapturer.isEffectivelyTransparent(image) ? nil : image
        }

        if let snapshotWindowImage = preSnapshotImage(
            captureRect: captureRect,
            screen: screen,
            preSnapshot: preSnapshot
        ) {
            guard let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID else {
                return WindowEffects.roundedCorners(snapshotWindowImage)
            }
            return WindowEffects.compositedWindowImage(
                snapshotImage: snapshotWindowImage,
                directWindowImage: usableDirectImage,
                captureRect: captureRect,
                displayBounds: CGDisplayBounds(displayID)
            )
        }

        return usableDirectImage
    }

    private func preSnapshotImage(
        captureRect: CGRect,
        screen: NSScreen,
        preSnapshot: CGImage?
    ) -> NSImage? {
        guard let preSnapshot,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else {
            return nil
        }

        // A pre-overlay screen snapshot can only supply pixels that were
        // visible on this display. For partially off-screen windows, keep the
        // direct window capture path so the full window content and size survive.
        guard CGDisplayBounds(displayID).contains(captureRect) else {
            return nil
        }

        return ScreenCapturer.crop(from: preSnapshot, captureRect: captureRect, screen: screen)
    }
}
