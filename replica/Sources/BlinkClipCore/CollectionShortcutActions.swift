import Foundation

/// Value matching for signatures produced by ShortcutFunctions.shortcutForEvent.
public enum CollectionShortcutActions {
    public struct QuickPasteAction {
        public let index: Int
        public let options: PasteboardRestore.Options
    }

    public static func copyOptions(for signature: KeyboardShortcut,
                                   plainTextModifierRawValue: UInt) -> PasteboardRestore.Options? {
        guard signature.keyCode == ShortcutFunctions.keyCodeForKey("c") else { return nil }
        let command: UInt = 0x100000
        if signature.modifierRawValue == command { return [] }
        if signature.modifierRawValue == (command | plainTextModifierRawValue) { return .plainText }
        return nil
    }

    public static func quickPasteAction(for signature: KeyboardShortcut,
                                        quickPasteModifierRawValue: UInt,
                                        plainTextModifierRawValue: UInt) -> QuickPasteAction? {
        let plainModifiers = plainTextModifierRawValue == quickPasteModifierRawValue
            ? quickPasteModifierRawValue : quickPasteModifierRawValue ^ plainTextModifierRawValue
        let options: PasteboardRestore.Options
        if signature.modifierRawValue == plainModifiers {
            options = .plainText
        } else if signature.modifierRawValue == quickPasteModifierRawValue {
            options = []
        } else {
            return nil
        }
        for index in 0..<9 {
            if signature.keyCode == ShortcutFunctions.keyCodeForKey(String(index + 1)) {
                return QuickPasteAction(index: index, options: options)
            }
        }
        return nil
    }
}
