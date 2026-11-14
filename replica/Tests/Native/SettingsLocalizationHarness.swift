import Foundation
import BlinkClipCore

// Compiles the production copy providers unchanged. Each language runs in a
// separate process so Foundation's preferred-language cache matches app startup.
//
// Two providers are covered here, and both are trilingual now:
//  * `SettingsCopy` — the settings chrome's own trilingual table.
//  * `ScreenshotSettingsCopy` — its own 32-key table, also three languages, and
//    it takes the current language from the same `SettingsLanguage` resolver, so
//    the screenshot pane and the rest of the settings page can never disagree.
// Expected strings are written out here per language instead of being read back
// from the production table, so a table that silently loses a translation fails.
@main
struct SettingsLocalizationHarness {
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else { exit(64) }
        let language = CommandLine.arguments[1]
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        // An in-app language pick (Defaults.language) would otherwise win over
        // -AppleLanguages; a harness run must reflect only the language it was
        // started with, so the stored preference is cleared first.
        UserDefaults.standard.removeObject(forKey: SettingsLanguage.preferenceKey)
        var cases: [[String: Any]] = []
        func record(_ name: String, _ passed: Bool, _ value: String = "") {
            cases.append(["case": name, "passed": passed, "value": value])
        }
        let preferredLanguage = Locale.preferredLanguages.first ?? ""
        record("process-language", preferredLanguage.hasPrefix(language), preferredLanguage)

        // --- settings chrome: trilingual, no "any zh is Simplified" branch ----
        let settingsLanguage = SettingsCopy.language
        record("settings-language", settingsLanguage.rawValue == expectedSettingsLanguage(language),
               settingsLanguage.rawValue)
        record("resolver-zh-hant", SettingsLanguage.settingsLanguage(preferredLanguages: ["zh-Hant"]) == .zhHant)
        record("resolver-zh-tw", SettingsLanguage.settingsLanguage(preferredLanguages: ["zh-TW"]) == .zhHant)
        record("resolver-zh-hk", SettingsLanguage.settingsLanguage(preferredLanguages: ["zh-HK"]) == .zhHant)
        record("resolver-zh-mo", SettingsLanguage.settingsLanguage(preferredLanguages: ["zh-MO"]) == .zhHant)
        record("resolver-zh-hans", SettingsLanguage.settingsLanguage(preferredLanguages: ["zh-Hans"]) == .zhHans)
        record("resolver-zh-cn", SettingsLanguage.settingsLanguage(preferredLanguages: ["zh-CN"]) == .zhHans)
        record("resolver-unsupported", SettingsLanguage.settingsLanguage(preferredLanguages: ["fr"]) == .en)
        record("resolver-stored-hant",
               SettingsLanguage.resolved(preferredLanguages: ["en"], storedAppLanguage: "zh-Hant") == .zhHant)
        record("resolver-stored-zh",
               SettingsLanguage.resolved(preferredLanguages: ["en"], storedAppLanguage: "zh") == .zhHans)
        // A stored language the settings chrome has no table for renders
        // English; it never falls back to a Chinese table the user did not pick.
        record("resolver-stored-unsupported",
               SettingsLanguage.resolved(preferredLanguages: ["zh-Hant"], storedAppLanguage: "ja") == .en)
        record("resolver-stored-empty",
               SettingsLanguage.resolved(preferredLanguages: ["zh-Hant"], storedAppLanguage: "") == .zhHant)
        record("trilingual-hant", SettingsStrings.trilingual("设置", "設定", "Settings", language: .zhHant) == "設定")
        record("trilingual-hans", SettingsStrings.trilingual("设置", "設定", "Settings", language: .zhHans) == "设置")
        record("trilingual-en", SettingsStrings.trilingual("设置", "設定", "Settings", language: .en) == "Settings")

        for section in SettingsSection.allCases {
            record("section.\(section.rawValue).title", !section.title.isEmpty, section.title)
        }
        for key in SettingsCopy.termKeys {
            let value = SettingsCopy.text(key)
            record("settings.\(key)", !value.isEmpty && value != key, value)
        }

        // --- screenshot provider: 32 keys, one table per language ------------
        let expectedTable: String
        let expectedTitle: String
        let expectedRegionLabel: String
        let expectedFullScreenLabel: String
        let expectedDisabledHelp: String
        switch language {
        case "zh-Hans":
            expectedTable = "zh-Hans"
            expectedTitle = "设置"
            expectedRegionLabel = "区域截图快捷键"
            expectedFullScreenLabel = "全屏截图快捷键"
            expectedDisabledHelp = "本次运行已停用全局快捷键。"
        case "zh-Hant":
            expectedTable = "zh-Hant"
            expectedTitle = "設定"
            expectedRegionLabel = "區域截圖快捷鍵"
            expectedFullScreenLabel = "全螢幕截圖快捷鍵"
            expectedDisabledHelp = "本次執行已停用全域快捷鍵。"
        default:
            expectedTable = "en"
            expectedTitle = "Settings"
            expectedRegionLabel = "Region capture shortcut"
            expectedFullScreenLabel = "Full-screen capture shortcut"
            expectedDisabledHelp = "Global shortcuts are disabled for this run."
        }
        // The screenshot pane resolves its language through the same resolver
        // as the rest of the settings page, so both must agree in one process.
        record("screenshot-language-matches-settings",
               ScreenshotSettingsCopy.language == settingsLanguage,
               ScreenshotSettingsCopy.language.rawValue)
        let table = ScreenshotSettingsCopy.tableIdentifier
        record("copy-table", table == expectedTable, table)
        let title = ScreenshotSettingsCopy.text(.settingsWindowTitle)
        record("settings-window-title", title == expectedTitle, title)
        for (key, expected) in [
            (ScreenshotSettingsCopy.Key.hotKeyRegionTitle, expectedRegionLabel),
            (.hotKeyFullScreenTitle, expectedFullScreenLabel),
        ] {
            let label = ScreenshotSettingsCopy.shortcutAccessibilityLabel(for: ScreenshotSettingsCopy.text(key))
            record(key.rawValue + ".accessibility", label == expected, label)
        }
        let disabledHelp = ScreenshotSettingsCopy.text(.hotKeysDisabledForRun)
        record("disabled-run-help", disabledHelp == expectedDisabledHelp, disabledHelp)
        for key in ScreenshotSettingsCopy.Key.allCases {
            let value = ScreenshotSettingsCopy.text(key)
            record("resolved." + key.rawValue, !value.isEmpty && value != key.rawValue, value)
        }

        let passed = cases.allSatisfy { $0["passed"] as? Bool == true }
        let payload: [String: Any] = [
            "language": language, "passed": passed, "cases": cases,
            "settingsLanguage": settingsLanguage.rawValue,
            "screenshotLanguage": ScreenshotSettingsCopy.language.rawValue,
            "keys": (SettingsCopy.termKeys.map { "settings." + $0 } + ScreenshotSettingsCopy.Key.allCases.map(\.rawValue)).sorted(),
            "settingsKeyCount": SettingsCopy.termKeys.count,
            "screenshotKeyCount": ScreenshotSettingsCopy.Key.allCases.count,
            "copyTable": table,
            "knownGaps": [],
            "boundaries": ["Production Foundation copy providers only; app/UI not launched.",
                           "Production call sites are checked separately in source-wiring.json.",
                           "No preferences written, global hotkeys registered, or devices created."]
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        print("\(language): \(cases.count) checks, passed=\(passed), table=\(table)")
        exit(passed ? 0 : 1)
    }

    /// The settings language a `-AppleLanguages (x)` process must resolve to.
    static func expectedSettingsLanguage(_ language: String) -> String {
        switch language.lowercased() {
        case "zh-hant", "zh-tw", "zh-hk", "zh-mo": return "zh-Hant"
        case "zh-hans", "zh-cn", "zh": return "zh-Hans"
        default: return "en"
        }
    }
}
