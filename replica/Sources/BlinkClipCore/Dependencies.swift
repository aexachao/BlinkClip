import Foundation
import os

/// Dependency keys are computed properties on a value with no stored state.
/// Providers remain separate from the task-local override and lazy cache.
public struct DependencyValues {
    public init() {}
}

public final class DependencyOverrides: @unchecked Sendable {
    private let lock = NSLock()
    private var factories: [AnyKeyPath: () -> Any] = [:]
    private let sharedCache = SharedDependencyCache()

    public init() {}

    /// The typed factory is erased only after it produces its result.
    public func registerFactory<Root, Value>(_ keyPath: KeyPath<Root, Value>, factory: @escaping () -> Value) {
        lock.lock()
        factories[keyPath] = { factory() as Any }
        lock.unlock()
    }

    public func removeFactory(_ keyPath: AnyKeyPath) {
        lock.lock()
        _ = factories.removeValue(forKey: keyPath)
        lock.unlock()
    }

    func cachedValue<Value>(key: String, factory: () -> Value) -> Value {
        sharedCache.cachedValue(key: key, factory: factory)
    }

    func removeAllFactories() {
        lock.lock()
        factories.removeAll()
        lock.unlock()
    }

    /// The original casts Optional<Any>, including its nil case. Keeping that
    /// source type also preserves a successful cast to an optional dependency.
    public func valueForKeyPath<Root, Value>(_ keyPath: KeyPath<Root, Value>) -> Value? {
        lock.lock()
        let factory = factories[keyPath]
        lock.unlock()
        let value: Any? = factory?()
        return value as? Value
    }
}

public enum Dependencies {
    @TaskLocal public static var overrides: DependencyOverrides?

    public static func valueWithOverrides<Root, Value>(root: Root, keyPath: KeyPath<Root, Value>) -> Value {
        if let overrides, case let .some(value) = overrides.valueForKeyPath(keyPath) {
            return value
        }
        return root[keyPath: keyPath]
    }

    /// This is the recovered task-local scope. The original container's
    /// separate recursive shared-service cache is tracked independently.
    public static func withOverrides<Result>(_ overrides: DependencyOverrides,
                                              operation: () throws -> Result) rethrows -> Result {
        try $overrides.withValue(overrides, operation: operation)
    }
}

/// resolve once while holding an unfair
/// lock. Optional.some(nil) is cached when Value itself is an optional type.
public final class Dependency<Value>: @unchecked Sendable {
    private let lock: OSAllocatedUnfairLock<Void>
    private let resolve: () -> Value
    private var cached: Value?

    public init(_ keyPath: KeyPath<DependencyValues, Value>) {
        lock = OSAllocatedUnfairLock()
        cached = nil
        resolve = { Self.valueWithOverrides(keyPath) }
    }

    public static func valueWithOverrides(_ keyPath: KeyPath<DependencyValues, Value>) -> Value {
        Dependencies.valueWithOverrides(root: DependencyValues(), keyPath: keyPath)
    }

    public func resolveValue() -> Value {
        lock.withLockUnchecked {
            if case let .some(value) = cached { return value }
            let value = resolve()
            cached = .some(value)
            return value
        }
    }
}
