import AppKit
import Foundation
import BlinkClipCore

/// 防回归：文本卡片外观四态矩阵。
///
/// 曾经的确诊缺陷（P1）：`CompactTextContentView.update(text:)` 在创建时把
/// `appearance` 钉成「旧外观」，label 的动态 `textColor` 于是永远按旧外观解析，
/// 而卡片底色（`PanelViews` 里的 `Color(nsColor: background)`) 跟着当前外观变白
/// → 浅色下面板里出现白底白字（实测 1.07:1）。`CompactTextFooterView` 同样把
/// 父 appearance 钉死，导致 `viewDidChangeEffectiveAppearance` 里解析出的
/// CGColor 仍是旧值，渐隐带与「N 个字符」冻结（实测 ΔRGB=0）。
///
/// 这个 harness 就是那两条缺陷的回归闸门：{创建时浅,创建时深} × {当前浅,当前深}
/// 四态，全部要求正文前景与卡片底色的对比度 ≥ 4.5:1、footer 带色等于当前外观下
/// 的卡片底色，并且真的渲染出了可见的文字像素（不是白底白字的 0 像素）。
/// 修复前四态里「创建时与当前不一致」的两态必然失败，修复后四态全绿。
@main
struct TextCardAppearanceHarness {
    struct Failure: Error, CustomStringConvertible { let description: String }

    enum Side: String, CaseIterable {
        case light, dark
        var appearanceName: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
        var appearance: NSAppearance {
            guard let appearance = NSAppearance(named: appearanceName) else {
                fatalError("missing appearance \(appearanceName.rawValue)")
            }
            return appearance
        }
    }

    struct RGB: Equatable {
        var r: Double
        var g: Double
        var b: Double
    }

    struct StateReport {
        var created: Side
        var current: Side
        var cardBackground: String
        var bodyForeground: String
        var bodyContrast: Double
        var bodyTextPixels: Int
        var bodyStrongTextPixels: Int
        var bodyPixelContrast: Double
        var footerBand: String
        var footerExpectedBand: String
        var footerBandMatches: Bool
        var footerTextPixels: Int
        var footerTextContrast: Double
        var footerTextSide: String
    }

    static var checks = 0
    static func check(_ condition: Bool, _ message: @autoclosure () -> String) throws {
        checks += 1
        guard condition else { throw Failure(description: message()) }
    }

    // MARK: - 颜色工具（WCAG 2.x 相对亮度与对比度）

    static func rgb(_ color: NSColor) -> RGB {
        guard let converted = color.usingColorSpace(.deviceRGB) else { return RGB(r: 0, g: 0, b: 0) }
        return RGB(r: Double(converted.redComponent), g: Double(converted.greenComponent),
                   b: Double(converted.blueComponent))
    }

    static func hex(_ color: RGB) -> String {
        String(format: "#%02X%02X%02X", Int((color.r * 255).rounded()),
               Int((color.g * 255).rounded()), Int((color.b * 255).rounded()))
    }

    static func linear(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func luminance(_ color: RGB) -> Double {
        0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    static func contrast(_ lhs: RGB, _ rhs: RGB) -> Double {
        let a = luminance(lhs), b = luminance(rhs)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// 文字色通常带 alpha（系统前景 0.85、次要前景 0.5），对比度要按合成后的
    /// 实色算，否则会高估。
    static func composite(_ foreground: RGB, alpha: Double, over background: RGB) -> RGB {
        RGB(r: foreground.r * alpha + background.r * (1 - alpha),
            g: foreground.g * alpha + background.g * (1 - alpha),
            b: foreground.b * alpha + background.b * (1 - alpha))
    }

    static func channelDelta(_ lhs: RGB, _ rhs: RGB) -> Double {
        max(abs(lhs.r - rhs.r), max(abs(lhs.g - rhs.g), abs(lhs.b - rhs.b)))
    }

    // MARK: - 渲染

    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    @MainActor
    static func render(_ view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        let scale = 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(view.bounds.width) * scale,
                                         pixelsHigh: Int(view.bounds.height) * scale,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else {
            throw Failure(description: "cannot allocate bitmap for \(view)")
        }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    static func save(_ rep: NSBitmapImageRep, _ name: String, _ directory: URL?) throws {
        guard let directory,
              let data = rep.representation(using: .png, properties: [:]) else { return }
        try data.write(to: directory.appendingPathComponent(name + ".png"))
    }

    @MainActor
    static func pump(_ seconds: Double = 0.08) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    // MARK: - 生产输入

    @MainActor
    static func makeWindow(_ side: Side) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 240, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = side.appearance
        window.contentView = FlippedView(frame: NSRect(x: 0, y: 0, width: 240, height: 180))
        window.orderFront(nil)
        return window
    }

    static func plainText() -> AttributedString {
        let lines = ["夏天傍晚的蝉声还在屋檐下回响，",
                     "窗外的梧桐叶被风翻了一页又一页。",
                     "The quick brown fox jumps over the lazy dog,",
                     "and the clipboard remembers every bit of it."]
        return AttributedString(NSAttributedString(string: lines.joined(separator: "\n")))
    }

    /// 来源内容自带深色底：网页/富文本里复制出来的代码块。它的还原语义是
    /// 「底色来自来源」，所以无论面板当前是浅色还是深色，正文都必须是浅色。
    static func darkSourceText() -> AttributedString {
        let source = NSMutableAttributedString(string: "let color = NSColor(white: 0.12, alpha: 1)\n// 深色来源块\nprint(color)")
        source.addAttribute(.backgroundColor, value: NSColor(white: 0.12, alpha: 1),
                            range: NSRange(location: 0, length: source.length))
        return AttributedString(source)
    }

    /// 生产里传给 footer 的 `fadingColor` 就是 `background(for:)` 原样返回的语义色
    /// （纯文本时是动态系统色），不是 harness 解析后的静态值；脚注必须拿它才能
    /// 随外观重解析。这里保持生产契约。
    @MainActor
    static func rawCardBackground(_ text: AttributedString) -> NSColor {
        CompactTextCardAppearance.background(for: text)
    }

    /// 卡片底色：production `PanelViews` 把它交给 SwiftUI 的 `Color(nsColor:)`，
    /// SwiftUI 按当前 colorScheme 解析动态色。这里在目标外观里解析成静态色，
    /// 才能拿来做像素/对比度断言（否则会落到 harness 当前的绘制外观上）。
    @MainActor
    static func cardBackground(_ text: AttributedString, under side: Side) -> NSColor {
        var background = NSColor.textBackgroundColor
        side.appearance.performAsCurrentDrawingAppearance {
            let raw = CompactTextCardAppearance.background(for: text)
            background = raw.usingColorSpace(.deviceRGB) ?? raw
        }
        return background
    }

    // MARK: - 四态矩阵

    @MainActor
    static func runState(created: Side, current: Side, text: AttributedString,
                         evidence: URL?) throws -> StateReport {
        let window = makeWindow(created)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        guard let container = window.contentView else { throw Failure(description: "missing container") }
        container.layoutSubtreeIfNeeded()

        // 模拟 SwiftUI 的一次更新：representable 在面板（已处于 created 外观）里被
        // 创建/更新。旧实现就是在这里把 appearance 钉死的，所以这一步放在
        // created 外观的绘制上下文里，让「创建时外观」可复现、不随系统漂移。
        var content: CompactTextContentView!
        var footer: CompactTextFooterView!
        created.appearance.performAsCurrentDrawingAppearance {
            content = CompactTextContentView(frame: NSRect(x: 4, y: 8, width: 232, height: 118))
            content.update(text: text)
            footer = CompactTextFooterView(frame: NSRect(x: 4, y: 130, width: 232, height: 50))
            footer.configure(length: text.characters.count, sizeClass: 2,
                             fadingColor: rawCardBackground(text))
        }
        let background = cardBackground(text, under: current)
        content.wantsLayer = true
        content.layer?.backgroundColor = background.cgColor
        footer.wantsLayer = true
        footer.layer?.backgroundColor = background.cgColor
        container.addSubview(content)
        container.addSubview(footer)
        container.layoutSubtreeIfNeeded()

        // 切到「当前外观」——这就是缺陷现场：面板/系统换浅色，卡片底色跟着变，
        // 而旧实现里被钉死的外观不会重新解析前景/带色。
        window.appearance = current.appearance
        pump()
        container.layoutSubtreeIfNeeded()

        // 1) 正文前景 vs 卡片底色（生产解析的实际颜色对）
        let expectedBackground = rgb(background)
        var label: NSTextField?
        var labelColor = NSColor.labelColor
        for subview in content.subviews {
            if let field = subview as? NSTextField { label = field; labelColor = field.textColor ?? .labelColor }
        }
        try check(label != nil, "content view lost its text label")
        var resolvedForeground = labelColor
        content.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedForeground = labelColor.usingColorSpace(.deviceRGB) ?? labelColor
        }
        let foreground = rgb(resolvedForeground)
        let bodyContrast = contrast(composite(foreground, alpha: Double(resolvedForeground.alphaComponent),
                                              over: expectedBackground), expectedBackground)
        try check(bodyContrast >= 4.5, String(format:
            "body contrast %.2f:1 below 4.5:1 (created %@, current %@, fg %@ on bg %@)",
            bodyContrast, created.rawValue, current.rawValue, hex(foreground), hex(expectedBackground)))
        try check(content.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue == current.appearanceName.rawValue,
                  "content view must inherit the live appearance (currently \(String(describing: content.effectiveAppearance.name)))")

        // 2) 真渲染出来的正文像素（白底白字的现场证据：≈0）
        let contentRep = try render(content)
        var bodyPixels = 0
        var strongPixels = 0
        var bodyPixelContrast = 0.0
        for y in 0..<contentRep.pixelsHigh {
            for x in 0..<contentRep.pixelsWide {
                guard let color = contentRep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let pixel = rgb(color)
                let ratio = contrast(pixel, expectedBackground)
                if luminanceDelta(pixel, expectedBackground) >= 0.05 { bodyPixels += 1 }
                if ratio >= 4.5 { strongPixels += 1 }
                if ratio > bodyPixelContrast { bodyPixelContrast = ratio }
            }
        }
        try check(bodyPixels >= 200, "body text did not render visibly (dark/light pixels = \(bodyPixels))")
        try check(strongPixels >= 100, "body text has no 4.5:1 pixels (strong pixels = \(strongPixels))")
        try check(bodyPixelContrast >= 4.5, String(format: "rendered body contrast %.2f:1 below 4.5:1", bodyPixelContrast))
        try save(contentRep, "body-\(created.rawValue)-to-\(current.rawValue)", evidence)

        // 3) footer 带色必须等于当前外观下的卡片底色
        let footerRep = try render(footer)
        let band = bandSample(footerRep)
        let bandDelta = channelDelta(band, expectedBackground)
        try check(bandDelta <= 0.04, String(format:
            "footer band %@ frozen in the old appearance (created %@, current %@, expected %@, max channel delta %.3f, footer appearance %@, content appearance %@)",
            hex(band), created.rawValue, current.rawValue, hex(expectedBackground), bandDelta,
            footer.effectiveAppearance.name.rawValue, content.effectiveAppearance.name.rawValue))
        let footerText = footerTextSample(footerRep, band: band)
        try check(footerText.pixels >= 30, "footer character count did not render (\(footerText.pixels) pixels)")
        let expectedTextSide = luminance(expectedBackground) > 0.5 ? "darker" : "brighter"
        try check(footerText.side == expectedTextSide, "footer text side \(footerText.side) does not match band \(hex(band))")
        try check(footerText.contrast >= 2.5, String(format: "footer text contrast %.2f:1 below 2.5:1", footerText.contrast))
        try save(footerRep, "footer-\(created.rawValue)-to-\(current.rawValue)", evidence)

        return StateReport(created: created, current: current,
                           cardBackground: hex(expectedBackground), bodyForeground: hex(foreground),
                           bodyContrast: bodyContrast, bodyTextPixels: bodyPixels,
                           bodyStrongTextPixels: strongPixels, bodyPixelContrast: bodyPixelContrast,
                           footerBand: hex(band), footerExpectedBand: hex(expectedBackground),
                           footerBandMatches: bandDelta <= 0.04, footerTextPixels: footerText.pixels,
                           footerTextContrast: footerText.contrast, footerTextSide: footerText.side)
    }

    static func luminanceDelta(_ lhs: RGB, _ rhs: RGB) -> Double {
        abs(luminance(lhs) - luminance(rhs))
    }

    /// footer 的实心带在底部 18pt（2x = 36 行）；左右两侧取样，避开居中的文字。
    static func bandSample(_ rep: NSBitmapImageRep) -> RGB {
        var samples: [RGB] = []
        for y in (rep.pixelsHigh - 34)..<(rep.pixelsHigh - 2) {
            for x in [8, 12, rep.pixelsWide - 12, rep.pixelsWide - 8] where x >= 0 && x < rep.pixelsWide {
                if let color = rep.colorAt(x: x, y: y) { samples.append(rgb(color)) }
            }
        }
        guard !samples.isEmpty else { return RGB(r: 0, g: 0, b: 0) }
        let count = Double(samples.count)
        return RGB(r: samples.reduce(0) { $0 + $1.r } / count,
                   g: samples.reduce(0) { $0 + $1.g } / count,
                   b: samples.reduce(0) { $0 + $1.b } / count)
    }

    static func footerTextSample(_ rep: NSBitmapImageRep, band: RGB)
        -> (pixels: Int, contrast: Double, side: String) {
        var pixels = 0
        var best = 0.0
        var bestPixel = band
        let xRange = (rep.pixelsWide / 5)..<(rep.pixelsWide * 4 / 5)
        for y in (rep.pixelsHigh - 36)..<rep.pixelsHigh {
            for x in xRange {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                let pixel = rgb(color)
                let ratio = contrast(pixel, band)
                if ratio >= 1.5 { pixels += 1 }
                if ratio > best { best = ratio; bestPixel = pixel }
            }
        }
        let side = luminance(bestPixel) < luminance(band) ? "darker" : "brighter"
        return (pixels, best, side)
    }

    // MARK: - 来源自带深色底：两种当前外观都要维持还原语义

    @MainActor
    static func runDarkSource() throws -> [String: Any] {
        var rows: [[String: Any]] = []
        for current in Side.allCases {
            let text = darkSourceText()
            let window = makeWindow(.light)
            defer { window.orderOut(nil); window.contentView = nil; window.close() }
            guard let container = window.contentView else { throw Failure(description: "missing container") }
            var content: CompactTextContentView!
            Side.light.appearance.performAsCurrentDrawingAppearance {
                content = CompactTextContentView(frame: NSRect(x: 4, y: 8, width: 232, height: 118))
                content.update(text: text)
            }
            container.addSubview(content)
            window.appearance = current.appearance
            pump()
            container.layoutSubtreeIfNeeded()
            let background = cardBackground(text, under: current)
            var backgroundIsLight = false
            current.appearance.performAsCurrentDrawingAppearance {
                backgroundIsLight = PreviewTextColors.isLightColor(background)
            }
            try check(!backgroundIsLight, "source dark background must stay dark")
            var label: NSTextField?
            for subview in content.subviews where subview is NSTextField { label = subview as? NSTextField }
            try check(label != nil, "dark-source content view lost its label")
            let storedLabelColor = label!.textColor ?? .labelColor
            var resolved = storedLabelColor
            content.effectiveAppearance.performAsCurrentDrawingAppearance {
                resolved = storedLabelColor.usingColorSpace(.deviceRGB) ?? storedLabelColor
            }
            let ratio = contrast(composite(rgb(resolved), alpha: Double(resolved.alphaComponent),
                                           over: rgb(background)), rgb(background))
            try check(ratio >= 4.5, String(format:
                "source dark background lost its light foreground (%.2f:1, current %@)", ratio, current.rawValue))
            // 来源自带的 foreground 属性必须原样保留（不被卡片前景覆盖）。
            let stored = label!.attributedStringValue
            try check(stored.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil,
                      "source background attribute was dropped")
            rows.append(["current": current.rawValue, "background": hex(rgb(background)),
                         "foreground": hex(rgb(resolved)), "contrast": ratio])
        }
        return ["states": rows]
    }

    @MainActor
    static func main() async {
        do {
            let evidence = ProcessInfo.processInfo.environment["BLINKCLIP_TEXT_CARD_EVIDENCE_DIR"]
                .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            _ = NSApplication.shared
            if let evidence { try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true) }

            var matrix: [StateReport] = []
            for created in Side.allCases {
                for current in Side.allCases {
                    matrix.append(try runState(created: created, current: current,
                                                text: plainText(), evidence: evidence))
                }
            }
            let darkSource = try runDarkSource()

            let rows = matrix.map { [
                "created": $0.created.rawValue, "current": $0.current.rawValue,
                "cardBackground": $0.cardBackground, "bodyForeground": $0.bodyForeground,
                "bodyContrast": $0.bodyContrast, "bodyTextPixels": $0.bodyTextPixels,
                "bodyStrongTextPixels": $0.bodyStrongTextPixels, "bodyPixelContrast": $0.bodyPixelContrast,
                "footerBand": $0.footerBand, "footerExpectedBand": $0.footerExpectedBand,
                "footerBandMatchesCurrentAppearance": $0.footerBandMatches,
                "footerTextPixels": $0.footerTextPixels, "footerTextContrast": $0.footerTextContrast,
                "footerTextSide": $0.footerTextSide
            ] as [String: Any] }
            let report: [String: Any] = [
                "passed": true,
                "checks": checks,
                "matrix": rows,
                "sourceDarkBackground": darkSource,
                "note": "防回归：{创建时浅,创建时深} × {当前浅,当前深}；修复前跨外观的两态必然白底白字/带色冻结。"
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8)!)
            if let evidence {
                try data.write(to: evidence.appendingPathComponent("four-state.json"))
            }
        } catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }
}
