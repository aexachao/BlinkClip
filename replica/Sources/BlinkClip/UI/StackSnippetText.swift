import AppKit
import Foundation
import BlinkClipCore

@MainActor
enum StackSnippetText {
    /// derive the Stack label from stored preview metadata.
    static func snippetLabel(_ item: ClipboardItem) -> String {
        label(rawPreview: item.rawPreview) { count in
            PreviewTitles.titleOrDefault(item.originalTitle,
                defaultTitle: defaultTitle(item, fileCount: count))
        }
    }

    static func text(for input: ClipboardRestoreItem) -> String {
        guard input.hasNativeEntity else { return snippetLabel(input.resolvedItem()) }
        return label(rawPreview: input.previewMetadataData()) { _ in input.previewTitle()!.title }
    }

    private static func label(rawPreview: Data?, filesTitle: (Int) -> String) -> String {
        if let metadata = ImagePreviewMetadataCodec.decodeText(rawPreview) {
            return String(metadata.text.characters)
        }
        if let metadata = ImagePreviewMetadataCodec.decodeLink(rawPreview) {
            return metadata.url.absoluteString
        }
        if ImagePreviewMetadataCodec.decode(rawPreview) != nil { return "Unknown" }
        if let metadata = ImagePreviewMetadataCodec.decodeColor(rawPreview) {
            return PreviewColorFormatting.hexString(
                ColorPreviewMetadataGenerator.color(metadata.code))
        }
        if let metadata = ImagePreviewMetadataCodec.decodeFiles(rawPreview) {
            if metadata.paths.count > 1 {
                return filesTitle(metadata.paths.count)
            }
            if let path = metadata.paths.first {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        }
        return "Unknown"
    }

    private static func defaultTitle(_ item: ClipboardItem, fileCount: Int) -> String {
        let rawType: Int
        switch item.kind {
        case .text, .richText: rawType = 5
        case .image: rawType = 1
        case .files: rawType = 3
        case .link: rawType = 4
        case .color: rawType = 2
        case .unknown: rawType = 0
        }
        return PreviewTitles.itemTypeTitle(rawType: rawType, fileCount: fileCount)
    }
}
