import AppKit

/// Recovered preview colors are weighted by UTF-16 coverage, including uncovered text.
@MainActor
public enum PreviewTextColors {
    private static let backgroundSlot: UnsafeMutablePointer<NSColor?> = {
        let slot = UnsafeMutablePointer<NSColor?>.allocate(capacity: 1)
        slot.initialize(to: nil)
        return slot
    }()
    private static let backgroundInitialized: Void = setupBackgroundColor()

    public static func setupBackgroundColor() {
        let light = NSColor.white
        let dark = NSColor(red: 20.0 / 255, green: 20.0 / 255, blue: 20.0 / 255, alpha: 1)
        backgroundSlot.pointee = NSColor(name: nil) { appearance in
            SearchAppearance.appearanceColor(appearance: appearance, dark: dark, light: light)
        }
    }

    public static func backgroundColorSlot() -> UnsafeMutablePointer<NSColor?> {
        _ = backgroundInitialized
        return backgroundSlot
    }

    public static func addToCounts(_ value: Any?, range: NSRange, counts: NSCountedSet) {
        guard let value else { return }
        precondition(range.length >= 0)
        for _ in 0..<range.length { counts.add(value) }
    }

    public static func addValueToCounts(_ value: Any?, range: NSRange, counts: NSCountedSet) {
        addToCounts(value, range: range, counts: counts)
    }

    private static func counts(_ source: NSAttributedString, key: NSAttributedString.Key) -> NSCountedSet {
        let result = NSCountedSet()
        source.enumerateAttribute(key, in: NSRange(location: 0, length: source.length), options: []) { value, range, _ in
            addValueToCounts(value, range: range, counts: result)
        }
        return result
    }

    public static func hasNoForegroundColor(_ source: NSAttributedString) -> Bool {
        counts(source, key: .foregroundColor).count == 0
    }

    public static func sortColorsByCount(_ colors: inout [(color: NSColor, count: Int)]) {
        colors.sort { $0.count > $1.count }
    }

    public static func isLightColor(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return false }
        let red = rgb.redComponent
        let green = rgb.greenComponent
        let blue = rgb.blueComponent
        _ = rgb.alphaComponent
        return 0.55 < (red * 299 + green * 587 + blue * 114) / 1000
    }

    public static func dominantBackgroundColor(_ source: NSAttributedString) -> NSColor {
        let backgrounds = counts(source, key: .backgroundColor)
        let foregrounds = counts(source, key: .foregroundColor)
        var backgroundColors: [(color: NSColor, count: Int)] = []
        var backgroundCoverage = 0
        for value in backgrounds {
            let count = backgrounds.count(for: value)
            backgroundColors.append((value as! NSColor, count))
            backgroundCoverage += count
        }
        var foregroundColors: [(color: NSColor, count: Int)] = []
        var foregroundCoverage = 0
        for value in foregrounds {
            let count = foregrounds.count(for: value)
            foregroundColors.append((value as! NSColor, count))
            foregroundCoverage += count
        }
        var dominantForeground = SearchAppearance.foregroundColor()!
        foregroundColors.append((dominantForeground, source.length - foregroundCoverage))
        sortColorsByCount(&foregroundColors)
        if let first = foregroundColors.first { dominantForeground = first.color }
        let fallback: NSColor
        if isLightColor(dominantForeground) {
            fallback = NSColor(red: 30.0 / 255, green: 30.0 / 255, blue: 30.0 / 255, alpha: 1)
        } else { fallback = .white }
        backgroundColors.append((fallback, source.length - backgroundCoverage))
        sortColorsByCount(&backgroundColors)
        return backgroundColors.first?.color ?? fallback
    }

    /// background always changes; foreground changes only when absent.
    @discardableResult
    public static func applyPreviewTextColors(original: NSAttributedString, editor: NSTextView) -> Int {
        let isPlain = PreviewAttributedText.isPlainText(original)
        let background: NSColor
        let foreground: NSColor?
        if isPlain {
            background = backgroundColorSlot().pointee!
            foreground = SearchAppearance.foregroundColor()
        } else {
            background = dominantBackgroundColor(original)
            foreground = hasNoForegroundColor(original) ? SearchAppearance.foregroundColor() : nil
        }
        editor.backgroundColor = background
        if let foreground { editor.textColor = foreground }
        if isPlain, !editor.isEditable { editor.font = PreviewAttributedText.bodyFont() }
        return 0
    }
}
