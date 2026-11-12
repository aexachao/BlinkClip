import AppKit
import Foundation

public enum PasteboardRestore {
    public struct Options: OptionSet {
        public let rawValue: UInt8
        public init(rawValue: UInt8) { self.rawValue = rawValue }
        public static let plainOtherContent = Options(rawValue: 1 << 0)
        public static let plainTextAndLinks = Options(rawValue: 1 << 1)
        public static let plainText: Options = [.plainOtherContent, .plainTextAndLinks]
    }

    public struct Selection {
        public let kind: PasteboardContentKind
        public let items: [PasteboardItem]
        public let sourceBundleID: String?

        public init(kind: PasteboardContentKind, items: [PasteboardItem], sourceBundleID: String?) {
            self.kind = kind
            self.items = items
            self.sourceBundleID = sourceBundleID
        }
    }

    public static func usesPlainProjection(kind: PasteboardContentKind, options: Options) -> Bool {
        options.contains(kind == .text || kind == .link ? .plainTextAndLinks : .plainOtherContent)
    }

    /// Value portion of the original entity processor; callers supply decoded/prepared items.
    public static func itemsFromSelections(_ selections: [Selection], options: Options,
                                  removingTypesContaining ignoredTypes: [String]) -> [[PasteboardItem]] {
        let multiple = selections.count > 1
        let aggregatesText = selections.contains { $0.kind == .text || $0.kind == .link }
        var groups: [[PasteboardItem]] = []
        var contents: [NSAttributedString] = []
        for selection in selections {
            let items = usesPlainProjection(kind: selection.kind, options: options)
                ? textOnlyItems(selection.items) : selection.items
            for item in items {
                item.removeTypesMatching(removingTypesContaining: ignoredTypes)
                item.setString(selection.sourceBundleID ?? "", forType: "org.nspasteboard.source")
                item.addBlinkClipMarker()
            }
            if !multiple { return [items] }
            if aggregatesText {
                contents.append(contentsOf: items.compactMap { $0.attributedString() })
                groups.append([])
            } else {
                groups.append(items)
            }
        }
        let combined = joinedAttributedString(separator: "\n", contents: contents)
        if combined.length > 0 {
            let aggregate = PasteboardItem()
            aggregate.addBlinkClipMarker()
            if !options.contains(.plainTextAndLinks), let data = rtfData(combined) {
                aggregate.setData(data, forType: "public.rtf")
            } else {
                aggregate.setString(combined.string, forType: "public.utf8-plain-text")
            }
            groups.insert([aggregate], at: 0)
        }
        return groups
    }

    /// The original entity getter first decodes ItemData; this is its array projection.
    public static func textOnlyItems(_ items: [PasteboardItem]) -> [PasteboardItem] {
        items.compactMap { $0.plainTextString() }.map(PasteboardItem.itemWithString)
    }

    public static func joinedAttributedString(separator: String, contents: [NSAttributedString]) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: "")
        for content in contents {
            if !result.string.isEmpty { result.append(NSAttributedString(string: separator)) }
            result.append(content)
        }
        return result
    }

    public static func rtfData(_ content: NSAttributedString) -> Data? {
        try? content.data(from: NSRange(location: 0, length: content.length), documentAttributes: [
            .documentType: NSAttributedString.DocumentType.rtf,
            .characterEncoding: String.Encoding.utf8
        ])
    }
}
