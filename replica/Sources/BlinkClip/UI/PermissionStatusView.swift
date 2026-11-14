import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import os
import BlinkClipCore
import SwiftUI

/// Permission-page copy. All three languages are supplied at every call site and
/// resolved by the one shared `SettingsStrings` lookup, so `zh-Hant` never lands
/// on the Simplified string.
enum PermissionCopy {
    static func text(_ zhHans: String, _ zhHant: String, _ en: String) -> String {
        SettingsStrings.trilingual(zhHans, zhHant, en)
    }
}

@MainActor
final class PermissionStatusModel: ObservableObject {
    @Published private(set) var accessibility = false
    @Published private(set) var postEvents = false
    @Published private(set) var screenRecording = false
    @Published private(set) var needsRestart = false
    @Published private(set) var checkFailed = false
    @Published private(set) var hasChecked = false
    /// System Settings shows a tick but this build is still denied: the grant on
    /// record belongs to another build (ad-hoc / another certificate).
    @Published private(set) var requirementMismatch = false
    /// The user already pressed a 「前往授权」 button in this process, so a still
    /// denied status afterwards needs the remove-and-re-add steps spelled out
    /// instead of hidden behind a disclosure.
    @Published private(set) var requestedSystemSettings = false
    private(set) var isRefreshing = false
    private(set) var isRequestingScreen = false
    private var observations: [AnyCancellable] = []
    private var refreshTask: Task<Void, Never>?
    private var screenRequestTask: Task<Void, Never>?
    private var generation = 0
    private(set) var isObserving = false
    private weak var ownerWindow: NSWindow?
    private var hasBoundWindow = false
    private let logger = Logger(subsystem: "com.chrisli.blinkclip", category: "permissions")
    private let reader: () async -> PermissionStatusReading
    private let requestScreenAccess: () -> Void
    private let openScreenSettings: () -> Void
    private let requestAccessibilityAccess: () -> Void
    private let requestPostEventAccess: () -> Void
    private let willOpenSystemSettings: () -> Void

    init(readAccessibility: (() -> Bool)? = nil,
         readPostEvents: (() -> Bool)? = nil,
         readScreenRecording: (() -> Bool)? = nil,
         requestScreenAccess: @escaping () -> Void = { _ = CGRequestScreenCaptureAccess() },
         openScreenSettings: (() -> Void)? = nil,
         requestAccessibilityAccess: (() -> Void)? = nil,
         requestPostEventAccess: (() -> Void)? = nil,
         willOpenSystemSettings: (() -> Void)? = nil,
         readStatus: (() async -> PermissionStatusReading)? = nil) {
        if let readStatus { reader = readStatus }
        else if readAccessibility != nil || readPostEvents != nil || readScreenRecording != nil {
            // Injected previews/tests stay within this process and never launch themselves.
            reader = {
                let snapshot = PermissionStatusSnapshot(accessibility: readAccessibility?() ?? false,
                    postEvents: readPostEvents?() ?? false, screenRecording: readScreenRecording?() ?? false)
                return PermissionStatusReading(currentProcess: snapshot, freshProcess: nil, checkFailed: false)
            }
        } else { reader = { await PermissionStatusProbe.read() } }
        self.requestScreenAccess = requestScreenAccess
        self.requestAccessibilityAccess = requestAccessibilityAccess ?? { AccessibilityRequestAction.perform() }
        self.requestPostEventAccess = requestPostEventAccess ?? { AccessibilityRequestAction.performPostEvents() }
        self.willOpenSystemSettings = willOpenSystemSettings ?? {
            SettingsWindowFocusRestore.shared.expectReturnFromSystemSettings()
        }
        self.openScreenSettings = openScreenSettings ?? {
            AccessibilityRequestAction.openSettings(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        refresh()
    }

    deinit {
        refreshTask?.cancel()
        screenRequestTask?.cancel()
    }

    /// The Accessibility authorization row reports AX trust alone. Event posting
    /// is a separate operational capability and must not turn this grant red.
    var accessibilityReady: Bool { accessibility }
    var statusUnknown: Bool { !hasChecked || checkFailed }
    /// The row title already names the capability, so the status line only
    /// answers granted / not granted. Repeating the name after a colon read as
    /// a second permission and pushed users into System Settings looking for
    /// an entry that does not exist.
    var accessibilityStatus: String {
        if checkFailed { return PermissionCopy.text("检查失败，请重试", "檢查失敗，請重試", "Check failed; try again") }
        if !hasChecked { return PermissionCopy.text("正在检查…", "正在檢查…", "Checking…") }
        return accessibility
            ? PermissionCopy.text("已授权", "已授權", "Granted")
            : PermissionCopy.text("未授权", "未授權", "Not granted")
    }
    /// Event posting is answered from the same Accessibility grant, so it is
    /// reported inside the Accessibility row. The probe still reads it: a
    /// build that can read the UI but cannot post events gets one inline
    /// warning instead of a second row users cannot find in System Settings.
    var postEventsHint: String? {
        guard hasChecked, !checkFailed, accessibility, !postEvents else { return nil }
        return PermissionCopy.text("发送事件权限未就绪，请重新勾选辅助功能。", "傳送事件權限尚未就緒，請重新勾選輔助功能。",
                                   "Sending events is not ready; re-tick Accessibility.")
    }
    var screenRecordingStatus: String {
        if checkFailed { return PermissionCopy.text("检查失败，请重试", "檢查失敗，請重試", "Check failed; try again") }
        if !hasChecked { return PermissionCopy.text("正在检查…", "正在檢查…", "Checking…") }
        return screenRecording
            ? PermissionCopy.text("已授权", "已授權", "Granted")
            : PermissionCopy.text("未授权", "未授權", "Not granted")
    }

    func refresh() {
        guard refreshTask == nil else { return }
        generation += 1
        let ticket = generation
        if !isRefreshing { isRefreshing = true }
        refreshTask = Task { [weak self, reader] in
            let reading = await reader()
            guard let self, !Task.isCancelled, ticket == self.generation else { return }
            // A failed fresh check is not a denial, and must not replace the last
            // confirmed state with stale current-process cache values.
            if !reading.checkFailed {
                let status = reading.authorization
                let changed = !self.hasChecked || self.accessibility != status.accessibility
                    || self.postEvents != status.postEvents || self.screenRecording != status.screenRecording
                    || self.requirementMismatch != reading.requirementMismatch
                    || self.needsRestart != reading.needsRestart || self.checkFailed
                if self.accessibility != status.accessibility { self.accessibility = status.accessibility }
                if self.postEvents != status.postEvents { self.postEvents = status.postEvents }
                if self.screenRecording != status.screenRecording { self.screenRecording = status.screenRecording }
                if self.requirementMismatch != reading.requirementMismatch {
                    self.requirementMismatch = reading.requirementMismatch
                }
                if self.needsRestart != reading.needsRestart { self.needsRestart = reading.needsRestart }
                if !self.hasChecked { self.hasChecked = true }
                if changed {
                    self.logger.notice("status ax=\(status.accessibility, privacy: .public) post=\(status.postEvents, privacy: .public) screen=\(status.screenRecording, privacy: .public) fresh=\(reading.freshProcess != nil, privacy: .public) restart_required=\(reading.needsRestart, privacy: .public) requirement_mismatch=\(reading.requirementMismatch, privacy: .public)")
                }
            }
            if reading.checkFailed && !self.checkFailed { self.logger.notice("status_check_failed=true") }
            if self.checkFailed != reading.checkFailed { self.checkFailed = reading.checkFailed }
            self.isRefreshing = false
            self.refreshTask = nil
        }
    }

    func bind(to window: NSWindow?) {
        hasBoundWindow = true
        ownerWindow = window
        if isObserving, window?.isVisible == true { refresh() }
    }

    func start() {
        guard !isObserving else { return }
        isObserving = true
        refresh()
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification] {
            center.publisher(for: name).sink { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard !self.hasBoundWindow || self.ownerWindow?.isVisible == true else { return }
                    if name == NSWindow.didBecomeKeyNotification,
                       let window = self.ownerWindow, notification.object as? NSWindow !== window { return }
                    self.refresh()
                }
            }.store(in: &observations)
        }
        center.publisher(for: NSWindow.willCloseNotification).sink { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let window = self.ownerWindow,
                      notification.object as? NSWindow === window else { return }
                self.stop()
            }
        }.store(in: &observations)
        Timer.publish(every: 3, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in MainActor.assumeIsolated {
                guard let self, !self.hasBoundWindow || self.ownerWindow?.isVisible == true else { return }
                self.refresh()
            }}.store(in: &observations)
    }

    func stop() {
        isObserving = false
        observations.removeAll()
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        screenRequestTask?.cancel()
        screenRequestTask = nil
        isRequestingScreen = false
        if isRefreshing { isRefreshing = false }
    }

    func requestAccessibility() {
        requestedSystemSettings = true
        willOpenSystemSettings()
        requestAccessibilityAccess()
        refresh()
    }

    /// "Send events to other apps" (direct paste) is its own TCC capability on
    /// macOS 14+: a green Accessibility row does not imply it, so it gets its own
    /// request path instead of reusing the Accessibility branch.
    func requestPostEvents() {
        requestedSystemSettings = true
        willOpenSystemSettings()
        requestPostEventAccess()
        refresh()
    }

    func requestScreenRecording() {
        guard screenRequestTask == nil else { return }
        requestedSystemSettings = true
        willOpenSystemSettings()
        refresh()
        let check = refreshTask
        isRequestingScreen = true
        screenRequestTask = Task { [weak self] in
            await check?.value
            guard let self, !Task.isCancelled else { return }
            if !self.screenRecording { self.requestScreenAccess() }
            self.openScreenSettings()
            self.screenRequestTask = nil
            self.isRequestingScreen = false
            self.refresh()
        }
    }
}

@MainActor
struct PermissionStatusView: View {
    @StateObject private var model: PermissionStatusModel

    init(model: PermissionStatusModel? = nil) {
        _model = StateObject(wrappedValue: model ?? PermissionStatusModel())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // macOS grants Accessibility and Screen Recording independently.
            // Event posting (direct paste) is answered from the Accessibility
            // grant — `CGPreflightPostEventAccess()` reports the same source —
            // so it stays inside this row instead of a second row that sends
            // users looking for a permission System Settings never lists.
            row(title: PermissionCopy.text("辅助功能", "輔助功能", "Accessibility"),
                subtitle: PermissionCopy.text("读取其他应用的界面（滚动截图、读取内容），并向其他应用发送键盘事件（直接粘贴）。", "讀取其他應用程式的介面（捲動截圖、讀取內容），並向其他應用程式傳送鍵盤事件（直接貼上）。", "Read other apps' interface (scrolling capture, reading content) and send keyboard events to other apps (direct paste)."),
                granted: model.accessibilityReady, identifier: "permission-accessibility",
                status: model.accessibilityStatus, hint: model.postEventsHint) {
                model.requestAccessibility()
            }
            Divider()
            row(title: PermissionCopy.text("屏幕录制", "螢幕錄製", "Screen Recording"),
                subtitle: PermissionCopy.text("截取区域、窗口或整个屏幕。", "擷取區域、視窗或整個螢幕。", "Capture a region, window, or full screen."),
                granted: model.screenRecording, identifier: "permission-screen-recording", status: model.screenRecordingStatus) {
                model.requestScreenRecording()
            }
            Divider()
            HStack {
                Spacer(minLength: 8)
                Button(PermissionCopy.text("刷新状态", "重新整理狀態", "Refresh Status")) { model.refresh() }
                    .accessibilityIdentifier("permission-refresh-status")
            }
            if showsRemediation {
                staleRequirementCard
            } else if model.hasChecked && !model.statusUnknown
                        && (!model.accessibility || !model.postEvents || !model.screenRecording) {
                DisclosureGroup(PermissionCopy.text("授权后仍不可用？", "授權後仍無法使用？", "Still unavailable after allowing access?")) {
                    Text(remediationSteps)
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            }
        }
        .background(PermissionWindowBinding(changed: { model.bind(to: $0) }, visibilityChanged: { visible in
            if visible { model.start() } else { model.stop() }
        }).frame(width: 0, height: 0))
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    /// A denied status is worth spelling out instead of hiding behind a
    /// disclosure once the app can either prove the grant belongs to another
    /// build, or the user already went to System Settings for it.
    private var showsRemediation: Bool {
        guard model.hasChecked, !model.statusUnknown else { return false }
        let denied = !model.accessibility || !model.postEvents || !model.screenRecording
        return denied && (model.requirementMismatch || model.requestedSystemSettings)
    }

    private var remediationSteps: String {
        PermissionCopy.text("若系统设置里已勾选闪贴但仍显示未生效，列表里那条授权很可能属于旧版本：先在该列表中用“−”移除闪贴，再用“+”添加 \(Bundle.main.bundlePath)，然后勾选新增的条目。退出并重新打开应用后仍不生效时按同样步骤处理。", "若系統設定裡已勾選閃貼但仍顯示未生效，列表裡那條授權很可能屬於舊版本：先在該列表中用「−」移除閃貼，再用「+」加入 \(Bundle.main.bundlePath)，然後勾選新增的項目。結束並重新開啟應用程式後仍不生效時，請依相同步驟處理。", "If BlinkClip is already ticked in System Settings but this page still shows it inactive, that entry most likely belongs to an older build: remove it with “−”, add \(Bundle.main.bundlePath) again with “+”, then tick the new entry. Do the same if quitting and reopening the app does not help.")
    }

    /// Shown when the app can prove the grant on record was issued to a different
    /// build (or the user has just come back from System Settings without a
    /// grant). The only fix is to remove the old list entry and add this bundle.
    private var staleRequirementCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.requirementMismatch
                 ? PermissionCopy.text("系统设置里已勾选，但当前版本仍被拒绝", "系統設定裡已勾選，但目前版本仍被拒絕", "Ticked in System Settings, still refused")
                 : PermissionCopy.text("授权后仍不可用？", "授權後仍無法使用？", "Still unavailable after allowing access?"))
                .font(.system(size: 12, weight: .semibold))
            Text(model.requirementMismatch
                 ? PermissionCopy.text("系统里那条授权属于旧版本（旧签名），当前版本对不上。请按顺序操作：1）在“辅助功能”列表中选中闪贴，点“−”移除；2）点“+”重新添加 \(Bundle.main.bundlePath)；3）勾选新增的条目。完成一次后，之后用同一 Developer ID 身份更新不再需要重做。", "系統裡那條授權屬於舊版本（舊簽章），與目前版本不符。請依序操作：1）在「輔助功能」列表中選取閃貼，按「−」移除；2）按「+」重新加入 \(Bundle.main.bundlePath)；3）勾選新增的項目。完成一次後，之後用同一 Developer ID 身分更新就不需要重做。", "That grant belongs to an older build (a different signature) and cannot match this one. In order: 1) select BlinkClip in the Accessibility list and remove it with “−”; 2) add \(Bundle.main.bundlePath) again with “+”; 3) tick the new entry. After doing this once, updates signed with the same Developer ID identity keep the grant.")
                 : remediationSteps)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(PermissionCopy.text("打开辅助功能设置…", "開啟輔助功能設定…", "Open Accessibility Settings…")) {
                    model.requestAccessibility()
                }
                .accessibilityIdentifier("permission-requirement-mismatch-settings")
                Button(PermissionCopy.text("在访达中显示应用", "在 Finder 中顯示應用程式", "Show App in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                .accessibilityIdentifier("permission-requirement-mismatch-reveal")
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("permission-requirement-mismatch")
    }

    private func row(title: String, subtitle: String, granted: Bool, identifier: String,
                     status: String? = nil, hint: String? = nil, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Circle().fill(model.statusUnknown ? Color.gray : (granted ? Color.green : Color.red)).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(status ?? (granted ? PermissionCopy.text("已授权", "已授權", "Granted") : PermissionCopy.text("未授权", "未授權", "Not granted")))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier(identifier + "-status")
                if let hint {
                    // One inline warning for the rare build whose UI access is
                    // granted while event posting is not: still one row, never
                    // a capability users cannot find in System Settings.
                    Text(hint)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(identifier + "-hint")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(granted ? PermissionCopy.text("系统设置…", "系統設定…", "System Settings…") : PermissionCopy.text("前往授权…", "前往授權…", "Allow Access…"), action: action)
                .accessibilityIdentifier(identifier + "-request")
        }
    }
}

private struct PermissionWindowBinding: NSViewRepresentable {
    let changed: (NSWindow?) -> Void
    let visibilityChanged: (Bool) -> Void
    func makeNSView(context: Context) -> BindingView {
        let view = BindingView()
        view.changed = changed
        view.visibilityChanged = visibilityChanged
        return view
    }
    func updateNSView(_ view: BindingView, context: Context) {
        view.changed = changed
        view.visibilityChanged = visibilityChanged
    }
    final class BindingView: NSView {
        var changed: ((NSWindow?) -> Void)?
        var visibilityChanged: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
            changed?(window)
            if let window {
                for name in [NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification,
                             NSWindow.willCloseNotification] {
                    observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.visibilityChanged?(name != NSWindow.willCloseNotification
                                && self.window?.isVisible == true && !self.isHiddenOrHasHiddenAncestor)
                        }
                    })
                }
            }
            visibilityChanged?(window?.isVisible == true && !isHiddenOrHasHiddenAncestor)
        }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }
    }
}

@MainActor
final class PermissionGuideWindowController: NSWindowController, NSWindowDelegate {
    private let directory: URL

    init(directory: URL) {
        self.directory = directory
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 450),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = PermissionCopy.text("欢迎使用闪贴", "歡迎使用閃貼", "Welcome to BlinkClip")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let content = PermissionGuideContent { [weak self] in self?.close() }
        window.contentView = NSHostingView(rootView: content)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        // The guide's buttons use the same permission flow, so it can be the
        // window that has to come back after the user visits System Settings.
        SettingsWindowFocusRestore.shared.attach(to: window)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        PermissionGuidePersistence.complete(directory: directory)
    }
}

@MainActor
struct PermissionGuideContent: View {
    let complete: () -> Void
    var statusModel: PermissionStatusModel? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text(PermissionCopy.text("准备好常用功能", "準備好常用功能", "Set up your everyday tools"))
                    .font(.title2.bold())
                Text(PermissionCopy.text("按需开启权限，随时可在设置中查看和修改。", "依需求開啟權限，隨時可在設定中檢視和修改。", "Enable the features you need. Review permissions anytime in Settings."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                PermissionStatusView(model: statusModel)
                    .padding(.trailing, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Spacer()
                Button(PermissionCopy.text("继续使用", "繼續使用", "Continue"), action: complete)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("permission-guide-continue")
            }
        }
        .padding(26)
        .frame(width: 520, height: 450)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
