import AppKit
import BlinkClipCore
import Foundation
import os

/// 菜单栏网速的渲染：**唯一一种呈现**——上下两行，第一行上传 `↑`、第二行下载 `↓`，
/// 容器固定宽度、两行左对齐。
///
/// 为什么整条状态项只有这一种画法：
///
/// - **两行**：`NSButton` 的标题只能单行，所以把「左侧 18pt 模板图标 + 右侧两行文字」
///   画进**同一张** `NSImage`，交给 `button.image`（`imagePosition = .imageOnly`）。
/// - **模板图**：整图 `isTemplate = true`。AppKit 按菜单栏外观着色——浅色黑、深色白，
///   按下/高亮时按高亮底色重新着色。所以不需要监听 `effectiveAppearance` 或高亮状态，
///   也不会出现「深色菜单栏上深色字」。
/// - **零额外行距**：两行文字上下紧接，行高 = 9pt 字体的实际行高（≈11pt），整图高
///   22pt，正好落在菜单栏可用高度内。
/// - **固定宽度**：状态项长度与图宽都写死（`FixedWidth`），读数变化时整条菜单栏不重排。
///   图内文字区宽度按**实测最宽的正常读数**取值（见 `FixedWidth` 的实测注释）。
/// - **左对齐、不补位**：两行都从同一个 `x` 起画，文字用「数字原本的宽度」。不再用
///   `U+2007 FIGURE SPACE` 从左侧补位、也不再给小数点补 `.kern`——所以数字右侧会随
///   位数变化，但两行的左边缘（箭头）始终对齐。
/// - **超宽不裁剪、不降级成 `>999`**：数值是真实的，容器宽度不动；真放不下时只记一次
///   日志（`NetworkSpeedStatusItem.overflowLogs`），绘制照旧、内容会被容器裁掉一点。
///   正常读数不会走到这里：最宽的两种串（正常读数 `99.9M`、降级串 `>999G`）都比文字区窄。
/// - **关闭开关**：清空标题、图片恢复纯图标，长度回 `squareLength`（24pt），
///   定时器由 `NetworkSpeedMonitor.stop()` 停掉（0 采样）。
enum NetworkSpeedStatusItem {
    private static let logger = Logger(subsystem: "com.chrisli.blinkclip", category: "network-speed")

    /// 同一次运行里只记一条超宽日志：读数每秒刷新，不刷屏。
    private(set) static var overflowLogs = 0

    /// 两行几何：9pt 等宽数字，两行之间不留额外间距。
    enum TwoLines {
        /// 9pt 等宽数字：两行加起来仍压在菜单栏可用高度（22pt）内。
        static let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        /// 行高取字体实际行高（9pt ≈ 10.6 → 向上取整 11），两行即 22pt。
        static let lineHeight: CGFloat = ceil(font.ascender - font.descender + font.leading)
        /// 左侧原生产品图标：与关闭态 `button.image` 是同一张 18×18 模板图。
        static let iconWidth: CGFloat = 18
        /// 图标与文字的间距（6pt：18pt 图标右边缘到文字左边缘）。
        static let iconGap: CGFloat = 6
        /// 菜单栏可用高度上限；超出会被状态栏裁掉。
        static let maxHeight: CGFloat = 22
        /// 整图高度：两行行高，且不超过菜单栏可用高度。
        static let height: CGFloat = min(maxHeight, lineHeight * 2)
        /// 文字起画位置（两行共用同一个 x，这就是「左对齐」）。
        static var textX: CGFloat { iconWidth + iconGap }
    }

    /// 固定宽度：容器固定、文字左对齐、无补位无字距，数字该多宽就多宽。
    ///
    /// 自适应小数（B 档 0 位、KB/MB/GB < 100 一位、≥ 100 无位）之后，读数最多 5 个字符
    /// （`99.9M`）。实测（`TwoLines.font` = `monospacedDigitSystemFont(ofSize: 9, weight: .regular)`）：
    ///
    /// | 串 | 宽 |
    /// |---|---|
    /// | `↑>999G`（降级串；现在是**最宽**的一种，`>999` 比三位数字宽） | **37.43pt** |
    /// | `↑99.9M`（最宽正常串：< 100 一位小数 + 最宽后缀 `M`，bps 下是 `↑11.2M`） | **35.58pt** |
    /// | `↑99.9G` | 34.43pt |
    /// | `↑32.4K`（< 100 一位小数） | 33.64pt |
    /// | `↑999M`（≥ 100 无小数） | 32.74pt |
    /// | `↑999B`（B 档无小数；`↑512B` 同宽） | 30.79pt |
    /// | `↑4B` | 19.12pt |
    /// | `↑—`（首拍占位） | 15.23pt |
    ///
    /// 文字区取 **38pt** = max(最宽正常串 35.58 + 2.42pt 安全余量（6.8%），
    /// 降级串 37.43 + 0.57pt)。图宽因此是 18（图标）+ 6（间距）+ 38 = **62pt**；
    /// 真实菜单栏里状态项左右各留 3pt，所以状态项长度 = 62 + 6 = **68pt**。
    /// 关闭开关时回 `squareLength`（24pt）。
    enum FixedWidth {
        /// 最宽的正常读数（`99.9` + 最宽后缀 `M`）；断言与注释共用这一条事实。
        static let widestLine = "↑99.9M"
        static let widestLineWidth: CGFloat = 35.58
        /// 降级串（末档 GB 无处可进）；带 `>999`，比最宽正常串还宽 1.85pt。
        static let degradedLine = "↑>999G"
        static let degradedLineWidth: CGFloat = 37.43
        /// 两行文字区的固定宽度（pt）：左对齐画进这个盒子，超出的部分由容器裁掉。
        static let textWidth: CGFloat = 38
        /// 两行图的固定宽度（pt）= 18pt 图标 + 6pt 间距 + 38pt 文字区。
        static var imageWidth: CGFloat { TwoLines.iconWidth + TwoLines.iconGap + textWidth }
        /// 真实菜单栏里 `NSStatusBarButton` 给图片左右各 3pt 内边距（沿用改动前的 62 + 6）。
        static let buttonPadding: CGFloat = 6
        /// 状态项固定长度（pt）= 图宽 + 六边距。
        static var length: CGFloat { imageWidth + buttonPadding }
    }

    /// 两行文字：第一行**上传** `↑…`，第二行**下载** `↓…`。
    ///
    /// 唯一来源是核心格式化器的紧凑写法（`↓下载 ↑上传`，两段之间只有一个空格），
    /// 这里只做「按唯一空格切开 + 上下对调」，所以两行与 tooltip / 设置预览的
    /// 数字口径永远一致。
    static func lines(rates: NetworkSpeedRates?,
                      unit: NetworkSpeedUnit) -> (upload: String, download: String) {
        let title = NetworkSpeedFormatter.menuBarTitle(
            downloadBytesPerSecond: rates?.downloadBytesPerSecond,
            uploadBytesPerSecond: rates?.uploadBytesPerSecond,
            unit: unit)
        let parts = title.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return (upload: title, download: title) }
        return (upload: String(parts[1]), download: String(parts[0]))
    }

    /// 两行图的文字属性：只有字体与颜色，没有 `.kern`、没有 `U+2007` 补位。
    static func rowAttributes(color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: TwoLines.font, .foregroundColor: color]
    }

    /// 两行图：第一行上传、第二行下载，固定 62×22pt，两行从同一个 `x` 左对齐。
    static func twoLinesImage(icon: NSImage, rates: NetworkSpeedRates?,
                              unit: NetworkSpeedUnit) -> NSImage {
        let lines = lines(rates: rates, unit: unit)
        let rows = [lines.upload, lines.download]
        let attributes = rowAttributes(color: .black)
        logOverflowIfNeeded(rows: rows, attributes: attributes)
        let size = NSSize(width: FixedWidth.imageWidth, height: TwoLines.height)
        let image = NSImage(size: size, flipped: true) { _ in
            // 图标：18×18 模板图，垂直居中贴左边。
            //
            // 本图自身是 flipped（y 向下）的，图标也是 flipped 图；`draw(in:)` 的默认路径会在
            // flipped 上下文里把图标上下颠倒（真机菜单栏实测：横条跑到卡片下半、右下切角跑到
            // 右上）。必须走 `respectFlipped: true`，让图标按目标上下文的朝向绘制、保持正向。
            icon.draw(in: NSRect(x: 0, y: (size.height - TwoLines.iconWidth) / 2,
                                 width: TwoLines.iconWidth, height: TwoLines.iconWidth),
                      from: .zero, operation: .sourceOver, fraction: 1,
                      respectFlipped: true, hints: nil)
            // 两行文字：同一个 x 起画 → 左边缘对齐；第二行紧接第一行，没有额外行距。
            for (index, row) in rows.enumerated() {
                let rect = NSRect(x: TwoLines.textX, y: CGFloat(index) * TwoLines.lineHeight,
                                  width: FixedWidth.textWidth, height: TwoLines.lineHeight)
                NSAttributedString(string: row, attributes: attributes).draw(in: rect)
            }
            return true
        }
        // 模板图：浅色菜单栏黑、深色白、高亮由 AppKit 重新着色。
        image.isTemplate = true
        // 无障碍描述走 tooltip 的同一份**完整写法**（`下载 812 KB/s · 上传 32.4 KB/s`，
        // 下载在前）：VoiceOver 读到的是带 `/s`、带小数的完整读数，与鼠标悬停一致。
        image.accessibilityDescription = toolTip(rates: rates, unit: unit)
        return image
    }

    /// 超宽只记一次日志：不裁剪内容、不改容器宽度（数值是真实的）。
    private static func logOverflowIfNeeded(rows: [String], attributes: [NSAttributedString.Key: Any]) {
        let widest = rows.map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
        guard widest > FixedWidth.textWidth, overflowLogs == 0 else { return }
        overflowLogs += 1
        logger.notice("""
            network speed row \(widest, format: .fixed(precision: 2))pt exceeds the \
            \(FixedWidth.textWidth, format: .fixed(precision: 2))pt text box; \
            keeping the real value and the fixed \(FixedWidth.length, format: .fixed(precision: 2))pt width
            """)
    }

    /// tooltip 的两段完整速度（B/s 或 bps 换算），文案走设置页同一张三语表。
    static func toolTip(rates: NetworkSpeedRates?, unit: NetworkSpeedUnit) -> String {
        let download = rates.map { NetworkSpeedFormatter.fullString(bytesPerSecond: $0.downloadBytesPerSecond, unit: unit) } ?? "—"
        let upload = rates.map { NetworkSpeedFormatter.fullString(bytesPerSecond: $0.uploadBytesPerSecond, unit: unit) } ?? "—"
        return String(format: SettingsCopy.text("settings.toolbox.network-speed.tooltip"), download, upload)
    }

    /// 状态项长度：关闭回 `squareLength`；打开时是固定长度（读数变化不重排）。
    ///
    /// 单值纯函数，回归里不需要真实菜单栏也能逐帧断言「宽度没有变化」。
    static func length(enabled: Bool) -> CGFloat {
        enabled ? FixedWidth.length : NSStatusItem.squareLength
    }

    /// 把开关、读数与单位落到一颗状态栏按钮上。
    ///
    /// - 关闭：清空标题、图片恢复成纯图标，宽度由 `apply` 收回 `squareLength`；
    /// - 打开：图标与两行文字合成一张模板图，`imageOnly`。
    static func configure(_ button: NSStatusBarButton, enabled: Bool,
                          rates: NetworkSpeedRates?, unit: NetworkSpeedUnit, icon: NSImage) {
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageOnly
        button.imageHugsTitle = false
        button.image = enabled ? twoLinesImage(icon: icon, rates: rates, unit: unit) : icon
    }

    /// 把开关、读数与单位落到状态项上。
    ///
    /// - 关闭：宽度收回 `squareLength`（24pt），图标回到原来的位置与点击行为；
    /// - 打开：固定 68pt，读数变化不重排。
    static func apply(to statusItem: NSStatusItem, enabled: Bool,
                      rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                      icon: NSImage = ReplicaBrand.menuBarImage()) {
        guard let button = statusItem.button else { return }
        configure(button, enabled: enabled, rates: rates, unit: unit, icon: icon)
        statusItem.length = length(enabled: enabled)
    }

    /// 离屏回归用：套用生产渲染后读回按钮的实测宽度与图片区宽度。
    static func measuredWidths(enabled: Bool, rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                               icon: NSImage) -> (button: CGFloat, image: CGFloat) {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        button.imageScaling = .scaleProportionallyDown
        configure(button, enabled: enabled, rates: rates, unit: unit, icon: icon)
        button.sizeToFit()
        let imageWidth = button.cell?.imageRect(forBounds: button.bounds).width ?? 0
        return (button.fittingSize.width, imageWidth)
    }
}
