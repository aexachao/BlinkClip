// BlinkClip-local adapter (not part of upstream capcap). Keep additive: upstream subtree merges must not conflict.
//
// 为什么这个文件存在：`Translation/TranslationProvider.swift` 里的
// `TranslationProviderKind` / `TranslationConfigStore` 都是 internal，跨 module 用不了。
// 上游的翻译设置页面在 `Settings/`（不在 vendoring 范围），所以 BlinkClip 的「截图」分区
// 自己放一个 Apple 翻译开关，读写的是**上游既有的** `translation.apple.enabled` 键。
//
// 不新增键：BlinkClip 侧只做开关和可用性路由，配置本身仍归 capcap 的 TranslationConfigStore 管，
// 这样 OCR/翻译面板（`OCRTranslatePanel` → `usableKinds()`）看到的是同一份状态。
//
// 默认值：这个键**从未被写过**时算「开」（macOS 15+ 才有意义，见 `isAppleTranslationAvailableOnSystem`）。
// 缺省策略本身放在 `TranslationConfigStore.defaultEnabledProvider`（唯一读取点），
// 本文件不写任何缺省状态，因此读开关不会顺手把键落盘：
// 用户显式关掉之后 `translation.apple.enabled == false`，下次启动读到的仍是 false。

import Foundation

public enum TranslationSettingsBridge {
    /// 对应 `translation.apple.enabled`。写入后 `TranslationConfigStore.setEnabled`
    /// 会 post `.translationConfigDidChange`，长驻的 OCR 面板据此刷新供应商列表。
    /// 读到的是「用户写入过的值」，用户从未设置过时由缺省策略给出 true。
    public static var appleTranslationEnabled: Bool {
        get { TranslationConfigStore.isEnabled(.apple) }
        set { TranslationConfigStore.setEnabled(newValue, for: .apple) }
    }

    /// Apple 的 Translation framework 只有 macOS 15+ 才有。
    /// 为 false 时设置面板要把这一行禁用（而不是让用户打开一个永远不生效的开关）。
    /// 走 store 的读口而不是直接问枚举，是为了与 `usableKinds()` 用同一份可用性判定。
    public static var isAppleTranslationAvailableOnSystem: Bool {
        TranslationConfigStore.isAvailable(.apple)
    }

    /// 与 `OCRTranslatePanel.runTranslation` 的判定同源：
    /// `isUsable = isAvailableOnCurrentSystem && isEnabled && isConfigured`。
    /// Apple 的 `isConfigured` 在 macOS 15+ 恒为 true，因此本档只要 Apple 一个开关打开，
    /// 这里就会变成 true——截图翻译不再落到「没有可用翻译服务」的占位文案。
    public static var hasUsableTranslationProvider: Bool {
        !TranslationConfigStore.usableKinds().isEmpty
    }
}
