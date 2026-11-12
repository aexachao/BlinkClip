import Foundation

/// Separate from a dependency wrapper's first-use cache: the original shares
/// services by their declaration site, scoped to the active dependency context.
public final class SharedDependencyCache: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var values: [String: Any] = [:]

    public init() {}

    public func cachedValue<Value>(key: String, factory: () -> Value) -> Value {
        lock.lock()
        defer { lock.unlock() }
        if let stored = values[key] { return stored as! Value }
        let value = factory()
        storeValue(value as Any, for: key)
        return value
    }

    /// nil removes the erased entry; a boxed Optional.none is a stored value.
    private func storeValue(_ value: Any?, for key: String) {
        values[key] = value
    }
}

extension Dependencies {
    private static let globalSharedCache = SharedDependencyCache()

    public static func resolveDependency<Value>(file: StaticString, line: UInt, column: UInt,
                                          factory: () -> Value) -> Value {
        let key = file.description + "-" + line.description + "-" + column.description
        if let overrides { return overrides.cachedValue(key: key, factory: factory) }
        return globalSharedCache.cachedValue(key: key, factory: factory)
    }

    /// A fresh scope has both a fresh override dictionary and a fresh shared
    /// service cache. Nesting never mutates the enclosing task's context.
    public static func withOverrides<Result>(operation: () throws -> Result) rethrows -> Result {
        try withOverrides(DependencyOverrides(), operation: operation)
    }

    public static func registerOverride<Value>(_ keyPath: KeyPath<DependencyValues, Value>,
                                         factory: @escaping () -> Value) {
        guard let overrides else { preconditionFailure("A dependency override requires an active scope") }
        overrides.registerFactory(keyPath, factory: factory)
    }

    public static func removeOverride(_ keyPath: AnyKeyPath) {
        guard let overrides else { preconditionFailure("A dependency override requires an active scope") }
        overrides.removeFactory(keyPath)
    }

    public static func removeAllOverrides() {
        guard let overrides else { preconditionFailure("Clearing overrides requires an active scope") }
        overrides.removeAllFactories()
    }
}
