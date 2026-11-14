import Foundation

/// The three languages the settings chrome can render its own copy in.
///
/// Why this exists instead of reading `AppLanguage` / `Defaults.language`
/// directly: both live in the vendored `BlinkClipCapture` module and are
/// `internal` there, so the settings UI cannot see them. This mirrors the same
/// `appLanguage` preference (`Defaults.language`'s storage key) and the same
/// preferred-language order from `AppLanguage.systemDefault`, at an access
/// level every target and every isolated native harness can use.
///
/// `zh-Hant` — and the Apple aliases `zh-TW` / `zh-HK` / `zh-MO` — is
/// Traditional. No branch may treat "any zh" as Simplified.
public enum SettingsLanguage: String, CaseIterable, Sendable {
    case en
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"

    /// `Defaults.language`'s storage key, kept stable for compatibility.
    public static let preferenceKey = "appLanguage"

    /// An explicit in-app pick wins — including an unsupported one, which
    /// renders English rather than a language the user did not choose. Only
    /// when nothing is stored does the system's first supported preferred
    /// language decide.
    public static func resolved(preferredLanguages: [String] = Locale.preferredLanguages,
                                storedAppLanguage: String? = UserDefaults.standard.string(forKey: preferenceKey)) -> SettingsLanguage {
        if let storedAppLanguage, !storedAppLanguage.isEmpty {
            return SettingsLanguage(appLanguage: storedAppLanguage) ?? .en
        }
        return settingsLanguage(preferredLanguages: preferredLanguages)
    }

    /// Pure preferred-language match, in order. `zh-Hant` aliases first so a
    /// `zh-HK` system language is Traditional, not Simplified.
    public static func settingsLanguage(preferredLanguages: [String]) -> SettingsLanguage {
        for code in preferredLanguages {
            let lower = code.lowercased()
            if lower.hasPrefix("zh-hant") || lower.hasPrefix("zh-tw")
                || lower.hasPrefix("zh-hk") || lower.hasPrefix("zh-mo") {
                return .zhHant
            }
            if lower.hasPrefix("zh") { return .zhHans }
            if lower.hasPrefix("en") { return .en }
        }
        return .en
    }

    /// `AppLanguage` raw values: "zh" is Simplified, "zh-Hant" is Traditional.
    /// A stored language this chrome has no table for (ja, ko, fr, ru, vi) is
    /// reported as `nil` so the caller can fall back to English — never to a
    /// Chinese table the user did not pick.
    private init?(appLanguage: String) {
        switch appLanguage {
        case "zh", "zh-Hans": self = .zhHans
        case "zh-Hant": self = .zhHant
        case "en": self = .en
        default: return nil
        }
    }
}

/// One trilingual lookup for the settings chrome: `zh-Hans`, `zh-Hant`, `en`
/// are all supplied at the call site, so a missing translation is a compile-time
/// shape error rather than a silent fallback to Simplified.
public enum SettingsStrings {
    public static func trilingual(_ zhHans: String, _ zhHant: String, _ en: String,
                                  language: SettingsLanguage = .resolved()) -> String {
        switch language {
        case .zhHans: return zhHans
        case .zhHant: return zhHant
        case .en: return en
        }
    }
}
