import Foundation

/// Shortcut copy uses the same owned-resource language policy as other Core copy.
enum ShortcutMessages {
    private static let bundle = ResourceBundle.bundle

    static func value(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(key), table: "Localizable",
            locale: ResourceBundle.selectedLocale(), bundle: .atURL(bundle.bundleURL)))
    }

    static func menuConflict(_ title: String) -> String {
        String(localized: LocalizedStringResource("shortcut-recorder.error.used-in-menu",
            defaultValue: "\(title)", table: "Localizable", locale: ResourceBundle.selectedLocale(),
            bundle: .atURL(bundle.bundleURL)))
    }
}
