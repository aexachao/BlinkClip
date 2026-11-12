import AppKit
import BlinkClipCore

@MainActor
enum SourceAppColor {
    private static let palette: [UInt64: NSColor] = [
        0x62a9f5: .systemBlue,
        0xf0554d: .systemRed
    ]

    private static let fallback: NSColor = {
        let light = NSColor(red: CGFloat(142) / 255, green: CGFloat(142) / 255,
                            blue: CGFloat(147) / 255, alpha: 1)
        let dark = NSColor(red: CGFloat(152) / 255, green: CGFloat(152) / 255,
                           blue: CGFloat(157) / 255, alpha: 1)
        return NSColor(name: nil) { appearance in
            SearchAppearance.appearanceColor(appearance: appearance, dark: dark, light: light)
        }
    }()

    static func color(application: SourceApplicationRecord?) -> NSColor {
        // Missing rawColor is an old-record compatibility case, not a live icon-color estimate.
        guard let code = application?.rawColor else { return fallback }
        let color = ColorPreviewMetadataGenerator.color(code)
        let key = SourceApplicationColors.encoded(color)
        return palette[key] ?? color
    }
}
