import Foundation

public enum PasteboardArchive {
    public enum ArchiveError: Error { case invalidRoot }

    public static func decodeItems(_ data: Data) throws -> [PasteboardItem] {
        try ObjCExceptionBridge.withResult {
            if let items = PasteboardDataCodec.decodeIfValid(data) { return items }
            let decoder = try NSKeyedUnarchiver(forReadingFrom: data)
            decoder.requiresSecureCoding = true
            decoder.decodingFailurePolicy = .setErrorAndReturn
            decoder.setClass(PasteboardItem.self, forClassName: "BlinkClipCore.PasteboardItem")
            decoder.setClass(PasteboardItem.self, forClassName: "_TtC13BlinkClipCore14PasteboardItem")
            defer { decoder.finishDecoding() }
            let root = decoder.decodeObject(of: [NSArray.self, PasteboardItem.self],
                                            forKey: NSKeyedArchiveRootObjectKey)
            if let error = decoder.error { throw error }
            if let items = root as? [PasteboardItem] { return items }
            if let item = root as? PasteboardItem { return [item] }
            throw ArchiveError.invalidRoot
        }
    }

    public static func encodeItems(_ items: [PasteboardItem]) throws -> Data {
        try ObjCExceptionBridge.withResult {
            try NSKeyedArchiver.archivedData(withRootObject: items as NSArray, requiringSecureCoding: true)
        }
    }
}
