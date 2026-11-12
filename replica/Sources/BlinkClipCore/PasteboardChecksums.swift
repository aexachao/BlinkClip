import CryptoKit
import Foundation

public enum PasteboardChecksums {
    public static func updateHasher(_ data: Data, into hasher: inout Insecure.MD5) {
        data.withUnsafeBytes { hasher.update(bufferPointer: $0) }
    }

    public static func hexStrings(_ digest: Insecure.MD5.Digest) -> [String] {
        digest.map { String(format: "%02x", $0) }
    }

    private static func checksum(_ data: Data) -> String {
        var hasher = Insecure.MD5()
        updateHasher(data, into: &hasher)
        return hexStrings(hasher.finalize()).joined()
    }

    public static func checksumForString(_ string: String) -> String {
        guard let data = string.data(using: .utf8, allowLossyConversion: false) else { return "" }
        return checksum(data)
    }

    public static func archivedItemsChecksum(_ items: [PasteboardItem]) -> String {
        let data = (try? NSKeyedArchiver.archivedData(withRootObject: items as NSArray,
                                                    requiringSecureCoding: false)) ?? Data()
        return checksum(data)
    }

    public static func checksumForItems(_ items: [PasteboardItem],
                                  kind: PasteboardContentKind) -> String? {
        switch kind {
        case .unknown:
            return archivedItemsChecksum(items)
        case .image:
            guard let data = items.lazy.compactMap({ $0.imageData() }).first else { return nil }
            return checksum(data)
        case .color, .link, .text:
            guard let text = items.first?.plainTextString() else { return nil }
            return checksumForString(text)
        case .files:
            let paths = items.compactMap { $0.fileURL()?.path }
            guard !paths.isEmpty else { return archivedItemsChecksum(items) }
            return checksumForString("FileSnippet:" + paths.joined())
        }
    }
}
