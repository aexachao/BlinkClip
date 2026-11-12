import AppKit
import Foundation
import BlinkClipCore
import BlinkClipCapture

@main struct ShortcutRowRestoreHarness {
    enum Injected: Error { case save }
    @MainActor static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"]!)
        let suite = "local.blinkclip.row-restore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("local.blinkclip.regression.") else { fatalError("isolated test bundle required") }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        var checks = 0
        func check(_ condition: Bool) { checks += 1; precondition(condition) }
        for row in SettingsShortcutRow.allCases {
            let fixture = root.appendingPathComponent("build/row-\(row.rawValue)")
            let store = try ClipboardStore(directoryURL: fixture)
            var shots: [SettingsShortcutRow: KeyboardShortcut] = [:]
            for candidate in SettingsShortcutRow.allCases {
                if let path = candidate.path { store.preferences[keyPath: path] = nil }
                if candidate == .region || candidate == .fullScreen {
                    shots[candidate] = .init(keyCode: candidate == .region ? 98 : 99, modifierRawValue: NSEvent.ModifierFlags.command.rawValue)
                }
                if let path = candidate.modifierPath { store.preferences[keyPath: path] = 0 }
            }
            store.preferences.playSounds = false
            try store.save()
            let before = store.preferences
            let beforeShots = shots
            var saves = 0, reloads = 0, commits = 0
            let read = { (target: SettingsShortcutRow) in shots[target] }
            check(row.isModified(store.preferences, screenshots: read))
            // Exercise the production six-way conflict gate against every other hotkey row.
            if let value = row.shortcutDefault {
                for owner in SettingsShortcutRow.allCases where owner != row && owner.shortcutDefault != nil {
                    if let path = owner.path { store.preferences[keyPath: path] = value } else { shots[owner] = value }
                    do {
                        try row.restore(store: store, save: { saves += 1 }, screenshots: read,
                            commitScreenshot: { _ in commits += 1 }, reload: { reloads += 1 })
                        preconditionFailure("occupied default restored")
                    } catch let error as SettingsShortcutRow.Conflict {
                        check(error.owner == owner && error.localizedDescription.contains(owner.title))
                    }
                    check(saves == 0 && reloads == 0 && commits == 0)
                    if let path = owner.path { store.preferences[keyPath: path] = before[keyPath: path] } else { shots[owner] = beforeShots[owner] }
                }
            }
            if row.path != nil || row.modifierPath != nil {
                do { try row.restore(store: store, save: { throw Injected.save }, screenshots: read, reload: { reloads += 1 }); preconditionFailure("failure not thrown") }
                catch Injected.save {}
                check(store.preferences == before && reloads == 0)
            }
            try row.restore(store: store, save: { saves += 1; try store.save() }, screenshots: read,
                commitScreenshot: { target in
                    commits += 1
                    // Isolated suite writes prove only the selected screenshot slot is committed.
                    defaults.set(Int(target.shortcutDefault!.keyCode), forKey: target.rawValue)
                    shots[target] = target.shortcutDefault
                }, reload: { reloads += 1 })
            check(!row.isModified(store.preferences, screenshots: read))
            check(commits == (row.path == nil && row.modifierPath == nil ? 1 : 0))
            check(saves == (commits == 0 ? 1 : 0) && reloads == (commits == 0 ? 1 : 0))
            let reopened = try ClipboardStore(directoryURL: fixture)
            var expected = before
            if let path = row.path { expected[keyPath: path] = row.shortcutDefault }
            if let path = row.modifierPath { expected[keyPath: path] = row.modifierDefault }
            check(store.preferences == expected && reopened.preferences == expected)
            for other in SettingsShortcutRow.allCases where other != row {
                if let path = other.path { check(store.preferences[keyPath: path] == before[keyPath: path] && reopened.preferences[keyPath: path] == before[keyPath: path]) }
                if let path = other.modifierPath { check(store.preferences[keyPath: path] == before[keyPath: path] && reopened.preferences[keyPath: path] == before[keyPath: path]) }
                if other == .region || other == .fullScreen { check(shots[other] == beforeShots[other] && defaults.object(forKey: other.rawValue) == nil) }
            }
            if let path = row.path { check(reopened.preferences[keyPath: path] == row.shortcutDefault) }
            if let path = row.modifierPath { check(reopened.preferences[keyPath: path] == row.modifierDefault) }
            check(!reopened.preferences.playSounds)
            defaults.removePersistentDomain(forName: suite)
        }
        // Exercise the actual screenshot bridge and notification in this unique test domain.
        BlinkClipScreenshotSettings.setShortcut(.init(keyCode: 98, modifierRawValue: NSEvent.ModifierFlags.command.rawValue), for: .region, force: true)
        BlinkClipScreenshotSettings.setShortcut(.init(keyCode: 99, modifierRawValue: NSEvent.ModifierFlags.command.rawValue), for: .fullScreen, force: true)
        for (slot, other) in [(BlinkClipScreenshotHotKeySlot.region, BlinkClipScreenshotHotKeySlot.fullScreen), (.fullScreen, .region)] {
            let beforeOther = other == .region ? BlinkClipScreenshotSettings.regionShortcut : BlinkClipScreenshotSettings.fullScreenShortcut
            var notifications: [BlinkClipScreenshotHotKeySlot?] = []
            let observer = NotificationCenter.default.addObserver(forName: BlinkClipScreenshotSettings.hotKeysDidChange, object: nil, queue: nil) { notifications.append($0.object as? BlinkClipScreenshotHotKeySlot) }
            BlinkClipScreenshotSettings.setShortcut(BlinkClipScreenshotSettings.default(for: slot), for: slot, force: true)
            NotificationCenter.default.removeObserver(observer)
            check(notifications.count == 1 && notifications[0] == slot)
            check((other == .region ? BlinkClipScreenshotSettings.regionShortcut : BlinkClipScreenshotSettings.fullScreenShortcut) == beforeOther)
            check((slot == .region ? BlinkClipScreenshotSettings.regionShortcut : BlinkClipScreenshotSettings.fullScreenShortcut) == BlinkClipScreenshotSettings.default(for: slot))
        }
        print("PASS \(checks) independent row restore/conflict/rollback/persisted-field assertions; real screenshot slot notifications verified in isolated test domain; no production defaults")
    }
}
