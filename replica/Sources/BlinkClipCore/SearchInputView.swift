import AppKit

@MainActor
open class SearchInputView: NSView, NSTextStorageDelegate {
    public var onClear: (() -> Void)?
    public var focusRingBounds: NSRect = .zero
    public private(set) var isClearButtonVisible = false
    private var storedTextView: SearchTextView?
    private var storedScroller: SearchTextScroller?
    private var storedClearButton: NSButton?

    open func makeTextView() -> SearchTextView {
        SearchTextView(usingTextLayoutManager: true)
    }

    public func cachedTextView() -> SearchTextView {
        if let storedTextView { return storedTextView }
        let textView = makeTextView()
        storedTextView = textView
        return textView
    }

    public func makeScroller() -> SearchTextScroller {
        if let storedScroller { return storedScroller }
        let scroll = SearchTextScroller(textView: cachedTextView())
        storedScroller = scroll
        return scroll
    }

    public func makeClearButton() -> NSButton {
        if let storedClearButton { return storedClearButton }
        let button = NSButton()
        configureClearButton(button)
        storedClearButton = button
        return button
    }

    public func configureClearButton(_ button: NSButton) {
        // Preserve the original availability probe followed by a second load.
        let image: NSImage
        if NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil) != nil {
            image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)!
        } else {
            image = NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)!
        }
        button.image = image
        button.action = #selector(clear)
        button.target = self
        button.refusesFirstResponder = true
        button.isBordered = false
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [makeScroller(), makeClearButton()] as [NSView] {
            addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate(subviewConstraints().flatMap { $0 })
        cachedTextView().textStorage?.delegate = self
        let button = makeClearButton()
        button.isEnabled = false
        button.isHidden = true
        button.alphaValue = 0
        refreshInputState()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func subviewConstraints() -> [[NSLayoutConstraint]] {
        let scroll = makeScroller()
        let clear = makeClearButton()
        return [
            [scroll.topAnchor.constraint(equalTo: topAnchor)],
            [scroll.leadingAnchor.constraint(equalTo: leadingAnchor)],
            [scroll.bottomAnchor.constraint(equalTo: bottomAnchor)],
            [clear.widthAnchor.constraint(equalToConstant: 16),
             clear.heightAnchor.constraint(equalToConstant: 16)],
            [clear.centerYAnchor.constraint(equalTo: centerYAnchor)],
            [clear.leadingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: 4)],
            [clear.trailingAnchor.constraint(equalTo: trailingAnchor)]
        ]
    }

    public func clearInput() {
        if let window { window.makeFirstResponder(cachedTextView()) }
        onClear?()
    }

    public func clearSearchInput() {
        SearchTextView.performOnContext(self) { $0.clearInput() }
    }
    @objc public func clear() { clearSearchInput() }

    @discardableResult
    public func showClearButton() -> Int {
        makeClearButton().animator().alphaValue = 1
        return 0
    }

    @discardableResult
    public func hideClearButton() -> Int {
        makeClearButton().animator().alphaValue = 0
        return 0
    }

    @discardableResult
    public static func hideClearButtonIfNeeded(_ input: SearchInputView?) -> Int {
        if let input, !input.isClearButtonVisible { input.makeClearButton().isHidden = true }
        return 0
    }

    public func updateClearButtonVisibility() {
        let visible = !cachedTextView().string.isEmpty
        guard isClearButtonVisible != visible else { return }
        isClearButtonVisible = visible
        makeClearButton().isEnabled = visible
        if visible {
            makeClearButton().isHidden = false
            ViewAnimation.runAnimation(duration: 0.12,
                timingFunction: ViewAnimation.easeOutTimingFunction(), animated: true) {
                _ = self.showClearButton()
            }
        } else {
            ViewAnimation.runAnimation(duration: 0.12,
                timingFunction: ViewAnimation.easeOutTimingFunction(), animated: true) {
                _ = self.hideClearButton()
            } completion: { [weak self] in
                _ = Self.hideClearButtonIfNeeded(self)
            }
        }
    }

    public func refreshInputState() {
        updateClearButtonVisibility()
        let textView = cachedTextView()
        textView.makePlaceholderField().isHidden = !textView.string.isEmpty
        let hasAttachments = textView.textStorage?.containsAttachments ?? false
        textView.textContainerInset = NSSize(width: 0, height: hasAttachments ? 0 : 2)
    }

    public func updateInputState() { refreshInputState() }
    nonisolated public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                            range editedRange: NSRange, changeInLength delta: Int) {
        MainActor.assumeIsolated { updateInputState() }
    }
}
