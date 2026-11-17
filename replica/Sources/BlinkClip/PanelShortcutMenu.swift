import AppKit

/// 快捷菜单的模型、`NSMenu` 构建与退出二次确认。
///
/// 同一套结构服务两个入口，差异只有**数据**（`PanelShortcutMenuVariant`）：
/// - `.statusItem`：状态栏图标右键（`AppMain.statusClicked`）；
/// - `.panelOverflow`：面板工具栏最右边的 `⋯`（`PanelViews.PanelMoreMenu`）。
///
/// 两者都经由 `PanelShortcutMenuModel.groups(_:)` 出分组、`PanelShortcutMenuBuilder`
/// 贴成 `NSMenu`，动作共用 `PanelShortcutMenuAction` 的 selector 名与同一个
/// target（`AppMain` 的 `@objc` 方法），所以不会出现「状态栏有检查更新、面板没有」
/// 这种两份实现走样。
///
/// 结构在这里是**纯数据**：`groups(_:)` 只回答「哪些分组、每组哪些项、
/// 什么标题/图标/动作」，`PanelShortcutMenuBuilder` 才把它贴到 `NSMenu` 上。
/// 这样离屏 harness（`Tests/Native/PanelShortcutMenuHarness.swift`）可以直接枚举
/// 分组、检查图标与动作、驱动退出确认，不必启动整个 App，也不必真的把菜单弹出来。
///
/// 图标统一走 SF Symbol：`NSImage(systemSymbolName:accessibilityDescription:)`
/// 拿到的模板图由系统按菜单背景着色，深色 / 浅色外观共用一套资源，不需要
/// 两套位图。
enum PanelShortcutMenuLayout {
    /// 每行图标统一成同一个 16×16 盒子，各行标题才会对齐。
    static let iconSide: CGFloat = 16
}

// MARK: - 两个入口的差异

/// 菜单放在哪里。两个变体共用同一台模型 / 构建器，只换数据：
/// 面板场景下剪贴板面板本来就开着，所以不给「打开剪贴板」；面板也没有状态栏
/// 专属的诊断开关与全局热键注册失败提示。
enum PanelShortcutMenuVariant: String, CaseIterable {
    case statusItem
    case panelOverflow
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
    /// 状态栏变体的「暂停采集 / 继续采集」单项；面板变体里是带子菜单的父项。
    case pauseMonitoring
    /// 面板变体子菜单里的「暂停」（不限时）。
    case pauseIndefinitely
    /// 面板变体子菜单里的「暂停 N 分钟 / N 小时」，具体分钟数在 `minutes` 上。
    case pauseForMinutes
    /// 面板变体子菜单里的「继续」。
    case resumeMonitoring
    /// 历史快捷键注册失败的只读提示（只在失败时出现）。
    case hotKeyNotice
    /// Stack 快捷键注册失败的只读提示（只在失败时出现）。
    case stackHotKeyNotice
    case quit
}

/// 菜单项要调的动作。`rawValue` 就是 `AppMain` 里 `@objc` 方法的 selector 名，
/// 构建器直接用它，避免第二份映射表走样。
enum PanelShortcutMenuAction: String {
    case togglePanel = "togglePanel:"
    case newText = "newText:"
    case settings = "settings:"
    case checkForUpdates = "checkForUpdates:"
    case openAbout = "openAbout:"
    case toggleDiagnostics = "toggleDiagnostics:"
    /// 状态栏变体的「暂停采集 / 继续采集」：一个开关。
    case pause = "pause:"
    /// 面板变体子菜单的「暂停」：暂停且不设定时恢复。
    case pauseIndefinitely = "pauseIndefinitely:"
    /// 面板变体子菜单的「暂停 N 分钟」：分钟数通过 `representedObject` 传。
    case pauseForMinutes = "pauseForMinutes:"
    /// 面板变体子菜单的「继续」。
    case resumeMonitoring = "resumeMonitoring:"
    case confirmQuit = "confirmQuit:"

    var selector: Selector { Selector(rawValue) }
}

/// 子菜单（目前只有面板变体的「暂停」一条）。
struct PanelShortcutMenuSubmenu: Equatable {
    let items: [PanelShortcutMenuItem]
}

struct PanelShortcutMenuItem: Equatable {
    let id: PanelShortcutMenuEntryID
    let title: String
    /// `nil` 表示只读提示行（快捷键注册失败）或带子菜单的父项。
    let action: PanelShortcutMenuAction?
    /// SF Symbol 名。
    let symbol: String
    var keyEquivalent: String = ""
    var modifiers: NSEvent.ModifierFlags = [.command]
    /// 有子菜单的项在 `NSMenuItem` 上挂 `submenu`，本体不执行动作。
    var submenu: PanelShortcutMenuSubmenu? = nil
    /// 带参数动作的载荷（「暂停 N 分钟」的分钟数），构建时写进 `representedObject`。
    var minutes: Int? = nil

    var isEnabled: Bool { action != nil || submenu != nil }

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

/// 每次弹出时现取的状态。菜单在点击时**重建**，所以这里的值永远是最新的
/// （暂停 / 继续、诊断开关、快捷键注册失败）。
struct PanelShortcutMenuContext: Equatable {
    /// 两个入口的差异全部落在数据上；缺省是状态栏右键菜单。
    var variant: PanelShortcutMenuVariant
    var productName: String
    var isMonitoringPaused: Bool
    /// 「收集诊断日志」/「停止收集诊断日志」，取自 `PreviewLocalization`。
    /// 只有状态栏变体用得到，面板变体不渲染诊断项。
    var diagnosticsTitle: String
    /// 历史快捷键注册失败时的提示文案；正常时为 `nil`。只有状态栏变体用得到。
    var hotKeyNotice: String?
    /// Stack 快捷键注册失败时的提示文案；正常时为 `nil`。只有状态栏变体用得到。
    var stackHotKeyNotice: String?

    init(variant: PanelShortcutMenuVariant = .statusItem,
         productName: String,
         isMonitoringPaused: Bool,
         diagnosticsTitle: String = "",
         hotKeyNotice: String? = nil,
         stackHotKeyNotice: String? = nil) {
        self.variant = variant
        self.productName = productName
        self.isMonitoringPaused = isMonitoringPaused
        self.diagnosticsTitle = diagnosticsTitle
        self.hotKeyNotice = hotKeyNotice
        self.stackHotKeyNotice = stackHotKeyNotice
    }
}

enum PanelShortcutMenuModel {
    /// 状态栏变体固定四组，组间一条 `NSMenuItem.separator()`：
    /// 动作 / 维护 / 应用 / 退出。
    ///
    /// 面板变体同样是四组：动作（只有新建文本）/ 维护（暂停子菜单）/ 应用 / 退出。
    /// 两个变体共用「应用」与「退出」两组，连标题、图标与快捷键都是同一份数据。
    static func groups(_ context: PanelShortcutMenuContext) -> [PanelShortcutMenuGroup] {
        [
            PanelShortcutMenuGroup(title: "动作", items: actionItems(context)),
            maintenanceGroup(context),
            PanelShortcutMenuGroup(title: "应用", items: applicationItems()),
            PanelShortcutMenuGroup(title: "退出", items: [quitItem(context)])
        ]
    }

    /// 面板变体「暂停」子菜单里可选的定时暂停分钟数（顺序即菜单顺序）。
    static let pauseWindowMinutes = [15, 30, 60, 180, 480]

    // MARK: 共用项

    private static func actionItems(_ context: PanelShortcutMenuContext) -> [PanelShortcutMenuItem] {
        var items: [PanelShortcutMenuItem] = []
        // 状态栏才需要「打开剪贴板」：点状态栏图标时面板可能没开；
        // 面板的 ⋯ 是从已经打开的面板上点出来的。
        if context.variant == .statusItem {
            items.append(PanelShortcutMenuItem(id: .openClipboard,
                                               title: "打开剪贴板",
                                               action: .togglePanel,
                                               symbol: "rectangle.on.rectangle"))
        }
        items.append(PanelShortcutMenuItem(id: .newText,
                                           title: "新建文本…",
                                           action: .newText,
                                           symbol: "square.and.pencil"))
        return items
    }

    private static func applicationItems() -> [PanelShortcutMenuItem] {
        [
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
        ]
    }

    private static func quitItem(_ context: PanelShortcutMenuContext) -> PanelShortcutMenuItem {
        PanelShortcutMenuItem(id: .quit,
                              title: "退出 \(context.productName)",
                              action: .confirmQuit,
                              symbol: "power")
    }

    // MARK: 维护组

    private static func maintenanceGroup(_ context: PanelShortcutMenuContext) -> PanelShortcutMenuGroup {
        switch context.variant {
        case .statusItem: return statusMaintenanceGroup(context)
        case .panelOverflow: return panelMaintenanceGroup(context)
        }
    }

    /// 状态栏：诊断开关 + 「暂停采集 / 继续采集」单项 + 注册失败提示（恒为 4 组）。
    private static func statusMaintenanceGroup(_ context: PanelShortcutMenuContext) -> PanelShortcutMenuGroup {
        var items = [
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
            items.append(PanelShortcutMenuItem(id: .hotKeyNotice,
                                               title: notice,
                                               action: nil,
                                               symbol: "exclamationmark.triangle"))
        }
        if let notice = context.stackHotKeyNotice {
            items.append(PanelShortcutMenuItem(id: .stackHotKeyNotice,
                                               title: notice,
                                               action: nil,
                                               symbol: "exclamationmark.triangle"))
        }
        return PanelShortcutMenuGroup(title: "维护", items: items)
    }

    /// 面板：只有一条带子菜单的「暂停 闪贴」。
    ///
    /// 子菜单里未暂停时是「暂停」+ 五档定时暂停；已暂停时只剩「继续 闪贴」。
    /// 父项标题保持「暂停 闪贴」（它是这个开关的名字），状态由子菜单表达。
    private static func panelMaintenanceGroup(_ context: PanelShortcutMenuContext) -> PanelShortcutMenuGroup {
        PanelShortcutMenuGroup(title: "维护", items: [
            PanelShortcutMenuItem(id: .pauseMonitoring,
                                  title: "暂停 \(context.productName)",
                                  action: nil,
                                  symbol: "pause.circle",
                                  submenu: pauseSubmenu(context))
        ])
    }

    private static func pauseSubmenu(_ context: PanelShortcutMenuContext) -> PanelShortcutMenuSubmenu {
        guard !context.isMonitoringPaused else {
            return PanelShortcutMenuSubmenu(items: [
                PanelShortcutMenuItem(id: .resumeMonitoring,
                                      title: "继续 \(context.productName)",
                                      action: .resumeMonitoring,
                                      symbol: "play.circle")
            ])
        }
        var items = [
            PanelShortcutMenuItem(id: .pauseIndefinitely,
                                  title: "暂停",
                                  action: .pauseIndefinitely,
                                  symbol: "pause.circle")
        ]
        items.append(contentsOf: pauseWindowMinutes.map { minutes in
            PanelShortcutMenuItem(id: .pauseForMinutes,
                                  title: pauseWindowTitle(minutes: minutes),
                                  action: .pauseForMinutes,
                                  symbol: "clock",
                                  minutes: minutes)
        })
        return PanelShortcutMenuSubmenu(items: items)
    }

    static func pauseWindowTitle(minutes: Int) -> String {
        minutes < 60 ? "暂停 \(minutes)分钟" : "暂停 \(minutes / 60)小时"
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
        // 带参数的动作用 `representedObject` 传载荷（目前只有「暂停 N 分钟」）。
        item.representedObject = entry.minutes
        if let submenu = entry.submenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for subentry in submenu.items { menu.addItem(makeItem(subentry, target: target)) }
            item.submenu = menu
        }
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
    /// 所以默认动作是取消。
    ///
    /// Esc 再显式挂到取消上：一个 `NSButton` 的 `keyEquivalent` 只能存一个键，
    /// 而 Return 由 `NSAlert` 的默认按钮机制负责，两者互不抢占。
    /// （`defaultButtonCell` 不要再手动改：赋值会把该按钮的 keyEquivalent 重置回
    /// `\r`，Esc 就丢了。）
    ///
    /// 「退出」按钮的样式：**系统强调色（压深到白字达标）实心填充 + 白字**，
    /// 圆角/尺寸/按钮顺序都还是系统那一套（`bezelColor` 只给现有圆角按钮换填充，
    /// 形状由 AppKit 画）。不要改回 `hasDestructiveAction`：警告样式会把它画成
    /// 「浅色底 + 红字」，1.0.30 实测浅色 3.55:1、深色 1.23:1，既不像系统按钮也读不清。
    /// 现在白字与填充实测 5.18:1（浅）/ 4.97:1（深），两种外观都清晰。
    static func makeAlert() -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = copy.title
        alert.informativeText = copy.message
        let cancel = alert.addButton(withTitle: copy.cancelTitle)   // .alertFirstButtonReturn
        let confirm = alert.addButton(withTitle: copy.confirmTitle) // .alertSecondButtonReturn
        styleConfirmButton(confirm)
        cancel.keyEquivalent = "\u{1b}"
        return alert
    }

    /// 把「退出」按钮画成强调色实心按钮，文字纯白。
    ///
    /// 只换颜色，不换控件：`bezelColor` 让 AppKit 用同一套圆角/内边距/尺寸重绘填充，
    /// 所以它和「取消」只差颜色。字号沿用按钮原来的字体（`attributedTitle` 里那一个，
    /// 取不到才退回系统字号），两个按钮的文字大小因此一致。
    ///
    /// 顺序有讲究：`hasDestructiveAction` 必须在 `bezelColor` **之前**清掉。
    /// 先上色再改这个标志会让 AppKit 把按钮的 cell 重新配一遍，填充色被丢掉
    /// （浅色外观尤其明显：按钮退回白底黑字）。
    static func styleConfirmButton(_ button: NSButton) {
        let title = button.title
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white]
        if let font = button.attributedTitle.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            attributes[.font] = font
        } else {
            attributes[.font] = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        }
        button.hasDestructiveAction = false
        button.bezelColor = accessibleAccentFill(for: button.window?.effectiveAppearance)
        button.attributedTitle = NSAttributedString(string: title, attributes: attributes)
    }

    /// 白字在按钮填充上要够清楚：系统强调色本身（浅色 `#007AFF`）与白字只有
    /// **4.02:1**，AppKit 渲染出的渐变按钮实测约 4.4:1，两者都低于 4.5:1 的
    /// 无障碍下限。这里从强调色出发逐步压深，到达标为止（目标 4.8:1，给按钮顶部
    /// 那一点浅色渐变留余量），色相仍是用户选的系统强调色。
    static let confirmFillContrastTarget: CGFloat = 4.8

    /// 按目标外观把系统强调色解析成具体颜色，再按 2% 一档压深到目标值；浅色与深色
    /// 各走同一段逻辑（强调色本身两种外观不同，达标所需的压深比例也不同）。
    static func accessibleAccentFill(for appearance: NSAppearance? = nil) -> NSColor {
        var accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.controlAccentColor
        if let appearance {
            // 强调色是按外观解析的动态色：在目标外观里取一次，压深结果才对。
            appearance.performAsCurrentDrawingAppearance {
                accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.controlAccentColor
            }
        }
        var fraction: CGFloat = 0
        while fraction <= 0.8 {
            let candidate = accent.blended(withFraction: fraction, of: .black) ?? accent
            if contrastRatio(candidate, .white) >= confirmFillContrastTarget { return candidate }
            fraction += 0.02
        }
        return .black
    }

    /// WCAG 2.1 相对亮度与对比度（只用来挑一个「白字够清楚」的填充色）。
    static func relativeLuminance(_ color: NSColor) -> CGFloat {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
    }

    static func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat {
        let a = relativeLuminance(first)
        let b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
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
