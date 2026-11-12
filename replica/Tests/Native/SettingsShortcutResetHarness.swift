import AppKit
import Foundation
import BlinkClipCore
import BlinkClipCapture

@main struct SettingsShortcutResetHarness {
    enum Injected: Error { case save }
    @MainActor static func settle(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        precondition(condition(), "native shortcut sheet did not finish")
    }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"]!)
        let fixture = root.appendingPathComponent("build/reset-fixture")
        let store = try ClipboardStore(directoryURL: fixture)
        store.preferences.historyShortcut = .init(keyCode: BlinkClipScreenshotSettings.regionDefault.keyCode, modifierRawValue: BlinkClipScreenshotSettings.regionDefault.modifierRawValue)
        store.preferences.stackShortcut = nil
        store.preferences.quickPasteModifierRawValue = 0
        store.preferences.plainTextModifierRawValue = 0
        store.preferences.playSounds = false
        try store.save()
        let original = store.preferences
        var saves = 0, reloads = 0, commits = 0
        let suite = "local.blinkclip.reset.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(99, forKey: BlinkClipScreenshotSettings.regionKeyCodeKey)
        defaults.set(100, forKey: BlinkClipScreenshotSettings.fullScreenKeyCodeKey)
        var screenshotNotifications = 0
        let observer = NotificationCenter.default.addObserver(forName: BlinkClipScreenshotSettings.hotKeysDidChange, object: nil, queue: nil) { _ in
            screenshotNotifications += 1
            precondition(defaults.integer(forKey: BlinkClipScreenshotSettings.regionKeyCodeKey) == Int(BlinkClipScreenshotSettings.regionDefault.keyCode))
            precondition(defaults.integer(forKey: BlinkClipScreenshotSettings.fullScreenKeyCodeKey) == Int(BlinkClipScreenshotSettings.fullScreenDefault.keyCode))
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let commit = { commits += 1; BlinkClipScreenshotSettings.restoreAllShortcutDefaults(defaults: defaults) }
        let reload = { reloads += 1 }
        let save = { saves += 1; try store.save() }
        let parent = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        parent.orderFront(nil)
        defer { parent.orderOut(nil); parent.close() }
        var responses = 0
        var confirmation = false
        for (characters, code) in [("\r", UInt16(36)), ("\u{3}", UInt16(76)), ("\u{1b}", UInt16(53)), ("button", UInt16(0))] {
            let alert = SettingsShortcutReset.makeAlert()
            let previousResponses = responses
            SettingsShortcutReset.present(alert, on: parent) { confirmed in
                responses += 1
                confirmation = confirmed
                do { try SettingsShortcutReset.apply(confirmed: confirmed, store: store, save: save, commitScreenshots: commit, reload: reload) }
                catch { preconditionFailure("unexpected sheet save error") }
            }
            settle { parent.attachedSheet === alert.window }
            precondition(alert.window.defaultButtonCell === alert.buttons[0].cell && alert.buttons[0].keyEquivalent == "\r" && alert.buttons[1].keyEquivalent.isEmpty)
            if characters == "button" { alert.buttons[0].performClick(nil) }
            else {
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: alert.window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
                NSApp.sendEvent(event)
            }
            settle { parent.attachedSheet == nil && responses == previousResponses + 1 }
            precondition(!confirmation && saves == 0 && commits == 0 && reloads == 0 && store.preferences == original)
        }
        let cancelled = try SettingsShortcutReset.apply(confirmed: false, store: store, save: save, commitScreenshots: commit, reload: reload)
        precondition(!cancelled && saves == 0 && reloads == 0 && commits == 0 && store.preferences == original)
        do {
            try SettingsShortcutReset.apply(confirmed: true, store: store, save: { throw Injected.save }, commitScreenshots: commit, reload: reload)
            fatalError("expected save failure")
        } catch Injected.save {}
        precondition(store.preferences == original && commits == 0 && reloads == 0)
        precondition(defaults.integer(forKey: BlinkClipScreenshotSettings.regionKeyCodeKey) == 99)
        let failedReadback = try ClipboardStore(directoryURL: fixture).preferences
        precondition(failedReadback == original)
        try SettingsShortcutReset.apply(confirmed: true, store: store, save: save, commitScreenshots: commit, reload: reload)
        precondition(saves == 1 && commits == 1 && reloads == 1 && screenshotNotifications == 1)
        let readback = try ClipboardStore(directoryURL: fixture).preferences
        precondition(readback == store.preferences && readback.playSounds == false)
        precondition(readback.historyShortcut == .historyDefault && readback.stackShortcut == .stackDefault)
        precondition(readback.nextPinboardShortcut == .nextPinboardDefault && readback.previousPinboardShortcut == .previousPinboardDefault)
        precondition(readback.quickPasteModifierRawValue == NSEvent.ModifierFlags.command.rawValue && readback.plainTextModifierRawValue == NSEvent.ModifierFlags.shift.rawValue)
        precondition(defaults.integer(forKey: BlinkClipScreenshotSettings.regionKeyCodeKey) == Int(BlinkClipScreenshotSettings.regionDefault.keyCode))
        precondition(defaults.integer(forKey: BlinkClipScreenshotSettings.fullScreenKeyCodeKey) == Int(BlinkClipScreenshotSettings.fullScreenDefault.keyCode))
        precondition(defaults.integer(forKey: BlinkClipScreenshotSettings.regionModifiersKey) == Int(BlinkClipScreenshotSettings.regionDefault.modifierRawValue))
        precondition(defaults.integer(forKey: BlinkClipScreenshotSettings.fullScreenModifiersKey) == Int(BlinkClipScreenshotSettings.fullScreenDefault.modifierRawValue))
        let confirmAlert = SettingsShortcutReset.makeAlert()
        SettingsShortcutReset.present(confirmAlert, on: parent) { confirmed in
            confirmation = confirmed
            responses += 1
            do { try SettingsShortcutReset.apply(confirmed: confirmed, store: store, save: save, commitScreenshots: commit, reload: reload) }
            catch { preconditionFailure("unexpected confirm save error") }
        }
        settle { parent.attachedSheet === confirmAlert.window }
        confirmAlert.buttons[1].performClick(nil)
        settle { parent.attachedSheet == nil && responses == 5 }
        precondition(confirmation && saves == 2 && commits == 2 && reloads == 2 && screenshotNotifications == 2)
        print("PASS native production NSAlert: Return/Enter/Escape/Cancel button each cancel with zero save/reload; Restore button commits once; retained alert lifecycle completes")
        print("PASS production SettingsShortcutReset: cancel zero writes/reloads; injected save failure rollback; confirmed complete defaults; real ClipboardStore readback; screenshot adapter isolated suite; registration callback once")
    }
}
