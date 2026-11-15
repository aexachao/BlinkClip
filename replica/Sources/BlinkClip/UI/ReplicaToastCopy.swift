// 所有轻提示（toast）文案的唯一来源：复制 / 暂停 / 继续 / 截图已复制。
//
// 为什么不再走 Core 的 `Localizable.strings`：那张表只带 en 与 zh-Hans 两个
// lproj，`zh-Hant` 会回落到开发语言（英文），繁体用户看到的暂停/继续提示
// 会整句变英文。这里与 `ScreenshotSettingsCopy` 一样把三语写进同一个 `Entry`，
// 结构上不可能出现「某语言缺键再回落」的分支。
//
// 语言判定不在本文件里：与设置页共用 `BlinkClipCore.SettingsLanguage.resolved()`，
// 所以同一个进程里设置页、截图文案与 toast 文案永远是同一种语言。

import Foundation
import BlinkClipCore

enum ReplicaToastCopy {
    enum Key: String, CaseIterable {
        /// 复制成功（面板里复制 / 复制并粘贴）。
        case copied = "toast.copied"
        /// 暂停采集（无定时）。
        case pastePaused = "toast.paste-paused"
        /// 暂停采集（有定时）：时间合进同一句，不再单独一行小字。
        case pastePausedUntil = "toast.paste-paused-until"
        /// 继续采集。
        case pasteResumed = "toast.paste-resumed"
        /// 截图已落库并写进剪贴板。
        case screenshotCopied = "toast.screenshot.copied"
    }

    /// 三张完整表；每个 key 在 `entries` 里必须同时给出三种语言。
    enum Table: String {
        case en
        case zhHans = "zh-Hans"
        case zhHant = "zh-Hant"
    }

    static var language: SettingsLanguage { SettingsLanguage.resolved() }

    static var table: Table {
        switch language {
        case .en: return .en
        case .zhHans: return .zhHans
        case .zhHant: return .zhHant
        }
    }

    static var tableIdentifier: String { table.rawValue }

    static func text(_ key: Key) -> String {
        guard let entry = entries[key] else { return key.rawValue }
        switch table {
        case .en: return entry.en
        case .zhHans: return entry.hans
        case .zhHant: return entry.hant
        }
    }

    /// 「已暂停记录剪贴板 · 至 14:30」：时间与标题在同一行，用中点分隔。
    static func pastePaused(until time: String) -> String {
        String(format: text(.pastePausedUntil), time)
    }

    private struct Entry {
        let en: String
        let hans: String
        let hant: String
        init(_ en: String, _ hans: String, _ hant: String) {
            self.en = en
            self.hans = hans
            self.hant = hant
        }
    }

    private static let entries: [Key: Entry] = [
        // 与设置页/状态栏的「暂停采集 / 继续采集」同一套术语（繁中用「擷取」）。
        .copied: Entry("Copied", "已复制", "已複製"),
        .pastePaused: Entry("Capture paused", "已暂停采集", "已暫停擷取"),
        .pastePausedUntil: Entry("Capture paused · Until %@",
                                 "已暂停采集 · 至 %@",
                                 "已暫停擷取 · 至 %@"),
        .pasteResumed: Entry("Capture resumed", "已恢复采集", "已恢復擷取"),
        .screenshotCopied: Entry("Screenshot copied", "已复制截图", "截圖已複製"),
    ]
}
