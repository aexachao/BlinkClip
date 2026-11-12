import AppKit

/// The search editor uses the same recovered font/color accessors as the
/// original. Swift static initialization supplies the original once storage.
public enum SearchAppearance {
    // A stable reference slot preserves the original storage-address accessor
    // separately from its value getter. The process-lifetime slot is deliberate.
    private static let foregroundSlot: UnsafeMutablePointer<NSColor?> = {
        let slot = UnsafeMutablePointer<NSColor?>.allocate(capacity: 1)
        slot.initialize(to: nil)
        return slot
    }()
    private static let foregroundInitialized: Void = setupForegroundColor()

    public static func foregroundColorSlot() -> UnsafeMutablePointer<NSColor?> {
        _ = foregroundInitialized
        return foregroundSlot
    }

    public static func foregroundColor() -> NSColor? { foregroundColorSlot().pointee }

    public static func setupForegroundColor() {
        let light = NSColor.black.withAlphaComponent(0.85)
        let dark = NSColor.white.withAlphaComponent(0.85)
        foregroundSlot.pointee = NSColor(name: nil) { appearance in
            appearanceColor(appearance: appearance, dark: dark, light: light)
        }
    }

    public static func appearanceColor(appearance: NSAppearance, dark: NSColor, light: NSColor) -> NSColor {
        resolvedAppearanceColor(appearance: appearance, dark: dark, light: light)
    }

    public static func resolvedAppearanceColor(appearance: NSAppearance, dark: NSColor, light: NSColor) -> NSColor {
        colorForAppearance(appearance: appearance, dark: dark, light: light)
    }

    public static func colorForAppearance(appearance: NSAppearance, dark: NSColor, light: NSColor) -> NSColor {
        let darkNames: [NSAppearance.Name] = [.darkAqua, .vibrantDark,
            .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]
        return appearance.bestMatch(from: darkNames) == nil ? light : dark
    }

    public static func bodyFont() -> NSFont { preferredFont(style: .body) }

    public static func preferredFont(style: NSFont.TextStyle) -> NSFont {
        NSFont.preferredFont(forTextStyle: style, options: [:])
    }

    /// The short search label in the reference's supported localizations.
    /// This does not replace or claim migration of the general localization API.
    public static func searchPlaceholder(locale: Locale = .current) -> String {
        let values = ["cs": "Hledat", "da": "Søg", "de": "Suchen", "en": "Search",
            "es": "Buscar", "fr": "Rechercher", "he": "חיפוש", "it": "Cerca",
            "ja": "検索", "ko": "검색", "nl": "Zoek", "pl": "Szukaj",
            "pt-BR": "Buscar", "pt-PT": "Pesquisar", "ru": "Поиск",
            "zh-Hans": "搜索", "zh-Hant": "搜尋"]
        let localizations = ["en"] + values.keys.filter { $0 != "en" }.sorted()
        let language = Bundle.preferredLocalizations(from: localizations,
            forPreferences: [locale.identifier]).first ?? "en"
        return values[language] ?? "Search"
    }
}
