// Only the capcap engine boundary and OS side effects are doubled. Production
// Settings, CaptureEntry, HistoryManagerBridge, Coordinator, HistoryBridge and
// ClipboardStore are compiled unchanged; this file contains no routing replica.
import AppKit
import CoreGraphics
import Foundation

#if CAPTURE_BOUNDARY
public enum CaptureProbe {
    public static var actions: [String] = []
    /// 遮罩/编辑器创建那一刻的现场（`ScreenshotCoordinator` 必须先收起面板再进来）。
    public static var onCaptureEntry: (() -> Void)?
    public static var activations = 0
    public static var fullScreenLaunches = 0
    public static var failFullScreen = false
    public static var suspendedToken: UUID?
    public static var resumedToken: UUID?
    static var current: OverlayWindowController?
    public static func complete(_ image: NSImage?) { current?.completion(image); current = nil }
    public static func suspend() {
        suspendedToken = current?.draft.token
        current?.suspension(current!.draft); current = nil
    }
    public static func historyImage(_ image: NSImage) { HistoryManager.shared.add(image: image) }
    public static func historyText(_ text: String) { HistoryManager.shared.addText(text) }
    public static func historyColor(_ hex: String) { HistoryManager.shared.addColor(hex: hex) }
}
struct CaptureTriggerContext {
    enum Source { case keyboardShortcut }
    let source: Source
}
final class OverlayWindowController {
    enum PostCaptureAction: String { case edit, quickPin, textRecognition, copyImageText, screenshotTranslation }
    struct SuspendedEditDraft {
        let screenDisplayID: CGDirectDisplayID? = nil
        let screenFrame: CGRect
        let token = UUID()
    }
    let draft: SuspendedEditDraft
    let completion: (NSImage?) -> Void
    let suspension: (SuspendedEditDraft) -> Void
    init(postCaptureAction: PostCaptureAction, triggerContext: CaptureTriggerContext,
         onFirstFramePresented: (() -> Void)?, onRecordingSelection: @escaping (CGRect, NSScreen) -> Void,
         onRequestFocusReturn: @escaping () -> Void, onSuspend: @escaping (SuspendedEditDraft) -> Void,
         onComplete: @escaping (NSImage?) -> Void) {
        draft = SuspendedEditDraft(screenFrame: NSScreen.screens.first?.frame ?? .zero)
        completion = onComplete; suspension = onSuspend
        CaptureProbe.onCaptureEntry?()
        CaptureProbe.actions.append(postCaptureAction.rawValue)
    }
    init(suspendedDraft: SuspendedEditDraft, onRecordingSelection: @escaping (CGRect, NSScreen) -> Void,
         onRequestFocusReturn: @escaping () -> Void, onSuspend: @escaping (SuspendedEditDraft) -> Void,
         onComplete: @escaping (NSImage?) -> Void) {
        draft = suspendedDraft; completion = onComplete; suspension = onSuspend
        CaptureProbe.resumedToken = suspendedDraft.token
    }
    func activate() { CaptureProbe.activations += 1; CaptureProbe.current = self }
}
enum ScreenCapturer {
    static func capture(rect: CGRect, screen: NSScreen, excludingWindowNumbers: [CGWindowID] = [], timeout: TimeInterval) -> NSImage? {
        CaptureProbe.failFullScreen ? nil : NSImage(size: NSSize(width: 2, height: 2))
    }
}
enum ImageEditLauncher {
    enum Source { case fullScreen }
    static func launch(generatedImage: NSImage, source: Source, onRequestFocusReturn: @escaping () -> Void,
                       onSuspend: @escaping (OverlayWindowController.SuspendedEditDraft) -> Void,
                       onComplete: @escaping (NSImage?) -> Void) -> AnyObject? {
        CaptureProbe.fullScreenLaunches += 1
        let controller = OverlayWindowController(postCaptureAction: .edit,
            triggerContext: CaptureTriggerContext(source: .keyboardShortcut), onFirstFramePresented: nil,
            onRecordingSelection: { _, _ in }, onRequestFocusReturn: onRequestFocusReturn,
            onSuspend: onSuspend, onComplete: onComplete)
        controller.activate()
        return controller
    }
}
#else
import Combine
import CryptoKit
import CoreData
import BlinkClipCore
import BlinkClipCapture

@MainActor final class GlobalHotKey {
    static var events: [String] = []
    static var status: OSStatus = 0
    static var pressedDuringTracking: UInt32?
    private var registeredIdentifier: UInt32?
    var action: (() -> Void)?
    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, identifier: UInt32) -> OSStatus {
        Self.events.append("register:\(identifier):\(keyCode):\(modifiers.rawValue)")
        registeredIdentifier = Self.status == 0 ? identifier : nil
        return Self.status
    }
    func isPressedDuringMenuTracking() -> Bool {
        guard let registeredIdentifier else { return false }
        return registeredIdentifier == Self.pressedDuringTracking
    }
    func unregister() { registeredIdentifier = nil; Self.events.append("unregister") }
}
struct ScreenshotFocusRestorer {
    static func captureFrontmost() -> Self { Self() }
    func restore() {}
}
enum ReplicaBrand {
    static let name = "BlinkClip"
    /// `ReplicaCopiedOSD` 会把品牌名替换成应用显示名；harness 里没有品牌替换，原样返回。
    static func replacingName(in text: String) -> String { text }
}

@main struct CaptureIntegrationHarness {
    enum Failure: Error { case assertion(String) }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "read-action" {
            guard BlinkClipScreenshotSettings.postCaptureAction.rawValue == args[2] else { exit(3) }
            exit(0)
        }
        if args.count == 3 && args[1] == "read-cleared" {
            let slot = BlinkClipScreenshotHotKeySlot(rawValue: args[2])!
            guard BlinkClipScreenshotSettings.effectiveShortcut(for: slot) == nil else { exit(4) }
            exit(0)
        }
        defer { defaults.removePersistentDomain(forName: domain); defaults.synchronize() }
        defaults.removePersistentDomain(forName: domain)
        var checks: [String] = []
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure.assertion(message) }
            checks.append(message)
            fputs("PASS \(message)\n", stderr)
        }
        func reopenAction(_ expected: String) throws {
            defaults.synchronize()
            let p = Process(); p.executableURL = Bundle.main.executableURL
            p.arguments = ["read-action", expected]; try p.run(); p.waitUntilExit()
            try require(p.terminationStatus == 0, "fresh-process preference read: \(expected)")
        }
        func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
        try require(BlinkClipScreenshotSettings.postCaptureAction == .edit, "missing action falls back to edit")
        defaults.set("unsupported", forKey: BlinkClipScreenshotSettings.postCaptureActionKey)
        try require(BlinkClipScreenshotSettings.postCaptureAction == .edit, "invalid action falls back to edit")
        // Start from a non-default value so `.edit` must really be written,
        // rather than passing only because the invalid value falls back to it.
        BlinkClipScreenshotSettings.postCaptureAction = .screenshotTranslation
        var actionNotifications = 0
        let observer = NotificationCenter.default.addObserver(forName: BlinkClipScreenshotSettings.didChange,
            object: nil, queue: .main) { _ in actionNotifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        for action in BlinkClipScreenshotAction.allCases {
            BlinkClipScreenshotSettings.postCaptureAction = action
            try require(defaults.string(forKey: BlinkClipScreenshotSettings.postCaptureActionKey) == action.rawValue,
                        "selected action is serialized: \(action.rawValue)")
            try reopenAction(action.rawValue)
            _ = CaptureEntry.presentRegionEditor(onFocusReturn: {}, onComplete: { _ in })
            try require(CaptureProbe.actions.last == action.rawValue, "real CaptureEntry forwards \(action.rawValue)")
            CaptureProbe.complete(nil)
        }
        try require(actionNotifications == 5, "all five changed effective actions notify")
        let before = actionNotifications
        BlinkClipScreenshotSettings.postCaptureAction = .screenshotTranslation
        try require(actionNotifications == before, "same action does not notify")
        _ = CaptureEntry.presentFullScreenEditor(onFocusReturn: {}, onComplete: { _ in })
        try require(CaptureProbe.fullScreenLaunches == 1 && CaptureProbe.actions.last == "edit", "full screen uses editor regardless of region preference")
        CaptureProbe.complete(nil)

        try require(BlinkClipScreenshotSettings.effectiveShortcut(for: .region) == BlinkClipScreenshotSettings.regionDefault && BlinkClipScreenshotSettings.effectiveShortcut(for: .fullScreen) == BlinkClipScreenshotSettings.fullScreenDefault, "legacy preferences without enabled keys preserve both defaults")
        for bad: Any in ["abc", true, -1, 70000] {
            defaults.set(bad, forKey: BlinkClipScreenshotSettings.regionKeyCodeKey)
            try require(BlinkClipScreenshotSettings.regionShortcut == BlinkClipScreenshotSettings.regionDefault, "malformed region key falls back: \(bad)")
        }
        BlinkClipScreenshotSettings.setShortcut(BlinkClipScreenshotSettings.regionDefault, for: .region, force: true)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAPTURE_STORE_ROOT"]!)
        let store = try ClipboardStore(directoryURL: root)
        try require(store.items.isEmpty, "capture integration starts with an empty isolated Store")
        var savedContext: NSManagedObjectContext?
        var saveCount = 0
        let saveObserver = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave,
            object: nil, queue: nil) { notification in
                guard let context = notification.object as? NSManagedObjectContext,
                      context.persistentStoreCoordinator?.persistentStores.contains(where: {
                          $0.url?.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
                      }) == true else { return }
                savedContext = context; saveCount += 1
            }
        defer { NotificationCenter.default.removeObserver(saveObserver) }
        let pb = NSPasteboard(name: NSPasteboard.Name("local.blinkclip.capture-test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let coordinator = ScreenshotCoordinator(store: store, pasteboard: pb)
        defer { coordinator.stop() }
        GlobalHotKey.status = -9878
        coordinator.start()
        try require(BlinkClipScreenshotSettings.lastRegistration[.region]?.status == -9878, "registration failure reaches settings")
        GlobalHotKey.status = 0; GlobalHotKey.events.removeAll()
        BlinkClipScreenshotSettings.requestHotKeyReload()
        try require(GlobalHotKey.events.prefix(2).allSatisfy { $0 == "unregister" } && GlobalHotKey.events.count == 4,
                    "retry with unchanged preference unregisters both before registering")
        try require(BlinkClipScreenshotSettings.lastRegistration.values.allSatisfy(\.succeeded), "retry replaces failed registration results")
        GlobalHotKey.events.removeAll()
        let custom = BlinkClipScreenshotHotKey(keyCode: 40, modifierRawValue: NSEvent.ModifierFlags([.control, .option]).rawValue)
        BlinkClipScreenshotSettings.regionShortcut = custom
        try require(GlobalHotKey.events.count == 4 && GlobalHotKey.events[2].hasPrefix("register:101:40:"), "settings notification registers selected key after old keys removed")
        GlobalHotKey.events.removeAll()
        BlinkClipScreenshotSettings.beginRecording(); BlinkClipScreenshotSettings.beginRecording()
        try require(GlobalHotKey.events == ["unregister", "unregister"], "overlapping recording suspends keys once")
        BlinkClipScreenshotSettings.fullScreenShortcut = BlinkClipScreenshotHotKey(keyCode: 41, modifierRawValue: custom.modifierRawValue)
        BlinkClipScreenshotSettings.endRecording()
        try require(GlobalHotKey.events.count == 2, "first recorder ending leaves keys suspended")
        BlinkClipScreenshotSettings.endRecording()
        try require(GlobalHotKey.events.count == 6 && GlobalHotKey.events.last!.hasPrefix("register:102:41:"), "last recorder restores current preferences")
        let endedCount = GlobalHotKey.events.count
        BlinkClipScreenshotSettings.endRecording()
        try require(GlobalHotKey.events.count == endedCount, "extra recording end does not re-register")

        // Clearing is persisted independently from the legacy key/modifier pair.
        for slot in BlinkClipScreenshotHotKeySlot.allCases {
            let other: BlinkClipScreenshotHotKeySlot = slot == .region ? .fullScreen : .region
            let otherValue = BlinkClipScreenshotSettings.effectiveShortcut(for: other)
            let oldValue = BlinkClipScreenshotSettings.shortcut(for: slot)
            GlobalHotKey.events.removeAll()
            BlinkClipScreenshotSettings.clearShortcut(for: slot)
            let identifier = slot == .region ? "101" : "102"
            try require(BlinkClipScreenshotSettings.effectiveShortcut(for: slot) == nil, "cleared shortcut is unset: \(slot)")
            try require(BlinkClipScreenshotSettings.lastRegistration[slot] == nil, "cleared slot removes stale registration status: \(slot)")
            try require(GlobalHotKey.events.contains("unregister") && !GlobalHotKey.events.contains(where: { $0.hasPrefix("register:\(identifier):") }), "cleared slot is really unregistered and never registered: \(slot)")
            try require(BlinkClipScreenshotSettings.effectiveShortcut(for: other) == otherValue, "clearing leaves other slot unchanged: \(slot)")
            try require(BlinkClipScreenshotSettings.slot(occupying: oldValue) == nil, "cleared shortcut no longer reserves a combination: \(slot)")
            defaults.synchronize()
            let fresh = Process(); fresh.executableURL = Bundle.main.executableURL
            fresh.arguments = ["read-cleared", slot.rawValue]; try fresh.run(); fresh.waitUntilExit()
            try require(fresh.terminationStatus == 0, "fresh-process unset shortcut persists: \(slot)")
            BlinkClipScreenshotSettings.requestHotKeyReload()
            try require(!GlobalHotKey.events.contains(where: { $0.hasPrefix("register:\(identifier):") }), "reload leaves cleared shortcut disabled: \(slot)")
            GlobalHotKey.events.removeAll()
            BlinkClipScreenshotSettings.setShortcut(oldValue, for: slot)
            try require(BlinkClipScreenshotSettings.effectiveShortcut(for: slot) == oldValue && GlobalHotKey.events.contains(where: { $0.hasPrefix("register:\(identifier):") }), "assigning same legacy combination re-enables cleared slot: \(slot)")
        }
        for slot in BlinkClipScreenshotHotKeySlot.allCases { BlinkClipScreenshotSettings.clearShortcut(for: slot) }
        BlinkClipScreenshotSettings.restoreAllShortcutDefaults()
        try require(BlinkClipScreenshotSettings.effectiveShortcut(for: .region) == BlinkClipScreenshotSettings.regionDefault && BlinkClipScreenshotSettings.effectiveShortcut(for: .fullScreen) == BlinkClipScreenshotSettings.fullScreenDefault, "restore all re-enables both cleared screenshot defaults")
        // Preserve this suite's existing custom-pair assertions below.
        BlinkClipScreenshotSettings.regionShortcut = custom
        BlinkClipScreenshotSettings.fullScreenShortcut = .init(keyCode: 41, modifierRawValue: custom.modifierRawValue)

        let beforeMenuCapture = CaptureProbe.activations
        var activationsWhileTracking = -1
        coordinator.trackStatusMenu(NSMenu()) {
            GlobalHotKey.pressedDuringTracking = 101
            RunLoop.current.run(mode: .eventTracking, before: Date().addingTimeInterval(0.1))
            activationsWhileTracking = CaptureProbe.activations
        }
        GlobalHotKey.pressedDuringTracking = nil
        drain()
        try require(activationsWhileTracking == beforeMenuCapture
                    && CaptureProbe.activations == beforeMenuCapture + 1,
                    "region shortcut sampled in menu tracking launches only after the menu returns")
        CaptureProbe.complete(nil)

        coordinator.startRegionCapture()
        GlobalHotKey.events.removeAll()
        BlinkClipScreenshotSettings.requestHotKeyReload()
        try require(GlobalHotKey.events.isEmpty, "reload deferred while presentation is queued")
        drain()
        let activeCount = CaptureProbe.activations
        coordinator.startRegionCapture(); drain()
        try require(CaptureProbe.activations == activeCount, "active overlay rejects repeated capture")
        BlinkClipScreenshotSettings.requestHotKeyReload()
        try require(GlobalHotKey.events.isEmpty, "reload deferred while overlay is active")
        let emptyCount = store.items.count
        CaptureProbe.complete(nil)
        try require(store.items.count == emptyCount && pb.pasteboardItems?.isEmpty != false, "cancel callback leaves Store and private pasteboard empty")
        try require(GlobalHotKey.events.count == 4, "cancel exit applies pending reload")

        BlinkClipScreenshotSettings.postCaptureAction = .edit
        coordinator.startRegionCapture(); drain()
        GlobalHotKey.events.removeAll(); BlinkClipScreenshotSettings.requestHotKeyReload()
        CaptureProbe.suspend()
        try require(GlobalHotKey.events.count == 4, "suspend exit applies pending reload")
        BlinkClipScreenshotSettings.postCaptureAction = .textRecognition
        coordinator.startRegionCapture()
        try require(CaptureProbe.resumedToken != nil && CaptureProbe.resumedToken == CaptureProbe.suspendedToken,
                    "real resume entry forwards original draft unchanged despite preference change")
        CaptureProbe.complete(nil)

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: 3, height: 2)); image.addRepresentation(bitmap)
        coordinator.startRegionCapture(); drain(); CaptureProbe.complete(image)
        let saved = store.items.first!
        try require(saved.kind == .image && saved.plainText == nil && Set(saved.payloads.keys) == ["public.png"], "completion creates PNG image record in real Store")
        try require(pb.data(forType: .png) == saved.payloads["public.png"], "completion writes same PNG via real Store to private pasteboard")

        // --- T2：统一 toast（复制 / 暂停 / 继续 / 截图已复制）----------------------
        // 成功 = 落库 + 写剪贴板都成功；失败分支只 beep，不弹这条。
        let toast = ReplicaToast.shared
        let toastCopy = ReplicaToastCopy.text(.screenshotCopied)
        try require(ReplicaToast.holdDuration >= 1.2 && ReplicaToast.holdDuration <= 1.5,
                    "toast hold time stays inside the 1.2–1.5s band")
        try require(abs(ReplicaToast.fadeDuration - 0.2) < 0.001,
                    "toast fade is 0.2s for every toast")
        try require(toast.isVisible, "successful screenshot presents the copied toast")
        try require(toast.currentText == toastCopy && !toastCopy.isEmpty
                    && toastCopy != ReplicaToastCopy.Key.screenshotCopied.rawValue,
                    "screenshot toast text is the trilingual screenshot-copied copy")
        try require(toast.isVisible && toast.presentationCount == 1, "the first successful screenshot presents exactly one toast")

        /// 窗口服务器看到的共享状态：0 = 任何截屏/录屏都抓不到这块窗口。
        func windowServerSharingState(_ window: NSWindow?) -> Int? {
            guard let window else { return nil }
            let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.windowNumber))
                as? [[String: Any]] ?? []
            return list.first?[kCGWindowSharingState as String] as? Int
        }
        /// 统一的 200×200pt 盘面：固定尺寸、圆角 20、上图下字、整块居中、只有一行文案区。
        func requireToastBox(_ window: NSWindow?, _ what: String) throws {
            guard let window, let view = window.contentView as? ReplicaToastView else {
                throw Failure.assertion("\(what): content view is not the shared ReplicaToastView")
            }
            let size = window.frame.size
            try require(size == ReplicaToastView.panelSize,
                        "\(what): the plate is exactly 128×128pt, got \(size)")
            try require(view.bounds.size == ReplicaToastView.panelSize,
                        "\(what): the plate view fills 128×128pt, got \(view.bounds.size)")
            try require(abs((view.layer?.cornerRadius ?? 0) - ReplicaToastView.cornerRadius) <= 0.01,
                        "\(what): corner radius is 16pt")
            try require(view.copyNodeCount == 1, "\(what): only one copy node, no second line of small text")
            try require(!view.copyText.contains("\n"), "\(what): copy carries no line break")
            try require(view.renderedLineCount >= 1 && view.renderedLineCount <= 2,
                        "\(what): the copy really renders in 1–2 lines, got \(view.renderedLineCount)")
            try require(view.maximumTextLines == 2, "\(what): the copy may wrap to at most two lines")
            try require(abs(view.textFontSize - 14) <= 0.01, "\(what): the copy is 14pt, got \(view.textFontSize)")
            try require(view.textAlignment == NSTextAlignment.center.rawValue,
                        "\(what): the copy is centred, alignment=\(view.textAlignment)")
            try require(abs(view.textLineSpacing2 - 2) <= 0.01,
                        "\(what): the copy uses 2pt line spacing, got \(view.textLineSpacing2)")
            let icon = view.iconFrame, text = view.textFrame
            try require(icon.width >= 40 && icon.width <= 44 && icon.height >= 40 && icon.height <= 44,
                        "\(what): the symbol slot is in the 40–44pt band, got \(icon.size)")
            try require(abs(icon.width - 42) <= 0.5, "\(what): the symbol slot is 42pt wide")
            try require(icon.minY > text.maxY, "\(what): the symbol sits above the copy (vertical layout)")
            try require(abs(icon.minY - text.maxY - ReplicaToastView.iconTextSpacing) <= 0.5,
                        "\(what): icon-to-copy spacing is the fixed 24pt")
            try require(abs(icon.midX - text.midX) <= 0.5 && abs(icon.midX - view.bounds.midX) <= 0.5,
                        "\(what): symbol and copy share the plate's horizontal centre")
            // 配色规范：图标与文案都是白色，底板两套系统外观下都是深色。
            try require(view.iconColor == .white, "\(what): the symbol is white")
            try require(view.copyColor == .white, "\(what): the copy is white")
            try require(view.backingAppearance == .vibrantDark,
                        "\(what): the plate keeps the dark HUD appearance in any system appearance")
            // 整块内容在盘内垂直居中：上下留白差 ≤0.5pt。
            let topGap = view.bounds.height - icon.maxY
            let bottomGap = text.minY
            try require(abs(topGap - bottomGap) <= 0.5,
                        "\(what): the content block is centred vertically (top \(topGap) vs bottom \(bottomGap))")
        }
        /// 底部居中：不压 Dock、离可用区域底边 120pt、水平居中。
        func requireBottomPlacement(_ window: NSWindow?, _ what: String) throws {
            guard let window, let screen = NSScreen.main else {
                throw Failure.assertion("\(what): toast window or screen missing")
            }
            let frame = window.frame
            let visible = screen.visibleFrame
            try require(frame.minY >= visible.minY - 0.5,
                        "\(what): toast sits above the Dock (frame.minY \(frame.minY) >= visibleFrame.minY \(visible.minY))")
            try require(abs(frame.minY - (visible.minY + ReplicaToast.bottomInset)) <= 1,
                        "\(what): toast bottom is 120pt above the usable bottom edge")
            try require(frame.minY - visible.minY <= 150,
                        "\(what): toast stays within 150pt of the bottom of the usable area")
            try require(frame.midY < screen.frame.midY, "\(what): toast is in the bottom half of the screen")
            try require(abs(frame.midX - visible.midX) <= 1, "\(what): toast is horizontally centred")
        }

        let toastWindow = toast.window
        try require(toastWindow is ReplicaToastPanel, "screenshot toast uses the shared toast panel class")
        try require(toastWindow?.ignoresMouseEvents == true, "toast ignores mouse events so it never takes focus")
        try require(toastWindow?.canBecomeKey == false && toastWindow?.canBecomeMain == false,
                    "toast can never become key or main")
        try require(toastWindow?.sharingType == NSWindow.SharingType.none,
                    "toast reports sharingType .none")
        // 出货件此前实测到 1：`WindowSharingPolicy` 在 didExpose/didUpdate 上把每个窗口
        // 改回 `.readOnly`。这里按窗口服务器的事实断言，而不是只信 NSWindow 属性。
        // 新窗口要等窗口服务器完成一次合成才会出现在 CGWindowList 里。
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let sharingBeforePolicy = windowServerSharingState(toastWindow)
        try require(sharingBeforePolicy == 0,
                    "window server reports CGWindowSharingState == 0 (toast cannot be captured), got \(sharingBeforePolicy.map(String.init) ?? "missing")")
        // 复现策略写入：允许读（.readOnly）也必须落回 .none。
        toastWindow?.sharingType = .readOnly
        try require(toastWindow?.sharingType == NSWindow.SharingType.none,
                    "an external sharingType write cannot turn the toast back into a capturable window")
        try require(windowServerSharingState(toastWindow) == 0,
                    "CGWindowSharingState stays 0 after the screen-sharing policy writes .readOnly")
        // capcap 的编辑器浮层是 `.screenSaver + 3/+4`；toast 必须比它们更高一级。
        try require((toastWindow?.level.rawValue ?? 0) > NSWindow.Level.screenSaver.rawValue + 4,
                    "toast sits above the screenshot editor overlay windows")
        try require(toast.currentSymbolName == "checkmark", "screenshot toast uses the bare checkmark symbol")
        let screenshotSymbol = toast.currentSymbolName
        try requireToastBox(toastWindow, "screenshot toast")
        try requireBottomPlacement(toastWindow, "screenshot toast")
        let plateHeight = toastWindow?.frame.height ?? 0
        let singleLineTextHeight = (toastWindow?.contentView as? ReplicaToastView)?.textFrame.height ?? 0

        // 暂停（无定时）：只有一句「已暂停记录剪贴板」，没有第二行复述。
        ReplicaCopiedOSD.showPaused(resumeDate: nil)
        try require(toast.currentText == ReplicaToastCopy.text(.pastePaused),
                    "pause toast without a timer is the single paused line")
        try require(!(toast.currentText ?? "").contains("·"),
                    "pause toast without a timer adds no trailing time fragment")
        try require(toast.currentSymbolName == "pause", "pause toast uses the pause symbol")
        try require(toast.window === toastWindow && toastWindow is ReplicaToastPanel,
                    "pause toast reuses the same shared panel class and instance")
        try require(toastWindow?.ignoresMouseEvents == true, "pause toast is not clickable")
        try requireToastBox(toastWindow, "pause toast")
        try requireBottomPlacement(toastWindow, "pause toast")

        // 暂停（有定时）：时间并进同一句，不拆成第二行小字。
        var components = DateComponents()
        components.hour = 14
        components.minute = 30
        let resumeAt = Calendar.current.date(from: components) ?? Date()
        ReplicaCopiedOSD.showPaused(resumeDate: resumeAt)
        let pausedUntilCopy = ReplicaToastCopy.pastePaused(until: "14:30")
        try require(toast.currentText == pausedUntilCopy,
                    "pause toast with a timer merges the resume time into the same copy")
        try require((toast.currentText ?? "").components(separatedBy: "14:30").count == 2,
                    "the resume time appears exactly once in the pause toast")
        try require(pausedUntilCopy.components(separatedBy: ReplicaToastCopy.text(.pastePaused)).count == 2,
                    "the paused sentence itself is present exactly once")
        try requireToastBox(toastWindow, "pause toast with timer")
        try requireBottomPlacement(toastWindow, "pause toast with timer")

        // 继续：同样 200×200、同位置、同窗口。
        ReplicaCopiedOSD.showResumed()
        try require(toast.currentText == ReplicaToastCopy.text(.pasteResumed),
                    "resume toast is the single resumed line")
        try require(toast.currentSymbolName == "arrow.clockwise", "resume toast uses the resume symbol")
        try require(toast.window === toastWindow, "resume toast reuses the same window")
        try requireToastBox(toastWindow, "resume toast")
        try requireBottomPlacement(toastWindow, "resume toast")

        // 复制（无动作）：不可点；图标与截图 toast 是同一个裸对勾。
        ReplicaCopiedOSD.showCopied()
        try require(toast.currentText == ReplicaToastCopy.text(.copied), "copy toast uses the copied line")
        try require(toast.currentSymbolName == "checkmark" && toast.currentSymbolName == screenshotSymbol,
                    "the copied and screenshot-copied toasts share the exact same symbol")
        try require(!toast.isInteractive, "copy toast without an action is not clickable")
        try require(toastWindow?.ignoresMouseEvents == true, "a copy toast without an action ignores mouse events")
        try requireToastBox(toastWindow, "copy toast")
        try requireBottomPlacement(toastWindow, "copy toast")

        // 复制（可点）：整块可点，且不再多一行「点击启用直接粘贴」的小字。
        var directPasteEnabled = false
        ReplicaCopiedOSD.showCopied(enableDirectPaste: { directPasteEnabled = true })
        try require(toast.currentText == ReplicaToastCopy.text(.copied), "actionable copy toast keeps the copied line")
        try require(toast.isInteractive, "the direct-paste toast is clickable as a whole")
        try require(toastWindow?.ignoresMouseEvents == false, "the clickable toast accepts mouse events")
        try require(toastWindow?.frame.height == plateHeight,
                    "the actionable toast adds no second line of copy")
        try requireToastBox(toastWindow, "actionable copy toast")
        try requireBottomPlacement(toastWindow, "actionable copy toast")
        if let view = toast.window?.contentView as? ReplicaToastView,
           let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 5, y: 5),
                                          modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: toastWindow?.windowNumber ?? 0, context: nil,
                                          eventNumber: 0, clickCount: 1, pressure: 1) {
            view.mouseDown(with: event)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        try require(directPasteEnabled, "clicking anywhere on the plate runs the direct-paste action")
        try require(windowServerSharingState(toastWindow) == 0,
                    "every toast keeps CGWindowSharingState == 0")

        // 盘面固定：文案变长也只换行，不改变窗口尺寸。
        toast.present(.init(symbolName: "checkmark", text: String(repeating: "Wide ", count: 40)))
        try require(toastWindow?.frame.size == ReplicaToastView.panelSize,
                    "a very long copy keeps the fixed 128×128pt plate")
        try requireToastBox(toastWindow, "long-copy toast")
        if let view = toast.window?.contentView as? ReplicaToastView {
            try require(view.textFrame.height > singleLineTextHeight * 1.5,
                        "the wrapped copy really occupies two lines inside the plate (\(view.textFrame.height) vs \(singleLineTextHeight))")
            try require(abs(view.iconFrame.minY - view.textFrame.maxY - ReplicaToastView.iconTextSpacing) <= 0.5,
                        "icon-to-copy spacing stays 16pt when the copy wraps")
        }
        // --- T3：停留时长（墙钟）---------------------------------------------------
        // 「1.3s 停留 + 0.2s 淡出」必须从**真正上屏可见**那一刻起算，并且不能因为主线程
        // 忙就被拉长：1.0.19 真机上「已复制截图」实测 2.72s（= 1.3 + 1.2 卡顿 + 0.2），
        // 原因是淡出与 orderOut 都挂在主线程的 `NSAnimationContext` 回调上。
        // 这里按真实 RunLoop 逐轮询 `isVisible`，量「上屏 → 收起」的墙钟，四条 toast 全覆盖。
        func measureToastWallClock(_ what: String, _ present: @MainActor () -> Void) throws -> TimeInterval {
            let start = Date()
            present()
            let deadline = Date().addingTimeInterval(3.5)
            while toast.isVisible && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            let wall = Date().timeIntervalSince(start)
            try require(!toast.isVisible, "\(what): toast really orderOuts itself")
            let recorded = toast.lastVisibleDuration ?? -1
            try require(abs(recorded - wall) <= 0.2,
                        "\(what): the recorded on-screen duration (\(String(format: "%.3f", recorded))s) matches the wall clock (\(String(format: "%.3f", wall))s)")
            try require(wall >= 1.3 && wall <= 1.7,
                        "\(what): stays 1.3–1.7s on screen (1.3 hold + 0.2 fade), got \(String(format: "%.3f", wall))s")
            return wall
        }
        // 机制断言：整段时长必须交给渲染服务器，锚点是「首帧已提交」而不是 present 被调用。
        ReplicaCopiedOSD.showScreenshotCopied()
        try require(toast.usesRenderServerTimeline,
                    "the hold + fade timeline is a layer CA animation driven by the render server (not a main-thread NSAnimationContext)")
        try require(toast.lastVisibleAt != nil,
                    "the hold clock is anchored at the committed first frame, not at the present() call")
        try require(toast.isVisible, "the flushed first frame is on screen synchronously after present")
        let anchorDrift = abs((toast.lastVisibleAt ?? .distantPast).timeIntervalSinceNow)
        try require(anchorDrift < 0.1,
                    "the hold-clock anchor is the just-committed frame (drift \(String(format: "%.3f", anchorDrift))s)")
        var toastDurations: [String: TimeInterval] = [:]
        toastDurations["copied"] = try measureToastWallClock("copy toast") { ReplicaCopiedOSD.showCopied() }
        toastDurations["paused"] = try measureToastWallClock("paused toast") { ReplicaCopiedOSD.showPaused(resumeDate: nil) }
        toastDurations["resumed"] = try measureToastWallClock("resumed toast") { ReplicaCopiedOSD.showResumed() }
        // 截图那条是唯一「BlinkClip 还是当前 App（截图编辑器刚关）」时弹的 toast，
        // 也是 1.0.19 超时的那个：连测三轮，确认不是偶发。
        for round in 1...3 {
            toastDurations["screenshot-eligible-\(round)"] = try measureToastWallClock("screenshot toast round \(round)") {
                ReplicaCopiedOSD.showScreenshotCopied()
            }
        }
        let durationBand = toastDurations.values.min()!...toastDurations.values.max()!
        try require(durationBand.lowerBound >= 1.3 && durationBand.upperBound <= 1.7,
                    "all four toasts stay inside 1.3–1.7s: \(toastDurations.mapValues { String(format: "%.3f", $0) })")

        let presentationsBeforeCapture = toast.presentationCount

        // 连续截图：上一颗 toast 必须在新截图抓屏前收起——这是「toast 不进成图」的兜底
        // （真正的保证是 sharingType 恒为 .none）。
        var toastVisibleAtCaptureEntry: Bool?
        CaptureProbe.onCaptureEntry = { toastVisibleAtCaptureEntry = toast.isVisible }
        coordinator.startRegionCapture()
        drain()
        CaptureProbe.onCaptureEntry = nil
        try require(toastVisibleAtCaptureEntry == false,
                    "a new capture hides the visible toast before the screen is snapshotted")
        CaptureProbe.complete(image)
        try require(toast.isVisible && toast.presentationCount == presentationsBeforeCapture + 1
                    && toast.window === toastWindow,
                    "a second quick screenshot reuses and resets the same toast instead of stacking")
        try require(toast.currentText == toastCopy, "the screenshot toast comes back with its own copy")
        try require(NSApp.windows.filter { $0 === toast.window }.count == 1,
                    "only one toast window exists no matter how many toasts were shown")
        RunLoop.current.run(until: Date().addingTimeInterval(ReplicaToast.holdDuration - 0.15))
        try require(toast.isVisible, "toast is still visible just before the hold elapses")
        RunLoop.current.run(until: Date().addingTimeInterval(ReplicaToast.fadeDuration + 0.45))
        try require(!toast.isVisible, "toast disappears after hold + fade")
        try require(toast.presentationCount == presentationsBeforeCapture + 1,
                    "one screenshot presents exactly one toast (no second present resetting the timer)")

        // 三轮真实截图循环：每轮都量「截图上屏 → 收起」的墙钟，确认 2.72s 不是偶发。
        var captureRoundDurations: [TimeInterval] = []
        for round in 1...3 {
            let before = toast.presentationCount
            coordinator.startRegionCapture()
            drain()
            let start = Date()
            CaptureProbe.complete(image)
            let deadline = Date().addingTimeInterval(3.5)
            while toast.isVisible && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            let wall = Date().timeIntervalSince(start)
            try require(!toast.isVisible && toast.presentationCount == before + 1,
                        "capture round \(round): exactly one present and it orderOuts itself")
            try require(wall >= 1.3 && wall <= 1.7,
                        "capture round \(round): screenshot toast stays 1.3–1.7s on screen, got \(String(format: "%.3f", wall))s")
            captureRoundDurations.append(wall)
        }
        try require((captureRoundDurations.max() ?? 9) - (captureRoundDurations.min() ?? 0) <= 0.2,
                    "three screenshot rounds agree on the stay duration (spread <= 0.2s): \(captureRoundDurations.map { String(format: "%.3f", $0) })")
        let bridge = ScreenshotHistoryBridge(store: store)
        try require(bridge.blinkclipImageEntries().count == 1 && bridge.blinkclipImage(forLocator: bridge.blinkclipImageEntries()[0].locator) != nil,
                    "history bridge reads real image locator and decodes payload")
        func diagnosticSHA(_ data: Data?) -> String {
            guard let data else { return "nil" }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        func diagnosticItems(_ phase: String) {
            fputs("DUPLICATE_DIAG phase=\(phase) mainThread=\(Thread.isMainThread) count=\(store.items.count)\n", stderr)
            for item in store.items {
                fputs("DUPLICATE_DIAG id=\(item.id) kind=\(item.kind) pngLength=\(item.payloads["public.png"]?.count ?? -1) pngSHA=\(diagnosticSHA(item.payloads["public.png"])) updatedAt=\(item.updatedAt.timeIntervalSince1970)\n", stderr)
            }
        }
        diagnosticItems("before-historyImage")
        CaptureProbe.historyImage(image)
        diagnosticItems("after-historyImage")
        let repeatedImage = store.items.first { $0.kind == .image }!
        try require(repeatedImage.id == saved.id && store.items.count == 1,
                    "duplicate PNG updates original identity without creating a second item")
        let repeatedReopened = try ClipboardStore(directoryURL: root)
        try require(repeatedReopened.items.first { $0.id == saved.id }?.updatedAt == repeatedImage.updatedAt,
                    "duplicate PNG publishes exact persisted updatedAt after willSave")
        CaptureProbe.historyText("capture OCR 接入")
        CaptureProbe.historyColor("#A1B2C3")
        try require(store.items.contains { $0.kind == .text && $0.plainText == "capture OCR 接入" && $0.payloads["public.utf8-plain-text"] == Data("capture OCR 接入".utf8) }, "real HistoryManager and Bridge forward text data shape")
        try require(store.items.contains { $0.kind == .color && $0.plainText == "#A1B2C3" && $0.payloads["public.utf8-plain-text"] == Data("#A1B2C3".utf8) }, "real HistoryManager and Bridge forward color data shape")
        let reopened = try ClipboardStore(directoryURL: root)
        var reopenDifferences: [String] = []
        for item in store.items {
            guard let reloaded = reopened.items.first(where: { $0.id == item.id }) else {
                throw Failure.assertion("missing persisted item \(item.id)")
            }
            let before = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
            let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reloaded)) as! [String: Any]
            for key in Set(before.keys).union(after.keys) {
                if String(describing: before[key]) != String(describing: after[key]) {
                    reopenDifferences.append("\(item.kind):\(key): \(String(describing: before[key])) -> \(String(describing: after[key]))")
                }
            }
            try require(reloaded.kind == item.kind && reloaded.plainText == item.plainText && reloaded.payloads == item.payloads,
                        "reopened persistent Store retains data shape: \(item.kind)")
            try require(reloaded.updatedAt == item.updatedAt, "reopened Store retains exact updatedAt: \(item.kind)")
        }
        try require(reopenDifferences.isEmpty, "all serialized PNG/text/color fields match after reopen")
        try require(reopened.items.count == store.items.count, "reopened Store preserves item count")
        guard let context = savedContext else { throw Failure.assertion("missing private Store context") }
        let stateRequest = NSFetchRequest<NSManagedObject>(entityName: "State")
        let beforeNoOpRevision = try context.fetch(stateRequest).first?.value(forKey: "revision") as? UUID
        let beforeNoOp = store.items
        let beforeNoOpSaves = saveCount
        var publishedItems = 0
        let publication = store.$items.dropFirst().sink { _ in publishedItems += 1 }
        defer { publication.cancel() }
        try store.save()
        let afterNoOpRevision = try context.fetch(stateRequest).first?.value(forKey: "revision") as? UUID
        try require(saveCount == beforeNoOpSaves && beforeNoOpRevision != nil && afterNoOpRevision == beforeNoOpRevision
                    && store.items == beforeNoOp && publishedItems == 0,
                    "unchanged save does not save, advance dates or publish items")

        let beforeRollback = store.items
        let beforeRollbackPublications = publishedItems
        var injectedFailure = false
        let failSave = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave,
            object: context, queue: nil) { _ in
                guard let target = context.updatedObjects.first(where: { $0.entity.name == "Item" }) else { return }
                // The production model requires Item.data. Trigger actual Core Data
                // validation failure so the production rollback path must run.
                target.setValue(nil, forKey: "data"); injectedFailure = true
            }
        var saveFailed = false
        do { try store.add(repeatedImage) } catch { saveFailed = true }
        NotificationCenter.default.removeObserver(failSave)
        try require(injectedFailure && saveFailed, "required Item.data failure reaches production save rollback")
        try require(store.items == beforeRollback && publishedItems == beforeRollbackPublications && !context.hasChanges,
                    "failed save rolls back managed changes and does not publish speculative items")
        let afterRollback = try ClipboardStore(directoryURL: root)
        // Compare read-time snapshots with read-time snapshots: ClipboardItem's
        // Equatable also includes non-archived native application projection flags.
        try require(afterRollback.items == reopened.items, "failed save leaves reopened persisted items unchanged")

        let syncDate = Date(timeIntervalSince1970: 4_000_000_000)
        var syncItem = repeatedImage; syncItem.updatedAt = syncDate
        let oldAuthor = context.transactionAuthor
        context.transactionAuthor = "syncApply"
        do { try store.add(syncItem) }
        catch { context.transactionAuthor = oldAuthor; throw error }
        context.transactionAuthor = oldAuthor
        let afterSync = try ClipboardStore(directoryURL: root)
        try require(store.items.first { $0.id == syncItem.id }?.updatedAt == syncDate
                    && afterSync.items.first { $0.id == syncItem.id }?.updatedAt == syncDate,
                    "syncApply preserves explicit incoming date in published and persisted items")
        try require(bridge.blinkclipImage(forLocator: URL(string: "https://example.invalid/not-a-history-item")!) == nil, "history bridge rejects foreign locator")

        CaptureProbe.failFullScreen = true
        let beforeFailure = store.items.count
        coordinator.startFullScreenCapture()
        GlobalHotKey.events.removeAll(); BlinkClipScreenshotSettings.requestHotKeyReload(); drain()
        try require(GlobalHotKey.events.count == 4 && store.items.count == beforeFailure,
                    "capture failure exit applies pending reload and creates no record")
        CaptureProbe.failFullScreen = false

        // 面板可见时触发区域截图：真实 `ScreenshotCoordinator` 必须先把面板移出屏幕，
        // 再创建遮罩（否则 capcap 在 init 抓的 pre-snapshot 会把面板截进底图），
        // 结束出口再把面板还回来。窗口识别走生产 `ScreenshotWindowHider` 的 identifier 规则。
        let capturePanel = NSPanel(contentRect: .init(x: 0, y: 0, width: 640, height: 200),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        capturePanel.identifier = NSUserInterfaceItemIdentifier("blinkclip-panel")
        capturePanel.isReleasedWhenClosed = false
        capturePanel.level = .mainMenu
        capturePanel.hidesOnDeactivate = false
        capturePanel.orderFront(nil)
        drain()
        try require(capturePanel.isVisible, "fixture panel starts visible before the screenshot hot key")
        var panelHiddenAtCaptureEntry: Bool?
        var panelVisibleAtCaptureEntry: Bool?
        var captureEntryRuns = 0
        CaptureProbe.onCaptureEntry = {
            captureEntryRuns += 1
            panelHiddenAtCaptureEntry = !capturePanel.isVisible
            panelVisibleAtCaptureEntry = capturePanel.isVisible
        }
        let actionsBeforePanelCapture = CaptureProbe.actions.count
        coordinator.startRegionCapture()
        drain()
        CaptureProbe.onCaptureEntry = nil
        try require(captureEntryRuns == 1 && CaptureProbe.actions.count == actionsBeforePanelCapture + 1,
                    "panel-visible trigger reaches the capture entry exactly once")
        try require(panelHiddenAtCaptureEntry == true && panelVisibleAtCaptureEntry == false,
                    "coordinator hides the visible panel before the capture entry snapshots the screen")
        CaptureProbe.complete(nil)
        drain()
        try require(capturePanel.isVisible, "capture exit restores the panel that the coordinator hid")
        var panelStayedVisibleWhileCaptureActive = true
        CaptureProbe.onCaptureEntry = { panelStayedVisibleWhileCaptureActive = capturePanel.isVisible }
        coordinator.startRegionCapture()
        drain()
        CaptureProbe.onCaptureEntry = nil
        try require(!panelStayedVisibleWhileCaptureActive, "repeated panel-visible capture also hides the panel")
        CaptureProbe.complete(nil)
        drain()
        try require(capturePanel.isVisible, "repeated capture restores the panel again")
        capturePanel.orderOut(nil)
        drain()

        let activationsBeforeStop = CaptureProbe.activations
        coordinator.startRegionCapture()
        coordinator.stop(); drain()
        try require(BlinkClipScreenshotSettings.lastRegistration.isEmpty && CaptureProbe.activations == activationsBeforeStop,
                    "stop clears registrations and cancels queued presentation")
        let stoppedCount = GlobalHotKey.events.count
        BlinkClipScreenshotSettings.requestHotKeyReload()
        try require(GlobalHotKey.events.count == stoppedCount, "stop removes settings observers")
        let report: [String: Any] = ["passed": true, "checks": checks, "count": checks.count,
            "reopen_field_differences": reopenDifferences,
            "duplicate_png_updated_at": ["first": saved.updatedAt.timeIntervalSince1970,
                "memory": repeatedImage.updatedAt.timeIntervalSince1970,
                "reopened": repeatedReopened.items.first { $0.id == saved.id }!.updatedAt.timeIntervalSince1970],
            "no_op_revision_unchanged": beforeNoOpRevision == afterNoOpRevision,
            "sync_apply_explicit_date": syncDate.timeIntervalSince1970,
            "real": ["ScreenshotSettings", "CaptureEntry", "HistoryManagerBridge", "ScreenshotCoordinator", "ScreenshotHistoryBridge", "ClipboardStore", "UserDefaults fresh-process reads", "private NSPasteboard", "ScreenshotWindowHider panel hide-before-capture and restore", "ReplicaToast shared 128x128 toast for copy/pause/resume/screenshot (window class/level/bottom geometry/CGWindowSharingState/centred content/reuse/action)"],
            "doubles": ["capcap OverlayWindowController/ScreenCapturer/ImageEditLauncher", "GlobalHotKey Carbon registration", "ScreenshotFocusRestorer", "ReplicaBrand constant"],
            "not_run": ["screen capture/editor internals", "real global Carbon delivery", "UI confirm-versus-save dispatch", "actual overlay draft internals", "focus restoration", "toast pixels inside a real captured image (asserted via hide-before-capture + sharingType)"]]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}
#endif
