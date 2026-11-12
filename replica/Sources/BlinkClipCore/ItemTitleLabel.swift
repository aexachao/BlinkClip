import AppKit

/// ItemCell.HeaderView.TitleLabel has its own queued-focus editing contract.
@MainActor
public final class ItemTitleLabel: NSView, NSTextFieldDelegate {
    public var isEditable = false
    public var onCommitEditing: ((String) -> Void)?
    private var storedTextField: PreviewTextField?
    private var originalText: String?

    public init() {
        super.init(frame: .zero)
        let field = makeTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.topAnchor.constraint(equalTo: topAnchor),
            field.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func makeTextField() -> PreviewTextField {
        if let storedTextField { return storedTextField }
        let field = PreviewTextField()
        storedTextField = field
        field.onDidEndEditing = { [weak self] in self?.commitEditing() }
        // Forward the shared field's sizing/end callbacks while owning cancelOperation.
        field.makeTextField().delegate = self
        return field
    }

    public var isEditing: Bool { makeTextField().isEditable() }

    public func beginEditing() {
        let field = makeTextField()
        originalText = field.currentTextOrNil()
        field.setEditable(true)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let field = self.makeTextField()
            field.window?.makeFirstResponder(field)
        }
    }

    public func cancelEditing() {
        let field = makeTextField()
        field.setEditable(false)
        field.updateText(originalText)
        field.abortEditing()
        enqueueFocusClear()
    }

    public func commitEditing() {
        let field = makeTextField()
        field.setEditable(false)
        enqueueFocusClear()
        if let onCommitEditing { onCommitEditing(field.currentTextOrNil() ?? "") }
    }

    private func enqueueFocusClear() {
        DispatchQueue.main.async { [weak self] in
            self?.makeTextField().window?.makeFirstResponder(nil)
        }
    }

    public override func cancelOperation(_ sender: Any?) { cancelEditing() }

    public override func mouseDown(with event: NSEvent) {
        if isEditable, !isEditing { beginEditing() }
        else { super.mouseDown(with: event) }
    }

    public func controlTextDidEndEditing(_ obj: Notification) {
        makeTextField().controlTextDidEndEditing(obj)
    }

    public func controlTextDidChange(_ obj: Notification) {
        makeTextField().controlTextDidChange(obj)
        invalidateIntrinsicContentSize()
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        cancelOperation(nil)
        return true
    }

    public override var intrinsicContentSize: NSSize { makeTextField().intrinsicContentSize }
}
