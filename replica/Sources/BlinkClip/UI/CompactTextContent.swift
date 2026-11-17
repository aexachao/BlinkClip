import AppKit
import BlinkClipCore
import SwiftUI

@MainActor
final class CompactTextContentView: NSView {
    private let label = NSTextField(labelWithAttributedString: NSAttributedString(string: ""))
    /// 卡片正文所在的那块底色。纯文本的底色是动态系统色，所以「底色亮还是暗」
    /// 只能在真正生效的外观里判读；这里只存语义底色，前景色按需重新解析。
    private var cardBackground: NSColor?
    /// 条目原文（只读快照）。真正画出来的文字是 `displayedText`。
    private var source = NSAttributedString(string: "")

    /// 真正交给 label 的文本：超出行数上限时已经截断并在末尾补了 `…`。
    private(set) var displayedText = ""
    /// 条目原文长度（字符数），用于断言「截断确实发生了」。
    private(set) var sourceCharacterCount = 0
    /// 按当前 `bounds.height` 算出的行数上限（≥ 1）。
    private(set) var maxLineCount = 0
    /// 实际渲染行数，恒 ≤ `maxLineCount`。
    private(set) var renderedLineCount = 0
    /// 是否因为放不下而截断（此时 `displayedText` 以 `…` 结尾）。
    private(set) var isTruncated = false
    /// 每次 `update(text:)` 递增；`layout()` 靠它判断要不要重排。
    private var sourceGeneration = 0
    /// 上一次裁断用的尺寸与内容版本，避免每次 layout 都重新做二分测量。
    private var lastAppliedLayout: (width: CGFloat, height: CGFloat, generation: Int)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.maximumNumberOfLines = 0
        label.alignment = .natural
        label.textColor = CompactTextCardAppearance.foreground(on: nil, ambient: effectiveAppearance)
        label.font = PreviewAttributedText.bodyFont()
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            // 旧实现给了 10pt 的下溢余量，文字能画到正文区外面（脚注带里）。正文现在
            // 自己裁断到行数上限，所以下沿直接钉在 bounds 上。
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 外观变化后重新解析前景色。这里刻意**不覆盖** appearance：覆盖会让整棵子树
    /// 停在旧外观上，正是白底白字的来源；只有前景色需要按底色一侧重新解析成静态色。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshForegroundColor()
    }

    /// 视图从没有窗口的上下文插进面板时 effectiveAppearance 会变，补一次刷新。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshForegroundColor()
    }

    /// 卡片尺寸变化（面板高度拖动）后行数上限跟着变，重新裁一次。
    override func layout() {
        super.layout()
        applyLineLimit()
    }

    func update(text: AttributedString) {
        cardBackground = CompactTextCardAppearance.background(for: text)
        source = NSAttributedString(text)
        sourceCharacterCount = source.string.count
        sourceGeneration += 1
        refreshForegroundColor()
        applyLineLimit()
    }

    private func refreshForegroundColor() {
        label.textColor = CompactTextCardAppearance.foreground(on: cardBackground,
                                                              ambient: effectiveAppearance)
    }

    /// 把渲染文本裁到「正文区高度」能放下的行数，末尾补 `…`。
    ///
    /// 刻意不用 NSTextField 自己的尾部截断：那套截断只保证多行里的最后一行被省略，
    /// 卡片正文同时要满足「行数 ≤ 上限」和「最后一行为省略号」两条可断言条件，且
    /// 无空格长串（长 URL、长 token）必须能在词中间断开。这里用实际排版高度做二分
    /// 找最长前缀，再拼上 `…`，渲染字符串本身就是断言依据。
    private func applyLineLimit() {
        let width = bounds.width
        let height = bounds.height
        guard source.length > 0, width > 1, height > 1 else {
            lastAppliedLayout = nil
            maxLineCount = 0
            renderedLineCount = 0
            isTruncated = false
            displayedText = ""
            label.attributedStringValue = NSAttributedString(string: "")
            return
        }
        if let last = lastAppliedLayout,
           last.width == width, last.height == height, last.generation == sourceGeneration {
            return
        }
        lastAppliedLayout = (width, height, sourceGeneration)
        let font = PreviewAttributedText.bodyFont()
        // 用真实排版里量出来的行高（两行高 − 一行高），而不是字体度量估算值：
        // 两者差 1pt 就会让「行数上限」和实际绘制行数对不上。
        let probe = NSAttributedString(string: "Ag", attributes: [.font: font])
        let singleLineHeight = CardTextMetrics.height(of: probe, width: width)
        let doubleLineHeight = CardTextMetrics.height(of: NSAttributedString(string: "Ag\nAg",
            attributes: [.font: font]), width: width)
        let lineHeight = max(1, doubleLineHeight - singleLineHeight)
        let limit = max(1, Int(floor(height / lineHeight)))
        maxLineCount = limit
        let allowedHeight = min(height, CGFloat(limit) * lineHeight)
        let measured = Self.withBodyFont(source, font: font)
        if CardTextMetrics.height(of: measured, width: width) <= allowedHeight + 0.5 {
            show(measured, lineHeight: lineHeight, width: width, truncated: false)
            return
        }
        let ellipsis = NSAttributedString(string: "…", attributes: [.font: font])
        var low = 0
        var high = measured.length - 1
        var best = NSMutableAttributedString(attributedString: ellipsis)
        while low <= high {
            let middle = (low + high) / 2
            let candidate = NSMutableAttributedString(attributedString:
                measured.attributedSubstring(from: NSRange(location: 0, length: middle)))
            // 尾部换行/空白会把省略号挤到下一行，先去掉再拼。
            while candidate.length > 0, let last = candidate.string.last,
                  last.isWhitespace || last.isNewline {
                candidate.deleteCharacters(in: NSRange(location: candidate.length - 1, length: 1))
            }
            candidate.append(ellipsis)
            if CardTextMetrics.height(of: candidate, width: width) <= allowedHeight + 0.5 {
                best = candidate
                low = middle + 1
            } else {
                high = middle - 1
            }
        }
        // 兜底：来源富文本可能自带行距，量出来的高度仍超过正文区时继续减字。
        while best.length > 1, CardTextMetrics.height(of: best, width: width) > height {
            best.deleteCharacters(in: NSRange(location: best.length - 2, length: 1))
        }
        show(best, lineHeight: lineHeight, width: width, truncated: true)
    }

    private func show(_ string: NSAttributedString, lineHeight: CGFloat, width: CGFloat, truncated: Bool) {
        label.attributedStringValue = string
        label.maximumNumberOfLines = max(1, maxLineCount)
        label.lineBreakMode = .byTruncatingTail
        displayedText = string.string
        isTruncated = truncated
        let drawn = CardTextMetrics.height(of: string, width: width)
        renderedLineCount = lineHeight > 0 ? max(1, Int(floor(drawn / lineHeight + 0.05))) : 1
    }

    /// 补上正文基准字体：来源富文本自带的字体保留，只有缺字体属性的片段用 `bodyFont`。
    private static func withBodyFont(_ string: NSAttributedString, font: NSFont) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: string)
        let full = NSRange(location: 0, length: copy.length)
        var missing: [NSRange] = []
        copy.enumerateAttribute(.font, in: full) { value, range, _ in
            if value == nil { missing.append(range) }
        }
        for range in missing { copy.addAttribute(.font, value: font, range: range) }
        return copy
    }
}

@MainActor
struct CompactTextContent: NSViewRepresentable {
    let text: AttributedString

    func makeNSView(context: Context) -> CompactTextContentView {
        let view = CompactTextContentView(frame: .zero)
        view.update(text: text)
        return view
    }

    func updateNSView(_ nsView: CompactTextContentView, context: Context) {
        nsView.update(text: text)
    }

    /// 卡片正文区由外层 `frame(height:)` 给定：接受提案尺寸，正文才不会按自然高度
    /// 把自己撑到卡片外面（旧实现在这里拿的是 294pt 的自然高度，把标题条顶了出去）。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CompactTextContentView,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: width, height: height)
    }
}
