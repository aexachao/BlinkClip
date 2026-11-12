import AppKit

/// Recovered SearchField.InputView.TextView behavior. The panel supplies its
/// current typing attributes and translated placeholder; initializer/theme and
/// localization functions are tracked separately from these method contracts.
@MainActor
open class SearchTextView: NSTextView, NSMenuDelegate {
    public var canAcceptFocus = true
    public var preferredTypingAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: SearchAppearance.foregroundColor()!,
        .font: SearchAppearance.bodyFont()
    ]
    private var storedPlaceholderText: String?
    public var placeholderText: String {
        get { storedPlaceholderText ?? SearchAppearance.searchPlaceholder() }
        set { storedPlaceholderText = newValue }
    }
    private var storedPlaceholder: NSTextField?

    public override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    public func menuForEvent(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        menu?.delegate = self
        return menu
    }
    open override func menu(for event: NSEvent) -> NSMenu? { menuForEvent(for: event) }

    public func cleanContextMenu(_ menu: NSMenu) { SearchMenu.cleanMenu(menu) }
    public func menuWillOpen(_ menu: NSMenu) { cleanContextMenu(menu) }

    public func makePlaceholderField() -> NSTextField {
        if let storedPlaceholder { return storedPlaceholder }
        let label = NSTextField()
        configurePlaceholderLabel(label)
        storedPlaceholder = label
        return label
    }

    public func configurePlaceholderLabel(_ label: NSTextField) {
        label.drawsBackground = false
        label.isSelectable = false
        label.isEditable = false
        label.isBordered = false
        label.textColor = .placeholderTextColor
        label.font = preferredTypingAttributes[.font] as? NSFont
        label.stringValue = placeholderText
    }

    public func syncPlaceholderFont() {
        makePlaceholderField().font = preferredTypingAttributes[.font] as? NSFont
        typingAttributes = preferredTypingAttributes
        font = preferredTypingAttributes[.font] as? NSFont
    }

    public func currentCanAcceptFocus() -> Bool { canAcceptFocus }
    open override var acceptsFirstResponder: Bool { currentCanAcceptFocus() }

    public func focusAndSelect() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { setSelectedRange(selectedRange()) }
        return accepted
    }
    open override func becomeFirstResponder() -> Bool { focusAndSelect() }

    public func updateSelectedRange(_ range: NSRange, affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRange(range, affinity: affinity, stillSelecting: stillSelecting)
        syncPlaceholderFont()
    }
    open override func setSelectedRange(_ charRange: NSRange, affinity: NSSelectionAffinity, stillSelecting flag: Bool) {
        updateSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
    }

    public func handleTextChange() {
        super.didChangeText()
        makePlaceholderField().isHidden = !string.isEmpty
        syncPlaceholderFont()
    }
    @discardableResult
    public static func performOnContext<T>(_ context: T, action: (T) -> Void) -> Int {
        action(context)
        return 0
    }
    public func notifyTextChange() { Self.performOnContext(self) { $0.handleTextChange() } }
    open override func didChangeText() { notifyTextChange() }

    public func updateLayout() {
        super.layout()
        let x = textContainerOrigin.x - 1
        let y = textContainerOrigin.y
        let label = makePlaceholderField()
        var frame = label.frame
        frame.origin = NSPoint(x: x, y: y)
        label.frame = frame
        label.sizeToFit()
    }
    public func refreshLayout() { Self.performOnContext(self) { $0.updateLayout() } }
    open override func layout() { refreshLayout() }

    public func validateMenuItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == NSSelectorFromString("changeLayoutOrientation:") { return false }
        return super.validateUserInterfaceItem(item)
    }
    open override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        validateMenuItem(item)
    }

    /// the text layout/configuration method, including its final
    /// placeholder and typing-attribute refresh. This uses TextKit 2, as does
    /// the original lazy text-view constructor.
    public func configureTextView() {
        minSize = NSSize(width: 1, height: 1)
        maxSize = NSSize(width: 1_000_000, height: 1_000_000)
        textLayoutManager?.textContainer?.widthTracksTextView = false
        textLayoutManager?.textContainer?.heightTracksTextView = false
        textLayoutManager?.textContainer?.size = maxSize
        textLayoutManager?.textContainer?.maximumNumberOfLines = 1
        textLayoutManager?.textContainer?.lineFragmentPadding = 0
        drawsBackground = false
        focusRingType = .exterior
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticDataDetectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        contentType = nil
        isHorizontallyResizable = true
        isVerticallyResizable = true
        isFieldEditor = true
        isSelectable = true
        isEditable = true
        isRichText = false
        addSubview(makePlaceholderField())
        syncPlaceholderFont()
    }
}
