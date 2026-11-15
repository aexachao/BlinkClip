import AppKit
import Carbon
import BlinkClipCore

@MainActor
final class GlobalHotKey {
    private var registeredShortcut: BlinkClipCore.KeyboardShortcut?
    private var monitor: GlobalShortcutMonitor?
    var action: (() -> Void)?

    func register(keyCode: UInt32 = UInt32(kVK_ANSI_V), modifiers: NSEvent.ModifierFlags = [.command, .shift],
                  identifier: UInt32 = 1) -> OSStatus {
        unregister()
        // The external identifier belongs to the replica facade. The reference
        // allocates a process-wide Carbon ID for every registration attempt.
        _ = identifier
        let shortcut = BlinkClipCore.KeyboardShortcut(keyCode: keyCode, modifierRawValue: modifiers.rawValue)
        let monitor = GlobalShortcutMonitor.shared
        self.monitor = monitor
        let status = monitor.registerShortcut(shortcut: shortcut) { [weak self] in self?.action?() }
        if status == noErr { registeredShortcut = shortcut }
        return status
    }

    /// Sample only this registered key, for our own status menu's tracking loop.
    func isPressedDuringMenuTracking() -> Bool {
        guard let shortcut = registeredShortcut,
              let keyCode = CGKeyCode(exactly: shortcut.keyCode) else { return false }
        let state = CGEventSourceStateID.combinedSessionState
        let activeModifiers = UInt(CGEventSource.flagsState(state).rawValue)
        return ShortcutFunctions.carbonModifierFlags(modifierRawValue: activeModifiers) ==
            ShortcutFunctions.carbonModifierFlags(modifierRawValue: shortcut.modifierRawValue)
            && CGEventSource.keyState(state, key: keyCode)
    }

    func unregister() {
        if let registeredShortcut { monitor?.unregisterShortcut(shortcut: registeredShortcut) }
        registeredShortcut = nil
    }
}
