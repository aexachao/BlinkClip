import AppKit
import os
import QuartzCore

// MARK: - Overlay perf signposts (MEAS)
//
// Measurement-only scaffolding: the overlay's per-event hot path is broken into
// `os_signpost` intervals so the in-app cost of a pointer move can be read from
// the trace instead of guessed from `top`.
//
// Off by default and zero-cost when off: every call site is a `guard` on a
// `static let` read once at launch, so nothing is emitted (and nothing is
// allocated for an interval id) unless the process was started with
//
//     BLINKCLIP_OVERLAY_PERF=1
//
// `OSSignposter` itself is the cheap path (`OS_LOG_CATEGORY_POINTS_OF_INTEREST`
// signposts are disabled at the source when no tooling is attached), so even the
// instrumented build keeps its product behaviour and its resting cost.
enum OverlayPerfSignpost {
    /// Set once at launch from the environment; not a user-facing setting.
    static let isEnabled = ProcessInfo.processInfo
        .environment["BLINKCLIP_OVERLAY_PERF"] == "1"

    static let signposter = OSSignposter(
        subsystem: "com.chrisli.blinkclip",
        category: "overlay-perf"
    )

    /// Opens an interval; returns `nil` (and emits nothing) when the gate is off.
    @inline(__always)
    static func begin(_ name: StaticString) -> OSSignpostIntervalState? {
        guard isEnabled else { return nil }
        return signposter.beginInterval(name, id: signposter.makeSignpostID())
    }

    /// Closes the interval opened by `begin`, if any.
    @inline(__always)
    static func end(_ name: StaticString, _ state: OSSignpostIntervalState?) {
        guard let state else { return }
        signposter.endInterval(name, state)
    }
}

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

/// The snap guide: the four edges of the window under the pointer (and,
/// optionally, its horizontal/vertical centre lines) drawn as a 1.5pt
/// `systemGray` 50% dashed line.
///
/// The guide lives in its own layer and is positioned by *window target*, not
/// by pointer coordinate: moving inside one window writes nothing at all, and
/// crossing into another window replaces the whole path in one synchronous
/// update — the guide jumps, it never interpolates. The pointer itself is the
/// *system* crosshair (`NSCursor.crosshair`, hardware-composited, never
/// hidden), so the view never draws or hides it.
private final class SnapGuideView: NSView {
    /// Guide weight and colour alpha. The source gate reads these constants, so
    /// the documented style cannot drift from the drawn one.
    static let lineWidth: CGFloat = 1.5
    static let alpha: CGFloat = 0.5

    /// Dash rhythm in points: 6pt on, 4pt off.
    ///
    /// **This is the one and only place to change the guide's line style.**
    /// The historical default was a solid line (1.0.25) and the SG spec calls
    /// for a dashed one (6/4) again; setting this constant to `nil` restores
    /// the solid line without touching any drawing or layout code.
    static let dashPattern: [NSNumber]? = [6, 4]

    private let lineLayer = CAShapeLayer()
    private var placedTarget: NSRect = .null
    private var showsCenterLines = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        layer?.isOpaque = false
        layer?.masksToBounds = false
        // A guide is decoration: never a hit or cursor target.
        layer?.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull()
        ]
        lineLayer.fillColor = nil
        lineLayer.strokeColor = NSColor.systemGray
            .withAlphaComponent(Self.alpha).cgColor
        lineLayer.lineWidth = Self.lineWidth
        lineLayer.lineDashPattern = Self.dashPattern
        lineLayer.lineCap = .butt
        lineLayer.isOpaque = false
        lineLayer.masksToBounds = false
        // A move must not animate: the guide has to be at the target's new
        // position in this event, not ride a 0.25s implicit animation.
        lineLayer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "path": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull()
        ]
        layer?.addSublayer(lineLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Four edge lines are the whole guide; the centre lines are optional chrome
    /// (settings) and do not change the target geometry.
    private func guidePath(in rect: NSRect, centerLines: Bool) -> CGPath {
        let path = CGMutablePath()
        // Keep the 1.5pt stroke inside the target rect, exactly on its edges.
        let edge = rect.insetBy(dx: Self.lineWidth / 2, dy: Self.lineWidth / 2)
        guard edge.width > 0, edge.height > 0 else { return path }
        path.addRect(edge)
        if centerLines {
            path.move(to: CGPoint(x: edge.midX, y: edge.minY))
            path.addLine(to: CGPoint(x: edge.midX, y: edge.maxY))
            path.move(to: CGPoint(x: edge.minX, y: edge.midY))
            path.addLine(to: CGPoint(x: edge.maxX, y: edge.midY))
        }
        return path
    }

    /// Positions the guide on `rect` (view coordinates) or hides it.
    ///
    /// The early return is the whole "snaps like a shadow" contract: while the
    /// pointer stays inside the same window the target rect does not change, so
    /// nothing is recomputed, no path is rebuilt and no layer is displayed.
    /// - Returns: true when visibility or geometry was actually written.
    @discardableResult
    func place(_ rect: NSRect, visible: Bool, centerLines: Bool) -> Bool {
        var wrote = false
        if isHidden != !visible {
            isHidden = !visible
            wrote = true
        }
        guard visible else {
            placedTarget = .null
            return wrote
        }
        guard rect != placedTarget || centerLines != showsCenterLines else { return false }
        placedTarget = rect
        showsCenterLines = centerLines
        frame = rect
        lineLayer.frame = bounds
        lineLayer.path = guidePath(in: bounds, centerLines: centerLines)
        // Render the layer now, inside the caller's disabled-actions
        // transaction: a guide jump is never deferred to the next run loop.
        lineLayer.setNeedsDisplay()
        lineLayer.displayIfNeeded()
        return true
    }
}

/// The window-hover highlight: dimming cut-out, accent frame and size label.
///
/// This chrome used to be painted by `SelectionView.draw(_:)`, so every hover
/// target change invalidated the *whole* overlay and re-blitted the frozen
/// desktop snapshot (tens of megabytes on a 2x display) before drawing the
/// cut-out on top — once per window crossing. It now lives in its own
/// layer-backed view: a crossing repaints a dim fill, one inset stroke and the
/// label, and never touches the snapshot underneath.
private final class HoverHighlightView: NSView {
    private let dimmingAlpha: CGFloat
    private let borderWidth: CGFloat
    private let tint: CGColor

    /// Highlighted rect in this view's coordinates (same space as the overlay,
    /// i.e. the whole display). `.null` means "nothing hovered".
    var hoverRect: NSRect = .null {
        didSet {
            guard hoverRect != oldValue else { return }
            needsDisplay = true
        }
    }

    init(dimmingAlpha: CGFloat, borderWidth: CGFloat, tint: CGColor) {
        self.dimmingAlpha = dimmingAlpha
        self.borderWidth = borderWidth
        self.tint = tint
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        layer?.isOpaque = false
        layer?.masksToBounds = false
        layer?.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull(),
            "contents": NSNull()
        ]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    /// Decoration only: it must never take the pointer away from the overlay.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let perfHighlight = OverlayPerfSignpost.begin("hover-highlight")
        defer { OverlayPerfSignpost.end("hover-highlight", perfHighlight) }
        guard !hoverRect.isNull, hoverRect.width > 0, hoverRect.height > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }

        // Dark overlay with cutout (even-odd fill preserves the snapshot
        // underneath, which this view's parent painted).
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(hoverRect)
        context.setFillColor(NSColor.black.withAlphaComponent(dimmingAlpha).cgColor)
        context.addPath(path)
        context.fillPath(using: .evenOdd)

        // Solid accent border — same 1pt weight as the committed frame and the
        // dragged box, so the three never look like different line thicknesses.
        // The stroke sits just outside the hover rect.
        context.setStrokeColor(tint)
        context.setLineWidth(borderWidth)
        context.setLineDash(phase: 0, lengths: [])
        context.stroke(hoverRect.insetBy(dx: -borderWidth / 2, dy: -borderWidth / 2))
        SelectionView.drawSizeLabel(context: context, rect: hoverRect, in: self)
    }
}

/// The selection's own chrome — dimming cut-out, 1pt accent frame, the eight
/// handles, the size label and the scroll-capture red marker — in a layer of
/// its own.
///
/// It used to be painted by `SelectionView.draw(_:)`, so every drag event
/// invalidated the *whole* overlay and re-blitted the frozen desktop snapshot
/// (tens of megabytes per pointer sample on a 2x display). Moving it next to
/// the hover highlight fixes that: a drag writes this view's geometry only,
/// and `SelectionView.draw(_:)` — which now draws nothing but the snapshot —
/// is never called while the pointer is down.
private final class SelectionChromeView: NSView {
    /// The owning overlay, for the one shared chrome painter
    /// (`SelectionView.drawSelectionChrome`) and the size-label geometry.
    weak var selectionView: SelectionView?

    private let dimmingAlpha: CGFloat
    private let borderWidth: CGFloat

    /// Last written state. Equal state means zero work, exactly like the snap
    /// guide's `placedTarget`: a pointer move that does not change the box
    /// writes nothing.
    private var placedRect: NSRect = .null
    private var placedHandles = false
    private var placedScrollCapture = false
    private var placedLabel: String?

    init(selectionView: SelectionView, dimmingAlpha: CGFloat, borderWidth: CGFloat) {
        self.selectionView = selectionView
        self.dimmingAlpha = dimmingAlpha
        self.borderWidth = borderWidth
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        layer?.isOpaque = false
        layer?.masksToBounds = false
        layer?.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull(),
            "contents": NSNull()
        ]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    /// Decoration only: it must never take the pointer away from the overlay.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Writes the chrome for `rect` (this view's coordinates) or hides it.
    ///
    /// - Parameters:
    ///   - rect: nil, or a zero-area rect, hides the chrome (no dimming either,
    ///     which is what an initial mouse-down with a 0×0 box looks like).
    ///   - showsHandles: the eight resize handles — only for a committed box.
    ///   - scrollCapture: red anti-bleed marker instead of the accent frame.
    ///   - sizeLabel: pinned label text (scroll-capture zoom, editor hand-off).
    /// - Returns: true when visibility, geometry or styling was actually written.
    @discardableResult
    func place(rect: NSRect?, showsHandles: Bool, scrollCapture: Bool, sizeLabel: String?) -> Bool {
        let target = rect ?? .null
        let drawable = !target.isNull && (target.width > 0 || target.height > 0)
        var wrote = false
        if isHidden != !drawable {
            isHidden = !drawable
            wrote = true
        }
        guard drawable else {
            placedRect = .null
            placedHandles = false
            placedScrollCapture = false
            placedLabel = nil
            return wrote
        }
        guard target != placedRect
            || showsHandles != placedHandles
            || scrollCapture != placedScrollCapture
            || sizeLabel != placedLabel else { return wrote }
        placedRect = target
        placedHandles = showsHandles
        placedScrollCapture = scrollCapture
        placedLabel = sizeLabel
        // Paint now, inside the caller's disabled-actions transaction: the box
        // follows the pointer in this event, it never trails it by a frame.
        needsDisplay = true
        displayIfNeeded()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !placedRect.isNull,
              placedRect.width > 0 || placedRect.height > 0,
              let context = NSGraphicsContext.current?.cgContext else { return }
        let rect = placedRect

        // Dark overlay with cutout (even-odd fill preserves the snapshot
        // underneath, which the parent's `draw(_:)` painted).
        // During scroll capture, enlarge the cutout by 0.5pt so anti-aliasing
        // at the cutout edge falls outside the captured rect instead of
        // darkening its first pixel — otherwise every frame's bottom edge
        // leaves a gray line at each stitch seam.
        let path = CGMutablePath()
        path.addRect(bounds)
        let cutoutRect = placedScrollCapture ? rect.insetBy(dx: -0.5, dy: -0.5) : rect
        path.addRect(cutoutRect)
        context.setFillColor(NSColor.black.withAlphaComponent(dimmingAlpha).cgColor)
        context.addPath(path)
        context.fillPath(using: .evenOdd)

        // Draw border — solid red during scroll capture, solid accent blue
        // otherwise.
        if placedScrollCapture {
            // ScreenCaptureKit sees the overlay panel, so any stroke pixels
            // inside `rect` bleed into every captured frame and produce thin
            // red lines at the left/right edges and at each stitch seam.
            // Inset enough that the stroke (and its anti-aliased fringe) sits
            // entirely outside the captured rect.
            let strokeWidth = borderWidth
            let outerInset = -(strokeWidth / 2 + 1)
            context.setStrokeColor(NSColor.systemRed.cgColor)
            context.setLineWidth(strokeWidth)
            context.setLineDash(phase: 0, lengths: [])
            context.stroke(rect.insetBy(dx: outerInset, dy: outerInset))
        } else {
            // Frame + handles + size label come from the one shared painter.
            // The editor's live-selection chrome calls the same function, so a
            // committed capture selection and the editor's live selection are
            // drawn by one geometry, never two (no dots, no dashes anywhere).
            selectionView?.drawSelectionChrome(
                in: context,
                rect: rect,
                showsHandles: placedHandles,
                sizeLabel: placedLabel
            )
        }
    }
}

/// The stronger line on a snapped drag edge: while a drag has glued a
/// selection edge to a window edge, that one edge is redrawn as a 2pt, 100%
/// `systemGray` solid line — same hue as the dashed window outline, just
/// stronger — so the user sees *which* edge holds.
///
/// Own `CAShapeLayer`, own path, cleared on mouse-up: a snap writes one
/// segment, it never repaints the overlay.
private final class SnapHighlightView: NSView {
    /// One drawn edge of the dragged box, in this view's coordinates.
    struct Segment: Equatable {
        let start: NSPoint
        let end: NSPoint
    }

    /// Highlight weight, alpha and colour. Same family as `SnapGuideView`
    /// (`systemGray`), stronger so a snapped edge reads at a glance.
    static let lineWidth: CGFloat = 2
    static let alpha: CGFloat = 1.0

    private let lineLayer = CAShapeLayer()
    private var placedSegments: [Segment] = []

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        isHidden = true
        layer?.isOpaque = false
        layer?.masksToBounds = false
        layer?.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull()
        ]
        lineLayer.fillColor = nil
        lineLayer.strokeColor = NSColor.systemGray
            .withAlphaComponent(Self.alpha).cgColor
        lineLayer.lineWidth = Self.lineWidth
        lineLayer.lineDashPattern = nil
        lineLayer.lineCap = .butt
        lineLayer.isOpaque = false
        lineLayer.masksToBounds = false
        lineLayer.actions = [
            "position": NSNull(),
            "bounds": NSNull(),
            "path": NSNull(),
            "hidden": NSNull(),
            "opacity": NSNull()
        ]
        layer?.addSublayer(lineLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isOpaque: Bool { false }

    /// Decoration only: it must never take the pointer away from the overlay.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// - Parameter segments: the edges to highlight; an empty list hides it.
    /// - Returns: true when visibility or geometry was actually written.
    @discardableResult
    func place(_ segments: [Segment]) -> Bool {
        var wrote = false
        let visible = !segments.isEmpty
        if isHidden != !visible {
            isHidden = !visible
            wrote = true
        }
        guard visible else {
            placedSegments = []
            return wrote
        }
        guard segments != placedSegments else { return wrote }
        placedSegments = segments
        let path = CGMutablePath()
        for segment in segments {
            path.move(to: segment.start)
            path.addLine(to: segment.end)
        }
        lineLayer.frame = bounds
        lineLayer.path = path
        lineLayer.setNeedsDisplay()
        lineLayer.displayIfNeeded()
        return true
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
                // The guide belonged to the idle hover; a click, a committed
                // frame or a returned selection hides it without repainting
                // the snapshot (it is a layer). The hover highlight is a layer
                // too, and only the idle state owns it.
                if state != .idle {
                    hideHoverHighlight()
                }
                // A snapped edge is highlighted only while a drag is running;
                // leaving `.drawing` clears it.
                if state != .drawing {
                    dragSnappedEdges = []
                }
                refreshSelectionChrome()
                refreshDragSnapHighlight()
                refreshSnapGuide()
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

    /// A foreground claim is a one-shot: activation is retried at most once per
    /// overlay session, never on every pointer move. `OverlayWindowController`
    /// already claims activation when it presents the overlay; re-claiming from
    /// `mouseMoved` used to run an activation attempt on every single event
    /// while the pointer moved over an inactive overlay.
    private var didAttemptCursorReactivation = false

    // When true, clicking outside selection won't start a new selection
    var selectionLocked = false {
        didSet {
            if selectionLocked != oldValue {
                refreshCursorRects()
                refreshSnapGuide()
            }
        }
    }

    // Scroll capture mode: update border styling while the controller manages event routing.
    var scrollCaptureActive = false {
        didSet {
            if scrollCaptureActive != oldValue {
                // The snapshot is skipped while scrolling, so this is the one
                // state change that has to repaint this view (to clear or
                // restore the frozen desktop); the chrome itself is a layer.
                needsDisplay = true
                refreshSelectionChrome()
                refreshSnapGuide()
            }
        }
    }

    // When false, the selection frame becomes a fixed viewport.
    var selectionInteractionEnabled = true {
        didSet {
            if selectionInteractionEnabled != oldValue {
                refreshCursorRects()
                refreshSelectionChrome()
                refreshSnapGuide()
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
        didSet { refreshSelectionChrome() }
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

    // MARK: - Snap guide

    /// The guide lives in its own view-backed layer (`SnapGuideView`), not in
    /// the overlay's snapshot drawing. It is positioned by the hovered window,
    /// not by the pointer: a move inside one window writes nothing, and a move
    /// into another window replaces the path synchronously — the line jumps and
    /// never trails the pointer by a run-loop turn. The pointer itself is the
    /// system crosshair: this view never draws or hides it.
    private let snapGuide = SnapGuideView()

    /// The hover dimming/border/label, in its own layer so a window crossing
    /// never repaints the frozen snapshot (see `HoverHighlightView`).
    private lazy var hoverHighlight = HoverHighlightView(
        dimmingAlpha: dimmingOverlayAlpha,
        borderWidth: borderWidth,
        tint: SelectionView.selectionTintCGColor
    )

    /// Settings: draw the hovered window's horizontal/vertical centre lines too.
    /// Off by default. Read by `OverlayWindowController` from the screenshot
    /// preferences when the overlay opens.
    var showsGuideCenterLines = false {
        didSet {
            guard showsGuideCenterLines != oldValue else { return }
            refreshSnapGuide()
        }
    }

    /// Snaps a dragged selection edge onto a window edge closer than
    /// `dragSnapDistance`. On by default; this is the one switch (the
    /// screenshot pane has no free height for another settings row, so it has
    /// no UI yet — see `evidence/patches/snap2-report.md`).
    var showsDragSnap = true

    /// Same-axis distance under which a dragged edge jumps onto a window edge.
    /// Strictly smaller than this: an edge 8pt away stays where the pointer
    /// put it.
    static let dragSnapDistance: CGFloat = 8

    /// The four edges of the box being dragged.
    private enum DragSnapEdge: CaseIterable {
        case left, right, bottom, top
    }

    /// Window rects (view coordinates) a dragged edge may glue to. Sampled once
    /// when the drag starts — the desktop is frozen while capturing, so the
    /// edges cannot move underneath the drag.
    private var dragSnapCandidates: [NSRect] = []
    /// The edges currently glued to a window edge (drives the highlight).
    private var dragSnappedEdges: Set<DragSnapEdge> = []

    /// The selection's chrome in its own layer (see `SelectionChromeView`).
    /// A drag writes this layer, so `draw(_:)` — and with it the frozen
    /// snapshot — is never invalidated while the pointer is down.
    private lazy var selectionChrome = SelectionChromeView(
        selectionView: self,
        dimmingAlpha: dimmingOverlayAlpha,
        borderWidth: borderWidth
    )

    /// The stronger line on a snapped drag edge (see `SnapHighlightView`).
    private let snapHighlight = SnapHighlightView()

    /// Evidence counters for the acceptance harness: how many times the hover
    /// target actually changed, and how many times the guide layer was written.
    /// Both are plain integers on the existing update path — no extra work.
    private(set) var hoverTargetChangeCount = 0
    private(set) var snapGuideWriteCount = 0
    /// How many times the selection chrome layer and the snapped-edge highlight
    /// were actually written. A drag writes the chrome; `draw(_:)` stays at 0.
    private(set) var selectionChromeWriteCount = 0
    private(set) var snapHighlightWriteCount = 0

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
    /// Breathing room kept between the capsule and the screen's left/right
    /// visible edges once it has to slide back inside them.
    private static let sizeLabelEdgeInset: CGFloat = 4
    // MARK: - Public

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        installSnapGuide()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installSnapGuide()
    }

    /// Adds the chrome/guide/highlight layers above the snapshot drawing.
    ///
    /// Stacking order, bottom to top: the selection chrome (dim + frame +
    /// handles + label), the hover highlight (idle only), the window outline
    /// and finally the snapped-edge highlight. Each stays hidden until its
    /// state owns it.
    private func installSnapGuide() {
        selectionChrome.frame = bounds
        selectionChrome.autoresizingMask = [.width, .height]
        addSubview(selectionChrome)
        snapGuide.isHidden = true
        hoverHighlight.frame = bounds
        hoverHighlight.autoresizingMask = [.width, .height]
        addSubview(hoverHighlight)
        addSubview(snapGuide)
        snapHighlight.frame = bounds
        snapHighlight.autoresizingMask = [.width, .height]
        addSubview(snapHighlight)
    }

    /// Keeps the full-overlay layers the same size as the overlay after a
    /// resize.
    private func layoutHoverHighlight() {
        if hoverHighlight.frame != bounds {
            hoverHighlight.frame = bounds
        }
        if selectionChrome.frame != bounds {
            selectionChrome.frame = bounds
        }
        if snapHighlight.frame != bounds {
            snapHighlight.frame = bounds
        }
    }

    /// Takes the hover highlight off screen without touching the snapshot.
    private func hideHoverHighlight() {
        guard !hoverHighlight.isHidden || !hoverHighlight.hoverRect.isNull else { return }
        hoverHighlight.isHidden = true
        hoverHighlight.hoverRect = .null
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // A clamped target is expressed in this view's coordinates, so a resize
        // re-states the guide against the new bounds.
        layoutHoverHighlight()
        refreshSnapGuide()
        refreshSelectionChrome()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshSnapGuide()
        refreshSelectionChrome()
    }

    var currentSelectionRect: NSRect? { selectionRect }

    func refreshHoverAtCurrentMouseLocation() {
        guard state == .idle, !selectionLocked, selectionInteractionEnabled else {
            clearHover()
            return
        }
        updateHover(screenPoint: NSEvent.mouseLocation)
    }

    // MARK: - Snap guide

    /// Positions (or hides) the guide for the current hover target.
    ///
    /// This is the only place the guide is written. It runs on the hover target
    /// change, on state changes that affect visibility, and on a frame resize —
    /// never on a plain pointer move. `SnapGuideView.place` early-returns while
    /// the target rect is unchanged, so hovering one window is zero work for the
    /// guide even if the pointer moves across it at 1000Hz.
    private func refreshSnapGuide() {
        let perfGuide = OverlayPerfSignpost.begin("snap-guide")
        defer { OverlayPerfSignpost.end("snap-guide", perfGuide) }
        let showsGuide = state == .idle
            && selectionInteractionEnabled
            && !scrollCaptureActive
            && !selectionLocked
            && hoverWindowRect != nil
        let rect = showsGuide ? (hoverWindowRect ?? .zero) : .zero

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if snapGuide.place(rect, visible: showsGuide, centerLines: showsGuideCenterLines) {
            snapGuideWriteCount += 1
        }
    }

    // MARK: - Selection chrome

    /// Positions (or hides) the selection chrome for the current state.
    ///
    /// This is the only place the chrome layer is written — never `draw(_:)`.
    /// It runs in a disabled-actions transaction and paints synchronously with
    /// `displayIfNeeded()`, so the box follows the pointer in this event and
    /// the frozen snapshot underneath is never invalidated by a drag.
    private func refreshSelectionChrome() {
        let rect: NSRect? = (state == .drawing || state == .selected) ? selectionRect : nil
        let showsHandles = state == .selected && selectionInteractionEnabled
        let label = showsHandles ? nil : (state == .selected ? selectionSizeLabelOverride : nil)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if selectionChrome.place(
            rect: rect,
            showsHandles: showsHandles,
            scrollCapture: scrollCaptureActive,
            sizeLabel: label
        ) {
            selectionChromeWriteCount += 1
        }
    }

    /// Writes the snapped-edge highlight: only the selection edges currently
    /// glued to a window edge, and only while a drag is running.
    private func refreshDragSnapHighlight() {
        let segments: [SnapHighlightView.Segment]
        if state == .drawing,
           let rect = selectionRect,
           !dragSnappedEdges.isEmpty,
           rect.width > 0 || rect.height > 0 {
            // Deterministic order, so an unchanged snap is zero writes.
            segments = DragSnapEdge.allCases.compactMap { edge -> SnapHighlightView.Segment? in
                guard dragSnappedEdges.contains(edge) else { return nil }
                switch edge {
                case .left:
                    return SnapHighlightView.Segment(
                        start: NSPoint(x: rect.minX, y: rect.minY),
                        end: NSPoint(x: rect.minX, y: rect.maxY)
                    )
                case .right:
                    return SnapHighlightView.Segment(
                        start: NSPoint(x: rect.maxX, y: rect.minY),
                        end: NSPoint(x: rect.maxX, y: rect.maxY)
                    )
                case .bottom:
                    return SnapHighlightView.Segment(
                        start: NSPoint(x: rect.minX, y: rect.minY),
                        end: NSPoint(x: rect.maxX, y: rect.minY)
                    )
                case .top:
                    return SnapHighlightView.Segment(
                        start: NSPoint(x: rect.minX, y: rect.maxY),
                        end: NSPoint(x: rect.maxX, y: rect.maxY)
                    )
                }
            }
        } else {
            segments = []
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if snapHighlight.place(segments) {
            snapHighlightWriteCount += 1
        }
    }

    // MARK: - Drag snapping

    /// Window rects (this view's coordinates) a dragged edge may snap to: the
    /// 8Hz cached window list plus the window hovered when the drag started.
    ///
    /// Sampling once per drag keeps the scan out of the mouse path: the
    /// desktop is frozen while capturing, so no window edge moves underneath
    /// a drag.
    private func dragSnapCandidatesForCurrentDrag() -> [NSRect] {
        var rects: [NSRect] = []
        if let hover = hoverWindowRect {
            rects.append(hover)
        }
        guard let detector = windowDetector,
              let displayFrame = window?.frame,
              let primary = NSScreen.screens.first else { return rects }
        let primaryHeight = primary.frame.height
        for detected in detector.cachedWindows
        where detected.isSelectableCaptureTarget && !detected.isProductChrome {
            let viewRect = Self.viewRect(
                forCGWindowFrame: detected.frame,
                displayFrame: displayFrame,
                primaryHeight: primaryHeight
            )
            let clamped = viewRect.intersection(bounds)
            guard !clamped.isNull, clamped.width > 1, clamped.height > 1 else { continue }
            rects.append(clamped)
        }
        return rects
    }

    /// Snaps every edge of `rect` that lies strictly closer than
    /// `dragSnapDistance` to a window edge on the same axis.
    ///
    /// Snapping only moves geometry: the committed capture is cropped from the
    /// pre-capture snapshot with the snapped rect, so the pixels follow the
    /// edge. An aspect-ratio-locked drag is left alone — gluing one edge there
    /// would silently break the ratio the user asked for.
    private func snappedDragRect(_ rect: NSRect) -> (rect: NSRect, edges: Set<DragSnapEdge>) {
        guard showsDragSnap, aspectRatio == nil, !dragSnapCandidates.isEmpty else {
            return (rect, [])
        }

        func nearestEdge(to value: CGFloat, vertical: Bool) -> CGFloat? {
            var best: CGFloat?
            var bestDistance = Self.dragSnapDistance
            for candidate in dragSnapCandidates {
                let edges = vertical
                    ? [candidate.minX, candidate.maxX]
                    : [candidate.minY, candidate.maxY]
                for edge in edges {
                    let distance = abs(edge - value)
                    if distance < bestDistance {
                        bestDistance = distance
                        best = edge
                    }
                }
            }
            return best
        }

        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY
        var snapped: Set<DragSnapEdge> = []
        if let target = nearestEdge(to: minX, vertical: true) {
            minX = target
            snapped.insert(.left)
        }
        if let target = nearestEdge(to: maxX, vertical: true) {
            maxX = target
            snapped.insert(.right)
        }
        if let target = nearestEdge(to: minY, vertical: false) {
            minY = target
            snapped.insert(.bottom)
        }
        if let target = nearestEdge(to: maxY, vertical: false) {
            maxY = target
            snapped.insert(.top)
        }
        // A box thinner than two snap distances can have both of its edges
        // pulled past each other; keep the raw axis in that case.
        if minX > maxX {
            minX = rect.minX
            maxX = rect.maxX
            snapped.remove(.left)
            snapped.remove(.right)
        }
        if minY > maxY {
            minY = rect.minY
            maxY = rect.maxY
            snapped.remove(.bottom)
            snapped.remove(.top)
        }
        guard !snapped.isEmpty else { return (rect, []) }
        return (
            NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            snapped
        )
    }

    func updateSelectionRect(_ rect: NSRect) {
        selectionRect = rect
        state = .selected
        refreshSelectionChrome()
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
        refreshSelectionChrome()
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
        refreshSelectionChrome()
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
            // The hovered window stays a snap candidate even though its
            // highlight clears while the box is dragged.
            dragSnapCandidates = dragSnapCandidatesForCurrentDrag()
            dragSnappedEdges = []
            pendingWindowRect = hoverWindowFullRect ?? hoverRect
            pendingWindowID = hoverWindowID
            hoverWindowRect = nil
            hoverWindowFullRect = nil
            hoverWindowID = nil
            // The highlight is a layer of its own, so clearing the target has
            // to hide it here too: `draw(_:)` no longer reads `hoverWindowRect`
            // and would keep the stale dimming/border/label on screen.
            hideHoverHighlight()
            selectionOrigin = point
            dragStart = point
            selectionRect = NSRect(origin: point, size: .zero)
            state = .drawing
            dragAction = .drawNew
            delegate?.selectionDidStart(reason: .newSelection)
            refreshSelectionChrome()
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

        // Start drawing new selection. The snap candidates are sampled once
        // here: the 8Hz cached window list plus the window under the pointer.
        dragSnapCandidates = dragSnapCandidatesForCurrentDrag()
        dragSnappedEdges = []
        selectionOrigin = point
        selectionRect = NSRect(origin: point, size: .zero)
        state = .drawing
        dragAction = .drawNew
        delegate?.selectionDidStart(reason: .newSelection)
        refreshSelectionChrome()
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
        let perfEvent = OverlayPerfSignpost.begin("event-dragged")
        defer { OverlayPerfSignpost.end("event-dragged", perfEvent) }
        guard selectionInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)

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
            // Geometry only: the snapped edges are written into the box and
            // highlighted on the guide layer. `draw(_:)` is not invalidated,
            // so the frozen snapshot is not re-blitted while dragging.
            let dragged = SelectionView.dragRect(
                from: selectionOrigin,
                to: point,
                aspectRatio: aspectRatio,
                bounds: bounds
            )
            let snapped = snappedDragRect(dragged)
            selectionRect = snapped.rect
            dragSnappedEdges = snapped.edges
            refreshSelectionChrome()
            refreshDragSnapHighlight()

        case .move:
            NSCursor.arrow.set()
            guard let _ = selectionRect else { return }
            let dx = point.x - dragStart.x
            let dy = point.y - dragStart.y
            var newRect = dragOriginalRect.offsetBy(dx: dx, dy: dy)
            newRect = clampedForMove(newRect)
            selectionRect = newRect
            delegate?.selectionDidChange(rect: newRect, inView: self)
            refreshSelectionChrome()

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
            refreshSelectionChrome()

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
            // The editor hand-off can switch interaction off mid-gesture; the
            // snap highlight still must not outlive this mouse-up.
            dragSnappedEdges = []
            dragSnapCandidates = []
            refreshDragSnapHighlight()
            NSCursor.arrow.set()
            return
        }
        defer {
            dragAction = .none
            // A snapped-edge highlight never outlives the drag that made it.
            dragSnappedEdges = []
            dragSnapCandidates = []
            refreshDragSnapHighlight()
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
                refreshSelectionChrome()
                return
            }
            guard let rect = selectionRect, rect.width >= 5, rect.height >= 5 else {
                selectionRect = nil
                state = .idle
                refreshSelectionChrome()
                return
            }
            state = .selected
            delegate?.selectionDidComplete(rect: rect, inView: self, isWindowSelection: false, windowID: nil)
            refreshSelectionChrome()

        case .move, .resize:
            if let rect = selectionRect {
                delegate?.selectionDidComplete(rect: rect, inView: self, isWindowSelection: false, windowID: nil)
            }
            refreshSelectionChrome()

        case .none:
            break
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let perfEvent = OverlayPerfSignpost.begin("event-moved")
        defer { OverlayPerfSignpost.end("event-moved", perfEvent) }
        guard selectionInteractionEnabled else { return }
        let point = convert(event.locationInWindow, from: nil)

        // In idle state, detect windows under cursor for hover highlight.
        if state == .idle && !selectionLocked {
            // capcap may lose activation over time, which causes WindowServer
            // to ignore the crosshair cursor rect registered in resetCursorRects.
            // One retry per session is enough: the overlay claims activation
            // when it is presented, and a per-event activation attempt costs a
            // full activation round trip on *every* pointer move.
            if mayActivateAppForCursor, !didAttemptCursorReactivation, !NSApp.isActive {
                didAttemptCursorReactivation = true
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
        updateCursor(at: point)
        if state == .idle && !selectionLocked {
            updateWindowHover(with: event)
        }
    }

    override func mouseExited(with event: NSEvent) {
        // The pointer left this display: hide the guide immediately. The guide
        // is per-screen, so no other overlay is waiting for a broadcast.
        clearHover()
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
        updateHover(screenPoint: screenPoint)
    }

    /// Resolves the window under `screenPoint` and re-targets the guide.
    ///
    /// Internal so the acceptance harness can drive the production maths with
    /// injected window frames (no pointer synthesis).
    ///
    /// Multi-display contract: `screenPoint` must belong to *this* overlay's
    /// display — that is the "each display snaps on its own, nothing bleeds
    /// across screens" rule. The CG→AppKit Y flip is done once, in global
    /// coordinates, against the primary display's height (the origin of both
    /// coordinate systems), so a window centre on any display lands correctly.
    func updateHover(screenPoint: NSPoint) {
        let perfHover = OverlayPerfSignpost.begin("hover-update")
        defer { OverlayPerfSignpost.end("hover-update", perfHover) }
        guard state == .idle, !selectionLocked, selectionInteractionEnabled else {
            clearHover()
            return
        }
        guard let detector = windowDetector,
              let displayFrame = window?.frame,
              let primary = NSScreen.screens.first else {
            clearHover()
            return
        }
        guard displayFrame.contains(screenPoint) else {
            clearHover()
            return
        }

        // CG's origin is the top-left of the primary display (y down); AppKit's
        // is its bottom-left (y up). One global flip handles every display.
        let cgPoint = CGPoint(x: screenPoint.x, y: primary.frame.height - screenPoint.y)
        guard let detected = detector.windowAt(cgPoint: cgPoint) else {
            clearHover()
            return
        }

        let viewRect = Self.viewRect(
            forCGWindowFrame: detected.frame,
            displayFrame: displayFrame,
            primaryHeight: primary.frame.height
        )
        // Clamp to view bounds: a window partly off-screen is still the target,
        // but only its visible part can be outlined.
        let clamped = viewRect.intersection(bounds)
        guard !clamped.isNull, clamped.width > 1, clamped.height > 1 else {
            clearHover()
            return
        }

        // The source of "snaps like a shadow": the hit test above is a scan of
        // the 8Hz cached window list (no enumeration), and everything below is
        // skipped while the target window and its rect stay the same.
        guard clamped != hoverWindowRect
            || viewRect != hoverWindowFullRect
            || hoverWindowID != detected.windowID else {
            // Same target: nothing to push to the delegate or the guide. The
            // highlight layer can still be off screen though — only the idle
            // state owns it — so bring it back for this rect.
            if hoverHighlight.isHidden {
                layoutHoverHighlight()
                hoverHighlight.isHidden = false
                hoverHighlight.hoverRect = clamped
                hoverHighlight.needsDisplay = true
            }
            return
        }
        hoverWindowRect = clamped
        hoverWindowFullRect = viewRect
        hoverWindowID = detected.windowID
        hoverTargetChangeCount += 1
        delegate?.selectionDidHoverWindow(detected)
        // The highlight is its own layer: writing it repaints the dim, the
        // border and the label only — the snapshot underneath is untouched.
        layoutHoverHighlight()
        hoverHighlight.isHidden = false
        hoverHighlight.hoverRect = clamped
        refreshSnapGuide()
    }

    /// CG window frame → this overlay's view coordinates.
    private static func viewRect(
        forCGWindowFrame frame: CGRect,
        displayFrame: NSRect,
        primaryHeight: CGFloat
    ) -> NSRect {
        // Flip against the primary display's height, then subtract the display
        // origin: the window's own display never enters the maths, which is why
        // a display above or left of the primary cannot invert the result.
        let appKitY = primaryHeight - frame.origin.y - frame.height
        return NSRect(
            x: frame.origin.x - displayFrame.origin.x,
            y: appKitY - displayFrame.origin.y,
            width: frame.width,
            height: frame.height
        )
    }

    private func clearHover() {
        guard hoverWindowRect != nil else {
            // Nothing hovered. The only work left is clearing a guide that a
            // state change left visible; when there is none, return without
            // opening a CATransaction on every pointer move over blank desktop.
            guard !snapGuide.isHidden else { return }
            refreshSnapGuide()
            return
        }
        hoverWindowRect = nil
        hoverWindowFullRect = nil
        hoverWindowID = nil
        delegate?.selectionDidHoverWindow(nil)
        hideHoverHighlight()
        refreshSnapGuide()
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let perfDraw = OverlayPerfSignpost.begin("snapshot-draw")
        defer { OverlayPerfSignpost.end("snapshot-draw", perfDraw) }
        defer {
            reportFirstDrawIfNeeded()
            scheduleFirstFramePresentationIfNeeded()
        }

        // The frozen desktop is the only thing this view draws now. The
        // selection chrome (`SelectionChromeView`), the window-hover highlight
        // (`HoverHighlightView`) and the snap guide/highlight are all layer
        // subviews, so dragging the box, snapping an edge, crossing a window
        // or moving inside one never re-blits this snapshot: every one of
        // those updates is a geometry/path write on a layer.
        //
        // Skip during scroll capture so live scrolling content shows through.
        if let snapshot = backgroundSnapshot, !scrollCaptureActive {
            snapshot.draw(in: bounds)
        }
    }

    /// The one painter for the selection frame and its resize handles.
    ///
    /// `SelectionChromeView` (the capture overlay's chrome layer) uses it; the
    /// editor's `SelectionChromeOverlay` (which sits above the editor canvas so
    /// the handles stay visible even when beautify expands the frame) calls it
    /// too. Both phases therefore paint the same chrome — a 1pt solid frame,
    /// 20×4pt edge bars and 12×2pt corner brackets — instead of each keeping a
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
            Self.drawSizeLabel(context: context, rect: rect, text: sizeLabel, in: self)
        } else if let sizeLabel {
            Self.drawSizeLabel(context: context, rect: rect, text: sizeLabel, in: self)
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

    /// Attributes for the capsule's text, kept in one place so measuring and
    /// drawing cannot drift apart.
    private static var sizeLabelAttributes: [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        ]
    }

    /// Capsule size for one label text, content padding included.
    static func sizeLabelSize(for text: String) -> NSSize {
        let size = text.size(withAttributes: sizeLabelAttributes)
        return NSSize(
            width: size.width + sizeLabelPadding.width * 2,
            height: size.height + sizeLabelPadding.height * 2
        )
    }

    /// The screen's `visibleFrame` (menu bar and Dock excluded) expressed in
    /// `view`'s coordinates, or `nil` when there is no screen to clamp to.
    ///
    /// The capture overlay and the editor's live chrome both live in a window
    /// on one display, so `view.window.screen` is the screen the label is
    /// drawn on; `NSScreen.main` is the fallback when the window has no screen
    /// yet. A view without a window has no coordinate mapping, so its own
    /// coordinates are treated as screen coordinates.
    static func sizeLabelVisibleFrame(in view: NSView?) -> NSRect? {
        guard let screen = view?.window?.screen ?? NSScreen.main else { return nil }
        guard let view, let window = view.window else { return screen.visibleFrame }
        let inWindow = window.convertFromScreen(screen.visibleFrame)
        return view.convert(inWindow, from: nil)
    }

    /// The capsule rect in `view`'s coordinates, clamped to the screen's
    /// `visibleFrame`.
    ///
    /// Default placement stays "outside the top-left corner": 8pt above the
    /// selection with the left edges aligned. Three rules keep it visible:
    /// 1. when the selection hugs the top of the screen there is no room
    ///    above, so the capsule flips below it (8pt outside);
    /// 2. horizontally it slides back inside, keeping a 4pt margin on each
    ///    side when the screen is wide enough;
    /// 3. when neither side fits (a tall selection on a small display) it is
    ///    allowed to sit over the selection, but never outside the screen.
    ///
    /// Text, padding, radius and gap are untouched — only the origin moves.
    static func sizeLabelRect(for rect: NSRect, in view: NSView?, text: String? = nil) -> NSRect {
        let size = sizeLabelSize(for: text ?? SelectionView.sizeLabelText(for: rect))
        var label = NSRect(
            x: rect.minX,
            y: rect.maxY + sizeLabelGap,
            width: size.width,
            height: size.height
        )
        guard let visible = sizeLabelVisibleFrame(in: view) else { return label }

        // 2) Horizontal slide. With room, the capsule keeps 4pt off both
        // screen edges; a screen narrower than the capsule pins its left edge.
        let leftLimit = visible.minX + sizeLabelEdgeInset
        let rightLimit = visible.maxX - sizeLabelEdgeInset - size.width
        if rightLimit >= leftLimit {
            label.origin.x = min(max(rect.minX, leftLimit), rightLimit)
        } else {
            // Too narrow for the 4pt margins: keep the capsule inside anyway,
            // and only when it is wider than the screen itself pin its left
            // edge (a capsule cannot be split).
            let insideRight = visible.maxX - size.width
            label.origin.x = insideRight >= visible.minX
                ? min(max(rect.minX, visible.minX), insideRight)
                : visible.minX
        }

        // 1) + 3) Vertical: above, else below, else over the selection.
        let fitsAbove = rect.maxY + sizeLabelGap <= visible.maxY - size.height
        let fitsBelow = rect.minY - sizeLabelGap - size.height >= visible.minY
        if fitsAbove {
            label.origin.y = rect.maxY + sizeLabelGap
        } else if fitsBelow {
            label.origin.y = rect.minY - sizeLabelGap - size.height
        } else if visible.maxY - size.height >= visible.minY {
            // Extreme case: nowhere outside. Pin the capsule inside the visible
            // frame (it overlaps the selection, but stays fully on screen).
            label.origin.y = min(max(rect.maxY + sizeLabelGap, visible.minY),
                                 visible.maxY - size.height)
        } else {
            // Screen shorter than the capsule: no position satisfies both
            // edges; keep the top-left corner on screen and let the shape
            // itself spill, which is the only remaining option.
            label.origin.y = visible.minY
        }
        return label
    }

    private static func sizeLabelText(for rect: NSRect) -> String {
        // Same multiplication sign as the rest of the app's size badges
        // (`ReplicaImagePreviewContent`, `PanelViews`, `ReplicaCanonicalCardContent`).
        "\(Int(rect.width)) × \(Int(rect.height))"
    }

    static func drawSizeLabel(context: CGContext, rect: NSRect, text: String? = nil, in view: NSView?) {
        let text = text ?? SelectionView.sizeLabelText(for: rect)
        let attrs = SelectionView.sizeLabelAttributes
        let size = text.size(withAttributes: attrs)
        let padding = SelectionView.sizeLabelPadding
        // Chrome, not content: the capsule is drawn outside the selection
        // whenever it fits, and clamped to the screen's visibleFrame so a
        // selection hugging an edge never crops it. See `sizeLabelRect`.
        let labelRect = SelectionView.sizeLabelRect(for: rect, in: view, text: text)

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
