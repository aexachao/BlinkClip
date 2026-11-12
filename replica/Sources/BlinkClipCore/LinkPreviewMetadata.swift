import Foundation

public struct LinkPreviewMetadata: Equatable, Sendable {
    public var url: URL
    public var name: String?
    public var iconData: Data?
    public var imageData: Data?

    public init(url: URL, name: String? = nil, iconData: Data? = nil, imageData: Data? = nil) {
        self.url = url
        self.name = name
        self.iconData = iconData
        self.imageData = imageData
    }
}

/// The local initial value, before its optional asynchronous provider branch.
public enum LinkPreviewMetadataGenerator {
    public static func generate(_ items: [PasteboardItem]) -> LinkPreviewMetadata? {
        guard let first = items.first, let url = first.url() else { return nil }
        let name = first.stringForType(forType: "public.url-name")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return LinkPreviewMetadata(url: url, name: name)
    }
}
