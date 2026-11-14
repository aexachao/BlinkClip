import AppKit
import BlinkClipCore
import BlinkClipCapture

/// The eight independent settings rows. No row restoration replaces the preferences object wholesale.
@MainActor
enum SettingsShortcutRow: String, CaseIterable {
    case history, stack, nextGroup, previousGroup, region, fullScreen, quickPaste, plainText
    var path: WritableKeyPath<AppPreferences, KeyboardShortcut?>? {
        switch self {
        case .history: return \.historyShortcut
        case .stack: return \.stackShortcut
        case .nextGroup: return \.nextPinboardShortcut
        case .previousGroup: return \.previousPinboardShortcut
        default: return nil
        }
    }
    var shortcutDefault: KeyboardShortcut? {
        switch self {
        case .history: return .historyDefault
        case .stack: return .stackDefault
        case .nextGroup: return .nextPinboardDefault
        case .previousGroup: return .previousPinboardDefault
        case .region: let value = BlinkClipScreenshotSettings.regionDefault; return .init(keyCode: value.keyCode, modifierRawValue: value.modifierRawValue)
        case .fullScreen: let value = BlinkClipScreenshotSettings.fullScreenDefault; return .init(keyCode: value.keyCode, modifierRawValue: value.modifierRawValue)
        default: return nil
        }
    }
    var title: String {
        switch self {
        case .history: return SettingsCopy.text("settings.shortcuts.activate-paste.title")
        case .stack: return SettingsCopy.text("settings.shortcuts.activate-paste-stack.title")
        case .nextGroup: return SettingsCopy.text("blinkclip.settings.shortcuts.next-group.title")
        case .previousGroup: return SettingsCopy.text("blinkclip.settings.shortcuts.previous-group.title")
        case .region: return ScreenshotSettingsCopy.text(.hotKeyRegionTitle)
        case .fullScreen: return ScreenshotSettingsCopy.text(.hotKeyFullScreenTitle)
        case .quickPaste: return SettingsCopy.text("settings.shortcuts.quick-paste.title")
        case .plainText: return SettingsCopy.text("settings.shortcuts.plain-text.title")
        }
    }
    var modifierPath: WritableKeyPath<AppPreferences, UInt>? {
        switch self { case .quickPaste: return \.quickPasteModifierRawValue; case .plainText: return \.plainTextModifierRawValue; default: return nil }
    }
    var modifierDefault: UInt { self == .quickPaste ? NSEvent.ModifierFlags.command.rawValue : NSEvent.ModifierFlags.shift.rawValue }
    func isModified(_ preferences: AppPreferences, screenshots: (SettingsShortcutRow) -> KeyboardShortcut?) -> Bool {
        if let path { return preferences[keyPath: path] != shortcutDefault }
        if let modifierPath { return preferences[keyPath: modifierPath] != modifierDefault }
        return screenshots(self) != shortcutDefault
    }
    static func occupant(of value: KeyboardShortcut, excluding row: Self, preferences: AppPreferences,
                         screenshots: (Self) -> KeyboardShortcut?) -> Self? {
        allCases.first { other in
            guard other != row, other.shortcutDefault != nil else { return false }
            return (other.path.map { preferences[keyPath: $0] } ?? screenshots(other)) == value
        }
    }
    static func conflictMessage(_ owner: Self) -> String {
        SettingsCopy.trilingual("默认快捷键已被“\(owner.title)”占用。请先修改该行，再重试恢复。", "預設快捷鍵已被「\(owner.title)」占用。請先修改該列，再重試復原。", "The default shortcut is used by “\(owner.title)”. Change that row, then restore again.")
    }
    struct Conflict: LocalizedError {
        let owner: SettingsShortcutRow
        let message: String
        var errorDescription: String? { message }
    }
    /// Save before registration. Failure restores only the field this operation owns.
    func restore(store: ClipboardStore, save: (() throws -> Void)? = nil,
                 screenshots: (Self) -> KeyboardShortcut? = { _ in nil },
                 commitScreenshot: (Self) -> Void = { _ in }, reload: () -> Void) throws {
        if let value = shortcutDefault,
           let owner = Self.occupant(of: value, excluding: self, preferences: store.preferences, screenshots: screenshots) {
            throw Conflict(owner: owner, message: Self.conflictMessage(owner))
        }
        if let path {
            let previous = store.preferences[keyPath: path]
            store.preferences[keyPath: path] = shortcutDefault
            do { try (save ?? { try store.save() })() }
            catch { store.preferences[keyPath: path] = previous; throw error }
        } else if let modifierPath {
            let previous = store.preferences[keyPath: modifierPath]
            store.preferences[keyPath: modifierPath] = modifierDefault
            do { try (save ?? { try store.save() })() }
            catch { store.preferences[keyPath: modifierPath] = previous; throw error }
        } else { commitScreenshot(self); return }
        reload()
    }
}
