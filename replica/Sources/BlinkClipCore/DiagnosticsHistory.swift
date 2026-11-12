import AppKit
import UniformTypeIdentifiers

extension DiagnosticsManager {
    /// The replica's repository creates the file item before history restores it.
    public func captureDiagnosticsFile(store: ClipboardStore, pasteboard: NSPasteboard) throws -> UUID? {
        guard let file = currentFileURL() else { return nil }
        let item = PasteboardItem()
        item.setString(file.absoluteString, forType: UTType.fileURL.identifier)
        guard let id = try store.capture(pasteboard: pasteboard, sourceName: "BlinkClip",
                                         sourceBundleID: Bundle.main.bundleIdentifier,
                                         snapshot: [item], respectMonitoringPolicy: false) else {
            throw PasteboardItemCreationError.emptyContent
        }
        try store.writeToPasteboard(ids: [id], pasteboard: pasteboard)
        return id
    }
}
