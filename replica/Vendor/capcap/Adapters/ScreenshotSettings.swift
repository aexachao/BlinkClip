// BlinkClip-local adapter (not part of upstream capcap). Keep additive: upstream subtree merges must not conflict.
//
// 为什么这个文件存在：截图「后置动作」在上游是
// `OverlayWindowController.PostCaptureAction`（internal），持久化则在 `Settings/`
// 那一套设置面板里（整个 `Settings/` 不在 vendoring 范围，见 SettingsWindowControllerStub）。
// BlinkClip 需要自己存一个偏好、并在区域截图入口把它交给 `OverlayWindowController`，
// 所以这里放一个薄门面：public 枚举 + UserDefaults 读写 + 到 internal 枚举的映射。
//
// 键名风格与 `blinkclip.icloud-drive.*` 一致：这是 BlinkClip 自有偏好，不写进 capcap 的 `Defaults`。
// 也不放进 `AppPreferences`——那是 BlinkClipCore 的 Core Data 二进制属性，本档不动 BlinkClipCore。

import AppKit
import Foundation

/// 区域截图松手后要做什么。
///
/// 刻意**不含** `.record`：录像要在触发层另外接线（capcap 的 `.record` 分支会
/// `onRecordingSelection` 交给外部），当前 BlinkClip 侧没有这条链路，
/// 放进下拉框等于给用户一个选了什么都不会发生的选项。
public enum BlinkClipScreenshotAction: String, CaseIterable {
    case edit
    case quickPin
    case textRecognition
    case copyImageText
    case screenshotTranslation
}

/// 一条截图热键：Carbon 键码 + `NSEvent.ModifierFlags.rawValue`。
///
/// 刻意**不放进 `AppPreferences`**：那是 BlinkClipCore 的 Core Data 二进制属性，本档不动 BlinkClipCore；
/// 截图热键与 `blinkclip.screenshot.postCaptureAction` 同源，都是 capcap 侧偏好。
/// 命名带 `BlinkClip` 前缀，避免与上游 capcap 的 `Defaults`/`PostCaptureAction` 撞名。
public struct BlinkClipScreenshotHotKey: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifierRawValue: UInt

    public init(keyCode: UInt32, modifierRawValue: UInt) {
        self.keyCode = keyCode
        self.modifierRawValue = modifierRawValue
    }

    public var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierRawValue) }
}

/// 截图热键的两个槽位。`region`/`fullScreen` 与两个入口一一对应；
/// 冲突检查、注册失败状态都按这个键区分，不再靠「第几条」。
public enum BlinkClipScreenshotHotKeySlot: String, CaseIterable, Sendable {
    case region
    case fullScreen
}

/// 一次热键注册的结果。`status` 原样保留 `OSStatus`（成功是 0），
/// `combo` 是注册那一刻的组合名，用于「⌘⇧A 注册失败（OSStatus -9878）」这种提示。
public struct BlinkClipScreenshotHotKeyRegistration: Equatable, Sendable {
    public let status: OSStatus
    public let combo: String

    public init(status: OSStatus, combo: String) {
        self.status = status
        self.combo = combo
    }

    public var succeeded: Bool { status == 0 }
}

/// 「截图」分区里「截图后行为」的持久化。
///
/// 存储只有一处真相：`UserDefaults` 里的一个字符串。与 `ScreenshotSettingsCopy` 无关——
/// 文案键在 `Sources/BlinkClip/UI/` 侧，这里只认 rawValue。
public enum BlinkClipScreenshotSettings {
    /// 与 `Sources/BlinkClip/UI/AuxiliaryViews.swift` 里读写的键必须一致（同一字符串，两个 module）。
    public static let postCaptureActionKey = "blinkclip.screenshot.postCaptureAction"

    /// 偏好变更通知。设置面板写完后自己刷新，OCR/编辑器等长驻界面靠它避免轮询 UserDefaults。
    public static let didChange = Notification.Name("BlinkClipScreenshotSettingsDidChange")

    /// 缺省 `.edit`：没有存过值（含旧版本升级上来）时行为与本档之前完全一致。
    public static var postCaptureAction: BlinkClipScreenshotAction {
        get {
            guard let raw = UserDefaults.standard.string(forKey: postCaptureActionKey),
                  let action = BlinkClipScreenshotAction(rawValue: raw)
            else { return .edit }
            return action
        }
        set {
            let previous = postCaptureAction
            guard newValue != previous else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: postCaptureActionKey)
            NotificationCenter.default.post(name: didChange, object: newValue)
        }
    }

    // MARK: - 两个截图热键（B 档：可在设置里改）

    /// 键名与 `Sources/BlinkClip/UI/` 侧读写的字符串必须一致（同一存储，两个 module）。
    /// modifiers 存 `NSEvent.ModifierFlags.rawValue`（Int）。
    public static let regionKeyCodeKey = "blinkclip.screenshot.region.keyCode"
    public static let regionModifiersKey = "blinkclip.screenshot.region.modifiers"
    public static let fullScreenKeyCodeKey = "blinkclip.screenshot.fullScreen.keyCode"
    public static let fullScreenModifiersKey = "blinkclip.screenshot.fullScreen.modifiers"
    public static let regionEnabledKey = "blinkclip.screenshot.region.enabled"
    public static let fullScreenEnabledKey = "blinkclip.screenshot.fullScreen.enabled"

    /// Missing enable flags preserve shortcuts from every older installation.
    public static func effectiveShortcut(for slot: BlinkClipScreenshotHotKeySlot) -> BlinkClipScreenshotHotKey? {
        guard UserDefaults.standard.object(forKey: enabledKey(for: slot)) as? Bool != false else { return nil }
        return shortcut(for: slot)
    }

    public static func clearShortcut(for slot: BlinkClipScreenshotHotKeySlot) {
        guard effectiveShortcut(for: slot) != nil else { return }
        UserDefaults.standard.set(false, forKey: enabledKey(for: slot))
        lastRegistration[slot] = nil
        NotificationCenter.default.post(name: hotKeysDidChange, object: slot)
        NotificationCenter.default.post(name: registrationDidChange, object: slot)
    }

    private static func enabledKey(for slot: BlinkClipScreenshotHotKeySlot) -> String {
        slot == .region ? regionEnabledKey : fullScreenEnabledKey
    }

    /// 默认：区域 ⌘⇧A（kVK_ANSI_A = 0x00）、全屏 ⌘⇧E（kVK_ANSI_E = 0x0E）。
    /// 与本档之前硬编码在 `ScreenshotCoordinator` 里的值逐字相同，升级上来的用户行为不变。
    public static let regionDefault = BlinkClipScreenshotHotKey(
        keyCode: 0x00,
        modifierRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue)
    public static let fullScreenDefault = BlinkClipScreenshotHotKey(
        keyCode: 0x0E,
        modifierRawValue: NSEvent.ModifierFlags([.command, .shift]).rawValue)

    /// 截图热键变更通知。`ScreenshotCoordinator` 靠它注销旧键、注册新键。
    /// 与 `didChange`（截图后行为）分开：改下拉框不该触发热键重注册，反之亦然。
    public static let hotKeysDidChange = Notification.Name("BlinkClipScreenshotHotKeysDidChange")

    /// 录制开始/结束通知，`userInfo` 里的 Bool 见 `recordingUserInfoKey`。
    /// 录制期间键盘事件要留给录制器，两个截图热键必须先摘掉，否则按键被吞。
    public static let recordingDidChange = Notification.Name("BlinkClipScreenshotHotKeyRecordingDidChange")
    public static let recordingUserInfoKey = "isRecording"

    /// 注册结果变更通知（`object` 是槽位，`userInfo` 里是该槽位的注册结果）。
    /// 设置面板开着时改键，失败提示要立刻出现，不能等重开窗口。
    public static let registrationDidChange = Notification.Name("BlinkClipScreenshotHotKeyRegistrationDidChange")
    public static let registrationUserInfoKey = "registration"

    /// 「按当前偏好再注册一次」的显式请求。**不是**偏好变更通知：
    /// 注册失败最常见的原因是组合被别的 App 占着（`OSStatus -9878`），
    /// 那个 App 退出后偏好值一个字节都没变，`storeHotKey` 也就不会再发 `hotKeysDidChange`。
    /// 设置面板的「重试」按钮走这条通知，重注册不依赖值变化。
    public static let hotKeyReloadRequested = Notification.Name("BlinkClipScreenshotHotKeyReloadRequested")

    /// Commit both slots before notifying observers, avoiding registration of an intermediate pair.
    public static func restoreAllShortcutDefaults(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: regionEnabledKey)
        defaults.set(true, forKey: fullScreenEnabledKey)
        defaults.set(Int(regionDefault.keyCode), forKey: regionKeyCodeKey)
        defaults.set(Int(regionDefault.modifierRawValue), forKey: regionModifiersKey)
        defaults.set(Int(fullScreenDefault.keyCode), forKey: fullScreenKeyCodeKey)
        defaults.set(Int(fullScreenDefault.modifierRawValue), forKey: fullScreenModifiersKey)
        NotificationCenter.default.post(name: hotKeysDidChange, object: nil)
    }

    public static func requestHotKeyReload() {
        NotificationCenter.default.post(name: hotKeyReloadRequested, object: nil)
    }

    public static var regionShortcut: BlinkClipScreenshotHotKey {
        get { hotKey(keyCodeKey: regionKeyCodeKey, modifiersKey: regionModifiersKey, fallback: regionDefault) }
        set {
            apply(newValue, keyCodeKey: regionKeyCodeKey, modifiersKey: regionModifiersKey,
                  fallback: regionDefault, slot: .region)
        }
    }

    public static var fullScreenShortcut: BlinkClipScreenshotHotKey {
        get { hotKey(keyCodeKey: fullScreenKeyCodeKey, modifiersKey: fullScreenModifiersKey, fallback: fullScreenDefault) }
        set {
            apply(newValue, keyCodeKey: fullScreenKeyCodeKey, modifiersKey: fullScreenModifiersKey,
                  fallback: fullScreenDefault, slot: .fullScreen)
        }
    }

    public static func shortcut(for slot: BlinkClipScreenshotHotKeySlot) -> BlinkClipScreenshotHotKey {
        switch slot {
        case .region: return regionShortcut
        case .fullScreen: return fullScreenShortcut
        }
    }

    /// 这个组合是否正被某个截图热键占着；占着就返回那个槽位，否则 nil。
    ///
    /// 冲突检查的**唯一**截图侧口径：底层 Carbon 对同值会先注销再登记，后注册的顶掉
    /// 前一个，同值注册**不会**返回错误，只会让另一条热键静默失效。
    /// 比的是**生效值**（`regionShortcut`/`fullScreenShortcut` 已把盘上坏值钳到默认），
    /// 和真正会被注册的那个组合一致。
    ///
    /// `excluding` 给「改/恢复某一行」用：那一行自己的现值不参与判定。
    public static func slot(occupyingKeyCode keyCode: UInt32,
                            modifierRawValue: UInt,
                            excluding excluded: BlinkClipScreenshotHotKeySlot? = nil) -> BlinkClipScreenshotHotKeySlot? {
        for slot in BlinkClipScreenshotHotKeySlot.allCases where slot != excluded {
            guard let hotKey = effectiveShortcut(for: slot) else { continue }
            if hotKey.keyCode == keyCode && hotKey.modifierRawValue == modifierRawValue {
                return slot
            }
        }
        return nil
    }

    public static func slot(occupying hotKey: BlinkClipScreenshotHotKey,
                            excluding excluded: BlinkClipScreenshotHotKeySlot? = nil) -> BlinkClipScreenshotHotKeySlot? {
        slot(occupyingKeyCode: hotKey.keyCode, modifierRawValue: hotKey.modifierRawValue, excluding: excluded)
    }

    public static func `default`(for slot: BlinkClipScreenshotHotKeySlot) -> BlinkClipScreenshotHotKey {
        switch slot {
        case .region: return regionDefault
        case .fullScreen: return fullScreenDefault
        }
    }

    /// 写一条截图热键偏好。
    ///
    /// `force` 只给「恢复默认」用：普通改键仍然「值未变不写、不发通知」，
    /// 否则两个录制器反复写同一个值会把协调器刷成不停重注册。
    /// 恢复默认必须强制：`hotKey(...)` 读盘时会把越界键码**钳到默认**，
    /// 于是盘上的毒化值（例如 `keyCode = 70000`）读出来正好等于默认值，
    /// 不强制写就会被判成「值没变」，坏值永远留在盘上。
    public static func setShortcut(_ hotKey: BlinkClipScreenshotHotKey,
                                   for slot: BlinkClipScreenshotHotKeySlot,
                                   force: Bool = false) {
        switch slot {
        case .region:
            apply(hotKey, keyCodeKey: regionKeyCodeKey, modifiersKey: regionModifiersKey,
                  fallback: regionDefault, slot: .region, force: force)
        case .fullScreen:
            apply(hotKey, keyCodeKey: fullScreenKeyCodeKey, modifiersKey: fullScreenModifiersKey,
                  fallback: fullScreenDefault, slot: .fullScreen, force: force)
        }
    }

    /// 录制状态 = 「还有几个录制器在等键盘」。
    ///
    /// 之前是一个 Bool：设置面板里六个录制器任意一个收起都会报 `false`，
    /// 两个录制器**重叠**时先结束的那个会立刻把两条截图热键挂回去，
    /// 而另一个仍在等键 —— 挂回去的 Carbon 热键会把它想录的组合吞掉。
    /// 改成计数：0→1 才发「开始」，1→0 才发「结束」，中间的重叠不打扰协调器。
    /// 重复的结束（每个录制器 `onDisappear` 都会报一次）不会把计数压成负数，
    /// 也不会多发通知。
    public private(set) static var recordingCount = 0

    public static var isRecording: Bool { recordingCount > 0 }

    public static func beginRecording() {
        recordingCount += 1
        guard recordingCount == 1 else { return }
        NotificationCenter.default.post(name: recordingDidChange, object: nil,
                                        userInfo: [recordingUserInfoKey: true])
    }

    public static func endRecording() {
        guard recordingCount > 0 else { return }
        recordingCount -= 1
        guard recordingCount == 0 else { return }
        NotificationCenter.default.post(name: recordingDidChange, object: nil,
                                        userInfo: [recordingUserInfoKey: false])
    }

    /// 最近一次注册结果，按槽位两条。调用方（`ScreenshotCoordinator`）在
    /// `GlobalHotKey.register` 返回后立刻写回；UI 只读，不解释错误码含义。
    public private(set) static var lastRegistration: [BlinkClipScreenshotHotKeySlot: BlinkClipScreenshotHotKeyRegistration] = [:]

    public static func setLastRegistration(_ slot: BlinkClipScreenshotHotKeySlot,
                                           status: OSStatus,
                                           combo: String) {
        let registration = BlinkClipScreenshotHotKeyRegistration(status: status, combo: combo)
        guard lastRegistration[slot] != registration else { return }
        lastRegistration[slot] = registration
        NotificationCenter.default.post(name: registrationDidChange, object: slot,
                                        userInfo: [registrationUserInfoKey: registration])
    }

    /// `ScreenshotCoordinator.stop()` 注销两个热键后，「最近一次注册结果」不再描述当前状态，
    /// 这里的清空只为避免设置面板留一条过期提示；下次注册会重新写入。
    public static func clearLastRegistration() {
        guard !lastRegistration.isEmpty else { return }
        lastRegistration = [:]
        NotificationCenter.default.post(name: registrationDidChange, object: nil)
    }

    public static func clearLastRegistration(_ slot: BlinkClipScreenshotHotKeySlot) {
        guard lastRegistration.removeValue(forKey: slot) != nil else { return }
        NotificationCenter.default.post(name: registrationDidChange, object: slot)
    }

    // MARK: 键值读写

    /// 缺键回落默认值。三个「读成 0 / 读成坏值」的坑要一起堵：
    ///
    /// 1. 必须先判空：`integer(forKey:)` 对缺键返回 0，而 0 恰好是 `kVK_ANSI_A`，
    ///    会把「没存过」误当成「用户选了 A」。
    /// 2. 判空之后还要判**类型**：`defaults write … blinkclip.screenshot.region.keyCode -string abc`
    ///    时 `object(forKey:)` 非 nil，但 `integer(forKey:)` 又给 0 ——区域/全屏都会变成 ⌘⇧A。
    ///    这里只接受真正桥接成 `Int` 的值（`NSNumber` 的整型），其它类型等于「没存过」。
    /// 3. 布尔值不算数字：`-bool YES` 会桥接成 1（`kVK_ANSI_S`），同样按「没存过」处理。
    private static func storedInteger(_ key: String) -> Int? {
        guard let value = UserDefaults.standard.object(forKey: key) else { return nil }
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        return value as? Int
    }

    private static func hotKey(keyCodeKey: String,
                               modifiersKey: String,
                               fallback: BlinkClipScreenshotHotKey) -> BlinkClipScreenshotHotKey {
        // `UInt32(exactly:)`/`UInt(exactly:)` 对负数与溢出返回 nil → 回落默认，
        // 不把外部写入的坏值变成随机键码。
        let storedKeyCode = storedInteger(keyCodeKey).flatMap { UInt32(exactly: $0) }
        // 上界也得管：`UInt32(exactly:)` 只挡负数/溢出，不挡「大于 UInt16.max」。
        // 越界键码会一路传到 `ShortcutFunctions.displayLabel(keyCode:)` 的
        // `precondition(keyCode <= UInt16.max)` —— 启动注册热键时直接 SIGTRAP，
        // 崩溃点在设置面板之前，用户没有机会在界面里改回来。
        let keyCode = storedKeyCode.flatMap { $0 <= UInt32(UInt16.max) ? $0 : nil } ?? fallback.keyCode
        let modifiers = storedInteger(modifiersKey).flatMap { UInt(exactly: $0) } ?? fallback.modifierRawValue
        return BlinkClipScreenshotHotKey(keyCode: keyCode, modifierRawValue: modifiers)
    }

    /// 值未变不写、不发通知（返回 false）。`force` 跳过「值未变」判定，直接写盘。
    private static func storeHotKey(_ hotKey: BlinkClipScreenshotHotKey,
                                    keyCodeKey: String,
                                    modifiersKey: String,
                                    fallback: BlinkClipScreenshotHotKey,
                                    force: Bool = false) -> Bool {
        if !force {
            let previous = self.hotKey(keyCodeKey: keyCodeKey, modifiersKey: modifiersKey, fallback: fallback)
            guard hotKey != previous else { return false }
        }
        let defaults = UserDefaults.standard
        defaults.set(Int(hotKey.keyCode), forKey: keyCodeKey)
        defaults.set(Int(hotKey.modifierRawValue), forKey: modifiersKey)
        return true
    }

    /// 写盘并在真写进去时发 `hotKeysDidChange`（两个 setter 与 `setShortcut` 共用）。
    private static func apply(_ hotKey: BlinkClipScreenshotHotKey,
                              keyCodeKey: String,
                              modifiersKey: String,
                              fallback: BlinkClipScreenshotHotKey,
                              slot: BlinkClipScreenshotHotKeySlot,
                              force: Bool = false) {
        let wasDisabled = effectiveShortcut(for: slot) == nil
        guard storeHotKey(hotKey, keyCodeKey: keyCodeKey, modifiersKey: modifiersKey,
                          fallback: fallback, force: force || wasDisabled) else { return }
        UserDefaults.standard.set(true, forKey: enabledKey(for: slot))
        NotificationCenter.default.post(name: hotKeysDidChange, object: slot)
    }
}

// MARK: - 桥接到 capcap 的 internal 枚举

extension BlinkClipScreenshotAction {
    /// `PostCaptureAction` 是 internal，只有同 target 的文件能提到它。
    /// `CaptureEntry.swift` 与本文件同属 `BlinkClipCapture`，所以这个映射不需要 public。
    var capcapPostCaptureAction: OverlayWindowController.PostCaptureAction {
        switch self {
        case .edit: return .edit
        case .quickPin: return .quickPin
        case .textRecognition: return .textRecognition
        case .copyImageText: return .copyImageText
        case .screenshotTranslation: return .screenshotTranslation
        }
    }
}
