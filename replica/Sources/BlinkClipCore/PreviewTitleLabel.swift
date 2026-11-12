import AppKit

/// The native text-field wrapper used by the recovered preview title.
@MainActor
public final class PreviewTextField: NSView, NSTextFieldDelegate {
    public var onDidEndEditing: (() -> Void)?
    private var storedTextField: NSTextField?

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

    /// initialize and configure the platform field exactly once.
    public func makeTextField() -> NSTextField {
        if let storedTextField { return storedTextField }
        let field = NSTextField()
        configureTextField(field)
        storedTextField = field
        return field
    }

    /// these defaults precede the preview title's own appearance.
    public func configureTextField(_ field: NSTextField) {
        field.delegate = self
        field.isBordered = false
        field.isEditable = false
        field.drawsBackground = false
        field.usesSingleLineMode = true
        field.allowsExpansionToolTips = true
        field.allowsDefaultTighteningForTruncation = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.alignment = .natural
        field.focusRingType = .none
    }

    /// PastePlatform: NSTextField.text reads stringValue.
    public func currentText() -> String { makeTextField().stringValue }

    /// PastePlatform: a nil text becomes an empty stringValue.
    @discardableResult
    public func setText(_ value: String?) -> Int {
        makeTextField().stringValue = value ?? ""
        return 0
    }

    public func currentTextOrNil() -> String? { currentText() }

    @discardableResult
    public func updateText(_ value: String?) -> Int { setText(value) }

    public func isEditable() -> Bool { makeTextField().isEditable }

    public func placeholderText() -> String? { makeTextField().placeholderAttributedString?.string }

    @discardableResult
    public func setPlaceholder(_ value: String?) -> Int {
        let field = makeTextField()
        field.placeholderAttributedString = value.map {
            NSAttributedString(string: $0, attributes: [
                .foregroundColor: field.textColor?.withAlphaComponent(0.6) ?? NSColor.textColor,
                .font: field.font ?? NSFont.preferredFont(forTextStyle: .title3, options: [:])
            ])
        }
        return 0
    }

    @discardableResult
    public func setTextColor(_ color: NSColor?) -> Int {
        let field = makeTextField()
        field.textColor = color
        setPlaceholder(placeholderText())
        return 0
    }

    @discardableResult
    public func setEditable(_ value: Bool) -> Int {
        makeTextField().isEditable = value
        return 0
    }

    /// reapply current text, then invalidate the wrapper's size.
    public func resetText() {
        let value = currentText()
        setText(value)
        invalidateIntrinsicContentSize()
    }

    /// retain abortEditing's result and refresh intrinsic sizing.
    @discardableResult
    public func abortEditing() -> Bool {
        let result = makeTextField().abortEditing()
        resetText()
        return result
    }

    public func notifyDidEndEditing() { onDidEndEditing?() }

    public func controlTextDidEndEditing(_ obj: Notification) { notifyDidEndEditing() }

    public func controlTextDidChange(_ obj: Notification) { resetText() }

    public override var acceptsFirstResponder: Bool { makeTextField().acceptsFirstResponder }
    public override func resignFirstResponder() -> Bool { makeTextField().resignFirstResponder() }

    public override func becomeFirstResponder() -> Bool {
        focus()
    }

    public func focus() -> Bool {
        let field = makeTextField()
        let result = field.becomeFirstResponder()
        if let editor = field.currentEditor() as? NSTextView {
            // The SDK declares this property nonnull, but the original forwards
            // the nullable NSTextField.textColor without an extra nil branch.
            let selector = NSSelectorFromString("setInsertionPointColor:")
            typealias Setter = @convention(c) (NSTextView, Selector, NSColor?) -> Void
            let setter = unsafeBitCast(editor.method(for: selector)!, to: Setter.self)
            setter(editor, selector, field.textColor)
        }
        return result
    }

    public override var intrinsicContentSize: NSSize {
        let field = makeTextField()
        let height = field.intrinsicContentSize.height
        let width = field.sizeThatFits(NSSize(width: CGFloat.infinity, height: height)).width
        return NSSize(width: width.rounded(.toNearestOrAwayFromZero), height: height)
    }
}

/// Paste PreviewHeader.TitleLabel's edit, cancel and commit state machine.
@MainActor
public final class PreviewTitleLabel: NSView {
    public var onCommitEditing: ((String) -> Void)?
    private var storedTextField: PreviewTextField?
    private var originalText: String?

    public init() {
        super.init(frame: .zero)
        let field = makeTextField()
        addSubview(field)
        constrainTextField(field)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public func makeTextField() -> PreviewTextField {
        if let storedTextField { return storedTextField }
        let field = PreviewTextField()
        configureTextField(field)
        storedTextField = field
        return field
    }

    public func configureTextField(_ field: PreviewTextField) {
        field.onDidEndEditing = { [weak self] in self?.commitEditing() }
        field.setTextColor(SearchAppearance.foregroundColor())
        field.alphaValue = 0.8
        field.makeTextField().font = NSFont.preferredFont(forTextStyle: .headline, options: [:])
    }

    public func constrainTextField(_ field: PreviewTextField) {
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: leadingAnchor),
            field.trailingAnchor.constraint(equalTo: trailingAnchor),
            field.topAnchor.constraint(equalTo: topAnchor),
            field.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @discardableResult
    public func beginEditing() -> Int {
        let field = makeTextField()
        originalText = field.currentTextOrNil()
        field.setEditable(true)
        field.window?.makeFirstResponder(field)
        return 0
    }

    @discardableResult
    public func cancelEditing() -> Int {
        let field = makeTextField()
        field.setEditable(false)
        field.updateText(originalText)
        field.abortEditing()
        field.window?.makeFirstResponder(nil)
        return 0
    }

    public func commitEditing() {
        let field = makeTextField()
        field.setEditable(false)
        field.window?.makeFirstResponder(nil)
        if let onCommitEditing { onCommitEditing(field.currentTextOrNil()!) }
    }

    public override func mouseDown(with event: NSEvent) {
        if !makeTextField().isEditable() { beginEditing() }
        else { super.mouseDown(with: event) }
    }
}
