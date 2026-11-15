import AppKit

/// 底部快捷菜单（状态栏图标右键弹出）的模型、`NSMenu` 构建与退出二次确认。
///
/// 结构在这里是**纯数据**：`PanelShortcutMenuModel.groups(_:)` 只回答「哪些分组、
/// 每组哪些项、什么标题/图标/动作」，`PanelShortcutMenuBuilder` 才把它贴到
/// `NSMenu` 上。这样离屏 harness（`Tests/Native/PanelShortcutMenuHarness.swift`）
/// 可以直接枚举分组、检查图标与动作、驱动退出确认，不必启动整个 App，
/// 也不必真的把菜单弹出来。
///
/// 图标统一走 SF Symbol：`NSImage(systemSymbolName:accessibilityDescription:)`
/// 拿到的模板图由系统按菜单背景着色，深色 / 浅色外观共用一套资源，不需要
/// 两套位图。
enum PanelShortcutMenuLayout {
    /// 每行图标统一成同一个 16×16 盒子，各行标题才会对齐。
    static let iconSide: CGFloat = 16
}

// MARK: - 「帮助与关于」

extension Notification.Name {
    /// 「帮助与关于」菜单项只会发出这个通知，**由设置窗口观察后打开关于页**。
    ///
    /// 关于页正在从独立窗口迁进设置页内部（下一单），所以目前没有观察者：
    /// 没有观察者时 `NotificationCenter.post` 没有任何副作用，动作只会静默返回，
    /// 不会崩溃，也不会顺手弹出旧窗口。
    static let blinkClipOpenAbout = Notification.Name("blinkclip.openAbout")
}

// MARK: - 模型

/// 菜单项身份。测试按它断言分组成员与顺序，不依赖标题文本。
enum PanelShortcutMenuEntryID: String, CaseIterable {
    case openClipboard
    case newText
    case settings
    case checkForUpdates
    case helpAndAbout
    case diagnostics
    case pauseMonitoring
    /// 历史快捷键注册失败的只读提示（只在失败时出现）。
    case hotKeyNotice
    /// Stack 快捷键注册失败的只读提示（只在失败时出现）。
    case stackHotKeyNotice
    case quit
}

/// 菜单项要调的动作。`rawValue` 就是 `AppMain` 里 `@objc` 方法的 selector 名，
/// 构建器直接用 `Selector(rawValue)`，避免第二份映射表走样。
enum PanelShortcutMenuAction: String {
    case togglePanel = "togglePanel:"
    case newText = "newText:"
    case settings = "settings:"
    case checkForUpdates = "checkForUpdates:"
    case openAbout = "openAbout:"
    case toggleDiagnostics = "toggleDiagnostics:"
    case pause = "pause:"
    case confirmQuit = "confirmQuit:"

    var selector: Selector { Selector(rawValue) }
}

struct PanelShortcutMenuItem: Equatable {
    let id: PanelShortcutMenuEntryID
    let title: String
    /// `nil` 表示只读提示行（快捷键注册失败），构建时置灰且没有动作。
    let action: PanelShortcutMenuAction?
    /// SF Symbol 名。
    let symbol: String
    var keyEquivalent: String = ""
    var modifiers: NSEvent.ModifierFlags = [.command]

    var isEnabled: Bool { action != nil }

    /// 菜单右侧显示的快捷键：标准顺序 ⌃⌥⇧⌘ + 键名。
    var keyEquivalentDisplay: String {
        var text = ""
        if modifiers.contains(.control) { text += "\u{2303}" }
        if modifiers.contains(.option) { text += "\u{2325}" }
        if modifiers.contains(.shift) { text += "\u{21e7}" }
        if modifiers.contains(.command) { text += "\u{2318}" }
        return text + keyEquivalent
    }
}

struct PanelShortcutMenuGroup: Equatable {
    /// 分组名只给测试 / 报告用，不渲染进菜单。
    let title: String
    let items: [PanelShortcutMenuItem]
}

/// 每次右键时现取的状态。菜单在 `statusClicked` 里**重建**，所以这里的值
/// 永远是最新的（暂停 / 继续、诊断开关、快捷键注册失败）。
struct PanelShortcutMenuContext: Equatable {
    var productName: String
    var isMonitoringPaused: Bool
    /// 「收集诊断日志」/「停止收集诊断日志」，取自 `PreviewLocalization`。
    var diagnosticsTitle: String
    /// 历史快捷键注册失败时的提示文案；正常时为 `nil`。
    var hotKeyNotice: String?
    /// Stack 快捷键注册失败时的提示文案；正常时为 `nil`。
    var stackHotKeyNotice: String?

    init(productName: String,
         isMonitoringPaused: Bool,
         diagnosticsTitle: String,
         hotKeyNotice: String? = nil,
         stackHotKeyNotice: String? = nil) {
        self.productName = productName
        self.isMonitoringPaused = isMonitoringPaused
        self.diagnosticsTitle = diagnosticsTitle
        self.hotKeyNotice = hotKeyNotice
        self.stackHotKeyNotice = stackHotKeyNotice
    }
}

enum PanelShortcutMenuModel {
    /// 四组，组间一条 `NSMenuItem.separator()`：
    /// 动作 / 应用 / 维护 / 退出。
    static func groups(_ context: PanelShortcutMenuContext) -> [PanelShortcutMenuGroup] {
        var maintenance = [
            PanelShortcutMenuItem(id: .diagnostics,
                                  title: context.diagnosticsTitle,
                                  action: .toggleDiagnostics,
                                  symbol: "stethoscope"),
            PanelShortcutMenuItem(id: .pauseMonitoring,
                                  // 暂停中时这一项变成「继续采集」，图标跟着换成 play。
                                  title: context.isMonitoringPaused ? "继续采集" : "暂停采集",
                                  action: .pause,
                                  symbol: context.isMonitoringPaused ? "play.circle" : "pause.circle")
        ]
        // 注册失败的提示只是状态行，没有动作；放进「维护」组尾部，
        // 分组数量因此恒为 4，不会因为一次注册失败多出一块。
        if let notice = context.hotKeyNotice {
            maintenance.append(PanelShortcutMenuItem(id: .hotKeyNotice,
                                                     title: notice,
                                                     action: nil,
                                                     symbol: "exclamationmark.triangle"))
        }
        if let notice = context.stackHotKeyNotice {
            maintenance.append(PanelShortcutMenuItem(id: .stackHotKeyNotice,
                                                     title: notice,
                                                     action: nil,
                                                     symbol: "exclamationmark.triangle"))
        }
        return [
            PanelShortcutMenuGroup(title: "动作", items: [
                PanelShortcutMenuItem(id: .openClipboard,
                                      title: "打开剪贴板",
                                      action: .togglePanel,
                                      symbol: "rectangle.on.rectangle"),
                PanelShortcutMenuItem(id: .newText,
                                      title: "新建文本…",
                                      action: .newText,
                                      symbol: "square.and.pencil")
            ]),
            PanelShortcutMenuGroup(title: "应用", items: [
                PanelShortcutMenuItem(id: .settings,
                                      title: "设置…",
                                      action: .settings,
                                      symbol: "gearshape",
                                      keyEquivalent: ",",
                                      modifiers: [.command]),
                PanelShortcutMenuItem(id: .checkForUpdates,
                                      title: "检查更新",
                                      action: .checkForUpdates,
                                      symbol: "arrow.triangle.2.circlepath"),
                PanelShortcutMenuItem(id: .helpAndAbout,
                                      title: "帮助与关于",
                                      action: .openAbout,
                                      symbol: "info.circle")
            ]),
            PanelShortcutMenuGroup(title: "维护", items: maintenance),
            PanelShortcutMenuGroup(title: "退出", items: [
                PanelShortcutMenuItem(id: .quit,
                                      title: "退出 \(context.productName)",
                                      action: .confirmQuit,
                                      symbol: "power")
            ])
        ]
    }
}

// MARK: - NSMenu 构建

enum PanelShortcutMenuBuilder {
    /// 把模型贴成真正要弹出的 `NSMenu`。分组之间补分隔线，其余格式一律来自模型。
    static func makeMenu(_ context: PanelShortcutMenuContext, target: AnyObject?) -> NSMenu {
        let menu = NSMenu()
        // 置灰完全由模型决定：交给 AppKit 自动启用的话，只读提示行会因为
        // 「没有动作」被验证成可用状态。
        menu.autoenablesItems = false
        for (index, group) in PanelShortcutMenuModel.groups(context).enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for entry in group.items { menu.addItem(makeItem(entry, target: target)) }
        }
        return menu
    }

    static func makeItem(_ entry: PanelShortcutMenuItem, target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: entry.title,
                              action: entry.action.map { Selector($0.rawValue) },
                              keyEquivalent: entry.keyEquivalent)
        item.keyEquivalentModifierMask = entry.modifiers
        item.target = target
        // 提示行没有动作，但同样带图标，菜单的左侧图标列不会缺一格。
        item.image = icon(entry.symbol, accessibilityDescription: entry.title)
        item.isEnabled = entry.isEnabled
        return item
    }

    /// 统一的 16×16 模板图标。
    static func icon(_ symbol: String, accessibilityDescription: String? = nil) -> NSImage? {
        guard let symbolImage = NSImage(systemSymbolName: symbol,
                                        accessibilityDescription: accessibilityDescription) else {
            return nil
        }
        // 字重固定，符号大小才在同一行里一致；随后把画布钉到 16×16。
        let configured = symbolImage.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)) ?? symbolImage
        configured.size = NSSize(width: PanelShortcutMenuLayout.iconSide,
                                 height: PanelShortcutMenuLayout.iconSide)
        configured.isTemplate = true
        return configured
    }
}

// MARK: - 退出二次确认

/// 「退出 闪贴」的二次确认。
///
/// 弹窗响应是注入的，`runModal` / `terminate` 都能替换，所以
/// 「取消（`.alertFirstButtonReturn`）不退出」可以在离屏 harness 里断言，
/// 不需要真的结束进程。
@MainActor
enum PanelShortcutMenuQuitConfirmation {
    struct Copy: Equatable {
        var title: String
        var message: String
        var confirmTitle: String
        var cancelTitle: String

        static let standard = Copy(title: "要退出闪贴吗？",
                                   message: "退出后将停止剪贴板记录与快捷键。",
                                   confirmTitle: "退出",
                                   cancelTitle: "取消")
    }

    static var copy: Copy { .standard }

    /// 取消按钮在前：`NSAlert` 的**第一个按钮就是默认按钮**（蓝底、Return 落在它上面），
    /// 所以默认动作是取消，红色 destructive 只染「退出」。
    ///
    /// Esc 再显式挂到取消上：一个 `NSButton` 的 `keyEquivalent` 只能存一个键，
    /// 而 Return 由 `NSAlert` 的默认按钮机制负责，两者互不抢占。
    /// （`defaultButtonCell` 不要再手动改：赋值会把该按钮的 keyEquivalent 重置回
    /// `\r`，Esc 就丢了。）
    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = copy.title
        alert.informativeText = copy.message
        let cancel = alert.addButton(withTitle: copy.cancelTitle)   // .alertFirstButtonReturn
        let confirm = alert.addButton(withTitle: copy.confirmTitle) // .alertSecondButtonReturn
        confirm.hasDestructiveAction = true
        cancel.keyEquivalent = "\u{1b}"
        return alert
    }

    /// 只有「退出」按钮（`.alertSecondButtonReturn`）才放行；
    /// 取消、Esc、关窗（`.abort` / `.cancel`）一律返回 false。
    static func shouldTerminate(_ response: NSApplication.ModalResponse) -> Bool {
        response == .alertSecondButtonReturn
    }

    /// 返回是否真的要退出。注入点缺省时才是真实弹窗。
    @discardableResult
    static func confirm(runAlert: ((NSAlert) -> NSApplication.ModalResponse)? = nil,
                        terminate: (() -> Void)? = nil) -> Bool {
        let response = (runAlert ?? { alert in
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal()
        })(makeAlert())
        guard shouldTerminate(response) else { return false }
        (terminate ?? { NSApp.terminate(nil) })()
        return true
    }
}
