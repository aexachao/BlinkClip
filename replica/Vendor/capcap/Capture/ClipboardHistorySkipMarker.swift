import AppKit

/// Marker written next to text the engine copies itself, telling
/// `ClipboardTextHistoryMonitor` not to re-record it.
///
/// Renamed with the rest of the identifiers: `cn.skyrin.capcap.…` →
/// `com.chrisli.blinkclip.…`. The legacy spelling is still read (a pasteboard
/// filled by the previous build is a live transport value, not a preference, so
/// the read path keeps both names for one release) and still written as an alias
/// so a downgrade keeps its own skip behaviour.
enum ClipboardHistorySkipMarker {
    static let identifier = RenamedIdentifier(
        current: "com.chrisli.blinkclip.skip-clipboard-text-history",
        legacy: "cn.skyrin.capcap.skip-clipboard-text-history"
    )

    static var currentType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(identifier.current)
    }

    static var legacyType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(identifier.legacy)
    }

    /// New name first, legacy name as the one-release fallback.
    static func isMarked(in pasteboard: NSPasteboard) -> Bool {
        let types = identifier.candidateNames.map { NSPasteboard.PasteboardType($0) }
        return pasteboard.availableType(from: types) != nil
    }

    /// Writes the current name plus the legacy alias (dual-write window).
    /// Never called on read: rewriting a pasteboard someone else owns would
    /// bump `changeCount` and wake every clipboard monitor.
    static func mark(_ pasteboard: NSPasteboard) {
        for name in identifier.writableNames {
            pasteboard.setString("1", forType: NSPasteboard.PasteboardType(name))
        }
    }
}
