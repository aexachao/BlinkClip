import AppKit
import Foundation
import QuickLook

public struct FilePreviewMetadata: Equatable, Sendable {
    public var paths: [String]
    public var totalSize: Int
    public var previewData: Data?

    public init(paths: [String], totalSize: Int, previewData: Data? = nil) {
        self.paths = paths
        self.totalSize = totalSize
        self.previewData = previewData
    }
}

public enum FilePreviewMetadataGenerator {
    @MainActor
    public static func generate(_ items: [PasteboardItem],
                                preferQuickLookThumbnails: Bool) -> FilePreviewMetadata {
        let urls = items.compactMap { $0.fileURL() }
        let size: Int
        let preview: Data?
        if let first = urls.first {
            size = (try? first.resourceValues(forKeys: [.totalFileSizeKey]))?.totalFileSize ?? 0
            preview = quickLookThumbnailData(first, preferQuickLookThumbnails: preferQuickLookThumbnails)
        } else {
            size = 0
            preview = nil
        }
        return FilePreviewMetadata(paths: urls.map(\.path), totalSize: size, previewData: preview)
    }

    @MainActor
    private static func quickLookThumbnailData(_ url: URL, preferQuickLookThumbnails: Bool) -> Data? {
        if preferQuickLookThumbnails,
           let thumbnail = QLThumbnailImageCreate(kCFAllocatorDefault, url as CFURL,
                                                   CGSize(width: 256, height: 256),
                                                   [kQLThumbnailOptionIconModeKey! as String: true] as CFDictionary) {
            let image = NSImage(cgImage: thumbnail.takeRetainedValue(), size: .zero)
            return PasteboardImageEncoding.pngData(image)
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 128, height: 128)
        return PasteboardImageEncoding.pngData(image)
    }
}
