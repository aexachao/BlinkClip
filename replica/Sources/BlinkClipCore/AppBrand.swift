import Foundation

/// Display branding only. Persisted identifiers and storage paths remain stable across upgrades.
public enum AppBrand {
    public static let chineseName = "闪贴"
    public static let englishName = "BlinkClip"

    public static var name: String {
        name(preferredLanguages: Locale.preferredLanguages)
    }

    public static func name(preferredLanguages: [String]) -> String {
        preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? chineseName : englishName
    }

}
