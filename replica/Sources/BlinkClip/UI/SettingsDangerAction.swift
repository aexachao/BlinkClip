import AppKit
import BlinkClipCore

/// 设置页里「不可撤销」动作的确认层。
///
/// 两个动作共用同一套规矩：把**影响面**（多少条）写进弹窗、确认按钮自带计数、
/// 取消不改变任何状态、确认才落地。「恢复全部快捷键…」的弹窗仍由
/// `SettingsShortcutReset` 提供（它同时负责事务与回滚），这里只负责「清空历史记录…」。
@MainActor
enum SettingsDangerAction {
    /// 将被 `ClipboardStore.eraseHistory()` 删除的条数：在历史里、且没有被任何分组引用的条目。
    ///
    /// 与 `eraseHistory()` 的删除条件逐字一致（`isInHistory && pinboardIDs.isEmpty`），
    /// 所以弹窗里的数字就是用户会失去的条数；钉到分组的项目不在其中。
    static func historyCount(in store: ClipboardStore) -> Int {
        store.items.filter { $0.isInHistory && $0.pinboardIDs.isEmpty }.count
    }

    /// 「清空 N 条」：确认按钮直接用它，用户不用回读正文就知道确认后的后果。
    static func clearHistoryConfirmTitle(_ count: Int) -> String {
        SettingsCopy.trilingual("清空 \(count) 条", "清除 \(count) 筆", "Clear \(count)")
    }

    static func makeClearHistoryAlert(count: Int) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = SettingsCopy.trilingual("清空历史记录？", "清除歷史記錄？", "Clear History?")
        // 一条与多条分开写，英文单复数才不会出现「1 history entries」。
        alert.informativeText = count == 1
            ? SettingsCopy.trilingual("将清空 1 条历史记录，且无法撤销。已钉到分组的项目会保留。",
                                      "將清除 1 筆歷史記錄，且無法復原。已釘到分組的項目會保留。",
                                      "This clears 1 history entry and cannot be undone. Items pinned to a group are kept.")
            : SettingsCopy.trilingual("将清空 \(count) 条历史记录，且无法撤销。已钉到分组的项目会保留。",
                                      "將清除 \(count) 筆歷史記錄，且無法復原。已釘到分組的項目會保留。",
                                      "This clears \(count) history entries and cannot be undone. Items pinned to a group are kept.")
        // 顺序与其他确认弹窗一致：取消在前并占 Return，危险动作在后、不带快捷键。
        let cancel = alert.addButton(withTitle: SettingsCopy.text("general.action.cancel"))
        cancel.keyEquivalent = "\r"
        let confirm = alert.addButton(withTitle: clearHistoryConfirmTitle(count))
        confirm.hasDestructiveAction = true
        confirm.keyEquivalent = ""
        alert.window.defaultButtonCell = cancel.cell as? NSButtonCell
        return alert
    }

    /// 有窗口时用 sheet，没有窗口时才退回模态；两条路都只有第二个按钮会执行动作。
    static func present(_ alert: NSAlert, on window: NSWindow?, confirm: @escaping () -> Void) {
        if let window, window.isVisible {
            alert.beginSheetModal(for: window) { response in
                guard response == .alertSecondButtonReturn else { return }
                confirm()
            }
        } else if alert.runModal() == .alertSecondButtonReturn {
            confirm()
        }
    }
}
