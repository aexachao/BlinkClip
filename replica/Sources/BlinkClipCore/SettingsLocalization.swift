import Foundation

public enum SettingsLocalization {
    private static let resourceBundle = ResourceBundle.bundle

    private static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
                                table: "Localizable", locale: ResourceBundle.selectedLocale(),
                                bundle: .atURL(resourceBundle.bundleURL))
    }

    public static func text(_ key: String) -> String {
        String(localized: resource(key))
    }

    public static func settingsGeneralTitle() -> LocalizedStringResource { resource("settings.general.title") }
    public static func settingsPrivacyTitle() -> LocalizedStringResource { resource("settings.privacy.title") }
    public static func settingsSoundEffectsTitle() -> LocalizedStringResource { resource("settings.sound-effects.title") }
}
