import AppKit
import Carbon
import Foundation

@MainActor
public enum ShortcutValidation {
    /// The original checks system shortcuts before walking the application's menu.
    public static func validateAgainstSystemHotKeys(shortcut: KeyboardShortcut, menu: @autoclosure () -> NSMenu?) -> ShortcutRecorderError? {
        validateAgainstSystemHotKeys(shortcut: ShortcutValue(keyCode: Int(shortcut.keyCode),
            internalModifiers: shortcut.modifierRawValue), menu: menu())
    }

    public static func validateAgainstSystemHotKeys(shortcut: ShortcutValue, menu: @autoclosure () -> NSMenu?) -> ShortcutRecorderError? {
        var copiedKeys: Unmanaged<CFArray>?
        if CopySymbolicHotKeys(&copiedKeys) == noErr,
           let keys = copiedKeys?.takeRetainedValue() as? [[String: Any]],
           keys.contains(where: { ShortcutFunctions.matchesSymbolicHotKey($0, shortcut: shortcut) }) {
            return ShortcutRecorderError(ShortcutMessages.value("shortcut-recorder.error.used-in-system"))
        }
        return validateAgainstMenu(shortcut: shortcut, menu: menu())
    }

    /// Depth-first submenu traversal, including Shift implicit in uppercase equivalents.
    public static func validateAgainstMenu(shortcut: KeyboardShortcut, menu: NSMenu?) -> ShortcutRecorderError? {
        validateAgainstMenu(shortcut: ShortcutValue(keyCode: Int(shortcut.keyCode),
            internalModifiers: shortcut.modifierRawValue), menu: menu)
    }

    public static func validateAgainstMenu(shortcut: ShortcutValue, menu: NSMenu?) -> ShortcutRecorderError? {
        for item in menu?.items ?? [] {
            if let failure = validateAgainstMenu(shortcut: shortcut, menu: item.submenu) { return failure }
            let rawModifiers = item.keyEquivalentModifierMask.rawValue
            let equivalent = item.keyEquivalent.lowercased()
            let candidate = ShortcutFunctions.keyEquivalentLabel(keyCode: shortcut.keyCode)
            guard equivalent == candidate else { continue }
            let exactEquivalent = item.keyEquivalent
            let exactCandidate = ShortcutFunctions.keyEquivalentLabel(keyCode: shortcut.keyCode)
            let modifiers = exactEquivalent == exactCandidate
                ? rawModifiers & 0x1e0000 : (rawModifiers & 0x1c0000) | 0x20000
            if modifiers == shortcut.internalModifiers {
                return ShortcutRecorderError(ShortcutMessages.menuConflict(item.title))
            }
        }
        return nil
    }

    public static func optionCompatibilityWarning(modifierRawValue: UInt,
                                                  version: OperatingSystemVersion) -> String? {
        guard requiresOptionCompatibilityWarning(modifierRawValue: modifierRawValue, version: version)
        else { return nil }
        return ShortcutMessages.value("shortcut-recorder.error.option-key")
    }

    public static func requiresOptionCompatibilityWarning(modifierRawValue: UInt,
                                                          version: OperatingSystemVersion) -> Bool {
        modifierRawValue & 0x80000 != 0 && modifierRawValue & 0x140000 == 0
            && version.majorVersion == 15 && version.minorVersion < 2
    }
}
