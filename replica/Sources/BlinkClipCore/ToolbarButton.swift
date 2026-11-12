import AppKit

@MainActor
public enum ToolbarAppearance {
    private static let secondary: NSColor = {
        let light = NSColor.black.withAlphaComponent(0.5)
        let dark = NSColor.white.withAlphaComponent(0.55)
        return NSColor(name: nil) { SearchAppearance.appearanceColor(appearance: $0, dark: dark, light: light) }
    }()
    private static let border: NSColor = {
        let light = NSColor.black.withAlphaComponent(0.05)
        let dark = NSColor.white.withAlphaComponent(0.05)
        return NSColor(name: nil) { SearchAppearance.appearanceColor(appearance: $0, dark: dark, light: light) }
    }()
    private static let label = NSColor.labelColor
    private static let secondaryLabel = NSColor.secondaryLabelColor
    public static func secondaryForeground() -> NSColor { secondary }
    public static func borderAndHover() -> NSColor { border }
    public static func labelForeground() -> NSColor { label }
    public static func secondaryLabelForeground() -> NSColor { secondaryLabel }
}

/// The recovered layered NSButton, used by the preview's native editing controls.
@MainActor
public final class ToolbarButton: NSButton {
    public enum Size: UInt8 { case normal = 0, large = 1 }
    public var symbol: String? { didSet { updateIcon() } }
    public var hasPullDownArrow = false { didSet { updateIcon() } }
    public var isPrimary = false { didSet { updateLayerAppearance() } }
    public var isSelected = false { didSet { updateLayerAppearance() } }
    public let size: Size
    public var buttonAction: (ToolbarButton) -> Void
    private var isHovered = false
    private var isPressed = false
    private var storedIconView: NSImageView?
    private var storedTitleLabel: NSTextField?
    private var recoveredTrackingArea: NSTrackingArea?
    private let pullDownArrowView: NSImageView
    private let stackView: NSStackView

    public init(symbol: String? = nil, title: String = "", size: Size = .normal,
                shortcut: ShortcutValue? = nil,
                toolTip: String? = nil, action: @escaping (ToolbarButton) -> Void) {
        self.symbol = symbol
        self.size = size
        buttonAction = action
        pullDownArrowView = NSImageView(image: Self.requiredImage("chevron.down"))
        pullDownArrowView.contentTintColor = SearchAppearance.foregroundColor()
        stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.spacing = 4
        stackView.distribution = .fillProportionally
        stackView.alignment = .centerY
        super.init(frame: .zero)
        super.title = title
        updateIcon()
        isTransparent = true
        wantsLayer = true
        target = self
        self.action = #selector(performAction)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate(sizeConstraints())
        if let shortcut {
            keyEquivalent = ShortcutFunctions.keyEquivalentLabel(keyCode: shortcut.keyCode)
            keyEquivalentModifierMask = .init(rawValue: shortcut.internalModifiers)
        }
        if let toolTip {
            self.toolTip = shortcut.map { toolTip + " (" + $0.description + ")" } ?? toolTip
        }
        updateIcon()
        updateLayerAppearance()
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func requiredImage(_ symbol: String) -> NSImage {
        if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil {
            return NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)!
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)!
    }

    public func makeIconView() -> NSImageView {
        if let storedIconView { return storedIconView }
        let view = NSImageView()
        storedIconView = view
        return view
    }

    public func makeTitleLabelField() -> NSTextField {
        if let storedTitleLabel { return storedTitleLabel }
        let view = NSTextField(labelWithString: "")
        view.font = NSFont.preferredFont(forTextStyle: size == .normal ? .body : .title3, options: [:])
        view.alignment = .right
        storedTitleLabel = view
        return view
    }

    public override var contentTintColor: NSColor? {
        get { super.contentTintColor }
        set {
            super.contentTintColor = newValue
            makeIconView().contentTintColor = super.contentTintColor
        }
    }

    public override var title: String {
        get { super.title }
        set { super.title = newValue; updateIcon() }
    }

    public override var isEnabled: Bool {
        get { super.isEnabled }
        set { super.isEnabled = newValue; updateLayerAppearance() }
    }

    public func updateIcon() {
        let icon = makeIconView()
        if let symbol {
            icon.image = Self.requiredImage(symbol).withSymbolConfiguration(
                NSImage.SymbolConfiguration(textStyle: size == .normal ? .body : .title2))
            stackView.addArrangedSubview(icon)
        } else {
            icon.image = nil
            icon.removeFromSuperview()
        }
        let label = makeTitleLabelField()
        if super.title.isEmpty {
            label.stringValue = ""
            label.removeFromSuperview()
        } else {
            label.stringValue = super.title
            stackView.addArrangedSubview(label)
        }
        if hasPullDownArrow { stackView.addArrangedSubview(pullDownArrowView) }
        else { pullDownArrowView.removeFromSuperview() }
    }

    public func stackViewConstraints(padding: CGFloat) -> [NSLayoutConstraint] {
        [stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
         stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding)]
    }

    public func sizeConstraints() -> [NSLayoutConstraint] {
        var result: [NSLayoutConstraint]
        if size == .large {
            result = [widthAnchor.constraint(equalToConstant: 32), heightAnchor.constraint(equalToConstant: 32)]
        } else {
            result = [heightAnchor.constraint(equalToConstant: 22), widthAnchor.constraint(greaterThanOrEqualToConstant: 32)]
        }
        result += stackViewConstraints(padding: size == .large ? 0 : 8)
        result += [stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
                   pullDownArrowView.widthAnchor.constraint(equalToConstant: 8),
                   pullDownArrowView.heightAnchor.constraint(equalToConstant: 8)]
        return result
    }

    public func updateLayerAppearance() {
        layer?.borderWidth = super.title.isEmpty ? 0 : 1
        if #available(macOS 26, *) { layer?.cornerRadius = bounds.height * 0.5 }
        else { layer?.cornerRadius = size == .normal ? 5 : 6 }
        effectiveAppearance.performAsCurrentDrawingAppearance { self.updateBackground() }
    }

    private func applyForeground(_ color: NSColor) {
        makeTitleLabelField().textColor = color
        pullDownArrowView.contentTintColor = color
        makeIconView().contentTintColor = super.contentTintColor ?? color
    }

    public func updateBackground() {
        if isPrimary {
            let effect: NSColor.SystemEffect = !super.isEnabled ? .disabled : (isPressed ? .pressed : .none)
            layer?.backgroundColor = NSColor.controlAccentColor.withSystemEffect(effect).cgColor
            applyForeground(NSColor.white.withSystemEffect(effect))
            return
        }
        layer?.backgroundColor = NSColor.clear.cgColor
        let base: NSColor
        if #available(macOS 26, *) { base = SearchAppearance.foregroundColor()! }
        else { base = ToolbarAppearance.secondaryForeground() }
        applyForeground(base)
        layer?.borderColor = super.title.isEmpty ? nil : ToolbarAppearance.borderAndHover().cgColor
        if !super.isEnabled {
            applyForeground(ToolbarAppearance.secondaryLabelForeground().withSystemEffect(.disabled))
        } else if isPressed {
            layer?.backgroundColor = SearchSurfaceAppearance.borderColorSlot().pointee?.withAlphaComponent(0.15).cgColor
            applyForeground(isSelected ? ToolbarAppearance.secondaryLabelForeground() : ToolbarAppearance.labelForeground())
        } else if isSelected {
            layer?.backgroundColor = SearchSurfaceAppearance.borderColorSlot().pointee?.cgColor
            applyForeground(ToolbarAppearance.labelForeground())
        } else if isHovered {
            layer?.backgroundColor = ToolbarAppearance.borderAndHover().cgColor
        }
    }

    public override func updateLayer() { updateLayerAppearance() }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let recoveredTrackingArea { removeTrackingArea(recoveredTrackingArea) }
        let area = NSTrackingArea(rect: bounds, options: .init(rawValue: 0x481), owner: self, userInfo: nil)
        recoveredTrackingArea = area
        addTrackingArea(area)
        isHovered = NSEvent.pressedMouseButtons == 0 && bounds.contains(convert(NSEvent.mouseLocation, from: nil))
        updateLayerAppearance()
        isPressed = false
        updateLayerAppearance()
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovered = true
        updateLayerAppearance()
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovered = false
        updateLayerAppearance()
        isPressed = false
        updateLayerAppearance()
    }

    public override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateLayerAppearance()
        super.mouseDown(with: event)
        isPressed = false
        updateLayerAppearance()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerAppearance()
    }

    @objc public func performAction() { buttonAction(self) }
}
