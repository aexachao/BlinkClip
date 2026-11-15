import AppKit
import BlinkClipCore
import QuartzCore
import SwiftUI

@MainActor
enum CompactTextCardAppearance {
    static func background(for text: AttributedString) -> NSColor {
        let source = NSAttributedString(text)
        if PreviewAttributedText.isPlainText(source) {
            return PreviewTextColors.backgroundColorSlot().pointee!
        }
        let color = PreviewTextColors.dominantBackgroundColor(source)
        return color.alphaComponent < 1 ? LinkPreviewSurface.startingColor : color
    }

    static func appearance(for color: NSColor) -> NSAppearance {
        NSAppearance(named: PreviewTextColors.isLightColor(color) ? .aqua : .darkAqua)
            ?? NSAppearance.currentDrawing()
    }

    /// 卡片底色是亮是暗。纯文本的底色是 `NSColor(name:)` 动态色，必须在真正生效的
    /// 外观（调用方的 effectiveAppearance）里读，否则会按旧外观判成另一侧。
    static func isLightBackground(_ color: NSColor, in appearance: NSAppearance) -> Bool {
        var light = false
        appearance.performAsCurrentDrawingAppearance { light = PreviewTextColors.isLightColor(color) }
        return light
    }

    /// 把动态色调按「卡片底色所在的一侧」解析成静态色。
    ///
    /// 面板会切浅/深外观，而来源内容自带的底色（网页/富文本的深色底）是静态的：
    /// 语义由底色决定，不由窗口决定。因此这里一次性算出静态色，父视图外观一变就
    /// 重算，子层 CGColor 永远只拿到算好的静态值（顺序不再影响结果）。
    static func resolved(_ color: NSColor, on background: NSColor, ambient: NSAppearance) -> NSColor {
        let name: NSAppearance.Name = isLightBackground(background, in: ambient) ? .aqua : .darkAqua
        let target = NSAppearance(named: name) ?? ambient
        var resolved = color
        target.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.deviceRGB) ?? color
        }
        return resolved
    }

    /// 卡片正文的前景色：底色未知时退回系统动态前景，否则按底色一侧解析一次。
    static func foreground(on background: NSColor?, ambient: NSAppearance) -> NSColor {
        let token = SearchAppearance.foregroundColor() ?? NSColor.labelColor
        guard let background else { return token }
        return resolved(token, on: background, ambient: ambient)
    }

    /// 卡片脚注（「N 个字符」/ 渐隐带）的次要前景色。
    ///
    /// 走 `FooterAppearance`：浅色 footer 小字需要 ≥4.5:1，而工具栏那个 50% 黑
    /// 压在白底上只有 3.95:1（U5 实测 4.0:1）。再叠一层 `contrastSafe`：正文卡的
    /// 脚注底色来自来源内容（富文本可带浅灰/中间调底色），常规白底/深底原样返回
    /// token，只有被底色压到 5:1 以下时才继续加深。
    static func secondaryForeground(on background: NSColor, ambient: NSAppearance) -> NSColor {
        let isLight = isLightBackground(background, in: ambient)
        let side = NSAppearance(named: isLight ? .aqua : .darkAqua) ?? ambient
        var base = FooterAppearance.secondaryForeground()
        var resolvedBackground = background
        side.performAsCurrentDrawingAppearance {
            base = base.usingColorSpace(.deviceRGB) ?? base
            resolvedBackground = background.usingColorSpace(.deviceRGB) ?? background
        }
        return FooterAppearance.contrastSafe(base, over: resolvedBackground)
    }
}

@MainActor
private final class CompactTextFadeView: NSView {
    private let gradient = CAGradientLayer()
    private var fadingColor: NSColor?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(gradient)
        clipsToBounds = true
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(color: NSColor) {
        fadingColor = color
        updateColors()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.colors = [(fadingColor?.withAlphaComponent(0) ?? .clear).cgColor,
                               (fadingColor ?? .clear).cgColor]
            gradient.transform = CATransform3DMakeRotation(0, 0, 0, 1)
            CATransaction.commit()
        }
    }
}

@MainActor
final class CompactTextFooterView: NSView {
    private let opaqueView = LayerBackedView(frame: .zero)
    private let fadingView = CompactTextFadeView(frame: .zero)
    private let textLabel = NSTextField(labelWithString: "")
    private lazy var opaqueHeight = opaqueView.heightAnchor.constraint(equalToConstant: 18)
    /// 脚注带的本色 = 卡片底色。纯文本时它是动态色，因此只存语义色，
    /// 每次外观变化都重新解析成静态色（旧实现按创建时外观钉死 → ΔRGB=0）。
    private var bandColor: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textLabel.textColor = FooterAppearance.secondaryForeground()
        textLabel.alignment = .center
        textLabel.font = NSFont.preferredFont(forTextStyle: .callout, options: [:])
        for view in [opaqueView, fadingView, textLabel] as [NSView] {
            addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            fadingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fadingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fadingView.topAnchor.constraint(equalTo: topAnchor),
            fadingView.heightAnchor.constraint(equalToConstant: 32),
            fadingView.bottomAnchor.constraint(equalTo: opaqueView.topAnchor),
            opaqueView.leadingAnchor.constraint(equalTo: leadingAnchor),
            opaqueView.trailingAnchor.constraint(equalTo: trailingAnchor),
            opaqueView.bottomAnchor.constraint(equalTo: bottomAnchor),
            opaqueHeight,
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        setContentHuggingPriority(.init(750), for: .vertical)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 32 + opaqueHeight.constant)
    }

    /// 不再覆盖 appearance：让脚注跟着面板的当前外观走，再按底色一侧把带色与
    /// 文字色重解析成静态色。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshColors()
    }

    func configure(length: Int, sizeClass: UInt8, fadingColor: NSColor) {
        bandColor = fadingColor
        textLabel.stringValue = String(localized: PreviewLocalization.characterCount(Int32(length)))
        let compact = sizeClass == 3
        textLabel.alphaValue = compact ? 0 : 1
        textLabel.isHidden = compact
        opaqueHeight.constant = compact ? 0 : 18
        invalidateIntrinsicContentSize()
        refreshColors()
    }

    private func refreshColors() {
        guard let bandColor else { return }
        // 静态解析后再下发：子层 CGColor 不再依赖子视图自己的 effectiveAppearance，
        // 所以「先父后子」的刷新顺序不再影响结果。
        let band = CompactTextCardAppearance.resolved(bandColor, on: bandColor,
                                                      ambient: effectiveAppearance)
        opaqueView.backgroundColor = band
        fadingView.configure(color: band)
        textLabel.textColor = CompactTextCardAppearance.secondaryForeground(on: bandColor,
                                                                           ambient: effectiveAppearance)
    }
}

@MainActor
struct CompactTextFooter: NSViewRepresentable {
    let length: Int
    let sizeClass: UInt8
    let fadingColor: NSColor

    func makeNSView(context: Context) -> CompactTextFooterView {
        let view = CompactTextFooterView(frame: .zero)
        view.configure(length: length, sizeClass: sizeClass, fadingColor: fadingColor)
        return view
    }

    func updateNSView(_ nsView: CompactTextFooterView, context: Context) {
        nsView.configure(length: length, sizeClass: sizeClass, fadingColor: fadingColor)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CompactTextFooterView,
                     context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        return CGSize(width: width, height: sizeClass == 3 ? 32 : 50)
    }
}
