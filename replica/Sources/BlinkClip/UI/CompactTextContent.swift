import AppKit
import BlinkClipCore
import SwiftUI

@MainActor
final class CompactTextContentView: NSView {
    private let label = NSTextField(labelWithAttributedString: NSAttributedString(string: ""))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.maximumNumberOfLines = 0
        label.alignment = .natural
        label.textColor = SearchAppearance.foregroundColor()
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

    func update(text: AttributedString) {
        appearance = CompactTextCardAppearance.appearance(
            for: CompactTextCardAppearance.background(for: text))
        label.attributedStringValue = NSAttributedString(text)
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
