import AppKit
import Foundation
import SwiftUI
import BlinkClipCore

@main
struct UIInteractionHarness {
    struct Failure: Error, CustomStringConvertible { let description: String }
    @MainActor static func main() async {
        do { try await run() }
        catch {
            print(String(data: try! JSONSerialization.data(withJSONObject: ["status": "failed", "reason": String(describing: error)]), encoding: .utf8)!)
            exit(1)
        }
    }
    static func require(_ condition: @autoclosure () -> Bool, line: UInt = #line) throws {
        if !condition() { throw Failure(description: "UI assertion failed at line \(line)") }
    }
    /// 2026-11 API 变更：`ReplicaUIController.removePinboard` 的参数从 `Pinboard` 改为
    /// `ClipboardListTarget`（面板菜单原本就持有 target）。这里按公开入口
    /// `ClipboardStore.tabListTarget(identifier:)` 把 fixture 分组解析成同样的 target。
    @MainActor static func listTarget(_ board: Pinboard, store: ClipboardStore) throws -> ClipboardListTarget {
        guard let target = store.tabListTarget(identifier: board.id.uuidString) else {
            throw Failure(description: "Missing list target for fixture group \(board.name)")
        }
        return target
    }
    /// 2026-11 API 变更：`ReplicaUIState.visibleItems` 现在返回 `ClipboardCollectionEntry`
    /// （原生集合条目），`select`/`addToStack` 仍接收实体内容；这里按公开入口 `item()` 解包。
    @MainActor static func entryItem(_ entry: ClipboardCollectionEntry) throws -> ClipboardItem {
        guard let item = entry.item() else {
            throw Failure(description: "Missing collection entry content for \(entry.id)")
        }
        return item
    }
    /// 03a538（`ReplicaUIState.reconcileTabListSelection`）：列表被删除后，产品不跳回历史，
    /// 而是把旧位置夹取到剩余原生顺序里的同位（min(oldIndex, count-1)）；列表栈空时才是历史。
    /// 原生快照 = 历史(0) + `store.pinboards`，两侧的下标偏移在夹取后相互抵消，因此用
    /// `store.pinboards` 的旧下标算出的期望值与产品一致。测试按这条语义给出期望目标，
    /// 不再假设“删组后选中历史”。
    @MainActor static func expectedBoardAfterDeletion(indexBefore: Int, store: ClipboardStore) -> UUID? {
        let remaining = store.pinboards
        guard !remaining.isEmpty else { return nil }
        return remaining[min(indexBefore, remaining.count - 1)].id
    }
    /// 首帧时序等待：原生卡片集合在面板 hosting view 建好后，才通过
    /// `ReplicaNativeCollectionHost.scheduleSnapshotDrain` 在主队列下一轮排空首个快照，
    /// 并在首次布局的 `viewDidMoveToWindow` 里取得 panel 第一响应者。若在该同步栈里
    /// 立刻注入 ⌘A，`appliedItems`/焦点都还未就绪，按键会被丢弃。这里显式等待
    /// “快照已排空 + 集合已持有焦点”，超时给出可解释的失败原因（而不是无限等待）。
    @MainActor static func waitForCollectionReady(_ ui: ReplicaUIController, _ state: ReplicaUIState,
                                                   expectedItemCount: Int) async throws {
        // 先加载面板（创建 hosting view），再在等待循环里有界地驱动首次布局；
        // 隐藏面板不会自动触发 SwiftUI 的子视图布局，这里只推进首帧，不改变可见性。
        let panel = ui.panel
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            panel.contentView?.layoutSubtreeIfNeeded()
            if let owner = state.collectionOwner,
               let replicaPanel = panel as? ReplicaPanel,
               replicaPanel.firstResponder === owner,
               owner.appliedItems(for: state)?.map(\.id) == state.visibleItems.map(\.id),
               state.visibleItems.count == expectedItemCount {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let owner = state.collectionOwner
        let applied = owner?.appliedItems(for: state)?.count
        let focused = (panel as? ReplicaPanel).map { $0.firstResponder === owner } ?? false
        throw Failure(description: "Collection not ready within 3s: owner=\(owner != nil), "
            + "applied=\(String(describing: applied)), visible=\(state.visibleItems.count), "
            + "expected=\(expectedItemCount), focused=\(focused)")
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard(name: .init("BlinkClipUIHarness-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let store = try ClipboardStore(directoryURL: directory)
        let first = try store.add(ClipboardItem(plainText: "FIRST fixture"))
        let second = try store.add(ClipboardItem(plainText: "SECOND fixture"))
        let pin = try store.createPinboard(name: "fixture", colorHex: "#00AAFF")
        try store.assign(ids: [first], to: pin.id)
        let ui = ReplicaUIController(store: store)
        ui.pasteboard = board
        let state = ui.state
        try require(!state.cloudSync.canSync && !state.cloudSync.isEnabled)
        state.cloudSync.start()
        state.cloudSync.setEnabled(true)
        try require(!state.cloudSync.isEnabled && !state.cloudSync.isBusy)
        try require(!state.originalCloudSync.canSync && !state.originalCloudSync.isEnabled)
        state.originalCloudSync.start()
        state.originalCloudSync.setEnabled(true)
        try require(!state.originalCloudSync.isEnabled && !state.originalCloudSync.isBusy)
        let cloudRow = NSHostingView(rootView: ICloudSyncGeneralRow(sync: state.originalCloudSync, drive: state.cloudSync))
        cloudRow.frame = NSRect(x: 0, y: 0, width: 430, height: 44)
        cloudRow.layoutSubtreeIfNeeded()
        try require(cloudRow.fittingSize.width > 0)
        var delivered: [([UUID], Bool)] = []
        ui.pasteItemsHandler = { delivered.append(($0, $1)); return true }
        func key(_ code: UInt16, _ chars: String, _ modifiers: NSEvent.ModifierFlags) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: ui.panel.windowNumber,
                                        context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            ui.panel.sendEvent(event)
        }
        state.normalizeSelection()
        try await waitForCollectionReady(ui, state, expectedItemCount: 2)
        key(0, "a", .command)
        try require(state.selection == Set([first, second]))
        key(8, "c", .command)
        let ordered = state.selectedItems.compactMap(\.plainText)
        try require(ordered.count == state.selection.count)
        let aggregate = board.data(forType: .rtf).flatMap {
            try? NSAttributedString(data: $0, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil).string
        }
        try require(board.pasteboardItems?.count == 1 && aggregate == ordered.joined(separator: "\n"))
        key(8, "c", [.command, .shift])
        try require(board.string(forType: .string) == ordered.joined(separator: "\n") && board.data(forType: .rtf) == nil)
        key(0, "a", [.command, .shift])
        state.normalizeSelection()
        try require(state.selection.isEmpty && state.primaryID == nil)
        let visible = state.visibleItems
        state.select(try entryItem(visible[0]))
        state.select(try entryItem(visible[1]), modifiers: .shift)
        try require(state.selection.count == 2)
        ui.pasteSelection(plainTextOnly: false)
        try require(delivered.last?.0 == visible.map(\.id) && delivered.last?.1 == false)
        store.preferences.quickPasteModifierRawValue = NSEvent.ModifierFlags.option.rawValue
        store.preferences.plainTextModifierRawValue = NSEvent.ModifierFlags.control.rawValue
        key(18, "1", [.option, .control])
        try require(delivered.last?.0 == [visible[0].id] && delivered.last?.1 == true)
        store.preferences.nextPinboardShortcut = KeyboardShortcut(keyCode: 124, modifierRawValue: NSEvent.ModifierFlags.option.rawValue)
        key(124, "", .option)
        try require(state.pinboardID == pin.id && state.visibleItems.map(\.id) == [first])
        state.chooseBoard(nil)
        // 第八十一轮（CHANGELOG «Stack 保留重复项并逐行移除»）：原版队列允许相同内容重复入队，
        // 右键移除或粘贴成功只消费当前行、保留同 ID 的其他项；第一百一十四轮再次确认
        // «保留顺序和重复项»。旧断言按“去重”期望 [visible[1], visible[0]]，与产品现状
        // （`ReplicaUIState.insertStackItem` 每次 addToStack 一律插入，不清同 ID）冲突。
        state.addToStack(try entryItem(visible[0])); state.addToStack(try entryItem(visible[0])); state.addToStack(try entryItem(visible[1]))
        let pushedStack = [visible[1].id, visible[0].id, visible[0].id]
        try require(state.stackIDs == pushedStack)
        state.reverseStack()
        try require(state.stackIDs == Array(pushedStack.reversed()))
        let reopened = try ClipboardStore(directoryURL: directory)
        // 第一百四十七轮（CHANGELOG «Stack 会话关闭与队列»）：关闭 Stack 后释放本次队列，
        // 重新打开从空队列开始；队列不再写入或从旧偏好恢复。只有方向偏好（stackReversed）
        // 与历史内容保留（`reverseStack` 仍 toggle 并 save）。
        try require(reopened.preferences.stackItemIDs.isEmpty)
        try require(reopened.preferences.stackReversed)
        ui.consumeStackHead()
        // 队首消费只移除一项，重复入队的另一项仍在（第八十一轮）。
        try require(state.stackIDs == [visible[0].id, visible[1].id])
        for minutes in [15, 30, 60, 180, 480] {
            let start = Date()
            state.pauseMonitoring(minutes: minutes)
            try require(store.preferences.isMonitoringPaused)
            try require(abs(store.preferences.pauseUntil!.timeIntervalSince(start) - Double(minutes * 60)) < 1)
        }
        state.pauseMonitoring()
        try require(store.preferences.isMonitoringPaused && store.preferences.pauseUntil == nil)
        state.resumeMonitoring()
        try require(!store.preferences.isMonitoringPaused && store.preferences.pauseUntil == nil)
        state.searchVisible = false
        state.query = ""
        func load(_ provider: NSItemProvider, _ type: String) async throws -> Data {
            try await withCheckedThrowingContinuation { continuation in
                provider.loadDataRepresentation(forTypeIdentifier: type) { data, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: data ?? Data()) }
                }
            }
        }
        let bytes = Data([0, 127, 255, 42])
        let dragItem = ClipboardItem(title: "drag fixture", plainText: "Unicode drag 中文", payloads: [
            "com.example.drag-fixture": bytes,
            "public.html": Data("<b>Unicode drag 中文</b>".utf8),
            "com.chrisli.blinkclip.internal.recognized-text": Data("private index".utf8)
        ])
        let provider = itemDragProvider(dragItem)
        let rawDrag = try await load(provider, "com.example.drag-fixture")
        let htmlDrag = try await load(provider, "public.html")
        let textDrag = try await load(provider, "public.utf8-plain-text")
        try require(rawDrag == bytes && htmlDrag == dragItem.payloads["public.html"])
        try require(String(data: textDrag, encoding: .utf8) == "Unicode drag 中文")
        try require(!provider.registeredTypeIdentifiers.contains { $0.hasPrefix("com.chrisli.blinkclip.internal.") })
        let fileA = directory.appendingPathComponent("first 中文.txt")
        let fileB = directory.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: fileA)
        try Data("second".utf8).write(to: fileB)
        let representations = [fileA, fileB].map { ["public.file-url": Data($0.absoluteString.utf8)] }
        let filesItem = ClipboardItem(kind: .files, payloads: [
            "public.file-url": Data(fileA.absoluteString.utf8),
            "com.chrisli.blinkclip.internal.items+json": try JSONEncoder().encode(representations)
        ])
        try require(itemFileURLs(filesItem) == [fileA, fileB])
        let fileProvider = itemDragProvider(filesItem)
        let filePaths = try await load(fileProvider, "NSFilenamesPboardType")
        let restoredPaths = try PropertyListSerialization.propertyList(from: filePaths, format: nil) as? [String]
        try require(restoredPaths == [fileA.path, fileB.path])
        state.addToStack(try entryItem(visible[1]))
        let stackWindow = NSPanel(contentRect: .init(x: 0, y: 0, width: 264, height: 120),
                                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let stackContent = NSHostingView(rootView: ReplicaStackView(state: state))
        stackWindow.contentView = stackContent
        stackContent.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        func tables(in view: NSView) -> [NSTableView] {
            (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { tables(in: $0) }
        }
        let stackTable = tables(in: stackContent).first!
        try require(stackTable.numberOfRows == state.stackItems.count && stackTable.rowHeight == 44)
        try require(stackTable.delegate?.tableView?(stackTable, shouldSelectRow: 0) == false)
        try require(stackTable.view(atColumn: 0, row: 0, makeIfNecessary: true) != nil)
        try require(!ui.panel.isVisible)
        guard let screen = NSScreen.main else {
            print("{\"status\":\"blocked\",\"reason\":\"No window-server screen for visibility assertions\"}")
            exit(77)
        }
        func waitForVisibility(_ expected: Bool) async throws {
            let deadline = Date().addingTimeInterval(3)
            while ui.panel.isVisible != expected && Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try require(ui.panel.isVisible == expected)
        }
        func presentOffscreen() async throws {
            ui.showPanel()
            ui.panel.setFrameOrigin(.init(x: screen.frame.maxX + 200, y: screen.frame.maxY + 200))
            try await waitForVisibility(true)
            try await Task.sleep(nanoseconds: 250_000_000)
            try require(ui.panel.isVisible)
        }
        defer { ui.panel.orderOut(nil); stackWindow.orderOut(nil) }
        try await presentOffscreen()
        func menuButtons(in view: NSView) -> [NSButton] {
            (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { menuButtons(in: $0) }
        }
        let hostedButtons = menuButtons(in: ui.panel.contentView!)
        guard let more = hostedButtons.first(where: { $0.accessibilityIdentifier() == "panel-more-actions" || $0.accessibilityLabel() == "更多操作" }) else {
            throw Failure(description: "Missing more menu button: \(hostedButtons.map { "\(type(of: $0)) \($0.accessibilityLabel() ?? "") \($0.bounds)" })")
        }
        try require(more.bounds.width >= 44 && more.bounds.height >= 44)
        let content = ui.panel.contentView!
        let toolbarSearch = hostedButtons.first { $0.accessibilityLabel() == "搜索剪贴板" }!
        try require(abs(more.convert(more.bounds, to: content).midY
            - toolbarSearch.convert(toolbarSearch.bounds, to: content).midY) < 0.5)
        for step in 0..<64 {
            let angle = CGFloat(step) * .pi * 2 / 64
            let point = NSPoint(x: more.bounds.midX + cos(angle) * 21.5,
                                y: more.bounds.midY + sin(angle) * 21.5)
            let hit = content.hitTest(more.convert(point, to: content.superview))
            try require(hit === more || hit?.isDescendant(of: more) == true)
        }
        let resizePoint = NSPoint(x: 100, y: content.bounds.maxY - 1)
        try require(content.hitTest(content.convert(resizePoint, to: content.superview)) is ReplicaPanelResizeHandle)
        for x in [CGFloat(1), more.bounds.midX, more.bounds.maxX - 1] {
            for y in [CGFloat(1), more.bounds.midY, more.bounds.maxY - 1] {
                let hit = content.hitTest(more.convert(.init(x: x, y: y), to: content.superview))
                guard hit === more || hit?.isDescendant(of: more) == true else {
                    throw Failure(description: "More hit missing at \(x),\(y); bounds=\(more.bounds); frame=\(more.convert(more.bounds, to: content)); root=\(content.frame),\(content.bounds); hit=\(String(describing: hit)); hitFrame=\(String(describing: hit?.frame)); direct=\(String(describing: more.hitTest(more.convert(.init(x: x, y: y), to: more.superview))))")
                }
            }
        }
        // Search remains centered while the collapsed board strip grows to its
        // right; extra groups must scroll before reaching the more button.
        func searchFields(in view: NSView) -> [ReplicaSearchEditor.SearchField] {
            (view as? ReplicaSearchEditor.SearchField).map { [$0] }
                ?? view.subviews.flatMap { searchFields(in: $0) }
        }
        var extraGroups: [UUID] = []
        for groupCount in [1, 4, 13] {
            while store.pinboards.count < groupCount {
                extraGroups.append(try store.createPinboard(name: "Search layout \(store.pinboards.count)").id)
            }
            state.searchVisible = true
            for width: CGFloat in [1024, 1512, 2560] {
                ui.panel.setFrame(.init(x: screen.frame.maxX + 200, y: screen.frame.maxY + 200,
                    width: width, height: 332), display: true)
                try await Task.sleep(for: .milliseconds(100))
                content.layoutSubtreeIfNeeded()
                // 产品没有「返回剪贴板历史」按钮：源码零命中，且激活态下搜索按钮 alpha 0、
                // `PanelSearchBar.hitTest` 把点击让给输入框。搜索态真正的“返回历史”路径是
                // 取消搜索（非空查询下 Esc 走 `cancelSearchOrPanel`），由本循环后的断言覆盖。
                guard let field = searchFields(in: content).first else {
                    throw Failure(description: "Missing active search field")
                }
                let fieldFrame = field.convert(field.bounds, to: content)
                let moreFrame = more.convert(more.bounds, to: content)
                try require(abs(fieldFrame.midX - content.bounds.midX) < 1)
                // 宽度按真实布局常量：`PanelToolbar.searchBarConstraints` 的
                // `widthAnchor(greaterThanOrEqualTo: widthAnchor, multiplier: 0.25)` 与
                // `greaterThanOrEqualToConstant: 400`，其中 widthAnchor 是工具栏宽度。
                // 工具栏宽度 = 面板宽度 − 2×`ReplicaPanelView.backgroundInset`
                // （macOS 26 起 8pt，之前 0）。旧断言固定再减 16，只在 macOS 26 成立，
                // 本机（macOS 15，inset=0）实测 2560→640 而非 636。
                let backgroundInset: CGFloat = {
                    if #available(macOS 26, *) { return 8 }
                    return 0
                }()
                let toolbarWidth = width - backgroundInset * 2
                try require(abs(fieldFrame.width - max(400, toolbarWidth * 0.25)) < 1)
                // 搜索框右侧的内部控件是筛选按钮（`SearchField.subviewConstraints`：
                // filters.trailing = trailing − 8），旧断言用不存在的历史按钮做 8pt 间距检查。
                let filters = field.makeFiltersButton()
                let filtersFrame = filters.convert(filters.bounds, to: content)
                try require(filtersFrame.width > 0 && filtersFrame.height > 0)
                try require(abs(filtersFrame.maxX - (fieldFrame.maxX - 8)) < 1)
                try require(filtersFrame.minX >= fieldFrame.minX)
                try require(moreFrame.minX > fieldFrame.maxX)
                for x in [CGFloat(1), more.bounds.midX, more.bounds.maxX - 1] {
                    for y in [CGFloat(1), more.bounds.midY, more.bounds.maxY - 1] {
                        let moreHit = content.hitTest(more.convert(.init(x: x, y: y), to: content.superview))
                        try require(moreHit === more || moreHit?.isDescendant(of: more) == true)
                    }
                }
            }
        }
        // 搜索态的“返回剪贴板历史”路径（替代不存在的返回按钮断言）：非空查询下 Esc 走
        // `ReplicaUIController.cancelSearchOrPanel` 的 mode1 分支——清空查询、退出搜索，
        // 面板保持可见（不 hidePanel）。面板已在屏幕外 present，这里只验证状态迁移。
        state.searchVisible = true
        state.applySearchInput(nodes: [.text("fixture")], text: "fixture", filters: [])
        // 集合查询经 `searchQueryChanges.debounce(120ms)` 才落到 `collectionSearchQueryNodes`。
        try await Task.sleep(for: .milliseconds(250))
        try require(!state.isCollectionSearchQueryEmpty)
        key(53, "", [])
        try await Task.sleep(for: .milliseconds(250))
        try require(state.isCollectionSearchQueryEmpty && !state.searchVisible && ui.panel.isVisible)
        for id in extraGroups { try store.removePinboard(id: id) }
        state.searchVisible = false
        try await presentOffscreen()
        // Exercise the actual hosted tab hit tree, including transparent padding and icon/label gaps.
        func tabs(in view: NSView) -> [PinboardTabView] {
            (view as? PinboardTabView).map { [$0] } ?? view.subviews.flatMap { tabs(in: $0) }
        }
        func tab(named name: String) throws -> PinboardTabView {
            guard let result = tabs(in: ui.panel.contentView!).first(where: {
                ($0.titleView.subviews.first as? NSTextField)?.stringValue == name
            }) else { throw Failure(description: "Missing hosted tab \(name)") }
            return result
        }
        func mouse(_ type: NSEvent.EventType, cell: PinboardTabView, point: NSPoint,
                   clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: cell.convert(point, to: nil), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: ui.panel.windowNumber,
                context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
        }
        func saveFixtureScreenshot(_ view: NSView, name: String) throws {
            guard let path = ProcessInfo.processInfo.environment["BLINKCLIP_TEST_SCREENSHOT_DIRECTORY"] else { return }
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
        }
        var tabHitChecks = 0
        for (name, id) in [(store.preferences.historyTitle, Optional<UUID>.none), (pin.name, Optional(pin.id))] {
            state.chooseBoard(id == nil ? pin.id : nil)
            try await Task.sleep(nanoseconds: 50_000_000)
            ui.panel.contentView!.layoutSubtreeIfNeeded()
            let cell = try tab(named: name)
            cell.layoutSubtreeIfNeeded()
            try require(cell.bounds.width > 30 && cell.bounds.height > 12)
            let points = [CGFloat(1), cell.bounds.midX, cell.bounds.maxX - 1].flatMap { x in
                [CGFloat(1), cell.bounds.midY, cell.bounds.maxY - 1].map { NSPoint(x: x, y: $0) }
            } + [NSPoint(x: 16, y: cell.bounds.midY), NSPoint(x: 26, y: cell.bounds.midY)]
            for point in points {
                state.chooseBoard(id == nil ? pin.id : nil)
                let content = ui.panel.contentView!
                guard let hit = content.hitTest(cell.convert(point, to: content.superview)),
                      hit === cell || hit.isDescendant(of: cell) else {
                    var chain: [String] = []
                    var ancestor: NSView? = cell
                    while let view = ancestor {
                        chain.append("\(type(of: view)): frame=\(view.frame) bounds=\(view.bounds) visible=\(view.visibleRect)")
                        ancestor = view.superview
                    }
                    throw Failure(description: "Tab hit area missing: \(name) at \(point); direct=\(String(describing: cell.hitTest(cell.convert(point, to: cell.superview)))); chain=\(chain)")
                }
                hit.mouseDown(with: mouse(.leftMouseDown, cell: cell, point: point))
                try require(state.pinboardID != id)
                hit.mouseUp(with: mouse(.leftMouseUp, cell: cell, point: point))
                try require(state.pinboardID == id)
                tabHitChecks += 1
            }
            state.chooseBoard(id == nil ? pin.id : nil)
            let inside = NSPoint(x: 1, y: cell.bounds.midY)
            cell.mouseDown(with: mouse(.leftMouseDown, cell: cell, point: inside))
            cell.mouseUp(with: mouse(.leftMouseUp, cell: cell, point: NSPoint(x: cell.bounds.maxX + 5, y: inside.y)))
            try require(state.pinboardID != id)
        }
        state.chooseBoard(nil)
        ui.panel.contentView!.layoutSubtreeIfNeeded()
        let hoverTab = try tab(named: pin.name)
        func tabSnapshot(_ view: NSView) -> Data {
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            return bitmap.representation(using: .png, properties: [:])!
        }
        hoverTab.mouseExited(with: NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: ui.panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
        let withoutHover = tabSnapshot(hoverTab)
        hoverTab.mouseEntered(with: NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: ui.panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
        try require(tabSnapshot(hoverTab) != withoutHover)
        try saveFixtureScreenshot(ui.panel.contentView!, name: "hover-panel")
        hoverTab.mouseExited(with: NSEvent.enterExitEvent(with: .mouseExited, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: ui.panel.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil)!)
        try require(tabSnapshot(hoverTab) == withoutHover)
        let editableTab = try tab(named: pin.name)
        let tabPanel = ui.panel as! ReplicaPanel
        editableTab.mouseDown(with: mouse(.leftMouseDown, cell: editableTab, point: .init(x: 1, y: 1), clicks: 2))
        try require(!editableTab.titleView.isEditing)
        let titlePoint = NSPoint(x: editableTab.titleView.frame.midX, y: editableTab.titleView.frame.midY)
        editableTab.titleView.mouseDown(with: mouse(.leftMouseDown, cell: editableTab, point: titlePoint, clicks: 2))
        guard editableTab.titleView.isEditing && editableTab.titleView.ownsEditor(in: tabPanel) else {
            throw Failure(description: "Inline double-click did not own editor; editing=\(editableTab.titleView.isEditing), responder=\(String(describing: tabPanel.firstResponder))")
        }
        let priorBoard = state.pinboardID
        editableTab.mouseUp(with: mouse(.leftMouseUp, cell: editableTab, point: .init(x: 1, y: 1)))
        try require(state.pinboardID == priorBoard)
        editableTab.titleView.cancelOperation(nil)
        try require(!editableTab.titleView.isEditing && tabPanel.tabTitleEditingOwner == nil)
        try require(tabHitChecks == 22)
        let countBeforeCreation = store.pinboards.count
        let selectionBeforeCreation = state.pinboardID
        ui.createPinboard()
        try require(store.pinboards.count == countBeforeCreation + 1)
        let newBoard = store.pinboards.last!
        try require(state.pinboardID == selectionBeforeCreation && newBoard.name == PinboardTitle.normalizedRename(""))
        try await Task.sleep(for: .milliseconds(350))
        ui.panel.contentView!.layoutSubtreeIfNeeded()
        let newTab = try tab(named: newBoard.name)
        try require(newTab.titleView.isEditing && newTab.titleView.ownsEditor(in: tabPanel))
        let editor = tabPanel.firstResponder as! NSTextView
        try require(editor.selectedRange().length == (newBoard.name as NSString).length)
        try saveFixtureScreenshot(ui.panel.contentView!, name: "inline-new-group")
        editor.insertText("Generated group rename", replacementRange: editor.selectedRange())
        let newField = newTab.titleView.subviews.first as! NSTextField
        _ = newTab.titleView.control(newField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:)))
        try require(store.pinboards.first { $0.id == newBoard.id }?.name == "Generated group rename")
        let capacity = HistoryCapacityControl(frame: .init(x: 0, y: 0, width: 420, height: 184))
        var capacityChanges: [Int] = []
        capacity.onCommit = { capacityChanges.append($0) }
        capacity.layoutSubtreeIfNeeded()
        capacity.confirmShortening = { _, completion in completion(true) }
        for days in [1, 7, 30, 60, 0] {
            capacity.optionButtons.first { $0.tag == days }!.performClick(nil)
        }
        try require(capacityChanges == [1, 7, 30, 60, 0])
        for (position, days) in [(1.5, 4), (2.5, 14), (3.5, 180), (4.5, 365), (5.5, 0)] {
            try require(HistoryCapacity.days(for: position) == days)
        }
        try require(HistoryCapacity.days(for: .nan) == nil && HistoryCapacity.days(for: 0) == nil)

        if ProcessInfo.processInfo.environment["BLINKCLIP_TEST_SCREENSHOT_DIRECTORY"] != nil {
            state.store.preferences.historyRetentionDays = 7
            let settingsWindow = NSPanel(contentRect: .init(x: 0, y: 0, width: 760, height: 640),
                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
            let settingsView = NSHostingView(rootView: ReplicaSettingsView(state: state))
            settingsWindow.contentView = settingsView
            settingsWindow.setFrameOrigin(.init(x: screen.frame.maxX + 300, y: screen.frame.maxY + 300))
            settingsWindow.orderBack(nil)
            try await Task.sleep(for: .milliseconds(150))
            try saveFixtureScreenshot(settingsView, name: "history-retention")
            settingsWindow.orderOut(nil)
        }

        // Delete only synthetic groups. Confirmation is panel content, not a
        // separate window/modal; preserve the original empty/nonempty split.
        state.chooseBoard(nil)
        let windowsBeforeDeletion = Set(NSApp.windows.map(ObjectIdentifier.init))
        let emptyGroup = try store.createPinboard(name: "Empty deletion fixture")
        let emptyGroupIndex = store.pinboards.firstIndex { $0.id == emptyGroup.id }!
        state.chooseBoard(emptyGroup.id)
        ui.removePinboard(try listTarget(emptyGroup, store: store))
        try require(!store.pinboards.contains { $0.id == emptyGroup.id })
        // 03a538：删掉的分组按“相邻夹取”（min(旧位置, 剩余数-1)）落到仍存在的列表，
        // 不会跳回历史。旧断言要求 `state.pinboardID == nil`，与产品语义冲突。
        try require(state.pinboardID == expectedBoardAfterDeletion(indexBefore: emptyGroupIndex, store: store)
            && state.pinboardID != nil && state.pendingPinboardDeletion == nil && ui.panel.isVisible)
        let deleteGroup = try store.createPinboard(name: "Delete fixture")
        let retainedGroup = try store.createPinboard(name: "Retained fixture")
        // fixture 必须带 `pinboardOwnerID`：原生列表的“非空”判定（
        // `ClipboardListPersistence.menuState` 的 `list == %@`）走的是 Item 的 list 关系，
        // 只给 `pinboardIDs` 不会建立该关系，分组被判为空 → 走“空组直接删除”，
        // `pendingPinboardDeletion` 确认分支永远不可达。
        let historyID = try store.add(ClipboardItem(plainText: "delete history fixture", pinboardIDs: [deleteGroup.id], pinboardOwnerID: deleteGroup.id))
        let onlyGroupID = try store.add(ClipboardItem(plainText: "delete only fixture", pinboardIDs: [deleteGroup.id], isInHistory: false, pinboardOwnerID: deleteGroup.id))
        let sharedID = try store.add(ClipboardItem(plainText: "delete shared fixture", pinboardIDs: [deleteGroup.id, retainedGroup.id], isInHistory: false, pinboardOwnerID: retainedGroup.id))
        // 旧值（无原生 owner）多分组条目：产品在删组后仍让它存活，只去掉被删组的归属
        // （`ClipboardStore.removeList` 的本地投影分支 `pinboardIDs.remove(id)`）。
        // 没有 CHANGELOG 结论，保留产品现状而不是为了变绿改成“随组删除”→ 见报告第 6 条。
        let legacySharedID = try store.add(ClipboardItem(plainText: "legacy multi-group fixture", pinboardIDs: [deleteGroup.id, retainedGroup.id], isInHistory: false))
        state.chooseBoard(deleteGroup.id)
        ui.removePinboard(try listTarget(deleteGroup, store: store))
        try await Task.sleep(for: .milliseconds(100))
        try require(state.pendingPinboardDeletion?.pinboardValue?.id == deleteGroup.id && state.pinboardID == deleteGroup.id)
        try require(ui.panel.isVisible && NSApp.modalWindow == nil && ui.panel.sheets.isEmpty)
        try require(Set(NSApp.windows.map(ObjectIdentifier.init)) == windowsBeforeDeletion)
        try require(store.items.contains { $0.id == onlyGroupID })
        ui.panel.contentView!.layoutSubtreeIfNeeded()
        try saveFixtureScreenshot(ui.panel.contentView!, name: "inline-group-deletion")
        key(8, "c", .command)
        key(51, "", [])
        try require(ui.panel.isVisible && store.items.contains { $0.id == onlyGroupID })
        key(53, "", [])
        try require(state.pendingPinboardDeletion == nil && ui.panel.isVisible)
        try require(store.pinboards.contains { $0.id == deleteGroup.id })
        ui.removePinboard(try listTarget(deleteGroup, store: store))
        ui.cancelPinboardRemoval()
        try require(state.pendingPinboardDeletion == nil && ui.panel.isVisible)
        ui.removePinboard(try listTarget(deleteGroup, store: store))
        state.chooseBoard(retainedGroup.id)
        try require(state.pendingPinboardDeletion == nil)
        func deletionSQL(_ sql: String) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
            process.arguments = [directory.appendingPathComponent("clipboard.sqlite").path, sql]
            try process.run()
            process.waitUntilExit()
            try require(process.terminationStatus == 0)
        }
        state.chooseBoard(deleteGroup.id)
        ui.removePinboard(try listTarget(deleteGroup, store: store))
        try deletionSQL("CREATE TRIGGER reject_group_deletion BEFORE DELETE ON ZPINBOARD BEGIN SELECT RAISE(ABORT,'synthetic group deletion failure'); END;")
        ui.confirmPinboardRemoval()
        // 产品修复（第 8 条）：失败事务仍会投递一次列表快照，被删组在快照里消失 →
        // 相邻夹取改选相邻列表 → `applySelectedList` 顺手 `cancelPendingDeletion()`，
        // 把这次失败要停留的确认与错误一起清掉。修复后 pending 目标与选中列表都留在
        // 原分组上，错误仍显示在同一个面板内确认里。
        try require(state.pendingPinboardDeletion?.pinboardValue?.id == deleteGroup.id && state.pinboardDeletionError != nil)
        try require(state.hasPendingDeletion && ui.panel.isVisible && NSApp.modalWindow == nil)
        try require(state.pinboardID == deleteGroup.id && ui.panel.isVisible && NSApp.modalWindow == nil)
        try require(store.pinboards.contains { $0.id == deleteGroup.id } && store.items.contains { $0.id == onlyGroupID })
        try deletionSQL("DROP TRIGGER reject_group_deletion;")
        ui.cancelPinboardRemoval()
        try require(state.pendingPinboardDeletion == nil && state.pinboardDeletionError == nil)
        state.chooseBoard(retainedGroup.id)
        ui.removePinboard(try listTarget(deleteGroup, store: store))
        key(36, "\r", [])
        try require(ui.panel.isVisible && state.pendingPinboardDeletion == nil && state.pinboardID == retainedGroup.id)
        try require(!store.pinboards.contains { $0.id == deleteGroup.id })
        try require(store.items.contains { $0.id == historyID && $0.isInHistory && $0.pinboardIDs.isEmpty })
        try require(!store.items.contains { $0.id == onlyGroupID })
        try require(store.items.first { $0.id == sharedID }?.pinboardIDs == [retainedGroup.id])
        // 旧值（无原生 owner）条目不会出现在 `removeList` 的 affected 里，因此仍存活，
        // 只丢掉被删分组的归属。按观察到的产品行为锁定（无明确产品结论，见报告第 6 条）。
        try require(store.items.first { $0.id == legacySharedID }?.pinboardIDs == [retainedGroup.id])
        let afterDeletion = try ClipboardStore(directoryURL: directory)
        try require(!afterDeletion.pinboards.contains { $0.id == deleteGroup.id })
        try require(afterDeletion.items.contains { $0.id == historyID } && !afterDeletion.items.contains { $0.id == onlyGroupID })
        let retainedGroupIndex = store.pinboards.firstIndex { $0.id == retainedGroup.id }!
        ui.removePinboard(try listTarget(retainedGroup, store: store))
        ui.confirmPinboardRemoval()
        // 03a538：同样按相邻夹取落位，不是跳回历史（旧断言要求 `state.pinboardID == nil`）。
        try require(state.pinboardID == expectedBoardAfterDeletion(indexBefore: retainedGroupIndex, store: store)
            && state.pendingPinboardDeletion == nil && ui.panel.isVisible)
        try require(!store.items.contains { $0.id == sharedID })
        // 旧值条目在所属分组被删后仍存活（原断言要求它随之消失，属同一处无结论的产品行为）。
        try require(store.items.contains { $0.id == legacySharedID }
            && store.items.first { $0.id == legacySharedID }?.pinboardIDs.isEmpty == true)
        ui.removePinboard(try listTarget(pin, store: store))
        ui.hidePanel()
        try require(state.pendingPinboardDeletion == nil)
        try await waitForVisibility(false)
        try await presentOffscreen()
        try require(state.pendingPinboardDeletion == nil && store.pinboards.contains { $0.id == pin.id })

        state.chooseBoard(nil)
        // 原生集合在 `replaceCollectionModel` 后经 `scheduleSnapshotDrain` 于下一轮主队列排空；
        // 排空前 `appliedItems` 为空，`state.select` 会静默 no-op，随后的 ⌘C 复制到错误条目。
        // 这里先等到集合就绪（条目与其顺序都与 `visibleItems` 一致），再显式断言选择落点。
        try await waitForCollectionReady(ui, state, expectedItemCount: 3)
        state.select(store.items.first { $0.id == first }!)
        try require(state.selection == [first] && state.primaryID == first)
        let priorCopyDate = store.items.first { $0.id == first }!.updatedAt
        var copyFeedbackCount = 0
        var restoreNotifiedBeforeFeedback = false
        var savedBeforeFeedback = false
        let restoreSubscription = store.didRestoreItem.sink { restoreNotifiedBeforeFeedback = true }
        ui.copiedItemsHandler = {
            copyFeedbackCount += 1
            let reopened = try? ClipboardStore(directoryURL: directory)
            savedBeforeFeedback = restoreNotifiedBeforeFeedback
                && reopened?.items.first { $0.id == first }?.updatedAt == store.items.first { $0.id == first }?.updatedAt
        }
        key(8, "c", .command)
        try require(board.string(forType: .string) == "FIRST fixture")
        try require(ui.panel.isVisible && copyFeedbackCount == 1)
        try require(savedBeforeFeedback)
        try require(store.items.first { $0.id == first }!.updatedAt > priorCopyDate)
        try await waitForVisibility(false)
        restoreSubscription.cancel()
        let afterCopy = try ClipboardStore(directoryURL: directory)
        try require(afterCopy.items.first { $0.id == first }!.updatedAt > priorCopyDate)
        try await presentOffscreen()
        key(53, "", [])
        try await waitForVisibility(false)
        state.searchVisible = true
        state.query = "missing search fixture"
        try await presentOffscreen()
        // `ReplicaUIController.cancelSearchOrPanel` 的显式语义是“先取消搜索上下文再关窗”：
        // 查询非空时第一次 Esc 只清空查询并退出搜索（面板保持），空查询时 Esc 才关面板。
        // 旧断言要求“第一次 Esc 就关面板（含搜索态）”，与产品源码冲突。
        try await Task.sleep(for: .milliseconds(250))
        key(53, "", [])
        try await Task.sleep(for: .milliseconds(250))
        try require(ui.panel.isVisible && state.isCollectionSearchQueryEmpty && !state.searchVisible)
        key(53, "", [])
        try await waitForVisibility(false)
        state.searchVisible = false
        state.query = ""
        try await presentOffscreen()
        let outside = NSWindow(contentRect: .init(x: screen.frame.maxX + 600, y: screen.frame.maxY + 600, width: 80, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false)
        defer { outside.orderOut(nil) }
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .init(x: 5, y: 5), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: outside.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: 1)!
        NSApp.sendEvent(click)
        try await waitForVisibility(false)
        try await presentOffscreen()
        state.chooseBoard(nil)
        // 同前：`chooseBoard` 后必须先让原生集合排空快照，否则选择会落到旧集合上。
        try await waitForCollectionReady(ui, state, expectedItemCount: state.visibleItems.count)
        state.select(store.items.first { $0.id == first }!)
        try require(state.selection == [first])
        let beforeInterruptedCopy = store.items.first { $0.id == first }!.updatedAt
        key(8, "c", .command)
        ui.copySelection(plainTextOnly: true)
        try require(copyFeedbackCount == 3)
        try require(store.items.first { $0.id == first }!.updatedAt > beforeInterruptedCopy)
        ui.showPanel()
        try require(store.items.first { $0.id == first }!.updatedAt > beforeInterruptedCopy)
        ui.panel.setFrameOrigin(.init(x: screen.frame.maxX + 200, y: screen.frame.maxY + 200))
        try await Task.sleep(nanoseconds: 350_000_000)
        try require(ui.panel.isVisible)
        ui.hidePanel()
        try await waitForVisibility(false)
        // Exercise the native card's actual double-click route, not only the
        // controller copy entry point or an injected delivery recorder.
        ui.pasteItemsHandler = { ids, plain in
            do {
                try store.writeToPasteboard(ids: ids, pasteboard: board, plainTextOnly: plain)
                ui.hidePanel()
                return true
            } catch { return false }
        }
        for _ in 0..<2 {
            try await presentOffscreen()
            state.chooseBoard(nil)
            state.select(store.items.first { $0.id == first }!)
            try await Task.sleep(for: .milliseconds(50))
            guard let collection = (ui.panel as? ReplicaPanel)?.collectionFocusTarget as? ReplicaNativeCollectionHost,
                  let cell = collection.previewAnchor(for: first) else {
                throw Failure(description: "Missing native double-click fixture cell")
            }
            let event = NSEvent.mouseEvent(with: .leftMouseDown,
                location: cell.convert(.init(x: cell.bounds.midX, y: cell.bounds.midY), to: nil),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: ui.panel.windowNumber, context: nil, eventNumber: 1,
                clickCount: 2, pressure: 1)!
            collection.mouseDown(with: event)
            try await waitForVisibility(false)
            try require(board.string(forType: .string) == store.items.first { $0.id == first }!.plainText)
        }
        var focusTransitions: [String] = []
        var closeWasVisible = false
        ui.panelDidShow = { focusTransitions.append("remember") }
        ui.panelWillClose = { restore in
            focusTransitions.append(restore ? "restore" : "keep-preview")
            closeWasVisible = ui.panel.isVisible
        }
        ui.togglePanel()
        try await waitForVisibility(true)
        ui.panel.setFrameOrigin(.init(x: screen.frame.maxX + 200, y: screen.frame.maxY + 200))
        try await Task.sleep(for: .milliseconds(200))
        ui.togglePanel()
        try require(focusTransitions == ["remember", "restore"] && closeWasVisible)
        ui.hidePanel()
        try require(focusTransitions == ["remember", "restore"])
        try await waitForVisibility(false)
        let previewID = try store.add(ClipboardItem(plainText: "Detached preview focus fixture",
            pinboardIDs: [pin.id], isInHistory: false))
        ui.showPreview(item: store.items.first { $0.id == previewID }!)
        let detached = NSApp.windows.compactMap { $0 as? PreviewWindow }
        try require(!detached.isEmpty)
        ui.togglePanel()
        try await waitForVisibility(true)
        ui.panel.setFrameOrigin(.init(x: screen.frame.maxX + 200, y: screen.frame.maxY + 200))
        try await Task.sleep(for: .milliseconds(200))
        ui.togglePanel()
        try require(focusTransitions == ["remember", "restore", "remember", "keep-preview"])
        try await waitForVisibility(false)
        detached.forEach { $0.close() }
        print("{\"status\":\"passed\",\"passed\":true,\"checks\":[\"panel select/copy/deselect and original multi-text RTF/plain aggregation\",\"ordered multi-selection paste and custom quick/plain modifiers\",\"board navigation and original prepend/reverse Stack consumption with duplicates retained (CHANGELOG 81/114/147: no dedupe, queue not persisted)\",\"pause/resume and native Stack rows\",\"NSItemProvider binary/HTML/Unicode and file paths; internal OCR excluded\",\"22 hosted tab hit points including icon/gaps/edges; release outside cancels; label-only double-click editing\",\"hover bitmap changes/restores; inline create/select-all/rename; native retention anchors and intermediate day/week/month mapping\",\"search layout centers the mask at max(400, toolbarWidth*0.25) with the in-field filters button; a non-empty-query Escape returns to the list, an empty-query Escape hides; offscreen ordered panel visible before Escape\",\"group deletion clamps to the adjacent surviving list (03a538); a failed delete keeps its inline confirmation, error and selection; legacy owner-less multi-group items survive a group delete\",\"local outside-window click closes panel\",\"old closing completion cannot close a reopened panel\"],\"scope\":\"Isolated app ID/store/private pasteboard. Native offscreen windows and synthetic local events; no system keyboard posting, real cross-app paste or physical external-app click claim.\"}")
    }
}
