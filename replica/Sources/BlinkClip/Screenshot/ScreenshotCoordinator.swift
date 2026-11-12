import AppKit
import os
import BlinkClipCore
import BlinkClipCapture

/// P1-B：把 capcap 的「采集 → 编辑器 → 落库」接到 BlinkClip 的既有设施上。
///
/// - 热键走 BlinkClip 既有的 `GlobalHotKey`（Carbon `RegisterEventHotKey`），
///   **不启用** capcap 的 `KeyMonitor`（`Trigger/` 未 vendored，双 tap 会吞键）。
/// - 采集/编辑器入口走 `CaptureEntry`（BlinkClipCapture 内的薄公共门面），
///   因为 BlinkClipCapture 的类型全部是 internal，跨 module 不可见。
/// - 编辑器产出的 `NSImage` 用 `ClipboardStore.add` 入历史，再用
///   `ClipboardStore.writeToPasteboard` 写剪贴板，用户可直接 ⌘V。
///
/// P1-C：
/// - 启动时把 capcap 的 `HistoryManager` 接到 `ClipboardStore`（`ScreenshotHistoryBridge`），
///   编辑器里的「上一张/下一张」（默认 , 和 .）才能取到真实图片。
/// - 编辑器双击遮罩会把草稿交回来（`onSuspend`），下一次触发优先恢复该草稿，
///   对应上游 `AppDelegate.resumeSuspendedEditIfAvailable()`。
@MainActor
final class ScreenshotCoordinator {
    /// 区域/全屏截图的键位不再硬编码：改到「设置 → 截图 → 快捷键」，
    /// 读写都在 `BlinkClipScreenshotSettings`（capcap 侧偏好，默认 ⌘⇧A / ⌘⇧E）。
    /// Carbon 热键标识符。`GlobalHotKey` 当前忽略该参数，仅作语义区分。
    private static let regionIdentifier: UInt32 = 101
    private static let fullScreenIdentifier: UInt32 = 102

    /// 落库失败必须有痕迹。subsystem/category 与 BlinkClip 其他诊断日志一致。
    private static let logger = Logger(subsystem: "com.chrisli.blinkclip",
                                       category: "screenshot")

    /// 一次「双击遮罩挂起」留下的现场。
    private struct SuspendedCapture {
        let draft: SuspendedEditDraftBox
        /// 触发原草稿的那次前台 App；恢复时沿用，避免把来源记成恢复那一刻的前台 App。
        let sourceApplication: SourceApplicationRecord?
    }

    private let store: ClipboardStore
    private let pasteboard: NSPasteboard
    private let regionHotKey = GlobalHotKey()
    private let fullScreenHotKey = GlobalHotKey()
    /// 编辑器/遮罩强引用；capcap 的 `OverlayWindowController` 不被窗口自持。
    private var overlayController: AnyObject?
    /// 触发瞬间的前台 App；编辑器跑起来之后前台就变成 BlinkClip 自己了。
    private var pendingSourceApplication: SourceApplicationRecord?
    /// capcap 挂起中的编辑草稿。最多一份：上游 `AppDelegate` 同样只留最后一个。
    private var suspendedCapture: SuspendedCapture?
    private var isStarted = false
    /// 截图热键偏好的观察者（设置变更 + 录制开始/结束）。`stop()` 里成对移除。
    private var hotKeyObservers: [NSObjectProtocol] = []
    /// 录制器正在等键盘：两个截图热键此刻已注销，录制结束后按偏好重挂。
    private var isRecordingHotKey = false
    /// 「这次注销是我们为录制做的」。`isRecordingHotKey` 在 `stop()` 里会复位，
    /// 但「注销过就必须恢复注册」不能靠猜，用独立标志记着，恢复注册后清掉。
    private var didUnregisterForRecording = false
    /// 截图进行中收到的偏好变更先挂起，等 `complete`/`suspend` 出口再应用，
    /// 避免遮罩跑到一半把热键换掉（也避免注册时和正在进行的那次触发抢键盘）。
    private var hasPendingHotKeyReload = false
    /// 面板收起等待期间的重入守卫：这段时间 `overlayController` 还是 nil，
    /// 光靠它挡不住第二次热键，会把「收面板」流程叠两遍。
    private var isPresenting = false
    /// 截图期间被临时移出屏幕的 BlinkClip 窗口（P1-D）。记录「哪些原本可见」，
    /// 在保存/取消/挂起/失败四个出口处原样还回去。
    private let windowHider = ScreenshotWindowHider()
    /// P1-C 审计 M2：`HistoryManager.configure` 与 `isStarted` 解耦。
    /// `--no-global-hotkey` 会在注册热键前早退，`isStarted` 保持 false，
    /// 若只靠它做幂等，重复 `start()` 会再 configure 一次（后端被覆盖）。
    private var didConfigureHistory = false

    init(store: ClipboardStore, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.pasteboard = pasteboard
    }

    // MARK: - 生命周期

    func start() {
        guard !isStarted else { return }
        // capcap 的 `HistoryManager` 只在这里接一次存储；没走到这里时它保持空实现。
        // 幂等：下面的 guard 早退时 `isStarted` 仍是 false，重复 start() 不能重新 configure。
        if !didConfigureHistory {
            didConfigureHistory = true
            HistoryManager.configure(backend: ScreenshotHistoryBridge(store: store))
        }
        // 与既有全局快捷键保持同一开关：`--no-global-hotkey` 时不注册。
        guard !ProcessInfo.processInfo.arguments.contains("--no-global-hotkey") else { return }
        regionHotKey.action = { [weak self] in self?.startRegionCapture() }
        fullScreenHotKey.action = { [weak self] in self?.startFullScreenCapture() }
        observeHotKeySettings()
        registerHotKeys()
        isStarted = true
    }

    func stop() {
        removeHotKeyObservers()
        isRecordingHotKey = false
        didUnregisterForRecording = false
        hasPendingHotKeyReload = false
        regionHotKey.unregister()
        fullScreenHotKey.unregister()
        // 热键不再注册，「最近一次注册结果」也就不再描述现实，清掉免得下次看板显示旧失败。
        BlinkClipScreenshotSettings.clearLastRegistration()
        regionHotKey.action = nil
        fullScreenHotKey.action = nil
        overlayController = nil
        isStarted = false
        // 退出时（`applicationWillTerminate`）若还有一次截图没走完，窗口不能留在屏幕外。
        windowHider.restore()
        // `suspendedCapture` 不清：退出热键注册不等于用户放弃草稿，重新 start 后仍可恢复。
    }

    // MARK: - 两个截图热键（偏好驱动）

    /// 按当前偏好注册两个热键，并把每个 `OSStatus` 写回 `BlinkClipScreenshotSettings`。
    ///
    /// `register` 的返回值此前被 `_ =` 丢掉：注册失败（例如组合已被别的 App 占住）
    /// 用户看到的只是「按了没反应」。现在留痕，设置面板据此显示失败原因。
    private func registerHotKeys() {
        func register(_ slot: BlinkClipScreenshotHotKeySlot, hotKey: GlobalHotKey, identifier: UInt32) -> OSStatus {
            guard let value = BlinkClipScreenshotSettings.effectiveShortcut(for: slot) else {
                hotKey.unregister()
                BlinkClipScreenshotSettings.clearLastRegistration(slot)
                return noErr
            }
            let status = hotKey.register(keyCode: value.keyCode, modifiers: value.modifiers, identifier: identifier)
            BlinkClipScreenshotSettings.setLastRegistration(slot, status: status, combo: Self.comboLabel(value))
            return status
        }
        let regionStatus = register(.region, hotKey: regionHotKey, identifier: Self.regionIdentifier)
        let fullStatus = register(.fullScreen, hotKey: fullScreenHotKey, identifier: Self.fullScreenIdentifier)
        if regionStatus != noErr || fullStatus != noErr {
            Self.logger.error("screenshot hotkey register failed region=\(regionStatus, privacy: .public) fullScreen=\(fullStatus, privacy: .public)")
        }
    }

    /// 组合名只用于提示文本（「⇧⌘A 注册失败（OSStatus -9878）」）。
    /// 格式与录制器可见文案一致：`ShortcutFunctions.modifierLabel(verbose: false …)`
    /// 给符号（⇧⌘），`verbose: true` 给的是「⇧ Shift⌘ Command」那种无障碍长名，
    /// 红字里读起来像另一种组合，用户对不上自己刚录的那一个。
    ///
    /// 这里是**第二道防线**：偏好侧已经把越界键码挡在 `UInt16.max` 以内
    /// （见 `BlinkClipScreenshotSettings.hotKey(keyCodeKey:…)`），但 `comboLabel` 拿到的
    /// 是任意 `UInt32`，一旦漏进来就会命中 `displayLabel` 里的 `precondition` 直接崩，
    /// 所以越界/翻译不出来时给兜底文案，不调那个会 precond 的函数。
    private static func comboLabel(_ hotKey: BlinkClipScreenshotHotKey) -> String {
        let modifiers = ShortcutFunctions.modifierLabel(verbose: false,
                                                             modifierRawValue: hotKey.modifierRawValue)
        guard hotKey.keyCode <= UInt32(UInt16.max) else {
            return modifiers + ScreenshotSettingsCopy.text(.hotKeyUnknownKey)
        }
        let key = ShortcutFunctions.displayLabel(keyCode: hotKey.keyCode)
        // 空组合（没有修饰键、键码也翻译不出可见字符）不适合放进「… 注册失败」里。
        guard !(modifiers + key).isEmpty else {
            return ScreenshotSettingsCopy.text(.hotKeyUnknownKey)
        }
        return modifiers + key
    }

    private func observeHotKeySettings() {
        guard hotKeyObservers.isEmpty else { return }
        let center = NotificationCenter.default
        hotKeyObservers.append(center.addObserver(forName: BlinkClipScreenshotSettings.hotKeysDidChange,
                                                  object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotKeyPreferencesDidChange() }
        })
        hotKeyObservers.append(center.addObserver(forName: BlinkClipScreenshotSettings.hotKeyReloadRequested,
                                                  object: nil, queue: .main) { [weak self] _ in
            // 显式「重试注册」：偏好值没变也要重挂（占用组合的 App 可能刚退出）。
            // 走同一个入口，于是 `--no-global-hotkey`/录制中/截图进行中的守卫都照旧生效。
            MainActor.assumeIsolated { self?.hotKeyPreferencesDidChange() }
        })
        hotKeyObservers.append(center.addObserver(forName: BlinkClipScreenshotSettings.recordingDidChange,
                                                  object: nil, queue: .main) { [weak self] notification in
            let recording = (notification.userInfo?[BlinkClipScreenshotSettings.recordingUserInfoKey] as? Bool) ?? false
            MainActor.assumeIsolated { self?.hotKeyRecordingDidChange(recording) }
        })
    }

    private func removeHotKeyObservers() {
        let center = NotificationCenter.default
        for observer in hotKeyObservers { center.removeObserver(observer) }
        hotKeyObservers.removeAll()
    }

    /// 偏好变了：先注销旧键再注册新键。`GlobalHotKey.register` 内部只按**同一个**
    /// 旧值注销自己，所以这里显式先全注销，避免旧组合在新组合注册后仍然活着。
    private func hotKeyPreferencesDidChange() {
        // 没注册过（`--no-global-hotkey` 或已 stop()）就没什么可换。
        guard isStarted else { return }
        // 录制中不重注册：录制结束会按那时的偏好统一注册一次。这里只需记下「有待落地」，
        // 否则录制期间的改键要等下一次改键才有机会生效。
        guard !isRecordingHotKey else {
            hasPendingHotKeyReload = true
            return
        }
        // 截图进行中：遮罩/编辑器还拿着键盘焦点，留到出口再换。
        if overlayController != nil || isPresenting {
            hasPendingHotKeyReload = true
            return
        }
        applyHotKeyPreferences()
    }

    /// 录制开始时把两个截图热键摘掉：录制器要靠 `keyDown` 拿到按键，
    /// 留着 Carbon 热键会把组合吞掉（用户看到的是「录不上」）。
    private func hotKeyRecordingDidChange(_ recording: Bool) {
        guard isStarted else { return }
        if recording {
            guard !isRecordingHotKey else { return }
            isRecordingHotKey = true
            // 硬要求：录制结束后这两个热键必须恢复注册，所以注销这件事要留痕。
            didUnregisterForRecording = true
            regionHotKey.unregister()
            fullScreenHotKey.unregister()
            return
        }
        // 没有「我们自己注销过」的记录，就没有必须恢复的东西。
        // 录制器每次 `onDisappear` 都会报一次 false（切分区/关窗口/六个录制器各自最后一下），
        // 这些重复的 false 不能白把两个热键注销重注册一遍（`lastRegistration` 也跟着被洗）。
        guard isRecordingHotKey || didUnregisterForRecording else { return }
        isRecordingHotKey = false
        guard didUnregisterForRecording || hasPendingHotKeyReload else { return }
        // 走 `hotKeyPreferencesDidChange` 而不是直接重注册：截图进行中（遮罩还拿着键盘）
        // 时它会把这轮变更挂起，等 `complete`/`suspend` 出口再落地。
        hotKeyPreferencesDidChange()
    }

    /// 把挂起的偏好变更落地。`complete`/`suspend`（以及抓屏失败）出口调用。
    private func applyPendingHotKeyReload() {
        guard hasPendingHotKeyReload else { return }
        guard isStarted, !isRecordingHotKey else { return }
        applyHotKeyPreferences()
    }

    private func applyHotKeyPreferences() {
        hasPendingHotKeyReload = false
        // 走到这里两个热键都会被重新注册，「因录制注销」这件事就算清掉了。
        didUnregisterForRecording = false
        regionHotKey.unregister()
        fullScreenHotKey.unregister()
        registerHotKeys()
    }

    // MARK: - 两个入口

    func startRegionCapture() {
        present(isRegion: true)
    }

    func startFullScreenCapture() {
        present(isRegion: false)
    }

    private func present(isRegion: Bool) {
        // 遮罩/编辑器已在前台、或上一轮「收面板 + 采集」还没落地时忽略重复触发
        // （对应 capcap 的 overlayController == nil 守卫；isPresenting 覆盖等待面板关闭的窗口期）。
        guard overlayController == nil, !isPresenting else { return }
        let focusRestorer = ScreenshotFocusRestorer.captureFrontmost()
        let onFocusReturn = { focusRestorer.restore() }
        let onSuspend: (SuspendedEditDraftBox) -> Void = { [weak self] draft in self?.suspend(draft) }
        let onComplete: (NSImage?) -> Void = { [weak self] image in self?.complete(image) }

        // 挂起的草稿优先恢复：不再重新抓屏，也不覆盖来源 App。
        if let suspended = suspendedCapture {
            if let controller = CaptureEntry.resumeSuspendedEditor(draft: suspended.draft,
                                                                  onFocusReturn: onFocusReturn,
                                                                  onSuspend: onSuspend,
                                                                  onComplete: onComplete) {
                suspendedCapture = nil
                pendingSourceApplication = suspended.sourceApplication
                overlayController = controller
                return
            }
            // 草稿恢复不了（例如那块显示器已经拔掉）：丢弃它，按普通触发继续抓新图，
            // 否则这个热键会被一份永远失败的草稿永久堵住。
            suspendedCapture = nil
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        pendingSourceApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? nil : frontmost.flatMap(SourceApplication.snapshot)
        // 门禁第 8 条（P1-D 版）：**创建遮罩之前**先把 BlinkClip 自己的窗口移出屏幕。
        // capcap 的 `OverlayWindowController` 在 init 时就抓 pre-snapshot，晚一步面板就进底图了。
        // `orderOut` 同步生效；再让出一轮主线程，确保窗口服务器已经把它撤下再开始抓屏。
        // 面板不可见时这里什么都没收，`restore()` 也自然是空操作。
        isPresenting = true
        windowHider.hideVisibleBlinkClipWindows()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.beginCapture(isRegion: isRegion,
                                   onFocusReturn: onFocusReturn,
                                   onSuspend: onSuspend,
                                   onComplete: onComplete)
            }
        }
    }

    /// 遮罩已经在上一轮主线程里创建好（面板此时已离屏）。所有失败出口都在这里收口。
    private func beginCapture(isRegion: Bool,
                              onFocusReturn: @escaping () -> Void,
                              onSuspend: @escaping (SuspendedEditDraftBox) -> Void,
                              onComplete: @escaping (NSImage?) -> Void) {
        // 等待期间 stop() 被调用（热键重配置 / App 退出）：不再拉起遮罩，并把窗口还回去。
        guard isStarted else {
            isPresenting = false
            windowHider.restore()
            return
        }
        let controller: AnyObject?
        if isRegion {
            controller = CaptureEntry.presentRegionEditor(onFocusReturn: onFocusReturn,
                                                          onSuspend: onSuspend,
                                                          onComplete: onComplete)
        } else {
            controller = CaptureEntry.presentFullScreenEditor(onFocusReturn: onFocusReturn,
                                                              onSuspend: onSuspend,
                                                              onComplete: onComplete)
        }
        isPresenting = false
        // 窗口已经离屏，把收起时摘掉的 delegate 装回（见 `ScreenshotWindowHider`）。
        windowHider.reattachDelegates()
        guard let controller else {
            // 抓屏失败（多为「屏幕录制」未授权）：不产生任何条目，窗口还回去。
            windowHider.restore()
            NSSound.beep()
            // 这也是一次「截图结束」：挂起的热键变更不能等下一次成功截图才生效。
            applyPendingHotKeyReload()
            return
        }
        overlayController = controller
    }

    /// capcap 双击遮罩挂起编辑器时回调：遮罩和编辑器已经被它自己拆掉，
    /// 这里只收下草稿并放开热键守卫，下一次触发走恢复分支。
    private func suspend(_ draft: SuspendedEditDraftBox) {
        // 遮罩和编辑器已经被 capcap 自己拆掉，窗口可以还回去了。
        windowHider.restore()
        overlayController = nil
        suspendedCapture = SuspendedCapture(draft: draft, sourceApplication: pendingSourceApplication)
        pendingSourceApplication = nil
        // 遮罩/编辑器已放开：截图期间挂起的热键变更在这里应用。
        applyPendingHotKeyReload()
    }

    // MARK: - 落库

    private func complete(_ image: NSImage?) {
        // 保存/取消都会走到这里：先把截图前收起的窗口还回去，再处理落库
        // （落库可能失败，不能让失败把面板留在屏幕外）。
        windowHider.restore()
        overlayController = nil
        // 保存/取消都走这里：截图期间挂起的热键变更在这条出口应用
        // （放在 `guard` 之前，取消截图也要让新键生效）。
        applyPendingHotKeyReload()
        let sourceApplication = pendingSourceApplication
        pendingSourceApplication = nil
        // 取消（Esc / 放弃编辑）不产生任何条目。
        guard let image, let data = BlinkClipImageEncoding.pngData(from: image) else { return }
        let item = ClipboardItem(kind: .image, plainText: nil, sourceName: ReplicaBrand.name,
                                 payloads: ["public.png": data])
        // 主保存路径唯一没有诊断痕迹的失败点：拆两个阶段，catch 里能说清断在哪一步。
        var stage = "store-add"
        do {
            let id = try store.add(item, sourceApplication: sourceApplication)
            stage = "pasteboard-write"
            // 复用 BlinkClip 自己的写剪贴板路径：它会同步 capture state 的 changeCount，
            // 避免 ClipboardMonitor 把这次写入当成新的拷贝再收一条。
            try store.writeToPasteboard(ids: [id], pasteboard: pasteboard, plainTextOnly: false)
        } catch {
            Self.logger.error("screenshot save failed kind=\(stage, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }
}
