import AppKit
import Foundation

public struct TextPreviewMetadata: Equatable, Sendable {
    public var length: Int
    public var text: AttributedString

    public init(length: Int, text: AttributedString) {
        self.length = length
        self.text = text
    }
}

public enum TextPreviewMetadataGenerator {
    @MainActor
    public static func generate(_ items: [PasteboardItem]) -> TextPreviewMetadata? {
        guard let source = items.first?.attributedString() else { return nil }
        let length = source.length
        let sample = length > 500
            ? source.attributedSubstring(from: NSRange(location: 0, length: 500)) : source
        return TextPreviewMetadata(length: length, text: AttributedString(sample))
    }
}
