import Foundation
import BlinkClipCore

/// Stable identifiers preserve existing settings deep links; ordering is independent.
enum SettingsSection: Int, CaseIterable, Identifiable {
    case general = 0, clipboard = 3, screenshot = 2, shortcuts = 4, privacy = 1, ai = 5
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .general: return SettingsCopy.trilingual("通用", "一般", "General")
        case .clipboard: return SettingsCopy.trilingual("剪贴板与历史", "剪貼簿與歷史記錄", "Clipboard & History")
        case .screenshot: return SettingsCopy.trilingual("截图", "截圖", "Screenshots")
        case .shortcuts: return SettingsCopy.trilingual("快捷键", "快捷鍵", "Shortcuts")
        case .privacy: return SettingsCopy.trilingual("隐私与权限", "隱私與權限", "Privacy & Permissions")
        case .ai: return SettingsCopy.trilingual("AI 工具", "AI 工具", "AI Tools")
        }
    }
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .clipboard: return "doc.on.clipboard"
        case .screenshot: return "camera.viewfinder"
        case .shortcuts: return "keyboard"
        case .privacy: return "hand.raised"
        case .ai: return "point.3.connected.trianglepath.dotted"
        }
    }
}

/// Settings-specific editorial terms. Other resource keys retain their existing localization.
///
/// Every term carries all three languages: `zh-Hans`, `zh-Hant`, `en`. The
/// language decision lives in one place (`SettingsLanguage.resolved`), so no
/// branch treats "any zh" as Simplified. Terminology follows
/// `Vendor/capcap/Resources/zh-Hant.lproj/Localizable.strings`: 設定 / 剪貼簿 /
/// 螢幕 / 復原 / 預設 / 檔案 / 儲存 / 視窗 / 選單列 / 圖示 / 應用程式 / 全域.
enum SettingsCopy {
    /// The language this process resolves the settings chrome in.
    static var language: SettingsLanguage { .resolved() }

    /// One trilingual lookup for settings copy.
    static func trilingual(_ zhHans: String, _ zhHant: String, _ en: String) -> String {
        SettingsStrings.trilingual(zhHans, zhHant, en)
    }

    /// Every term key, sorted, so tests can prove all three languages are present.
    static var termKeys: [String] { terms.keys.sorted() }

    static func text(_ key: String) -> String {
        guard let term = terms[key] else {
            // Settings sources must not lean on this path: test-settings-localization
            // fails when a settings key is missing from `terms`, because the bundle
            // has no `zh-Hant.lproj` and would fall back to English.
            return SettingsLocalization.text(key)
        }
        return trilingual(term.hans, term.hant, term.en)
    }

    private static let terms: [String: (hans: String, hant: String, en: String)] = [
        "settings.shortcuts.reset-all": ("恢复全部快捷键…", "復原全部快捷鍵…", "Restore All Shortcuts…"),
        "settings.shortcuts.reset-all.confirmation": ("恢复全部快捷键？", "復原全部快捷鍵？", "Restore All Shortcuts?"),
        "settings.shortcuts.reset-all.scope": ("将恢复四个应用快捷键、两个截图快捷键，以及快捷粘贴和纯文本粘贴的修饰键。其他设置不变。", "將復原四個應用程式快捷鍵、兩個截圖快捷鍵，以及快速貼上和純文字貼上的修飾鍵。其他設定不變。", "Restore the four app shortcuts, both screenshot shortcuts, and the Quick Paste and Plain Text modifier keys. Other settings stay unchanged."),
        "settings.shortcuts.reset-all.failed": ("未能恢复快捷键，原设置已保留。", "未能復原快捷鍵，原設定已保留。", "Couldn’t restore shortcuts. Your previous settings were kept."),
        "settings.shortcuts.activate-paste.title": ("打开历史面板", "開啟歷史面板", "Open History Panel"),
        "settings.shortcuts.activate-paste-stack.title": ("打开堆栈面板", "開啟堆疊面板", "Open Stack Panel"),
        "blinkclip.settings.shortcuts.next-group.title": ("下一个分组", "下一個分組", "Next Group"),
        "blinkclip.settings.shortcuts.previous-group.title": ("上一个分组", "上一個分組", "Previous Group"),
        "settings.paste-items.title": ("粘贴方式", "貼上方式", "Paste Behavior"),
        "settings.paste-items.active-app.title": ("直接粘贴到当前应用", "直接貼上到目前應用程式", "Paste into the Current App"),
        "settings.paste-items.active-app.info": ("将选定记录粘贴到正在使用的应用。", "將選取的記錄貼上到正在使用的應用程式。", "Paste the selected entry into the app you are using."),
        "settings.paste-items.clipboard.title": ("复制到剪贴板", "複製到剪貼簿", "Copy to Clipboard"),
        "settings.paste-items.clipboard.info": ("将选定记录复制到剪贴板，再手动粘贴。", "將選取的記錄複製到剪貼簿，再手動貼上。", "Copy the selected entry, then paste it yourself."),
        "settings.paste-items.plain-text.title": ("始终以纯文本粘贴", "一律以純文字貼上", "Always Paste as Plain Text"),
        "settings.history.title": ("历史记录保留时间", "歷史記錄保留時間", "History Retention"),
        "general.action.erase-history": ("清空历史记录", "清除歷史記錄", "Clear History"),
        "settings.privacy.applications-history.title": ("不记录这些应用", "不記錄這些應用程式", "Excluded Apps"),
        "settings.privacy.applications-history.subtitle": ("在这些应用中复制的内容不会加入历史记录。", "在這些應用程式中複製的內容不會加入歷史記錄。", "Content copied in these apps is not added to history."),
        "settings.privacy.applications-history.empty": ("尚未添加应用", "尚未加入應用程式", "No apps added"),
        "settings.privacy.confidential-content.title": ("不记录敏感内容", "不記錄敏感內容", "Exclude Sensitive Content"),
        "settings.privacy.confidential-content.subtitle": ("跳过来源应用标记为机密的内容。", "略過來源應用程式標記為機密的內容。", "Skip content marked as confidential by its source app."),
        "settings.privacy.autogenerated-content.title": ("不记录临时内容", "不記錄暫存內容", "Exclude Temporary Content"),
        "settings.privacy.autogenerated-content.subtitle": ("跳过来源应用标记为临时的剪贴板内容。", "略過來源應用程式標記為暫存的剪貼簿內容。", "Skip clipboard content marked as transient by its source app."),
        "settings.mcp.connect.action.connect-to": ("查看连接配置…", "檢視連線設定…", "View Configuration…"),
        "settings.mcp.copy": ("复制配置", "複製設定", "Copy Configuration"),
        "settings.mcp.connection-sheet.done": ("完成", "完成", "Done"),
        // Keys below are also in the Core resource table; the trilingual copy here
        // keeps the settings pages fully Traditional instead of falling back to
        // English for a key the shipped bundle has no `zh-Hant.lproj` for.
        "general.action.cancel": ("取消", "取消", "Cancel"),
        "general.action.reset": ("恢复默认设置", "復原預設設定", "Restore Defaults"),
        "general.help-center": ("帮助与指南", "說明與指南", "Help & Guides"),
        "replica.settings.privacy.saved-link-preview.title": ("已保存的预览图", "已儲存的預覽圖", "Saved Preview Images"),
        "replica.settings.privacy.saved-link-preview.subtitle": ("显示记录中已经保存的链接预览。", "顯示記錄中已經儲存的連結預覽。", "Display link previews already stored with your items."),
        "settings.open-at-login.title": ("登录时启动", "登入時啟動", "Launch at Login"),
        "settings.privacy.screensharing.title": ("共享屏幕时显示闪贴", "共享螢幕時顯示閃貼", "Show BlinkClip While Sharing Screen"),
        "settings.privacy.screensharing.subtitle": ("面板打开时，允许共享屏幕的观看者看到闪贴面板。", "面板開啟時，允許共享螢幕的觀看者看到閃貼面板。", "Let shared-screen viewers see the BlinkClip panel when it is open."),
        "settings.shortcuts.plain-text.title": ("纯文本修饰键", "純文字修飾鍵", "Plain Text Modifier"),
        "settings.shortcuts.quick-paste.title": ("快捷粘贴按键", "快速貼上按鍵", "Quick Paste Keys"),
        "settings.run-in-background.title": ("保持后台服务运行", "保持背景服務執行", "Keep Background Service Running"),
        "settings.sound-effects.title": ("播放操作提示音", "播放操作提示音", "Play Feedback Sounds"),
        "updates.about-title": ("关于闪贴", "關於閃貼", "About BlinkClip")
    ]
}
