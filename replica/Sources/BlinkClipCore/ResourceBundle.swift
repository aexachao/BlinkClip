import Foundation

private final class ResourceBundleFinder: NSObject { }

/// Locates the owned resources packaged with the Core module.
enum ResourceBundle {
    /// Unsupported languages deliberately use English copy and English plural rules.
    static func selectedLocale(preferredLanguages: [String] = Locale.preferredLanguages) -> Locale {
        let first = preferredLanguages.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "en"
        return Locale(identifier: first.lowercased().hasPrefix("zh") ? "zh-Hans" : "en")
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
