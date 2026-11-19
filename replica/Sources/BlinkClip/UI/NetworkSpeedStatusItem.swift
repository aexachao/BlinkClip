import AppKit
import BlinkClipCore
import Foundation

/// 菜单栏网速文字的渲染。
///
/// 选型：保留现有 18×18 模板图标，文字用 `button.attributedTitle` 画在同一颗
/// `NSStatusBarButton` 里（`imagePosition = .imageLeading`）。没有改成「把文字画进
/// NSImage」的自绘方案，因为实测 attributedTitle 与图标基线并排正常、文字能跟随
/// 系统深浅色（`labelColor` 是动态语义色），并且原生方案仍然保留图标/文字各自的
/// 无障碍与点击命中。实机与离屏渲染的宽度、图标位置见测试报告。
enum NetworkSpeedStatusItem {
    /// 9.5pt 等宽数字：菜单栏里比正文小一档，同时保证 `↓1.4M ↑32.4K` 的宽度稳定。
    static let titleFont = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)

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

    /// tooltip 的两段完整速度（B/s 或 bps 换算），文案走设置页同一张三语表。
    static func toolTip(rates: NetworkSpeedRates?, unit: NetworkSpeedUnit) -> String {
        let download = rates.map { NetworkSpeedFormatter.fullString(bytesPerSecond: $0.downloadBytesPerSecond, unit: unit) } ?? "—"
        let upload = rates.map { NetworkSpeedFormatter.fullString(bytesPerSecond: $0.uploadBytesPerSecond, unit: unit) } ?? "—"
        return String(format: SettingsCopy.text("settings.toolbox.network-speed.tooltip"), download, upload)
    }

    /// 把开关、读数与单位落到状态栏按钮上。
    ///
    /// - 关闭：清空标题并把宽度收回 `squareLength`，图标回到原来的位置与点击行为；
    /// - 打开：`variableLength` 让状态栏按「图标 + 文字」自适应宽度；
    ///   `imageHugsTitle` 保证文字紧贴图标，宽度增长时图标不会被挤掉。
    static func apply(to statusItem: NSStatusItem, enabled: Bool,
                      rates: NetworkSpeedRates?, unit: NetworkSpeedUnit) {
        guard let button = statusItem.button else { return }
        if enabled {
            statusItem.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.attributedTitle = attributedTitle(rates: rates, unit: unit)
        } else {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            statusItem.length = NSStatusItem.squareLength
        }
    }

    /// 离屏回归用：套用生产渲染后读回按钮的实测宽度与图标宽度。
    static func measuredWidths(enabled: Bool, rates: NetworkSpeedRates?, unit: NetworkSpeedUnit,
                               icon: NSImage) -> (button: CGFloat, icon: CGFloat) {
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        button.image = icon
        button.imageScaling = .scaleProportionallyDown
        if enabled {
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true
            button.attributedTitle = attributedTitle(rates: rates, unit: unit)
        } else {
            button.imagePosition = .imageOnly
        }
        button.sizeToFit()
        let iconWidth = button.cell?.imageRect(forBounds: button.bounds).width ?? 0
        return (button.fittingSize.width, iconWidth)
    }
}
