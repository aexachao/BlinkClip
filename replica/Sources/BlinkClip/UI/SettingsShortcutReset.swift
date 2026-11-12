import AppKit
import BlinkClipCore

/// Shared production transaction. Screenshot storage and registration only run after app persistence succeeds.
@MainActor
enum SettingsShortcutReset {
    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = SettingsCopy.text("settings.shortcuts.reset-all.confirmation")
        alert.informativeText = SettingsCopy.text("settings.shortcuts.reset-all.scope")
        alert.addButton(withTitle: SettingsCopy.text("general.action.cancel"))
        alert.addButton(withTitle: SettingsCopy.text("general.action.reset"))
        return alert
    }

    static func configureSafeCancel(_ alert: NSAlert) {
        alert.window.defaultButtonCell = alert.buttons[0].cell as? NSButtonCell
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""
    }

    static func present(_ alert: NSAlert, on window: NSWindow, completion: @escaping (Bool) -> Void) {
        var keyMonitor: Any?
        var closeObserver: Any?
        alert.beginSheetModal(for: window) { response in
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
            completion(response == .alertSecondButtonReturn)
        }
        // AppKit assigns default equivalents during presentation; override afterwards.
        configureSafeCancel(alert)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak alert, weak window] event in
            guard let alert, event.window === alert.window,
                  [36, 76, 53].contains(Int(event.keyCode)) else { return event }
            window?.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
            return nil
        }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak alert, weak window] _ in
            guard let alert else { return }
            window?.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
        }
    }

    @discardableResult
    static func apply(confirmed: Bool, store: ClipboardStore,
                      save: (() throws -> Void)? = nil,
                      commitScreenshots: () -> Void, reload: () -> Void) throws -> Bool {
        guard confirmed else { return false }
        let previous = store.preferences
        var updated = previous
        updated.historyShortcut = .historyDefault
        updated.stackShortcut = .stackDefault
        updated.nextPinboardShortcut = .nextPinboardDefault
        updated.previousPinboardShortcut = .previousPinboardDefault
        updated.quickPasteModifierRawValue = NSEvent.ModifierFlags.command.rawValue
        updated.plainTextModifierRawValue = NSEvent.ModifierFlags.shift.rawValue
        store.preferences = updated
        do { try (save ?? { try store.save() })() }
        catch { store.preferences = previous; throw error }
        commitScreenshots()
        reload()
        return true
    }
}
