import Foundation

/// Local content projections of the original ContentMetadata.Stored wire record.
/// The original configuration lookup stays separate.
public enum ImagePreviewMetadataCodec {
    public static func decode(_ rawPreview: Data?) -> ImagePreviewMetadata? {
        guard let stored = decodeStored(rawPreview), stored.type == "image" else { return nil }
        let size = stored.imageSize ?? .zero
        return ImagePreviewMetadata(width: size.width, height: size.height,
                                            previewData: stored.imageData ?? Data())
    }

    public static func decodeFiles(_ rawPreview: Data?) -> FilePreviewMetadata? {
        guard let stored = decodeStored(rawPreview), stored.type == "files" else { return nil }
        return FilePreviewMetadata(paths: stored.filePaths ?? [], totalSize: stored.filesTotalSize ?? 0,
                                           previewData: stored.filesImageData ?? Data())
    }

    public static func decodeColor(_ rawPreview: Data?) -> ColorPreviewMetadata? {
        guard let stored = decodeStored(rawPreview), stored.type == "color" else { return nil }
        return ColorPreviewMetadata(code: stored.colorCode ?? 0)
    }

    public static func decodeLink(_ rawPreview: Data?) -> LinkPreviewMetadata? {
        guard let stored = decodeStored(rawPreview), stored.type == "link" else { return nil }
        return LinkPreviewMetadata(url: stored.url ?? URL(string: "example.com")!,
                                           name: stored.urlName, iconData: stored.urlIconData,
                                           imageData: stored.urlImageData)
    }

    public static func decodeText(_ rawPreview: Data?) -> TextPreviewMetadata? {
        guard let stored = decodeStored(rawPreview) else { return nil }
        switch stored.type {
        case "link", "image", "color", "files": return nil
        default: return TextPreviewMetadata(length: stored.textLength ?? 0,
                                                    text: stored.text ?? AttributedString())
        }
    }

    private static func decodeStored(_ rawPreview: Data?) -> Stored? {
        guard let rawPreview else { return nil }
        return (try? PropertyListDecoder().decode(Stored.self, from: rawPreview))
            ?? (try? JSONDecoder().decode(Stored.self, from: rawPreview))
    }

    public static func encode(_ metadata: ImagePreviewMetadata?, binaryPropertyList: Bool) -> Data? {
        guard let metadata else { return nil }
        var stored = Stored()
        stored.type = "image"
        stored.imageSize = metadata.size
        stored.imageData = metadata.previewData
        return encodeStored(stored, binaryPropertyList: binaryPropertyList)
    }

    public static func encodeFiles(_ metadata: FilePreviewMetadata?, binaryPropertyList: Bool) -> Data? {
        guard let metadata else { return nil }
        var stored = Stored()
        stored.type = "files"
        stored.filePaths = metadata.paths
        stored.filesTotalSize = metadata.totalSize
        stored.filesImageData = metadata.previewData
        return encodeStored(stored, binaryPropertyList: binaryPropertyList)
    }

    public static func encodeColor(_ metadata: ColorPreviewMetadata?, binaryPropertyList: Bool) -> Data? {
        guard let metadata else { return nil }
        var stored = Stored()
        stored.type = "color"
        stored.colorCode = metadata.code
        return encodeStored(stored, binaryPropertyList: binaryPropertyList)
    }

    public static func encodeText(_ metadata: TextPreviewMetadata?, binaryPropertyList: Bool) -> Data? {
        guard let metadata else { return nil }
        var stored = Stored()
        stored.type = "text"
        stored.textLength = metadata.length
        stored.text = metadata.text
        return encodeStored(stored, binaryPropertyList: binaryPropertyList)
    }

    public static func encodeLink(_ metadata: LinkPreviewMetadata?, binaryPropertyList: Bool) -> Data? {
        guard let metadata else { return nil }
        var stored = Stored()
        stored.type = "link"
        stored.url = metadata.url
        stored.urlName = metadata.name
        stored.urlIconData = metadata.iconData
        stored.urlImageData = metadata.imageData
        return encodeStored(stored, binaryPropertyList: binaryPropertyList)
    }

    private static func encodeStored(_ stored: Stored, binaryPropertyList: Bool) -> Data? {
        if binaryPropertyList {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            return try? encoder.encode(stored)
        }
        return try? JSONEncoder().encode(stored)
    }

    // All original fields are decoded, including optional fields irrelevant to
    // images: a malformed present value makes decoding the whole record fail.
    private struct Stored: Codable {
        var type: String?
        var textLength: Int?
        var text: AttributedString?
        var url: URL?
        var urlName: String?
        var urlIconData: Data?
        var urlImageData: Data?
        var imageSize: CGSize?
        var imageData: Data?
        var filePaths: [String]?
        var filesTotalSize: Int?
        var filesImageData: Data?
        var colorCode: UInt64?
    }
}
