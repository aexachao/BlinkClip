import AppKit
import BlinkClipCore

/// 卡片脚注（文本卡「N 个字符」、链接卡 URL）的次要前景色。
///
/// 之所以单独一个 token，而不是复用 `ToolbarAppearance.secondaryForeground()`：
/// 后者（浅色 50% 黑 / 深色 55% 白）同时服务工具栏图标、描边、卡片 header 等
/// 非 body 表面，浅色下 50% 黑压在白底上只有 3.95:1，达不到 WCAG AA 对小字的
/// 4.5:1（U5 真机实测文本卡 footer 4.0:1、链接卡 footer 4.07:1）。
///
/// 这里只服务两处 footer：浅色提到 58% 黑（白底合成 `#6B6B6B` ≈ 5.3:1），
/// 深色保持 55% 白（深底 ≈ 5.1–6.2:1，不动）。正文仍是 15.1:1，脚注依旧明显
/// 低一个层级，不会被读成正文。
///
/// 文本卡的脚注底色是来源内容自带的（富文本可以带任意底色），所以文本卡那边
/// 走 `contrastSafe`：在语义 token 的基础上，只有当底色把它压到 5:1 以下时才
/// 继续往黑/白一侧加深，其余情况颜色与 token 完全一致。
@MainActor
enum FooterAppearance {
    /// WCAG AA 小字是 4.5:1；脚注按 5:1 兜底，留一点抗锯齿/取整余量。
    static let targetContrast = 5.0

    private static let secondary: NSColor = {
        let light = NSColor.black.withAlphaComponent(0.58)
        let dark = NSColor.white.withAlphaComponent(0.55)
        return NSColor(name: nil) { SearchAppearance.appearanceColor(appearance: $0, dark: dark, light: light) }
    }()

    /// 脚注文字色（动态色：按调用方/底色所在的那一侧解析）。
    static func secondaryForeground() -> NSColor { secondary }

    // MARK: - WCAG 对比度

    /// WCAG 2.x 相对亮度（sRGB）。
    static func luminance(of color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return 0 }
        func linear(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(Double(rgb.redComponent))
            + 0.7152 * linear(Double(rgb.greenComponent))
            + 0.0722 * linear(Double(rgb.blueComponent))
    }

    /// 两个实色之间的 WCAG 对比度。带 alpha 的前景要先合成到底色上再量。
    static func contrast(_ foreground: NSColor, over background: NSColor) -> Double {
        let composited = composite(foreground, over: background)
        let first = luminance(of: composited)
        let second = luminance(of: background)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    private static func composite(_ foreground: NSColor, over background: NSColor) -> NSColor {
        guard let front = foreground.usingColorSpace(.deviceRGB),
              let back = background.usingColorSpace(.deviceRGB) else { return foreground }
        let alpha = Double(front.alphaComponent)
        guard alpha < 1 else { return front }
        return NSColor(deviceRed: CGFloat(Double(front.redComponent) * alpha + Double(back.redComponent) * (1 - alpha)),
                       green: CGFloat(Double(front.greenComponent) * alpha + Double(back.greenComponent) * (1 - alpha)),
                       blue: CGFloat(Double(front.blueComponent) * alpha + Double(back.blueComponent) * (1 - alpha)),
                       alpha: 1)
    }

    /// 对比度兜底：`base` 在给定底色上不足 `target` 时，只把不透明度往黑/白一侧
    /// 加（不换色相、不降不透明度），直到达标或到纯黑/纯白。
    ///
    /// 常态下（浅色白底 / 深色窗口底）`base` 本身就达标，函数原样返回——所以
    /// 只有「来源自带底色把脚注压暗」的少数情形才会看到颜色变化。
    static func contrastSafe(_ base: NSColor, over background: NSColor,
                             target: Double = targetContrast) -> NSColor {
        guard let baseRGB = base.usingColorSpace(.deviceRGB),
              let backgroundRGB = background.usingColorSpace(.deviceRGB) else { return base }
        let initial = contrast(baseRGB, over: backgroundRGB)
        guard initial < target else { return baseRGB }
        // 方向由 token 自己决定（浅色是黑、深色是白），不要用底色的亮度重算：
        // 中间调底色在 WCAG 亮度与「看起来是浅色」两种阈值上会给出相反的答案。
        let towardsBlack = luminance(of: baseRGB) < 0.5
        let extreme: CGFloat = towardsBlack ? 0 : 1
        var alpha = Double(baseRGB.alphaComponent)
        while alpha < 1 {
            alpha = min(1, alpha + 0.02)
            let candidate = NSColor(deviceRed: extreme, green: extreme, blue: extreme, alpha: CGFloat(alpha))
            if contrast(candidate, over: backgroundRGB) >= target { return candidate }
        }
        return NSColor(deviceRed: extreme, green: extreme, blue: extreme, alpha: 1)
    }
}
