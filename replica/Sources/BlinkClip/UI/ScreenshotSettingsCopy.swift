// BlinkClip 截图设置的中英文文案；其他语言回退英文。
// 只依赖 Foundation，供应用和隔离的原生界面验证共用。

import Foundation

enum ScreenshotSettingsCopy {
    enum Key: String, CaseIterable {
        case settingsWindowTitle = "settings.window-title"
        case shortcutAccessibilityLabelFormat = "shortcuts.accessibility-label-format"
        case hotKeysDisabledForRun = "shortcuts.disabled-for-run"
        case paneTitle = "screenshot.pane-title"
        case postCaptureSectionTitle = "screenshot.post-capture.section-title"
        case postCaptureFootnote = "screenshot.post-capture.footnote"
        case postCaptureEditTitle = "screenshot.post-capture.edit.title"
        case postCaptureEditSubtitle = "screenshot.post-capture.edit.subtitle"
        case postCaptureQuickPinTitle = "screenshot.post-capture.quick-pin.title"
        case postCaptureQuickPinSubtitle = "screenshot.post-capture.quick-pin.subtitle"
        case postCaptureTextRecognitionTitle = "screenshot.post-capture.text-recognition.title"
        case postCaptureTextRecognitionSubtitle = "screenshot.post-capture.text-recognition.subtitle"
        case postCaptureCopyImageTextTitle = "screenshot.post-capture.copy-image-text.title"
        case postCaptureCopyImageTextSubtitle = "screenshot.post-capture.copy-image-text.subtitle"
        case postCaptureTranslationTitle = "screenshot.post-capture.translation.title"
        case postCaptureTranslationSubtitle = "screenshot.post-capture.translation.subtitle"
        case translationSectionTitle = "screenshot.translation.section-title"
        case appleTranslationTitle = "screenshot.translation.apple.title"
        case appleTranslationSubtitle = "screenshot.translation.apple.subtitle"
        case appleTranslationUnavailable = "screenshot.translation.apple.unavailable"
        // B 档：两个截图热键可改（卡片标题、两行标题、注册失败、恢复默认、重复提示）
        case applicationShortcutsTitle = "shortcuts.application.title"
        case groupShortcutsTitle = "shortcuts.groups.title"
        case pasteShortcutsTitle = "shortcuts.paste.title"
        case hotKeySectionTitle = "screenshot.shortcuts.section-title"
        case hotKeyRegionTitle = "screenshot.shortcuts.region.title"
        case hotKeyFullScreenTitle = "screenshot.shortcuts.full-screen.title"
        case hotKeyRegistrationFailureFormat = "screenshot.shortcuts.registration-failure-format"
        case hotKeyRestoreDefault = "screenshot.shortcuts.restore-default"
        case hotKeyDuplicate = "screenshot.shortcuts.duplicate"
        case hotKeyRetryRegistration = "screenshot.shortcuts.retry-registration"
        case hotKeyUnknownKey = "screenshot.shortcuts.unknown-key"
        // 「快捷键」分区「恢复默认…」：默认值撞上截图热键时跳过该条并提示。
        case defaultShortcutConflictFormat = "shortcut.restore-default.conflict-format"
    }

    /// `Locale.preferredLanguages.first` 以 `zh` 开头就用中文表，其它一律英文。
    /// 用 preferredLanguages 而不是 `Locale.current`：前者不受当前进程的格式化区域影响，
    /// 与系统「首选语言」列表一致。
    static var isChinese: Bool {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") ?? false
    }

    static func text(_ key: Key) -> String {
        let table = isChinese ? chinese : english
        if let value = table[key] { return value }
        return english[key] ?? key.rawValue
    }

    static func shortcutAccessibilityLabel(for label: String) -> String {
        String(format: text(.shortcutAccessibilityLabelFormat), label)
    }

    private static let chinese: [Key: String] = [
        .settingsWindowTitle: "设置",
        .shortcutAccessibilityLabelFormat: "%@快捷键",
        .hotKeysDisabledForRun: "本次运行已停用全局快捷键。",
        .paneTitle: "截图",
        .postCaptureSectionTitle: "截图后行为",
        .postCaptureFootnote: "仅用于区域截图；全屏截图直接进入编辑器。",
        .postCaptureEditTitle: "编辑",
        .postCaptureEditSubtitle: "标注后确认，保存到历史并复制到剪贴板。",
        .postCaptureQuickPinTitle: "钉图",
        .postCaptureQuickPinSubtitle: "置于屏幕最上层并保存到历史，不复制到剪贴板。",
        .postCaptureTextRecognitionTitle: "文字识别",
        .postCaptureTextRecognitionSubtitle: "查看并手动复制识别结果，截图不保存到历史。",
        .postCaptureCopyImageTextTitle: "复制图中文字",
        .postCaptureCopyImageTextSubtitle: "直接复制识别结果，截图不保存到历史。",
        .postCaptureTranslationTitle: "截图翻译",
        .postCaptureTranslationSubtitle: "查看翻译结果，不保存截图或改动剪贴板。",
        .translationSectionTitle: "截图翻译",
        .appleTranslationTitle: "使用 Apple 翻译",
        .appleTranslationSubtitle: "系统翻译服务，无需 API 密钥。需要 macOS 15 或更新版本。",
        .appleTranslationUnavailable: "需要 macOS 15 或更新版本。",
        .applicationShortcutsTitle: "应用唤起",
        .groupShortcutsTitle: "分组切换",
        .pasteShortcutsTitle: "粘贴操作",
        .hotKeySectionTitle: "截图",
        .hotKeyRegionTitle: "区域截图",
        .hotKeyFullScreenTitle: "全屏截图",
        .hotKeyRegistrationFailureFormat: "%@ 注册失败（OSStatus %d）",
        .hotKeyRestoreDefault: "恢复默认",
        .hotKeyDuplicate: "此快捷键已被占用（闪贴命令或另一条截图热键）。",
        .hotKeyRetryRegistration: "重试",
        .hotKeyUnknownKey: "未知按键",
        .defaultShortcutConflictFormat: "默认值 %@（%@）与截图热键冲突，未应用。",
    ]

    private static let english: [Key: String] = [
        .settingsWindowTitle: "Settings",
        .shortcutAccessibilityLabelFormat: "%@ shortcut",
        .hotKeysDisabledForRun: "Global shortcuts are disabled for this run.",
        .paneTitle: "Screenshots",
        .postCaptureSectionTitle: "After capture",
        .postCaptureFootnote: "For region captures only; full-screen captures open the editor.",
        .postCaptureEditTitle: "Edit",
        .postCaptureEditSubtitle: "Annotate, then confirm to save to history and copy to the clipboard.",
        .postCaptureQuickPinTitle: "Pin",
        .postCaptureQuickPinSubtitle: "Keep above other windows and save to history, without copying to the clipboard.",
        .postCaptureTextRecognitionTitle: "Text recognition",
        .postCaptureTextRecognitionSubtitle: "Review and copy recognized text. The screenshot is not saved to history.",
        .postCaptureCopyImageTextTitle: "Copy text in image",
        .postCaptureCopyImageTextSubtitle: "Copy recognized text directly. The screenshot is not saved to history.",
        .postCaptureTranslationTitle: "Translate capture",
        .postCaptureTranslationSubtitle: "View the translation without saving the screenshot or changing the clipboard.",
        .translationSectionTitle: "Screenshot translation",
        .appleTranslationTitle: "Use Apple Translation",
        .appleTranslationSubtitle: "System translation, without an API key. Requires macOS 15 or later.",
        .appleTranslationUnavailable: "Requires macOS 15 or later.",
        .applicationShortcutsTitle: "Open app",
        .groupShortcutsTitle: "Switch groups",
        .pasteShortcutsTitle: "Paste actions",
        .hotKeySectionTitle: "Screenshots",
        .hotKeyRegionTitle: "Region capture",
        .hotKeyFullScreenTitle: "Full-screen capture",
        .hotKeyRegistrationFailureFormat: "%@ failed to register (OSStatus %d)",
        .hotKeyRestoreDefault: "Restore default",
        .hotKeyDuplicate: "That shortcut is already taken (by a BlinkClip command or by the other screenshot shortcut).",
        .hotKeyRetryRegistration: "Retry",
        .hotKeyUnknownKey: "Unknown key",
        .defaultShortcutConflictFormat: "Default %@ (%@) conflicts with a screenshot shortcut, so it was not applied.",
    ]
}
