import AppKit
import Foundation
import UniformTypeIdentifiers

/// The original item stores an ordered type list separately from its data map.
/// In particular, repeated writes append a type even when replacing its data.
@objc(_TtC13BlinkClipCore14PasteboardItem)
public final class PasteboardItem: NSObject, Codable, NSSecureCoding {
    private var orderedTypes: [String] = []
    private var dataByType: [String: Data] = [:]

    public override init() { super.init() }

    init(types: [String], dataByType: [String: Data]) {
        orderedTypes = types
        self.dataByType = dataByType
        super.init()
    }

    public static var supportsSecureCoding: Bool { isSecureCodingSupported() }
    public static func isSecureCodingSupported() -> Bool { true }

    public required init?(coder: NSCoder) {
        super.init()
        guard let types = coder.decodeArrayOfObjects(ofClass: NSString.self, forKey: "types") as? [String] else {
            return nil
        }
        let values: [String: Data]
        if coder.containsValue(forKey: "data") {
            guard let decoded = coder.decodeDictionary(withKeyClass: NSString.self, objectClass: NSData.self,
                                                       forKey: "data") as? [String: Data] else { return nil }
            values = decoded
        } else {
            guard let legacy = coder.decodeDictionary(withKeyClass: NSString.self, objectClass: NSData.self,
                                                      forKey: "dataByType") as? [String: Data] else { return nil }
            values = legacy
        }
        orderedTypes = types
        dataByType = values
    }

    public func decodeWithCoder(with coder: NSCoder) {
        coder.encode(orderedTypes as NSArray, forKey: "types")
        coder.encode(dataByType as NSDictionary, forKey: "data")
    }

    public func encode(with coder: NSCoder) {
        decodeWithCoder(with: coder)
    }

    private enum CodingKeys: String, CodingKey { case types, dataByType }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderedTypes = try container.decode([String].self, forKey: .types)
        dataByType = try container.decode([String: Data].self, forKey: .dataByType)
        super.init()
    }

    public func encodeToEncoder(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(orderedTypes, forKey: .types)
        try container.encode(dataByType, forKey: .dataByType)
    }

    public func encode(to encoder: Encoder) throws {
        try encodeToEncoder(to: encoder)
    }

    public static func itemWithString(_ string: String) -> PasteboardItem {
        let item = PasteboardItem()
        item.setString(string, forType: UTType.utf8PlainText.identifier)
        return item
    }

    public static func itemWithURL(_ url: URL, title: String?) -> PasteboardItem {
        let item = PasteboardItem()
        item.setString(url.absoluteString, forType: UTType.utf8PlainText.identifier)
        item.setString(url.absoluteString, forType: UTType.url.identifier)
        if let title { item.setString(title, forType: "public.url-name") }
        return item
    }

    public func setString(_ string: String, forType type: String) {
        setData(string.data(using: .utf8, allowLossyConversion: false), forType: type)
    }

    public func dataForType(forType type: String) -> Data? {
        dataByType[type]
    }

    public func setData(_ data: Data?, forType type: String) {
        orderedTypes.append(type)
        dataByType[type] = data
    }

    public func setValue(_ value: Any, forType type: String) {
        if let data = value as? Data {
            setData(data, forType: type)
        } else if let string = value as? String {
            setString(string, forType: type)
        } else if let string = value as? NSAttributedString {
            setString(string.string, forType: type)
        } else if let url = value as? URL {
            setString(url.absoluteString, forType: type)
        } else if let image = value as? NSImage {
            setData(PasteboardImageEncoding.pngData(image), forType: type)
        }
    }

    public func currentOrderedTypes() -> [String] { orderedTypes }

    public func removeData(_ type: String) {
        orderedTypes.removeAll { $0 == type }
        dataByType.removeValue(forKey: type)
    }

    public func removeTypesMatching(removingTypesContaining patterns: [String]) {
        for type in orderedTypes where patterns.contains(where: { type.contains($0) }) {
            removeData(type)
        }
    }

    public func addBlinkClipMarker() {
        setData(Data(), forType: "com.chrisli.blinkclip")
    }

    public func stringForType(forType type: String) -> String? {
        guard let data = dataForType(forType: type) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func nsDataForType(forType type: String) -> NSData? {
        dataForType(forType: type).map { $0 as NSData }
    }

    public func plainTextString() -> String? {
        for type in [UTType.plainText, .utf8PlainText, .text, .url] {
            if let string = stringForType(forType: type.identifier) { return string }
        }
        return nil
    }

    public func fileURL() -> URL? {
        guard let string = stringForType(forType: UTType.fileURL.identifier) else { return nil }
        return URL(string: string)
    }

    public func url() -> URL? {
        if let string = stringForType(forType: UTType.url.identifier), let url = URL(string: string) {
            return url
        }
        var allowed = CharacterSet(charactersIn: "#")
        allowed.formUnion(.urlQueryAllowed)
        allowed.formUnion(.urlFragmentAllowed)
        guard let string = plainTextString(), let encoded = string.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: encoded), url.scheme != nil, url.host != nil else { return nil }
        return url
    }

    public func urlName() -> String? {
        stringForType(forType: "public.url-name")
    }

    public func image() -> NSImage? {
        imageData().flatMap(NSImage.init(data:))
    }

    public func imageData() -> Data? {
        for type in [UTType.png, .jpeg, .heic, .tiff, .icns] {
            if let data = dataForType(forType: type.identifier) { return data }
        }
        return nil
    }

    public func attributedStringForTypes(_ types: [UTType]) -> NSAttributedString? {
        for type in types {
            guard let data = dataForType(forType: type.identifier) else { continue }
            if let string = NSAttributedString(rtfd: data, documentAttributes: nil) { return string }
            if let string = NSAttributedString(rtf: data, documentAttributes: nil) { return string }
            if let string = try? NSAttributedString(data: data, options: [:], documentAttributes: nil) {
                return string
            }
        }
        return nil
    }

    public func attributedString() -> NSAttributedString? {
        guard let rich = attributedStringForTypes([.flatRTFD, .rtfd, .rtf]) else {
            return plainTextString().map { NSAttributedString(string: $0) }
        }
        let result = NSMutableAttributedString(attributedString: rich)
        result.enumerateAttributes(in: NSRange(location: 0, length: result.length)) { attributes, range, _ in
            Self.applyParagraphStyle(attributes: attributes, range: range, string: result)
        }
        return result
    }

    public static func applyParagraphStyle(attributes: [NSAttributedString.Key: Any], range: NSRange,
                                    string: NSMutableAttributedString) {
        guard let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle,
              let mutable = paragraph.mutableCopy() as? NSMutableParagraphStyle else { return }
        mutable.textBlocks = []
        string.addAttribute(.paragraphStyle, value: mutable, range: range)
    }
}

/// Source function has no filtering, empty-input guard, generated
/// marker, or write-failure branch. Those policies belong to its callers.
@MainActor
public final class PasteboardWriter {
    public let pasteboard: NSPasteboard
    private let state: PasteboardCaptureState
    public var lastChangeCount: Int { state.lastChangeCount }
    public var lastWriteSucceeded: Bool { state.lastWriteSucceeded }

    public init(pasteboard: NSPasteboard) {
        self.pasteboard = pasteboard
        self.state = PasteboardCaptureState.makePasteboardCaptureState(changeCount: 0, pasteboard: pasteboard)
    }

    public func writeItems(_ items: [PasteboardItem]) {
        state.writeItems(items)
    }
}
