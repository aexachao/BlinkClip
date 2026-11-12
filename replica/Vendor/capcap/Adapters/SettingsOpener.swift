// BlinkClip-local adapter (not part of upstream capcap). Keep additive: upstream subtree merges must not conflict.
//
// 为什么这个文件存在：capcap 的 OCR/翻译面板（`Translation/OCRTranslatePanel.swift`）
// 有一个「打开设置」按钮，它调用 `SettingsWindowController.shared.showAsSettings()`。
// 上游那个方法打开的是 capcap 自己的设置窗（`Settings/`，不在 vendoring 范围）。
//
// `BlinkClipCapture` 不能 import BlinkClip（依赖方向是 BlinkClip → BlinkClipCapture），
// 所以反向跳转只能靠注入：BlinkClip 侧在 `ReplicaUIController.init` 里给
// `BlinkClipSettingsOpener.open` 装一个闭包，这里只留一个空槽 + 目标分区枚举。
// 没有安装时 `open` 为 nil，按钮点下去什么都不发生（与 P1-A 的空壳行为一致）。

import Foundation

/// 要跳到 BlinkClip 设置面板的哪个分区。
///
/// 目前只有「截图」一个落点：热键那一档完成后可以在这里追加 `.shortcuts`。
public enum BlinkClipSettingsPane {
    case screenshot
}

public enum BlinkClipSettingsOpener {
    /// 由 BlinkClip 主线程安装；`SettingsWindowController.showAsSettings` 在 AppKit 动作里读它。
    /// 保持「一个可选闭包」而不是代理对象，正是为了不把 BlinkClip 类型漏进这个 target。
    public static var open: ((BlinkClipSettingsPane) -> Void)?
}
