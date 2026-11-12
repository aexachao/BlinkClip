import AppKit

@MainActor
public enum SelectionAppearance {
    public static func grayscaleColor(_ color: NSColor) -> NSColor {
        let converted = color.usingColorSpace(.sRGB) ?? color
        guard converted.colorSpace.colorSpaceModel == .rgb else { return color }
        return converted.usingColorSpace(.genericGray) ?? color
    }
}
