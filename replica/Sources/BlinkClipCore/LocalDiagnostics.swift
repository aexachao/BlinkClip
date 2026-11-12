import Foundation
import os

public protocol DiagnosticSink {
    func emit(level: UInt8, message: String)
}

extension DiagnosticSink {
    public func emitDebug(_ message: String) { emit(level: 0, message: message) }
    public func emitInfo(_ message: String) { emit(level: 1, message: message) }
    public func emitError(_ message: String) { emit(level: 2, message: message) }
    public func emitFault(_ message: String) { emit(level: 3, message: message) }
}

extension DependencyValues {
    public var diagnosticFactory: (String) -> any DiagnosticSink {
        { DiagnosticDispatcher.diagnosticSink(name: $0) }
    }
}

public final class NamedDiagnostic {
    private static let factoryDependency = Dependency(\DependencyValues.diagnosticFactory)
    private let lock = OSAllocatedUnfairLock<Void>(uncheckedState: ())
    public let name: String
    private var cached: (any DiagnosticSink)?

    private init(name: String) {
        self.name = name
        self.cached = nil
    }

    public static func makeNamedDiagnostic(name: String) -> NamedDiagnostic {
        NamedDiagnostic(name: name)
    }

    public func diagnosticSink() -> any DiagnosticSink {
        lock.withLockUnchecked { _ in
            if let cached { return cached }
            let sink = Self.factoryDependency.resolveValue()(name)
            cached = sink
            return sink
        }
    }
}
