import Foundation

/// The reference value stores an Int key code. Carbon's UInt32 constraint is
/// applied when registering it, rather than when decoding preferences.
public struct ShortcutValue: Codable, Equatable, Hashable, CustomStringConvertible, Sendable {
    public var keyCode: Int
    public var internalModifiers: UInt

    public init(keyCode: Int, internalModifiers: UInt) {
        self.keyCode = keyCode
        self.internalModifiers = internalModifiers
    }

    public init(from decoder: Decoder) throws { self = try Self.decodeFromDecoder(from: decoder) }

    public static func decodeFromDecoder(from decoder: Decoder) throws -> Self {
        let values = try decoder.container(keyedBy: ShortcutCodingKey.self)
        let keyCode = try values.decode(Int.self, forKey: .keyCode)
        let modifiers = try values.decode(UInt.self, forKey: .internalModifiers)
        return Self(keyCode: keyCode, internalModifiers: modifiers)
    }

    public func encodeToEncoder(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: ShortcutCodingKey.self)
        try values.encode(keyCode, forKey: .keyCode)
        try values.encode(internalModifiers, forKey: .internalModifiers)
    }

    public func encode(to encoder: Encoder) throws { try encodeToEncoder(to: encoder) }

    public static func displayString(keyCode: Int, internalModifiers: UInt) -> String {
        ShortcutFunctions.modifierLabel(verbose: false, modifierRawValue: internalModifiers)
            + ShortcutFunctions.displayLabel(keyCode: keyCode)
    }

    public var description: String {
        Self.displayString(keyCode: keyCode, internalModifiers: internalModifiers)
    }

    public var displayName: String { description }
}

public typealias ShortcutCodingKey = ShortcutValue.CodingKeys

extension ShortcutValue {
    public enum CodingKeys: CodingKey, Sendable {
        case keyCode
        case internalModifiers

        public func codingKeyName() -> String {
            switch self {
            case .keyCode: return "keyCode"
            case .internalModifiers: return "internalModifiers"
            }
        }

        public static func fromString(_ string: String) -> Self? {
            switch string {
            case "keyCode": return .keyCode
            case "internalModifiers": return .internalModifiers
            default: return nil
            }
        }

        public var stringValue: String { codingKeyName() }
        public init?(stringValue: String) {
            guard let key = Self.fromString(stringValue) else { return nil }
            self = key
        }
        public var intValue: Int? { nil }
        public init?(intValue: Int) { return nil }
    }
}
