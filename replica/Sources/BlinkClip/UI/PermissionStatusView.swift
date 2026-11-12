import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import os
import BlinkClipCore
import SwiftUI

enum PermissionCopy {
    static func text(_ chinese: String, _ english: String) -> String {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
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

    init(readAccessibility: (() -> Bool)? = nil,
         readPostEvents: (() -> Bool)? = nil,
         readScreenRecording: (() -> Bool)? = nil,
         requestScreenAccess: @escaping () -> Void = { _ = CGRequestScreenCaptureAccess() },
         openScreenSettings: (() -> Void)? = nil,
         requestAccessibilityAccess: (() -> Void)? = nil,
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
    var accessibilityStatus: String {
        if checkFailed { return PermissionCopy.text("检查失败，请重试", "Check failed; try again") }
        if !hasChecked { return PermissionCopy.text("正在检查…", "Checking…") }
        return accessibility ? PermissionCopy.text("已授权", "Granted") : PermissionCopy.text("未生效", "Not active")
    }
    var screenRecordingStatus: String {
        if checkFailed { return PermissionCopy.text("检查失败，请重试", "Check failed; try again") }
        if !hasChecked { return PermissionCopy.text("正在检查…", "Checking…") }
        return screenRecording ? PermissionCopy.text("已授权", "Granted") : PermissionCopy.text("未生效", "Not active")
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
                    || self.needsRestart != reading.needsRestart || self.checkFailed
                if self.accessibility != status.accessibility { self.accessibility = status.accessibility }
                if self.postEvents != status.postEvents { self.postEvents = status.postEvents }
                if self.screenRecording != status.screenRecording { self.screenRecording = status.screenRecording }
                if self.needsRestart != reading.needsRestart { self.needsRestart = reading.needsRestart }
                if !self.hasChecked { self.hasChecked = true }
                if changed {
                    self.logger.notice("status ax=\(status.accessibility, privacy: .public) post=\(status.postEvents, privacy: .public) screen=\(status.screenRecording, privacy: .public) fresh=\(reading.freshProcess != nil, privacy: .public) restart_required=\(reading.needsRestart, privacy: .public)")
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
        requestAccessibilityAccess()
        refresh()
    }

    func requestScreenRecording() {
        guard screenRequestTask == nil else { return }
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
            row(title: PermissionCopy.text("辅助功能", "Accessibility"),
                subtitle: PermissionCopy.text("直接粘贴到其他应用，以及滚动截图。", "Paste into other apps and capture scrolling content."),
                granted: model.accessibilityReady, identifier: "permission-accessibility", status: model.accessibilityStatus) {
                model.requestAccessibility()
            }
            Divider()
            row(title: PermissionCopy.text("屏幕录制", "Screen Recording"),
                subtitle: PermissionCopy.text("截取区域、窗口或整个屏幕。", "Capture a region, window, or full screen."),
                granted: model.screenRecording, identifier: "permission-screen-recording", status: model.screenRecordingStatus) {
                model.requestScreenRecording()
            }
            HStack {
                Text(PermissionCopy.text("返回应用后自动更新权限状态。", "Permission status updates automatically when you return."))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button(PermissionCopy.text("刷新状态", "Refresh Status")) { model.refresh() }
                    .accessibilityIdentifier("permission-refresh-status")
            }
            Text(PermissionCopy.text("未授权也可使用剪贴板历史。", "Clipboard history works without these permissions."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.needsRestart {
                Text(PermissionCopy.text("权限已开启，请退出并重新打开应用。", "Access is enabled. Quit and reopen this app to apply it."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.hasChecked && !model.statusUnknown && (!model.accessibility || !model.screenRecording) {
                DisclosureGroup(PermissionCopy.text("授权后仍不可用？", "Still unavailable after allowing access?")) {
                    Text(PermissionCopy.text("先退出并重新打开应用。若仍不可用，请在系统设置中移除旧的闪贴条目，再添加“应用程序”中的当前版本。", "Quit and reopen the app first. If access is still unavailable, remove the old BlinkClip entry in System Settings and add the current version from Applications."))
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            }
            if model.accessibility && !model.postEvents && !model.statusUnknown {
                Text(PermissionCopy.text("辅助功能已授权，但直接粘贴暂不可用。请退出并重新打开应用。", "Accessibility is granted, but direct paste is temporarily unavailable. Quit and reopen this app."))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(PermissionWindowBinding(changed: { model.bind(to: $0) }, visibilityChanged: { visible in
            if visible { model.start() } else { model.stop() }
        }).frame(width: 0, height: 0))
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private func row(title: String, subtitle: String, granted: Bool, identifier: String,
                     status: String? = nil, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Circle().fill(model.statusUnknown ? Color.gray : (granted ? Color.green : Color.red)).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(status ?? (granted ? PermissionCopy.text("已授权", "Granted") : PermissionCopy.text("未授权", "Not granted")))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }.accessibilityIdentifier(identifier + "-status")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(granted ? PermissionCopy.text("系统设置…", "System Settings…") : PermissionCopy.text("前往授权…", "Allow Access…"), action: action)
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
        window.title = PermissionCopy.text("欢迎使用闪贴", "Welcome to BlinkClip")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let content = PermissionGuideContent { [weak self] in self?.close() }
        window.contentView = NSHostingView(rootView: content)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
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
                Text(PermissionCopy.text("准备好常用功能", "Set up your everyday tools"))
                    .font(.title2.bold())
                Text(PermissionCopy.text("按需开启权限，随时可在设置中查看和修改。", "Enable the features you need. Review permissions anytime in Settings."))
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
                Button(PermissionCopy.text("继续使用", "Continue"), action: complete)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("permission-guide-continue")
            }
        }
        .padding(26)
        .frame(width: 520, height: 450)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
