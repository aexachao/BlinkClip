import AppKit
import Combine
import Foundation

public enum ShortcutRecorderState: Equatable, Hashable, Sendable {
    case assigned(ShortcutValue)
    case recording(previous: ShortcutValue?, candidate: ShortcutValue?)
    case unassigned

    public static func isEqual(_ lhs: Self, _ rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.assigned(a), .assigned(b)): return a == b
        case let (.recording(a, b), .recording(c, d)): return a == c && b == d
        case (.unassigned, .unassigned): return true
        default: return false
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { isEqual(lhs, rhs) }

    public func hashInto(into hasher: inout Hasher) {
        switch self {
        case let .assigned(shortcut):
            hasher.combine(1)
            hasher.combine(shortcut.keyCode)
            hasher.combine(shortcut.internalModifiers)
        case let .recording(previous, candidate):
            hasher.combine(2)
            Self.hashOptional(previous, into: &hasher)
            Self.hashOptional(candidate, into: &hasher)
        case .unassigned:
            hasher.combine(0)
        }
    }

    private static func hashOptional(_ shortcut: ShortcutValue?, into hasher: inout Hasher) {
        guard let shortcut else { hasher.combine(0); return }
        hasher.combine(1)
        hasher.combine(shortcut.keyCode)
        hasher.combine(shortcut.internalModifiers)
    }

    public func hash(into hasher: inout Hasher) { hashInto(into: &hasher) }

    public var previousShortcut: ShortcutValue? {
        switch self {
        case let .assigned(value): return value
        case let .recording(previous, _): return previous
        case .unassigned: return nil
        }
    }

    public var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}

public struct ShortcutRecorderError: LocalizedError {
    public let errorDescription: String?
    public var message: String { errorDescription ?? "" }
    public init(_ message: String?) { errorDescription = message }
}

public enum ShortcutRecorderValidationError: LocalizedError, Hashable, Sendable {
    case optionKey

    public var errorDescription: String? { optionKeyErrorMessage() }

    public func optionKeyErrorMessage() -> String {
        ShortcutMessages.value("shortcut-recorder.error.option-key")
    }
}

/// The original recorder's model owns its event monitor and preserves the
/// previous value separately from the unfinished modifier/key candidate.
@MainActor
public final class ShortcutRecorder: ObservableObject {
    @Published public private(set) var state: ShortcutRecorderState
    @Published public private(set) var validationError: Error?
    public var onDetect: (ShortcutValue?) -> Void
    public let allowsClearing: Bool
    private var eventMonitor: Any?
    private let validator: Dependency<ShortcutValidatorService>

    public init(shortcut: ShortcutValue?, allowsClearing: Bool = true,
                onDetect: @escaping (ShortcutValue?) -> Void) {
        validationError = nil
        self.validator = Dependency(\DependencyValues.shortcutValidator)
        eventMonitor = nil
        state = shortcut.map(ShortcutRecorderState.assigned) ?? .unassigned
        self.onDetect = onDetect
        self.allowsClearing = allowsClearing
    }

    deinit {
        // Swift 5 deinitializers are not guaranteed to execute on the UI actor.
        // Retain only the monitor handle when scheduling its final removal.
        if let eventMonitor {
            if Thread.isMainThread {
                MainActor.assumeIsolated { NSEvent.removeMonitor(eventMonitor) }
            } else {
                Task { @MainActor in NSEvent.removeMonitor(eventMonitor) }
            }
        }
    }

    public func currentState() -> ShortcutRecorderState { state }
    public func currentValidationError() -> Error? { validationError }

    public func clearValidationError() { validationError = nil }

    public func setShortcut(_ shortcut: ShortcutValue?) {
        state = shortcut.map(ShortcutRecorderState.assigned) ?? .unassigned
    }

    /// Optional state is the original method's "keep current state" sentinel.
    public func updateState(newState: ShortcutRecorderState?) {
        if let newState { state = newState }
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    public func startRecording() {
        if case let .recording(previous, _) = state {
            updateState(newState: previous.map(ShortcutRecorderState.assigned) ?? .unassigned)
            return
        }
        state = .recording(previous: state.previousShortcut, candidate: nil)
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return nil }
            return self.handleKeyEvent(event)
        }
    }

    /// Action closure forwarded by the original recorder button.
    public func beginRecording() { startRecording() }

    public func handleClearKey() {
        guard allowsClearing else {
            // Required shortcuts keep their prior value when Delete is pressed while recording.
            if state.isRecording { startRecording() }
            return
        }
        onDetect(nil)
        updateState(newState: .unassigned)
    }

    /// Return the original event only on the two explicit pass-through paths.
    public func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let eventShortcut = ShortcutFunctions.shortcutForEvent(event)
        let shortcut = ShortcutValue(keyCode: Int(eventShortcut.keyCode),
                                              internalModifiers: eventShortcut.modifierRawValue)
        if [ShortcutFunctions.deleteKeyCode(), ShortcutFunctions.forwardDeleteKeyCode()]
            .contains(shortcut.keyCode), shortcut.internalModifiers == 0 {
            handleClearKey()
            return nil
        }
        if shortcut.keyCode == ShortcutFunctions.escapeKeyCode(), shortcut.internalModifiers == 0 {
            startRecording()
            return nil
        }
        let closeKey = ShortcutFunctions.keyCodeForKey("w")
        let quitKey = ShortcutFunctions.keyCodeForKey("q")
        if shortcut.internalModifiers == NSEvent.ModifierFlags.command.rawValue,
           [Int(closeKey), Int(quitKey)].contains(shortcut.keyCode) {
            let closingState: ShortcutRecorderState = allowsClearing
                ? .unassigned
                : state.previousShortcut.map(ShortcutRecorderState.assigned) ?? .unassigned
            updateState(newState: closingState)
            return event
        }
        let key = ShortcutFunctions.displayLabel(keyCode: shortcut.keyCode)
        if key.isEmpty {
            state = .recording(previous: state.previousShortcut, candidate: shortcut)
            return nil
        }
        _ = validator.resolveValue()
        guard ShortcutFunctions.isFunctionKeyOrModified(keyCode: shortcut.keyCode,
                                                  modifierRawValue: shortcut.internalModifiers) else {
            NSSound.beep()
            return event
        }
        let validate = validator.resolveValue()
        if let failure = validate.validate(shortcut) {
            startRecording()
            validationError = failure
            return nil
        }
        onDetect(shortcut)
        updateState(newState: .assigned(shortcut))
        if ShortcutValidation.requiresOptionCompatibilityWarning(
            modifierRawValue: shortcut.internalModifiers,
            version: ProcessInfo.processInfo.operatingSystemVersion) {
            validationError = ShortcutRecorderValidationError.optionKey
        }
        return nil
    }

    /// (modifier/status text, optional key text, whether key styling is active).
    public func presentation() -> (String, String?, Bool) {
        let shortcut: ShortcutValue
        switch state {
        case let .assigned(value): shortcut = value
        case let .recording(_, candidate):
            guard let candidate else {
                return (ShortcutMessages.value("shortcut-recorder.status.recording"), nil, false)
            }
            let modifiers = ShortcutFunctions.modifierLabel(verbose: false,
                                                                 modifierRawValue: candidate.internalModifiers)
            let key = ShortcutFunctions.displayLabel(keyCode: candidate.keyCode)
            guard !(modifiers + key).isEmpty else {
                return (ShortcutMessages.value("shortcut-recorder.status.recording"), nil, false)
            }
            shortcut = candidate
        case .unassigned:
            return (ShortcutMessages.value("shortcut-recorder.none"), nil, false)
        }
        return (ShortcutFunctions.modifierLabel(verbose: false, modifierRawValue: shortcut.internalModifiers),
                ShortcutFunctions.displayLabel(keyCode: shortcut.keyCode), true)
    }

    public static var removeTitle: String { ShortcutMessages.value("shortcut-recorder.action.remove") }

}
