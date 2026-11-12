import AppKit
import Carbon
import Foundation
import OSLog

public enum ShortcutMonitorError: Error, CustomStringConvertible {
    case eventHandler(OSStatus)
    case hotKey(OSStatus)

    public var description: String {
        switch self {
        case let .eventHandler(status):
            return "Failed to install Carbon event handler (OSStatus: \(status))"
        case let .hotKey(status):
            return "Failed to register Carbon hot key (OSStatus: \(status))"
        }
    }
}

public struct ShortcutDiagnostic {
    public enum Level { case information, warning, error }
    public let level: Level
    public let topic: String?
    public let message: String
    public let tags: [String: String]
    public let metadata: [String: Int]
    public let error: ShortcutMonitorError?
}

private final class ShortcutCarbonIDCounter {
    static let shared = ShortcutCarbonIDCounter()
    private var value: UInt32 = 0
    private let lock = NSLock()

    func next() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        precondition(value < UInt32.max)
        value += 1
        return value
    }
}

/// A successful registration is retained by the monitor's shortcut dictionary.
/// Removing the entry releases this object and unregisters its Carbon handle.
public final class ShortcutRegistration {
    public let action: () -> Void
    public let identifier: UInt32
    public let status: OSStatus
    private var reference: EventHotKeyRef?

    public init(keyCode: Int, modifierRawValue: UInt, action: @escaping () -> Void) {
        self.action = action
        identifier = ShortcutCarbonIDCounter.shared.next()
        precondition(keyCode >= 0 && keyCode <= Int(UInt32.max))
        let hotKey = EventHotKeyID(signature: 1, id: identifier)
        var reference: EventHotKeyRef?
        status = RegisterEventHotKey(UInt32(keyCode),
                                    ShortcutFunctions.carbonModifierFlags(modifierRawValue: modifierRawValue),
                                    hotKey, GetEventDispatcherTarget(), 0, &reference)
        self.reference = reference
    }

    private func unregisterEventHotKey() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    deinit { unregisterEventHotKey() }
}

/// The reference installs one dispatcher handler for all registered shortcuts,
/// allocates process-wide IDs and delivers a retained action on the main queue.
public final class GlobalShortcutMonitor {
    public static var shared: GlobalShortcutMonitor { DependencyValues().globalShortcutMonitor() }

    public static func makeGlobalShortcutMonitor() -> GlobalShortcutMonitor { GlobalShortcutMonitor() }
    private static let logger = Logger(subsystem: "BlinkClip", category: "shortcuts")
    private var handler: EventHandlerRef?
    private let lock = NSLock()
    private var registrations: [ShortcutValue: ShortcutRegistration] = [:]
    private let diagnostic: Dependency<(ShortcutDiagnostic) -> Void>

    public init() {
        self.diagnostic = Dependency(\DependencyValues.shortcutDiagnostic)
        var specification = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                          eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), { call, event, context in
            GlobalShortcutMonitor.eventHandlerCallback(call, event, context)
        }, 1, &specification, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr {
            let failure = ShortcutMonitorError.eventHandler(status)
            emit(ShortcutDiagnostic(level: .error, topic: nil,
                message: failure.description, tags: [:], metadata: ["status": Int(status)], error: failure))
        }
    }

    private func emit(_ diagnostic: ShortcutDiagnostic) {
        let write = self.diagnostic.resolveValue()
        write(diagnostic)
    }

    static func writeDiagnostic(_ diagnostic: ShortcutDiagnostic) {
        let message = diagnostic.message
        let metadata = String(describing: diagnostic.metadata)
        switch diagnostic.level {
        case .information: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public) \(metadata, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public) \(metadata, privacy: .public)")
        }
    }

    public func registerShortcutIgnoringStatus(shortcut: KeyboardShortcut, action: @escaping () -> Void) {
        registerShortcutIgnoringStatus(shortcut: ShortcutValue(keyCode: Int(shortcut.keyCode),
            internalModifiers: shortcut.modifierRawValue), action: action)
    }

    public func registerShortcutIgnoringStatus(shortcut: ShortcutValue, action: @escaping () -> Void) {
        _ = registerShortcut(shortcut: shortcut, action: action)
    }

    /// BlinkClip reports registration failures to its preferences UI; the original entry returns Void.
    public func registerShortcut(shortcut: KeyboardShortcut, action: @escaping () -> Void) -> OSStatus {
        registerShortcut(shortcut: ShortcutValue(keyCode: Int(shortcut.keyCode),
            internalModifiers: shortcut.modifierRawValue), action: action)
    }

    private func registerShortcut(shortcut: ShortcutValue, action: @escaping () -> Void) -> OSStatus {
        unregisterShortcut(shortcut: shortcut)
        let registration = ShortcutRegistration(keyCode: shortcut.keyCode,
            modifierRawValue: shortcut.internalModifiers, action: action)
        let modifiers = ShortcutFunctions.carbonModifierFlags(modifierRawValue: shortcut.internalModifiers)
        if registration.status == noErr {
            lock.lock()
            storeRegistration(registration, for: shortcut)
            lock.unlock()
            emit(ShortcutDiagnostic(level: .information, topic: "shortcuts",
                message: "registered carbonID=\(registration.identifier) keyCode=\(shortcut.keyCode) modifiers=\(modifiers)",
                tags: [:], metadata: [:], error: nil))
        } else {
            let failure = ShortcutMonitorError.hotKey(registration.status)
            emit(ShortcutDiagnostic(level: .error, topic: nil, message: failure.description,
                tags: [:], metadata: ["status": Int(registration.status), "carbon_key_code": Int(shortcut.keyCode),
                                     "carbon_modifiers": Int(modifiers)], error: failure))
        }
        return registration.status
    }

    public func unregisterShortcut(shortcut: KeyboardShortcut) {
        unregisterShortcut(shortcut: ShortcutValue(keyCode: Int(shortcut.keyCode),
            internalModifiers: shortcut.modifierRawValue))
    }

    public func unregisterShortcut(shortcut: ShortcutValue) {
        lock.lock()
        let removed = removeRegistration(shortcut)
        lock.unlock()
        if let removed {
            let modifiers = ShortcutFunctions.carbonModifierFlags(modifierRawValue: shortcut.internalModifiers)
            emit(ShortcutDiagnostic(level: .information, topic: "shortcuts",
                message: "unregistered carbonID=\(removed.identifier) keyCode=\(shortcut.keyCode) modifiers=\(modifiers)",
                tags: [:], metadata: [:], error: nil))
            withExtendedLifetime(removed) {}
        }
    }

    private func removeRegistration(_ shortcut: ShortcutValue) -> ShortcutRegistration? {
        registrations.removeValue(forKey: shortcut)
    }

    private func storeRegistration(_ registration: ShortcutRegistration, for shortcut: ShortcutValue) {
        registrations[shortcut] = registration
    }

    public func dispatchHotKeyEvent(_ event: EventRef) {
        guard GetEventClass(event) == OSType(kEventClassKeyboard) else { return }
        var identifier = EventHotKeyID()
        // The original ignores GetEventParameter's status and compares only ID,
        // retaining the zero-initialized value when the parameter cannot be read.
        _ = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
        lock.lock()
        let action = registrations.values.first { $0.identifier == identifier.id }?.action
        lock.unlock()
        guard let action else {
            emit(ShortcutDiagnostic(level: .warning, topic: nil,
                message: "Global shortcut event received with no matching handler",
                tags: ["source": "GlobalShortcutMonitor"], metadata: ["carbon_id": Int(identifier.id)], error: nil))
            return
        }
        emit(ShortcutDiagnostic(level: .information, topic: "shortcuts",
            message: "fired carbonID=\(identifier.id)", tags: [:], metadata: [:], error: nil))
        DispatchQueue.main.async(execute: action)
    }

    public static func eventHandlerCallback(_ call: EventHandlerCallRef?, _ event: EventRef?,
                                  _ context: UnsafeMutableRawPointer?) -> OSStatus {
        if let event, let context {
            let monitor = Unmanaged<GlobalShortcutMonitor>.fromOpaque(context).retain().takeRetainedValue()
            monitor.dispatchHotKeyEvent(event)
            withExtendedLifetime(monitor) {}
        }
        return noErr
    }

    private func removeEventHandler() {
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    deinit { removeEventHandler() }
}
