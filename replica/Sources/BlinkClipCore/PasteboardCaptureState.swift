import AppKit
import Foundation
import OSLog

@MainActor
public protocol PasteboardCaptureDelegate: AnyObject {
    func originalPasteboardShouldRead(_ types: [String]) throws -> Bool
    func originalPasteboardDidRead(_ state: PasteboardCaptureState) throws
}

/// Local replacement for the original lazy logger dependency. Resolving the
/// sink is deferred until the first diagnostic, as in the source initializer.
public protocol PasteboardEventLogging {
    func record(scope: String, message: String)
}

private struct LocalPasteboardEventLogger: PasteboardEventLogging {
    func record(scope: String, message: String) {
        Logger(subsystem: "com.chrisli.blinkclip", category: scope).debug("\(message, privacy: .public)")
    }
}

extension DependencyValues {
    public var pasteboardEventLogging: any PasteboardEventLogging {
        LocalPasteboardEventLogger()
    }
}

@MainActor
public final class PasteboardLogDependency {
    private let dependency = Dependency(\DependencyValues.pasteboardEventLogging)

    public func resolve() -> any PasteboardEventLogging {
        dependency.resolveValue()
    }
}

@MainActor
public final class PasteboardCaptureState {
    private final class WeakState {
        weak var value: PasteboardCaptureState?
        init(_ value: PasteboardCaptureState) { self.value = value }
    }
    private static var active: [NSPasteboard.Name: WeakState] = [:]

    public let pasteboard: NSPasteboard
    public weak var delegate: (any PasteboardCaptureDelegate)?
    public var items: [PasteboardItem] = []
    public var lastChangeCount: Int
    public private(set) var lastWriteSucceeded = false
    var persistChangeCount: ((Int) -> Void)?
    public var pollTimer: Timer?
    public var syncTimer: Timer?
    public let diagnostics = NamedDiagnostic.makeNamedDiagnostic(name: "Pasteboard")
    public var diagnosticName: String { diagnostics.name }
    public let loggingDependency = PasteboardLogDependency()

    private init(pasteboard: NSPasteboard, changeCount: Int) {
        self.pasteboard = pasteboard
        self.lastChangeCount = changeCount == 0 ? pasteboard.changeCount : changeCount
    }

    public static func makePasteboardCaptureState(changeCount: Int, pasteboard: NSPasteboard = .general) -> PasteboardCaptureState {
        PasteboardCaptureState(pasteboard: pasteboard, changeCount: changeCount)
    }

    public func writeItems(_ items: [PasteboardItem]) {
        let objects = items.map { item -> NSPasteboardItem in
            let object = NSPasteboardItem()
            for type in item.currentOrderedTypes() {
                if let data = item.nsDataForType(forType: type) {
                    object.setData(data as Data, forType: NSPasteboard.PasteboardType(type))
                }
            }
            return object
        }
        pasteboard.clearContents()
        lastWriteSucceeded = pasteboard.writeObjects(objects)
        lastChangeCount = pasteboard.changeCount
        Self.current(for: pasteboard)?.lastChangeCount = lastChangeCount
    }

    public static func register(_ state: PasteboardCaptureState) {
        active[state.pasteboard.name] = WeakState(state)
    }

    public static func current(for pasteboard: NSPasteboard) -> PasteboardCaptureState? {
        active[pasteboard.name]?.value
    }
}
