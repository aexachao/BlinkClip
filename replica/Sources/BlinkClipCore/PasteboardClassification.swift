import Foundation
import UniformTypeIdentifiers

public enum PasteboardContentKind: UInt8 {
    case unknown = 0, image = 1, color = 2, files = 3, link = 4, text = 5
}

public enum PasteboardClassification {
    public static let priorityTypes: [UTType] = [
        .fileURL, .rtf, .png, .jpeg, .heic, .tiff, .icns, .url, .utf8PlainText, .plainText, .text
    ]
    public static let typeMap: [UTType: PasteboardContentKind] = Dictionary(uniqueKeysWithValues: [
        (.fileURL, .files), (.png, .image), (.jpeg, .image), (.heic, .image), (.tiff, .image), (.icns, .image),
        (.url, .link), (.rtf, .text), (.utf8PlainText, .text), (.plainText, .text), (.text, .text)
    ])

    public static func isHexColor(_ string: String) -> Bool {
        guard string.range(of: "^#?[A-Fa-f0-9]{6}$", options: .regularExpression) != nil else { return false }
        return string.hasPrefix("#") || string.range(of: "[A-Fa-f]", options: .regularExpression) != nil
    }

    public static func classifyItems(_ items: [PasteboardItem]) -> PasteboardContentKind {
        let types = items.flatMap { $0.currentOrderedTypes() }
        guard let type = priorityTypes.first(where: { types.contains($0.identifier) }),
              var kind = typeMap[type] else { return .unknown }
        if kind == .text {
            if items.first?.url() != nil { kind = .link }
            if let text = items.first?.plainTextString(), isHexColor(text) { return .color }
        }
        if kind == .link, let text = items.first?.plainTextString() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
                  let match = detector.firstMatch(in: trimmed, options: [],
                                                   range: NSRange(location: 0, length: trimmed.utf16.count)) else { return .link }
            return match.range.location == 0 && match.range.length == trimmed.utf16.count ? .link : .text
        }
        return kind
    }
}
