import AppKit
import Foundation
import BlinkClipCore

@main
struct PanelScrollHarness {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BlinkClipScroll-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardStore(directoryURL: directory)
        store.preferences.historyRetentionDays = 0
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        memset(bitmap.bitmapData!, 128, bitmap.bytesPerRow * bitmap.pixelsHigh)
        let png = bitmap.representation(using: .png, properties: [:])!
        let original = PasteboardItem()
        original.setData(png, forType: "public.png")
        let metadata = ImagePreviewMetadataGenerator.previewMetadata([original])!
        store.items = (0..<120).map {
            ClipboardItem(title: "Generated \($0)", kind: .image, payloads: ["public.png": png], imagePreviewMetadata: metadata)
        }
        precondition(store.items.allSatisfy { $0.decodedImagePreviewMetadata != nil })
        try store.save()
        let ui = ReplicaUIController(store: store)
        defer { ui.panel.orderOut(nil) }
        ui.showPanel()
        if let screen = NSScreen.main { ui.panel.setFrameOrigin(.init(x: screen.frame.maxX + 200, y: screen.frame.maxY + 200)) }
        try await Task.sleep(for: .milliseconds(250))
        func collection(in view: NSView) -> ReplicaNativeCollectionHost? {
            if let view = view as? ReplicaNativeCollectionHost { return view }
            return view.subviews.lazy.compactMap { collection(in: $0) }.first
        }
        let host = collection(in: ui.panel.contentView!)!
        let scroll = host.subviews.first as! NSScrollView
        var samples: [Double] = []
        for cycle in 0..<3 {
            let start = ProcessInfo.processInfo.systemUptime
            for i in 0..<600 {
                let x = CGFloat(i % 200) * 0.25
                scroll.contentView.setBoundsOrigin(.init(x: x, y: 0))
                NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
                if i % 30 == 0 { host.layoutSubtreeIfNeeded() }
            }
            let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
            if cycle > 0 { samples.append(ms) }
        }
        let maxX = scroll.documentView!.frame.width - scroll.contentView.bounds.width
        for i in 0..<40 {
            scroll.contentView.setBoundsOrigin(.init(x: min(maxX, CGFloat(i) * 100), y: 0))
            host.layoutSubtreeIfNeeded()
        }
        precondition(scroll.contentView.bounds.origin.x > 0 && !scroll.documentView!.subviews.isEmpty)
        let visible = ui.state.visibleItems
        for cell in scroll.documentView!.subviews where cell.frame.intersects(scroll.contentView.bounds) {
            let index = Int(((cell.frame.minX - 24) / (cell.frame.width + 24)).rounded())
            precondition(visible.indices.contains(index))
            precondition(host.previewAnchor(for: visible[index].id, revealIfNeeded: false) === cell)
        }
        precondition(host.previewAnchor(for: visible[0].id, revealIfNeeded: false) == nil)
        // V3: 呼出面板时横向位置回到初始态；同一会话内的手动滚动只有 show 才会重置。
        // 先造出溢出的分组标签条，覆盖面板里另一个横向 NSScrollView。
        var lastPinboard: Pinboard?
        for index in 0..<24 {
            lastPinboard = try store.createPinboard(name: "Scroll fixture \(index)", colorHex: "#3366AA")
        }
        try await Task.sleep(for: .milliseconds(300))
        ui.panel.contentView!.layoutSubtreeIfNeeded()
        func containsTab(_ view: NSView) -> Bool {
            if view is PinboardTabView { return true }
            return view.subviews.contains(where: containsTab)
        }
        func tabBarScrollView(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               containsTab(document) { return scroll }
            return view.subviews.lazy.compactMap { tabBarScrollView(in: $0) }.first
        }
        func presentForResetCheck() async throws {
            ui.showPanel()
            if let screen = NSScreen.main {
                ui.panel.setFrameOrigin(.init(x: screen.frame.maxX + 200, y: screen.frame.maxY + 200))
            }
            try await Task.sleep(for: .milliseconds(450))
            precondition(ui.panel.isVisible)
        }
        func hideForResetCheck() async throws {
            ui.hidePanel()
            let deadline = Date().addingTimeInterval(3)
            while ui.panel.isVisible, Date() < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            precondition(!ui.panel.isVisible)
        }
        precondition(scroll.contentView.bounds.origin.x > 0)
        guard let tabScroll = tabBarScrollView(in: ui.panel.contentView!) else {
            preconditionFailure("标签条的 NSScrollView 没找到")
        }
        tabScroll.documentView!.layoutSubtreeIfNeeded()
        let tabMaximumX = tabScroll.documentView!.frame.width - tabScroll.contentView.bounds.width
        precondition(tabMaximumX > 60, "溢出标签条 fixture 宽度不足：\(tabMaximumX)")
        tabScroll.contentView.setBoundsOrigin(.init(x: 60, y: 0))
        precondition(tabScroll.contentView.bounds.origin.x > 0)
        try await hideForResetCheck()
        try await presentForResetCheck()
        // 面板复用同一个原生集合视图：不是"重建后碰巧为 0"。
        precondition(collection(in: ui.panel.contentView!) === host)
        precondition(scroll.contentView.bounds.origin.x == 0,
            "召唤面板必须把卡片行横向偏移重置为 0，实际 \(scroll.contentView.bounds.origin.x)")
        // 标签条归零后把当前选中（历史）标签滚回可见；历史标签在最左，所以偏移就是 0。
        precondition(tabScroll.contentView.bounds.origin.x == 0,
            "召唤面板必须把标签条横向偏移重置到初始态，实际 \(tabScroll.contentView.bounds.origin.x)")
        // 同一会话内用户自己滚动后，后续布局/通知不得再把它拉回 0。
        scroll.contentView.setBoundsOrigin(.init(x: 640, y: 0))
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        host.layoutSubtreeIfNeeded()
        precondition(scroll.contentView.bounds.origin.x == 640,
            "同一会话内滚动不应被重置，实际 \(scroll.contentView.bounds.origin.x)")
        tabScroll.contentView.setBoundsOrigin(.init(x: 60, y: 0))
        try await Task.sleep(for: .milliseconds(250))
        precondition(tabScroll.contentView.bounds.origin.x == 60,
            "同一会话内标签条滚动不应被重置，实际 \(tabScroll.contentView.bounds.origin.x)")
        // 再次召唤仍然回到 0。
        try await hideForResetCheck()
        try await presentForResetCheck()
        precondition(scroll.contentView.bounds.origin.x == 0,
            "再次召唤必须重新归零，实际 \(scroll.contentView.bounds.origin.x)")
        precondition(scroll.contentView.bounds.origin.y == 0)
        // 切换分组后标签条会滚到选中项（既有行为）；呼出归位后选中项仍然可见，
        // 说明标签条的"初始态"是按当前选中分组算的，而不是硬拉回 0。
        if let lastPinboard {
            ui.state.chooseBoard(lastPinboard.id)
            try await Task.sleep(for: .milliseconds(350))
            ui.panel.contentView!.layoutSubtreeIfNeeded()
            precondition(tabScroll.contentView.bounds.origin.x > 0,
                "切换分组后标签条应滚动到选中标签，实际 \(tabScroll.contentView.bounds.origin.x)")
            tabScroll.contentView.setBoundsOrigin(.init(x: 0, y: 0))
            try await hideForResetCheck()
            try await presentForResetCheck()
            try await Task.sleep(for: .milliseconds(250))
            ui.panel.contentView!.layoutSubtreeIfNeeded()
            precondition(tabScroll.contentView.bounds.origin.x > 0,
                "呼出归位后选中标签仍应可见，实际 \(tabScroll.contentView.bounds.origin.x)")
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["passed": true,
            "stationary_viewport_600_changes_ms": samples, "synthetic_image_items":120,
            "presentation_scroll_reset": "show → scroll x=640 → show → x=0; same-session scroll preserved",
            "scope":"Temporary store, generated images, offscreen native panel; programmatic clip bounds, not physical trackpad or original runtime benchmark."], options:[.sortedKeys]), as:UTF8.self))
    }
}
