import AppKit

/// Independently authored artwork; the existing picker API remains stable.
public enum SettingsIllustrations {
    @MainActor private static let images: [String: NSImage] = {
        var result: [String: NSImage] = [:]
        for directPaste in [false, true] {
            for dark in [false, true] {
                result["\(directPaste)-\(dark)"] = BlinkClipAssetRenderer.settings(directPaste: directPaste, dark: dark)
            }
        }
        return result
    }()

    @MainActor public static func image(directPaste: Bool, dark: Bool) -> NSImage? {
        images["\(directPaste)-\(dark)"]
    }
}
