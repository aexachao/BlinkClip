import AppKit

extension NSImage {
    /// 把模板图染成单一颜色。`SOURCE_ATOP` 只保留图标自身的 alpha 形状，
    /// 所以同一张 16×16 的 SF Symbol 在浅色 / 深色底上都能用。
    func tinted(_ color: NSColor) -> NSImage? {
        let canvas = NSImage(size: size)
        canvas.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        rect.fill()
        draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
        canvas.unlockFocus()
        return canvas
    }
}

/// 离屏画出**展开的菜单**。
///
/// 系统 `NSMenu` 的绘制不归我们管，所以这里把生产模型里的分组、标题、
/// 实际 SF Symbol 图标和快捷键按系统菜单的观感排版成一张 PNG：
/// 行、图标列、分隔线、置灰行都是真实数据，不是另写一份文案。
/// 边界写在 harness 报告的 `boundary` 里。
final class PanelShortcutMenuSurfaceView: NSView {
    enum Row {
        case item(PanelShortcutMenuItem)
        case separator
    }

    static let titleFont = NSFont.systemFont(ofSize: 13)
    static let keyFont = NSFont.systemFont(ofSize: 13)
    static let cornerRadius: CGFloat = 12
    static let horizontalPadding: CGFloat = 12
    static let iconTitleGap: CGFloat = 10
    static let titleKeyGap: CGFloat = 24
    static let rowHeight: CGFloat = 24
    static let separatorRowHeight: CGFloat = 11
    static let verticalPadding: CGFloat = 6
    static let minWidth: CGFloat = 232

    let rows: [Row]

    init(rows: [Row]) {
        self.rows = rows
        super.init(frame: NSRect(origin: .zero, size: Self.measure(rows)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未实现") }

    override var isFlipped: Bool { true }

    static func rows(groups: [PanelShortcutMenuGroup]) -> [Row] {
        var rows: [Row] = []
        for (index, group) in groups.enumerated() {
            if index > 0 { rows.append(.separator) }
            rows.append(contentsOf: group.items.map { .item($0) })
        }
        return rows
    }

    static func measure(_ rows: [Row]) -> NSSize {
        var width = minWidth
        var height = verticalPadding * 2
        for row in rows {
            switch row {
            case .separator:
                height += separatorRowHeight
            case .item(let item):
                height += rowHeight
                let title = (item.title as NSString)
                    .size(withAttributes: [.font: titleFont]).width
                let key = (item.keyEquivalentDisplay as NSString)
                    .size(withAttributes: [.font: keyFont]).width
                // 带子菜单的父项在系统菜单里右侧有一个 ▸，这里同样留出位置。
                let disclosure: CGFloat = item.submenu == nil ? 0 : 12
                let needed = horizontalPadding + PanelShortcutMenuLayout.iconSide + iconTitleGap
                    + title + titleKeyGap + key + disclosure + horizontalPadding
                width = max(width, needed.rounded(.up))
            }
        }
        return NSSize(width: width, height: height)
    }

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = isDark
        let background = dark ? NSColor(calibratedWhite: 0.17, alpha: 1)
                              : NSColor(calibratedWhite: 0.98, alpha: 1)
        let border = dark ? NSColor(calibratedWhite: 1, alpha: 0.14)
                          : NSColor(calibratedWhite: 0, alpha: 0.14)
        let primary = dark ? NSColor(calibratedWhite: 1, alpha: 0.92)
                           : NSColor(calibratedWhite: 0.1, alpha: 0.92)
        let secondary = primary.withAlphaComponent(0.55)

        let panel = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                 xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        background.setFill()
        panel.fill()
        border.setStroke()
        panel.lineWidth = 1
        panel.stroke()

        var y = Self.verticalPadding
        for row in rows {
            switch row {
            case .separator:
                let line = NSRect(x: Self.horizontalPadding,
                                  y: y + Self.separatorRowHeight / 2,
                                  width: bounds.width - Self.horizontalPadding * 2,
                                  height: 1)
                primary.withAlphaComponent(0.12).setFill()
                line.fill()
                y += Self.separatorRowHeight
            case .item(let item):
                draw(item, rowY: y, primary: primary, secondary: secondary)
                y += Self.rowHeight
            }
        }
    }

    private func draw(_ item: PanelShortcutMenuItem, rowY: CGFloat,
                      primary: NSColor, secondary: NSColor) {
        let color = item.isEnabled ? primary : primary.withAlphaComponent(0.35)
        let iconRect = NSRect(x: Self.horizontalPadding,
                              y: rowY + (Self.rowHeight - PanelShortcutMenuLayout.iconSide) / 2,
                              width: PanelShortcutMenuLayout.iconSide,
                              height: PanelShortcutMenuLayout.iconSide)
        if let image = PanelShortcutMenuBuilder.icon(item.symbol)?.tinted(color) {
            image.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
        let titleX = iconRect.maxX + Self.iconTitleGap
        let title = NSAttributedString(string: item.title,
                                       attributes: [.font: Self.titleFont, .foregroundColor: color])
        title.draw(at: NSPoint(x: titleX, y: rowY + (Self.rowHeight - title.size().height) / 2))
        if item.submenu != nil {
            let chevron = NSAttributedString(string: "\u{25b8}",
                                             attributes: [.font: Self.keyFont, .foregroundColor: secondary])
            chevron.draw(at: NSPoint(x: bounds.width - Self.horizontalPadding - chevron.size().width,
                                     y: rowY + (Self.rowHeight - chevron.size().height) / 2))
        }
        guard !item.keyEquivalent.isEmpty else { return }
        let key = NSAttributedString(string: item.keyEquivalentDisplay,
                                     attributes: [.font: Self.keyFont, .foregroundColor: secondary])
        key.draw(at: NSPoint(x: bounds.width - Self.horizontalPadding - key.size().width,
                             y: rowY + (Self.rowHeight - key.size().height) / 2))
    }

    // MARK: - 输出

    static func render(groups: [PanelShortcutMenuGroup],
                       appearance: NSAppearance.Name) -> NSBitmapImageRep? {
        let view = PanelShortcutMenuSurfaceView(rows: rows(groups: groups))
        view.appearance = NSAppearance(named: appearance)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    // 二次确认弹窗在这里不截图：`NSAlert` 的按钮排布、图标和隐藏占位只有在
    // 真的 `runModal` 之后才会定稿，离屏截到的是一张带空按钮 / “Do not show
    // this message” 占位的骨架图，放出去只会误导。确认弹窗的证据是 harness 里
    // 的结构断言 + 注入响应断言（按钮顺序、Esc/Return、destructive、取消不退出）。
}
