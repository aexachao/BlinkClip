import AppKit
import BlinkClipCore
import Foundation

/// 菜单栏网速文字的渲染，支持两种排版（`NetworkSpeedLayout`）× 两种宽度策略
/// （`NetworkSpeedWidth`），四种组合共用同一条采样与格式化链路。
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
///
/// 宽度策略（`NetworkSpeedWidth`）只改「状态项多宽、数字怎么落格」，不改采样与格式：
///
/// - **固定（默认）**：状态项长度写死（单行 `FixedWidth.singleLineLength`、
///   两行 `FixedWidth.twoLinesLength`），数字在自己的 4 位等宽格里**右对齐**，
///   短的数字用 `U+2007 FIGURE SPACE` 从左侧补位。读数从 `1.2M` 变到 `32.4M`
///   时字符位不变，所以整条菜单栏不会被推着重排。
/// - **随内容**：`NSStatusItem.variableLength`，文字不补位，宽度随读数变化（旧行为）。
enum NetworkSpeedStatusItem {
    /// 9.5pt 等宽数字：菜单栏里比正文小一档，同时保证 `↓1.4M ↑32.4K` 的宽度稳定。
    static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

    /// 两行排版的原生图标：与单行模式的 `button.image` 是同一张 18×18 模板图。
    static let baseIcon = ReplicaBrand.menuBarImage()

    /// 固定宽度的几何与字符预算。
    ///
    /// 一段（下载或上传）= **箭头 1 + 数字 4 + 后缀 1 = 6 个字符位**，单行两段加一个
    /// 分隔空格共 13 位。数字位按最宽的紧凑写法取 4 位（`32.4`、`99.9`、`812`、`999`）；
    /// 后缀位只留 1 位，`B/s`、`bps` 在固定宽度下压成 `B`、`b`（菜单栏紧凑写法，
    /// 单位本身仍由设置页的 `B/s | bps` 决定），否则最宽串会多出 2 个字符位。
    /// 实测（`titleFont` 9.5pt，`monospacedDigitSystemFont`）：数字位 4×6.13pt、
    /// 箭头 7.57pt、最宽后缀 `M` 8.45pt → 一段 40.53pt，`↓ 999M ↑ 812M` 共 83.87pt。
    enum FixedWidth {
        /// 数字位：`1.2` / `32.4` / `999` 都能落进去。
        static let numberSlots = 4
        /// 后缀位：`K` / `M` / `G` / `T` / `B` / `b`。
        static let suffixSlots = 1
        /// 一段的字符位数：箭头 1 + 数字位 + 后缀位 = 6。
        static var segmentSlots: Int { 1 + numberSlots + suffixSlots }
        /// 补位字符 `U+2007 FIGURE SPACE`：在等宽数字字体里正好一个数字宽，
        /// 所以「数字在 4 位格里右对齐」只需要补字符，不需要另算绘制坐标。
        static let pad = "\u{2007}"
        /// 降级数字：数字位写满 4 位，`>999` 表示「这一档已经超出可显示范围」。
        static let overflowNumber = ">999"
        /// 数字位里小数点比数字窄（实测 9.5pt 下 `0` 6.128pt、`.` 2.964pt），
        /// 只按字符位补 4 格时 `99.9` 会比 `812` 窄 3.16pt，数字列还是会抖 3pt。
        /// 所以给数字串里的每个 `.` 补一份字距（kern），让小数点也占满一格——
        /// 这样任意写法（`1.2` / `32.4` / `999` / `>999`）的数字格都是 4×数字宽。
        static func digitKerning(font: NSFont) -> CGFloat {
            let digit = ("0" as NSString).size(withAttributes: [.font: font]).width
            let dot = ("." as NSString).size(withAttributes: [.font: font]).width
            return max(0, digit - dot)
        }
        /// 单行状态项长度（pt）。
        ///
        /// 真实菜单栏里文字区两侧各 9pt、图标 18pt、图标与文字间距 2pt，共 38pt 固定开销；
        /// 最宽串 `↓ 999M ↑ 812M` 实测 83.87pt → 需要 121.9pt。取 124pt 留 2pt 余量，
        /// 保证任何读数（含 `B/s`、`bps`、`—`）都不会被裁。题目给的 110pt 只够
        /// 「典型」串（`↓ 1.4M ↑ 32.4K` = 75.49pt → 113.5pt），高速读数会被截断。
        static let singleLineLength: CGFloat = 124
        /// 上下两行状态项长度（pt）：两行图固定宽度 + 左右各 3pt 内边距。
        static let twoLinesLength: CGFloat = 72
        /// 两行图的固定宽度（= 两行状态项长度 − 6）。与单行不同，两行图自己带着
        /// 18pt 图标，图内的文字格被画死，读数变化时图宽不变。
        static let twoLinesImageWidth: CGFloat = 66
        /// 两行图里文字的固定格宽（= 图宽 − 18pt 图标 − 2pt 间距）。
        static let twoLinesTextWidth: CGFloat = 46
        /// 单行标题的字符位数：两段 + 一个分隔空格。
        static var singleLineSlots: Int { segmentSlots * 2 + 1 }
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
        /// 「随内容」策略下单行数字的宽度带（测试断言用，不是绘制常量）。
        static let expectedWidth: ClosedRange<CGFloat> = 40...64
    }

    /// 一段菜单栏文字的成分：`↓1.4M` → 箭头 `↓`、数字 `1.4`、后缀 `M`。
    ///
    /// 固定宽度需要把数字单独放进 4 位格、后缀单独放进 1 位格，所以先拆开；
    /// 「随内容」策略仍直接用拼好的整段（不拆、不补位）。
    struct Segment: Equatable {
        var arrow: String
        var number: String
        var suffix: String
    }

    /// 把 `↓1.4M` / `↑0B/s` / `↓—` 拆成箭头、数字与后缀。
    ///
    /// 数字只认 `0-9` 和 `.`；一个数字都没有（例如占位 `—`）时整段都算数字位，
    /// 这样占位也会落在数字列的右边，不会跑到后缀列去。
    static func segment(from part: String) -> Segment {
        var rest = Substring(part)
        var arrow = ""
        if let first = rest.first, first == "↓" || first == "↑" {
            arrow = String(first)
            rest = rest.dropFirst()
        }
        var number = ""
        while let character = rest.first, character.isNumber || character == "." {
            number.append(character)
            rest = rest.dropFirst()
        }
        if number.isEmpty {
            return Segment(arrow: arrow, number: String(rest), suffix: "")
        }
        return Segment(arrow: arrow, number: number, suffix: String(rest))
    }

    /// 超预算降级：数字字符位超过 `FixedWidth.numberSlots` 时换成 `>999`，
    /// 后缀照留（`>999T`）。紧凑格式化只输出三位有效数字，现实里只有最高一档
    /// （`T`）在同档数字 >= 10000 时才会撞到这条规则；其余档会先进位。
    static func budgetedNumber(_ number: String) -> String {
        number.count > FixedWidth.numberSlots ? FixedWidth.overflowNumber : number
    }

    /// 把一段落到固定字符位：数字左补 `U+2007` 到 4 位（右对齐），后缀取 1 位。
    static func fixedSegmentText(_ segment: Segment) -> String {
        let number = budgetedNumber(segment.number)
        let padding = String(repeating: FixedWidth.pad,
                             count: max(0, FixedWidth.numberSlots - number.count))
        return segment.arrow + padding + number
            + String(segment.suffix.prefix(FixedWidth.suffixSlots))
    }

    /// 把固定宽度的整段文字做成属性串：小数点补字距，让数字格正好 4 个数字宽。
    ///
    /// 纯字符串给测试与无障碍用（字符位是契约），这里只多一份 `.kern` 元数据。
    static func fixedAttributedText(_ text: String, font: NSFont,
                                    color: NSColor) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        let kerning = FixedWidth.digitKerning(font: font)
        if kerning > 0 {
            let characters = Array(text)
            for (index, character) in characters.enumerated() where character == "." {
                attributed.addAttribute(.kern, value: kerning,
                                        range: NSRange(location: index, length: 1))
            }
        }
        return attributed
    }

    /// 固定宽度下的单行标题：`↓␣1.4M ↑␣32.4K`（`␣` 是 figure space，不可见）。
    static func fixedTitle(rates: NetworkSpeedRates?, unit: NetworkSpeedUnit) -> String {
        let lines = fixedLines(rates: rates, unit: unit)
        return lines.download + " " + lines.upload
    }

    /// 固定宽度下的两段文字（两行排版的两行）。
    static func fixedLines(rates: NetworkSpeedRates?,
                           unit: NetworkSpeedUnit) -> (download: String, upload: String) {
        let lines = menuBarLines(rates: rates, unit: unit)
        return (fixedSegmentText(segment(from: lines.download)),
                fixedSegmentText(segment(from: lines.upload)))
    }

    static func attributedTitle(rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                                width: NetworkSpeedWidth) -> NSAttributedString {
        let text = width.isFixed
            ? fixedTitle(rates: rates, unit: unit)
            : NetworkSpeedFormatter.menuBarTitle(
                downloadBytesPerSecond: rates?.downloadBytesPerSecond,
                uploadBytesPerSecond: rates?.uploadBytesPerSecond,
                unit: unit)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineBreakMode = .byClipping
        // 动态语义色：状态栏按钮在深/浅色菜单栏下各自取到正确的文字颜色。
        let attributed = width.isFixed
            ? fixedAttributedText(text, font: titleFont, color: NSColor.labelColor)
            : NSAttributedString(string: text, attributes: [
                .font: titleFont,
                .foregroundColor: NSColor.labelColor,
            ])
        let result = NSMutableAttributedString(attributedString: attributed)
        result.addAttribute(.paragraphStyle, value: paragraph,
                            range: NSRange(location: 0, length: result.length))
        return result
    }

    /// 两行排版的两段文字：`↓1.4M` / `↑32.4K`（固定宽度时同样补位）。
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
    ///
    /// - `width == .fixed`：图宽写死 `FixedWidth.twoLinesImageWidth`，两行文字画进
    ///   固定的 `FixedWidth.twoLinesTextWidth` 格子里，从 `x = 20` 起左对齐。
    ///   箭头列、数字列（4 位格右对齐）、后缀列都固定，所以读数变化时两行不会错位。
    /// - `width == .content`：按内容自适应宽度（旧行为）。
    static func twoLinesImage(icon: NSImage, rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                              width: NetworkSpeedWidth) -> NSImage {
        let fixed = width.isFixed
        let text: (download: String, upload: String)
        if fixed {
            text = fixedLines(rates: rates, unit: unit)
        } else {
            text = menuBarLines(rates: rates, unit: unit)
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: TwoLines.font,
                                                         .foregroundColor: NSColor.black]
        let downloadWidth = (text.download as NSString).size(withAttributes: attributes).width
        let uploadWidth = (text.upload as NSString).size(withAttributes: attributes).width
        let lineText: (download: NSAttributedString, upload: NSAttributedString)
        if fixed {
            lineText = (fixedAttributedText(text.download, font: TwoLines.font, color: .black),
                        fixedAttributedText(text.upload, font: TwoLines.font, color: .black))
        } else {
            lineText = (NSAttributedString(string: text.download, attributes: attributes),
                        NSAttributedString(string: text.upload, attributes: attributes))
        }
        let imageWidth: CGFloat
        let textWidth: CGFloat
        if fixed {
            imageWidth = FixedWidth.twoLinesImageWidth
            textWidth = FixedWidth.twoLinesTextWidth
        } else {
            textWidth = ceil(max(downloadWidth, uploadWidth))
            imageWidth = TwoLines.iconWidth + TwoLines.iconGap + textWidth
        }
        let size = NSSize(width: imageWidth, height: TwoLines.height)
        let image = NSImage(size: size, flipped: true) { _ in
            // 图标：18×18 模板图，垂直居中贴左边。
            icon.draw(in: NSRect(x: 0, y: (size.height - TwoLines.iconWidth) / 2,
                                 width: TwoLines.iconWidth, height: TwoLines.iconWidth),
                      from: .zero, operation: .sourceOver, fraction: 1)
            // 两行文字：左上对齐，第二行紧接第一行，没有额外行距。
            let textX = TwoLines.iconWidth + TwoLines.iconGap
            for (index, line) in [lineText.download, lineText.upload].enumerated() {
                let rect = NSRect(x: textX, y: CGFloat(index) * TwoLines.lineHeight,
                                  width: textWidth, height: TwoLines.lineHeight)
                line.draw(in: rect)
            }
            return true
        }
        // 模板图：浅色菜单栏黑、深色白、高亮由 AppKit 重新着色。
        image.isTemplate = true
        // 无障碍描述始终用未补位的紧凑文字：VoiceOver 不该念出 figure space。
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

    /// 状态项长度：关闭回 `squareLength`；固定策略按排版写死；随内容用 `variableLength`。
    ///
    /// 单值纯函数，回归里不需要真实菜单栏也能逐帧断言「宽度没有变化」。
    static func length(enabled: Bool, layout: NetworkSpeedLayout,
                       width: NetworkSpeedWidth) -> CGFloat {
        guard enabled else { return NSStatusItem.squareLength }
        guard width.isFixed else { return NSStatusItem.variableLength }
        return layout == .singleLine ? FixedWidth.singleLineLength : FixedWidth.twoLinesLength
    }

    /// 把开关、读数、单位、排版与宽度策略落到一颗状态栏按钮上。四种组合共用这一个入口，
    /// 所以切换排版 / 宽度（同一颗按钮）下一帧就生效，不需要重建 `NSStatusItem`。
    ///
    /// - 关闭：清空标题、图片恢复成纯图标，宽度由 `apply` 收回 `squareLength`；
    /// - 单行：图标 + `attributedTitle`（`imageLeading`、`imageHugsTitle`）；
    /// - 两行：图标与两行文字合成一张模板图，`imageOnly`。
    static func configure(_ button: NSStatusBarButton, enabled: Bool,
                          rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                          layout: NetworkSpeedLayout, width: NetworkSpeedWidth, icon: NSImage) {
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
            button.attributedTitle = attributedTitle(rates: rates, unit: unit, width: width)
        case .twoLines:
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            button.imageHugsTitle = false
            button.image = twoLinesImage(icon: icon, rates: rates, unit: unit, width: width)
        }
    }

    /// 把开关、读数、单位、排版与宽度策略落到状态项上。
    ///
    /// - 关闭：清空标题并把宽度收回 `squareLength`，图标回到原来的位置与点击行为；
    /// - 固定：单行 124pt / 两行 72pt，读数变化不重排；
    /// - 随内容：`variableLength` 让状态栏按「图标 + 文字」自适应宽度。
    static func apply(to statusItem: NSStatusItem, enabled: Bool,
                      rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                      layout: NetworkSpeedLayout, width: NetworkSpeedWidth,
                      icon: NSImage = baseIcon) {
        guard let button = statusItem.button else { return }
        configure(button, enabled: enabled, rates: rates, unit: unit, layout: layout,
                  width: width, icon: icon)
        statusItem.length = length(enabled: enabled, layout: layout, width: width)
    }

    /// 离屏回归用：套用生产渲染后读回按钮的实测宽度与图片区宽度。
    static func measuredWidths(enabled: Bool, rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                               layout: NetworkSpeedLayout, width: NetworkSpeedWidth,
                               icon: NSImage) -> (button: CGFloat, image: CGFloat) {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        button.imageScaling = .scaleProportionallyDown
        configure(button, enabled: enabled, rates: rates, unit: unit, layout: layout,
                  width: width, icon: icon)
        button.sizeToFit()
        let imageWidth = button.cell?.imageRect(forBounds: button.bounds).width ?? 0
        return (button.fittingSize.width, imageWidth)
    }
}
