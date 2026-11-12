import Compression
import Foundation

/// The value codec used by the original ItemDataEntity rawPasteboardItems field.
/// The replica stores these bytes as private payload metadata, outside exported pasteboard types.
public enum PasteboardDataCodec {
    public static func hasPrefix(_ data: Data, startsWith prefix: [UInt8]) -> Bool {
        data.starts(with: prefix)
    }

    public static func firstByte(_ data: Data) -> UInt8? { data.first }

    public static func compressedData(_ data: Data, algorithm: compression_algorithm) -> Data? {
        guard !data.isEmpty else { return nil }
        return data.withUnsafeBytes { source in
            guard let input = source.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let output = UnsafeMutablePointer<UInt8>.allocate(capacity: source.count)
            defer { output.deallocate() }
            let count = compression_encode_buffer(output, source.count, input, source.count, nil, algorithm)
            guard count > 0 else { return nil }
            return Data(bytes: output, count: count)
        }
    }

    public static func decompressedData(_ data: Data, algorithm: compression_algorithm) -> Data? {
        guard !data.isEmpty else { return Data() }
        return data.withUnsafeBytes { source in
            decodeBuffer(source.bindMemory(to: UInt8.self), algorithm: algorithm)
        }
    }

    public static func decodeBuffer(_ source: UnsafeBufferPointer<UInt8>, algorithm: compression_algorithm) -> Data? {
        guard let input = source.baseAddress else { return Data() }
        var capacity = max(source.count * 2, 0x10000)
        while true {
            let output = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            let count = compression_decode_buffer(output, capacity, input, source.count, nil, algorithm)
            if count == 0 {
                output.deallocate()
                return nil
            }
            if count != capacity {
                let data = Data(bytes: output, count: count)
                output.deallocate()
                return data
            }
            output.deallocate()
            guard capacity <= 0x0fffffff else { return nil }
            capacity *= 2
        }
    }

    /// This is the setter's encoding algorithm; the original entity mutation and DI are separate.
    public static func encodeItems(_ items: [PasteboardItem], useBinaryPlist: Bool) -> Data {
        let encoded: Data
        let algorithm: compression_algorithm
        if useBinaryPlist {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            encoded = (try? encoder.encode(items)) ?? Data()
            algorithm = COMPRESSION_LZFSE
        } else {
            encoded = (try? JSONEncoder().encode(items)) ?? Data()
            algorithm = COMPRESSION_ZLIB
        }
        if items.contains(where: { $0.imageData() != nil }) { return encoded }
        return compressedData(encoded, algorithm: algorithm) ?? encoded
    }

    /// Strict validity is needed for external imports and payload identity comparisons.
    public static func decodeIfValid(_ data: Data) -> [PasteboardItem]? {
        let normalized: Data
        if hasPrefix(data, startsWith: [0x62, 0x76, 0x78]) {
            normalized = decompressedData(data, algorithm: COMPRESSION_LZFSE) ?? data
        } else if hasPrefix(data, startsWith: [0x62, 0x70, 0x6c, 0x69, 0x73, 0x74]) {
            normalized = data
        } else if firstByte(data) == 0x5b || firstByte(data) == 0x7b {
            normalized = data
        } else {
            normalized = decompressedData(data, algorithm: COMPRESSION_ZLIB) ?? data
        }
        if hasPrefix(normalized, startsWith: [0x62, 0x70, 0x6c, 0x69, 0x73, 0x74]),
           let items = try? PropertyListDecoder().decode([PasteboardItem].self, from: normalized) {
            return items
        }
        return try? JSONDecoder().decode([PasteboardItem].self, from: normalized)
    }

    public static func decodeItems(_ data: Data) -> [PasteboardItem] {
        decodeIfValid(data) ?? []
    }
}
