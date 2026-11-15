import AppKit

/// 底部快捷菜单的离屏回归。
///
/// 断言对象全部是**生产代码**：`PanelShortcutMenuModel` 的分组数据、
/// `PanelShortcutMenuBuilder` 真正要弹出的 `NSMenu`、以及
/// `PanelShortcutMenuQuitConfirmation`（响应注入，不会真的结束进程）。
/// 渲染用的是同一份模型 + 同一套 SF Symbol 图标，因此截图里的行、图标、
/// 快捷键和分组分隔线就是菜单里会出现的内容。
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

        let renders = renderIfRequested()
        let payload: [String: Any] = [
            "passed": true,
            "count": checks,
            "renders": renders,
            "menu": PanelShortcutMenuModel.groups(context).map { group in
                ["group": group.title, "items": group.items.map { item in
                    ["id": item.id.rawValue, "title": item.title, "symbol": item.symbol,
                     "action": item.action?.rawValue ?? "none", "key": item.keyEquivalent]
                }]
            },
            "boundary": "生产 PanelShortcutMenuModel / PanelShortcutMenuBuilder / PanelShortcutMenuQuitConfirmation 与真实 NSMenu、真实 SF Symbol 图标；退出确认注入 modal 响应，没有真的终止进程。"
        ]
        let json = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: json, as: UTF8.self))
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
        let groups = PanelShortcutMenuModel.groups(context)
        var written: [String] = []
        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            guard let rep = PanelShortcutMenuSurfaceView.render(groups: groups, appearance: appearance) else {
                continue
            }
            let url = directory.appendingPathComponent("panel-menu-\(suffix)-expanded.png")
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: url)
                written.append(url.path)
            }
        }
        return written
    }
}
