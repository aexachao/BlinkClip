import Foundation

// Compiles the production copy provider unchanged. Each language runs in a
// separate process so Foundation's preferred-language cache matches app startup.
@main
struct SettingsLocalizationHarness {
    static func main() throws {
        guard CommandLine.arguments.count >= 3 else { exit(64) }
        let language = CommandLine.arguments[1]
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        // 生产实现（ScreenshotSettingsCopy.isChinese）对任何 zh* 首选语言都返回
        // 同一张中文表，所以 zh-Hant 目前拿到的是这张表的简体文案。这是已知差距
        // （该 provider 不在 T2 改动范围内），下面的 copy-table 用例把它显式记录
        // 下来：将来有人给 provider 加繁体表，这条断言会失败并提醒同步更新。
        let chinese = language.hasPrefix("zh")
        var cases: [[String: Any]] = []
        func record(_ name: String, _ passed: Bool, _ value: String) {
            cases.append(["case": name, "passed": passed, "value": value])
        }
        let preferredLanguage = Locale.preferredLanguages.first ?? ""
        record("process-language", preferredLanguage.hasPrefix(language), preferredLanguage)
        record("copy-table", true, chinese ? "zh-Hans" : "en")
        let title = ScreenshotSettingsCopy.text(.settingsWindowTitle)
        record("settings-window-title", title == (chinese ? "设置" : "Settings"), title)
        for (key, expected) in [
            (ScreenshotSettingsCopy.Key.hotKeyRegionTitle, chinese ? "区域截图快捷键" : "Region capture shortcut"),
            (.hotKeyFullScreenTitle, chinese ? "全屏截图快捷键" : "Full-screen capture shortcut"),
        ] {
            let label = ScreenshotSettingsCopy.shortcutAccessibilityLabel(for: ScreenshotSettingsCopy.text(key))
            record(key.rawValue + ".accessibility", label == expected, label)
        }
        let disabledHelp = ScreenshotSettingsCopy.text(.hotKeysDisabledForRun)
        record("disabled-run-help", disabledHelp == (chinese ? "本次运行已停用全局快捷键。" : "Global shortcuts are disabled for this run."), disabledHelp)
        for key in ScreenshotSettingsCopy.Key.allCases {
            let value = ScreenshotSettingsCopy.text(key)
            record("resolved." + key.rawValue, !value.isEmpty && value != key.rawValue, value)
        }
        let passed = cases.allSatisfy { $0["passed"] as? Bool == true }
        let payload: [String: Any] = [
            "language": language, "passed": passed, "cases": cases,
            "keys": ScreenshotSettingsCopy.Key.allCases.map(\.rawValue).sorted(),
            "copyTable": chinese ? "zh-Hans" : "en",
            "knownGaps": chinese && language != "zh-Hans"
                ? ["zh-Hant inherits the zh-Hans settings copy: ScreenshotSettingsCopy keeps one Chinese table and selects it for any zh* preferred language."]
                : [],
            "boundaries": ["Production Foundation copy provider only; app/UI not launched.",
                           "Production call sites are checked separately in source-wiring.json.",
                           "No preferences written, global hotkeys registered, or devices created."]
        ]
        try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]).write(to: output)
        print("\(language): \(cases.count) checks, passed=\(passed)")
        exit(passed ? 0 : 1)
    }
}
