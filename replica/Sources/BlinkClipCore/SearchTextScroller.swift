import AppKit

@MainActor
public final class SearchTextScroller: NSScrollView {
    public var focusRingBounds: NSRect = .zero

    /// Dedicated document-view initializer.
    public init(textView: SearchTextView) {
        super.init(frame: .zero)
        hasHorizontalScroller = false
        hasVerticalScroller = false
        drawsBackground = false
        focusRingType = .exterior
        borderType = .noBorder
        documentView = textView
        textView.configureTextView()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable for SearchTextScroller")
    }

    public override init(frame frameRect: NSRect) {
        fatalError("init(frame:) is unavailable for SearchTextScroller")
    }

    public func currentFocusRingBounds() -> NSRect { focusRingBounds }
    public override var focusRingMaskBounds: NSRect { currentFocusRingBounds() }

    public func drawFocusRing() {
        let radius: CGFloat
        if #available(macOS 26, *) { radius = focusRingBounds.height * 0.5 }
        else { radius = 6 }
        let path = NSBezierPath(roundedRect: focusRingBounds, xRadius: radius, yRadius: radius)
        NSColor.black.set()
        path.fill()
    }

    public func redrawFocusRing() {
        SearchTextView.performOnContext(self) { $0.drawFocusRing() }
    }
    public override func drawFocusRingMask() { redrawFocusRing() }
}
