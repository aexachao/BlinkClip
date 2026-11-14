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
        let zh = language.hasPrefix("zh")
        var checks: [[String: Any]] = []
        func check(_ name: String, _ passed: Bool, _ value: String = "") {
            checks.append(["case": name, "passed": passed, "value": value])
        }
        for (languages, expected) in [(["fr", "zh-Hans"], "en"), (["ja"], "en"), (["en"], "en"), (["zh-Hant"], "zh-Hans"), (["", "zh-Hans"], "zh-Hans"), ([], "en")] {
            check("policy.\(languages)", ResourceBundle.selectedLocale(preferredLanguages: languages).identifier == expected)
        }
        check("active-locale", ResourceBundle.selectedLocale().identifier == (zh ? "zh-Hans" : "en"), Locale.preferredLanguages.description)
        let tableURL = ResourceBundle.bundle.bundleURL.appendingPathComponent((zh ? "zh-Hans" : "en") + ".lproj/Localizable.strings")
        let table = try PropertyListSerialization.propertyList(from: Data(contentsOf: tableURL), format: nil) as! [String: String]
        check("table-count", table.count == 126)
        for (key, expected) in table {
            check("settings.dynamic.\(key)", SettingsLocalization.text(key) == expected, SettingsLocalization.text(key))
            check("search.dynamic.\(key)", SearchLocalization.text(key) == expected)
            check("shortcut.dynamic.\(key)", ShortcutMessages.value(key) == expected)
        }
        for count: Int32 in [0, 1, 2] {
            for (name, resource, expected) in [
                ("characters", PreviewLocalization.characterCount(count), zh ? "\(count) 个字符" : "\(count) " + (count == 1 ? "character" : "characters")),
                ("words", PreviewLocalization.wordCount(count), zh ? "\(count) 个词" : "\(count) " + (count == 1 ? "word" : "words")),
                ("lines", PreviewLocalization.lineCount(count), zh ? "\(count) 行" : "\(count) " + (count == 1 ? "line" : "lines")),
                ("files", PreviewLocalization.fileCount(count), zh ? "\(count) 个文件" : (count == 1 ? "File" : "\(count) files"))
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
