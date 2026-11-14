import AppKit
import SwiftUI

/// 设置页卡片的浅/深色层与说明文字语义。
///
/// 浅色下面板底是 `windowBackgroundColor`（实测 236），卡片必须比它更亮才符合
/// 系统设置的方向。旧实现用 `Color.primary.opacity(0.035)`，浅色下等于「在页面上
/// 压 3.5% 黑」，卡片落到 229、比页面更暗；11pt 说明文字用系统 `secondaryLabelColor`
/// 在这块底色上只有 3.76:1。
///
/// 这里只定义一套层：卡片比页面亮（浅色纯白 +19 级、深色 +12 级），再用 1pt 内描边
/// 维持边界；说明文字固定 58% 前/背景色，两种外观对卡片的对比度是 5.32:1 / 4.80:1
/// （WCAG 相对亮度）。数值在 `Tests/Native/SettingsArchitectureHarness.swift` 里断言。
enum SettingsSurfaceStyle {
    static let cornerRadius: CGFloat = 12
    static let borderWidth: CGFloat = 1
    static let contentPadding: CGFloat = 10

    /// 说明文字在卡片底色上的不透明度：系统 `secondaryLabelColor` 是 50% / 55%，
    /// 浅色 3.95:1、深色 4.48:1，都不到 11pt 文字要求的 4.5:1。
    static let secondaryTextOpacity: CGFloat = 0.58

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// 浅色：纯白卡片（页面 236 → 卡片 255）；深色：页面 50 → 卡片 62。
    static func cardBackground(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.06) : NSColor.white
    }

    /// 1pt 内描边：浅色在卡片内缘压 8% 黑，深色提 10% 白；只为边界，不参与层级。
    static func cardBorder(dark: Bool) -> NSColor {
        dark ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.08)
    }

    /// 说明文字：浅色 58% 黑（255 → 107，5.32:1）、深色 58% 白（62 → 174，4.80:1）。
    static func secondaryText(dark: Bool) -> NSColor {
        (dark ? NSColor.white : NSColor.black).withAlphaComponent(secondaryTextOpacity)
    }

    /// SwiftUI 侧跟随 `ColorScheme` 取色，避免把外观钉死在创建时刻。
    static func cardBackgroundColor(dark: Bool) -> Color { Color(nsColor: cardBackground(dark: dark)) }
    static func cardBorderColor(dark: Bool) -> Color { Color(nsColor: cardBorder(dark: dark)) }
    static func secondaryTextColor(dark: Bool) -> Color { Color(nsColor: secondaryText(dark: dark)) }

    /// AppKit 侧（历史保留期说明等）：交给 AppKit 在绘制时按有效外观解析。
    static let cardBackgroundDynamic = NSColor(name: nil) { cardBackground(dark: isDark($0)) }
    static let cardBorderDynamic = NSColor(name: nil) { cardBorder(dark: isDark($0)) }
    static let secondaryTextDynamic = NSColor(name: nil) { secondaryText(dark: isDark($0)) }

    /// WCAG 2.x 相对亮度与对比度：测试直接对上面两组颜色做断言，不看截图。
    static func relativeLuminance(_ color: NSColor) -> CGFloat {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
    }

    /// 把带透明度的前景合成到不透明背景上（卡片在深色里是半透明白）。
    static func composite(_ foreground: NSColor, over background: NSColor) -> NSColor {
        let top = foreground.usingColorSpace(.sRGB) ?? foreground
        let bottom = background.usingColorSpace(.sRGB) ?? background
        let alpha = top.alphaComponent
        return NSColor(srgbRed: top.redComponent * alpha + bottom.redComponent * (1 - alpha),
                       green: top.greenComponent * alpha + bottom.greenComponent * (1 - alpha),
                       blue: top.blueComponent * alpha + bottom.blueComponent * (1 - alpha),
                       alpha: 1)
    }

    static func contrastRatio(_ foreground: NSColor, over background: NSColor) -> CGFloat {
        let top = relativeLuminance(composite(foreground, over: background))
        let bottom = relativeLuminance(background)
        return (max(top, bottom) + 0.05) / (min(top, bottom) + 0.05)
    }
}

/// 卡片里的说明文字。设置页里所有 11pt/12pt 副标题共用这一个样式，
/// 系统 `.secondary` 在浅色卡片上不达标（见 `SettingsSurfaceStyle`）。
private struct SettingsSecondaryTextStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.foregroundStyle(SettingsSurfaceStyle.secondaryTextColor(dark: colorScheme == .dark))
    }
}

extension View {
    func settingsSecondaryText() -> some View { modifier(SettingsSecondaryTextStyle()) }
}
