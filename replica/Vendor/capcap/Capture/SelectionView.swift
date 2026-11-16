import AppKit
import QuartzCore

enum SelectionStartReason: Equatable {
    case newSelection
    case existingSelectionAdjustment
}

protocol SelectionViewDelegate: AnyObject {
    func selectionDidStart(reason: SelectionStartReason)
    func selectionDidHoverWindow(_ window: DetectedWindow?)
    /// - Parameter isWindowSelection: true when the rect came from clicking a
    ///   detected window (no drag), so the editor can apply window-only
    ///   effects like rounded corners. False for free-drag / resize / preset.
    /// - Parameter windowID: the WindowServer id for clicked-window captures.
    ///   nil for free-drag / resize / preset selections.
    func selectionDidComplete(rect: NSRect, inView view: NSView, isWindowSelection: Bool, windowID: CGWindowID?)
    func selectionDidChange(rect: NSRect, inView view: NSView)
    func selectionMaskDidDoubleClick(inView view: NSView)
    func selectionDidDoubleClickInsideSelection(inView view: NSView)
}

extension SelectionViewDelegate {
    func selectionDidHoverWindow(_ window: DetectedWindow?) {}
    func selectionDidChange(rect: NSRect, inView view: NSView) {}
    func selectionMaskDidDoubleClick(inView view: NSView) {}
    func selectionDidDoubleClickInsideSelection(inView view: NSView) {}
}

/// One axis of the pointer guide: a 2pt dark halo with a 1pt white core.
///
/// Both strands are layers, so following the pointer is a layer move rather
/// than a repaint of the overlay's full-screen snapshot. That is the whole
/// point of this type: `draw(_:)`-based lines only reach the screen after the
/// next display refresh (and after the snapshot has been re-composited), which
/// is exactly the lag the pointer guide must not have.
private final class CrosshairBandView: NSView {
    enum Axis {
        case horizontal
        case vertical
    }

    static let haloThickness: CGFloat = 2
    static let coreThickness: CGFloat = 1

    private let axis: Axis
    private let coreLayer = CALayer()
    private var placedRect: NSRect = .null

    init(axis: Axis) {
        self.axis = axis
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        layer?.backgroundColor = NSColor.black
            .withAlphaComponent(SelectionView.crosshairHaloAlpha).cgColor
        layer?.isOpaque = false
        layer?.masksToBounds = false
        // A guide is decoration: never a hit or cursor target.
        layer?.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull()
        ]
        coreLayer.backgroundColor = NSColor.white
            .withAlphaComponent(SelectionView.crosshairCoreAlpha).cgColor
        coreLayer.isOpaque = false
        coreLayer.masksToBounds = false
        coreLayer.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull()]
        layer?.addSublayer(coreLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Moves the band to `rect` (view coordinates) and re-states the core,
    /// writing only the layers whose geometry or visibility changed.
    func place(_ rect: NSRect, visible: Bool) {
        if isHidden != !visible {
            isHidden = !visible
        }
        guard visible else {
            placedRect = .null
            return
        }
        guard !rect.equalTo(placedRect) else { return }
        placedRect = rect
        frame = rect
        let core: NSRect
        switch axis {
        case .horizontal:
            core = NSRect(
                x: 0,
                y: (rect.height - Self.coreThickness) / 2,
                width: rect.width,
                height: Self.coreThickness
            )
        case .vertical:
            core = NSRect(
                x: (rect.width - Self.coreThickness) / 2,
                y: 0,
                width: Self.coreThickness,
                height: rect.height
            )
        }
        coreLayer.frame = core
    }
}

/// The pointer itself, drawn inside the overlay.
///
/// The WindowServer paints the hardware cursor at its own cadence; an AppKit
/// layer update for the guides therefore always lands one display frame later,
/// which reads as the guides chasing the pointer no matter how cheap the update
/// is. Drawing the pointer into the same overlay makes "pointer + guides" one
/// layer update, so their relative displacement is exactly zero at every speed.
/// That is only true while the system cursor is out of the way — the overlay
/// controller hides it for as long as this view is on screen and falls back to
/// guides-only when it cannot confirm the hide.
///
/// Shape: two 1pt white strands, 18pt across, over a 3pt dark outline, with a
/// 2pt hole at the crossing so the aimed pixel stays readable on both a light
/// and a dark desktop.
private final class CrosshairCursorView: NSView {
    /// Total length of one strand, gap included.
    static let strandLength: CGFloat = 18
    /// The strands stop this far short of the crossing (1pt on each side).
    static let centerGap: CGFloat = 2
    /// White core thickness.
    static let lineWidth: CGFloat = 1
    /// Dark outline thickness around the core (1pt either side).
    static let strokeWidth: CGFloat = 3

    private let outlineLayer = CAShapeLayer()
    private let coreLayer = CAShapeLayer()
    private var placedCentre: NSPoint?

    init() {
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: Self.strandLength,
            height: Self.strandLength
        ))
        wantsLayer = true
        isHidden = true
        layer?.isOpaque = false
        layer?.masksToBounds = false
        // A pointer is decoration: never a hit or cursor target, and a move
        // must not animate.
        layer?.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull()
        ]

        let centre = NSPoint(x: Self.strandLength / 2, y: Self.strandLength / 2)
        let half = Self.strandLength / 2
        let gap = Self.centerGap / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: centre.x - half, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x - gap, y: centre.y))
        path.move(to: CGPoint(x: centre.x + gap, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x + half, y: centre.y))
        path.move(to: CGPoint(x: centre.x, y: centre.y - half))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y - gap))
        path.move(to: CGPoint(x: centre.x, y: centre.y + gap))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + half))

        configure(
            outlineLayer,
            path: path,
            color: NSColor.black.withAlphaComponent(0.62),
            width: Self.strokeWidth
        )
        configure(
            coreLayer,
            path: path,
            color: NSColor.white.withAlphaComponent(0.95),
            width: Self.lineWidth
        )
        layer?.addSublayer(outlineLayer)
        layer?.addSublayer(coreLayer)
        updateContentsScale()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    /// Shape layers are rasterised at their contents scale, so a 1pt stroke
    /// stays one device pixel wide (two on a 2x display) instead of blurring.
    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard outlineLayer.contentsScale != scale else { return }
        outlineLayer.contentsScale = scale
        coreLayer.contentsScale = scale
    }

    private func configure(_ shape: CAShapeLayer, path: CGPath, color: NSColor, width: CGFloat) {
        shape.path = path
        shape.fillColor = nil
        shape.strokeColor = color.cgColor
        shape.lineWidth = width
        shape.lineCap = .butt
        shape.isOpaque = false
        shape.masksToBounds = false
        shape.frame = bounds
        shape.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "path": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull(),
            "contentsScale": NSNull()
        ]
    }

    /// Centres the pointer on `point` (view coordinates, already snapped to the
    /// device pixel grid by the caller) and hides it when not drawn.
    func place(centre point: NSPoint, visible: Bool) {
        guard visible else {
            if !isHidden { isHidden = true }
            placedCentre = nil
            return
        }
        if isHidden { isHidden = false }
        guard placedCentre != point else { return }
        placedCentre = point
        let half = Self.strandLength / 2
        frame = NSRect(
            x: point.x - half,
            y: point.y - half,
            width: Self.strandLength,
            height: Self.strandLength
        )
    }
}

class SelectionView: NSView {
    weak var delegate: SelectionViewDelegate?
    var onFirstDrawCompleted: (() -> Void)?
    var onFirstFramePresented: (() -> Void)?
    private var firstFrameDisplayLink: CADisplayLink?
    private var didReportFirstDraw = false
    private var didScheduleFirstFramePresentation = false

    // MARK: - State

    private enum State {
        case idle
        case drawing
        case selected
    }

    private enum DragAction {
        case none
        case drawNew
        case move
        case resize(HandlePosition)
    }

    enum HandlePosition: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        case topCenter, bottomCenter, leftCenter, rightCenter
    }

    private var state: State = .idle {
        didSet {
            if state != oldValue {
                // The guides are only shown while drawing; a committed frame
                // hides them without repainting anything.
                updateCrosshairLayers()
            }
        }
    }
    private var dragAction: DragAction = .none
    private var selectionOrigin: NSPoint = .zero
    private var selectionRect: NSRect?
    private var dragStart: NSPoint = .zero
    private var dragOriginalRect: NSRect = .zero

    // Whether annotation tools are active (pass mouse events through to canvas)
    var annotationToolActive = false

    /// A foreground claim would dismiss an open menu before its snapshot lands.
    var mayActivateAppForCursor = true

    // When true, clicking outside selection won't start a new selection
    var selectionLocked = false {
        didSet {
            if selectionLocked != oldValue {
                refreshCursorRects()
                updateCrosshairLayers()
            }
        }
    }

    // Scroll capture mode: update border styling while the controller manages event routing.
    var scrollCaptureActive = false {
        didSet {
            if scrollCaptureActive != oldValue {
                updateCrosshairLayers()
            }
        }
    }

    // When false, the selection frame becomes a fixed viewport.
    var selectionInteractionEnabled = true {
        didSet {
            if selectionInteractionEnabled != oldValue {
                refreshCursorRects()
                needsDisplay = true
                updateCrosshairLayers()
            }
        }
    }
    /// Optional bounds for moving/resizing an established selection. Image
    /// crop mode uses the original image frame so handles can reveal only
    /// pixels that actually exist, while normal screen capture continues to
    /// use the full overlay bounds.
    var selectionAdjustmentBounds: NSRect?
    var aspectRatio: CGFloat? = nil
    var selectionSizeLabelOverride: String? {
        didSet { needsDisplay = true }
    }

    // MARK: - Pre-captured Snapshot

    /// Full-screen snapshot taken before overlays appear, preserving transient menus/popups.
    var backgroundSnapshot: NSImage?

    /// Seeds the frozen desktop background from a CGImage produced by the
    /// off-main-thread pre-capture path.
    func setBackgroundSnapshot(cgImage: CGImage, pointSize: NSSize) {
        backgroundSnapshot = NSImage(cgImage: cgImage, size: pointSize)
        needsDisplay = true
    }

    func cancelFirstFramePresentationTracking() {
        firstFrameDisplayLink?.invalidate()
        firstFrameDisplayLink = nil
        onFirstDrawCompleted = nil
        onFirstFramePresented = nil
    }

    // MARK: - Window Detection

    /// Set by OverlayWindowController so the view can detect windows under the cursor.
    var windowDetector: WindowDetector?

    /// The window rect currently highlighted under the cursor (view coordinates).
    /// This is clipped to the overlay's visible bounds so the hover cutout
    /// stays drawable even when the real window extends off screen.
    private var hoverWindowRect: NSRect?
    /// The full detected window rect in view coordinates. This may extend
    /// outside `bounds`; use it for the actual clicked-window capture so the
    /// output keeps the real window dimensions.
    private var hoverWindowFullRect: NSRect?
    private var hoverWindowID: CGWindowID?

    /// Pending window selection — confirmed on mouseUp if no significant drag occurs.
    private var pendingWindowRect: NSRect?
    private var pendingWindowID: CGWindowID?
    private let windowClickThreshold: CGFloat = 4

    // MARK: - Crosshair

    /// Pointer position in screen (global) coordinates, or `nil` when the
    /// crosshair is hidden. Stored globally so every display's overlay draws
    /// the same crossing point at its own local coordinates — a pointer on one
    /// screen then continues the horizontal line across a side-by-side setup.
    private var crosshairScreenPoint: NSPoint?
    /// The same point in this view's coordinates. Cached because hiding the
    /// guides after the pointer has already moved on still needs it.
    private var crosshairLocalPoint: NSPoint?
    /// Set by `OverlayWindowController`: a pointer move seen by one display's
    /// overlay is mirrored to the overlays of every other display.
    var onCrosshairMoved: ((NSPoint) -> Void)?

    /// The guides live in their own view-backed layers (`CrosshairBandView`),
    /// not in the overlay's snapshot drawing. A pointer move then only moves a
    /// layer — the full-screen snapshot is never invalidated, so the lines
    /// cannot trail the pointer by the display refresh a `draw(_:)` line costs.
    private let crosshairHorizontal = CrosshairBandView(axis: .horizontal)
    private let crosshairVertical = CrosshairBandView(axis: .vertical)
    /// The pointer. It lives here, in the same layer tree as the guides, so the
    /// two are written in one `CATransaction` and therefore reach the screen in
    /// the same frame — there is no relative displacement to see, at any speed.
    private let crosshairCursor = CrosshairCursorView()

    /// Set by `OverlayWindowController` once the WindowServer confirmed that the
    /// system cursor is hidden. When the confirmation fails this stays false and
    /// the overlay draws the guides only, so the user never sees two pointers.
    var drawsPointerCursor = false {
        didSet {
            guard drawsPointerCursor != oldValue else { return }
            updateCrosshairLayers()
        }
    }

    /// True while this overlay is actually painting the pointer. Only state
    /// changes cross this callback — never pointer motion — so the controller
    /// can hide/show the system cursor without a per-event cost.
    var onPointerCursorDrawnChanged: ((Bool) -> Void)?
    private(set) var isDrawingPointerCursor = false

    // MARK: - Constants

    /// Capture chrome tint: the product accent (system blue), aliased to the one
    /// shared constant so the overlay, the editor's selection chrome and the
    /// magnifier lens cannot drift apart. The colour itself is defined once in
    /// `UI/SelectionAccent.swift`; there is no second literal here.
    private static let selectionTint: NSColor = selectionAccent
    private static let selectionTintCGColor: CGColor = selectionTint.cgColor
    /// Grabbable area around each handle. The drawn handle is a bar or an L
    /// bracket (see `drawHandles`), but the target is 22×22pt — at least the
    /// required 20×20 — so every point within ±10pt of a handle still grabs it.
    /// The editor's live-selection chrome (`SelectionChromeOverlay`) hits the
    /// same 22×22pt target by reading this value; there is no second number.
    static let handleHitSize: CGFloat = 22
    /// Edge handles: one 20pt bar, 4pt thick, 2pt rounded ends. Top/bottom
    /// edges get a horizontal bar, left/right edges a vertical one.
    static let handleBarLength: CGFloat = 20
    static let handleBarThickness: CGFloat = 4
    static let handleBarCornerRadius: CGFloat = 2
    /// Corner handles: an L of two 12pt arms, 2pt thick, drawn along the
    /// inside of the corner — no dots anywhere.
    static let handleCornerArmLength: CGFloat = 12
    static let handleCornerArmThickness: CGFloat = 2
    /// One visual weight for every overlay frame. 1pt is exactly 2 device
    /// pixels on a 2x display (1 pixel at 1x), so the idle hover frame, the
    /// box being dragged, a committed selection and the scroll-capture marker
    /// all read as the same line instead of 3pt vs 2pt.
    private let borderWidth: CGFloat = 1.0
    private let dimmingOverlayAlpha: CGFloat = 0.45
    /// Size label geometry: 10x6 content padding, 6pt radius, 8pt above the frame
    /// (6pt let the capsule crowd the top-left handle).
    private static let sizeLabelPadding = NSSize(width: 10, height: 6)
    private static let sizeLabelCornerRadius: CGFloat = 6
    private static let sizeLabelGap: CGFloat = 8
    /// Crosshair: a 1pt white hairline at 42% over a 2pt dark halo, so the lines
    /// read on both a light and a dark desktop without becoming harsh.
    fileprivate static let crosshairCoreAlpha: CGFloat = 0.42
    fileprivate static let crosshairHaloAlpha: CGFloat = 0.35

    // MARK: - Public

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installCrosshairBands()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installCrosshairBands()
    }

    /// Adds the two guide layers above everything the snapshot drawing puts on
    /// screen. They stay hidden until a pointer position is known. The pointer
    /// is added last so it sits on top of its own guides.
    private func installCrosshairBands() {
        for band in [crosshairHorizontal, crosshairVertical] {
            band.isHidden = true
            addSubview(band)
        }
        addSubview(crosshairCursor)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // The guides span the whole overlay, so a resize re-states their length.
        updateCrosshairLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateCrosshairLayers()
    }

    var currentSelectionRect: NSRect? { selectionRect }

    func refreshHoverAtCurrentMouseLocation() {
        guard state == .idle, !selectionLocked else { return }
        updateWindowHover(screenPoint: NSEvent.mouseLocation)
    }

    // MARK: - Crosshair

    /// Mirrors the pointer (screen coordinates) into this overlay and moves the
    /// two guide layers. No part of the frozen snapshot is redrawn, so this is
    /// cheap enough to run on every mouse event. `nil` hides the crosshair.
    func updateCrosshair(globalPoint: NSPoint?) {
        crosshairScreenPoint = globalPoint
        crosshairLocalPoint = globalPoint.flatMap(localPoint(forScreenPoint:))
        updateCrosshairLayers()
    }

    /// Hides the crosshair without touching the pointer bookkeeping used by
    /// the drag itself (mouse-exit on the display holding the pointer).
    private func hideCrosshair() {
        guard crosshairScreenPoint != nil || crosshairLocalPoint != nil else { return }
        crosshairScreenPoint = nil
        crosshairLocalPoint = nil
        updateCrosshairLayers()
    }

    private func localPoint(forScreenPoint point: NSPoint) -> NSPoint? {
        guard let window else { return nil }
        return convert(window.convertPoint(fromScreen: point), from: nil)
    }

    /// Positions the two guide layers and the self-drawn pointer. Each axis is
    /// written only when its geometry actually changes, all three writes happen
    /// inside one transaction with implicit animations disabled, and there is no
    /// second update path for the pointer: a move can never separate "cursor"
    /// from "guides", not even for one frame.
    private func updateCrosshairLayers() {
        let showsGuides = state == .idle || state == .drawing
        guard showsGuides,
              selectionInteractionEnabled,
              !scrollCaptureActive,
              !selectionLocked,
              let point = crosshairLocalPoint
        else {
            crosshairHorizontal.isHidden = true
            crosshairVertical.isHidden = true
            crosshairCursor.place(centre: .zero, visible: false)
            reportPointerCursorDrawn(false)
            return
        }

        // Snap the hairline centre to a device pixel edge: on a 2x display a
        // 1pt stroke then covers exactly two pixels instead of two blurred ones.
        let scale = window?.backingScaleFactor ?? 2
        let x = (point.x * scale).rounded() / scale
        let y = (point.y * scale).rounded() / scale
        let showsHorizontal = bounds.minY...bounds.maxY ~= y
        let showsVertical = bounds.minX...bounds.maxX ~= x
        // The pointer is only painted by the display it is standing on, so the
        // other screens' overlays keep nothing at the crossing point.
        let showsPointer = drawsPointerCursor && showsHorizontal && showsVertical
        let halo = CrosshairBandView.haloThickness

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // A pointer on one display continues the horizontal line onto its
        // neighbours, while the vertical line only lands on the pointer's own
        // display: each overlay only writes the axis that changed.
        let horizontalRect = showsHorizontal
            ? NSRect(x: bounds.minX, y: y - halo / 2, width: bounds.width, height: halo)
            : .zero
        let verticalRect = showsVertical
            ? NSRect(x: x - halo / 2, y: bounds.minY, width: halo, height: bounds.height)
            : .zero
        crosshairHorizontal.place(horizontalRect, visible: showsHorizontal)
        crosshairVertical.place(verticalRect, visible: showsVertical)
        // Same snapped point as the two guide centres: the pointer stands
        // exactly on its own crossing, in this frame.
        crosshairCursor.place(centre: NSPoint(x: x, y: y), visible: showsPointer)
        reportPointerCursorDrawn(showsPointer)
    }

    private func reportPointerCursorDrawn(_ drawn: Bool) {
        guard isDrawingPointerCursor != drawn else { return }
        isDrawingPointerCursor = drawn
        onPointerCursorDrawnChanged?(drawn)
    }

    /// Turns a local pointer position into a screen point and hands it to the
    /// overlay controller, which mirrors it to every display. Without a
    /// controller (e.g. a bare view in a harness) the lines still follow the
    /// pointer on this display.
    private func broadcastCrosshair(at point: NSPoint) {
        let screenPoint: NSPoint
        if let window {
            screenPoint = window.convertPoint(toScreen: convert(point, to: nil))
        } else {
            screenPoint = NSEvent.mouseLocation
        }
        if let onCrosshairMoved {
            onCrosshairMoved(screenPoint)
        } else {
            updateCrosshair(globalPoint: screenPoint)
        }
    }

    func updateSelectionRect(_ rect: NSRect) {
        selectionRect = rect
        state = .selected
        needsDisplay = true
        refreshCursorRects()
    }

    /// Translate the selection rect by `delta` from the supplied
    /// `originalRect` and notify the delegate. Used by the editor toolbar's
    /// drag-handle button — it captures the rect at mouseDown and forwards
    /// per-frame deltas while the user drags. Mirrors the clamping done by
    /// the in-rect `.move` gesture so the selection stays on screen.
    func moveByExternalDrag(deltaFromOriginal delta: CGSize, originalRect: NSRect) {
        var newRect = originalRect.offsetBy(dx: delta.width, dy: delta.height)
        newRect = clampedForMove(newRect)
        selectionRect = newRect
        state = .selected
        delegate?.selectionDidChange(rect: newRect, inView: self)
        needsDisplay = true
    }

    /// Mirror of `mouseUp`'s `.move` finalize: notify the delegate that the
    /// selection rect's final position is committed.
    func finalizeExternalDrag() {
        if let rect = selectionRect {
            delegate?.selectionDidComplete(rect: rect, inView: self, isWindowSelection: false, windowID: nil)
        }
    }

    /// Resize the selection rect using a handle drag driven by an overlay
    /// (e.g. `SelectionChromeOverlay`) rather than the SelectionView's own
    /// mouse handling. Mirrors `mouseDragged`'s `.resize` branch.
    func resizeByExternalDrag(handle: HandlePosition, originalRect: NSRect, currentPoint: NSPoint) {
        let newRect = SelectionView.resizedRect(
            from: originalRect,
            handle: handle,
            currentPoint: currentPoint,
            aspectRatio: aspectRatio,
            bounds: selectionAdjustmentBounds ?? bounds
        )
        selectionRect = newRect
        state = .selected
        delegate?.selectionDidChange(rect: newRect, inView: self)
        needsDisplay = true
    }

    /// Mirror of `mouseUp`'s `.resize` finalize.
    func finalizeExternalResize() {
        if let rect = selectionRect {
            delegate?.selectionDidComplete(rect: rect, inView: self, isWindowSelection: false, windowID: nil)
        }
    }

    // MARK: - Cursors

    /// Registers the initial crosshair and the selected frame's directional
    /// resize cursors. Explicit mouse-event updates below mirror these rects
    /// so drag events cannot fall back to the initial crosshair.
    /// OverlayWindowController activates capcap before invalidating cursor
    /// rects, because AppKit cursor ownership is scoped to the frontmost app.
    override func resetCursorRects() {
        super.resetCursorRects()
        if state == .idle, !selectionLocked {
            addCursorRect(bounds, cursor: .crosshair)
        } else if state == .selected,
                  selectionInteractionEnabled,
                  let rect = selectionRect {
            let positions = SelectionView.handlePositions(for: rect)
            for (index, handle) in HandlePosition.allCases.enumerated() {
                let position = positions[index]
                let cursorRect = NSRect(
                    x: position.x - Self.handleHitSize / 2,
                    y: position.y - Self.handleHitSize / 2,
                    width: Self.handleHitSize,
                    height: Self.handleHitSize
                ).intersection(bounds)
                if !cursorRect.isNull {
                    addCursorRect(
                        cursorRect,
                        cursor: SelectionView.cursorForHandle(handle)
                    )
                }
            }
        }
    }

    /// Tells WindowServer to re-evaluate cursor rects for this view.
    /// Call after state changes that affect which cursor should appear.
    func refreshCursorRects() {
        window?.invalidateCursorRects(for: self)
    }

    /// Gives an editor subview a single source of truth for the outer
    /// selection frame's resize handles. Editor views can receive tracking
    /// events while the pointer is still inside the selected canvas, so they
    /// must preserve this cursor instead of replacing it with their own.
    @discardableResult
    func setResizeCursorIfNeeded(at point: NSPoint, from sourceView: NSView) -> Bool {
        guard state == .selected,
              selectionInteractionEnabled,
              let rect = selectionRect
        else { return false }

        let localPoint = convert(point, from: sourceView)
        guard let handle = hitTestHandle(point: localPoint, rect: rect) else {
            return false
        }
        SelectionView.setCursorForHandle(handle)
        return true
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateCursor(at: point)
        if shouldConfirmFromSelectionDoubleClick(event: event, point: point) {
            dragAction = .none
            delegate?.selectionDidDoubleClickInsideSelection(inView: self)
            return
        }
        if shouldSuspendFromMaskDoubleClick(event: event, point: point) {
            dragAction = .none
            delegate?.selectionMaskDidDoubleClick(inView: self)
            return
        }

        guard selectionInteractionEnabled else {
            dragAction = .none
            return
        }

        // On a highlighted window: defer confirmation until mouseUp.
        // If the user drags past the threshold, fall through to free-form drawing.
        if state == .idle, let hoverRect = hoverWindowRect {
            pendingWindowRect = hoverWindowFullRect ?? hoverRect
            pendingWindowID = hoverWindowID
            hoverWindowRect = nil
            hoverWindowFullRect = nil
            hoverWindowID = nil
            selectionOrigin = point
            dragStart = point
            selectionRect = NSRect(origin: point, size: .zero)
            state = .drawing
            dragAction = .drawNew
            delegate?.selectionDidStart(reason: .newSelection)
            needsDisplay = true
            return
        }

        if let rect = selectionRect, state == .selected {
            // Check control points first
            if let handle = hitTestHandle(point: point, rect: rect) {
                dragAction = .resize(handle)
                dragStart = point
                dragOriginalRect = rect
                SelectionView.setCursorForHandle(handle)
                delegate?.selectionDidStart(reason: .existingSelectionAdjustment)
                return
            }
            // Check inside selection for move
            if rect.contains(point) {
                if annotationToolActive {
                    // Let canvas handle it
                    return
                }
                dragAction = .move
                dragStart = point
                dragOriginalRect = rect
                NSCursor.arrow.set()
                delegate?.selectionDidStart(reason: .existingSelectionAdjustment)
                return
            }
            // Click outside selection — if locked (editor active), ignore
            if selectionLocked {
                dragAction = .none
                return
            }
        }

        // Start drawing new selection
        selectionOrigin = point
        selectionRect = NSRect(origin: point, size: .zero)
        state = .drawing
        dragAction = .drawNew
        delegate?.selectionDidStart(reason: .newSelection)
        needsDisplay = true
    }

    private func shouldSuspendFromMaskDoubleClick(event: NSEvent, point: NSPoint) -> Bool {
        guard event.clickCount >= 2,
              state == .selected,
              selectionLocked,
              let rect = selectionRect
        else { return false }
        return !rect.contains(point)
    }

    private func shouldConfirmFromSelectionDoubleClick(event: NSEvent, point: NSPoint) -> Bool {
        guard event.clickCount >= 2,
              state == .selected,
              selectionLocked,
              selectionInteractionEnabled,
              let rect = selectionRect
        else { return false }
        return rect.contains(point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard selectionInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        // Keep the guides glued to the pointer while the frame is being drawn.
        broadcastCrosshair(at: point)

        switch dragAction {
        case .drawNew:
            NSCursor.crosshair.set()
            // If still within click threshold, keep the pending window rect alive
            if pendingWindowRect != nil {
                let dx = abs(point.x - dragStart.x)
                let dy = abs(point.y - dragStart.y)
                if dx < windowClickThreshold && dy < windowClickThreshold {
                    return  // no visual update yet — wait for more movement or mouseUp
                }
                // Drag exceeded threshold → discard window snap, proceed with free draw
                pendingWindowRect = nil
                pendingWindowID = nil
            }
            selectionRect = SelectionView.dragRect(
                from: selectionOrigin,
                to: point,
                aspectRatio: aspectRatio,
                bounds: bounds
            )
            needsDisplay = true

        case .move:
            NSCursor.arrow.set()
            guard let _ = selectionRect else { return }
            let dx = point.x - dragStart.x
            let dy = point.y - dragStart.y
            var newRect = dragOriginalRect.offsetBy(dx: dx, dy: dy)
            newRect = clampedForMove(newRect)
            selectionRect = newRect
            delegate?.selectionDidChange(rect: newRect, inView: self)
            needsDisplay = true

        case .resize(let handle):
            SelectionView.setCursorForHandle(handle)
            let newRect = SelectionView.resizedRect(
                from: dragOriginalRect,
                handle: handle,
                currentPoint: point,
                aspectRatio: aspectRatio,
                bounds: selectionAdjustmentBounds ?? bounds
            )
            selectionRect = newRect
            delegate?.selectionDidChange(rect: newRect, inView: self)
            needsDisplay = true

        case .none:
            break
        }
    }

    private func clampedForMove(_ rect: NSRect) -> NSRect {
        let adjustmentBounds = selectionAdjustmentBounds ?? bounds
        var result = rect
        result.origin.x = max(
            adjustmentBounds.minX,
            min(adjustmentBounds.maxX - result.width, result.origin.x)
        )
        result.origin.y = max(
            adjustmentBounds.minY,
            min(adjustmentBounds.maxY - result.height, result.origin.y)
        )
        return result
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard selectionInteractionEnabled else {
            dragAction = .none
            NSCursor.arrow.set()
            return
        }
        defer {
            dragAction = .none
            refreshCursorRects()
            updateCursor(at: point)
        }

        switch dragAction {
        case .drawNew:
            // Click without drag → confirm the pending window selection
            if let windowRect = pendingWindowRect {
                let windowID = pendingWindowID
                pendingWindowRect = nil
                pendingWindowID = nil
                selectionRect = windowRect
                state = .selected
                delegate?.selectionDidComplete(rect: windowRect, inView: self, isWindowSelection: true, windowID: windowID)
                needsDisplay = true
                return
            }
            guard let rect = selectionRect, rect.width >= 5, rect.height >= 5 else {
                selectionRect = nil
                state = .idle
                needsDisplay = true
                return
            }
            state = .selected
            delegate?.selectionDidComplete(rect: rect, inView: self, isWindowSelection: false, windowID: nil)
            needsDisplay = true

        case .move, .resize:
            if let rect = selectionRect {
                delegate?.selectionDidComplete(rect: rect, inView: self, isWindowSelection: false, windowID: nil)
            }
            needsDisplay = true

        case .none:
            break
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard selectionInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        broadcastCrosshair(at: point)

        // In idle state, detect windows under cursor for hover highlight
        if state == .idle && !selectionLocked {
            // capcap may lose activation over time, which causes WindowServer
            // to ignore the crosshair cursor rect registered in resetCursorRects.
            // Re-activate on every mouse-move so the cursor stays crosshair.
            if mayActivateAppForCursor && !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
            }
            NSCursor.crosshair.set()
            updateWindowHover(with: event)
        } else {
            updateCursor(at: point)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard selectionInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)
        broadcastCrosshair(at: point)
        updateCursor(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        // The pointer left this display: hide the guides until the next move
        // (the receiving display broadcasts its own position right away).
        hideCrosshair()
    }

    private func updateCursor(at point: NSPoint) {
        guard selectionInteractionEnabled else {
            NSCursor.arrow.set()
            return
        }

        if setResizeCursorIfNeeded(at: point, from: self) {
            return
        }
        if state == .idle, !selectionLocked {
            NSCursor.crosshair.set()
        } else if state == .drawing {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Window Hover

    private func updateWindowHover(with event: NSEvent) {
        guard let win = self.window else {
            clearHover()
            return
        }

        // Convert view point → screen point
        let viewPoint = convert(event.locationInWindow, from: nil)
        let windowPoint = convert(viewPoint, to: nil)
        let screenPoint = win.convertPoint(toScreen: windowPoint)
        updateWindowHover(screenPoint: screenPoint)
    }

    private func updateWindowHover(screenPoint: NSPoint) {
        guard let detector = windowDetector,
              let win = self.window,
              let screen = win.screen else {
            clearHover()
            return
        }

        // Convert screen point → CG point
        let primaryHeight = NSScreen.screens[0].frame.height
        let cgPoint = CGPoint(x: screenPoint.x, y: primaryHeight - screenPoint.y)

        if let detected = detector.windowAt(cgPoint: cgPoint) {
            // Convert CG window frame → AppKit screen coords → view coords
            let appKitY = primaryHeight - detected.frame.origin.y - detected.frame.height
            let viewRect = NSRect(
                x: detected.frame.origin.x - screen.frame.origin.x,
                y: appKitY - screen.frame.origin.y,
                width: detected.frame.width,
                height: detected.frame.height
            )
            // Clamp to view bounds
            let clamped = viewRect.intersection(bounds)
            guard !clamped.isNull, clamped.width > 1, clamped.height > 1 else {
                clearHover()
                return
            }
            if hoverWindowRect != clamped
                || hoverWindowFullRect != viewRect
                || hoverWindowID != detected.windowID {
                hoverWindowRect = clamped
                hoverWindowFullRect = viewRect
                hoverWindowID = detected.windowID
                delegate?.selectionDidHoverWindow(detected)
                needsDisplay = true
            }
        } else {
            clearHover()
        }
    }

    private func clearHover() {
        if hoverWindowRect != nil {
            hoverWindowRect = nil
            hoverWindowFullRect = nil
            hoverWindowID = nil
            delegate?.selectionDidHoverWindow(nil)
            needsDisplay = true
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        defer {
            reportFirstDrawIfNeeded()
            scheduleFirstFramePresentationIfNeeded()
        }

        // Draw pre-captured screen snapshot as background so transient
        // menus/popups remain visible even after they dismiss.
        // Skip during scroll capture so live scrolling content shows through.
        if let snapshot = backgroundSnapshot, !scrollCaptureActive {
            snapshot.draw(in: bounds)
        }

        // Hover highlight for window detection (idle state, before any click)
        if state == .idle, let hoverRect = hoverWindowRect {
            // Dark overlay with cutout (even-odd fill preserves snapshot underneath)
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(hoverRect)
            context.setFillColor(NSColor.black.withAlphaComponent(dimmingOverlayAlpha).cgColor)
            context.addPath(path)
            context.fillPath(using: .evenOdd)
            // Solid accent border — same 1pt weight as the committed frame
            // and the dragged box, so the three never look like different
            // line thicknesses. The stroke sits just outside the hover rect.
            context.setStrokeColor(SelectionView.selectionTintCGColor)
            context.setLineWidth(borderWidth)
            context.setLineDash(phase: 0, lengths: [])
            context.stroke(hoverRect.insetBy(dx: -borderWidth / 2, dy: -borderWidth / 2))
            // Size label
            SelectionView.drawSizeLabel(context: context, rect: hoverRect)
            return
        }

        // In idle state with no selection, just show the snapshot (already drawn above).
        // The pointer guides are not drawn here: they live in their own layers.
        guard let rect = selectionRect, (state == .drawing || state == .selected),
              rect.width > 0 || rect.height > 0 else {
            return
        }

        // Dark overlay with cutout (even-odd fill preserves snapshot underneath).
        // During scroll capture, enlarge the cutout by 0.5pt so anti-aliasing
        // at the cutout edge falls outside the captured rect instead of
        // darkening its first pixel — otherwise every frame's bottom edge
        // leaves a gray line at each stitch seam.
        let path = CGMutablePath()
        path.addRect(bounds)
        let cutoutRect = scrollCaptureActive ? rect.insetBy(dx: -0.5, dy: -0.5) : rect
        path.addRect(cutoutRect)
        context.setFillColor(NSColor.black.withAlphaComponent(dimmingOverlayAlpha).cgColor)
        context.addPath(path)
        context.fillPath(using: .evenOdd)

        // Draw border — solid red during scroll capture, solid accent blue otherwise.
        if scrollCaptureActive {
            // ScreenCaptureKit sees the overlay panel, so any stroke pixels
            // inside `rect` bleed into every captured frame and produce thin
            // red lines at the left/right edges and at each stitch seam.
            // Inset enough that the stroke (and its anti-aliased fringe) sits
            // entirely outside the captured rect.
            let strokeWidth = borderWidth
            let outerInset = -(strokeWidth / 2 + 1)
            context.setStrokeColor(NSColor.systemRed.cgColor)
            context.setLineWidth(strokeWidth)
            context.stroke(rect.insetBy(dx: outerInset, dy: outerInset))
        } else {
            // Frame + handles + size label come from the one shared painter.
            // The editor's live-selection chrome calls the same function, so a
            // committed capture selection and the editor's live selection are
            // drawn by one geometry, never two (no dots, no dashes anywhere).
            let showsHandles = state == .selected && selectionInteractionEnabled
            drawSelectionChrome(
                in: context,
                rect: rect,
                showsHandles: showsHandles,
                sizeLabel: showsHandles ? nil : (state == .selected ? selectionSizeLabelOverride : nil)
            )
        }
    }

    /// The one painter for the selection frame and its resize handles.
    ///
    /// `draw(_:)` uses it for the capture overlay; the editor's
    /// `SelectionChromeOverlay` (which sits above the editor canvas so the
    /// handles stay visible even when beautify expands the frame) calls it too.
    /// Both phases therefore paint the same chrome — a 1pt solid frame, 20×4pt
    /// edge bars and 12×2pt corner brackets — instead of each keeping a
    /// drawing of its own (the editor used to paint a 2pt dashed frame plus
    /// 8pt dots on top of this one).
    ///
    /// - Parameters:
    ///   - showsHandles: draws the eight handles and the live size label.
    ///   - sizeLabel: pinned label text (used instead of the live rect size).
    func drawSelectionChrome(
        in context: CGContext,
        rect: NSRect,
        showsHandles: Bool = true,
        sizeLabel: String? = nil
    ) {
        context.setStrokeColor(Self.selectionTintCGColor)
        context.setLineWidth(borderWidth)
        context.setLineDash(phase: 0, lengths: [])
        context.stroke(rect.insetBy(dx: -borderWidth / 2, dy: -borderWidth / 2))

        if showsHandles {
            drawHandles(context: context, rect: rect)
            Self.drawSizeLabel(context: context, rect: rect, text: sizeLabel)
        } else if let sizeLabel {
            Self.drawSizeLabel(context: context, rect: rect, text: sizeLabel)
        }
    }

    private func reportFirstDrawIfNeeded() {
        guard !didReportFirstDraw else { return }
        didReportFirstDraw = true
        onFirstDrawCompleted?()
        onFirstDrawCompleted = nil
    }

    private func scheduleFirstFramePresentationIfNeeded() {
        guard !didScheduleFirstFramePresentation else { return }
        didScheduleFirstFramePresentation = true

        // draw(_:) only proves AppKit prepared the backing store. Waiting for
        // the next display refresh also captures the render-to-display gap.
        let displayLink = displayLink(
            target: self,
            selector: #selector(firstFrameDisplayLinkDidFire(_:))
        )
        firstFrameDisplayLink = displayLink
        displayLink.add(to: .main, forMode: .common)
    }

    @objc private func firstFrameDisplayLinkDidFire(_ displayLink: CADisplayLink) {
        displayLink.invalidate()
        firstFrameDisplayLink = nil
        onFirstFramePresented?()
        onFirstFramePresented = nil
    }

    /// Draws the eight resize handles in the macOS screenshot-tool language:
    /// edge midpoints are short bars (horizontal on the top/bottom edge,
    /// vertical on the left/right edge) and the four corners are L-shaped
    /// brackets hugging the inside of the corner. No dots.
    private func drawHandles(context: CGContext, rect: NSRect) {
        context.setFillColor(SelectionView.selectionTintCGColor)
        let positions = SelectionView.handlePositions(for: rect)
        for (index, handle) in HandlePosition.allCases.enumerated() {
            let position = positions[index]
            switch handle {
            case .topCenter, .bottomCenter:
                context.addPath(Self.barPath(
                    centered: position,
                    horizontal: true,
                    pixelAligned: pixelAligned
                ))
                context.fillPath()
            case .leftCenter, .rightCenter:
                context.addPath(Self.barPath(
                    centered: position,
                    horizontal: false,
                    pixelAligned: pixelAligned
                ))
                context.fillPath()
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                for arm in SelectionView.cornerBracketRects(handle: handle, rect: rect) {
                    context.addRect(pixelAligned(arm))
                    context.fillPath()
                }
            }
        }
    }

    /// Bar geometry for an edge handle: 20pt long, 4pt thick, 2pt rounded
    /// ends, centred on the edge so it straddles the frame line.
    private static func barPath(
        centered position: NSPoint,
        horizontal: Bool,
        pixelAligned: (NSRect) -> NSRect
    ) -> CGPath {
        let length = SelectionView.handleBarLength
        let thickness = SelectionView.handleBarThickness
        let rect = horizontal
            ? NSRect(
                x: position.x - length / 2,
                y: position.y - thickness / 2,
                width: length,
                height: thickness
            )
            : NSRect(
                x: position.x - thickness / 2,
                y: position.y - length / 2,
                width: thickness,
                height: length
            )
        return CGPath(
            roundedRect: pixelAligned(rect),
            cornerWidth: SelectionView.handleBarCornerRadius,
            cornerHeight: SelectionView.handleBarCornerRadius,
            transform: nil
        )
    }

    /// The two 12pt × 2pt arms of a corner bracket, lying inside the selection
    /// and meeting at the corner itself.
    static func cornerBracketRects(handle: HandlePosition, rect: NSRect) -> [NSRect] {
        let arm = SelectionView.handleCornerArmLength
        let thickness = SelectionView.handleCornerArmThickness
        switch handle {
        case .topLeft:
            return [
                NSRect(x: rect.minX, y: rect.maxY - thickness, width: arm, height: thickness),
                NSRect(x: rect.minX, y: rect.maxY - arm, width: thickness, height: arm)
            ]
        case .topRight:
            return [
                NSRect(x: rect.maxX - arm, y: rect.maxY - thickness, width: arm, height: thickness),
                NSRect(x: rect.maxX - thickness, y: rect.maxY - arm, width: thickness, height: arm)
            ]
        case .bottomLeft:
            return [
                NSRect(x: rect.minX, y: rect.minY, width: arm, height: thickness),
                NSRect(x: rect.minX, y: rect.minY, width: thickness, height: arm)
            ]
        case .bottomRight:
            return [
                NSRect(x: rect.maxX - arm, y: rect.minY, width: arm, height: thickness),
                NSRect(x: rect.maxX - thickness, y: rect.minY, width: thickness, height: arm)
            ]
        case .topCenter, .bottomCenter, .leftCenter, .rightCenter:
            return []
        }
    }

    /// Rounds handle geometry onto the display's pixel grid so a 20×4pt bar is
    /// exactly 40×8 device pixels on a 2x display instead of a blurred 41×9.
    private func pixelAligned(_ rect: NSRect) -> NSRect {
        let scale = window?.backingScaleFactor ?? 2
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        return NSRect(
            x: snap(rect.origin.x),
            y: snap(rect.origin.y),
            width: snap(rect.width),
            height: snap(rect.height)
        )
    }

    static func drawSizeLabel(context: CGContext, rect: NSRect, text: String? = nil) {
        // Same multiplication sign as the rest of the app's size badges
        // (`ReplicaImagePreviewContent`, `PanelViews`, `ReplicaCanonicalCardContent`).
        let text = text ?? "\(Int(rect.width)) × \(Int(rect.height))"
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        ]
        let size = text.size(withAttributes: attrs)
        let padding = SelectionView.sizeLabelPadding
        // Sit above the top-left corner of the frame, never over its pixels:
        // the label is chrome, so anything inside `rect` would end up cropped.
        let labelRect = NSRect(
            x: rect.origin.x,
            y: rect.origin.y + rect.height + SelectionView.sizeLabelGap,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )

        // Blue capsule with a soft drop shadow so it separates from both a
        // bright and a dark snapshot.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -1),
            blur: 4,
            color: NSColor.black.withAlphaComponent(0.35).cgColor
        )
        context.setFillColor(SelectionView.selectionTintCGColor)
        let bgPath = CGPath(
            roundedRect: labelRect,
            cornerWidth: SelectionView.sizeLabelCornerRadius,
            cornerHeight: SelectionView.sizeLabelCornerRadius,
            transform: nil
        )
        context.addPath(bgPath)
        context.fillPath()
        context.restoreGState()

        // Draw text, vertically centred inside the capsule.
        let textOrigin = NSPoint(
            x: labelRect.origin.x + padding.width,
            y: labelRect.origin.y + (labelRect.height - size.height) / 2
        )
        text.draw(at: textOrigin, withAttributes: attrs)
    }

    // MARK: - Handle Positions

    static func handlePositions(for rect: NSRect) -> [NSPoint] {
        let minX = rect.minX, midX = rect.midX, maxX = rect.maxX
        let minY = rect.minY, midY = rect.midY, maxY = rect.maxY
        return [
            NSPoint(x: minX, y: maxY),  // topLeft
            NSPoint(x: maxX, y: maxY),  // topRight
            NSPoint(x: minX, y: minY),  // bottomLeft
            NSPoint(x: maxX, y: minY),  // bottomRight
            NSPoint(x: midX, y: maxY),  // topCenter
            NSPoint(x: midX, y: minY),  // bottomCenter
            NSPoint(x: minX, y: midY),  // leftCenter
            NSPoint(x: maxX, y: midY),  // rightCenter
        ]
    }

    static func hitTestHandle(point: NSPoint, rect: NSRect, hitSize: CGFloat) -> HandlePosition? {
        let positions = handlePositions(for: rect)
        let handles = HandlePosition.allCases
        for (i, pos) in positions.enumerated() {
            let hitRect = NSRect(
                x: pos.x - hitSize / 2,
                y: pos.y - hitSize / 2,
                width: hitSize,
                height: hitSize
            )
            if hitRect.contains(point) {
                return handles[i]
            }
        }
        return nil
    }

    private func hitTestHandle(point: NSPoint, rect: NSRect) -> HandlePosition? {
        SelectionView.hitTestHandle(point: point, rect: rect, hitSize: Self.handleHitSize)
    }

    // MARK: - Resize Logic

    private static func dragRect(from origin: NSPoint, to point: NSPoint, aspectRatio: CGFloat?, bounds: NSRect) -> NSRect {
        guard let ratio = normalizedAspectRatio(aspectRatio) else {
            let x = min(origin.x, point.x)
            let y = min(origin.y, point.y)
            let width = abs(point.x - origin.x)
            let height = abs(point.y - origin.y)
            return NSRect(x: x, y: y, width: width, height: height)
        }

        let dx = point.x - origin.x
        let dy = point.y - origin.y
        let unconstrainedWidth = abs(dx)
        let unconstrainedHeight = abs(dy)
        let constrainedWidth = max(unconstrainedWidth, unconstrainedHeight * ratio)
        let constrainedHeight = constrainedWidth / ratio
        let maxWidth = dx < 0 ? origin.x - bounds.minX : bounds.maxX - origin.x
        let maxHeight = dy < 0 ? origin.y - bounds.minY : bounds.maxY - origin.y
        let size = fittedAspectSize(
            CGSize(width: constrainedWidth, height: constrainedHeight),
            aspectRatio: ratio,
            maximumWidth: maxWidth,
            maximumHeight: maxHeight
        )
        let signedWidth = dx < 0 ? -size.width : size.width
        let signedHeight = dy < 0 ? -size.height : size.height
        let maxX = origin.x + signedWidth
        let maxY = origin.y + signedHeight

        return NSRect(
            x: min(origin.x, maxX),
            y: min(origin.y, maxY),
            width: abs(signedWidth),
            height: abs(signedHeight)
        )
    }

    static func resizedRect(
        from original: NSRect,
        handle: HandlePosition,
        currentPoint: NSPoint,
        aspectRatio: CGFloat? = nil,
        bounds: NSRect
    ) -> NSRect {
        let minimumSize: CGFloat = 5
        let boundedPoint = NSPoint(
            x: max(bounds.minX, min(bounds.maxX, currentPoint.x)),
            y: max(bounds.minY, min(bounds.maxY, currentPoint.y))
        )
        var minX = original.minX
        var minY = original.minY
        var maxX = original.maxX
        var maxY = original.maxY

        switch handle {
        case .topLeft:
            minX = min(boundedPoint.x, maxX - minimumSize)
            maxY = max(boundedPoint.y, minY + minimumSize)
        case .topRight:
            maxX = max(boundedPoint.x, minX + minimumSize)
            maxY = max(boundedPoint.y, minY + minimumSize)
        case .bottomLeft:
            minX = min(boundedPoint.x, maxX - minimumSize)
            minY = min(boundedPoint.y, maxY - minimumSize)
        case .bottomRight:
            maxX = max(boundedPoint.x, minX + minimumSize)
            minY = min(boundedPoint.y, maxY - minimumSize)
        case .topCenter:
            maxY = max(boundedPoint.y, minY + minimumSize)
        case .bottomCenter:
            minY = min(boundedPoint.y, maxY - minimumSize)
        case .leftCenter:
            minX = min(boundedPoint.x, maxX - minimumSize)
        case .rightCenter:
            maxX = max(boundedPoint.x, minX + minimumSize)
        }

        let unconstrained = NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        guard let ratio = normalizedAspectRatio(aspectRatio) else { return unconstrained }
        return aspectLockedRect(
            from: unconstrained,
            original: original,
            handle: handle,
            aspectRatio: ratio,
            minimumSize: minimumSize,
            bounds: bounds
        )
    }

    private static func normalizedAspectRatio(_ aspectRatio: CGFloat?) -> CGFloat? {
        guard let aspectRatio, aspectRatio > 0, aspectRatio.isFinite else { return nil }
        return aspectRatio
    }

    private static func aspectLockedRect(
        from unconstrained: NSRect,
        original: NSRect,
        handle: HandlePosition,
        aspectRatio: CGFloat,
        minimumSize: CGFloat,
        bounds: NSRect
    ) -> NSRect {
        switch handle {
        case .topLeft:
            let size = fittedAspectSize(
                aspectSize(
                    fittingWidth: unconstrained.width,
                    height: unconstrained.height,
                    aspectRatio: aspectRatio,
                    minimumSize: minimumSize
                ),
                aspectRatio: aspectRatio,
                maximumWidth: original.maxX - bounds.minX,
                maximumHeight: bounds.maxY - original.minY
            )
            return NSRect(x: original.maxX - size.width, y: original.minY, width: size.width, height: size.height)
        case .topRight:
            let size = fittedAspectSize(
                aspectSize(
                    fittingWidth: unconstrained.width,
                    height: unconstrained.height,
                    aspectRatio: aspectRatio,
                    minimumSize: minimumSize
                ),
                aspectRatio: aspectRatio,
                maximumWidth: bounds.maxX - original.minX,
                maximumHeight: bounds.maxY - original.minY
            )
            return NSRect(x: original.minX, y: original.minY, width: size.width, height: size.height)
        case .bottomLeft:
            let size = fittedAspectSize(
                aspectSize(
                    fittingWidth: unconstrained.width,
                    height: unconstrained.height,
                    aspectRatio: aspectRatio,
                    minimumSize: minimumSize
                ),
                aspectRatio: aspectRatio,
                maximumWidth: original.maxX - bounds.minX,
                maximumHeight: original.maxY - bounds.minY
            )
            return NSRect(x: original.maxX - size.width, y: original.maxY - size.height, width: size.width, height: size.height)
        case .bottomRight:
            let size = fittedAspectSize(
                aspectSize(
                    fittingWidth: unconstrained.width,
                    height: unconstrained.height,
                    aspectRatio: aspectRatio,
                    minimumSize: minimumSize
                ),
                aspectRatio: aspectRatio,
                maximumWidth: bounds.maxX - original.minX,
                maximumHeight: original.maxY - bounds.minY
            )
            return NSRect(x: original.minX, y: original.maxY - size.height, width: size.width, height: size.height)
        case .topCenter:
            let size = fittedAspectSize(
                aspectSize(
                    fromHeight: unconstrained.height,
                    aspectRatio: aspectRatio,
                    minimumSize: minimumSize
                ),
                aspectRatio: aspectRatio,
                maximumWidth: symmetricMaximumLength(around: original.midX, lowerBound: bounds.minX, upperBound: bounds.maxX),
                maximumHeight: bounds.maxY - original.minY
            )
            return NSRect(x: original.midX - size.width / 2, y: original.minY, width: size.width, height: size.height)
        case .bottomCenter:
            let size = fittedAspectSize(
                aspectSize(
                    fromHeight: unconstrained.height,
                    aspectRatio: aspectRatio,
                    minimumSize: minimumSize
                ),
                aspectRatio: aspectRatio,
                maximumWidth: symmetricMaximumLength(around: original.midX, lowerBound: bounds.minX, upperBound: bounds.maxX),
                maximumHeight: original.maxY - bounds.minY
            )
            return NSRect(x: original.midX - size.width / 2, y: original.maxY - size.height, width: size.width, height: size.height)
        case .leftCenter:
            let size = fittedAspectSize(
                aspectSize(
                    fromWidth: unconstrained.width,
                    aspectRatio: aspectRatio,
                    minimumSize: minimumSize
                ),
                aspectRatio: aspectRatio,
                maximumWidth: original.maxX - bounds.minX,
                maximumHeight: symmetricMaximumLength(around: original.midY, lowerBound: bounds.minY, upperBound: bounds.maxY)
            )
            return NSRect(x: original.maxX - size.width, y: original.midY - size.height / 2, width: size.width, height: size.height)
        case .rightCenter:
            let size = fittedAspectSize(
                aspectSize(
                    fromWidth: unconstrained.width,
                    aspectRatio: aspectRatio,
                    minimumSize: minimumSize
                ),
                aspectRatio: aspectRatio,
                maximumWidth: bounds.maxX - original.minX,
                maximumHeight: symmetricMaximumLength(around: original.midY, lowerBound: bounds.minY, upperBound: bounds.maxY)
            )
            return NSRect(x: original.minX, y: original.midY - size.height / 2, width: size.width, height: size.height)
        }
    }

    private static func fittedAspectSize(
        _ size: CGSize,
        aspectRatio: CGFloat,
        maximumWidth: CGFloat,
        maximumHeight: CGFloat
    ) -> CGSize {
        let width = min(size.width, max(0, maximumWidth), max(0, maximumHeight) * aspectRatio)
        return CGSize(width: width, height: width / aspectRatio)
    }

    private static func symmetricMaximumLength(around center: CGFloat, lowerBound: CGFloat, upperBound: CGFloat) -> CGFloat {
        2 * max(0, min(center - lowerBound, upperBound - center))
    }

    private static func aspectSize(
        fittingWidth width: CGFloat,
        height: CGFloat,
        aspectRatio: CGFloat,
        minimumSize: CGFloat
    ) -> CGSize {
        var constrainedWidth = max(width, height * aspectRatio, minimumSize)
        var constrainedHeight = constrainedWidth / aspectRatio
        if constrainedHeight < minimumSize {
            constrainedHeight = minimumSize
            constrainedWidth = constrainedHeight * aspectRatio
        }
        return CGSize(width: constrainedWidth, height: constrainedHeight)
    }

    private static func aspectSize(
        fromHeight height: CGFloat,
        aspectRatio: CGFloat,
        minimumSize: CGFloat
    ) -> CGSize {
        var constrainedHeight = max(height, minimumSize)
        var constrainedWidth = constrainedHeight * aspectRatio
        if constrainedWidth < minimumSize {
            constrainedWidth = minimumSize
            constrainedHeight = constrainedWidth / aspectRatio
        }
        return CGSize(width: constrainedWidth, height: constrainedHeight)
    }

    private static func aspectSize(
        fromWidth width: CGFloat,
        aspectRatio: CGFloat,
        minimumSize: CGFloat
    ) -> CGSize {
        var constrainedWidth = max(width, minimumSize)
        var constrainedHeight = constrainedWidth / aspectRatio
        if constrainedHeight < minimumSize {
            constrainedHeight = minimumSize
            constrainedWidth = constrainedHeight * aspectRatio
        }
        return CGSize(width: constrainedWidth, height: constrainedHeight)
    }

    // MARK: - Cursor

    static func cursorForHandle(_ handle: HandlePosition) -> NSCursor {
        switch handle {
        case .topLeft:
            return ResizeHandleCursor.frameResizeCursor(for: .topLeft)
        case .topRight:
            return ResizeHandleCursor.frameResizeCursor(for: .topRight)
        case .bottomLeft:
            return ResizeHandleCursor.frameResizeCursor(for: .bottomLeft)
        case .bottomRight:
            return ResizeHandleCursor.frameResizeCursor(for: .bottomRight)
        case .topCenter:
            return ResizeHandleCursor.frameResizeCursor(for: .top)
        case .bottomCenter:
            return ResizeHandleCursor.frameResizeCursor(for: .bottom)
        case .leftCenter:
            return ResizeHandleCursor.frameResizeCursor(for: .left)
        case .rightCenter:
            return ResizeHandleCursor.frameResizeCursor(for: .right)
        }
    }

    static func setCursorForHandle(_ handle: HandlePosition) {
        cursorForHandle(handle).set()
    }

    // MARK: - Configuration

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
}
