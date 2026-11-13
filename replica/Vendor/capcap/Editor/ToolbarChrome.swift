import AppKit

/// Green used for the selected / active toolbar state. Shared by the bar, the
/// grouped-tool dropdown rows and the shortcut list, so "selected" reads the
/// same everywhere.
let accentGreen = NSColor(red: 0, green: 212.0 / 255.0, blue: 106.0 / 255.0, alpha: 1.0)

/// Geometry and drawing shared by the editor toolbar and the grouped-tool
/// dropdown panel. Both surfaces draw through these helpers, so the dropdown
/// cannot drift away from the bar's own material, radius and highlight rules.
///
/// Every colour comes from `AdaptiveChrome`, which resolves per appearance:
/// no literal RGB that would only read in one of light/dark.
enum ToolbarChrome {
    /// Height of one toolbar button — also the height of a dropdown row.
    static let rowHeight: CGFloat = 40
    /// Symbol size used by toolbar buttons and dropdown rows.
    static let symbolPointSize: CGFloat = 18
    /// Corner radius of the bar's own capsule surface.
    static let surfaceCornerRadius: CGFloat = 8
    /// Inset of the bar's surface inside its bounds.
    static let surfaceInset: CGFloat = 2
    /// Padding around the bar's button run, reused as the dropdown's outer
    /// padding so the two surfaces keep the same rhythm.
    static let surfacePadding: CGFloat = 6
    /// Corner radius of a button highlight (hover and selected alike).
    static let highlightCornerRadius: CGFloat = 6
    /// Inset of a button highlight inside its button.
    static let highlightInset: CGFloat = 2
    /// Gap between the bar and its dropdown panel.
    static let dropdownGap: CGFloat = 6

    // MARK: - Surfaces

    /// The bar's own material. The dropdown reuses it so it reads as an
    /// extension of the toolbar rather than a system menu.
    static var surfaceFill: NSColor { AdaptiveChrome.toolbarBackground }
    static var surfaceBorder: NSColor { AdaptiveChrome.border }

    static func surfacePath(in bounds: NSRect) -> NSBezierPath {
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: surfaceInset, dy: surfaceInset),
            xRadius: surfaceCornerRadius,
            yRadius: surfaceCornerRadius
        )
    }

    static func highlightPath(in bounds: NSRect) -> NSBezierPath {
        NSBezierPath(
            roundedRect: bounds.insetBy(dx: highlightInset, dy: highlightInset),
            xRadius: highlightCornerRadius,
            yRadius: highlightCornerRadius
        )
    }

    /// Paints a toolbar-style surface (used by the bar and by the dropdown
    /// panel). Layer-free so it renders the same on screen and offscreen.
    static func drawSurface(in bounds: NSRect, bordered: Bool = false) {
        let path = surfacePath(in: bounds)
        surfaceFill.setFill()
        path.fill()
        guard bordered else { return }
        surfaceBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    // MARK: - Hover

    /// Resting hover fill. Deliberately weaker than `AdaptiveChrome.selectedFill`
    /// so a hovered button never looks selected, and adaptive so both
    /// appearances stay readable.
    static var hoverFill: NSColor { AdaptiveChrome.subtleFill }

    /// Draws one clickable control's hover background. A disabled control
    /// draws nothing: greyed-out undo (empty stack) or upload (no provider)
    /// must not light up under the pointer.
    static func drawHoverBackground(in bounds: NSRect, hovered: Bool, enabled: Bool = true) {
        guard hovered, enabled else { return }
        hoverFill.setFill()
        highlightPath(in: bounds).fill()
    }

    /// Draws the selected / active background under a control. Same radius and
    /// inset as the hover fill, one step stronger.
    static func drawSelectedBackground(in bounds: NSRect) {
        AdaptiveChrome.selectedFill.setFill()
        highlightPath(in: bounds).fill()
    }
}

/// A control that paints a hover highlight. The bar drives these when it moves
/// or reflows under a stationary pointer, where AppKit does not deliver the
/// matching `mouseExited` — the usual cause of a highlight that "sticks" after
/// the pointer flew across the bar.
protocol ToolbarHoverable: AnyObject {
    func setHovered(_ hovered: Bool)
    func resyncHoverWithPointer()
    /// Whether the highlight is limited to the key window. Bar controls live
    /// in the editor's key window, so they are; the group dropdown is a
    /// deliberately non-activating panel (`canBecomeKey == false`), where
    /// `.activeInKeyWindow` tracking never fires and rows would never
    /// highlight.
    var hoverRequiresKeyWindow: Bool { get }
}

extension ToolbarHoverable where Self: NSView {
    /// Toolbar controls only light up in the key window: a floating bar over
    /// another app's window must not look interactive.
    var hoverRequiresKeyWindow: Bool { true }

    /// Installs (or reinstalls) the hover tracking area. `updateTrackingAreas`
    /// runs whenever the view's geometry changes; `.inVisibleRect` keeps the
    /// rect tied to the visible portion, and reinstalling re-derives the state
    /// from the pointer instead of trusting the last event. Controls that live
    /// in a never-key panel (the dropdown rows) track with `.activeAlways`, so
    /// `mouseEntered`/`mouseExited` arrive even though their window is not key.
    func refreshHoverTrackingArea(_ storage: inout NSTrackingArea?) {
        if let existing = storage {
            removeTrackingArea(existing)
        }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .inVisibleRect]
        options.insert(hoverRequiresKeyWindow ? .activeInKeyWindow : .activeAlways)
        let area = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        storage = area
        resyncHoverWithPointer()
    }

    /// Derives the hover state from where the pointer actually is now.
    func resyncHoverWithPointer() {
        guard let window else {
            setHovered(false)
            return
        }
        if hoverRequiresKeyWindow, !window.isKeyWindow {
            setHovered(false)
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(point))
    }
}
