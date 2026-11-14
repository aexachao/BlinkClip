// BlinkClip 截图设置的三语文案：英文 / 简体中文 / 繁体中文（台湾用语）。
// 语言判定不在本文件里：与设置页其余文案共用 BlinkClipCore.SettingsStrings /
// SettingsLanguage 这同一份实现，所以整个设置页只有一套“当前语言”的答案。

import Foundation
import BlinkClipCore

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

    /// 三张完整表；每个 key 在 `entries` 里必须同时给出三种语言，结构上不可能缺键。
    enum Table: String {
        case en
        case zhHans = "zh-Hans"
        case zhHant = "zh-Hant"
    }

    /// 当前语言只有一份判定：`BlinkClipCore.SettingsLanguage.resolved()`
    /// （应用内显式选择优先，否则按系统首选语言；`zh-Hant` 与 `zh-TW` / `zh-HK` /
    /// `zh-MO` 都是繁体）。本文件只把这个结果映射成表名，不再自己读
    /// `UserDefaults`、也不再扫 `Locale.preferredLanguages`——设置页不会出现
    /// 截图分区和其余分区各判一套语言的情况。
    static var language: SettingsLanguage { SettingsLanguage.resolved() }

    static var table: Table {
        switch language {
        case .en: return .en
        case .zhHans: return .zhHans
        case .zhHant: return .zhHant
        }
    }

    static var tableIdentifier: String { table.rawValue }

    static func text(_ key: Key) -> String {
        guard let entry = entries[key] else { return key.rawValue }
        switch table {
        case .en: return entry.en
        case .zhHans: return entry.hans
        case .zhHant: return entry.hant
        }
    }

    static func shortcutAccessibilityLabel(for label: String) -> String {
        String(format: text(.shortcutAccessibilityLabelFormat), label)
    }

    /// 一个 key 的三种语言；构造器要求三语齐全，因此不存在「某语言缺键回落」的分支。
    private struct Entry {
        let en: String
        let hans: String
        let hant: String
        init(_ en: String, _ hans: String, _ hant: String) {
            self.en = en
            self.hans = hans
            self.hant = hant
        }
    }

    private static let entries: [Key: Entry] = [
        .settingsWindowTitle: Entry("Settings", "设置", "設定"),
        .shortcutAccessibilityLabelFormat: Entry("%@ shortcut", "%@快捷键", "%@快捷鍵"),
        .hotKeysDisabledForRun: Entry("Global shortcuts are disabled for this run.",
                                      "本次运行已停用全局快捷键。",
                                      "本次執行已停用全域快捷鍵。"),
        .paneTitle: Entry("Screenshots", "截图", "截圖"),
        .postCaptureSectionTitle: Entry("After capture", "截图后行为", "截圖後行為"),
        .postCaptureFootnote: Entry("For region captures only; full-screen captures open the editor.",
                                    "仅用于区域截图；全屏截图直接进入编辑器。",
                                    "僅用於區域截圖；全螢幕截圖直接進入編輯器。"),
        .postCaptureEditTitle: Entry("Edit", "编辑", "編輯"),
        .postCaptureEditSubtitle: Entry("Annotate, then confirm to save to history and copy to the clipboard.",
                                        "标注后确认，保存到历史并复制到剪贴板。",
                                        "標註後確認，儲存到歷史並複製到剪貼簿。"),
        .postCaptureQuickPinTitle: Entry("Pin", "钉图", "釘圖"),
        .postCaptureQuickPinSubtitle: Entry("Keep above other windows and save to history, without copying to the clipboard.",
                                            "置于屏幕最上层并保存到历史，不复制到剪贴板。",
                                            "置於螢幕最上層並儲存到歷史，不複製到剪貼簿。"),
        .postCaptureTextRecognitionTitle: Entry("Text recognition", "文字识别", "文字識別"),
        .postCaptureTextRecognitionSubtitle: Entry("Review and copy recognized text. The screenshot is not saved to history.",
                                                   "查看并手动复制识别结果，截图不保存到历史。",
                                                   "檢視並手動複製識別結果，截圖不儲存到歷史。"),
        .postCaptureCopyImageTextTitle: Entry("Copy text in image", "复制图中文字", "複製圖中文字"),
        .postCaptureCopyImageTextSubtitle: Entry("Copy recognized text directly. The screenshot is not saved to history.",
                                                 "直接复制识别结果，截图不保存到历史。",
                                                 "直接複製識別結果，截圖不儲存到歷史。"),
        .postCaptureTranslationTitle: Entry("Translate capture", "截图翻译", "截圖翻譯"),
        .postCaptureTranslationSubtitle: Entry("View the translation without saving the screenshot or changing the clipboard.",
                                               "查看翻译结果，不保存截图或改动剪贴板。",
                                               "檢視翻譯結果，不儲存截圖或變更剪貼簿。"),
        .translationSectionTitle: Entry("Screenshot translation", "截图翻译", "截圖翻譯"),
        .appleTranslationTitle: Entry("Use Apple Translation", "使用 Apple 翻译", "使用 Apple 翻譯"),
        .appleTranslationSubtitle: Entry("System translation, without an API key. Requires macOS 15 or later.",
                                         "系统翻译服务，无需 API 密钥。需要 macOS 15 或更新版本。",
                                         "系統翻譯服務，無需 API 金鑰。需要 macOS 15 或更新版本。"),
        .appleTranslationUnavailable: Entry("Requires macOS 15 or later.",
                                            "需要 macOS 15 或更新版本。",
                                            "需要 macOS 15 或更新版本。"),
        .applicationShortcutsTitle: Entry("Open app", "应用唤起", "啟動應用程式"),
        .groupShortcutsTitle: Entry("Switch groups", "分组切换", "分組切換"),
        .pasteShortcutsTitle: Entry("Paste actions", "粘贴操作", "貼上操作"),
        .hotKeySectionTitle: Entry("Screenshots", "截图", "截圖"),
        .hotKeyRegionTitle: Entry("Region capture", "区域截图", "區域截圖"),
        .hotKeyFullScreenTitle: Entry("Full-screen capture", "全屏截图", "全螢幕截圖"),
        .hotKeyRegistrationFailureFormat: Entry("%@ failed to register (OSStatus %d)",
                                                "%@ 注册失败（OSStatus %d）",
                                                "%@ 註冊失敗（OSStatus %d）"),
        .hotKeyRestoreDefault: Entry("Restore default", "恢复默认", "恢復預設"),
        .hotKeyDuplicate: Entry("That shortcut is already taken (by a BlinkClip command or by the other screenshot shortcut).",
                                "此快捷键已被占用（闪贴命令或另一条截图热键）。",
                                "此快捷鍵已被佔用（閃貼指令或另一條截圖快捷鍵）。"),
        .hotKeyRetryRegistration: Entry("Retry", "重试", "重試"),
        .hotKeyUnknownKey: Entry("Unknown key", "未知按键", "未知按鍵"),
        .defaultShortcutConflictFormat: Entry("Default %@ (%@) conflicts with a screenshot shortcut, so it was not applied.",
                                              "默认值 %@（%@）与截图热键冲突，未应用。",
                                              "預設值 %@（%@）與截圖快捷鍵衝突，未套用。"),
    ]
}
