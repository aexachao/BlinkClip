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

    private var state: State = .idle
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
            }
        }
    }

    // Scroll capture mode: update border styling while the controller manages event routing.
    var scrollCaptureActive = false

    // When false, the selection frame becomes a fixed viewport.
    var selectionInteractionEnabled = true {
        didSet {
            if selectionInteractionEnabled != oldValue {
                refreshCursorRects()
                needsDisplay = true
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
    /// The same point in this view's coordinates. Cached because invalidating
    /// the previous hairline needs it after the pointer has already moved on.
    private var crosshairLocalPoint: NSPoint?
    /// Set by `OverlayWindowController`: a pointer move seen by one display's
    /// overlay is mirrored to the overlays of every other display.
    var onCrosshairMoved: ((NSPoint) -> Void)?

    // MARK: - Constants

    /// Capture chrome tint: the product accent (system blue), aliased to the one
    /// shared constant so the overlay, the editor's selection chrome and the
    /// magnifier lens cannot drift apart. The colour itself is defined once in
    /// `UI/SelectionAccent.swift`; there is no second literal here.
    private static let selectionTint: NSColor = selectionAccent
    private static let selectionTintCGColor: CGColor = selectionTint.cgColor
    private let handleSize: CGFloat = 8
    private let handleHitSize: CGFloat = 12
    private let borderWidth: CGFloat = 2.0
    private let dimmingOverlayAlpha: CGFloat = 0.45
    /// Size label geometry: 10x6 content padding, 6pt radius, 8pt above the frame
    /// (6pt let the capsule crowd the top-left handle).
    private static let sizeLabelPadding = NSSize(width: 10, height: 6)
    private static let sizeLabelCornerRadius: CGFloat = 6
    private static let sizeLabelGap: CGFloat = 8
    /// Crosshair: a 1pt white hairline at 42% over a 2pt dark halo, so the lines
    /// read on both a light and a dark desktop without becoming harsh.
    private static let crosshairCoreAlpha: CGFloat = 0.42
    private static let crosshairHaloAlpha: CGFloat = 0.35

    // MARK: - Public

    var currentSelectionRect: NSRect? { selectionRect }

    func refreshHoverAtCurrentMouseLocation() {
        guard state == .idle, !selectionLocked else { return }
        updateWindowHover(screenPoint: NSEvent.mouseLocation)
    }

    // MARK: - Crosshair

    /// Mirrors the pointer (screen coordinates) into this overlay and repaints
    /// only the two hairline bands, so a full-screen snapshot is not redrawn
    /// for every mouse event. `nil` hides the crosshair.
    func updateCrosshair(globalPoint: NSPoint?) {
        let previousLocal = crosshairLocalPoint
        crosshairScreenPoint = globalPoint
        crosshairLocalPoint = globalPoint.flatMap(localPoint(forScreenPoint:))
        invalidateCrosshairBands(at: previousLocal)
        invalidateCrosshairBands(at: crosshairLocalPoint)
    }

    /// Hides the crosshair without touching the pointer bookkeeping used by
    /// the drag itself (mouse-exit on the display holding the pointer).
    private func hideCrosshair() {
        guard crosshairScreenPoint != nil || crosshairLocalPoint != nil else { return }
        let previousLocal = crosshairLocalPoint
        crosshairScreenPoint = nil
        crosshairLocalPoint = nil
        invalidateCrosshairBands(at: previousLocal)
    }

    private func localPoint(forScreenPoint point: NSPoint) -> NSPoint? {
        guard let window else { return nil }
        return convert(window.convertPoint(fromScreen: point), from: nil)
    }

    /// Invalidates a 4pt band around each line so the redraw covers both the
    /// lateral anti-aliasing and the 2pt halo.
    private func invalidateCrosshairBands(at point: NSPoint?) {
        guard let point else { return }
        let halfBand: CGFloat = 4
        let bands = [
            NSRect(x: bounds.minX, y: point.y - halfBand, width: bounds.width, height: halfBand * 2),
            NSRect(x: point.x - halfBand, y: bounds.minY, width: halfBand * 2, height: bounds.height)
        ]
        for band in bands {
            let clipped = band.intersection(bounds)
            if !clipped.isNull, !clipped.isEmpty {
                setNeedsDisplay(clipped)
            }
        }
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
                    x: position.x - handleHitSize / 2,
                    y: position.y - handleHitSize / 2,
                    width: handleHitSize,
                    height: handleHitSize
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
            // Solid accent border
            context.setStrokeColor(SelectionView.selectionTintCGColor)
            context.setLineWidth(borderWidth + 1)
            context.setLineDash(phase: 0, lengths: [])
            context.stroke(hoverRect.insetBy(dx: -1.5, dy: -1.5))
            // Size label
            SelectionView.drawSizeLabel(context: context, rect: hoverRect)
            drawCrosshair(context: context)
            return
        }

        // In idle state with no selection, just show the snapshot (already drawn above)
        guard let rect = selectionRect, (state == .drawing || state == .selected),
              rect.width > 0 || rect.height > 0 else {
            drawCrosshair(context: context)
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
            let strokeWidth: CGFloat = borderWidth + 1
            let outerInset = -(strokeWidth / 2 + 1)
            context.setStrokeColor(NSColor.systemRed.cgColor)
            context.setLineWidth(strokeWidth)
            context.stroke(rect.insetBy(dx: outerInset, dy: outerInset))
        } else {
            context.setStrokeColor(SelectionView.selectionTintCGColor)
            context.setLineWidth(borderWidth)
            context.setLineDash(phase: 0, lengths: [])
            context.stroke(rect.insetBy(dx: -1, dy: -1))
        }

        drawCrosshair(context: context)

        if state == .selected && selectionInteractionEnabled {
            // Draw 8 control handles
            drawHandles(context: context, rect: rect)
            // Draw size label
            SelectionView.drawSizeLabel(context: context, rect: rect)
        } else if state == .selected, let selectionSizeLabelOverride {
            SelectionView.drawSizeLabel(context: context, rect: rect, text: selectionSizeLabelOverride)
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

    private func drawHandles(context: CGContext, rect: NSRect) {
        let positions = SelectionView.handlePositions(for: rect)
        for pos in positions {
            let handleRect = NSRect(
                x: pos.x - handleSize / 2,
                y: pos.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.setFillColor(SelectionView.selectionTintCGColor)
            context.fillEllipse(in: handleRect)
        }
    }

    /// Draws the full-width/full-height pointer guides. The lines are driven by
    /// a screen-space point, so on a multi-display desktop every overlay draws
    /// the same crossing: displays side by side continue the horizontal line,
    /// while the vertical line only lands on the display holding the pointer.
    /// Only `.idle` and `.drawing` show them; a committed frame hides them.
    private func drawCrosshair(context: CGContext) {
        guard state == .idle || state == .drawing,
              selectionInteractionEnabled,
              !scrollCaptureActive,
              !selectionLocked,
              let point = crosshairLocalPoint
        else { return }

        // Snap the hairline centre to a device pixel edge: on a 2x display a
        // 1pt stroke then covers exactly two pixels instead of two blurred ones.
        let scale = window?.backingScaleFactor ?? 2
        let x = (point.x * scale).rounded() / scale
        let y = (point.y * scale).rounded() / scale
        let showsHorizontal = bounds.minY...bounds.maxY ~= y
        let showsVertical = bounds.minX...bounds.maxX ~= x
        guard showsHorizontal || showsVertical else { return }

        func addLines() {
            if showsHorizontal {
                context.move(to: CGPoint(x: bounds.minX, y: y))
                context.addLine(to: CGPoint(x: bounds.maxX, y: y))
            }
            if showsVertical {
                context.move(to: CGPoint(x: x, y: bounds.minY))
                context.addLine(to: CGPoint(x: x, y: bounds.maxY))
            }
        }

        context.saveGState()
        defer { context.restoreGState() }
        context.setLineDash(phase: 0, lengths: [])
        context.setLineCap(.butt)
        // Dark halo first, then the white core: on a light desktop the halo
        // carries the contrast, on a dark one the white core does.
        context.setStrokeColor(NSColor.black.withAlphaComponent(SelectionView.crosshairHaloAlpha).cgColor)
        context.setLineWidth(2)
        addLines()
        context.strokePath()
        context.setStrokeColor(NSColor.white.withAlphaComponent(SelectionView.crosshairCoreAlpha).cgColor)
        context.setLineWidth(1)
        addLines()
        context.strokePath()
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
        SelectionView.hitTestHandle(point: point, rect: rect, hitSize: handleHitSize)
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
