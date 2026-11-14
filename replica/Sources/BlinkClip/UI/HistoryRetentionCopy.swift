import Foundation
import BlinkClipCore

enum HistoryRetentionCopy {
    static func text(_ zhHans: String, _ zhHant: String, _ en: String) -> String {
        SettingsStrings.trilingual(zhHans, zhHant, en)
    }
    static func option(_ days: Int) -> String {
        days == 0 ? text("永久", "永久", "Forever")
            : text("\(days) 天", "\(days) 天", days == 1 ? "1 day" : "\(days) days")
    }
    static func period(_ days: Int) -> String {
        days <= 0 ? text("永久（不按时间清理）", "永久（不依時間清理）", "Forever (no time-based cleanup)")
            : text("最近 \(days) 天", "最近 \(days) 天", days == 1 ? "Last 1 day" : "Last \(days) days")
    }
    static func isShorter(from old: Int, to new: Int) -> Bool { new > 0 && (old <= 0 || new < old) }
    static func shorteningWarning(_ days: Int) -> String {
        text("将改为保留最近 \(days) 天。过期且未加入分组的历史记录会立即清理，此操作无法撤销。",
             "將改為保留最近 \(days) 天。過期且未加入分組的歷史記錄會立即清除，此操作無法復原。",
             "Keep only the last \(days) days. Expired history entries outside groups will be removed immediately. This cannot be undone.")
    }
}
