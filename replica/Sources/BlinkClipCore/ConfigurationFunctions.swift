import Foundation

/// Recovered value conversion shared by the original local Config wrappers.
/// Storage lookup and the original archive/key-path layout remain separate concerns.
public enum ConfigurationFunctions {
    /// conditionally cast Optional<Any> to the requested value type.
    public static func castValue<Value>(storedValue: Any?, as type: Value.Type) -> Value? {
        storedValue as? Value
    }

    /// the closure entry captures and forwards the configured value type.
    public static func castStoredValue<Value>(storedValue: Any?, as type: Value.Type) -> Value? {
        castValue(storedValue: storedValue, as: type)
    }

    /// decoding failure alone evaluates the configured default.
    public static func decodeOrDefault<Value>(storedValue: Any?,
                                        decode: (Any?) -> Value?,
                                        defaultValue: () -> Value) -> Value {
        if let value = decode(storedValue) { return value }
        return defaultValue()
    }

    /// independently decode the old/new observation values.
    public static func decodeOldAndNew<Value>(old: Any?, new: Any?,
                                        decode: (Any?) -> Value?,
                                        defaultValue: () -> Value) -> (old: Value, new: Value) {
        let oldValue = decodeOrDefault(storedValue: old, decode: decode, defaultValue: defaultValue)
        let newValue = decodeOrDefault(storedValue: new, decode: decode, defaultValue: defaultValue)
        return (oldValue, newValue)
    }
}
