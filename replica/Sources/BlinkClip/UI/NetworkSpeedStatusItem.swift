import AppKit
import BlinkClipCore
import Foundation

/// 菜单栏网速文字的渲染，支持两种排版（`NetworkSpeedLayout`）。
///
/// - **单行（默认）**：`↓1.2M ↑7.0K`，文字用 `button.attributedTitle` 画在同一颗
///   `NSStatusBarButton` 里（`imagePosition = .imageLeading`）。`labelColor` 是动态
///   语义色，深浅菜单栏各自取到正确对比度，选中态由 AppKit 自己反白。
/// - **上下两行**：第一行 `↓1.2M`、第二行 `↑7.0K`。`NSButton` 的标题只能单行，
///   所以这一种把「左侧 18pt 模板图标 + 右侧两行文字」画进**同一张** `NSImage`，
///   交给 `button.image`（`imagePosition = .imageOnly`）：
///   1. 图片整体 `isTemplate = true`。模板图由 AppKit 按菜单栏外观着色——浅色是黑、
///      深色是白，按下/高亮时再按高亮底色重新着色（深底为白字）。所以两行模式不需要
///      自己监听 `effectiveAppearance` 或高亮状态，也不会出现「深色菜单栏上深色字」。
///   2. 文字与图标同一条绘制路径（图标画进同一张图），两行文字之间**零额外行距**，
///      行高 = 9pt 字体的实际行高（约 11pt），整图高 22pt，正好落在菜单栏可用高度内。
///   3. 宽度按内容自适应：`18（图标）+ 2（间距）+ 两行文字宽度的较大值`，
///      约 46–60pt（单行拟合宽度约 104pt），比单行窄。
///   4. 图片的 `accessibilityDescription` 写单行文字（`↓1.2M ↑7.0K`），
///      image-only 按钮的 VoiceOver 语义与单行模式一致。
enum NetworkSpeedStatusItem {
    /// 9.5pt 等宽数字：菜单栏里比正文小一档，同时保证 `↓1.4M ↑32.4K` 的宽度稳定。
    static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

    /// 两行排版的原生图标：与单行模式的 `button.image` 是同一张 18×18 模板图。
    static let baseIcon = ReplicaBrand.menuBarImage()

    static func attributedTitle(rates: NetworkSpeedRates?, unit: NetworkSpeedUnit) -> NSAttributedString {
        let text = NetworkSpeedFormatter.menuBarTitle(
            downloadBytesPerSecond: rates?.downloadBytesPerSecond,
            uploadBytesPerSecond: rates?.uploadBytesPerSecond,
            unit: unit)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byClipping
        return NSAttributedString(string: text, attributes: [
            .font: titleFont,
            // 动态语义色：状态栏按钮在深/浅色菜单栏下各自取到正确的文字颜色。
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
    }

    /// 两行排版的几何：9pt 等宽数字，两行之间不留额外间距。
    enum TwoLines {
        /// 9pt 等宽数字：两行加起来仍压在菜单栏可用高度（22pt）内。
        static let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        /// 行高取字体实际行高（9pt ≈ 10.6 → 向上取整 11），两行即 22pt。
        static let lineHeight: CGFloat = ceil(font.ascender - font.descender + font.leading)
        static let iconWidth: CGFloat = 18
        /// 图标与文字的间距：单行模式靠 `imageHugsTitle` 贴紧，两行模式手动画 2pt。
        static let iconGap: CGFloat = 2
        /// 菜单栏可用高度上限；超出会被状态栏裁掉。
        static let maxHeight: CGFloat = 22
        /// 整图高度：两行行高，且不超过菜单栏可用高度。
        static let height: CGFloat = min(maxHeight, lineHeight * 2)
        /// 默认单行数字下的宽度带（测试断言用，不是绘制常量）。
        static let expectedWidth: ClosedRange<CGFloat> = 40...64
    }

    /// 两行排版的两段文字：`↓1.4M` / `↑32.4K`。
    ///
    /// 直接从单行紧凑文字里切：紧凑格式两段之间只有一个空格（数字里没有空格），
    /// 这样两行与单行永远共用同一份格式化逻辑，不会出现「单行改了、两行没跟上」。
    static func menuBarLines(rates: NetworkSpeedRates?,
                             unit: NetworkSpeedUnit) -> (download: String, upload: String) {
        let title = NetworkSpeedFormatter.menuBarTitle(
            downloadBytesPerSecond: rates?.downloadBytesPerSecond,
            uploadBytesPerSecond: rates?.uploadBytesPerSecond,
            unit: unit)
        let parts = title.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return (title, "") }
        return (String(parts[0]), String(parts[1]))
    }

    /// 两行排版的一张图：左侧 18pt 模板图标，右侧两行 9pt 等宽数字。
    ///
    /// 绘制在 flipped 坐标系里（`y = 0` 是顶边）：第一行占 `0…lineHeight`，
    /// 第二行紧接其后，两行之间没有空白带。整图 `isTemplate = true`。
    static func twoLinesImage(icon: NSImage, rates: NetworkSpeedRates?,
                              unit: NetworkSpeedUnit) -> NSImage {
        let lines = menuBarLines(rates: rates, unit: unit)
        let attributes: [NSAttributedString.Key: Any] = [.font: TwoLines.font,
                                                         .foregroundColor: NSColor.black]
        let downloadWidth = (lines.download as NSString).size(withAttributes: attributes).width
        let uploadWidth = (lines.upload as NSString).size(withAttributes: attributes).width
        let textWidth = ceil(max(downloadWidth, uploadWidth))
        let size = NSSize(width: TwoLines.iconWidth + TwoLines.iconGap + textWidth,
                          height: TwoLines.height)
        let image = NSImage(size: size, flipped: true) { _ in
            // 图标：18×18 模板图，垂直居中贴左边。
            icon.draw(in: NSRect(x: 0, y: (size.height - TwoLines.iconWidth) / 2,
                                 width: TwoLines.iconWidth, height: TwoLines.iconWidth),
                      from: .zero, operation: .sourceOver, fraction: 1)
            // 两行文字：左上对齐，第二行紧接第一行，没有额外行距。
            let textX = TwoLines.iconWidth + TwoLines.iconGap
            for (index, line) in [lines.download, lines.upload].enumerated() {
                let rect = NSRect(x: textX, y: CGFloat(index) * TwoLines.lineHeight,
                                  width: textWidth, height: TwoLines.lineHeight)
                (line as NSString).draw(in: rect, withAttributes: attributes)
            }
            return true
        }
        // 模板图：浅色菜单栏黑、深色白、高亮由 AppKit 重新着色。
        image.isTemplate = true
        image.accessibilityDescription = NetworkSpeedFormatter.menuBarTitle(
            downloadBytesPerSecond: rates?.downloadBytesPerSecond,
            uploadBytesPerSecond: rates?.uploadBytesPerSecond, unit: unit)
        return image
    }

    /// tooltip 的两段完整速度（B/s 或 bps 换算），文案走设置页同一张三语表。
    static func toolTip(rates: NetworkSpeedRates?, unit: NetworkSpeedUnit) -> String {
        let download = rates.map { NetworkSpeedFormatter.fullString(bytesPerSecond: $0.downloadBytesPerSecond, unit: unit) } ?? "—"
        let upload = rates.map { NetworkSpeedFormatter.fullString(bytesPerSecond: $0.uploadBytesPerSecond, unit: unit) } ?? "—"
        return String(format: SettingsCopy.text("settings.toolbox.network-speed.tooltip"), download, upload)
    }

    /// 把开关、读数、单位与排版落到一颗状态栏按钮上。单行与两行共用这一个入口，
    /// 所以切换排版（同一颗按钮）下一帧就生效，不需要重建 `NSStatusItem`。
    ///
    /// - 关闭：清空标题、图片恢复成纯图标，宽度由 `apply` 收回 `squareLength`；
    /// - 单行：图标 + `attributedTitle`（`imageLeading`、`imageHugsTitle`）；
    /// - 两行：图标与两行文字合成一张模板图，`imageOnly`。
    static func configure(_ button: NSStatusBarButton, enabled: Bool,
                          rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                          layout: NetworkSpeedLayout, icon: NSImage) {
        guard enabled else {
            button.attributedTitle = NSAttributedString(string: "")
            button.image = icon
            button.imagePosition = .imageOnly
            button.imageHugsTitle = false
            return
        }
        switch layout {
        case .singleLine:
            button.image = icon
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.attributedTitle = attributedTitle(rates: rates, unit: unit)
        case .twoLines:
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            button.imageHugsTitle = false
            button.image = twoLinesImage(icon: icon, rates: rates, unit: unit)
        }
    }

    /// 把开关、读数、单位与排版落到状态项上。
    ///
    /// - 关闭：清空标题并把宽度收回 `squareLength`，图标回到原来的位置与点击行为；
    /// - 打开：`variableLength` 让状态栏按「图标 + 文字」自适应宽度；
    ///   `imageHugsTitle` 保证单行文字紧贴图标，宽度增长时图标不会被挤掉。
    static func apply(to statusItem: NSStatusItem, enabled: Bool,
                      rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                      layout: NetworkSpeedLayout, icon: NSImage = baseIcon) {
        guard let button = statusItem.button else { return }
        configure(button, enabled: enabled, rates: rates, unit: unit, layout: layout, icon: icon)
        statusItem.length = enabled ? NSStatusItem.variableLength : NSStatusItem.squareLength
    }

    /// 离屏回归用：套用生产渲染后读回按钮的实测宽度与图片区宽度。
    static func measuredWidths(enabled: Bool, rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                               layout: NetworkSpeedLayout,
                               icon: NSImage) -> (button: CGFloat, image: CGFloat) {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        button.imageScaling = .scaleProportionallyDown
        configure(button, enabled: enabled, rates: rates, unit: unit, layout: layout, icon: icon)
        button.sizeToFit()
        let imageWidth = button.cell?.imageRect(forBounds: button.bounds).width ?? 0
        return (button.fittingSize.width, imageWidth)
    }
}
