import AppKit

/// 快捷菜单的离屏回归。
///
/// 断言对象全部是**生产代码**：`PanelShortcutMenuModel` 的分组数据、
/// `PanelShortcutMenuBuilder` 真正要弹出的 `NSMenu`、以及
/// `PanelShortcutMenuQuitConfirmation`（响应注入，不会真的结束进程）。
/// 渲染用的是同一份模型 + 同一套 SF Symbol 图标，因此截图里的行、图标、
/// 快捷键和分组分隔线就是菜单里会出现的内容。
///
/// 两个入口（状态栏右键 `.statusItem` / 面板工具栏 ⋯ `.panelOverflow`）走的是
/// 同一台模型与同一个构建器，这里对两个变体分别断言分组、项数、图标、顺序与
/// 动作接线；面板变体另外断言暂停子菜单与退出二次确认被调用。
@MainActor
@main struct PanelShortcutMenuHarness {
    static var checks = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static let productName = "闪贴"

    static var context: PanelShortcutMenuContext {
        PanelShortcutMenuContext(productName: productName,
                                 isMonitoringPaused: false,
                                 diagnosticsTitle: "收集诊断日志")
    }

    /// 面板工具栏 ⋯ 的上下文：没有诊断标题、没有注册失败提示。
    static var panelContext: PanelShortcutMenuContext {
        PanelShortcutMenuContext(variant: .panelOverflow,
                                 productName: productName,
                                 isMonitoringPaused: false)
    }

    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)

        groupingChecks()
        iconChecks()
        dynamicStateChecks()
        noticeChecks()
        menuChecks()
        notificationChecks()
        quitConfirmationChecks()

        panelGroupingChecks()
        panelSubmenuChecks()
        panelMenuChecks()
        dispatchChecks()

        let renders = renderIfRequested()
        let payload: [String: Any] = [
            "passed": true,
            "count": checks,
            "renders": renders,
            "menu": dump(PanelShortcutMenuModel.groups(context)),
            "panelMenu": dump(PanelShortcutMenuModel.groups(panelContext)),
            "boundary": "生产 PanelShortcutMenuModel / PanelShortcutMenuBuilder / PanelShortcutMenuQuitConfirmation 与真实 NSMenu、真实 SF Symbol 图标；两个变体分别断言；退出确认注入 modal 响应，没有真的终止进程。"
        ]
        let json = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
    }

    static func dump(_ groups: [PanelShortcutMenuGroup]) -> [[String: Any]] {
        groups.map { group in
            ["group": group.title, "items": group.items.map(dumpItem)]
        }
    }

    static func dumpItem(_ item: PanelShortcutMenuItem) -> [String: Any] {
        var value: [String: Any] = [
            "id": item.id.rawValue, "title": item.title, "symbol": item.symbol,
            "action": item.action?.rawValue ?? "none", "key": item.keyEquivalent
        ]
        if let minutes = item.minutes { value["minutes"] = minutes }
        if let submenu = item.submenu { value["submenu"] = submenu.items.map(dumpItem) }
        return value
    }

    // MARK: - 分组与顺序

    static func groupingChecks() {
        let groups = PanelShortcutMenuModel.groups(context)
        check(groups.count == 4, "菜单必须是 4 组，实际 \(groups.count)")
        check(groups.map(\.title) == ["动作", "应用", "维护", "退出"],
              "分组顺序变了：\(groups.map(\.title))")
        check(groups[0].items.map(\.id) == [.openClipboard, .newText], "动作组内容不对")
        check(groups[1].items.map(\.id) == [.settings, .checkForUpdates, .helpAndAbout],
              "应用组必须是 设置 / 检查更新 / 帮助与关于，实际 \(groups[1].items.map(\.id))")
        check(groups[2].items.map(\.id) == [.diagnostics, .pauseMonitoring], "维护组内容不对")
        check(groups[3].items.map(\.id) == [.quit], "退出组只放一项")

        check(groups[0].items.map(\.title) == ["打开剪贴板", "新建文本…"], "动作组标题不对")
        check(groups[1].items.map(\.title) == ["设置…", "检查更新", "帮助与关于"], "应用组标题不对")
        check(groups[2].items.map(\.title) == ["收集诊断日志", "暂停采集"], "维护组标题不对")
        check(groups[3].items[0].title == "退出 \(productName)",
              "退出项标题应为「退出 \(productName)」，实际 \(groups[3].items[0].title)")

        let settings = groups[1].items[0]
        check(settings.keyEquivalent == ",", "设置项应有 ⌘, 快捷键")
        check(settings.modifiers == [.command], "设置的修饰键必须是 command")
        check(settings.keyEquivalentDisplay == "\u{2318},", "设置项的快捷键应显示为 ⌘,")

        // 检查更新 / 帮助与关于 / 退出的动作接线
        check(groups[1].items[1].action == .checkForUpdates, "检查更新走的是 checkForUpdates:")
        check(groups[1].items[2].action == .openAbout, "帮助与关于走的是 openAbout:（只发通知）")
        check(groups[3].items[0].action == .confirmQuit, "退出项必须走 confirmQuit: 确认路径")
        check(groups.flatMap(\.items).allSatisfy { $0.action != nil }, "常规菜单项都应有动作")
        check(groups.flatMap(\.items).allSatisfy { $0.isEnabled }, "常规菜单项都应是可用状态")
    }

    static func iconChecks() {
        let groups = PanelShortcutMenuModel.groups(context)
        let icons = Dictionary(uniqueKeysWithValues: groups.flatMap(\.items).map { ($0.id, $0.symbol) })
        check(icons[.openClipboard] == "rectangle.on.rectangle", "打开剪贴板图标不对")
        check(icons[.newText] == "square.and.pencil", "新建文本图标不对")
        check(icons[.settings] == "gearshape", "设置图标不对")
        check(icons[.checkForUpdates] == "arrow.triangle.2.circlepath", "检查更新图标不对")
        check(icons[.helpAndAbout] == "info.circle", "帮助与关于图标不对")
        check(icons[.diagnostics] == "stethoscope", "收集诊断日志图标不对")
        check(icons[.pauseMonitoring] == "pause.circle", "暂停采集图标不对")
        check(icons[.quit] == "power", "退出图标不对")

        for item in groups.flatMap(\.items) {
            guard let image = PanelShortcutMenuBuilder.icon(item.symbol) else {
                preconditionFailure("SF Symbol「\(item.symbol)」在本机解析不出来（\(item.id)）")
            }
            check(image.size == NSSize(width: PanelShortcutMenuLayout.iconSide,
                                      height: PanelShortcutMenuLayout.iconSide),
                  "\(item.id) 图标尺寸不是 16×16：\(image.size)")
            check(image.isTemplate, "\(item.id) 图标必须是模板图，深色外观才能反色")
        }
    }

    static func dynamicStateChecks() {
        let paused = PanelShortcutMenuContext(productName: productName,
                                              isMonitoringPaused: true,
                                              diagnosticsTitle: "停止收集诊断日志")
        let groups = PanelShortcutMenuModel.groups(paused)
        check(groups[2].items[1].title == "继续采集", "暂停中这一项应变成「继续采集」")
        check(groups[2].items[1].symbol == "play.circle", "暂停中图标应变成 play.circle")
        check(groups[2].items[0].title == "停止收集诊断日志", "诊断项标题应跟随诊断状态")
        check(groups.count == 4, "状态变化不改变分组数量")
    }

    static func noticeChecks() {
        var context = context
        context.hotKeyNotice = "历史快捷键无法注册"
        context.stackHotKeyNotice = "闪贴 Stack 快捷键无法注册"
        let groups = PanelShortcutMenuModel.groups(context)
        check(groups.count == 4, "注册失败的提示不能改变分组数量")
        check(groups[2].items.map(\.id) == [.diagnostics, .pauseMonitoring, .hotKeyNotice, .stackHotKeyNotice],
              "提示行应追加在「维护」组尾部，实际 \(groups[2].items.map(\.id))")
        let notices = groups[2].items.filter { $0.action == nil }
        check(notices.count == 2, "提示行没有动作")
        check(notices.allSatisfy { !$0.isEnabled }, "提示行必须是置灰状态")
        check(notices.allSatisfy { !$0.symbol.isEmpty }, "提示行同样带图标")
    }

    // MARK: - 真实 NSMenu

    final class Target: NSObject {
        var invoked: [String] = []
        @objc func probe(_ sender: Any?) { invoked.append("probe") }
    }

    static func menuChecks() {
        let target = Target()
        let menu = PanelShortcutMenuBuilder.makeMenu(context, target: target)
        check(!menu.autoenablesItems, "菜单启用状态必须由模型决定，不能交给自动验证")
        check(menu.items.count == 11, "4 组 8 项 + 3 条分隔线 = 11，实际 \(menu.items.count)")

        let separators = menu.items.enumerated().filter { $0.element.isSeparatorItem }.map(\.offset)
        check(separators == [2, 6, 9], "分隔线位置不对：\(separators)")

        for (index, item) in menu.items.enumerated() where !item.isSeparatorItem {
            guard let image = item.image else {
                preconditionFailure("第 \(index) 项「\(item.title)」缺图标")
            }
            check(image.size == NSSize(width: 16, height: 16) && image.isTemplate,
                  "第 \(index) 项「\(item.title)」图标不是 16×16 模板图")
            check(item.target === target, "第 \(index) 项「\(item.title)」没挂上 target")
            check(item.isEnabled, "第 \(index) 项「\(item.title)」应可用")
        }

        let titles = menu.items.map { $0.isSeparatorItem ? "---" : $0.title }
        check(titles == ["打开剪贴板", "新建文本…", "---",
                         "设置…", "检查更新", "帮助与关于", "---",
                         "收集诊断日志", "暂停采集", "---",
                         "退出 \(productName)"],
              "菜单顺序不对：\(titles)")

        check(menu.items[3].keyEquivalent == "," && menu.items[3].keyEquivalentModifierMask == [.command],
              "NSMenu 里设置项的快捷键应是 ⌘,")
        let checkUpdate = menu.items.first { $0.action == PanelShortcutMenuAction.checkForUpdates.selector }
        check(checkUpdate != nil, "菜单里找不到检查更新")
        check(menu.items.first { $0.action == PanelShortcutMenuAction.openAbout.selector } != nil,
              "菜单里找不到帮助与关于")
        let quit = menu.items.first { $0.action == PanelShortcutMenuAction.confirmQuit.selector }
        check(quit != nil, "菜单里找不到退出项")
        guard let quit else { return }
        check(quit.title == "退出 \(productName)", "退出项标题不对")
        check(quit.action != PanelShortcutMenuAction.togglePanel.selector, "退出项不能直连其它动作")
        // 退出项只能落在确认路径上：既不是 NSApp.terminate 的直连动作，
        // 也不是 quit:（应用菜单里那个直接终止的选择器）。
        check(quit.action == Selector(("confirmQuit:")), "退出项必须指向 confirmQuit:")
        check(quit.action != Selector(("quit:")), "退出项不能复用未确认的 quit:")

        // 每次右键都重建，不共享状态。
        let rebuilt = PanelShortcutMenuBuilder.makeMenu(context, target: target)
        check(rebuilt.items.map(\.title) == menu.items.map(\.title), "菜单重建后内容不一致")
        check(rebuilt.items.first?.image !== menu.items.first?.image, "每次重建都应拿到新的 NSMenu")

        // 置灰的提示行在真实 NSMenu 里也是灰的。
        var withNotice = context
        withNotice.hotKeyNotice = "历史快捷键无法注册"
        let noticeMenu = PanelShortcutMenuBuilder.makeMenu(withNotice, target: target)
        let notice = noticeMenu.items.first { $0.title == "历史快捷键无法注册" }
        check(notice != nil, "提示行没进 NSMenu")
        check(notice?.isEnabled == false, "提示行在 NSMenu 里必须置灰")
        check(notice?.action == nil, "提示行没有动作")
        check(notice?.image != nil, "提示行也要有图标")
        check(menu.items.filter { $0.image == nil && !$0.isSeparatorItem }.isEmpty,
              "所有非分隔线菜单项都必须有 image")
    }

    // MARK: - 面板变体（工具栏 ⋯）

    static func panelGroupingChecks() {
        let groups = PanelShortcutMenuModel.groups(panelContext)
        check(groups.count == 4, "面板菜单必须也是 4 组，实际 \(groups.count)")
        check(groups.map(\.title) == ["动作", "应用", "维护", "退出"],
              "面板菜单分组顺序变了：\(groups.map(\.title))")
        check(groups[0].items.map(\.id) == [.newText], "面板动作组只放新建文本")
        check(groups[0].items.map(\.title) == ["新建文本…"], "面板动作组标题不对")
        check(groups[1].items.map(\.id) == [.settings, .checkForUpdates, .helpAndAbout],
              "面板应用组必须是 设置 / 检查更新 / 帮助与关于，实际 \(groups[1].items.map(\.id))")
        check(groups[1].items.map(\.title) == ["设置…", "检查更新", "帮助与关于"],
              "面板应用组标题不对：\(groups[1].items.map(\.title))")
        check(groups[2].items.map(\.id) == [.pauseMonitoring], "面板维护组只有暂停父项")
        check(groups[2].items[0].title == "暂停 \(productName)",
              "面板暂停父项标题应为「暂停 \(productName)」，实际 \(groups[2].items[0].title)")
        check(groups[3].items.map(\.id) == [.quit], "面板退出组只放一项")
        check(groups[3].items[0].title == "退出 \(productName)", "面板退出项标题不对")

        // 面板已经开着：不再出现「打开剪贴板」；诊断开关与注册失败提示也是状态栏专属。
        let ids = groups.flatMap(\.items).map(\.id)
        check(!ids.contains(.openClipboard), "面板变体不该出现「打开剪贴板」")
        check(!ids.contains(.diagnostics), "面板变体不该出现诊断开关")
        check(!ids.contains(.hotKeyNotice) && !ids.contains(.stackHotKeyNotice),
              "面板变体不该出现状态栏的注册失败提示")

        // 两个变体共用的分组 / 项必须逐字一致（同一份数据，不是复制出来的第二份）。
        let statusGroups = PanelShortcutMenuModel.groups(context)
        check(groups[1] == statusGroups[1], "两个变体的「应用」组必须完全一致")
        check(groups[3] == statusGroups[3], "两个变体的「退出」组必须完全一致")
        check(groups[0].items.last == statusGroups[0].items.last,
              "两个变体的「新建文本…」必须完全一致")

        // 图标：共用项同款 SF Symbol，面板特有项也用 SF Symbol。
        let symbols = Dictionary(uniqueKeysWithValues: groups.flatMap(\.items).map { ($0.id, $0.symbol) })
        check(symbols[.newText] == "square.and.pencil", "面板新建文本图标与状态栏不一致")
        check(symbols[.settings] == "gearshape", "面板设置图标与状态栏不一致")
        check(symbols[.checkForUpdates] == "arrow.triangle.2.circlepath", "面板检查更新图标与状态栏不一致")
        check(symbols[.helpAndAbout] == "info.circle", "面板帮助与关于图标与状态栏不一致")
        check(symbols[.pauseMonitoring] == "pause.circle", "面板暂停父项图标不对")
        check(symbols[.quit] == "power", "面板退出图标与状态栏不一致")

        // 同尺寸、同模板色：两个变体一视同仁。
        for item in groups.flatMap(\.items) {
            guard let image = PanelShortcutMenuBuilder.icon(item.symbol) else {
                preconditionFailure("面板变体 SF Symbol「\(item.symbol)」解析不出来（\(item.id)）")
            }
            check(image.size == NSSize(width: PanelShortcutMenuLayout.iconSide,
                                      height: PanelShortcutMenuLayout.iconSide),
                  "面板变体 \(item.id) 图标尺寸不是 16×16：\(image.size)")
            check(image.isTemplate, "面板变体 \(item.id) 图标必须是模板图")
        }
    }

    static func panelSubmenuChecks() {
        let groups = PanelShortcutMenuModel.groups(panelContext)
        guard let submenu = groups[2].items[0].submenu else {
            preconditionFailure("面板「暂停」项必须有子菜单")
        }
        check(groups[2].items[0].action == nil, "带子菜单的父项本体不执行动作")
        check(groups[2].items[0].isEnabled, "带子菜单的父项必须是可用状态")
        check(submenu.items.map(\.id) == [.pauseIndefinitely, .pauseForMinutes, .pauseForMinutes,
                                          .pauseForMinutes, .pauseForMinutes, .pauseForMinutes],
              "暂停子菜单项不对：\(submenu.items.map(\.id))")
        check(submenu.items.map(\.title) == ["暂停", "暂停 15分钟", "暂停 30分钟",
                                             "暂停 1小时", "暂停 3小时", "暂停 8小时"],
              "暂停子菜单标题不对：\(submenu.items.map(\.title))")
        check(submenu.items.dropFirst().map(\.minutes) == [15, 30, 60, 180, 480],
              "暂停档位必须是 15/30/60/180/480 分钟：\(submenu.items.dropFirst().map(\.minutes))")
        check(submenu.items.first?.minutes == nil, "「暂停」不限时，minutes 必须为空")
        check(submenu.items.allSatisfy { $0.action != nil && $0.isEnabled },
              "暂停子菜单每项都要有动作且可用")
        check(submenu.items.allSatisfy { $0.symbol == "pause.circle" || $0.symbol == "clock" },
              "暂停子菜单图标不对：\(submenu.items.map(\.symbol))")
        check(PanelShortcutMenuModel.pauseWindowMinutes == [15, 30, 60, 180, 480],
              "暂停档位常量被改动了")

        // 已暂停：子菜单只剩「继续」，父项标题保持「暂停 闪贴」。
        var paused = panelContext
        paused.isMonitoringPaused = true
        let pausedGroups = PanelShortcutMenuModel.groups(paused)
        check(pausedGroups.count == 4, "暂停状态不改变面板分组数量")
        check(pausedGroups[2].items[0].title == "暂停 \(productName)", "暂停中父项标题不变")
        guard let pausedSubmenu = pausedGroups[2].items[0].submenu else {
            preconditionFailure("暂停中也要保留「暂停 \(productName)」父项的子菜单")
        }
        check(pausedSubmenu.items.map(\.id) == [.resumeMonitoring], "暂停中子菜单只保留「继续」")
        check(pausedSubmenu.items.map(\.title) == ["继续 \(productName)"], "暂停中子菜单标题不对")
        check(pausedSubmenu.items[0].symbol == "play.circle", "暂停中图标应为 play.circle")
        check(pausedGroups[0].items.map(\.id) == [.newText], "暂停状态不影响动作组")
    }

    static func panelMenuChecks() {
        let target = DispatchTarget()
        let menu = PanelShortcutMenuBuilder.makeMenu(panelContext, target: target)
        check(!menu.autoenablesItems, "面板菜单启用状态也必须由模型决定")
        check(menu.items.count == 9, "面板菜单 4 组 6 项 + 3 条分隔线 = 9，实际 \(menu.items.count)")

        let separators = menu.items.enumerated().filter { $0.element.isSeparatorItem }.map(\.offset)
        check(separators == [1, 5, 7], "面板菜单分隔线位置不对：\(separators)")

        let titles = menu.items.map { $0.isSeparatorItem ? "---" : $0.title }
        check(titles == ["新建文本…", "---", "设置…", "检查更新", "帮助与关于", "---",
                         "暂停 \(productName)", "---", "退出 \(productName)"],
              "面板菜单顺序不对：\(titles)")
        check(!titles.contains("打开剪贴板"), "面板菜单不该有「打开剪贴板」")

        for (index, item) in menu.items.enumerated() where !item.isSeparatorItem {
            guard let image = item.image else {
                preconditionFailure("面板菜单第 \(index) 项「\(item.title)」缺图标")
            }
            check(image.size == NSSize(width: 16, height: 16) && image.isTemplate,
                  "面板菜单第 \(index) 项「\(item.title)」图标不是 16×16 模板图")
            check(item.target === target, "面板菜单第 \(index) 项「\(item.title)」没挂上 target")
            check(item.isEnabled, "面板菜单第 \(index) 项「\(item.title)」应可用")
        }

        // 子菜单是真实的 NSMenu，图标 / target 与顶层一致。
        guard let submenu = menu.items[6].submenu else {
            preconditionFailure("面板菜单的「暂停」项没有子菜单")
        }
        check(!submenu.autoenablesItems, "子菜单启用状态也要由模型决定")
        check(submenu.items.count == 6, "暂停子菜单应有 6 项，实际 \(submenu.items.count)")
        check(submenu.items.map(\.title) == ["暂停", "暂停 15分钟", "暂停 30分钟",
                                             "暂停 1小时", "暂停 3小时", "暂停 8小时"],
              "子菜单顺序不对：\(submenu.items.map(\.title))")
        for (index, item) in submenu.items.enumerated() {
            guard let image = item.image else { preconditionFailure("子菜单第 \(index) 项缺图标") }
            check(image.size == NSSize(width: 16, height: 16) && image.isTemplate,
                  "子菜单第 \(index) 项图标不是 16×16 模板图")
            check(item.target === target, "子菜单第 \(index) 项没挂上 target")
            check(item.isEnabled, "子菜单第 \(index) 项应可用")
        }
        check(submenu.items.dropFirst().map { $0.representedObject as? Int } == [15, 30, 60, 180, 480],
              "子菜单的分钟数必须写进 representedObject")

        // 每次弹出都重建。
        let rebuilt = PanelShortcutMenuBuilder.makeMenu(panelContext, target: target)
        check(rebuilt.items.map(\.title) == menu.items.map(\.title), "面板菜单重建后内容不一致")
    }

    // MARK: - 动作投递（真实 sendAction）

    @MainActor
    final class DispatchTarget: NSObject {
        var invoked: [String] = []
        var presentedAlerts = 0
        var terminateCount = 0
        var lastMinutes: Int?

        /// 退出：与 AppMain.confirmQuit 一样的路径——先弹二次确认，
        /// 这里注入「取消」，所以既不会卡在模态也不会真的终止进程。
        @objc func confirmQuit(_ sender: Any?) {
            invoked.append("confirmQuit")
            PanelShortcutMenuQuitConfirmation.confirm(
                runAlert: { _ in
                    self.presentedAlerts += 1
                    return .alertFirstButtonReturn
                },
                terminate: { self.terminateCount += 1 })
        }

        @objc func pauseForMinutes(_ sender: NSMenuItem) {
            invoked.append("pauseForMinutes")
            lastMinutes = sender.representedObject as? Int
        }
        @objc func pauseIndefinitely(_ sender: Any?) { invoked.append("pauseIndefinitely") }
        @objc func resumeMonitoring(_ sender: Any?) { invoked.append("resumeMonitoring") }
        @objc func settings(_ sender: Any?) { invoked.append("settings") }
        @objc func newText(_ sender: Any?) { invoked.append("newText") }
        @objc func checkForUpdates(_ sender: Any?) { invoked.append("checkForUpdates") }
        @objc func openAbout(_ sender: Any?) { invoked.append("openAbout") }
    }

    static func dispatch(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return false }
        return NSApp.sendAction(action, to: item.target, from: item)
    }

    static func dispatchChecks() {
        let target = DispatchTarget()
        let menu = PanelShortcutMenuBuilder.makeMenu(panelContext, target: target)
        func item(_ action: PanelShortcutMenuAction) -> NSMenuItem {
            guard let found = menu.items.first(where: { $0.action == action.selector }) else {
                preconditionFailure("面板菜单里找不到 \(action.rawValue)")
            }
            return found
        }

        // 退出：面板菜单的退出项必须落到 confirmQuit:（二次确认），取消后不终止进程。
        let quit = item(.confirmQuit)
        check(quit.action != Selector(("quit:")), "面板退出项不能直连未确认的 quit:")
        check(dispatch(quit), "面板退出项的动作没投递出去")
        check(target.invoked == ["confirmQuit"], "退出项必须调用 confirmQuit:，实际 \(target.invoked)")
        check(target.presentedAlerts == 1, "退出前必须弹出一次确认弹窗，实际 \(target.presentedAlerts)")
        check(target.terminateCount == 0, "取消后不能终止进程")

        // 检查更新 / 帮助与关于：面板菜单与状态栏走同一批 selector。
        for action in [PanelShortcutMenuAction.checkForUpdates, .openAbout] {
            check(dispatch(item(action)), "面板 \(action.rawValue) 没投递出去")
        }
        check(target.invoked.contains("checkForUpdates"), "面板「检查更新」没接到 checkForUpdates:")
        check(target.invoked.contains("openAbout"), "面板「帮助与关于」没接到 openAbout:（通知路径）")

        // 定时暂停：representedObject 带着分钟数。
        guard let timed = menu.items[6].submenu?.items.first(where: { $0.title == "暂停 30分钟" }) else {
            preconditionFailure("找不到「暂停 30分钟」")
        }
        check(dispatch(timed), "定时暂停项的动作没投递出去")
        check(target.lastMinutes == 30,
              "定时暂停没有把 30 分钟带过去，实际 \(String(describing: target.lastMinutes))")

        // 状态栏变体的退出项同样是 confirmQuit:（两个入口同一套接线）。
        let statusMenu = PanelShortcutMenuBuilder.makeMenu(context, target: target)
        guard let statusQuit = statusMenu.items.first(where: {
            $0.action == PanelShortcutMenuAction.confirmQuit.selector
        }) else {
            preconditionFailure("状态栏菜单里找不到退出项")
        }
        check(statusQuit.action == Selector(("confirmQuit:")), "状态栏退出项必须走 confirmQuit:")
        check(dispatch(statusQuit), "状态栏退出项的动作没投递出去")
        check(target.terminateCount == 0, "状态栏退出同样先确认，取消后不终止")
    }

    // MARK: - 通知

    static func notificationChecks() {
        check(Notification.Name.blinkClipOpenAbout.rawValue == "blinkclip.openAbout",
              "通知名被改动了：\(Notification.Name.blinkClipOpenAbout.rawValue)")
        // 没有观察者时 post 不能有副作用（也不崩）。
        NotificationCenter.default.post(name: .blinkClipOpenAbout, object: nil)
        check(true, "无观察者时 post 通过")

        var received = 0
        let token = NotificationCenter.default.addObserver(forName: .blinkClipOpenAbout,
                                                           object: nil, queue: nil) { _ in received += 1 }
        NotificationCenter.default.post(name: .blinkClipOpenAbout, object: nil)
        NotificationCenter.default.removeObserver(token)
        check(received == 1, "观察者应收到一次 blinkClipOpenAbout，实际 \(received)")
    }

    // MARK: - 退出二次确认

    static func quitConfirmationChecks() {
        let copy = PanelShortcutMenuQuitConfirmation.copy
        check(copy.title == "要退出闪贴吗？", "确认弹窗标题不对：\(copy.title)")
        check(copy.message == "退出后将停止剪贴板记录与快捷键。", "确认弹窗正文不对：\(copy.message)")

        let alert = PanelShortcutMenuQuitConfirmation.makeAlert()
        check(alert.messageText == copy.title, "alert 标题没接上")
        check(alert.informativeText == copy.message, "alert 正文没接上")
        check(alert.buttons.map(\.title) == [copy.cancelTitle, copy.confirmTitle],
              "按钮顺序必须是 取消 / 退出，实际 \(alert.buttons.map(\.title))")
        // NSAlert 的第一个按钮就是默认按钮：取消在前 ⇒ Return 落在取消上。
        check(alert.buttons.first?.title == copy.cancelTitle, "默认按钮（第一个）必须是「取消」")
        // Esc 也落在取消上（一个按钮只能存一个键，Return 由默认按钮机制负责）。
        check(alert.buttons[0].keyEquivalent == "\u{1b}", "Esc 必须取消")
        check(alert.buttons[1].keyEquivalent != "\u{1b}", "Esc 不能落到「退出」上")
        // 真的能接住 Esc：alert 窗口自己处理这个按键。
        if let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                         timestamp: 0, windowNumber: alert.window.windowNumber,
                                         context: nil, characters: "\u{1b}",
                                         charactersIgnoringModifiers: "\u{1b}",
                                         isARepeat: false, keyCode: 53) {
            check(alert.window.performKeyEquivalent(with: escape), "alert 必须接住 Esc（落到取消上）")
        }
        // 红色 destructive 只修饰「退出」。
        check(alert.buttons[1].hasDestructiveAction, "「退出」应是 destructive")
        check(!alert.buttons[0].hasDestructiveAction, "「取消」不能是 destructive")

        // 响应映射
        check(!PanelShortcutMenuQuitConfirmation.shouldTerminate(.alertFirstButtonReturn),
              "取消（alertFirstButtonReturn）不能退出")
        check(!PanelShortcutMenuQuitConfirmation.shouldTerminate(.abort), "关窗不能退出")
        check(!PanelShortcutMenuQuitConfirmation.shouldTerminate(.cancel), "取消不能退出")
        check(PanelShortcutMenuQuitConfirmation.shouldTerminate(.alertSecondButtonReturn),
              "确认按钮才放行")

        // 注入响应：取消 → 不调用 terminate；确认 → 才调用。
        var terminated = 0
        var presented: NSAlert?
        let cancelled = PanelShortcutMenuQuitConfirmation.confirm(
            runAlert: { alert in presented = alert; return .alertFirstButtonReturn },
            terminate: { terminated += 1 })
        check(!cancelled, "取消后 confirm 必须返回 false")
        check(terminated == 0, "取消后不能终止进程")
        check(presented?.messageText == copy.title, "弹出的 alert 标题不对")
        check(presented?.buttons.map(\.title) == [copy.cancelTitle, copy.confirmTitle],
              "弹出的 alert 按钮不对")

        let escaped = PanelShortcutMenuQuitConfirmation.confirm(
            runAlert: { _ in .abort }, terminate: { terminated += 1 })
        check(!escaped && terminated == 0, "Esc / 关窗后不能终止进程")

        let accepted = PanelShortcutMenuQuitConfirmation.confirm(
            runAlert: { _ in .alertSecondButtonReturn }, terminate: { terminated += 1 })
        check(accepted, "确认后 confirm 必须返回 true")
        check(terminated == 1, "确认后必须恰好终止一次，实际 \(terminated)")
    }

    // MARK: - 渲染

    static func renderIfRequested() -> [String] {
        guard let index = CommandLine.arguments.firstIndex(of: "--render"),
              index + 1 < CommandLine.arguments.count else { return [] }
        let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [String] = []
        // 两个变体各自出图：状态栏右键菜单与面板工具栏 ⋯ 菜单。
        let variants: [(name: String, groups: [PanelShortcutMenuGroup])] = [
            ("panel-menu", PanelShortcutMenuModel.groups(context)),
            ("panel-overflow-menu", PanelShortcutMenuModel.groups(panelContext))
        ]
        for variant in variants {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                guard let rep = PanelShortcutMenuSurfaceView.render(groups: variant.groups,
                                                                    appearance: appearance) else {
                    continue
                }
                let url = directory.appendingPathComponent("\(variant.name)-\(suffix)-expanded.png")
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: url)
                    written.append(url.path)
                }
            }
        }
        // 面板 ⋯ 的「暂停 闪贴」子菜单单独出图：它只存在于面板变体。
        if let submenu = PanelShortcutMenuModel.groups(panelContext)[2].items[0].submenu {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                guard let rep = PanelShortcutMenuSurfaceView.render(
                    groups: [PanelShortcutMenuGroup(title: "暂停子菜单", items: submenu.items)],
                    appearance: appearance) else { continue }
                let url = directory.appendingPathComponent("panel-overflow-pause-\(suffix)-expanded.png")
                if let data = rep.representation(using: .png, properties: [:]) {
                    try? data.write(to: url)
                    written.append(url.path)
                }
            }
        }
        return written
    }
}
