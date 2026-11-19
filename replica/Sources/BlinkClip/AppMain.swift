import AppKit
import ApplicationServices
import Combine
import os
import BlinkClipCore

@main
enum BlinkClipMain {
    @MainActor static func main() {
        if let status = PermissionProbeCommand.handleIfRequested() { exit(status) }
        let application = NSApplication.shared
        let delegate = ReplicaAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class ReplicaAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var store: ClipboardStore!
    private var ui: ReplicaUIController!
    private lazy var inAppUpdater = BlinkClipInAppUpdater()
    private var monitor: ClipboardMonitor?
    private var soundEffects: SoundEffects?
    private var diagnostics: DiagnosticsManager?
    private var diagnosticsObservation: AnyCancellable?
    private let accessibilityService = AccessibilityService()
    private var accessibilityObservation: AnyCancellable?
    private var permissionGuide: PermissionGuideWindowController?
    private var permissionPromptPolicy = PermissionPromptPolicy()
    private let hotKey = GlobalHotKey()
    private let stackHotKey = GlobalHotKey()
    private let stackPasteHotKey = GlobalHotKey()
    private var screenshotCoordinator: ScreenshotCoordinator?
    private var stackPasteRegistered = false
    private var statusItem: NSStatusItem!
    private var targetApplication: NSRunningApplication?
    private var handoffPreviousApplication: NSRunningApplication?
    private let pasteLogger = Logger(subsystem: "com.chrisli.blinkclip", category: "direct-paste")
    private var activationObserver: NSObjectProtocol?
    private var refreshTimer: Timer?
    private var pausePreferencesObservation: AnyCancellable?
    private var pauseResumeTimer: Timer?
    private var scheduledResumeDate: Date?
    private var lastPauseFlag: Bool?
    private var networkSpeedObservation: AnyCancellable?
    private var hotKeyStatus: OSStatus = noErr
    private var stackHotKeyStatus: OSStatus = noErr
    private var hotKeyObservation: AnyCancellable?
    private var lastHotKeyConfiguration: [KeyboardShortcut?]?
    private var isRecordingHotKey = false
    private let arguments = ProcessInfo.processInfo.arguments
    private var pasteboard: NSPasteboard = .general

    private func argument(_ name: String) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            for flag in ["--data-dir", "--pasteboard-name"] where arguments.contains(flag) {
                guard let value = argument(flag), !value.isEmpty, !value.hasPrefix("--") else {
                    throw NSError(domain: "BlinkClipArguments", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "\(flag) 必须提供有效的值。"])
                }
            }
            if arguments.contains("--fixture"), argument("--data-dir") == nil {
                throw NSError(domain: "BlinkClipArguments", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "--fixture 必须搭配独立的 --data-dir。"])
            }
            if let name = argument("--pasteboard-name") {
                guard name != "general", name != NSPasteboard.Name.general.rawValue else {
                    throw NSError(domain: "BlinkClipArguments", code: 3,
                                  userInfo: [NSLocalizedDescriptionKey: "--pasteboard-name 只支持具名私有剪贴板。"])
                }
                pasteboard = NSPasteboard(name: .init(name))
            } else if arguments.contains("--fixture") {
                pasteboard = NSPasteboard(name: .init("blinkclip-fixture-\(UUID().uuidString)"))
            }
            let directory = argument("--data-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? ClipboardStore.defaultDirectoryURL
            store = try ClipboardStore(directoryURL: directory)
            BlinkClipAppIntentStore.configure(store: store)
            diagnostics = DiagnosticsManager.makeLocal(
                logDirectory: directory.appendingPathComponent("Diagnostics", isDirectory: true)
            ) { [weak self] enabled in
                guard let self, self.store.preferences.isDiagnosticsEnabled != enabled else { return }
                self.store.preferences.isDiagnosticsEnabled = enabled
                do { try self.store.save() }
                catch { self.ui?.presentError(error) }
            }
            diagnostics?.setDiagnosticsEnabled(store.preferences.isDiagnosticsEnabled)
            diagnosticsObservation = store.$preferences.map(\.isDiagnosticsEnabled).removeDuplicates().sink { [weak self] _ in
                // @Published emits before storage changes; resolve the committed preference next turn.
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.diagnostics?.setDiagnosticsEnabled(self.store.preferences.isDiagnosticsEnabled)
                }
            }
            try store.save()
            if arguments.contains("--fixture"), store.items.isEmpty { try seedFixture() }
            ui = ReplicaUIController(store: store)
            if argument("--data-dir") == nil, !arguments.contains("--fixture") {
                ui.state.cloudSync.start()
                ui.state.originalCloudSync.start()
            }
            ui.pasteboard = pasteboard
            ui.pasteHandler = { [weak self] id, plain in self?.paste(id: id, plain: plain) ?? false }
            ui.pasteItemsHandler = { [weak self] ids, plain in self?.paste(ids: ids, plain: plain) ?? false }
            ui.directPasteItemsHandler = { [weak self] ids, plain in
                self?.paste(ids: ids, plain: plain, forceDirect: true) ?? false
            }
            ui.pasteRestoreItemsHandler = { [weak self] items, plain, forceDirect in
                self?.paste(ids: items.map(\.id), plain: plain, forceDirect: forceDirect, restoreItems: items) ?? false
            }
            ui.panelDidShow = { [weak self] in self?.rememberPanelApplication() }
            ui.panelWillClose = { [weak self] restore in self?.restorePanelApplication(restore: restore) }
            ui.copiedItemsHandler = {
                ReplicaCopiedOSD.showCopied()
                NSApp.deactivate()
            }
            ui.hotKeyConfigurationChanged = { [weak self] in self?.configureGlobalHotKeys() }
            ui.stackDidChange = { [weak self] in self?.configureStackPasteShortcut() }
            ui.hotKeyRecordingChanged = { [weak self] recording in
                guard let self else { return }
                self.isRecordingHotKey = recording
                if recording { self.hotKey.unregister(); self.stackHotKey.unregister(); self.updateStatus() }
                else { self.configureGlobalHotKeys(force: true) }
                self.configureStackPasteShortcut()
            }
            setupMenus()
            targetApplication = NSWorkspace.shared.frontmostApplication
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                MainActor.assumeIsolated { self?.targetApplication = app }
            }
            if !arguments.contains("--no-monitor") {
                monitor = ClipboardMonitor(store: store, pasteboard: pasteboard)
            }
            soundEffects = SoundEffects(store: store, monitor: monitor)
            ReplicaCopiedOSD.pauseStatus = { [weak self] in
                guard let self, self.monitor != nil,
                      let capture = PasteboardCaptureState.current(for: self.pasteboard) else { return nil }
                return capture.pollTimer == nil
            }
            ui.state.monitoringPauseChanged = { [weak self] in self?.configurePauseMonitoring() }
            configurePauseMonitoring()
            pausePreferencesObservation = store.$preferences.sink { [weak self] _ in
                // @Published fires before the two pause fields finish changing.
                DispatchQueue.main.async { self?.configurePauseMonitoring() }
            }
            hotKey.action = { [weak self] in self?.togglePanel(nil) }
            stackHotKey.action = { [weak self] in
                guard let self else { return }
                // 面板可见时这条热键**不再注销**（注销后 Carbon 收不到按键，面板内的 ⇧⌘C
                // 也会一起失效）。面板 key window 下的「复制为纯文本」语义由
                // `StackHotKeyRouting` 决定，和 `ReplicaUIController.handleKey` 的
                // `CollectionShortcutActions.copyOptions` 对齐。
                switch StackHotKeyRouting.route(
                    isAppActive: NSApp.isActive,
                    isPanelKeyWindow: self.ui.isPanelKeyWindow,
                    isDefaultStackShortcut: self.store.preferences.stackShortcut == .stackDefault) {
                case .copySelection: self.ui.copySelection(plainTextOnly: true)
                case .showStack: self.ui.showStack()
                }
            }
            hotKeyObservation = store.$preferences.sink { [weak self] _ in
                // @Published 在赋值前通知，下一轮读取完整的新偏好。
                DispatchQueue.main.async { self?.configureGlobalHotKeys() }
            }
            stackPasteHotKey.action = { [weak self] in
                guard let self else { return }
                if NSApp.isActive {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                    return
                }
                guard let first = self.ui.state.stackItemIDs.first else { return }
                let input = self.ui.state.stackRestoreItem(for: first)
                self.targetApplication = NSWorkspace.shared.frontmostApplication
                self.ui.consumeStackHead()
                // Stack 粘贴走的是 `AppMain.paste` 这条直连路径，不经过
                // `ReplicaUIController.paste`（那里由 UI 层声明 `.paste`），所以动作必须
                // 在调用点自己声明，否则这次写入会被当成未分类成功，回落到系统 Purr。
                // 粘贴成功同样补一次「置顶」，与面板内所有粘贴路径的约定一致。
                let pasted = SoundEffects.withFeedback(.paste) {
                    self.paste(ids: [first], plain: false, forceDirect: true, restoreItems: input.map { [$0] })
                }
                if pasted { self.ui.state.movePastedItemToFront(first) }
                if self.ui.state.stackItemIDs.isEmpty { self.ui.hideStack() }
            }
            configureGlobalHotKeys(force: true)
            screenshotCoordinator = ScreenshotCoordinator(store: store, pasteboard: pasteboard)
            screenshotCoordinator?.start()
            accessibilityObservation = accessibilityService.trustedStatusPublisher().sink { [weak self] _ in
                MainActor.assumeIsolated { self?.configureStackPasteShortcut() }
            }
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    do { try self.store.reload() }
                    catch { self.statusItem.button?.toolTip = "无法刷新历史：\(error.localizedDescription)" }
                }
            }
            updateStatus()
            if argument("--data-dir") == nil { BackgroundService.markRunning(true) }
            if arguments.contains("--show-panel") { ui.showPanel() }
            if arguments.contains("--show-settings") { ui.showSettings() }
            // Isolated fixtures and custom stores never introduce an extra window.
            // Only a normal first launch shows the guide; it never requests TCC itself.
            if argument("--data-dir") == nil, !arguments.contains("--fixture"),
               PermissionGuidePersistence.shouldShow(directory: store.directoryURL) {
                permissionGuide = PermissionGuideWindowController(directory: store.directoryURL)
                DispatchQueue.main.async { [weak self] in self?.permissionGuide?.present() }
            }
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "",
                          modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        ui?.showPanel()
        return true
    }

    private func setupMenus() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = ReplicaBrand.menuBarImage()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        // 菜单栏网速：文字与现有图标共用这一颗 NSStatusBarButton，点击/右键行为不变。
        // 开关关闭时渲染器只把标题清空、宽度收回 squareLength，没有任何后台定时器。
        NetworkSpeedStatusItem.apply(to: statusItem, enabled: NetworkSpeedMonitor.shared.snapshot.isEnabled,
                                     rates: NetworkSpeedMonitor.shared.snapshot.rates,
                                     unit: NetworkSpeedMonitor.shared.unit)
        networkSpeedObservation = NetworkSpeedMonitor.shared.$snapshot
            .removeDuplicates()
            .sink { [weak self] snapshot in
                MainActor.assumeIsolated { self?.renderNetworkSpeed(snapshot) }
            }
        if NetworkSpeedMonitor.shared.snapshot.isEnabled { NetworkSpeedMonitor.shared.start() }
        ui.panelToggleButton = statusItem.button
        let main = NSMenu()
        let appMenu = NSMenu(title: ReplicaBrand.name)
        appMenu.addItem(menuItem("关于 \(ReplicaBrand.name)", #selector(about(_:))))
        appMenu.addItem(menuItem("设置…", #selector(settings(_:)), key: ","))
        appMenu.addItem(menuItem(diagnosticsMenuTitle, #selector(toggleDiagnostics(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("退出 \(ReplicaBrand.name)", #selector(quit(_:)), key: "q"))
        let app = NSMenuItem(); app.submenu = appMenu; main.addItem(app)
        let file = NSMenu(title: "文件")
        file.addItem(menuItem("新建文本…", #selector(newText(_:)), key: "n"))
        file.addItem(menuItem(SearchLocalization.text("blinkclip.action.create-group") + "…", #selector(newBoard(_:)), key: "n", modifiers: [.command, .shift]))
        file.addItem(.separator())
        file.addItem(menuItem("导入…", #selector(importArchive(_:))))
        file.addItem(menuItem("导出…", #selector(exportArchive(_:))))
        file.addItem(.separator())
        file.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: ""); fileItem.submenu = file; main.addItem(fileItem)
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"),
                                        ("拷贝", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(selector), keyEquivalent: key))
        }
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: ""); editItem.submenu = edit; main.addItem(editItem)
        let view = NSMenu(title: "显示")
        view.addItem(menuItem("剪贴板历史", #selector(togglePanel(_:))))
        view.addItem(menuItem("搜索", #selector(search(_:)), key: "f"))
        view.addItem(menuItem("\(ReplicaBrand.name) Stack", #selector(stack(_:))))
        let viewItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: ""); viewItem.submenu = view; main.addItem(viewItem)
        NSApp.mainMenu = main
    }

    /// 把采集快照落到状态栏：文字/宽度由渲染器负责，tooltip 与热键状态共用一份。
    private func renderNetworkSpeed(_ snapshot: NetworkSpeedMonitor.Snapshot) {
        NetworkSpeedStatusItem.apply(to: statusItem, enabled: snapshot.isEnabled,
                                     rates: snapshot.rates, unit: snapshot.unit)
        // 只刷新 tooltip；热键状态文案不必每秒重算一次。
        applyStatusToolTip()
    }

    private func updateStatus() {
        if arguments.contains("--no-global-hotkey") {
            ui.hotKeyStatusMessage = ScreenshotSettingsCopy.text(.hotKeysDisabledForRun)
        } else if isRecordingHotKey {
            ui.hotKeyStatusMessage = "正在录制快捷键，全局快捷键暂时停用。"
        } else {
            func message(_ title: String, _ shortcut: KeyboardShortcut?, _ status: OSStatus) -> String {
                guard let shortcut else { return "\(title)：未设置" }
                return status == noErr ? "\(title)：\(shortcut.displayName)" : "\(title)：\(shortcut.displayName) 无法注册（可能已被占用，错误 \(status)）"
            }
            ui.hotKeyStatusMessage = [message("历史", store.preferences.historyShortcut, hotKeyStatus),
                                      message("\(ReplicaBrand.name) Stack", store.preferences.stackShortcut, stackHotKeyStatus)].joined(separator: "；")
        }
        applyStatusToolTip()
    }

    private func applyStatusToolTip() {
        let baseTooltip = "\(ReplicaBrand.name) · \(ui.hotKeyStatusMessage)"
        if NetworkSpeedMonitor.shared.snapshot.isEnabled {
            // 网速打开时 tooltip 先给完整速度（B/s 或 bps），下一行仍保留原有的
            // 快捷键状态，不因为新功能丢掉旧信息。
            let speed = NetworkSpeedStatusItem.toolTip(rates: NetworkSpeedMonitor.shared.snapshot.rates,
                                                       unit: NetworkSpeedMonitor.shared.unit)
            statusItem.button?.toolTip = "\(speed)\n\(baseTooltip)"
        } else {
            statusItem.button?.toolTip = baseTooltip
        }
    }

    private func configureGlobalHotKeys(force: Bool = false) {
        guard !isRecordingHotKey else { updateStatus(); return }
        let configuration = [store.preferences.historyShortcut, store.preferences.stackShortcut]
        guard force || configuration != lastHotKeyConfiguration else { return }
        lastHotKeyConfiguration = configuration
        hotKey.unregister(); stackHotKey.unregister()
        func register(_ shortcut: KeyboardShortcut?, with hotKey: GlobalHotKey, identifier: UInt32) -> OSStatus {
            guard let shortcut else { return noErr }
            guard shortcut.isValidGlobal else { return OSStatus(-50) }
            return hotKey.register(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers, identifier: identifier)
        }
        if !arguments.contains("--no-global-hotkey") {
            hotKeyStatus = register(configuration[0], with: hotKey, identifier: 1)
            stackHotKeyStatus = register(configuration[1], with: stackHotKey, identifier: 2)
        } else { hotKeyStatus = noErr; stackHotKeyStatus = noErr }
        updateStatus()
    }

    // 面板可见性**不再参与**全局热键的注册生命周期。
    //
    // 这里曾经有 `installPanelVisibilityObservation` + `panelVisibilityChanged(_:)`：
    // 面板一显示就 `stackHotKey.unregister()`、收起再注册，注释写的是「面板内的 ⇧⌘C
    // 是复制、不是打开 Stack」。但 Panel 是 `NSPanel(.nonactivatingPanel)`，Carbon 热键
    // 是唯一入口：注销之后按键既到不了 `AppMain`，也到不了 `ReplicaPanel.keyHandler`，
    // 面板可见期间的 ⇧⌘C 就此彻底失效（`stackHotKey.action` 里的 `.copySelection` 分支
    // 变成死代码）。语义分歧改由 `StackHotKeyRouting` 在动作里判断，注册保持不动。

    private func configureStackPasteShortcut() {
        let enabled = ui.isStackVisible && !ui.state.stackItemIDs.isEmpty && !isRecordingHotKey
            && !arguments.contains("--no-global-hotkey") && pasteboard.name == NSPasteboard.general.name
        guard enabled != stackPasteRegistered else { return }
        stackPasteHotKey.unregister()
        stackPasteRegistered = false
        if enabled {
            stackPasteRegistered = stackPasteHotKey.register(keyCode: 9, modifiers: .command, identifier: 3) == noErr
            if !stackPasteRegistered { ui.hotKeyStatusMessage = "\(ReplicaBrand.name) Stack 的 ⌘V 无法注册，请使用项目菜单粘贴。" }
        }
    }

    /// 底部快捷菜单每次右键现取状态重建：分组、图标、动作与置灰都来自模型
    /// （`PanelShortcutMenuModel`），这里只负责把当前状态塞进去。
    private var panelShortcutMenuContext: PanelShortcutMenuContext {
        PanelShortcutMenuContext(
            productName: ReplicaBrand.name,
            isMonitoringPaused: store.preferences.isMonitoringPaused,
            diagnosticsTitle: diagnosticsMenuTitle,
            hotKeyNotice: hotKeyStatus != noErr ? "历史快捷键无法注册" : nil,
            stackHotKeyNotice: stackHotKeyStatus != noErr
                ? "\(ReplicaBrand.name) Stack 快捷键无法注册" : nil)
    }

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = PanelShortcutMenuBuilder.makeMenu(panelShortcutMenuContext, target: self)
            let show = {
                self.statusItem.menu = menu
                self.statusItem.button?.performClick(nil)
                self.statusItem.menu = nil
            }
            if let screenshotCoordinator {
                screenshotCoordinator.trackStatusMenu(menu, show: show)
            } else {
                show()
            }
        } else { togglePanel(sender) }
    }

    private var diagnosticsMenuTitle: String {
        String(localized: diagnostics?.enabled == true
            ? PreviewLocalization.diagnosticsStopTitle() : PreviewLocalization.diagnosticsStartTitle())
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleDiagnostics(_:)) {
            menuItem.title = diagnosticsMenuTitle
            return diagnostics != nil
        }
        return true
    }

    @objc private func toggleDiagnostics(_ sender: Any?) { toggleDiagnostics() }

    private func toggleDiagnostics() {
        guard let diagnostics else { return }
        let wasEnabled = diagnostics.enabled
        let alert = NSAlert()
        alert.messageText = String(localized: wasEnabled
            ? PreviewLocalization.diagnosticsStopTitle() : PreviewLocalization.diagnosticsStartTitle())
        alert.informativeText = ReplicaBrand.replacingName(in: String(localized: wasEnabled
            ? PreviewLocalization.diagnosticsStopMessage() : PreviewLocalization.diagnosticsStartMessage()))
        alert.addButton(withTitle: ReplicaBrand.replacingName(in: String(localized: wasEnabled
            ? PreviewLocalization.diagnosticsActionStopAndCopyLogs() : PreviewLocalization.generalActionRestartPaste())))
        alert.addButton(withTitle: String(localized: PreviewLocalization.generalActionCancel()))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if wasEnabled {
            diagnostics.setDiagnosticsEnabled(false)
            do {
                if try diagnostics.captureDiagnosticsFile(store: store, pasteboard: pasteboard) != nil {
                    ReplicaCopiedOSD.showCopied()
                }
            }
            catch { ui.presentError(error) }
        } else {
            diagnostics.setDiagnosticsEnabled(true)
            DiagnosticsAppActions.relaunchAppAndExit()
        }
    }

    @objc private func togglePanel(_ sender: Any?) {
        rememberPasteTargetBeforeOpeningPanel()
        ui.togglePanel()
    }
    private func rememberPanelApplication() {
        // after showing, sample before activation.
        let app = NSWorkspace.shared.frontmostApplication
        if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            handoffPreviousApplication = app
        }
        NSApp.activate()
    }

    private func restorePanelApplication(restore: Bool) {
        // restore onWillClose, then clear the saved application.
        defer { handoffPreviousApplication = nil }
        guard restore, let previous = handoffPreviousApplication,
              previous.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        previous.activate(options: .activateIgnoringOtherApps)
    }

    private func rememberPasteTargetBeforeOpeningPanel() {
        guard !ui.isPanelOrderedVisible else { return }
        let app = NSWorkspace.shared.frontmostApplication
        if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier { targetApplication = app }
    }
    @objc private func settings(_ sender: Any?) { ui.showSettings() }
    @objc private func newText(_ sender: Any?) { ui.newTextItem() }
    @objc private func newBoard(_ sender: Any?) { ui.createPinboard() }
    @objc private func search(_ sender: Any?) { rememberPasteTargetBeforeOpeningPanel(); ui.focusSearch() }
    @objc private func stack(_ sender: Any?) { ui.showStack() }
    @objc private func importArchive(_ sender: Any?) { ui.importArchive() }
    @objc private func exportArchive(_ sender: Any?) { ui.exportArchive() }
    @objc private func quit(_ sender: Any?) { NSApp.terminate(nil) }

    /// 底部快捷菜单的「退出 \(ReplicaBrand.name)」：先过二次确认弹窗，
    /// 用户点「取消」或按 Esc 时 `confirm` 返回 false，进程继续跑。
    @objc private func confirmQuit(_ sender: Any?) { PanelShortcutMenuQuitConfirmation.confirm() }

    /// 「检查更新」走的就是关于页那颗按钮的同一条路径
    /// （`BlinkClipInAppUpdater.checkForUpdates()`），不再另写一套。
    @objc private func checkForUpdates(_ sender: Any?) {
        do { try inAppUpdater.checkForUpdates() }
        catch { ui.presentError(error) }
    }

    /// 「帮助与关于」只发通知，**由设置页控制器观察后打开关于页**：
    /// `ReplicaUIController` 的观察者收到后打开（必要时创建）设置窗口并选中关于页，
    /// 与应用菜单的 `about(_:)` 同一条落点。
    @objc private func openAbout(_ sender: Any?) {
        NotificationCenter.default.post(name: .blinkClipOpenAbout, object: nil)
    }

    /// 面板 ⋯ 菜单「暂停 闪贴 → 暂停」：暂停且不设定时恢复。
    /// 与状态栏那个开关同一条路径（`ReplicaUIState.pauseMonitoring`），
    /// 只是不做「已暂停就反转」的判断。
    @objc private func pauseIndefinitely(_ sender: Any?) { ui.state.pauseMonitoring() }

    /// 面板 ⋯ 菜单「暂停 闪贴 → 暂停 N 分钟 / N 小时」：分钟数由菜单项的
    /// `representedObject` 带过来（模型里的 `minutes`）。
    @objc private func pauseForMinutes(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        ui.state.pauseMonitoring(minutes: minutes)
    }

    /// 面板 ⋯ 菜单「暂停 闪贴 → 继续 闪贴」。
    @objc private func resumeMonitoring(_ sender: Any?) { ui.state.resumeMonitoring() }

    /// 应用菜单「关于 \(ReplicaBrand.name)」：关于是设置窗口内容区里的一页，
    /// 所以这里只是打开设置并选中那一页（与 `.blinkClipOpenAbout` 通知、
    /// 面板 ⋯ / 状态栏菜单的「帮助与关于」是同一条落点），不再有独立窗口。
    @objc private func about(_ sender: Any?) {
        ui?.hidePanel()
        ui?.showSettings(initialTab: SettingsAboutPane.tabIndex)
    }
    private func configurePauseMonitoring() {
        let paused = store.preferences.isMonitoringPaused
        let date = store.preferences.pauseUntil
        guard lastPauseFlag != paused || scheduledResumeDate != date else { return }
        pauseResumeTimer?.invalidate()
        pauseResumeTimer = nil
        lastPauseFlag = paused
        scheduledResumeDate = date
        guard paused || date != nil else {
            monitor?.start()
            return
        }
        monitor?.stop()
        if let date {
            // Schedules one NSTimer for resumeDate - Date().
            pauseResumeTimer = Timer.scheduledTimer(withTimeInterval: date.timeIntervalSinceNow,
                                                   repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeTimedPause(expectedDate: date) }
            }
        }
    }

    private func resumeTimedPause(expectedDate: Date) {
        guard store.preferences.pauseUntil == expectedDate else {
            configurePauseMonitoring()
            return
        }
        pauseResumeTimer?.invalidate()
        pauseResumeTimer = nil
        store.preferences.pauseUntil = nil
        store.preferences.isMonitoringPaused = false
        do {
            try store.save()
            ReplicaCopiedOSD.showResumed()
        } catch { ui.presentError(error) }
        configurePauseMonitoring()
    }

    @objc private func pause(_ sender: Any?) {
        if store.preferences.isMonitoringPaused { ui.state.resumeMonitoring() }
        else { ui.state.pauseMonitoring() }
    }

    private func paste(id: UUID, plain: Bool) -> Bool {
        paste(ids: [id], plain: plain)
    }

    @discardableResult
    private func paste(ids: [UUID], plain: Bool, forceDirect: Bool = false,
                       restoreItems: [ClipboardRestoreItem]? = nil) -> Bool {
        let requestedTarget = targetApplication
        let hasAccessibilityAccess = accessibilityService.AXIsProcessTrusted()
        let canPostEvents = accessibilityService.canPostEvents()
        // Reset suppression as soon as a live grant is observed, including copy-only actions.
        if canPostEvents { _ = permissionPromptPolicy.shouldRemind(canPostEvents: true) }
        pasteLogger.notice("request ax=\(hasAccessibilityAccess, privacy: .public) post=\(canPostEvents, privacy: .public) target=\(requestedTarget?.processIdentifier ?? -1, privacy: .public) front=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1, privacy: .public)")
        var copyInsteadOfPaste = !(forceDirect || store.preferences.pasteToActiveApp)
        if pasteboard.name == NSPasteboard.general.name, !copyInsteadOfPaste,
           !canPostEvents {
            if permissionPromptPolicy.shouldRemind(canPostEvents: canPostEvents) {
                NSApp.activate(ignoringOtherApps: true)
                let result = PasteToOtherAppsModal.run()
                pasteLogger.notice("permission_result=\(result, privacy: .public)")
                if result == 2 {
                    NSApp.deactivate()
                    _ = EnableAccessibilityModal.run(requestOnShow: true)
                    return false
                }
                if result & 1 != 0 {
                    do {
                        store.preferences.pasteToActiveApp = false
                        try store.save()
                    } catch { ui.presentError(error); return false }
                }
            }
            copyInsteadOfPaste = true
        }
        var restoreOptions: PasteboardRestore.Options = plain ? .plainText : []
        if store.preferences.alwaysPastePlainText { restoreOptions.insert(.plainTextAndLinks) }
        do {
            if let restoreItems {
                try store.writeToPasteboard(restoreItems: restoreItems, pasteboard: pasteboard, options: restoreOptions)
            } else {
                try store.writeToPasteboard(ids: ids, pasteboard: pasteboard, options: restoreOptions)
            }
        }
        catch {
            pasteLogger.error("restore_failed code=\((error as NSError).code, privacy: .public)")
            ui.presentError(error)
            return false
        }
        pasteLogger.notice("restored copy_only=\(copyInsteadOfPaste, privacy: .public)")
        // Named pasteboards support isolated acceptance runs and never generate system keystrokes.
        guard pasteboard.name == NSPasteboard.general.name else {
            ui.hidePanel()
            return true
        }
        guard !copyInsteadOfPaste else {
            ReplicaCopiedOSD.showCopied(enableDirectPaste: { [weak self] in
                guard let self else { return }
                self.ui.state.perform {
                    self.store.preferences.pasteToActiveApp = true
                    try self.store.save()
                }
            })
            NSApp.deactivate()
            ui.hidePanel()
            return true
        }
        // creates the MainActor task before deactivation. The
        // existing panel onWillClose path restores the previous application.
        Task { @MainActor [self] in
            await self.postPasteKeystroke()
        }
        NSApp.deactivate()
        ui.hidePanel()
        return true
    }

    private func postPasteKeystroke() async {
        PasteKeyTranslation.postPasteKeystroke()
    }

    private func seedFixture() throws {
        let board = try store.createPinboard(name: "实用链接", colorHex: "5575D9")
        _ = try store.add(ClipboardItem(title: "欢迎使用 \(ReplicaBrand.name)", plainText: "拷贝内容，随时找回。\n搜索、预览、编辑，整理到 \(ReplicaBrand.name)。", sourceName: "文本编辑", sourceBundleID: "com.apple.TextEdit"))
        _ = try store.add(ClipboardItem(title: "REA", kind: .link, plainText: "https://github.com/morluto/rea", sourceName: "Safari", sourceBundleID: "com.apple.Safari", pinboardIDs: [board.id]))
        _ = try store.add(ClipboardItem(title: "品牌颜色", kind: .color, plainText: "#5575D9", sourceName: "设计工具"))
        _ = try store.add(ClipboardItem(title: "会议记录", plainText: "今天的计划\n1. 整理灵感\n2. 完成设计\n3. 分享成果", sourceName: "备忘录", sourceBundleID: "com.apple.Notes"))
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store != nil, ui != nil else { return .terminateNow }
        do { try store?.save(); return .terminateNow }
        catch { ui?.presentError(error); return .terminateCancel }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if argument("--data-dir") == nil { BackgroundService.markRunning(false) }
        hotKeyObservation?.cancel()
        networkSpeedObservation?.cancel()
        NetworkSpeedMonitor.shared.stop()
        diagnosticsObservation?.cancel()
        accessibilityObservation?.cancel()
        soundEffects?.stop()
        soundEffects = nil
        pausePreferencesObservation?.cancel()
        pauseResumeTimer?.invalidate()
        pauseResumeTimer = nil
        ReplicaCopiedOSD.pauseStatus = nil
        screenshotCoordinator?.stop()
        screenshotCoordinator = nil
        monitor?.stop(); hotKey.unregister(); stackHotKey.unregister(); stackPasteHotKey.unregister(); refreshTimer?.invalidate()
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
    }
}
