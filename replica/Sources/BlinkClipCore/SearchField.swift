import AppKit
import QuartzCore

@MainActor
open class SearchField: LayerBackedView {
    public var onShowFilters: ((NSButton) -> Void)?
    public var onClear: ((Bool) -> Void)?
    public var onUndo: (() -> Bool)?
    public var onRedo: (() -> Bool)?
    public var canAcceptFocus = true
    public private(set) var editingDelegate: SearchEditing?
    private var storedIcon: NSImageView?
    private var storedInput: SearchInputView?
    private var storedFiltersButton: NSButton?

    open func makeInputView() -> SearchInputView { SearchInputView(frame: .zero) }

    public func makeInput() -> SearchInputView {
        if let storedInput { return storedInput }
        let input = makeInputView()
        let editing = SearchEditing(textView: input.cachedTextView())
        input.cachedTextView().delegate = editing
        editingDelegate = editing
        input.onClear = { [weak self] in self?.notifyClear() }
        storedInput = input
        return input
    }

    public func makeIconImageView() -> NSImageView {
        if let storedIcon { return storedIcon }
        let style: NSFont.TextStyle
        if #available(macOS 26, *) { style = .body } else { style = .title2 }
        let configuration = NSImage.SymbolConfiguration(textStyle: style)
        let image = Self.systemImage("magnifyingglass")
        let icon = NSImageView(image: image.withSymbolConfiguration(configuration) ?? image)
        storedIcon = icon
        return icon
    }

    private static func systemImage(_ name: String) -> NSImage {
        if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)!
        }
        return NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)!
    }

    public func makeFiltersButton() -> NSButton {
        if let storedFiltersButton { return storedFiltersButton }
        let button = NSButton()
        configureFiltersButton(button)
        storedFiltersButton = button
        return button
    }

    public func configureFiltersButton(_ button: NSButton) {
        button.image = Self.systemImage("line.3.horizontal.decrease")
        button.action = #selector(didClickFiltersButton)
        button.target = self
        button.refusesFirstResponder = true
        button.isBordered = false
        button.wantsLayer = true
        let shortcut = KeyboardShortcut(keyCode: ShortcutFunctions.keyCodeForKey("f"),
                                       modifierRawValue: NSEvent.ModifierFlags.command.rawValue)
        button.toolTip = Self.filtersTitle() + " (" + shortcut.displayName + ")"
    }

    private static func filtersTitle() -> String {
        let values = ["cs": "Filtry", "da": "Filtre", "de": "Filter", "en": "Filters",
            "es": "Filtros", "fr": "Filtres", "he": "מסננים", "it": "Filtri",
            "ja": "フィルター", "ko": "필터", "nl": "Filters", "pl": "Filtry",
            "pt-BR": "Filtros", "pt-PT": "Filtros", "ru": "Фильтры",
            "zh-Hans": "筛选", "zh-Hant": "篩選"]
        let language = Bundle.preferredLocalizations(from: ["en"] + values.keys.filter { $0 != "en" }.sorted(),
            forPreferences: [Locale.current.identifier]).first ?? "en"
        return values[language] ?? "Filters"
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backgroundColor = SearchSurfaceAppearance.borderColorSlot().pointee
        for view in [makeIconImageView(), makeInput(), makeFiltersButton()] as [NSView] {
            addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate(subviewConstraints().flatMap { $0 })
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func subviewConstraints() -> [[NSLayoutConstraint]] {
        let icon = makeIconImageView()
        let input = makeInput()
        let filters = makeFiltersButton()
        return [
            [icon.centerYAnchor.constraint(equalTo: centerYAnchor)],
            [icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)],
            [input.centerYAnchor.constraint(equalTo: centerYAnchor)],
            [input.heightAnchor.constraint(equalToConstant: 20)],
            [input.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4)],
            [filters.topAnchor.constraint(equalTo: topAnchor), filters.bottomAnchor.constraint(equalTo: bottomAnchor)],
            [filters.leadingAnchor.constraint(equalTo: input.trailingAnchor, constant: 4)],
            [filters.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)]
        ]
    }

    public func notifyClear() { onClear?(false) }

    public func showFilters() {
        if let onShowFilters { onShowFilters(makeFiltersButton()) }
    }
    @objc public func didClickFiltersButton() { showFilters() }

    public func updateLayout() {
        super.layout()
        let input = makeInput()
        input.focusRingBounds = convert(bounds, to: input)
        input.makeScroller().focusRingBounds = input.focusRingBounds
        let radius: CGFloat
        if #available(macOS 26, *) { radius = bounds.height * 0.5 } else { radius = 6 }
        ViewLayerFunctions.setCornerRadius(radius, curve: .circular, view: self)
    }

    public func refreshLayout() { updateLayout() }
    open override func layout() { refreshLayout() }

    public func forwardMouseEvent(_ event: NSEvent) {
        if let window { window.makeFirstResponder(makeInput().cachedTextView()) }
        let textView = makeInput().cachedTextView()
        let point = textView.convert(event.locationInWindow, from: nil)
        guard let manager = textView.textLayoutManager,
              let fragment = manager.textLayoutFragment(for: point),
              let line = fragment.textLineFragments.first else { return }
        let inFragment = NSPoint(x: point.x - fragment.layoutFragmentFrame.origin.x,
                                y: point.y - fragment.layoutFragmentFrame.origin.y - line.typographicBounds.origin.y)
        let index = line.characterIndex(for: inFragment)
        let offset = manager.offset(from: manager.documentRange.location, to: fragment.rangeInElement.location)
        textView.setSelectedRange(NSRange(location: offset + index, length: 1))
    }

    public func focusInput(_ event: NSEvent) {
        if let window { window.makeFirstResponder(makeInput().cachedTextView()) }
    }
    open override func mouseDown(with event: NSEvent) { focusInput(event) }

    public func makeFilterStack(title: String, image: NSImage?) -> NSStackView {
        let filter = SearchFilterView(title: title, image: image) { [weak self] event in
            Self.handleFilterEvent(event, field: self)
        }
        let stack = NSStackView(views: [filter])
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 4)
        return stack
    }

    @discardableResult
    public static func handleFilterEvent(_ event: NSEvent, field: SearchField?) -> Int {
        field?.forwardMouseEvent(event)
        return 0
    }

    public func isUndoRedoShortcut(_ event: NSEvent) -> Bool {
        let responder = window?.firstResponder
        let textView = makeInput().cachedTextView()
        if let responder, responder.isEqual(textView) {
            let shortcut = ShortcutFunctions.shortcutForEvent(event)
            let undoKey = ShortcutFunctions.keyCodeForKey("z")
            if shortcut.keyCode == undoKey, shortcut.modifierRawValue == 0x100000 {
                return onUndo?() ?? false
            }
            let redoKey = ShortcutFunctions.keyCodeForKey("z")
            if shortcut.keyCode == redoKey, shortcut.modifierRawValue == 0x120000 {
                return onRedo?() ?? false
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    public func isUndoRedoKeyEvent(_ event: NSEvent) -> Bool { isUndoRedoShortcut(event) }
    open override func performKeyEquivalent(with event: NSEvent) -> Bool { isUndoRedoKeyEvent(event) }
}
