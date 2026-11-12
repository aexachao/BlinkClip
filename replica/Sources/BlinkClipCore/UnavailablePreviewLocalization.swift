import Foundation

/// The unsupported preview uses the original localizable keys and bundle fallback.
public enum UnavailablePreviewLocalization {
    private static let resourceBundle = ResourceBundle.bundle

    private static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
                                table: "Localizable", locale: ResourceBundle.selectedLocale(),
                                bundle: .atURL(resourceBundle.bundleURL))
    }

    public static func previewUnavailableTitle() -> LocalizedStringResource { resource("preview.unavailable.title") }
    public static func previewUnavailableSubtitle() -> LocalizedStringResource { resource("preview.unavailable.subtitle") }
}
