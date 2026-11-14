import Foundation

private final class ResourceBundleFinder: NSObject { }

/// Locates the owned resources packaged with the Core module.
enum ResourceBundle {
    /// Unsupported languages deliberately use English copy and English plural
    /// rules. `zh-Hant` resolves to Traditional, not Simplified: the shipped
    /// bundle carries no `zh-Hant.lproj`, so `String(localized:)` falls back to
    /// the development region (English) for those keys. It never falls back to
    /// the Simplified table, so a Traditional reader is not served
    /// Simplified-only glyphs.
    static func selectedLocale(preferredLanguages: [String] = Locale.preferredLanguages,
                               storedAppLanguage: String? = UserDefaults.standard.string(forKey: SettingsLanguage.preferenceKey)) -> Locale {
        let first = preferredLanguages.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "en"
        return Locale(identifier: SettingsLanguage.resolved(preferredLanguages: [first],
                                                            storedAppLanguage: storedAppLanguage).rawValue)
    }

    static let bundle: Bundle = {
        let directories = [Bundle.main.resourceURL,
                           Bundle(for: ResourceBundleFinder.self).resourceURL,
                           Bundle.main.bundleURL].compactMap { $0 }
        for directory in directories {
            if let bundle = Bundle(url: directory.appendingPathComponent("BlinkClip_BlinkClipCore.bundle")) {
                return bundle
            }
        }
        return Bundle.module
    }()
}
