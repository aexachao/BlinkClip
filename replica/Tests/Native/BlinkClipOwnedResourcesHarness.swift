import AppKit
import Foundation

// Test-only SPM accessor substitute: production bundle lookup is compiled unchanged.
extension Bundle {
    static var module: Bundle { Bundle(url: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("BlinkClip_BlinkClipCore.bundle"))! }
}

@main
struct BlinkClipOwnedResourcesHarness {
    @MainActor static func main() throws {
        let language = CommandLine.arguments[1]
        let out = URL(fileURLWithPath: CommandLine.arguments[2])
        var checks: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool, _ value: String = "") {
            checks.append(["case": name, "passed": passed, "value": value])
        }
        // An in-app language pick (Defaults.language) must not leak into a run
        // that only sets -AppleLanguages.
        UserDefaults.standard.removeObject(forKey: SettingsLanguage.preferenceKey)
        // zh-Hant is Traditional, never Simplified. The owned bundle ships no
        // zh-Hant table yet, so a zh-Hant reader gets English (the development
        // region) rather than Simplified-only glyphs.
        for (languages, expected) in [(["fr", "zh-Hans"], "en"), (["ja"], "en"), (["en"], "en"),
                                      (["zh-Hant"], "zh-Hant"), (["zh-TW"], "zh-Hant"),
                                      (["zh-HK"], "zh-Hant"), (["zh-MO"], "zh-Hant"),
                                      (["zh-Hans"], "zh-Hans"), (["", "zh-Hans"], "zh-Hans"),
                                      ([], "en")] {
            check("policy.\(languages)", ResourceBundle.selectedLocale(preferredLanguages: languages,
                                                                       storedAppLanguage: nil).identifier == expected)
        }
        let expectedActiveLocale = ["zh-Hant": "zh-Hant", "zh-Hans": "zh-Hans"][language] ?? "en"
        let enTableURL = ResourceBundle.bundle.bundleURL.appendingPathComponent("en.lproj/Localizable.strings")
        let hansTableURL = ResourceBundle.bundle.bundleURL.appendingPathComponent("zh-Hans.lproj/Localizable.strings")
        let enTable = try PropertyListSerialization.propertyList(from: Data(contentsOf: enTableURL), format: nil) as! [String: String]
        let hansTable = try PropertyListSerialization.propertyList(from: Data(contentsOf: hansTableURL), format: nil) as! [String: String]
        if language == "zh-Hant" {
            // Fallback order is zh-Hant -> en. Never zh-Hans.
            check("zh-hant-falls-back-to-english",
                  SettingsLocalization.text("settings.general.title") == enTable["settings.general.title"]
                  && SettingsLocalization.text("settings.general.title") != hansTable["settings.general.title"],
                  SettingsLocalization.text("settings.general.title"))
        }
        check("no-hant-table-yet", !ResourceBundle.bundle.localizations.contains("zh-Hant"),
              ResourceBundle.bundle.localizations.joined(separator: ","))
        check("active-locale", ResourceBundle.selectedLocale().identifier == expectedActiveLocale,
              Locale.preferredLanguages.description)
        // The table this build can actually show: Simplified for zh-Hans, and
        // English for zh-Hant while it has no table of its own.
        let tableLanguage = language == "zh-Hans" ? "zh-Hans" : "en"
        let simplified = tableLanguage == "zh-Hans"
        // No table of its own means the Traditional run falls back to the
        // English text. Chinese has a single CLDR plural category, so the
        // English "other" branch is selected even for 1 ("1 characters").
        // Recorded here instead of quietly expecting an English singular.
        let hantFallsBackToEnglish = language == "zh-Hant"
        func englishCount(_ count: Int32, _ singular: String, _ plural: String) -> String {
            count == 1 && !hantFallsBackToEnglish ? "\(count) " + singular : "\(count) " + plural
        }
        func englishFileCount(_ count: Int32) -> String {
            count == 1 && !hantFallsBackToEnglish ? "File" : "\(count) files"
        }
        let tableURL = ResourceBundle.bundle.bundleURL.appendingPathComponent(tableLanguage + ".lproj/Localizable.strings")
        let table = try PropertyListSerialization.propertyList(from: Data(contentsOf: tableURL), format: nil) as! [String: String]
        check("table-count", table.count == 126)
        for (key, expected) in table {
            check("settings.dynamic.\(key)", SettingsLocalization.text(key) == expected, SettingsLocalization.text(key))
            check("search.dynamic.\(key)", SearchLocalization.text(key) == expected)
            check("shortcut.dynamic.\(key)", ShortcutMessages.value(key) == expected)
        }
        for count: Int32 in [0, 1, 2] {
            for (name, resource, expected) in [
                ("characters", PreviewLocalization.characterCount(count), simplified ? "\(count) 个字符" : englishCount(count, "character", "characters")),
                ("words", PreviewLocalization.wordCount(count), simplified ? "\(count) 个词" : englishCount(count, "word", "words")),
                ("lines", PreviewLocalization.lineCount(count), simplified ? "\(count) 行" : englishCount(count, "line", "lines")),
                ("files", PreviewLocalization.fileCount(count), simplified ? "\(count) 个文件" : englishFileCount(count))
            ] {
                let value = String(localized: resource)
                check("plural.\(name).\(count)", value == expected, value)
            }
        }
        for (key, resource) in [("general.until", PreviewLocalization.untilTime("14:30")), ("general.action.open-in", PreviewLocalization.openInApplication("TestApp"))] {
            let value = String(localized: resource)
            let argument = key == "general.until" ? "14:30" : "TestApp"
            check("interpolation.\(key)", value == String(format: table[key]!, argument), value)
        }
        check("menu-interpolation", ShortcutMessages.menuConflict("Test Menu") == String(format: table["shortcut-recorder.error.used-in-menu"]!, "Test Menu"))
        check("preview-accessor", String(localized: PreviewLocalization.generalUntitled()) == table["general.untitled"])
        check("unavailable-accessor", String(localized: UnavailablePreviewLocalization.previewUnavailableTitle()) == table["preview.unavailable.title"])
        if language == "en" {
            for (name, size) in [("BlinkClipDirectPaste@2x", NSSize(width: 384, height: 256)),
                                 ("BlinkClipCopyToClipboard@2x", NSSize(width: 384, height: 256)),
                                 ("BlinkClipPermissions@2x", NSSize(width: 480, height: 288))] {
                let url = ResourceBundle.bundle.url(forResource: name, withExtension: "png")!
                let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url))!
                check("generated.dimensions.\(name)", bitmap.pixelsWide == Int(size.width) && bitmap.pixelsHigh == Int(size.height))
                check("generated.alpha.\(name)", bitmap.hasAlpha && bitmap.colorAt(x: 0, y: 0)?.alphaComponent == 0)
            }
            let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 400, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 640, height: 400).fill()
            for (index, pair) in [(false,false),(false,true),(true,false),(true,true)].enumerated() {
                let image = SettingsIllustrations.image(directPaste: pair.0, dark: pair.1)!
                check("settings.size.\(index)", image.size == NSSize(width: 192, height: 128))
                check("settings.generated.\(index)", image.representations.contains { $0 is NSBitmapImageRep })
                check("settings.cached.\(index)", image === BlinkClipAssetRenderer.settings(directPaste: pair.0, dark: pair.1))
                image.draw(in: NSRect(x: 20 + index * 140, y: 300, width: 96, height: 64))
            }
            for (index, category) in BlinkClipAssetRenderer.Category.allCases.enumerated() {
                let image = BlinkClipAssetRenderer.category(category)
                check("category.template.\(category)", image.isTemplate && image.size == NSSize(width: 20, height: 20))
                image.draw(in: NSRect(x: 30 + index * 70, y: 250, width: 18, height: 18))
            }
            for (index, dark) in [false, true].enumerated() {
                let image = BlinkClipAssetRenderer.permission(dark: dark)
                check("permission.size.\(dark)", image.size == NSSize(width: 240, height: 144))
                check("permission.generated.\(dark)", image.representations.contains { $0 is NSBitmapImageRep })
                check("permission.cached.\(dark)", image === BlinkClipAssetRenderer.permission(dark: dark))
                image.draw(in: NSRect(x: 20 + index * 300, y: 50, width: 240, height: 144))
            }
            NSGraphicsContext.restoreGraphicsState()
            try sheet.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("native-sizes.png"))
        }
        let passed = checks.allSatisfy { $0["passed"] as? Bool == true }
        try JSONSerialization.data(withJSONObject: ["language": language, "passed": passed, "checks": checks], options: [.prettyPrinted,.sortedKeys]).write(to: out.appendingPathComponent(language + ".json"))
        print("\(language): \(checks.count) checks, passed=\(passed)")
        exit(passed ? 0 : 1)
    }
}
