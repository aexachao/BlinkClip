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

    func unregister() {
        if let registeredShortcut { monitor?.unregisterShortcut(shortcut: registeredShortcut) }
        registeredShortcut = nil
    }
}
