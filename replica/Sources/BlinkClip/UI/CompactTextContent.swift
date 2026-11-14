import AppKit
import BlinkClipCore
import SwiftUI

@MainActor
final class CompactTextContentView: NSView {
    private let label = NSTextField(labelWithAttributedString: NSAttributedString(string: ""))
    /// 卡片正文所在的那块底色。纯文本的底色是动态系统色，所以「底色亮还是暗」
    /// 只能在真正生效的外观里判读；这里只存语义底色，前景色按需重新解析。
    private var cardBackground: NSColor?

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
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: 10)
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

    func update(text: AttributedString) {
        cardBackground = CompactTextCardAppearance.background(for: text)
        label.attributedStringValue = NSAttributedString(text)
        refreshForegroundColor()
    }

    private func refreshForegroundColor() {
        label.textColor = CompactTextCardAppearance.foreground(on: cardBackground,
                                                              ambient: effectiveAppearance)
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
}
