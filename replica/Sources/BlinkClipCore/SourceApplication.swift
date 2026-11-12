import AppKit
import Foundation

public struct SourceApplicationRecord: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var name: String
    public var rawIcon: Data?
    public var rawColor: UInt64?

    public init(bundleIdentifier: String, name: String, rawIcon: Data?, rawColor: UInt64? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.rawIcon = rawIcon
        self.rawColor = rawColor
    }
}

public enum SourceApplication {
    @MainActor
    public static func snapshot(_ app: NSRunningApplication?) -> SourceApplicationRecord? {
        guard let app, let identifier = app.bundleIdentifier,
              let name = app.localizedName, let icon = app.icon else { return nil }
        icon.size = NSSize(width: 128, height: 128)
        return SourceApplicationRecord(bundleIdentifier: identifier, name: name,
                                       rawIcon: PasteboardImageEncoding.pngData(icon),
                                       rawColor: SourceApplicationColors.rawColor(bundleIdentifier: identifier, image: icon))
    }

    static func normalizedIcon(_ data: Data?) -> Data? {
        guard let data, let image = NSImage(data: data) else { return nil }
        return PasteboardImageEncoding.pngData(image)
    }
}
