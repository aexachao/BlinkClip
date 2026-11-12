import AppKit
import SwiftUI
import BlinkClipCore

@MainActor
struct ReplicaCardTitle: NSViewRepresentable {
    let state: ReplicaUIState
    let itemID: UUID
    var input: ClipboardRestoreItem? = nil
    let title: String
    let font: NSFont
    let textColor: NSColor

    func makeNSView(context: Context) -> ReplicaCardTitleView {
        let view = ReplicaCardTitleView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: ReplicaCardTitleView, context: Context) {
        view.configure(state: state, itemID: itemID, input: input, title: title, font: font, textColor: textColor)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ReplicaCardTitleView, context: Context) -> CGSize? {
        let size = nsView.intrinsicContentSize
        return CGSize(width: min(proposal.width ?? size.width, size.width), height: size.height)
    }
}

@MainActor
final class ReplicaCardTitleView: NSView {
    let label = ItemTitleLabel()
    private(set) var itemID: UUID?
    private var lastModelTitle: String?
    private weak var editingPanel: ReplicaPanel?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(state: ReplicaUIState, itemID: UUID, input: ClipboardRestoreItem? = nil, title: String, font: NSFont, textColor: NSColor) {
        self.itemID = itemID
        // Offline lists have no CKShare permission record (nil path).
        label.isEditable = true
        let field = label.makeTextField()
        field.makeTextField().font = font
        field.setTextColor(textColor)
        if lastModelTitle != title {
            lastModelTitle = title
            field.updateText(title)
        }
        invalidateIntrinsicContentSize()
        field.makeTextField().setAccessibilityLabel("重命名项目")
        label.onCommitEditing = { [weak state] title in
            guard let state else { return }
            if let input {
                state.perform { try state.store.updateItem(input, title: title) }
            } else {
                state.perform { try state.store.updateItem(id: itemID, title: title, text: nil) }
            }
        }
    }

    func beginEditing() {
        guard label.isEditable else { return }
        editingPanel = window as? ReplicaPanel
        editingPanel?.cardTitleEditingOwner = self
        label.beginEditing()
    }

    func ownsEditor(in panel: ReplicaPanel) -> Bool {
        let field = label.makeTextField().makeTextField()
        return window === panel && label.isEditing && field.currentEditor() != nil
            && field.currentEditor() === panel.firstResponder
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if editingPanel !== window {
            if editingPanel?.cardTitleEditingOwner === self { editingPanel?.cardTitleEditingOwner = nil }
            editingPanel = nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let result = super.hitTest(point) else { return nil }
        return label.isEditing ? result : self
    }

    override func mouseDown(with event: NSEvent) {
        if label.isEditable, !label.isEditing {
            editingPanel = window as? ReplicaPanel
            editingPanel?.cardTitleEditingOwner = self
            label.mouseDown(with: event)
        } else { super.mouseDown(with: event) }
    }

    override var intrinsicContentSize: NSSize { label.intrinsicContentSize }
}
