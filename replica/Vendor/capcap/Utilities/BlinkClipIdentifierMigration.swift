import Foundation

/// Namespacing used by every process-local identifier in the vendored engine.
///
/// The engine used to spell them with a `capcap` namespace. They are now spelled
/// with `blinkclip`, matching the app's bundle identifier (`com.chrisli.blinkclip`),
/// the logger subsystem (`com.chrisli.blinkclip`) and the taste of the reverse-DNS
/// pasteboard types (`com.chrisli.blinkclip.internal.*`) that BlinkClipCore writes.
enum BlinkClipIdentifierNamespace {
    static let current = "blinkclip"
    static let legacy = "capcap"
}

/// One identifier that was renamed once (`capcap` → `blinkclip`).
///
/// Persisted or in-flight values written by the previous build still carry the
/// old spelling, so readers ask for `candidateNames` (current first, legacy as the
/// one-release fallback) while writers emit `writableNames` (current plus the
/// legacy alias) until the compatibility window closes.
struct RenamedIdentifier: Equatable {
    let current: String
    let legacy: String

    /// Current spelling first; the legacy spelling is only consulted when the
    /// current one is absent, so a value stored under both is never ambiguous.
    var candidateNames: [String] { [current, legacy] }

    /// The current spelling plus the legacy alias, for the one release in which
    /// the previous build may still read what this build writes.
    var writableNames: [String] { [current, legacy] }
}

/// Reads a renamed `UserDefaults` key without dropping the user's value.
///
/// Read: the new key wins; when it is absent the legacy value is returned *and*
/// written back to the new key, so the next read is new-key only. The legacy read
/// path stays for one release cycle so a downgrade or a second launch of the old
/// build still sees the setting.
///
/// Write: only the new key is touched. The legacy key is left untouched (never
/// cleared) so the previous build keeps working during the window.
enum LegacyPreferenceKey {
    static func string(_ key: RenamedIdentifier, in defaults: UserDefaults) -> String? {
        if let value = defaults.string(forKey: key.current) { return value }
        guard let legacy = defaults.string(forKey: key.legacy) else { return nil }
        defaults.set(legacy, forKey: key.current)
        return legacy
    }

    static func integer(_ key: RenamedIdentifier, in defaults: UserDefaults) -> Int? {
        if defaults.object(forKey: key.current) != nil { return defaults.integer(forKey: key.current) }
        guard defaults.object(forKey: key.legacy) != nil else { return nil }
        let legacy = defaults.integer(forKey: key.legacy)
        defaults.set(legacy, forKey: key.current)
        return legacy
    }

    /// `nil` means "absent in both spellings", which callers turn into their own
    /// default; a stored `false` is distinguishable from a missing key.
    static func bool(_ key: RenamedIdentifier, in defaults: UserDefaults) -> Bool? {
        if defaults.object(forKey: key.current) != nil { return defaults.bool(forKey: key.current) }
        guard defaults.object(forKey: key.legacy) != nil else { return nil }
        let legacy = defaults.bool(forKey: key.legacy)
        defaults.set(legacy, forKey: key.current)
        return legacy
    }

    static func set(_ value: Any?, for key: RenamedIdentifier, in defaults: UserDefaults) {
        guard let value else {
            defaults.removeObject(forKey: key.current)
            return
        }
        defaults.set(value, forKey: key.current)
    }
}
