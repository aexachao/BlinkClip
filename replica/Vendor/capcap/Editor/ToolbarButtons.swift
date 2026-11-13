import AppKit

/// One square toolbar button.
///
/// It draws its own rounded hover/selected background (through
/// `ToolbarChrome`) instead of using a bezel, which is what lets the grouped
/// dropdown rows share exactly the same highlight. Hover is tracked with an
/// `NSTrackingArea`, re-derived from the pointer whenever the area is
/// reinstalled, and never shown while the button is disabled.
class ToolButton: NSButton, ToolbarHoverable {
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    /// Text shown by the dark hover tooltip. nil = no tip.
    var hoverTip: String?

    /// The toolbar item this button triggers. Set at creation; a grouped
    /// button's inner button follows the group's selected member.
    var itemID: ToolbarItemID?

    private let normalColor: NSColor
    private let selectedColor: NSColor

    /// Pointer is over the button. Only ever `true` for an enabled button in
    /// the key window, so a disabled control never lights up.
    private var isHovered = false {
        didSet { if oldValue != isHovered { needsDisplay = true } }
    }

    /// Whether the hover fill is currently painted. Exposed so the native
    /// harness can assert the key-window rule without reading pixels.
    var isHoverHighlighted: Bool { isHovered }

    var hoverTrackingArea: NSTrackingArea?

    init(frame: NSRect, symbolName: String, normalColor: NSColor, selectedColor: NSColor, symbolPointSize: CGFloat = 14, iconImage: NSImage? = nil) {
        self.normalColor = normalColor
        self.selectedColor = selectedColor
        super.init(frame: frame)

        bezelStyle = .regularSquare
        isBordered = false
        setButtonType(.momentaryPushIn)

        if let iconImage {
            image = iconImage
        } else if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
            // Keep the text tool's Aa glyph independent of the system language.
            let localizedImage = symbolName == "textformat" ? img.withLocale(Locale(identifier: "en")) : img
            image = localizedImage.withSymbolConfiguration(config)
        }

        contentTintColor = normalColor
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var isEnabled: Bool {
        didSet {
            // A button that becomes disabled under the pointer drops the
            // highlight immediately (undo runs out of history mid-hover).
            if !isEnabled { setHovered(false) }
        }
    }

    func setHovered(_ hovered: Bool) {
        let allowed = hovered && isEnabled && (window?.isKeyWindow ?? true)
        guard allowed != isHovered else { return }
        isHovered = allowed
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshHoverTrackingArea(&hoverTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovered(true)
        guard let tip = hoverTip, let window else { return }
        let frameInWindow = convert(bounds, to: nil)
        let frameOnScreen = window.convertToScreen(frameInWindow)
        ToolTipWindow.show(text: tip, anchor: frameOnScreen)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(false)
        ToolTipWindow.hide()
    }

    override func mouseDown(with event: NSEvent) {
        ToolTipWindow.hide()
        super.mouseDown(with: event)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            ToolTipWindow.hide()
            setHovered(false)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Hover/selected fills are adaptive; repaint on light/dark switches.
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            contentTintColor = selectedColor
            ToolbarChrome.drawSelectedBackground(in: bounds)
        } else {
            contentTintColor = normalColor
            ToolbarChrome.drawHoverBackground(in: bounds, hovered: isHovered, enabled: isEnabled)
        }
        // NSButtonCell lays out SF Symbols using their text alignment rect,
        // which excludes some ascenders/descenders. Its rendering can clip
        // those parts on a different backing scale. Draw the full symbol in
        // points and let NSImage rasterize for the current graphics context.
        guard let image else { return }
        let color = isSelected ? selectedColor : normalColor
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            color.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        let imageRect = NSRect(
            x: bounds.midX - image.size.width / 2,
            y: bounds.midY - image.size.height / 2,
            width: image.size.width,
            height: image.size.height
        )
        tinted.draw(in: imageRect, from: .zero, operation: .sourceOver,
                    fraction: !isEnabled ? 0.5 : (isHighlighted ? 0.65 : 1),
                    respectFlipped: true, hints: nil)
    }
}

/// The chevron half of a grouped toolbar button. It is a real button — it
/// opens the group's dropdown — and it carries the same hover treatment as the
/// tool half, so both halves of a group button answer the pointer alike.
final class ToolbarChevronButton: NSButton, ToolbarHoverable {
    private let chevronImage: NSImage?
    private var isHovered = false {
        didSet { if oldValue != isHovered { needsDisplay = true } }
    }

    var hoverTrackingArea: NSTrackingArea?

    init(frame: NSRect, symbolPointSize: CGFloat = 9) {
        chevronImage = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold))
        super.init(frame: frame)
        bezelStyle = .regularSquare
        isBordered = false
        setButtonType(.momentaryPushIn)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setHovered(_ hovered: Bool) {
        let allowed = hovered && isEnabled && (window?.isKeyWindow ?? true)
        guard allowed != isHovered else { return }
        isHovered = allowed
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshHoverTrackingArea(&hoverTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setHovered(false) }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        ToolbarChrome.drawHoverBackground(in: bounds, hovered: isHovered, enabled: isEnabled)
        guard let chevronImage else { return }
        // Secondary when resting, full label colour while hovered: the same
        // step up in emphasis the tool half gets from its hover fill.
        let tint = isHovered ? NSColor.labelColor : NSColor.secondaryLabelColor
        let tinted = NSImage(size: chevronImage.size, flipped: false) { rect in
            chevronImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            tint.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        let imageRect = NSRect(
            x: bounds.midX - chevronImage.size.width / 2,
            y: bounds.midY - chevronImage.size.height / 2,
            width: chevronImage.size.width,
            height: chevronImage.size.height
        )
        tinted.draw(in: imageRect, from: .zero, operation: .sourceOver,
                    fraction: isEnabled ? 1 : 0.5, respectFlipped: true, hints: nil)
    }
}
