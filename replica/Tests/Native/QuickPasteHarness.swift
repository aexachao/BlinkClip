import AppKit
import Foundation
import SwiftUI
import BlinkClipCore

/// 快捷粘贴排序回归：真实 `ReplicaUIController` / `ClipboardStore` / `ClipboardMonitor`，
/// 私有具名剪贴板 + 独立数据目录。覆盖历史列表与分组列表的三条粘贴路径
/// （双击 / ⌘1–9 / 右键「粘贴」），断言：
/// ① 粘贴不新增历史条目（监控运行，写回不得被自捕获成重复项）；
/// ② 粘贴后该条在历史列表和分组列表都位于首位（分组用持久化 `pinboardOrder`）；
/// ③ 数字键路径的置顶来自显式的共享粘贴成功分支，不再依赖捕获副作用。
@main
struct QuickPasteHarness {
    struct Failure: Error, CustomStringConvertible { let description: String }

    @MainActor static func main() async {
        do { try await run() } catch {
            let payload: [String: Any] = ["status": "failed", "reason": String(describing: error)]
            print(String(data: try! JSONSerialization.data(withJSONObject: payload), encoding: .utf8)!)
            exit(1)
        }
    }

    @MainActor static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(description: message) }
    }

    @MainActor static func waitForCollectionReady(_ ui: ReplicaUIController, _ state: ReplicaUIState,
                                                   expectedItemCount: Int) async throws {
        let panel = ui.panel
        let deadline = Date().addingTimeInterval(5)
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
        throw Failure(description: "Collection not ready: owner=\(owner != nil) applied=\(String(describing: applied)) "
            + "visible=\(state.visibleItems.count) expected=\(expectedItemCount) focused=\(focused)")
    }

    @MainActor static func run() async throws {
        let app = NSApplication.shared
        app.finishLaunching()
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()
            .appending("BlinkClipQuickPaste-\(UUID().uuidString)"))
        try? FileManager.default.removeItem(at: directory)
        let board = NSPasteboard(name: .init("BlinkClipQuickPaste-\(UUID().uuidString)"))
        let defaults = UserDefaults(suiteName: "blinkclip.quickpaste.\(UUID().uuidString)")!
        let store = try ClipboardStore(directoryURL: directory)
        store.preferences.historyRetentionDays = 30
        store.preferences.quickPasteModifierRawValue = NSEvent.ModifierFlags.command.rawValue
        store.preferences.plainTextModifierRawValue = NSEvent.ModifierFlags.shift.rawValue

        let texts = ["FIXTURE-1 oldest", "FIXTURE-2", "FIXTURE-3", "FIXTURE-4 newest"]
        let base = Date().addingTimeInterval(-3600)
        var seedIDs: [UUID] = []
        for (offset, text) in texts.enumerated() {
            let item = ClipboardItem(createdAt: base.addingTimeInterval(Double(offset)),
                                     title: text, plainText: text,
                                     payloads: ["public.utf8-plain-text": Data(text.utf8)])
            seedIDs.append(try store.add(item))
        }
        let pin = try store.createPinboard(name: "Quick Paste pin", colorHex: "#00AAFF")
        try store.assign(ids: [seedIDs[0], seedIDs[1]], to: pin.id)
        try store.reorderItems(ids: [seedIDs[0], seedIDs[1]], in: pin.id, toOffset: 0)

        // 与生产实例一致：监控常开，粘贴写回若被自捕获，1.2s 内一定会新增条目。
        let monitor = ClipboardMonitor(store: store, pasteboard: board, defaults: defaults)
        monitor.start()
        defer { monitor.stop() }

        let ui = ReplicaUIController(store: store)
        ui.pasteboard = board
        let state = ui.state
        var delivered: [([UUID], Bool)] = []
        ui.pasteItemsHandler = { ids, plain in
            delivered.append((ids, plain))
            do {
                // 与 `AppMain.paste` 同一条写入 / 恢复路径（含恢复时间戳刷新）。
                try store.writeToPasteboard(ids: ids, pasteboard: board, plainTextOnly: plain)
                ui.hidePanel()
                return true
            } catch { return false }
        }

        guard let screen = NSScreen.main else { throw Failure(description: "No window-server screen") }
        func waitForVisibility(_ expected: Bool) async throws {
            let deadline = Date().addingTimeInterval(3)
            while ui.panel.isVisible != expected && Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            try require(ui.panel.isVisible == expected, "panel visibility \(ui.panel.isVisible) != \(expected)")
        }
        func presentOffscreen() async throws {
            ui.showPanel()
            ui.panel.setFrameOrigin(.init(x: screen.frame.maxX + 200, y: screen.frame.maxY + 200))
            try await waitForVisibility(true)
            try await Task.sleep(nanoseconds: 250_000_000)
        }
        func key(_ code: UInt16, _ chars: String, _ modifiers: NSEvent.ModifierFlags) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: ui.panel.windowNumber,
                                        context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            ui.panel.sendEvent(event)
        }
        func presentHistory() async throws {
            if ui.panel.isVisible { ui.hidePanel(); try await waitForVisibility(false) }
            try await presentOffscreen()
            state.chooseBoard(nil)
            try await waitForCollectionReady(ui, state, expectedItemCount: 4)
        }
        func presentPinboard() async throws {
            if ui.panel.isVisible { ui.hidePanel(); try await waitForVisibility(false) }
            try await presentOffscreen()
            state.chooseBoard(pin.id)
            try await waitForCollectionReady(ui, state, expectedItemCount: 2)
        }
        /// 越过 ClipboardMonitor 的 0.25s 轮询 + 0.3s 同步定时器。
        func settle() async throws {
            if ui.panel.isVisible { try await waitForVisibility(false) }
            try await Task.sleep(nanoseconds: 1_200_000_000)
        }
        func duplicateCount(_ text: String) -> Int {
            store.items.filter { ($0.plainText ?? "") == text }.count
        }
        func historyFirstID() -> UUID? {
            store.search(query: "", pinboardID: nil).first?.id
        }
        func pinFirstID() -> UUID? {
            store.items(in: pin.id).first?.id
        }
        func doubleClick(_ target: UUID) throws {
            guard let host = (ui.panel as? ReplicaPanel)?.collectionFocusTarget as? ReplicaNativeCollectionHost,
                  let cell = host.previewAnchor(for: target) else {
                throw Failure(description: "Missing native card cell for \(target)")
            }
            let point = NSPoint(x: cell.bounds.midX, y: cell.bounds.midY)
            func mouse(_ type: NSEvent.EventType, clicks: Int) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: cell.convert(point, to: nil), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: ui.panel.windowNumber,
                    context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
            }
            host.mouseDown(with: mouse(.leftMouseDown, clicks: 1))
            host.mouseUp(with: mouse(.leftMouseUp, clicks: 1))
            host.mouseDown(with: mouse(.leftMouseDown, clicks: 2))
            host.mouseUp(with: mouse(.leftMouseUp, clicks: 2))
        }
        /// `reorderItems` 保留被移动条目的当前相对顺序，所以用「只移动第一条到首位」
        /// 才能把顺序复位成 [seed0, seed1]。
        func resetPinOrder() throws {
            try store.reorderItems(ids: [seedIDs[0]], in: pin.id, toOffset: 0)
        }

        let baselineCount = store.items.count
        try require(baselineCount == 4, "fixture history count \(baselineCount) != 4")

        // ① 历史列表：⌘4 = 第 4 张（最旧的一张）。
        try await presentHistory()
        key(21, "4", .command)
        try await settle()
        try require(store.items.count == 4, "⌘4 created a duplicate history entry: \(store.items.count)")
        try require(historyFirstID() == seedIDs[0], "⌘4 did not put the pasted item first in history")
        try require(duplicateCount(texts[0]) == 1, "⌘4 duplicated FIXTURE-1 content")

        // ② 历史列表：原生卡片双击。
        try await presentHistory()
        try doubleClick(seedIDs[2])
        try await settle()
        try require(store.items.count == 4, "double click created a duplicate history entry: \(store.items.count)")
        try require(historyFirstID() == seedIDs[2], "double click did not put the pasted item first in history")
        try require(duplicateCount(texts[2]) == 1, "double click duplicated FIXTURE-3 content")

        // ③ 历史列表：右键菜单「粘贴」。
        try await presentHistory()
        state.select(store.items.first { $0.id == seedIDs[1] }!)
        ui.pasteSelection(plainTextOnly: false)
        try await settle()
        try require(store.items.count == 4, "context paste created a duplicate history entry: \(store.items.count)")
        try require(historyFirstID() == seedIDs[1], "context paste did not put the pasted item first in history")
        try require(duplicateCount(texts[1]) == 1, "context paste duplicated FIXTURE-2 content")

        // ④ 分组列表：⌘2 = 第二张；置顶必须来自共享的成功分支并持久化。
        try await presentPinboard()
        try require(pinFirstID() == seedIDs[0], "pinboard fixture order changed before ⌘2")
        key(19, "2", .command)
        try await settle()
        try require(pinFirstID() == seedIDs[1], "⌘2 did not move the pasted item to the pinboard front")
        try require(store.items.count == 4, "⌘2 created a duplicate history entry: \(store.items.count)")
        try require(duplicateCount(texts[1]) == 1, "⌘2 duplicated FIXTURE-2 content")

        // ⑤ 分组列表：双击同样置顶。
        try resetPinOrder()
        try await presentPinboard()
        try require(pinFirstID() == seedIDs[0], "pinboard fixture order did not reset before the double click")
        try doubleClick(seedIDs[1])
        try await settle()
        try require(pinFirstID() == seedIDs[1], "double click did not move the pasted item to the pinboard front")
        try require(store.items.count == 4, "pinboard double click created a duplicate history entry: \(store.items.count)")

        // ⑥ 分组列表：右键「粘贴」同样置顶。
        try resetPinOrder()
        try await presentPinboard()
        try require(pinFirstID() == seedIDs[0], "pinboard fixture order did not reset before the context paste")
        state.select(store.items.first { $0.id == seedIDs[1] }!)
        ui.pasteSelection(plainTextOnly: false)
        try await settle()
        try require(pinFirstID() == seedIDs[1], "context paste did not move the pasted item to the pinboard front")
        try require(store.items.count == 4, "pinboard context paste created a duplicate history entry: \(store.items.count)")

        // ⑦ 数字键路径不再依赖剪贴板写回/自捕获副作用：把粘贴 handler 换成只记录、
        // 不写剪贴板的版本，⌘2 仍必须显式把该条移到分组首位。
        try resetPinOrder()
        try await presentPinboard()
        try require(pinFirstID() == seedIDs[0], "pinboard fixture order changed before the no-write ⌘2")
        ui.pasteItemsHandler = { ids, plain in
            delivered.append((ids, plain))
            ui.hidePanel()
            return true
        }
        key(19, "2", .command)
        try await settle()
        try require(pinFirstID() == seedIDs[1], "⌘2 relied on a clipboard write side effect for reordering")
        try require(store.items.count == 4, "the no-write ⌘2 changed the history count: \(store.items.count)")

        // ⑧ 重排已持久化：重新打开同一数据目录仍是置顶顺序。
        let reopened = try ClipboardStore(directoryURL: directory)
        try require(reopened.items(in: pin.id).first?.id == seedIDs[1], "pinboard order was not persisted")

        let checks: [String] = [
            "⌘1–9 quick paste refreshes the history position without creating a duplicate history entry",
            "the native double click pastes once and does not create a duplicate history entry",
            "the right-click paste does not create a duplicate history entry",
            "⌘1–9, double click and right-click paste all move the item to the pinboard front through the shared paste success branch",
            "⌘1–9 still reorders when the paste handler does not write the clipboard at all, so it does not depend on self-capture or restore side effects",
            "the pinboard reorder is persisted across a store reopen",
            "the clipboard monitor runs throughout, so the no-duplicate assertions cover self-capture",
        ]
        let summary: [String: Any] = [
            "status": "passed",
            "passed": true,
            "baseline_count": baselineCount,
            "final_count": store.items.count,
            "delivered_count": delivered.count,
            "checks": checks,
        ]
        print(String(data: try JSONSerialization.data(withJSONObject: summary), encoding: .utf8)!)
        ui.panel.orderOut(nil)
    }
}
