import Foundation

public enum SearchLocalization {
    private static let bundle = ResourceBundle.bundle

    public static func text(_ key: String) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
            table: "Localizable", locale: ResourceBundle.selectedLocale(), bundle: .atURL(bundle.bundleURL)))
    }
}
