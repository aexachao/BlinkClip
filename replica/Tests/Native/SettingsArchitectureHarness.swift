import AppKit
import Foundation
import SwiftUI
import BlinkClipCore
import BlinkClipCapture

@MainActor private final class OffscreenSettingsWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@main struct SettingsArchitectureHarness {
    struct Failure: Error { let message: String }
    static var assertions = 0
    @MainActor static var captures: [(String, NSImage)] = []
    static func check(_ value: Bool, _ message: String) throws {
        assertions += 1
        if !value { throw Failure(message: message) }
    }
    @MainActor static func pause() async { try? await Task.sleep(nanoseconds: 250_000_000) }
    @MainActor static func capture(_ view: NSView, name: String, out: URL) throws {
        guard ProcessInfo.processInfo.environment["BLINKCLIP_SKIP_SCREENSHOTS"] != "1" else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(message: "no bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if ProcessInfo.processInfo.environment["BLINKCLIP_SETTINGS_CLIPBOARD_SCREENSHOTS_ONLY"] == "1",
           !name.contains("-3-") { return }
        captures.append((name, NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size)))
    }
    @MainActor static func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
    }
    @MainActor static func pixels(_ view: NSView, headerOnly: Bool) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let target: NSView
        if headerOnly {
            guard let frameView = view.window?.contentView?.superview,
                  let label = descendants(frameView, of: NSTextField.self).first(where: { $0.accessibilityIdentifier() == "BlinkClipSettingsPaneTitle" }) else {
                throw Failure(message: "native toolbar title missing")
            }
            target = label
        } else { target = view }
        guard let bitmap = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { throw Failure(message: "no navigation bitmap") }
        target.cacheDisplay(in: target.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "no navigation PNG") }
        return data
    }
    /// Renders the hosted view and returns the sRGB pixel at a screen point.
    /// Used only for the six-page surface checks: the card must be brighter than
    /// the page in both appearances, which the semantic colors alone cannot prove.
    @MainActor static func renderedColor(_ view: NSView, atScreen point: NSPoint) -> NSColor? {
        guard let window = view.window,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let local = view.convert(window.convertPoint(fromScreen: point), from: nil)
        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, view.bounds.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, view.bounds.height)
        let px = Int(local.x * scaleX)
        let py = Int((view.isFlipped ? local.y : view.bounds.height - local.y) * scaleY)
        guard px >= 0, py >= 0, px < bitmap.pixelsWide, py < bitmap.pixelsHigh else { return nil }
        return bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB)
    }

    @MainActor static func grayLevel(_ color: NSColor) -> Int {
        Int(((color.usingColorSpace(.sRGB)?.redComponent ?? 0) * 255).rounded())
    }

    @MainActor static func accessibilityTree(_ element: Any) -> [NSObject] {
        var seen = Set<ObjectIdentifier>()
        func visit(_ value: Any) -> [NSObject] {
            guard let node = value as? NSObject, seen.insert(ObjectIdentifier(node)).inserted else { return [] }
            let selector = NSSelectorFromString("accessibilityChildren")
            let children = node.responds(to: selector)
                ? (node.perform(selector)?.takeUnretainedValue() as? [Any] ?? []) : []
            let legacy = node.accessibilityAttributeValue(.children) as? [Any] ?? []
            let views = (node as? NSView)?.subviews ?? []
            return [node] + (children + legacy + views).flatMap(visit)
        }
        return visit(element)
    }
    @MainActor static func axID(_ element: NSObject) -> String? {
        let selector = NSSelectorFromString("accessibilityIdentifier")
        return (element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() as? String : nil)
            ?? element.accessibilityAttributeValue(.identifier) as? String
    }
    @MainActor static func axFrame(_ element: NSObject) -> NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        if element.responds(to: selector) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
            return unsafeBitCast(element.method(for: selector), to: Getter.self)(element, selector)
        }
        let point = (element.accessibilityAttributeValue(.position) as? NSValue)?.pointValue ?? .zero
        let size = (element.accessibilityAttributeValue(.size) as? NSValue)?.sizeValue ?? .zero
        return NSRect(origin: point, size: size)
    }
    @MainActor static func press(_ node: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard node.responds(to: selector) else { return false }
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(node.method(for: selector), to: Press.self)(node, selector)
    }
    @MainActor static var firstElementOffsets: [String: CGFloat] = [:]

    /// Per-page surface + geometry contract (top-aligned pages):
    /// - every page starts at the same fixed top offset: the gap above the first
    ///   content element is `SettingsPageMetrics.topInset` (16pt) within 0.5pt,
    ///   whether the page fits one screen or not; there is no "centre it if it
    ///   fits" rule any more (the previous round's page-level centring is gone);
    /// - a page whose content is taller than the visible area scrolls from that
    ///   same 16pt offset; scrolled to the bottom its last element sits
    ///   `bottomInset` (20pt) above the content area's bottom;
    /// - row alignment is measured separately (`checkRowAlignment`): the trailing
    ///   switch's frame centre must sit on the row text block's centre (<=0.5pt);
    /// - the rendered card is brighter than the page margin in both appearances;
    /// - the retention grid is one fixed 4-column grid (10pt gaps, empty last cell);
    /// - the AI connect action sits inside its status card and aligns with the title;
    /// - the iCloud summary sits under the title with >=12pt to the switch;
    /// - reset-all shortcuts is below the last card, not at the top right.
    /// 内容块在屏幕坐标里的上下边界：内容区里所有「比一屏矮」的无障碍元素的并集
    /// 边界。比一屏高的元素是滚动容器/文档视图本身，排除；页尾动作等零散元素因此
    /// 也算进内容块，不会被漏算。
    @MainActor static func contentEdges(_ hosting: NSView, window: NSWindow) -> (top: CGFloat, bottom: CGFloat)? {
        let contentTop = window.convertPoint(toScreen: NSPoint(x: 0, y: window.contentLayoutRect.maxY)).y
        let contentBottom = window.convertPoint(toScreen: NSPoint(x: 0, y: window.contentLayoutRect.minY)).y
        let viewportHeight = window.contentLayoutRect.height
        // 只量右侧内容列：无障碍树里也有侧栏的表格行，它们的 y 落在内容区里，
        // 但 x 在 200pt 宽的侧栏内。内容列左边 = 卡片左边（卡片距内容区左 20pt）。
        let cards = accessibilityTree(hosting).filter { axID($0) == "settings.card" }
            .map { axFrame($0) }.filter { $0.width > 10 }
        let detailLeft = cards.map(\.minX).min() ?? contentTop
        let frames = accessibilityTree(hosting).compactMap { node -> NSRect? in
            let frame = axFrame(node)
            guard frame.height > 2, frame.width > 2, frame.height < viewportHeight - 1 else { return nil }
            guard frame.minX >= detailLeft - 1 else { return nil }
            // 贴着内容区上下边的元素是滚动条一类的 chrome（其 AX 帧可能越界 1pt），
            // 真正的内容块至少离边 16pt；这一条把它们排除在内容块之外。
            guard frame.maxY <= contentTop - 8, frame.minY >= contentBottom + 8 else { return nil }
            return frame
        }
        guard let top = frames.map(\.maxY).max(), let bottom = frames.map(\.minY).min() else { return nil }
        return (top, bottom)
    }

    /// 648×600（出货窗口尺寸）下六页的内容高度分类：全部只影响「是否滚动」，
    /// 不影响首元素位置——页面一律从顶部 16pt 起排。实测值见 `pageGeometry`。
    @MainActor static var pageGeometry: [String: [String: Double]] = [:]
    /// 行内对齐的逐行实测值（文字块中线、开关中线、偏差），写进结果 JSON。
    @MainActor static var rowAlignmentGeometry: [String: [[String: Any]]] = [:]
    /// 卡片内容垂直居中的逐卡实测值（卡顶→首行墨迹顶、末行墨迹底→卡底、差值）。
    @MainActor static var cardCentringGeometry: [String: [[String: Any]]] = [:]
    /// 关于页的实测值（页顶 → 卡片顶、卡片内容上下留白、状态行与按钮间距）。
    @MainActor static var aboutGeometry: [String: [String: Double]] = [:]

    @MainActor static func checkPageSurface(hosting: NSView, window: NSWindow, section: SettingsSection,
                                            appearance: String) async throws {
        let tree = accessibilityTree(hosting)
        func node(_ identifier: String, height: CGFloat? = nil) -> NSRect? {
            tree.filter { axID($0) == identifier }
                .map { axFrame($0) }
                .filter { height == nil || abs($0.height - height!) < 1 }
                .max { $0.width < $1.width }
        }
        let cardRects = tree.filter { axID($0) == "settings.card" }.map { axFrame($0) }.filter { $0.width > 10 }
        try check(!cardRects.isEmpty, "\(appearance) \(section) renders no settings card")
        let titleRects = tree.filter { axID($0) == "settings.section-title" }.map { axFrame($0) }.filter { $0.width > 10 }
        let contentTop = window.convertPoint(toScreen: NSPoint(x: 0, y: window.contentLayoutRect.maxY)).y
        let contentBottom = window.convertPoint(toScreen: NSPoint(x: 0, y: window.contentLayoutRect.minY)).y
        let viewportHeight = window.contentLayoutRect.height
        // 内容块的上下边界：取内容区里所有「比一屏矮」的无障碍元素的并集边界。
        // 比一屏高的元素是滚动容器/文档视图本身，排除掉；这样页尾动作（例如
        // 「清空历史记录…」）也算进内容块，居中与否不会被漏算的元素歪曲。
        guard let edges = contentEdges(hosting, window: window) else {
            throw Failure(message: "\(appearance) \(section) has no content elements")
        }
        let offset = contentTop - edges.top
        let bottomGap = edges.bottom - contentBottom
        firstElementOffsets["\(appearance)-\(section.rawValue)"] = offset

        // 这一个分区的内容装得下/装不下一屏：文档视图高度对可视高度的实测值，
        // 不是从「哪一页应该居中」反推出来的。
        let pageScroll = descendants(hosting, of: NSScrollView.self)
            .filter { $0.documentView != nil }
            .max { $0.contentView.bounds.height < $1.contentView.bounds.height }
        guard let pageScroll else { throw Failure(message: "\(appearance) \(section) has no page scroll view") }
        let documentHeight = pageScroll.documentView?.bounds.height ?? 0
        let fitsOneScreen = documentHeight <= viewportHeight + 0.5
        pageGeometry["\(appearance)-\(section.rawValue)"] = [
            "topGap": Double((offset * 100).rounded() / 100),
            "bottomGap": Double((bottomGap * 100).rounded() / 100),
            "documentHeight": Double(documentHeight),
            "viewportHeight": Double(viewportHeight),
            "fitsOneScreen": fitsOneScreen ? 1 : 0,
        ]
        try check(abs(offset - SettingsPageMetrics.topInset) <= 0.5,
                  "\(appearance) \(section) first element offset \(offset) is not the fixed \(SettingsPageMetrics.topInset)pt top inset")
        // 页面级居中已撤销：任何页都不再按「装得下/装不下」改首元素位置。
        // 装得下只意味着不需要滚动；装不下才滚动，但起点仍是同一个 16pt。
        if fitsOneScreen {
            try check(bottomGap >= SettingsPageMetrics.bottomInset - 1,
                      "\(appearance) \(section) bottom inset \(bottomGap) is under the \(SettingsPageMetrics.bottomInset)pt page inset")
        } else {
            try check(pageScroll.contentView.bounds.origin.y == 0,
                      "\(appearance) \(section) does not start at the top: origin \(pageScroll.contentView.bounds.origin.y)")
        }

        // Rendered surface: sample the card fill in the top-right padding and the
        // page margin just left of it. Pixel levels are 8-bit sRGB gray.
        guard let card = cardRects.max(by: { $0.maxY < $1.maxY }) else { throw Failure(message: "no card") }
        guard let cardColor = renderedColor(hosting, atScreen: NSPoint(x: card.minX + 4, y: card.midY)),
              let pageColor = renderedColor(hosting, atScreen: NSPoint(x: card.minX - 8, y: card.midY)) else {
            throw Failure(message: "\(appearance) \(section) surface pixel out of bounds")
        }
        let cardLevel = grayLevel(cardColor), pageLevel = grayLevel(pageColor)
        try check(cardLevel > pageLevel,
                  "\(appearance) \(section) rendered card is not brighter than the page: card \(cardLevel) page \(pageLevel)")
        try check(cardLevel - pageLevel >= 8,
                  "\(appearance) \(section) rendered card/page separation \(cardLevel - pageLevel) is under 8 levels")

        if section == .clipboard {
            // The retention tiles are AppKit buttons inside an NSViewRepresentable:
            // AX frames carry a 1pt focus-ring outset, so the fixed-grid assertion
            // reads the real button frames (all in the HistoryCapacityControl).
            let tileButtons = descendants(hosting, of: NSButton.self)
                .filter { $0.accessibilityIdentifier().hasPrefix("history-retention-") }
            try check(tileButtons.count == 7, "retention grid exposes \(tileButtons.count) tiles")
            let frames = Dictionary(uniqueKeysWithValues: tileButtons.map {
                ($0.accessibilityIdentifier(), $0.convert($0.bounds, to: nil))
            })
            let widths = Set(frames.values.map { ($0.width * 2).rounded() / 2 })
            try check(widths.count == 1, "retention tiles have different widths: \(widths.sorted())")
            // 窗口坐标 y 向上：视觉第一行是 y 更大的那一行。
            let rows = Dictionary(grouping: frames.values) { Int($0.minY.rounded()) }.sorted { $0.key > $1.key }
            try check(rows.count == 2, "retention grid has \(rows.count) rows: \(rows.map(\.key))")
            let topRow = rows[0].value.sorted { $0.minX < $1.minX }
            let bottomRow = rows[1].value.sorted { $0.minX < $1.minX }
            try check(topRow.count == 4 && bottomRow.count == 3,
                      "retention rows are \(topRow.count) + \(bottomRow.count), expected 4 + 3")
            for row in [topRow, bottomRow] {
                for pair in zip(row, row.dropFirst()) {
                    try check(abs((pair.1.minX - pair.0.maxX) - HistoryCapacityControl.tileSpacing) < 0.01,
                              "retention column gap \(pair.1.minX - pair.0.maxX) is not 10pt: \(row.map(\.minX))")
                }
            }
            for (index, tile) in bottomRow.enumerated() {
                try check(abs(tile.minX - topRow[index].minX) < 0.01,
                          "retention row 2 column \(index) is not aligned: \(tile.minX) vs \(topRow[index].minX)")
            }
            // 窗口坐标 y 向上：上行的 minY 减下行的 maxY 才是两行之间的空隙。
            let verticalGap = topRow[0].minY - bottomRow[0].maxY
            try check(abs(verticalGap - HistoryCapacityControl.tileSpacing) < 0.01,
                      "retention row gap \(verticalGap) is not 10pt")
            try check(!bottomRow.contains { abs($0.minX - topRow[3].minX) < 1 },
                      "retention row 2 does not leave the fourth cell empty")
            try check(abs(bottomRow[2].maxX - topRow[2].maxX) < 0.01,
                      "retention row 2 ends in the wrong column: \(bottomRow[2].maxX) vs \(topRow[2].maxX)")
            try check(abs((topRow[0].maxY - bottomRow[0].minY) - HistoryCapacityControl.gridHeight) < 0.01,
                      "retention grid height is not \(HistoryCapacityControl.gridHeight)pt")
        }

        if section == .ai {
            guard let connect = node("settings.mcp.connect"), let status = node("settings.mcp.status"),
                  let description = node("settings.mcp.description") else {
                throw Failure(message: "AI page is missing connect/status/description elements")
            }
            try check(card.insetBy(dx: -1, dy: -1).contains(connect),
                      "connect button is outside the status card: button \(connect) card \(card)")
            try check(abs(description.minX - status.minX) <= 0.5,
                      "AI description is not left-aligned with the status title: \(description.minX) vs \(status.minX)")
        }

        if section == .general {
            guard let title = node("settings.icloud.title"), let summary = node("settings.icloud.summary"),
                  let toggle = node("settings.icloud.toggle") else {
                throw Failure(message: "iCloud row is missing title/summary/switch elements")
            }
            try check(summary.maxY < title.maxY,
                      "iCloud summary is not below the row title: summary \(summary) title \(title)")
            let gap = toggle.minX - max(title.maxX, summary.maxX)
            try check(gap >= 11.5, "iCloud switch is \(gap)pt from the row text, expected >=12pt")
        }

        if section == .shortcuts {
            guard let reset = node("settings.reset-all-shortcuts") else {
                throw Failure(message: "shortcuts page is missing reset-all")
            }
            let lastCardBottom = cardRects.map(\.minY).min() ?? 0
            try check(reset.maxY <= lastCardBottom + 1,
                      "reset-all is not below the last card: reset \(reset) last card bottom \(lastCardBottom)")
        }

        if section == .clipboard {
            // 「清空历史记录…」与「恢复全部快捷键…」同一区域策略：内容区底部、右对齐，
            // 不挤进卡片正文；危险性质只用系统红做语义强调。
            guard let clear = node("settings.clear-history") else {
                throw Failure(message: "clipboard page is missing the clear-history footer action")
            }
            let lastCardBottom = cardRects.map(\.minY).min() ?? 0
            try check(clear.maxY <= lastCardBottom + 1,
                      "clear-history is not below the last card: clear \(clear) last card bottom \(lastCardBottom)")
            try check(clear.maxX >= (cardRects.map(\.maxX).max() ?? 0) - 2,
                      "clear-history is not right-aligned with the cards: clear \(clear)")
        }

        if section == .privacy {
            // 「刷新状态」在「系统权限」卡片的标题行里：与标题同一行、右对齐、压在卡片上方。
            guard let refresh = node("permission-refresh-status") else {
                throw Failure(message: "privacy page is missing the card-title refresh control")
            }
            guard let title = titleRects.min(by: { abs($0.midY - refresh.midY) < abs($1.midY - refresh.midY) }) else {
                throw Failure(message: "privacy page has no card title to hold the refresh control")
            }
            try check(abs(refresh.midY - title.midY) <= 3,
                      "refresh control is not on the card title line: refresh \(refresh) title \(title)")
            try check(refresh.minY >= card.maxY - 1,
                      "refresh control is not above the permissions card: refresh \(refresh) card \(card)")
            try check(abs(card.maxX - refresh.maxX) <= 2,
                      "refresh control is not right-aligned with the card: refresh \(refresh) card \(card)")
        }
    }

    // MARK: - 卡片内容垂直居中（墨迹带，≤0.5pt）

    /// 卡片「可见内容带」的两条留白：卡顶 → 首行墨迹顶、末行墨迹底 → 卡底。
    ///
    /// 量的是渲染出来的墨迹，不是 AX 控件外框：文字行盒里升部/降部的空隙、
    /// 开关轨道、分隔线都算在内容带里，所以这张表能和肉眼看到的一致。
    struct CardInkBand {
        let index: Int
        let card: NSRect
        let inkTopY: CGFloat      // 首行墨迹顶（窗口坐标 y 向上）
        let inkBottomY: CGFloat   // 末行墨迹底
        var topGap: CGFloat { card.maxY - inkTopY }
        var bottomGap: CGFloat { inkBottomY - card.minY }
        var delta: CGFloat { abs(topGap - bottomGap) }
        var record: [String: Any] {
            [
                "card": index,
                "cardHeight": Double((card.height * 100).rounded() / 100),
                "inkHeight": Double(((inkTopY - inkBottomY) * 100).rounded() / 100),
                "topGap": Double((topGap * 100).rounded() / 100),
                "bottomGap": Double((bottomGap * 100).rounded() / 100),
                "delta": Double((delta * 100).rounded() / 100),
            ]
        }
    }

    /// 一张卡片的内容墨迹带。
    ///
    /// 取卡片内缘（左右各让 16pt 避开 12pt 圆角、上下各让 2.5pt 避开 1pt 描边）的
    /// 全部像素，先按出现次数最多的颜色定卡片底色，再把「任一通道差 >4/255」的像素
    /// 记为墨迹；最高的一行墨迹像素到卡顶、最低的一行墨迹像素到卡底就是两条留白。
    @MainActor static func cardInkBand(index: Int, card: NSRect, hosting: NSView, window: NSWindow,
                                       bitmap: NSBitmapImageRep) -> CardInkBand? {
        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, hosting.bounds.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, hosting.bounds.height)
        func pixel(_ point: NSPoint) -> (x: Int, y: Int)? {
            let local = hosting.convert(window.convertPoint(fromScreen: point), from: nil)
            let x = Int(local.x * scaleX)
            let y = Int((hosting.isFlipped ? local.y : hosting.bounds.height - local.y) * scaleY)
            guard x >= 0, y >= 0, x < bitmap.pixelsWide, y < bitmap.pixelsHigh else { return nil }
            return (x, y)
        }
        /// 位图行号（0 = 图像顶）→ 窗口坐标 y（向上）。
        func windowY(ofRow row: Int) -> CGFloat {
            let topDown = (CGFloat(row) + 0.5) / scaleY
            let local = hosting.isFlipped ? topDown : hosting.bounds.height - topDown
            return window.convertPoint(toScreen: hosting.convert(NSPoint(x: 0, y: local), to: nil)).y
        }
        func channels(_ x: Int, _ y: Int) -> (CGFloat, CGFloat, CGFloat)? {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return nil }
            return (color.redComponent, color.greenComponent, color.blueComponent)
        }
        guard let topLeft = pixel(NSPoint(x: card.minX + 16, y: card.maxY - 2.5)),
              let bottomRight = pixel(NSPoint(x: card.maxX - 16, y: card.minY + 2.5)),
              bottomRight.x > topLeft.x, bottomRight.y > topLeft.y else { return nil }
        var histogram: [Int: Int] = [:]
        var lookup: [Int: (CGFloat, CGFloat, CGFloat)] = [:]
        for y in topLeft.y...bottomRight.y {
            for x in topLeft.x...bottomRight.x {
                guard let color = channels(x, y) else { continue }
                let key = (Int((color.0 * 255).rounded()) << 16)
                    | (Int((color.1 * 255).rounded()) << 8)
                    | Int((color.2 * 255).rounded())
                histogram[key, default: 0] += 1
                lookup[key] = color
            }
        }
        guard let backgroundKey = histogram.max(by: { $0.value < $1.value })?.key,
              let background = lookup[backgroundKey] else { return nil }
        var inkTopRow: Int?
        var inkBottomRow: Int?
        for y in topLeft.y...bottomRight.y {
            var ink = 0
            for x in topLeft.x...bottomRight.x {
                guard let color = channels(x, y) else { continue }
                let delta = max(abs(color.0 - background.0),
                                max(abs(color.1 - background.1), abs(color.2 - background.2)))
                if delta > 0.015 { ink += 1 }
            }
            if ink >= 2 {
                if inkTopRow == nil { inkTopRow = y }
                inkBottomRow = y
            }
        }
        guard let top = inkTopRow, let bottom = inkBottomRow else { return nil }
        return CardInkBand(index: index, card: card, inkTopY: windowY(ofRow: top), inkBottomY: windowY(ofRow: bottom))
    }

    /// 逐卡量本页所有卡片的内容墨迹带（在出货窗口 648×600 的同一张渲染上量），
    /// 写进 `cardCentringGeometry`；实测值先落盘，断言在后面统一跑。
    @MainActor static func measureCardCentring(hosting: NSView, window: NSWindow,
                                               section: SettingsSection, appearance: String,
                                               out: URL) throws {
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw Failure(message: "\(appearance) \(section) has no bitmap for the card centring check")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        var frames: [NSRect] = []
        for rect in accessibilityTree(hosting).filter({ axID($0) == "settings.card" }).map({ axFrame($0) })
        where rect.width > 10 && rect.height > 20 {
            if frames.contains(where: { abs($0.minX - rect.minX) < 0.5 && abs($0.minY - rect.minY) < 0.5
                                          && abs($0.width - rect.width) < 0.5 && abs($0.height - rect.height) < 0.5 }) {
                continue
            }
            frames.append(rect)
        }
        guard !frames.isEmpty else { throw Failure(message: "\(appearance) \(section) renders no settings card to centre") }
        frames.sort { $0.maxY > $1.maxY }
        var rows: [[String: Any]] = []
        for (index, card) in frames.enumerated() {
            guard let band = cardInkBand(index: index, card: card, hosting: hosting, window: window, bitmap: bitmap) else {
                throw Failure(message: "\(appearance) \(section) card \(index) has no ink band inside \(card)")
            }
            rows.append(band.record)
        }
        cardCentringGeometry["\(appearance)-\(section.rawValue)"] = rows
    }

    /// 实测值落盘：`out/card-centring-<language>-<appearance>.json`。
    @MainActor static func writeCardCentringReport(appearance: String, language: String, out: URL) throws {
        let sections = cardCentringGeometry.filter { $0.key.hasPrefix(appearance + "-") }
        let data = try JSONSerialization.data(withJSONObject: ["appearance": appearance, "language": language,
                                                               "sections": sections],
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: out.appendingPathComponent("card-centring-\(language)-\(appearance).json"))
    }



    // MARK: - 行内垂直对齐（右侧控件 ↔ 行文字块，≤0.5pt）

    /// 一行「标题 + 可选说明 + 右侧控件」的对齐规格。
    ///
    /// `title` 按当前语言的文案找标题（单行行只有标题）；`detailIdentifier` 是
    /// 说明行的稳定标识（双行行才有）。两者都取不到就判失败，不做「找不到就跳过」。
    struct AlignmentRow {
        let toggle: String
        let title: String
        let detailIdentifier: String?
        var lines: Int { detailIdentifier == nil ? 1 : 2 }
    }

    static func alignmentRows(for section: SettingsSection) -> [AlignmentRow] {
        switch section {
        case .general:
            return [
                AlignmentRow(toggle: "settings.open-at-login.toggle",
                             title: SettingsCopy.text("settings.open-at-login.title"),
                             detailIdentifier: nil),
                AlignmentRow(toggle: "settings.run-in-background.toggle",
                             title: SettingsCopy.text("settings.run-in-background.title"),
                             detailIdentifier: nil),
                AlignmentRow(toggle: "settings.icloud.toggle",
                             title: SettingsCopy.trilingual("iCloud 同步", "iCloud 同步", "iCloud Sync"),
                             detailIdentifier: "settings.icloud.summary"),
                AlignmentRow(toggle: "settings.automatic-updates.toggle",
                             title: SettingsCopy.text("settings.automatic-updates.title"),
                             detailIdentifier: "settings.automatic-updates.subtitle"),
                AlignmentRow(toggle: "settings.sound-effects.toggle",
                             title: SettingsCopy.text("settings.sound-effects.title"),
                             detailIdentifier: nil),
            ]
        case .screenshot:
            return [
                AlignmentRow(toggle: "settings.apple-translation.toggle",
                             title: ScreenshotSettingsCopy.text(.appleTranslationTitle),
                             detailIdentifier: "settings.apple-translation.subtitle"),
            ]
        case .privacy:
            return [
                AlignmentRow(toggle: "settings.privacy.screensharing.toggle",
                             title: SettingsCopy.text("settings.privacy.screensharing.title"),
                             detailIdentifier: "settings.privacy.screensharing.subtitle"),
                AlignmentRow(toggle: "settings.privacy.saved-link-preview.toggle",
                             title: SettingsCopy.text("replica.settings.privacy.saved-link-preview.title"),
                             detailIdentifier: "replica.settings.privacy.saved-link-preview.subtitle"),
            ]
        default:
            return []
        }
    }

    @MainActor static func axRole(_ element: NSObject) -> String {
        let selector = NSSelectorFromString("accessibilityRole")
        if element.responds(to: selector),
           let role = element.perform(selector)?.takeUnretainedValue() as? String { return role }
        return element.accessibilityAttributeValue(.role) as? String ?? ""
    }

    @MainActor static func axText(_ element: NSObject) -> String {
        // SwiftUI 的文字节点把文案暴露在 NSAccessibility 协议的 `accessibilityValue`
        // / `accessibilityLabel` 上，旧的 AXValue 属性在这里是 nil；两条都试。
        for name in ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"] {
            let selector = NSSelectorFromString(name)
            if element.responds(to: selector),
               let value = element.perform(selector)?.takeUnretainedValue() as? String,
               !value.isEmpty { return value }
        }
        for attribute in [NSAccessibility.Attribute.value, .title, .description] {
            if let value = element.accessibilityAttributeValue(attribute) as? String, !value.isEmpty { return value }
        }
        return ""
    }

    /// 逐行断言：开关外框中心 == 该行文字块中心（单行对文字行高中心，双行对
    /// 标题 + 说明整块的中心），误差 ≤0.5pt。实测值写进 `rowAlignmentGeometry`。
    @MainActor static func checkRowAlignment(hosting: NSView, section: SettingsSection,
                                              appearance: String) throws {
        let rows = alignmentRows(for: section)
        guard !rows.isEmpty else { return }
        hosting.layoutSubtreeIfNeeded()
        let tree = accessibilityTree(hosting)
        var measured: [[String: Any]] = []
        for row in rows {
            guard let toggle = tree.filter({ node in
                axID(node) == row.toggle && ["AXCheckBox", "AXButton", "AXSwitch"].contains(axRole(node))
            }).map({ axFrame($0) }).filter({ $0.width > 10 && $0.height > 10 })
                .max(by: { $0.width < $1.width }) else {
                throw Failure(message: "\(appearance) \(section) is missing the row switch \(row.toggle)")
            }
            guard let title = tree.filter({ node in
                guard axRole(node) == "AXStaticText" else { return false }
                let text = axText(node)
                return text == row.title || text.hasSuffix("| " + row.title)
            }).map({ axFrame($0) }).filter({ $0.width > 2 }).max(by: { $0.width < $1.width }) else {
                throw Failure(message: "\(appearance) \(section) row \(row.toggle) is missing its title: \(row.title)")
            }
            var block = title
            if let detail = row.detailIdentifier {
                guard let detailFrame = tree.filter({ axID($0) == detail }).map({ axFrame($0) })
                    .filter({ $0.width > 2 }).max(by: { $0.width < $1.width }) else {
                    throw Failure(message: "\(appearance) \(section) row \(row.toggle) is missing its detail \(detail)")
                }
                block = block.union(detailFrame)
            }
            let delta = abs(block.midY - toggle.midY)
            measured.append(["row": row.toggle, "lines": row.lines,
                             "textCenter": Double((block.midY * 100).rounded() / 100),
                             "switchCenter": Double((toggle.midY * 100).rounded() / 100),
                             "delta": Double((delta * 100).rounded() / 100)])
            try check(delta <= 0.5,
                      "\(appearance) \(section) row \(row.toggle) switch centre \(toggle.midY) is \(delta)pt off its \(row.lines)-line text block centre \(block.midY)")
        }
        if section == .general {
            let upper = try startupSwitchFrame(rows[0].toggle, in: tree)
            let lower = try startupSwitchFrame(rows[1].toggle, in: tree)
            guard let card = tree.filter({ axID($0) == "settings.card" }).map({ axFrame($0) })
                .first(where: { $0.contains(upper) && $0.contains(lower) }) else {
                throw Failure(message: "Missing the shared startup card")
            }
            // The two one-line rows have equal height and the divider is in the
            // middle. Check each row against its actual card/divider boundaries.
            let upperCenter = (card.maxY + card.midY) / 2
            let lowerCenter = (card.minY + card.midY) / 2
            try check(abs(upper.midY - upperCenter) <= 0.75 && abs(lower.midY - lowerCenter) <= 0.75,
                      "\(appearance) startup switches are not centred between card edges and divider")
        }
        rowAlignmentGeometry["\(appearance)-\(section.rawValue)"] = measured
    }

    @MainActor static func startupSwitchFrame(_ identifier: String, in tree: [NSObject]) throws -> NSRect {
        guard let frame = tree.filter({ axID($0) == identifier }).map({ axFrame($0) })
            .filter({ $0.width > 10 && $0.height > 10 }).max(by: { $0.width < $1.width }) else {
            throw Failure(message: "Missing startup switch \(identifier)")
        }
        return frame
    }

    /// AI 页状态行：7pt 圆点（绘制出来的实心圆，读屏隐藏）与状态标题文字
    /// 同一条中线，误差 ≤0.5pt。用渲染像素量，因为圆点不暴露 AX 帧。
    @MainActor static func checkAIStatusDotAlignment(hosting: NSView, appearance: String) throws {
        let tree = accessibilityTree(hosting)
        guard let status = tree.first(where: { axID($0) == "settings.mcp.status" }).map({ axFrame($0) }),
              let window = hosting.window else {
            throw Failure(message: "\(appearance) AI page has no status title to align the dot with")
        }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw Failure(message: "\(appearance) AI page has no bitmap for the status dot")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, hosting.bounds.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, hosting.bounds.height)
        var top = CGFloat.greatestFiniteMagnitude, bottom = -CGFloat.greatestFiniteMagnitude
        // 圆点在标题左侧：标题行上下各放宽 6pt，横向从卡片内文左缘到标题左缘。
        let search = NSRect(x: status.minX - 24, y: status.minY - 6,
                            width: 22, height: status.height + 12)
        var y = search.minY
        while y <= search.maxY {
            var x = search.minX
            while x <= search.maxX {
                let local = hosting.convert(window.convertPoint(fromScreen: NSPoint(x: x, y: y)), from: nil)
                let px = Int(local.x * scaleX)
                let py = Int((hosting.isFlipped ? local.y : hosting.bounds.height - local.y) * scaleY)
                if px >= 0, py >= 0, px < bitmap.pixelsWide, py < bitmap.pixelsHigh,
                   let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) {
                    // 圆点是该区域里唯一的饱和色（正常=系统绿、异常=系统红），
                    // 文字/背景都是灰阶：按「最大与最小通道差」判定，不挑色相。
                    let channels = [color.redComponent, color.greenComponent, color.blueComponent]
                    if (channels.max() ?? 0) - (channels.min() ?? 0) > 0.25 {
                        let screenY = window.convertPoint(toScreen: hosting.convert(
                            NSPoint(x: local.x, y: hosting.isFlipped ? local.y : hosting.bounds.height - local.y), to: nil)).y
                        top = min(top, screenY)
                        bottom = max(bottom, screenY)
                    }
                }
                x += 1
            }
            y += 1
        }
        guard top <= bottom else { throw Failure(message: "\(appearance) AI status dot is not rendered") }
        let dotCenter = (top + bottom) / 2
        try check(abs(dotCenter - status.midY) <= 0.5,
                  "\(appearance) AI status dot centre \(dotCenter) is \(abs(dotCenter - status.midY))pt off the title centre \(status.midY)")
        rowAlignmentGeometry["\(appearance)-ai-dot"] = [[
            "row": "settings.mcp.status.dot", "lines": 1,
            "textCenter": Double((status.midY * 100).rounded() / 100),
            "switchCenter": Double((dotCenter * 100).rounded() / 100),
            "delta": Double((abs(dotCenter - status.midY) * 100).rounded() / 100),
        ]]
    }

    // MARK: - 「外观与语言」组（主题 + 语言）

    /// 「通用 → 外观与语言」：两行、两个菜单选择器，主题写 `preferences.appearance`，
    /// 语言写 `appLanguage`。
    ///
    /// 三层断言，全部在**出货的** `ReplicaSettingsView` 上量：
    /// 1) 位置：这一组夹在「启动与运行」与「同步与更新」之间（同页按 y 排序）；
    /// 2) 回显：选择器显示的就是存储里的值，改存储后重开仍是同一项；
    /// 3) 即时生效：语言换掉之后**同一个已经渲染的**页面立刻按新语言重算文案
    ///    （分区标题、侧栏、「外观与语言」组标题与工具栏标题一起变），
    ///    选「跟随系统」等于删掉 `appLanguage` 键。
    @MainActor static func verifyAppearanceLanguageRows(state: ReplicaUIState, model: PermissionStatusModel,
                                                        out: URL, language: String) async throws {
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("local.blinkclip.regression.") else {
            throw Failure(message: "isolated test app domain required")
        }
        func makeHost() -> NSHostingView<AnyView> {
            let root = AnyView(ReplicaSettingsView(state: state,
                                                  initialTab: SettingsSection.general.rawValue,
                                                  permissionModel: model)
                .background(Color(nsColor: .windowBackgroundColor)))
            let host = NSHostingView(rootView: root)
            let window = OffscreenSettingsWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 600),
                                                styleMask: [.titled, .closable, .fullSizeContentView],
                                                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unified
            window.setFrame(NSRect(x: -5000, y: -5000, width: 648, height: 600), display: false)
            window.contentView = host
            window.orderFront(nil)
            return host
        }
        func close(_ host: NSView) {
            host.window?.orderOut(nil)
            host.window?.contentView = nil
            host.window?.close()
        }
        /// 行文字块（标题 + 说明）的并集帧：标题按文案找，说明按标识符找。
        func textBlock(_ host: NSView, title: String, detail: String) -> NSRect? {
            let tree = accessibilityTree(host)
            guard let titleFrame = tree.filter({ node in
                axRole(node) == "AXStaticText" && axText(node) == title
            }).map({ axFrame($0) }).filter({ $0.width > 2 }).max(by: { $0.width < $1.width }) else { return nil }
            guard let detailFrame = tree.filter({ axID($0) == detail }).map({ axFrame($0) })
                .filter({ $0.width > 2 }).max(by: { $0.width < $1.width }) else { return nil }
            return titleFrame.union(detailFrame)
        }
        func popups(_ host: NSView) -> [NSPopUpButton] {
            descendants(host, of: NSPopUpButton.self)
                .filter { !$0.isHidden && $0.frame.height > 10 }
                // 窗口坐标 y 向上：这一页里靠上的那个是「主题」。
                .sorted { $0.convert($0.bounds, to: nil).maxY > $1.convert($1.bounds, to: nil).maxY }
        }
        func sectionTitleFrames(_ host: NSView) -> [NSRect] {
            accessibilityTree(host).filter { axID($0) == "settings.section-title" }
                .map { axFrame($0) }.filter { $0.width > 10 }
                .sorted { $0.maxY > $1.maxY }
        }

        try check(SettingsAppearanceChoice.allCases == [.system, .light, .dark],
                  "theme options are not 跟随系统/浅色/深色: \(SettingsAppearanceChoice.allCases)")
        try check(SettingsAppLanguageChoice.allCases == [.system, .zhHans, .zhHant, .en],
                  "language options are not 跟随系统/简体中文/繁體中文/English: \(SettingsAppLanguageChoice.allCases)")
        try check(SettingsAppearanceChoice(stored: "system").storedValue == "system"
                  && SettingsAppearanceChoice(stored: "light").storedValue == "light"
                  && SettingsAppearanceChoice(stored: "dark").storedValue == "dark",
                  "theme choices do not use the existing preferences.appearance values")
        try check(SettingsAppLanguageChoice.zhHans.storedValue == "zh"
                  && SettingsAppLanguageChoice.zhHant.storedValue == "zh-Hant"
                  && SettingsAppLanguageChoice.en.storedValue == "en"
                  && SettingsAppLanguageChoice.system.storedValue == nil,
                  "language choices do not use the appLanguage raw values (跟随系统 = no key)")
        // 语言名按自称显示，不随界面语言翻译。
        try check(SettingsAppLanguageChoice.zhHans.title == "简体中文"
                  && SettingsAppLanguageChoice.zhHant.title == "繁體中文"
                  && SettingsAppLanguageChoice.en.title == "English",
                  "language names must be the languages' own names")

        let originalAppearance = state.store.preferences.appearance
        let originalLanguage = UserDefaults.standard.string(forKey: SettingsLanguage.preferenceKey)
        defer {
            state.store.preferences.appearance = originalAppearance
            try? state.store.save()
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: SettingsLanguage.preferenceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: SettingsLanguage.preferenceKey)
            }
            NotificationCenter.default.post(name: .appLanguageDidChange, object: nil)
            print("appearance-language: state restored")
        }

        let host = makeHost()
        defer { close(host) }
        await pause()
        host.layoutSubtreeIfNeeded()

        // 1) 位置：启动与运行 → 外观与语言 → 同步与更新 → 声音。
        let titles = [SettingsCopy.text("settings.general.startup-section.title"),
                      SettingsCopy.text("settings.general.appearance-section.title"),
                      SettingsCopy.text("settings.general.sync-section.title"),
                      SettingsCopy.text("settings.general.sound-section.title")]
        let titleFrames = sectionTitleFrames(host)
        try check(titleFrames.count == titles.count,
                  "general page has \(titleFrames.count) section titles, expected \(titles.count)")
        for (index, title) in titles.enumerated() {
            try check(treeHasText(host, title), "general page is missing the section title: \(title)")
        }
        if let appearanceFrame = accessibleTextFrame(host, text: titles[1]),
           let startupFrame = accessibleTextFrame(host, text: titles[0]),
           let syncFrame = accessibleTextFrame(host, text: titles[2]) {
            try check(appearanceFrame.maxY < startupFrame.minY,
                      "「外观与语言」is not below「启动与运行」: \(appearanceFrame) vs \(startupFrame)")
            try check(appearanceFrame.minY > syncFrame.maxY,
                      "「外观与语言」is not above「同步与更新」: \(appearanceFrame) vs \(syncFrame)")
        } else {
            throw Failure(message: "could not measure the three group titles around 外观与语言")
        }

        // 两行文字与两个选择器都在，且选择器中心与文字块中心对齐（≤0.5pt）。
        let rows: [(title: String, detail: String)] = [
            (SettingsCopy.text("settings.appearance.theme.title"), "settings.appearance.theme.subtitle"),
            (SettingsCopy.text("settings.appearance.language.title"), "settings.appearance.language.subtitle"),
        ]
        let controls = popups(host)
        try check(controls.count == 2, "外观与语言 has \(controls.count) pickers, expected 2")
        // 行内对齐按**选择器的无障碍帧**量（与开关行同一条口径）：SwiftUI 的布局帧
        // 才是行里被居中的那个框，NSPopUpButton 自己的 bounds 含着色器内缩。
        let pickerNodes = accessibilityTree(host)
            .filter { node in
                ["settings.appearance.theme.picker", "settings.appearance.language.picker"].contains(axID(node))
            }
            .map { (frame: axFrame($0), role: axRole($0)) }
            .filter { $0.frame.width > 10 && $0.frame.height > 8 }
            .sorted { $0.frame.maxY > $1.frame.maxY }
        try check(pickerNodes.count == 2,
                  "外观与语言 exposes \(pickerNodes.count) pickers to accessibility, expected 2")
        for picker in pickerNodes {
            try check(["AXPopUpButton", "AXMenuButton", "AXButton"].contains(picker.role),
                      "外观与语言 picker role is \(picker.role), expected a pop-up button")
        }
        var measured: [[String: Any]] = []
        for (index, row) in rows.enumerated() {
            guard let block = textBlock(host, title: row.title, detail: row.detail) else {
                throw Failure(message: "外观与语言 row \(row.title) is missing its title or subtitle")
            }
            try check(treeHasText(host, row.title), "外观与语言 row title is not rendered: \(row.title)")
            let control = pickerNodes[index].frame
            let delta = abs(block.midY - control.midY)
            measured.append(["row": row.title, "control": pickerNodes[index].role,
                             "textCenter": Double((block.midY * 100).rounded() / 100),
                             "controlCenter": Double((control.midY * 100).rounded() / 100),
                             "delta": Double((delta * 100).rounded() / 100)])
            try check(delta <= 0.5,
                      "外观与语言 row \(row.title) picker centre \(control.midY) is \(delta)pt off its text block centre \(block.midY)")
        }
        rowAlignmentGeometry["\(language)-appearance-language"] = measured

        // 2) 主题回显：写 store 的存量字符串，重开页面选择器就显示对应项；落盘后重开 store 仍在。
        for choice in SettingsAppearanceChoice.allCases {
            state.store.preferences.appearance = choice.storedValue
            try state.store.save()
            let reopenedHost = makeHost()
            await pause()
            reopenedHost.layoutSubtreeIfNeeded()
            let reopened = popups(reopenedHost)
            try check(reopened.count == 2, "theme echo page lost a picker")
            try check(reopened[0].titleOfSelectedItem == choice.title,
                      "theme picker does not echo \(choice.storedValue): \(String(describing: reopened[0].titleOfSelectedItem))")
            if choice == .dark {
                try writePNG(reopenedHost.window?.contentView?.superview ?? reopenedHost,
                             name: "z3b-\(language)-general-theme-dark-echo", out: out)
            }
            close(reopenedHost)
            let reread = try ClipboardStore(directoryURL: state.store.directoryURL)
            try check(reread.preferences.appearance == choice.storedValue,
                      "theme \(choice.storedValue) did not survive reopening the store")
        }
        state.store.preferences.appearance = originalAppearance
        try state.store.save()

        // 3) 语言即时刷新：写键 + 发通知（生产 `apply()` 的同一条路径），
        //    已经渲染的页面必须按新语言重算文案，并持久化到重启也能读到的键上。
        let target: SettingsAppLanguageChoice = SettingsCopy.language == .zhHant ? .en : .zhHant
        target.apply()
        await pause()
        host.layoutSubtreeIfNeeded()
        try check(treeHasText(host, SettingsCopy.text("settings.general.appearance-section.title")),
                  "the open page did not refresh to \(target.rawValue): \(SettingsCopy.text("settings.general.appearance-section.title"))")
        try check(SettingsSection.general.title == (target == .en ? "General" : "一般"),
                  "section titles did not refresh to \(target.rawValue): \(SettingsSection.general.title)")
        try check(UserDefaults.standard.string(forKey: SettingsLanguage.preferenceKey) == target.storedValue,
                  "changing the language did not persist appLanguage = \(target.storedValue ?? "nil")")
        let refreshed = popups(host)
        try check(refreshed.count == 2 && refreshed[1].titleOfSelectedItem == target.title,
                  "language picker does not echo \(target.rawValue): \(refreshed.map { $0.titleOfSelectedItem ?? "?" })")
        if let themeFrame = host.window?.contentView?.superview,
           let nativeTitle = descendants(themeFrame, of: NSTextField.self)
            .first(where: { $0.accessibilityIdentifier() == "BlinkClipSettingsPaneTitle" }) {
            try check(nativeTitle.stringValue == SettingsSection.general.title,
                      "toolbar title did not follow the language change: \(nativeTitle.stringValue)")
        } else {
            throw Failure(message: "settings page lost its native toolbar title")
        }
        try writePNG(host.window?.contentView?.superview ?? host,
                     name: "z3b-\(language)-general-language-\(target.rawValue)", out: out)
        // 「跟随系统」= 删键，页面回到进程语言。
        SettingsAppLanguageChoice.system.apply()
        await pause()
        try check(UserDefaults.standard.object(forKey: SettingsLanguage.preferenceKey) == nil,
                  "choosing 跟随系统 did not remove the appLanguage key")
        try check(SettingsCopy.language == (language == "zh-Hant" ? .zhHant : language == "zh-Hans" ? .zhHans : .en),
                  "after 跟随系统 the page does not resolve the process language: \(SettingsCopy.language.rawValue)")
        try check(popups(host).count == 2 && popups(host)[1].titleOfSelectedItem == SettingsAppLanguageChoice.system.title,
                  "language picker does not echo 跟随系统 after removing the key")
        // 写工具本身：scratch 域里写入 / 删除，并发出同名的通知。
        let scratchName = "z3b-appearance-language-\(UUID().uuidString)"
        let scratch = UserDefaults(suiteName: scratchName)!
        defer { scratch.removePersistentDomain(forName: scratchName) }
        let center = NotificationCenter()
        var posted = 0
        let token = center.addObserver(forName: .appLanguageDidChange, object: nil, queue: nil) { _ in posted += 1 }
        defer { center.removeObserver(token) }
        try check(SettingsAppLanguageChoice.current(defaults: scratch) == .system, "an empty suite is not 跟随系统")
        SettingsAppLanguageChoice.zhHant.apply(defaults: scratch, notificationCenter: center)
        try check(scratch.string(forKey: SettingsLanguage.preferenceKey) == "zh-Hant"
                  && SettingsAppLanguageChoice.current(defaults: scratch) == .zhHant,
                  "保存 繁體中文 did not write appLanguage = zh-Hant")
        SettingsAppLanguageChoice.zhHans.apply(defaults: scratch, notificationCenter: center)
        try check(SettingsAppLanguageChoice.current(defaults: scratch) == .zhHans, "保存 简体中文 did not round-trip")
        SettingsAppLanguageChoice.en.apply(defaults: scratch, notificationCenter: center)
        try check(SettingsAppLanguageChoice.current(defaults: scratch) == .en, "保存 English did not round-trip")
        SettingsAppLanguageChoice.system.apply(defaults: scratch, notificationCenter: center)
        try check(scratch.string(forKey: SettingsLanguage.preferenceKey) == nil
                  && SettingsAppLanguageChoice.current(defaults: scratch) == .system,
                  "跟随系统 did not删除 the appLanguage key")
        try check(posted == 4, "语言写入没有每次都发出 appLanguageDidChange: \(posted)")
        // 不认识的存量值（例如设置页没有表的 ja）显示「跟随系统」，但不回写。
        scratch.set("ja", forKey: SettingsLanguage.preferenceKey)
        try check(SettingsAppLanguageChoice.current(defaults: scratch) == .system,
                  "an unsupported stored language is not shown as 跟随系统")
        try check(scratch.string(forKey: SettingsLanguage.preferenceKey) == "ja",
                  "opening the page rewrote the stored language")
        print("appearance-language: \(measured.count) rows, theme \(originalAppearance) restored, language key restored")
    }

    /// 页面上某段文字（任一无障碍取值）的帧，用于量分组标题的相对顺序。
    @MainActor static func accessibleTextFrame(_ host: NSView, text: String) -> NSRect? {
        func values(_ node: NSObject) -> [String] {
            var result: [String] = []
            for attribute in [NSAccessibility.Attribute.value, .title, .description] {
                if let value = node.accessibilityAttributeValue(attribute) as? String { result.append(value) }
            }
            for name in ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"] {
                let selector = NSSelectorFromString(name)
                if node.responds(to: selector),
                   let value = node.perform(selector)?.takeUnretainedValue() as? String { result.append(value) }
            }
            return result
        }
        return accessibilityTree(host).filter { values($0).contains(text) }
            .map { axFrame($0) }.filter { $0.width > 2 && $0.height > 2 }
            .max(by: { $0.width < $1.width })
    }

    // MARK: - P7「自动检查更新」

    /// 「自动检查更新」开关：默认关（信息表里 `SUEnableAutomaticChecks=NO`，默认域
    /// 里连键都没有）→ 打开写入 Sparkle 自己那一份 `SUEnableAutomaticChecks`（`true`）
    /// → 重开视图（相当于重启应用后重开设置窗）仍然是开 → 关掉写回 false。
    /// 「关于闪贴」是设置内容区里的第七页。
    ///
    /// 它必须和六个分区共用同一套节奏（页顶 16pt、settingsCard、卡片内容垂直居中），
    /// 并且只有「检查更新」一个动作按钮：状态行压在按钮上方 ≤12pt、两者同一条中轴，
    /// 状态行在链接与许可之上（用户要求把这两块调换位置），页面上没有关闭按钮
    /// （设置窗口自己的关闭按钮就是关闭路径）。
    @MainActor static func checkAboutPage(hosting: NSView, window: NSWindow, appearance: String,
                                          language: String, out: URL) async throws {
        hosting.layoutSubtreeIfNeeded()
        let tree = accessibilityTree(hosting)
        func frame(_ identifier: String) throws -> NSRect {
            guard let element = tree.first(where: { axID($0) == identifier }) else {
                throw Failure(message: "\(appearance) About page is missing \(identifier)")
            }
            let rect = axFrame(element)
            guard rect.width > 0.5, rect.height > 0.5 else {
                throw Failure(message: "\(appearance) About page \(identifier) has no frame")
            }
            return rect
        }
        try check(!tree.contains { axID($0) == "about-close" },
                  "\(appearance) About page still carries a Close button")
        try check(!NSApp.windows.contains { $0.identifier?.rawValue == "blinkclip-about-window" },
                  "\(appearance) About page produced an independent About window")
        try check((window.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == SettingsCopy.text("updates.about-title"),
                  "\(appearance) About page title is \(String(describing: (window.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle))")
        let card = try frame("settings.card")
        let icon = try frame("about-application-icon")
        let name = try frame("about-product-name")
        let version = try frame("about-current-version")
        let description = try frame("about-description")
        let status = try frame("about-update-status")
        let button = try frame("about-check-updates")
        let project = try frame("about-project-link")
        let releases = try frame("about-release-notes-link")
        let copyright = try frame("about-copyright")
        let license = try frame("about-license-link")
        try check(name.maxY <= icon.minY && version.maxY <= name.minY && description.maxY <= version.minY,
                  "the About page identity must show the installed version under the product name")
        try check(card.maxY <= description.minY && copyright.maxY <= card.minY,
                  "the About footer must appear below the update card")
        try check(card.contains(status) && card.contains(button) && status.maxX < button.minX
                  && status.maxY > button.minY && status.minY < button.maxY,
                  "the update status and Check for Updates must share a row")
        try check(abs(project.midY - license.midY) <= 1 && abs(project.midY - releases.midY) <= 1
                  && project.maxX < license.minX && license.maxX < releases.minX
                  && copyright.minY >= max(project.maxY, license.maxY, releases.maxY),
                  "the three footer links must appear in order on one row below the copyright")
        let contentBottom = window.convertPoint(toScreen: NSPoint(x: 0, y: window.contentLayoutRect.minY)).y
        try check(abs(min(project.minY, license.minY, releases.minY) - contentBottom
                      - SettingsPageMetrics.bottomInset) <= 1,
                  "the About footer must align with the bottom page inset")
        let actionButtons = tree.filter { axRole($0) == "AXButton" && (axID($0) ?? "").hasPrefix("about-") }
        try check(actionButtons.count == 1 && axID(actionButtons[0]) == "about-check-updates",
                  "\(appearance) About page action buttons: \(actionButtons.compactMap { axID($0) })")
        let contentTop = window.convertPoint(toScreen: NSPoint(x: 0, y: window.contentLayoutRect.maxY)).y
        let topGap = contentTop - icon.maxY
        try check(abs(topGap - SettingsPageMetrics.topInset) <= 0.5,
                  "\(appearance) About identity starts \(topGap)pt from the content top")
        try check(icon.height >= 90 && icon.height <= 100,
                  "\(appearance) About icon is \(icon.height)pt, expected about 96pt")
        aboutGeometry["\(appearance)-about"] = [
            "topGap": Double(topGap),
            "actionButtonCount": Double(actionButtons.count),
            "iconSide": Double(icon.height),
        ]
        if ProcessInfo.processInfo.environment["BLINKCLIP_SKIP_SCREENSHOTS"] != "1",
           let frameView = window.contentView?.superview {
            try writePNG(frameView, name: "\(language)-about-pane-\(appearance)", out: out)
        }
    }

    @MainActor static func verifyAutomaticUpdateToggle(state: ReplicaUIState, model: PermissionStatusModel,
                                                       out: URL, language: String) async throws {
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("local.blinkclip.regression.") else {
            throw Failure(message: "isolated test app domain required")
        }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "SUEnableAutomaticChecks")
        defer { defaults.removeObject(forKey: "SUEnableAutomaticChecks") }
        try check(defaults.object(forKey: "SUEnableAutomaticChecks") == nil,
                  "the isolated domain already stored an automatic-check flag")
        try check(BlinkClipInAppUpdater.automaticallyChecksForUpdates == false,
                  "the shipped default (Info.plist SUEnableAutomaticChecks=NO) is not off")

        func makeHost() -> NSHostingView<AnyView> {
            let root = AnyView(ReplicaSettingsView(state: state,
                                                  initialTab: SettingsSection.general.rawValue,
                                                  permissionModel: model)
                .background(Color(nsColor: .windowBackgroundColor)))
            let host = NSHostingView(rootView: root)
            let window = OffscreenSettingsWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 600),
                                                styleMask: [.titled, .closable, .fullSizeContentView],
                                                backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unified
            window.setFrame(NSRect(x: -5000, y: -5000, width: 648, height: 600), display: false)
            window.contentView = host
            window.orderFront(nil)
            return host
        }
        func nodes(_ host: NSView, id: String) -> [NSObject] {
            accessibilityTree(host).filter { axID($0) == id }
        }
        func toggleNodes(_ host: NSView) -> [NSObject] {
            nodes(host, id: "settings.automatic-updates.toggle")
        }
        func switchIsOn(_ node: NSObject) -> Bool? {
            // SwiftUI 的开关只经现代的 `accessibilityValue` 暴露 0/1；
            // 旧的 AXValue 属性在这里是 nil（实测），两个都试一遍。
            let modern = NSSelectorFromString("accessibilityValue")
            if node.responds(to: modern),
               let value = node.perform(modern)?.takeUnretainedValue() {
                if let number = value as? NSNumber { return number.boolValue }
                if let string = value as? String { return ["1", "on", "true"].contains(string.lowercased()) }
            }
            if let number = node.accessibilityAttributeValue(.value) as? NSNumber { return number.boolValue }
            if let string = node.accessibilityAttributeValue(.value) as? String {
                return ["1", "on", "true"].contains(string.lowercased())
            }
            return nil
        }
        func frameOfLabel(_ host: NSView, _ text: String) -> NSRect? {
            for node in accessibilityTree(host) {
                var values: [String] = []
                for attribute in [NSAccessibility.Attribute.value, .title, .description] {
                    if let value = node.accessibilityAttributeValue(attribute) as? String { values.append(value) }
                }
                for name in ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"] {
                    let selector = NSSelectorFromString(name)
                    if node.responds(to: selector),
                       let value = node.perform(selector)?.takeUnretainedValue() as? String {
                        values.append(value)
                    }
                }
                if values.contains(text) {
                    let frame = axFrame(node)
                    if frame.height > 0 { return frame }
                }
            }
            return nil
        }

        let host = makeHost()
        defer { host.window?.orderOut(nil); host.window?.contentView = nil; host.window?.close() }
        await pause()
        // 1) 默认关：开关在关位，键盘上也没有写入过任何键。
        guard let switchNode = toggleNodes(host).max(by: { axFrame($0).width < axFrame($1).width }) else {
            throw Failure(message: "general page has no automatic-update switch")
        }

        try check(switchIsOn(switchNode) == false,
                  "the automatic-update switch does not start off: \(String(describing: switchIsOn(switchNode)))")
        try check(defaults.object(forKey: "SUEnableAutomaticChecks") == nil,
                  "opening the page wrote SUEnableAutomaticChecks before the user touched it")
        // 文案三语在同一行：标题在上、说明在下，行在 iCloud 之后、提示音之前。
        try check(treeHasText(host, SettingsCopy.text("settings.automatic-updates.title")),
                  "the row title is missing: \(SettingsCopy.text("settings.automatic-updates.title"))")
        try check(treeHasText(host, SettingsCopy.text("settings.automatic-updates.subtitle")),
                  "the row subtitle is missing")
        if let icloud = nodes(host, id: "settings.icloud.toggle").map({ axFrame($0) })
            .max(by: { $0.width < $1.width }),
           let sound = frameOfLabel(host, SettingsCopy.text("settings.sound-effects.title")) {
            try check(icloud.midY > axFrame(switchNode).midY,
                      "the automatic-update row is not below the iCloud row: \(icloud.midY) vs \(axFrame(switchNode).midY)")
            try check(axFrame(switchNode).midY > sound.midY,
                      "the automatic-update row is not above the sound row: \(axFrame(switchNode).midY) vs \(sound.midY)")
        } else {
            throw Failure(message: "could not measure the iCloud row and the sound row around the new switch")
        }
        if let themeFrame = host.window?.contentView?.superview {
            try writePNG(themeFrame, name: "p7-\(language)-general-automatic-updates-off", out: out)
        }
        // 2) 打开：写的就是 Sparkle 的键，值是 true。
        try check(press(switchNode), "the automatic-update switch rejects AX press")
        await pause()
        try check(BlinkClipInAppUpdater.automaticallyChecksForUpdates == true,
                  "turning the switch on did not reach SPUUpdater.automaticallyChecksForUpdates")
        try check(defaults.bool(forKey: "SUEnableAutomaticChecks") == true,
                  "turning the switch on did not persist SUEnableAutomaticChecks = true: \(String(describing: defaults.object(forKey: "SUEnableAutomaticChecks")))")
        if let themeFrame = host.window?.contentView?.superview {
            try writePNG(themeFrame, name: "p7-\(language)-general-automatic-updates-on", out: out)
        }
        host.window?.orderOut(nil)
        host.window?.contentView = nil
        host.window?.close()

        // 3) 「重启后保持」：换一份全新的根视图（= 重开设置窗/重启后的首次渲染），
        //    开关读到的仍是打开状态。
        let relaunched = makeHost()
        defer { relaunched.window?.orderOut(nil); relaunched.window?.contentView = nil; relaunched.window?.close() }
        await pause()
        try check(BlinkClipInAppUpdater.automaticallyChecksForUpdates == true,
                  "a fresh process view lost the persisted automatic-check flag")
        guard let reloadedSwitch = toggleNodes(relaunched).max(by: { axFrame($0).width < axFrame($1).width }) else {
            throw Failure(message: "the reopened general page has no automatic-update switch")
        }
        try check(switchIsOn(reloadedSwitch) == true,
                  "the reopened switch does not show the persisted on state: \(String(describing: switchIsOn(reloadedSwitch)))")
        try check(defaults.bool(forKey: "SUEnableAutomaticChecks") == true,
                  "the persisted key vanished after reopening the page")

        // 4) 关掉：写回 false，状态与默认一致。
        try check(press(reloadedSwitch), "the reopened automatic-update switch rejects AX press")
        await pause()
        try check(BlinkClipInAppUpdater.automaticallyChecksForUpdates == false,
                  "turning the switch off did not reach SPUUpdater.automaticallyChecksForUpdates")
        try check(defaults.bool(forKey: "SUEnableAutomaticChecks") == false,
                  "turning the switch off did not persist false: \(String(describing: defaults.object(forKey: "SUEnableAutomaticChecks")))")
        try check(defaults.object(forKey: "SUEnableAutomaticChecks") != nil,
                  "turning the switch off left no stored value at all")
        print("{\"automatic_updates\":\"off->on->persisted->off\",\"key\":\"SUEnableAutomaticChecks\"}")
    }

    @MainActor static func treeHasText(_ host: NSView, _ text: String) -> Bool {
        texts(accessibilityTree(host)).contains(text)
    }

    @MainActor static func verifyShortcutRows(store: ClipboardStore, state: ReplicaUIState, model: PermissionStatusModel, out: URL, language: String) async throws {
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("local.blinkclip.regression.") else { throw Failure(message: "isolated test app domain required") }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        for row in SettingsShortcutRow.allCases {
            if let path = row.path { store.preferences[keyPath: path] = row.shortcutDefault }
            if let path = row.modifierPath { store.preferences[keyPath: path] = row.modifierDefault }
        }
        BlinkClipScreenshotSettings.setShortcut(BlinkClipScreenshotSettings.regionDefault, for: .region)
        BlinkClipScreenshotSettings.setShortcut(BlinkClipScreenshotSettings.fullScreenDefault, for: .fullScreen)
        try store.save()
        let host = NSHostingView(rootView: ReplicaSettingsView(state: state, initialTab: 4, permissionModel: model))
        let window = OffscreenSettingsWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 800), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        await pause()
        func restoreNodes() -> [NSObject] { accessibilityTree(host).filter { (axID($0) ?? "").hasPrefix("settings.shortcut.restore.") } }
        try check(restoreNodes().isEmpty, "all eight default rows hide restore button")
        for row in SettingsShortcutRow.allCases {
            if let path = row.path { store.preferences[keyPath: path] = nil }
            if let path = row.modifierPath { store.preferences[keyPath: path] = 0 }
        }
        BlinkClipScreenshotSettings.setShortcut(.init(keyCode: 98, modifierRawValue: NSEvent.ModifierFlags.command.rawValue), for: .region)
        BlinkClipScreenshotSettings.setShortcut(.init(keyCode: 99, modifierRawValue: NSEvent.ModifierFlags.command.rawValue), for: .fullScreen)
        try store.save()
        await pause()
        let visibleRestoreIDs = Set(restoreNodes().compactMap { axID($0) })
        try check(visibleRestoreIDs.count == 8, "all eight changed rows display restore buttons, including cleared app rows; actual \(visibleRestoreIDs.sorted()); tree \(accessibilityTree(host).map { "\(type(of: $0)):\(axID($0) ?? "-")" })")
        if let frame = window.contentView?.superview, let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(language)-modified-shortcuts-complete-window.png"))
        }
        let restoreRightEdges = Set(restoreNodes().map { axFrame($0).maxX.rounded() })
        try check(restoreRightEdges.count == 1, "all eight restore labels align immediately left of 120pt controls: \(restoreRightEdges)")
        let recorders = accessibilityTree(host).filter { (axID($0) ?? "").hasPrefix("settings.shortcut.recorder.") }
        try check(Set(recorders.compactMap { axID($0) }).count == 6, "six actual recorder accessibility slots")
        var recorderSizes: [NSSize] = []
        for row in SettingsShortcutRow.allCases where row.shortcutDefault != nil {
            let slots = recorders.filter { axID($0) == "settings.shortcut.recorder." + row.rawValue }
            if let slot = slots.first(where: { abs(axFrame($0).width - 120) <= 1 && abs(axFrame($0).height - 24) <= 1 }) { recorderSizes.append(axFrame(slot).size) }
            try check(slots.contains { let frame = axFrame($0); return abs(frame.width - 120) <= 1 && abs(frame.height - 24) <= 1 }, "recorder content is 120 by 24 with at most 1pt outline: \(row), actual \(slots.map { axFrame($0) })")
        }
        try check(recorderSizes.count == 6 && recorderSizes.allSatisfy { $0 == recorderSizes.first! }, "all six recorders have exactly equal outer sizes")
        for row in SettingsShortcutRow.allCases {
            let buttons = restoreNodes().filter { axID($0) == "settings.shortcut.restore." + row.rawValue }
            try check(buttons.contains { press($0) }, "actual modern AX press accepts row \(row)")
            await pause()
            try check(!restoreNodes().contains(where: { axID($0) == "settings.shortcut.restore." + row.rawValue }), "restored row hides its button immediately: \(row)")
        }
        try check(restoreNodes().isEmpty, "all actual buttons disappear after individual restores")
        for slot in BlinkClipScreenshotHotKeySlot.allCases {
            let row = slot == .region ? "region" : "fullScreen"
            let nodes = accessibilityTree(host).filter { axID($0) == "settings.shortcut.recorder." + row }
            var rects: [NSRect] = []
            for node in nodes {
                let rect: NSRect = axFrame(node)
                if abs(rect.width - CGFloat(120)) <= CGFloat(1), abs(rect.height - CGFloat(24)) <= CGFloat(1) {
                    rects.append(rect)
                }
            }
            var clearButtons: [NSObject] = []
            for node in accessibilityTree(host) {
                let rect = axFrame(node)
                guard abs(rect.width - 24) <= 1, abs(rect.height - 24) <= 1 else { continue }
                if rects.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(rect) }) {
                    clearButtons.append(node)
                }
            }
            try check(clearButtons.contains { press($0) }, "actual screenshot recorder x is present and accepts AX press: \(slot)")
            await pause()
            try check(BlinkClipScreenshotSettings.effectiveShortcut(for: slot) == nil, "actual screenshot x clears persisted effective shortcut: \(slot)")
            try check(BlinkClipScreenshotSettings.recordingCount == 0, "clearing screenshot does not begin recording: \(slot)")
            try check(restoreNodes().contains { axID($0) == "settings.shortcut.restore." + row }, "cleared screenshot row displays individual restore: \(slot)")
            if slot == .region, let frame = window.contentView?.superview,
               let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                frame.cacheDisplay(in: frame.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(language)-cleared-region-complete-window.png"))
            }
            var labels: [String] = []
            for node in accessibilityTree(host) {
                for attribute in [NSAccessibility.Attribute.value, .title, .description] {
                    if let text = node.accessibilityAttributeValue(attribute) as? String { labels.append(text) }
                }
                for name in ["accessibilityLabel", "accessibilityValue"] {
                    let selector = NSSelectorFromString(name)
                    if node.responds(to: selector), let text = node.perform(selector)?.takeUnretainedValue() as? String {
                        labels.append(text)
                    }
                }
            }
            try check(labels.contains(SettingsCopy.trilingual("未设置", "未設定", "Not Set")), "cleared screenshot row displays localized Not Set: \(slot)")
            try check(restoreNodes().filter { axID($0) == "settings.shortcut.restore." + row }.contains { press($0) }, "actual screenshot individual restore accepts AX press: \(slot)")
            await pause()
            try check(BlinkClipScreenshotSettings.effectiveShortcut(for: slot) == BlinkClipScreenshotSettings.default(for: slot), "individual restore re-enables screenshot default: \(slot)")
            try check(!restoreNodes().contains { axID($0) == "settings.shortcut.restore." + row }, "restored screenshot hides individual restore: \(slot)")
        }

        if let frame = window.contentView?.superview, let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(language)-restored-shortcuts-complete-window.png"))
        }
    }
    // MARK: - P4 交互契约（刷新反馈、危险动作、冲突提示、关于项回退）

    @MainActor static func writePNG(_ view: NSView, name: String, out: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Failure(message: "no bitmap for \(name)")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: out.appendingPathComponent(name + ".png"))
    }

    /// 只数「明显偏红」的像素：系统红（浅色 255,59,48 / 深色 255,69,58）的
    /// 红-绿、红-蓝都远大于 40，而正文灰、链接蓝都过不了这个门。
    @MainActor static func reddishPixels(_ view: NSView, inScreen rect: NSRect) -> Int {
        guard let window = view.window,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return 0 }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, view.bounds.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, view.bounds.height)
        // 屏幕坐标 y 向上、翻转视图 y 向下：换算两个角再取包围盒，别用一个角加宽高。
        let cornerA = view.convert(window.convertPoint(fromScreen: NSPoint(x: rect.minX, y: rect.minY)), from: nil)
        let cornerB = view.convert(window.convertPoint(fromScreen: NSPoint(x: rect.maxX, y: rect.maxY)), from: nil)
        let minX = min(cornerA.x, cornerB.x), maxX = max(cornerA.x, cornerB.x)
        let minY = min(cornerA.y, cornerB.y), maxY = max(cornerA.y, cornerB.y)
        var count = 0
        var y = minY
        while y <= maxY {
            var x = minX
            while x <= maxX {
                let px = Int(x * scaleX)
                let py = Int((view.isFlipped ? y : view.bounds.height - y) * scaleY)
                if px >= 0, py >= 0, px < bitmap.pixelsWide, py < bitmap.pixelsHigh,
                   let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) {
                    let r = color.redComponent * 255, g = color.greenComponent * 255, b = color.blueComponent * 255
                    if r >= 120, r - g >= 40, r - b >= 40 { count += 1 }
                }
                x += 1
            }
            y += 1
        }
        return count
    }

    @MainActor static func texts(_ tree: [NSObject]) -> [String] {
        var values: [String] = []
        for node in tree {
            for attribute in [NSAccessibility.Attribute.value, .title, .description, .help] {
                if let text = node.accessibilityAttributeValue(attribute) as? String { values.append(text) }
            }
            for name in ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"] {
                let selector = NSSelectorFromString(name)
                if node.responds(to: selector), let text = node.perform(selector)?.takeUnretainedValue() as? String {
                    values.append(text)
                }
            }
        }
        return values
    }

    /// 页尾危险动作的渲染证据：滚到底部后取样，确认它真的用系统红画出来（不是灰按钮），
    /// 并留一张「清空历史记录…」在页尾的截图。
    @MainActor static func verifyDangerFooter(state: ReplicaUIState, out: URL, language: String) async throws {
        let host = NSHostingView(rootView: ReplicaSettingsView(state: state,
                                                              initialTab: SettingsSection.clipboard.rawValue))
        let window = OffscreenSettingsWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 600), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.setFrame(NSRect(x: -5000, y: -5000, width: 648, height: 600), display: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        await pause()
        for scroll in descendants(host, of: NSScrollView.self) where scroll.documentView != nil {
            let document = scroll.documentView!
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, document.bounds.height - scroll.contentView.bounds.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        await pause()
        guard let clear = accessibilityTree(host).filter({ axID($0) == "settings.clear-history" })
            .map({ axFrame($0) }).max(by: { $0.width < $1.width }) else {
            throw Failure(message: "clipboard page is missing the clear-history footer action")
        }
        let reddish = reddishPixels(host, inScreen: clear)
        try check(reddish > 0,
                  "clear-history label is not rendered in the system red semantic color: \(clear)")
        if let themeFrame = window.contentView?.superview {
            try writePNG(themeFrame, name: "p4-\(language)-clipboard-clear-history-footer", out: out)
        }
    }

    /// 「刷新状态」反馈：标题行位置 + 三段可见文案 + 时间戳格式 + 3 秒后恢复。
    ///
    /// 用一份「慢探针」（250ms）而不是真实探针：`正在刷新…` 才是可稳定观察的状态，
    /// 也顺便证明按钮在刷新期间被禁用、不是只换了个字。
    @MainActor static func verifyRefreshFeedback(state: ReplicaUIState, out: URL, language: String) async throws {
        let slow = PermissionStatusModel(readStatus: {
            try? await Task.sleep(nanoseconds: 250_000_000)
            return PermissionStatusReading(currentProcess: PermissionStatusSnapshot(accessibility: true, postEvents: true, screenRecording: false),
                                           freshProcess: nil, checkFailed: false)
        })
        defer { slow.stop() }
        let host = NSHostingView(rootView: ReplicaSettingsView(state: state, initialTab: SettingsSection.privacy.rawValue, permissionModel: slow))
        let window = OffscreenSettingsWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 600), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        await pause()
        func nodes() -> [NSObject] { accessibilityTree(host).filter { axID($0) == "permission-refresh-status" } }
        func label() -> String? {
            let locals = texts(nodes())
            return locals.first { $0.contains("刷新") || $0.contains("整理") || $0.lowercased().contains("refresh") }
        }
        let idle = PermissionCopy.text("刷新状态", "重新整理狀態", "Refresh Status")
        func refreshedPrefix() -> String {
            String(PermissionCopy.text("已刷新 · %@", "已重新整理 · %@", "Refreshed · %@").split(separator: "%")[0])
        }
        try check(label() == idle, "refresh starts as \(idle): \(String(describing: label()))")
        guard let button = nodes().max(by: { axFrame($0).width < axFrame($1).width }) else {
            throw Failure(message: "refresh control is missing from the permission card title row")
        }
        try writePNG(host, name: "p4-\(language)-refresh-idle", out: out)
        try check(press(button), "refresh control rejects AX press")
        try await Task.sleep(nanoseconds: 80_000_000)
        try check(label() == PermissionCopy.text("正在刷新…", "正在重新整理…", "Refreshing…"),
                  "refresh shows no in-flight state: \(String(describing: label()))")
        try writePNG(host, name: "p4-\(language)-refresh-inflight", out: out)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if let value = label(), value.hasPrefix(refreshedPrefix()) { break }
            await pause()
        }
        guard let refreshed = label(), refreshed.hasPrefix(refreshedPrefix()) else {
            throw Failure(message: "refresh never reached the refreshed state: \(String(describing: label()))")
        }
        let stamp = String(refreshed.dropFirst(refreshedPrefix().count))
        try check(stamp.range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil,
                  "refreshed timestamp is not a 24-hour HH:mm: \(stamp)")
        try writePNG(host, name: "p4-\(language)-refresh-done", out: out)
        // 2 秒时仍要显示「已刷新」，3 秒后才淡出回「刷新状态」。
        try await Task.sleep(nanoseconds: 2_000_000_000)
        try check(label()?.hasPrefix(refreshedPrefix()) == true, "refreshed state disappears before its 3s window")
        try await Task.sleep(nanoseconds: 1_700_000_000)
        try check(label() == idle, "refresh label never returns to \(idle): \(String(describing: label()))")
        try writePNG(host, name: "p4-\(language)-refresh-restored", out: out)
    }

    /// 两个不可撤销动作：确认弹窗写明影响面、取消不改变状态、确认才落地。
    @MainActor static func verifyDangerActions(state: ReplicaUIState, out: URL, language: String) async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"]!)
        let directory = root.appendingPathComponent("build/danger-fixture-\(language)")
        try? FileManager.default.removeItem(at: directory)
        let dangerStore = try ClipboardStore(directoryURL: directory)
        for index in 0..<3 { _ = try dangerStore.add(ClipboardItem(plainText: "danger fixture \(index)")) }
        let pinnedBoard = try dangerStore.createPinboard(name: "danger pinned")
        let pinned = try dangerStore.add(ClipboardItem(plainText: "pinned fixture", pinboardIDs: [pinnedBoard.id], isInHistory: false, pinboardOwnerID: pinnedBoard.id))
        try dangerStore.save()
        try check(SettingsDangerAction.historyCount(in: dangerStore) == 3,
                  "history count does not match the three erase targets: \(SettingsDangerAction.historyCount(in: dangerStore))")
        let alert = SettingsDangerAction.makeClearHistoryAlert(count: 3)
        let confirmTitle = SettingsDangerAction.clearHistoryConfirmTitle(3)
        try check(alert.buttons.count == 2, "clear-history alert does not offer exactly confirm + cancel")
        try check(alert.buttons[0].title == SettingsCopy.text("general.action.cancel"), "cancel is not the first button")
        try check(alert.buttons[1].title == confirmTitle && confirmTitle.contains("3"),
                  "confirm button does not carry the count: \(alert.buttons[1].title)")
        try check(alert.buttons[1].hasDestructiveAction, "clear-history confirm is not marked destructive")
        try check(alert.buttons[0].keyEquivalent == "\r" && alert.buttons[1].keyEquivalent.isEmpty,
                  "Return is not bound to cancel only")
        try check(alert.informativeText.contains("3"), "story text does not name how many entries go: \(alert.informativeText)")
        try check(alert.informativeText.contains("撤销") || alert.informativeText.contains("復原")
                    || alert.informativeText.lowercased().contains("undo"),
                  "story text does not say the action cannot be undone: \(alert.informativeText)")
        let window = OffscreenSettingsWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        var confirms = 0
        let erase = { try? dangerStore.eraseHistory() }
        SettingsDangerAction.present(alert, on: window) {
            confirms += 1
            erase()
        }
        let settleDeadline = Date().addingTimeInterval(3)
        while window.attachedSheet !== alert.window && Date() < settleDeadline { await pause() }
        try check(window.attachedSheet === alert.window, "clear-history confirmation is not presented as a sheet")
        if let frameView = alert.window.contentView?.superview {
            try writePNG(frameView, name: "p4-\(language)-confirm-clear-history", out: out)
        }
        alert.buttons[0].performClick(nil)
        let cancelDeadline = Date().addingTimeInterval(3)
        while window.attachedSheet != nil && Date() < cancelDeadline { await pause() }
        try check(confirms == 0, "cancelling the clear-history alert still ran the destructive action")
        try check(SettingsDangerAction.historyCount(in: dangerStore) == 3, "cancelling the alert still erased history")
        let confirmAlert = SettingsDangerAction.makeClearHistoryAlert(count: 3)
        SettingsDangerAction.present(confirmAlert, on: window) {
            confirms += 1
            erase()
        }
        let agreeDeadline = Date().addingTimeInterval(3)
        while window.attachedSheet !== confirmAlert.window && Date() < agreeDeadline { await pause() }
        confirmAlert.buttons[1].performClick(nil)
        let doneDeadline = Date().addingTimeInterval(3)
        while window.attachedSheet != nil && Date() < doneDeadline { await pause() }
        try check(confirms == 1, "confirming the clear-history alert did not run exactly once")
        try check(SettingsDangerAction.historyCount(in: dangerStore) == 0, "confirmed clear did not erase the three history entries")
        try check(dangerStore.items.contains { $0.id == pinned }, "confirmed clear removed a pinned item")

        // 「恢复全部快捷键…」：确认文案必须点名 6 条，取消不改任何偏好。
        for row in SettingsShortcutRow.allCases {
            if let path = row.path { dangerStore.preferences[keyPath: path] = (nil as BlinkClipCore.KeyboardShortcut?) }
            if let path = row.modifierPath { dangerStore.preferences[keyPath: path] = 0 }
        }
        try dangerStore.save()
        let before = dangerStore.preferences
        let resetAlert = SettingsShortcutReset.makeAlert()
        try check(resetAlert.informativeText.contains("6"),
                  "restore-all scope does not name the six shortcuts: \(resetAlert.informativeText)")
        try check(resetAlert.buttons.count == 2 && resetAlert.buttons[0].title == SettingsCopy.text("general.action.cancel"),
                  "restore-all confirmation does not offer cancel first")
        var resetConfirmed: Bool?
        // 走生产入口：先以 sheet 呈现（这样截图是真实的确认弹窗），再分别点取消与确认。
        SettingsShortcutReset.present(resetAlert, on: window) { confirmed in
            resetConfirmed = confirmed
            if confirmed {
                _ = try? SettingsShortcutReset.apply(confirmed: true, store: dangerStore,
                                                     commitScreenshots: {}, reload: {})
            }
        }
        let resetDeadline = Date().addingTimeInterval(3)
        while window.attachedSheet !== resetAlert.window && Date() < resetDeadline { await pause() }
        try check(window.attachedSheet === resetAlert.window, "restore-all confirmation is not presented as a sheet")
        if let frameView = resetAlert.window.contentView?.superview {
            try writePNG(frameView, name: "p4-\(language)-confirm-reset-shortcuts", out: out)
        }
        resetAlert.buttons[0].performClick(nil)
        let resetCancelDeadline = Date().addingTimeInterval(3)
        while window.attachedSheet != nil && Date() < resetCancelDeadline { await pause() }
        try check(resetConfirmed == false, "restore-all cancel reported a confirmation")
        try check(dangerStore.preferences == before, "cancelling restore-all changed preferences")
        try check(dangerStore.preferences.historyShortcut == nil && dangerStore.preferences.stackShortcut == nil,
                  "cancelled restore-all wrote defaults anyway")
        let confirmReset = SettingsShortcutReset.makeAlert()
        SettingsShortcutReset.present(confirmReset, on: window) { confirmed in
            resetConfirmed = confirmed
            if confirmed {
                _ = try? SettingsShortcutReset.apply(confirmed: true, store: dangerStore,
                                                     commitScreenshots: {}, reload: {})
            }
        }
        let resetAgreeDeadline = Date().addingTimeInterval(3)
        while window.attachedSheet !== confirmReset.window && Date() < resetAgreeDeadline { await pause() }
        confirmReset.buttons[1].performClick(nil)
        let resetDoneDeadline = Date().addingTimeInterval(3)
        while window.attachedSheet != nil && Date() < resetDoneDeadline { await pause() }
        try check(resetConfirmed == true, "restore-all confirm did not report a confirmation")
        try check(dangerStore.preferences.historyShortcut == .historyDefault
                    && dangerStore.preferences.stackShortcut == .stackDefault,
                  "confirmed restore-all did not restore the six shortcuts")
    }

    /// 冲突提示：归属正在编辑的那一行、文案指名占用者、被拒之后仍保持录制态。
    @MainActor static func verifyShortcutConflict(state: ReplicaUIState, out: URL, language: String) async throws {
        let store = state.store
        let historyRow = SettingsShortcutRow.history
        let stackRow = SettingsShortcutRow.stack
        let historyValue = KeyboardShortcut(keyCode: 16, modifierRawValue: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        let stackValue = KeyboardShortcut(keyCode: 7, modifierRawValue: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        let retryValue = KeyboardShortcut(keyCode: 6, modifierRawValue: NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        store.preferences[keyPath: historyRow.path!] = historyValue
        store.preferences[keyPath: stackRow.path!] = stackValue
        try store.save()
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("local.blinkclip.regression.") else {
            throw Failure(message: "isolated test app domain required")
        }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        defer {
            store.preferences[keyPath: historyRow.path!] = nil
            store.preferences[keyPath: stackRow.path!] = nil
            _ = try? store.save()
        }
        let host = NSHostingView(rootView: ReplicaSettingsView(state: state, initialTab: SettingsSection.shortcuts.rawValue))
        let window = OffscreenSettingsWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 900), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.frame.maxX + 200, y: screen.frame.maxY + 200))
        }
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        await pause()
        func recorderNode(_ row: SettingsShortcutRow) -> NSRect? {
            accessibilityTree(host).filter { axID($0) == "settings.shortcut.recorder." + row.rawValue }
                .map { axFrame($0) }
                .first { abs($0.width - 120) <= 1 && abs($0.height - 24) <= 1 }
        }
        func errorNode(_ row: SettingsShortcutRow) -> NSRect? {
            accessibilityTree(host).filter { axID($0) == "settings.shortcut.error." + row.rawValue }
                .map { axFrame($0) }
                .max { $0.width < $1.width }
        }
        func pressRecorder(_ row: SettingsShortcutRow) throws {
            guard let node = accessibilityTree(host).first(where: {
                axID($0) == "settings.shortcut.recorder." + row.rawValue
                    && abs(axFrame($0).width - 120) <= 1 && abs(axFrame($0).height - 24) <= 1
            }), press(node) else {
                throw Failure(message: "recorder for \(row) does not accept AX press")
            }
        }
        func sendKey(_ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags) {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil,
                                         characters: characters, charactersIgnoringModifiers: characters,
                                         isARepeat: false, keyCode: keyCode)!
            NSApp.sendEvent(event)
        }
        try pressRecorder(historyRow)
        await pause()
        // ⌘⇧X 已经被「打开堆栈面板」占着：这一次赋值必须被拒。
        sendKey(7, "x", [.command, .shift])
        await pause()
        try await Task.sleep(nanoseconds: 150_000_000)
        await pause()
        guard let error = errorNode(historyRow), let recorder = recorderNode(historyRow) else {
            throw Failure(message: "conflict hint is missing under the history row")
        }
        let hint = texts(accessibilityTree(host).filter { axID($0) == "settings.shortcut.error." + historyRow.rawValue })
        try check(hint.contains { $0.contains(stackRow.title) },
                  "conflict hint does not name the occupying row (\(stackRow.title)): \(hint)")
        // 窗口坐标 y 向上：行的底边 = 录制器底边 − (minHeight 36 − 24) / 2 = −6pt。
        let rowBottom = recorder.minY - 6
        let gap = rowBottom - error.maxY
        try check(gap >= -0.5 && gap <= 8, "conflict hint is \(gap)pt below the edited row, expected 0...8")
        try check(store.preferences[keyPath: historyRow.path!] == historyValue,
                  "a rejected combination was written into preferences anyway")
        try check(store.preferences[keyPath: stackRow.path!] == stackValue, "the occupying row lost its shortcut")
        try writePNG(host, name: "p4-\(language)-shortcut-conflict", out: out)
        // 提示还在，录制也还在：不再点第二次，直接改按 ⌘⇧Z，应当立刻落成新值。
        sendKey(6, "z", [.command, .shift])
        await pause()
        try await Task.sleep(nanoseconds: 150_000_000)
        try check(store.preferences[keyPath: historyRow.path!] == retryValue,
                  "recording did not stay armed after the conflict: \(String(describing: store.preferences[keyPath: historyRow.path!]))")
        try check(errorNode(historyRow) == nil, "conflict hint survived a successful reassignment")

        // 截图热键行同一口径：⌘⇧X 仍被「打开堆栈面板」占着，提示落在截图行正下方并指名它。
        let regionValue = BlinkClipScreenshotSettings.effectiveShortcut(for: .region)
        defer {
            if let regionValue { BlinkClipScreenshotSettings.setShortcut(regionValue, for: .region, force: true) }
        }
        try pressRecorder(.region)
        await pause()
        sendKey(7, "x", [.command, .shift])
        await pause()
        try await Task.sleep(nanoseconds: 150_000_000)
        guard let hotKeyError = errorNode(.region), let hotKeyRecorder = recorderNode(.region) else {
            throw Failure(message: "conflict hint is missing under the screenshot hotkey row")
        }
        let hotKeyHint = texts(accessibilityTree(host).filter { axID($0) == "settings.shortcut.error.region" })
        try check(hotKeyHint.contains { $0.contains(stackRow.title) },
                  "screenshot conflict hint does not name the occupying row: \(hotKeyHint)")
        let hotKeyGap = (hotKeyRecorder.minY - 6) - hotKeyError.maxY
        try check(hotKeyGap >= -0.5 && hotKeyGap <= 8,
                  "screenshot conflict hint is \(hotKeyGap)pt below its row, expected 0...8")
        try check(BlinkClipScreenshotSettings.effectiveShortcut(for: .region) == regionValue,
                  "a rejected screenshot shortcut was written anyway")
        try writePNG(host, name: "p4-\(language)-shortcut-conflict-hotkey", out: out)
    }

    @MainActor static func main() async {
        do { try await run() } catch { print("FAIL \(error)"); exit(1) }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.finishLaunching()
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        let language = Locale.preferredLanguages.first ?? "unknown"
        let runID = ProcessInfo.processInfo.environment["BLINKCLIP_SETTINGS_RUN_ID"] ?? "1"
        guard ["1", "2", "3"].contains(runID),
              let artifactRoot = ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"] else {
            throw Failure(message: "managed artifact directory and valid run ID required")
        }
        let fixture = URL(fileURLWithPath: artifactRoot, isDirectory: true)
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("fixture-\(runID)-\(language)", isDirectory: true)
        let store = try ClipboardStore(directoryURL: fixture)
        let state = ReplicaUIState(store: store)
        let model = PermissionStatusModel(readAccessibility: { true }, readPostEvents: { true }, readScreenRecording: { true }, requestScreenAccess: {}, requestAccessibilityAccess: {})
        try check(SettingsSection.allCases.map(\.rawValue) == [0,3,2,4,1,5], "stable ordered section IDs")
        try check(SettingsSection(rawValue: 2) == .screenshot, "screenshot deep link preserved")
        // The six sidebar names are trilingual now: under zh-Hant every one of
        // them must be Traditional, and no Simplified-only spelling may survive.
        // 关于页的图标是真实应用图标（离屏渲染的证据要能看出是闪贴）。
        let iconURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Assets/BlinkClipIcon.png")
        if let image = NSImage(contentsOf: iconURL) { NSApp.applicationIconImage = image }
        let settingsLanguage = SettingsCopy.language
        let sectionTitles = SettingsSection.allCases.map(\.title)
        if settingsLanguage == .zhHant {
            try check(sectionTitles == ["一般", "剪貼簿與歷史記錄", "截圖", "快捷鍵", "隱私與權限", "AI 工具"],
                      "zh-Hant sidebar names: \(sectionTitles)")
            let simplifiedOnly = ["设置", "默认", "剪贴板", "屏幕", "恢复", "窗口", "保存", "应用", "快捷键", "历史", "权限", "复制"]
            for title in sectionTitles {
                for term in simplifiedOnly {
                    try check(!title.contains(term), "zh-Hant sidebar name still Simplified: \(title) contains \(term)")
                }
            }
        } else if settingsLanguage == .zhHans {
            try check(sectionTitles == ["通用", "剪贴板与历史", "截图", "快捷键", "隐私与权限", "AI 工具"],
                      "zh-Hans sidebar names: \(sectionTitles)")
        }
        let originalRetention = store.preferences.historyRetentionDays
        var screenshotHeader: Data?
        rowAlignmentGeometry = [:]
        cardCentringGeometry = [:]
        for appearance in ["light", "dark"] {
        NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        captures = []
        firstElementOffsets = [:]
        for section in SettingsSection.allCases {
            let hosting = NSHostingView(rootView: ReplicaSettingsView(state: state, initialTab: section.rawValue, permissionModel: model).background(Color(nsColor: .windowBackgroundColor)))
            let window = OffscreenSettingsWindow(contentRect: NSRect(x: -5000,y: -5000,width: 648,height: 600),styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],backing: .buffered,defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unified
            window.setFrame(NSRect(x: -5000, y: -5000, width: 648, height: 600), display: false)
            window.contentView = hosting
            window.orderFront(nil)
            await pause()
            hosting.layoutSubtreeIfNeeded()
            try check(hosting.bounds.width >= 640, "minimum width")
            try await checkPageSurface(hosting: hosting, window: window, section: section, appearance: appearance)
            // 卡片内容垂直居中：在滚到底之前、同一张出货尺寸渲染上量（页面原点 0），
            // 这样每张卡都在视口内可以从卡顶量到卡底。
            try measureCardCentring(hosting: hosting, window: window, section: section,
                                    appearance: appearance, out: out)
            if appearance == "light", section == .screenshot { screenshotHeader = try pixels(hosting, headerOnly: true) }
            guard let themeFrame = window.contentView?.superview,
                  let title = descendants(themeFrame, of: NSTextField.self).first(where: { $0.accessibilityIdentifier() == "BlinkClipSettingsPaneTitle" }) else { throw Failure(message: "missing complete native titlebar") }
            let titleFrame = title.convert(title.bounds, to: nil)
            try check(title.stringValue == section.title, "native toolbar title matches section")
            try check(titleFrame.minY >= window.contentLayoutRect.maxY, "title above contentLayoutRect: \(titleFrame), layout \(window.contentLayoutRect)")
            try check(titleFrame.minX >= 200, "toolbar title right of sidebar")
            try check(window.frame.maxX < 0 && window.frame.maxY < 0, "window remains entirely off physical screens")
            try check(window.frame.size == NSSize(width: 648, height: 600), "fixed complete window frame: \(window.frame)")
            guard let toolbar = window.toolbar, let owner = toolbar.delegate as? SettingsSplitViewController else { throw Failure(message: "production toolbar delegate missing") }
            try check(title.isEnabled, "native toolbar title label remains enabled")
            try check(toolbar.items.first(where: { $0.view === title })?.isEnabled == true, "native title toolbar item remains enabled")
            let originalItems = toolbar.items.map { ObjectIdentifier($0) }
            for _ in 0..<100 {
                owner.paneTitle = section.title
                owner.viewDidLayout()
            }
            try check(window.toolbar === toolbar && toolbar.items.map { ObjectIdentifier($0) } == originalItems, "100 same-title/layout updates preserve toolbar and item identity")

            try capture(themeFrame, name: "\(language)-\(section.rawValue)-top-640pt", out: out)
            // 单页 2x 截图（本轮的卡片居中证据用）：默认不写，避免每次回归多落几十张图。
            if ProcessInfo.processInfo.environment["BLINKCLIP_PAGE_RENDERS"] == "1" {
                try writePNG(themeFrame, name: "\(language)-\(appearance)-\(section.rawValue)-page", out: out)
            }
            let beforeScrollHeader = try pixels(hosting, headerOnly: true)
            if true {
                let key = "\(appearance)-\(section.rawValue)"
                let fitsOneScreen = pageGeometry[key]?["fitsOneScreen"] == 1
                let scrolls = descendants(hosting, of: NSScrollView.self)
                for scroll in scrolls where scroll.documentView != nil {
                    let document = scroll.documentView!
                    scroll.contentView.scroll(to: NSPoint(x: 0,y: max(0,document.bounds.height-scroll.contentView.bounds.height)))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                await pause()
                try capture(themeFrame, name: "\(language)-\(section.rawValue)-bottom-648x600", out: out)
                try check(title.convert(title.bounds, to: nil) == titleFrame, "native toolbar frame stable after scroll")
                try check(try pixels(hosting, headerOnly: true) == beforeScrollHeader, "\(appearance) \(section) header pixels unchanged after scrolling")
                // 滚到底之后：装不下一屏的分区必须真的滚动了、并且最后一个内容块仍
                // 距内容区底 16pt（能滚到底，不是被裁掉）；装得下的分区一格都不滚。
                guard let pageScroll = scrolls.filter({ $0.documentView != nil })
                    .max(by: { $0.contentView.bounds.height < $1.contentView.bounds.height }) else {
                    throw Failure(message: "\(appearance) \(section) has no page scroll view to scroll")
                }
                let hidden = max(0, (pageScroll.documentView?.bounds.height ?? 0) - pageScroll.contentView.bounds.height)
                if fitsOneScreen {
                    try check(hidden <= 0.5 && pageScroll.contentView.bounds.origin.y == 0,
                              "\(appearance) \(section) fits one screen but still scrolled by \(pageScroll.contentView.bounds.origin.y) of \(hidden)")
                } else {
                    try check(pageScroll.contentView.bounds.origin.y >= hidden - 1,
                              "\(appearance) \(section) did not reach the bottom: origin \(pageScroll.contentView.bounds.origin.y) hidden \(hidden)")
                    let contentBottom = window.convertPoint(toScreen: NSPoint(x: 0, y: window.contentLayoutRect.minY)).y
                    guard let edges = contentEdges(hosting, window: window) else {
                        throw Failure(message: "\(appearance) \(section) has no content bottom after scrolling")
                    }
                    let gapAfterScroll = edges.bottom - contentBottom
                    try check(gapAfterScroll >= SettingsPageMetrics.bottomInset - 1.5
                              && gapAfterScroll <= SettingsPageMetrics.bottomInset + 4,
                              "\(appearance) \(section) bottom inset after scrolling is \(gapAfterScroll), expected \(SettingsPageMetrics.bottomInset)")
                }
            }
            // 行内对齐：右侧开关外框中心 == 该行文字块中心（单行对文字行高中心，
            // 双行对标题+说明整块中心），误差 ≤0.5pt。
            try checkRowAlignment(hosting: hosting, section: section, appearance: appearance)
            if section == .ai {
                try checkAIStatusDotAlignment(hosting: hosting, appearance: appearance)
            }
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        // 关于是内容区里的第七页：与六个分区同一套宿主、同一套节奏，不弹独立窗口。
        let aboutHosting = NSHostingView(rootView: ReplicaSettingsView(
            state: state, initialTab: SettingsAboutPane.tabIndex, permissionModel: model).background(Color(nsColor: .windowBackgroundColor)))
        let aboutWindow = OffscreenSettingsWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 600),
                                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                                  backing: .buffered, defer: false)
        aboutWindow.isReleasedWhenClosed = false
        aboutWindow.titlebarAppearsTransparent = false
        aboutWindow.toolbarStyle = .unified
        aboutWindow.setFrame(NSRect(x: -5000, y: -5000, width: 648, height: 600), display: false)
        aboutWindow.contentView = aboutHosting
        aboutWindow.orderFront(nil)
        await pause()
        try await checkAboutPage(hosting: aboutHosting, window: aboutWindow,
                                 appearance: appearance, language: language, out: out)
        aboutWindow.orderOut(nil)
        aboutWindow.contentView = nil
        aboutWindow.close()
        // 六页所有卡片都量过之后再统一断言：某一张不达标不影响其它卡的实测值落盘。
        try writeCardCentringReport(appearance: appearance, language: language, out: out)
        // 六页一律顶部对齐：首元素距内容区顶固定 16pt，不再按「装得下就居中」
        // 分类。装得下的页不滚，装不下的页从同一位置滚到底。
        let pageOffsets = firstElementOffsets.filter { $0.key.hasPrefix(appearance + "-") }
        try check(pageOffsets.count == SettingsSection.allCases.count,
                  "\(appearance) only \(pageOffsets.count) pages measured: \(pageOffsets.keys.sorted())")
        for key in pageOffsets.keys {
            guard let geometry = pageGeometry[key] else { throw Failure(message: "\(key) has no geometry") }
            try check(abs(geometry["topGap"]! - Double(SettingsPageMetrics.topInset)) <= 0.5,
                      "\(appearance) \(key) is not top aligned at \(SettingsPageMetrics.topInset)pt: \(geometry)")
        }
        if !captures.isEmpty {
            let cell = NSSize(width: 648, height: 622)
            let sheet = NSImage(size: NSSize(width: cell.width * 4, height: cell.height * 3))
            sheet.lockFocus()
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: sheet.size).fill()
            for (index, pair) in captures.enumerated() {
                let x = CGFloat(index % 4) * cell.width
                let y = CGFloat(2 - index / 4) * cell.height
                pair.1.draw(in: NSRect(x: x, y: y, width: 648, height: 600))
                (pair.0 as NSString).draw(at: NSPoint(x: x + 8, y: y + 602), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
            }
            sheet.unlockFocus()
            let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(language)-\(appearance)-seven-pages-top-scroll-offscreen.png"))
        }
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        // ---- shared surface contract (color math, independent of rendering) ----
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            var page = NSColor.windowBackgroundColor
            appearance.performAsCurrentDrawingAppearance {
                page = NSColor.windowBackgroundColor.usingColorSpace(.sRGB) ?? page
            }
            let card = SettingsSurfaceStyle.composite(SettingsSurfaceStyle.cardBackground(dark: dark), over: page)
            let pageLevel = Int((page.redComponent * 255).rounded())
            let cardLevel = Int((card.redComponent * 255).rounded())
            try check(SettingsSurfaceStyle.relativeLuminance(card) > SettingsSurfaceStyle.relativeLuminance(page),
                      "dark=\(dark) card is not brighter than the page: card \(cardLevel) page \(pageLevel)")
            try check(cardLevel - pageLevel >= 8 || (!dark && cardLevel == 255),
                      "dark=\(dark) card/page separation too small: card \(cardLevel) page \(pageLevel)")
            let caption = SettingsSurfaceStyle.composite(SettingsSurfaceStyle.secondaryText(dark: dark), over: card)
            let contrast = SettingsSurfaceStyle.contrastRatio(caption, over: card)
            try check(contrast >= 4.5,
                      "dark=\(dark) caption contrast \(contrast) on card \(cardLevel) is below 4.5:1")
            let border = SettingsSurfaceStyle.composite(SettingsSurfaceStyle.cardBorder(dark: dark), over: card)
            try check(SettingsSurfaceStyle.contrastRatio(border, over: card) >= 1.05,
                      "dark=\(dark) 1pt card border is invisible: \(SettingsSurfaceStyle.contrastRatio(border, over: card))")
        }

        // Independent navigation path: real native outline selection, compared with
        // the rendered screenshot deep-link header. The sidebar is excluded from ROI.
        let navigationHost = NSHostingView(rootView: ReplicaSettingsView(state: state, initialTab: 0, permissionModel: model).background(Color(nsColor: .windowBackgroundColor)))
        let navigationWindow = OffscreenSettingsWindow(contentRect: NSRect(x: -5000,y: -5000,width: 648,height: 600),styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],backing: .buffered,defer: false)
        navigationWindow.isReleasedWhenClosed = false
        navigationWindow.titlebarAppearsTransparent = false
        navigationWindow.toolbarStyle = .unified
        navigationWindow.setFrame(NSRect(x: -5000, y: -5000, width: 648, height: 600), display: false)
        navigationWindow.contentView = navigationHost
        navigationWindow.orderFront(nil)
        await pause()
        let beforeHeader = try pixels(navigationHost, headerOnly: true)
        let beforeBody = try pixels(navigationHost, headerOnly: false)
        guard let targetHeader = screenshotHeader else { throw Failure(message: "missing screenshot reference") }
        try check(beforeHeader != targetHeader, "general and screenshot headers differ before navigation")
        // 六项分区 + 末尾的「关于闪贴」动作行：动作行不是分区，选中态与顺序都不变。
        guard let navigation = descendants(navigationHost, of: NSOutlineView.self).first(where: { $0.numberOfRows == 7 }) else { throw Failure(message: "native seven-row outline not found") }
        navigation.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        navigation.delegate?.outlineViewSelectionDidChange?(Notification(name: NSOutlineView.selectionDidChangeNotification, object: navigation))
        let deadline = Date().addingTimeInterval(3)
        while (navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle != SettingsSection.screenshot.title && Date() < deadline { await pause() }
        try capture(navigationHost, name: "\(language)-navigation-to-screenshot-640pt", out: out)
        try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == SettingsSection.screenshot.title, "native sidebar updates exact screenshot title")
        guard let navigationFrame = navigationWindow.contentView?.superview,
              let nativeTitle = descendants(navigationFrame, of: NSTextField.self).first(where: { $0.accessibilityIdentifier() == "BlinkClipSettingsPaneTitle" }) else { throw Failure(message: "navigation native title missing") }
        try check(nativeTitle.stringValue == SettingsSection.screenshot.title, "native toolbar rendered label receives screenshot title")
        try check(try pixels(navigationHost, headerOnly: false) != beforeBody, "right content changes after native navigation")
        let navigationToolbar = navigationWindow.toolbar
        for (row, section) in SettingsSection.allCases.enumerated() {
            navigation.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            navigation.delegate?.outlineViewSelectionDidChange?(Notification(name: NSOutlineView.selectionDidChangeNotification, object: navigation))
            await pause()
            try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == section.title, "native selection title \(section)")
            try check(navigationWindow.toolbar === navigationToolbar, "navigation retains toolbar")
        }
        // 页脚已删：产品名不再作为侧栏页脚出现；「关于闪贴」变成列表里的最后一行。
        let sidebarNodes = accessibilityTree(navigationHost)
        // The rendered sidebar must carry the same six trilingual names the
        // production provider returns for this process language.
        var sidebarLabels = Set<String>()
        for node in sidebarNodes {
            for attribute in [NSAccessibility.Attribute.value, .title, .description] {
                if let text = node.accessibilityAttributeValue(attribute) as? String { sidebarLabels.insert(text) }
            }
            for name in ["accessibilityLabel", "accessibilityValue"] {
                let selector = NSSelectorFromString(name)
                if node.responds(to: selector), let text = node.perform(selector)?.takeUnretainedValue() as? String {
                    sidebarLabels.insert(text)
                }
            }
        }
        for section in SettingsSection.allCases {
            try check(sidebarLabels.contains(section.title),
                      "rendered sidebar is missing \(section.title) in \(settingsLanguage.rawValue): \(sidebarLabels.sorted())")
        }
        try check(!sidebarNodes.contains { axID($0) == "BlinkClipSettingsProductName" },
                  "the removed settings-footer product name is still rendered")
        try check(sidebarNodes.contains { axID($0) == "BlinkClipSettingsAbout" }, "sidebar is missing the About BlinkClip row")
        let aboutRowIndex = SettingsSection.allCases.count
        try check(aboutRowIndex == 6, "About row is not the seventh row")
        let aboutTitle = SettingsCopy.text("updates.about-title")
        // 点侧栏「关于闪贴」：右侧内容区换成关于页、标题栏跟着换，**不弹独立窗口**。
        navigation.selectRowIndexes(IndexSet(integer: aboutRowIndex), byExtendingSelection: false)
        navigation.delegate?.outlineViewSelectionDidChange?(Notification(name: NSOutlineView.selectionDidChangeNotification, object: navigation))
        await pause()
        await pause()
        try check(navigation.selectedRowIndexes == IndexSet(integer: aboutRowIndex),
                  "the About row is not the selected row: \(navigation.selectedRowIndexes)")
        try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == aboutTitle,
                  "the About row did not put About BlinkClip in the title bar: \(String(describing: (navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle))")
        let aboutNodes = accessibilityTree(navigationHost)
        for identifier in ["about-application-icon", "about-product-name", "about-current-version",
                           "about-description", "about-update-status", "about-check-updates",
                           "about-project-link", "about-release-notes-link", "about-copyright",
                           "about-license-link"] {
            try check(aboutNodes.contains { axID($0) == identifier },
                      "the About page is missing \(identifier) in \(language)")
        }
        try check(!aboutNodes.contains { axID($0) == "about-close" },
                  "the About page carries a Close button again")
        try check(!NSApp.windows.contains { $0.identifier?.rawValue == "blinkclip-about-window" },
                  "selecting About opened an independent About window")
        if ProcessInfo.processInfo.environment["BLINKCLIP_SKIP_SCREENSHOTS"] != "1",
           let frame = navigationWindow.contentView?.superview {
            try writePNG(frame, name: "\(language)-about-pane-selected", out: out)
        }
        // 再点一次同一行：不另开窗口，标题与内容不动。
        navigation.delegate?.outlineViewSelectionDidChange?(Notification(name: NSOutlineView.selectionDidChangeNotification, object: navigation))
        await pause()
        try check(!NSApp.windows.contains { $0.identifier?.rawValue == "blinkclip-about-window" },
                  "repeated About selection opened an About window")
        try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == aboutTitle,
                  "repeated About selection lost the title")
        // 从关于页切回通用页：选中态、标题与内容一起回到分区（关于页没有「关闭」这一步）。
        navigation.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        navigation.delegate?.outlineViewSelectionDidChange?(Notification(name: NSOutlineView.selectionDidChangeNotification, object: navigation))
        await pause()
        try check(navigation.selectedRowIndexes == IndexSet(integer: 0),
                  "leaving the About page did not select General: \(navigation.selectedRowIndexes)")
        try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == SettingsSection.general.title,
                  "leaving the About page did not restore the General title")
        try check(accessibilityTree(navigationHost).contains { axID($0) == "settings.automatic-updates.toggle" },
                  "leaving the About page did not restore the General content")
        if ProcessInfo.processInfo.environment["BLINKCLIP_SKIP_SCREENSHOTS"] != "1",
           let frame = navigationWindow.contentView?.superview {
            try writePNG(frame, name: "\(language)-about-pane-left", out: out)
        }
        navigationWindow.contentView = NSHostingView(rootView: ReplicaSettingsView(state: state, initialTab: 2, permissionModel: model))
        await pause()
        try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == SettingsSection.screenshot.title, "deep-link root replacement installs current title delegate")
        navigationWindow.orderOut(nil)
        navigationWindow.orderFront(nil)
        await pause()
        try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == SettingsSection.screenshot.title, "reopen preserves title and delegate")
        navigationWindow.orderOut(nil); navigationWindow.contentView = nil; navigationWindow.close()
        if runID == "1" {
            try await verifyAppearanceLanguageRows(state: state, model: model, out: out, language: language)
            try await verifyAutomaticUpdateToggle(state: state, model: model, out: out, language: language)
            try await verifyRefreshFeedback(state: state, out: out, language: language)
            try await verifyDangerFooter(state: state, out: out, language: language)
            try await verifyDangerActions(state: state, out: out, language: language)
            try await verifyShortcutConflict(state: state, out: out, language: language)
        }
        try await verifyShortcutRows(store: store, state: state, model: model, out: out, language: language)
        model.stop()
        try check(store.preferences.historyRetentionDays == originalRetention, "viewing pages does not change retention")
        let reopened = try ClipboardStore(directoryURL: fixture)
        try check(reopened.preferences.historyRetentionDays == originalRetention, "persisted retention unchanged")
        let result: [String: Any] = ["passed":true,"assertions":assertions,"language":language,"runID":runID,"fixtureDirectory":fixture.path,
            "pageGeometry": pageGeometry.mapValues { $0.mapValues { $0 } },
            "rowAlignment": rowAlignmentGeometry,
            "cardCentring": cardCentringGeometry,
            "about": aboutGeometry,
            "topInset": SettingsPageMetrics.topInset,
            "bottomInset": SettingsPageMetrics.bottomInset,
            "sections":SettingsSection.allCases.map(\.title),"settingsLanguage":SettingsCopy.language.rawValue,"evidence":"Actual ReplicaSettingsView offscreen complete NSWindow theme frame including traffic lights and native NSToolbar; 648x600 window with production SettingsSplitView toolbar delegate path, seven sidebar rows (six sections plus the About action row) light/dark top/scrolled header pixel invariance; isolated store and injected permissions. No live user history/TCC requests. Initial-tab navigation plus native NSOutlineView selection and exact native toolbar title checked; right content also changes; the removed footer product name is absent and the About row is the seventh page inside the right content area (no independent About window): native selection updates the pane title to the About BlinkClip copy, the page is top aligned at 16pt, with separate identity, update card and project footer, and leaving it selects General again. No physical mouse clicks."]
        let data = try JSONSerialization.data(withJSONObject: result, options:[.prettyPrinted,.sortedKeys])
        try data.write(to: out.appendingPathComponent("result-\(language).json"))
        print(String(decoding:data,as:UTF8.self))
    }
}
