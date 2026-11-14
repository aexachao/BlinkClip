import AppKit

/// Native gate for the `capcap` → `blinkclip` identifier rename.
///
/// It exercises the two names the rename touches at runtime, against the real
/// production types (no doubles):
///
/// - `ClipboardHistorySkipMarker`: the pasteboard marker moved from
///   `cn.skyrin.capcap.skip-clipboard-text-history` to
///   `com.chrisli.blinkclip.skip-clipboard-text-history`.
/// - `LegacyPreferenceKey`: the read/write rules that keep a renamed
///   `UserDefaults` key from losing the user's value.
///
/// Both cases are asserted for the three states the ticket requires:
/// legacy-only, current-only, and neither (caller default).
@main struct IdentifierNamespaceMigrationHarness {
    static var checks = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static func main() {
        let pasteboardChecks = pasteboardMigrationChecks()
        let defaultsChecks = preferenceMigrationChecks()
        let namespaceChecks = namespaceChecks()
        print("""
        {"passed":true,"checks":\(checks),"pasteboard":\(pasteboardChecks),"preferences":\(defaultsChecks),"namespace":\(namespaceChecks),"boundary":"Real ClipboardHistorySkipMarker and LegacyPreferenceKey production sources; unique scratch NSPasteboard instances and a scratch UserDefaults suite. No clipboard monitor, no editor session."}
        """)
    }

    // MARK: - Pasteboard marker (transient transport value)

    static func pasteboardMigrationChecks() -> Int {
        let before = checks
        let current = ClipboardHistorySkipMarker.currentType
        let legacy = ClipboardHistorySkipMarker.legacyType

        check(current.rawValue == "com.chrisli.blinkclip.skip-clipboard-text-history",
              "marker uses the blinkclip namespace")
        check(legacy.rawValue == "cn.skyrin.capcap.skip-clipboard-text-history",
              "legacy marker name is still declared for the one-release read window")
        check(current != legacy, "the two spellings never collide")

        // 1. legacy-only: written by the previous build — still honoured.
        withScratchPasteboard { pasteboard in
            pasteboard.setString("1", forType: legacy)
            check(ClipboardHistorySkipMarker.isMarked(in: pasteboard),
                  "a pasteboard marked only with the legacy name is still skipped")
            check(pasteboard.availableType(from: [current]) == nil,
                  "the legacy-only pasteboard has no current-name marker yet")
        }

        // 2. current-only: written by this build — honoured, legacy ignored.
        withScratchPasteboard { pasteboard in
            pasteboard.setString("1", forType: current)
            check(ClipboardHistorySkipMarker.isMarked(in: pasteboard),
                  "a pasteboard marked with the current name is skipped")
            check(pasteboard.availableType(from: [legacy]) == nil,
                  "no legacy marker is invented on the read path")
        }

        // 3. both spellings present — still a single answer.
        withScratchPasteboard { pasteboard in
            pasteboard.setString("1", forType: current)
            pasteboard.setString("1", forType: legacy)
            check(ClipboardHistorySkipMarker.isMarked(in: pasteboard),
                  "a double-marked pasteboard is skipped exactly once")
        }

        // 4. neither: the caller default (record the item) applies.
        withScratchPasteboard { pasteboard in
            pasteboard.setString("plain text", forType: .string)
            check(!ClipboardHistorySkipMarker.isMarked(in: pasteboard),
                  "an unmarked pasteboard is recorded (default)")
        }

        // 5. write path: current name plus the legacy alias (downgrade window).
        withScratchPasteboard { pasteboard in
            pasteboard.setString("copied", forType: .string)
            ClipboardHistorySkipMarker.mark(pasteboard)
            check(pasteboard.string(forType: current) == "1", "current marker is written")
            check(pasteboard.string(forType: legacy) == "1", "legacy alias is written during the window")
            check(ClipboardHistorySkipMarker.isMarked(in: pasteboard), "the written marker reads back")
        }
        return checks - before
    }

    static func withScratchPasteboard(_ body: (NSPasteboard) -> Void) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("blinkclip.harness.identifier.\(UUID().uuidString)"))
        pasteboard.clearContents()
        body(pasteboard)
        pasteboard.releaseGlobally()
    }

    // MARK: - UserDefaults preference key (persisted value)

    static func preferenceMigrationChecks() -> Int {
        let before = checks
        let suite = "blinkclip.harness.identifier-migration"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("scratch defaults suite unavailable")
        }
        defaults.removePersistentDomain(forName: suite)

        let key = RenamedIdentifier(
            current: "blinkclip.harness.preference",
            legacy: "capcap.harness.preference"
        )

        // 1. Neither spelling present → nil, so the caller's own default applies.
        check(LegacyPreferenceKey.string(key, in: defaults) == nil,
              "absent in both spellings returns nil and leaves the caller default alone")
        check(LegacyPreferenceKey.bool(key, in: defaults) == nil,
              "an absent boolean is distinguishable from a stored false")

        // 2. Legacy only → the old value takes effect and is written to the new key.
        defaults.set("legacy-value", forKey: key.legacy)
        check(LegacyPreferenceKey.string(key, in: defaults) == "legacy-value",
              "legacy-only value is read when the new key is missing")
        check(defaults.string(forKey: key.current) == "legacy-value",
              "the legacy value is written back to the new key")
        defaults.removeObject(forKey: key.current)

        // 3. Current present → the legacy value is ignored, even when it is stale.
        defaults.set("current-value", forKey: key.current)
        check(LegacyPreferenceKey.string(key, in: defaults) == "current-value",
              "the new key wins over a stale legacy value")
        check(defaults.string(forKey: key.legacy) == "legacy-value",
              "the legacy key is never rewritten by a read")

        // 4. Writes only touch the new key; the legacy value survives the window.
        LegacyPreferenceKey.set("written-value", for: key, in: defaults)
        check(defaults.string(forKey: key.current) == "written-value", "writes land on the new key")
        check(defaults.string(forKey: key.legacy) == "legacy-value",
              "writes leave the legacy key alone (a downgrade keeps working)")

        // 5. Booleans keep the stored false intact and migrate it like a value.
        defaults.removeObject(forKey: key.current)
        defaults.set(false, forKey: key.legacy)
        check(LegacyPreferenceKey.bool(key, in: defaults) == false,
              "a stored false migrates as a value, not as 'absent'")
        check(defaults.object(forKey: key.current) != nil, "the migrated false exists in the new key")

        // 6. Integers round trip through the same rules.
        let intKey = RenamedIdentifier(current: "blinkclip.harness.count", legacy: "capcap.harness.count")
        defaults.removeObject(forKey: intKey.current)
        defaults.set(42, forKey: intKey.legacy)
        check(LegacyPreferenceKey.integer(intKey, in: defaults) == 42, "legacy integer migrates")
        check(defaults.integer(forKey: intKey.current) == 42, "migrated integer is written back")

        let legacyBeforeRemoval = defaults.object(forKey: key.legacy)
        LegacyPreferenceKey.set(nil, for: key, in: defaults)
        check(defaults.object(forKey: key.current) == nil, "removal clears only the new key")
        check(defaults.object(forKey: key.legacy) as? Bool == legacyBeforeRemoval as? Bool,
              "removal keeps the legacy key for the compatibility window")

        defaults.removePersistentDomain(forName: suite)
        return checks - before
    }

    // MARK: - Namespace spelling

    static func namespaceChecks() -> Int {
        let before = checks
        check(BlinkClipIdentifierNamespace.current == "blinkclip", "current namespace is blinkclip")
        check(BlinkClipIdentifierNamespace.legacy == "capcap", "legacy namespace is documented")
        let renamed = RenamedIdentifier(current: "blinkclip.queue", legacy: "capcap.queue")
        check(renamed.candidateNames == ["blinkclip.queue", "capcap.queue"],
              "readers try the current name first")
        check(renamed.writableNames == ["blinkclip.queue", "capcap.queue"],
              "writers keep the one-release alias")
        return checks - before
    }
}
