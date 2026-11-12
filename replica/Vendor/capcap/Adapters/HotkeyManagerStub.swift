// TEMP-STUB (P1-A)
//
// Why this file exists: vendored capcap code (Editor/EditorShortcutRegistry,
// Capture/OverlayWindowController) references `HotkeyManager`, which lives in
// `Trigger/HotkeyManager.swift` — the whole `Trigger/` directory is explicitly
// excluded from the vendoring scope.
//
// Local editor bindings are read from the same preferences as their labels.
// Global triggers remain owned by BlinkClip; this adapter registers no hotkeys.

import AppKit
import Carbon
import Foundation

/// TEMP-STUB (P1-A) — see file header.
final class HotkeyManager {
    static let shared = HotkeyManager()

    private init() {}

    /// Carbon modifier masks. Duplicated here so the stub does not need to
    /// import Carbon; values are identical to `cmdKey`/`shiftKey`/`optionKey`/`controlKey`.
    private static let carbonCommand: UInt32 = 1 << 8   // 256
    private static let carbonShift: UInt32 = 1 << 9     // 512
    private static let carbonOption: UInt32 = 1 << 11   // 2048
    private static let carbonControl: UInt32 = 1 << 12  // 4096

    /// Carbon virtual key codes used by the capcap defaults.
    private static let keyS: UInt32 = 1
    private static let keyComma: UInt32 = 43
    private static let keyPeriod: UInt32 = 47

    /// Mirrors the upstream slot enum so call sites compile unchanged.
    enum HotkeySlot {
        case screenshot
        case quickPin
        case selectedImagePin
        case clipboardImagePin
        case clipboardTextPin
        case selectedImageEdit
        case clipboardImageEdit
        case textRecognition
        case copyImageText
        case screenshotTranslation
        case record
        case imageMerge
        case finderUpload
        case fullScreenScreenshot
        case colorPicker
        case clipboard
        case fileSave
        case previousHistoryImage
        case nextHistoryImage
        case historyPanel
    }

    // MARK: - Current editor bindings

    func currentClipboardHotkey() -> (keyCode: UInt32, modifiers: UInt32)? {
        guard Defaults.hasCustomClipboardHotkey else { return nil }
        return Self.binding(keyCode: Defaults.clipboardHotkeyKeyCode,
                            modifiers: Defaults.clipboardHotkeyModifiers)
    }

    private static func binding(keyCode: Int, modifiers: Int) -> (keyCode: UInt32, modifiers: UInt32)? {
        guard (0...Int(UInt16.max)).contains(keyCode),
              modifiers >= 0, modifiers <= Int(UInt32.max) else { return nil }
        let mask = carbonCommand | carbonShift | carbonOption | carbonControl
        guard UInt32(modifiers) & ~mask == 0 else { return nil }
        return (UInt32(keyCode), UInt32(modifiers))
    }

    func currentFileSaveHotkey() -> (keyCode: UInt32, modifiers: UInt32) {
        if Defaults.hasCustomFileSaveHotkey,
           let custom = Self.binding(keyCode: Defaults.fileSaveHotkeyKeyCode,
                                     modifiers: Defaults.fileSaveHotkeyModifiers) { return custom }
        return (Self.keyS, Self.carbonCommand)
    }

    func currentPreviousHistoryImageHotkey() -> (keyCode: UInt32, modifiers: UInt32) {
        if Defaults.hasCustomPreviousHistoryImageHotkey,
           let custom = Self.binding(keyCode: Defaults.previousHistoryImageHotkeyKeyCode,
                                     modifiers: Defaults.previousHistoryImageHotkeyModifiers) { return custom }
        return (Self.keyComma, 0)
    }

    func currentNextHistoryImageHotkey() -> (keyCode: UInt32, modifiers: UInt32) {
        if Defaults.hasCustomNextHistoryImageHotkey,
           let custom = Self.binding(keyCode: Defaults.nextHistoryImageHotkeyKeyCode,
                                     modifiers: Defaults.nextHistoryImageHotkeyModifiers) { return custom }
        return (Self.keyPeriod, 0)
    }

    // MARK: - Conflict detection (never reports a conflict)

    func hotkeyConflictMessage(forKeyCode keyCode: UInt32,
                              modifiers: UInt32,
                              assigningTo slot: HotkeySlot? = nil) -> String? {
        _ = keyCode
        _ = modifiers
        _ = slot
        return nil
    }

    // MARK: - Event matching

    static func eventMatchesClipboardHotkey(_ event: NSEvent) -> Bool {
        guard let binding = shared.currentClipboardHotkey() else { return false }
        return matches(event: event, keyCode: binding.keyCode, modifiers: binding.modifiers)
    }

    static func eventMatchesFileSaveHotkey(_ event: NSEvent) -> Bool {
        matches(event: event,
                keyCode: shared.currentFileSaveHotkey().keyCode,
                modifiers: shared.currentFileSaveHotkey().modifiers)
    }

    static func eventMatchesPreviousHistoryImageHotkey(_ event: NSEvent) -> Bool {
        matches(event: event,
                keyCode: shared.currentPreviousHistoryImageHotkey().keyCode,
                modifiers: shared.currentPreviousHistoryImageHotkey().modifiers)
    }

    static func eventMatchesNextHistoryImageHotkey(_ event: NSEvent) -> Bool {
        matches(event: event,
                keyCode: shared.currentNextHistoryImageHotkey().keyCode,
                modifiers: shared.currentNextHistoryImageHotkey().modifiers)
    }

    private static func matches(event: NSEvent, keyCode: UInt32, modifiers: UInt32) -> Bool {
        UInt32(event.keyCode) == keyCode
            && carbonModifiers(from: event.modifierFlags) == modifiers
    }

    // MARK: - Formatting helpers (pure, identical to upstream)

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let activeMask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let mods = flags.intersection(activeMask)
        var carbonMods: UInt32 = 0
        if mods.contains(.command) { carbonMods |= carbonCommand }
        if mods.contains(.shift) { carbonMods |= carbonShift }
        if mods.contains(.option) { carbonMods |= carbonOption }
        if mods.contains(.control) { carbonMods |= carbonControl }
        return carbonMods
    }

    static func modifierString(_ m: UInt32) -> String {
        var s = ""
        if m & carbonControl != 0 { s += "\u{2303}" }
        if m & carbonOption != 0 { s += "\u{2325}" }
        if m & carbonShift != 0 { s += "\u{21E7}" }
        if m & carbonCommand != 0 { s += "\u{2318}" }
        return s
    }

    static func keyString(_ keyCode: UInt32) -> String {
        let special: [UInt32: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
            123: "←", 124: "→", 125: "↓", 126: "↑"]
        if let value = special[keyCode] { return value }
        guard keyCode <= UInt32(UInt16.max) else { return "Key \(keyCode)" }
        let source = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        if let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue()
            let layout = UnsafeRawPointer(CFDataGetBytePtr(data))!.assumingMemoryBound(to: UCKeyboardLayout.self)
            var state: UInt32 = 0
            var count = 0
            var characters = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask), &state,
                characters.count, &count, &characters)
            if status == noErr, count > 0 {
                return String(utf16CodeUnits: characters, count: count).uppercased()
            }
        }
        return "Key \(keyCode)"
    }
}
