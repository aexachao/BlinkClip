// Compiles the production editor registry and adapter with isolated dependencies.
// No defaults, clipboard, event monitors, or sound devices are accessed.
import AppKit
import Combine
import Foundation

enum Defaults {
    static var hasCustomClipboardHotkey = false
    static var clipboardHotkeyKeyCode = 0
    static var clipboardHotkeyModifiers = 0
    static var hasCustomFileSaveHotkey = false
    static var fileSaveHotkeyKeyCode = 0
    static var fileSaveHotkeyModifiers = 0
    static var hasCustomPreviousHistoryImageHotkey = false
    static var previousHistoryImageHotkeyKeyCode = 0
    static var previousHistoryImageHotkeyModifiers = 0
    static var hasCustomNextHistoryImageHotkey = false
    static var nextHistoryImageHotkeyKeyCode = 0
    static var nextHistoryImageHotkeyModifiers = 0
    static func clearClipboardHotkey() { hasCustomClipboardHotkey = false }
    static func clearFileSaveHotkey() { hasCustomFileSaveHotkey = false }
}
// EditorShortcutRegistry owns the real Defaults.editorShortcutConfiguration extension.

enum ToolbarItemID: String, Hashable {
    case rectangle, ellipse, line, arrow, pen, marker, mosaic, eraser, numbered, text
    case undo, redo, pin, close, save, confirm, moveSelection
    var localizedTitle: String { rawValue }
}
enum ToolbarLayout { static let canonicalOrder: [ToolbarItemID] = [.confirm, .save, .pin, .close] }
enum L10n {
    static let editorShortcutSelect = "Select"
    static let editorShortcutShapeFill = "Fill"
    static let clipboardShortcutDefaultDisplay = "Double-tap ⌘"
    static let editorShortcutReserved = "Reserved"
    static func editorShortcutConflict(_ title: String) -> String { title }
}
extension Notification.Name {
    static let hotkeyDidChange = Self("feedback-fixture.hotkey")
    static let editorShortcutsDidChange = Self("feedback-fixture.editor")
}

@main struct FeedbackShortcutHarness {
    static func event(_ code: UInt16, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                        timestamp: 0, windowNumber: 0, context: nil,
                        characters: "", charactersIgnoringModifiers: "",
                        isARepeat: false, keyCode: code)!
    }
    static func main() {
        precondition(EditorShortcutRegistry.displayString(for: .toolbar(.confirm)) == L10n.clipboardShortcutDefaultDisplay,
                     "unset confirm is backed by the editor-local double Command detector")
        precondition(!HotkeyManager.eventMatchesClipboardHotkey(event(0, .command)))
        Defaults.hasCustomClipboardHotkey = true
        Defaults.clipboardHotkeyKeyCode = 0 // A is a valid key, not absence.
        Defaults.clipboardHotkeyModifiers = 768
        precondition(HotkeyManager.eventMatchesClipboardHotkey(event(0, [.command, .shift])))
        precondition(!HotkeyManager.eventMatchesClipboardHotkey(event(0, .command)))
        precondition(EditorShortcutRegistry.binding(for: .toolbar(.confirm))?.keyCode == 0)
        precondition(EditorShortcutRegistry.displayString(for: .toolbar(.confirm)) == "⇧⌘A")
        Defaults.clearClipboardHotkey()
        precondition(EditorShortcutRegistry.displayString(for: .toolbar(.confirm)) == L10n.clipboardShortcutDefaultDisplay)
        precondition(HotkeyManager.eventMatchesFileSaveHotkey(event(1, .command)))
        Defaults.hasCustomFileSaveHotkey = true
        Defaults.fileSaveHotkeyKeyCode = 3
        Defaults.fileSaveHotkeyModifiers = 2048
        precondition(!HotkeyManager.eventMatchesFileSaveHotkey(event(1, .command)))
        precondition(HotkeyManager.eventMatchesFileSaveHotkey(event(3, .option)))
        precondition(EditorShortcutRegistry.displayString(for: .toolbar(.save)) == "⌥F")
        Defaults.hasCustomPreviousHistoryImageHotkey = true
        Defaults.previousHistoryImageHotkeyKeyCode = 123
        Defaults.previousHistoryImageHotkeyModifiers = 512
        precondition(HotkeyManager.eventMatchesPreviousHistoryImageHotkey(event(123, .shift)))
        precondition(!HotkeyManager.eventMatchesPreviousHistoryImageHotkey(event(43)))
        Defaults.hasCustomNextHistoryImageHotkey = true
        Defaults.nextHistoryImageHotkeyKeyCode = 124
        Defaults.nextHistoryImageHotkeyModifiers = 512
        precondition(HotkeyManager.eventMatchesNextHistoryImageHotkey(event(124, .shift)))
        precondition(!HotkeyManager.eventMatchesNextHistoryImageHotkey(event(47)))
        var detector = EditorCommandDoubleTap()
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: .command, timestamp: 1))
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 1.1))
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: .command, timestamp: 1.2))
        precondition(detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 1.3))
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 1.4))
        _ = detector.flagsChanged(keyCode: 55, modifiers: .command, timestamp: 2)
        _ = detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 2.1)
        detector.reset() // keyDown, resign, custom binding or editor switch
        _ = detector.flagsChanged(keyCode: 55, modifiers: .command, timestamp: 2.2)
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 2.3))
        detector.reset()
        _ = detector.flagsChanged(keyCode: 55, modifiers: .command, timestamp: 3)
        _ = detector.flagsChanged(keyCode: 55, modifiers: [.command, .shift], timestamp: 3.1)
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 3.2))
        _ = detector.flagsChanged(keyCode: 55, modifiers: .command, timestamp: 4)
        _ = detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 4.1)
        _ = detector.flagsChanged(keyCode: 55, modifiers: .command, timestamp: 5)
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 5.1))
        detector.reset()
        _ = detector.flagsChanged(keyCode: 54, modifiers: .command, timestamp: 6)
        _ = detector.flagsChanged(keyCode: 54, modifiers: [], timestamp: 6.1)
        _ = detector.flagsChanged(keyCode: 54, modifiers: .command, timestamp: 6.2)
        precondition(detector.flagsChanged(keyCode: 54, modifiers: [], timestamp: 6.3))
        detector.reset()
        _ = detector.flagsChanged(keyCode: 55, modifiers: .command, timestamp: 7)
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 8), "long hold is not a tap")
        _ = detector.flagsChanged(keyCode: 55, modifiers: .command, timestamp: 8.1)
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 8.2))
        detector.reset()
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 9), "release without press is ignored")
        _ = detector.flagsChanged(keyCode: 55, modifiers: .command, timestamp: 10)
        _ = detector.flagsChanged(keyCode: 56, modifiers: [.command, .shift], timestamp: 10.1)
        precondition(!detector.flagsChanged(keyCode: 55, modifiers: [], timestamp: 10.2))
        var callbacks = 0
        for base in [11.0, 12.0] {
            for (offset, flags): (Double, NSEvent.ModifierFlags) in [(0, .command), (0.1, []), (0.2, .command), (0.3, [])] {
                if detector.flagsChanged(keyCode: 55, modifiers: flags, timestamp: base + offset) { callbacks += 1 }
            }
        }
        precondition(callbacks == 2, "each independent double tap invokes confirm exactly once")
        for keyCode: UInt16 in [54, 55] {
            detector.reset()
            var capsLockCallbacks = 0
            for (offset, flags): (Double, NSEvent.ModifierFlags) in [
                (0, [.command, .capsLock]), (0.1, .capsLock),
                (0.2, [.command, .capsLock]), (0.3, .capsLock)
            ] {
                if detector.flagsChanged(keyCode: keyCode, modifiers: flags, timestamp: 13 + offset) {
                    capsLockCallbacks += 1
                }
            }
            precondition(capsLockCallbacks == 1, "persistent Caps Lock permits either Command key's double tap")
        }
        for capsLockFlags: NSEvent.ModifierFlags in [.capsLock, []] {
            detector.reset()
            let priorFlags: NSEvent.ModifierFlags = capsLockFlags.isEmpty ? .capsLock : []
            _ = detector.flagsChanged(keyCode: 55, modifiers: [.command, priorFlags], timestamp: 14)
            _ = detector.flagsChanged(keyCode: 55, modifiers: priorFlags, timestamp: 14.1)
            precondition(!detector.flagsChanged(keyCode: 57, modifiers: capsLockFlags, timestamp: 14.15),
                         "a Caps Lock key event cannot confirm")
            _ = detector.flagsChanged(keyCode: 55, modifiers: [.command, capsLockFlags], timestamp: 14.2)
            precondition(!detector.flagsChanged(keyCode: 55, modifiers: capsLockFlags, timestamp: 14.3),
                         "toggling Caps Lock interrupts the pending double tap")
        }
        for extra: NSEvent.ModifierFlags in [.shift, .option, .control, .function] {
            detector.reset()
            var chordCallbacks = 0
            for (offset, flags): (Double, NSEvent.ModifierFlags) in [
                (0, [.command, .capsLock, extra]), (0.1, [.capsLock, extra]),
                (0.2, [.command, .capsLock, extra]), (0.3, [.capsLock, extra])
            ] {
                if detector.flagsChanged(keyCode: 55, modifiers: flags, timestamp: 15 + offset) {
                    chordCallbacks += 1
                }
            }
            precondition(chordCallbacks == 0, "Caps Lock does not permit other modifier chords")
        }
        Defaults.clipboardHotkeyKeyCode = -1
        Defaults.hasCustomClipboardHotkey = true
        precondition(HotkeyManager.shared.currentClipboardHotkey() == nil)
        Defaults.fileSaveHotkeyKeyCode = Int.max
        precondition(HotkeyManager.eventMatchesFileSaveHotkey(event(1, .command)))
        print("{\"passed\":true,\"checks\":41,\"boundary\":\"production adapter and registry; synthetic NSEvents; isolated preference fixtures\"}")
    }
}
