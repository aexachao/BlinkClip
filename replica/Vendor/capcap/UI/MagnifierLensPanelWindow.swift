import AppKit
import CoreText
import QuartzCore

private enum MagnifierLensPanelLayout {
    static let panelWidth: CGFloat = 148
    static let infoRowHeight: CGFloat = 18
    static let infoGroupSpacing: CGFloat = 4
    static let infoVerticalInset: CGFloat = 8
    static let cornerRadius: CGFloat = 8
}

/// Cursor-adjacent magnifier color picker shown on the overlay's idle state.
///
/// Replaces the legacy "drag to screenshot" cursor chip while the user has not
/// yet started dragging a selection rectangle. Displays absolute desktop
/// coordinates, a magnification of the pixel neighborhood around the cursor,
/// and the current pixel value in either HEX or RGB. Listens for mouse-move
/// events to follow the cursor but never blocks input. Visual values are read
/// from `Defaults`, whose fallback values define the built-in lens style.
final class MagnifierLensPanelWindow: NSPanel {

    enum Format {
        case hex
        case rgb
    }

    /// Single-pixel sRGB sample. Channels are 0-255 integers.
    struct Sample: Equatable {
        let r: Int
        let g: Int
        let b: Int
    }

    private static let edgeMargin: CGFloat = 8

    /// Computes the panel size that fits the full-width square magnifier plus
    /// 5 info rows, or 3 rows when optional hints are disabled.
    private static func computePanelSize() -> NSSize {
        let infoRows = 3
            + (Defaults.magnifierLensPanelShowCopyHint ? 1 : 0)
            + (Defaults.magnifierLensPanelShowFormatHint ? 1 : 0)
        let infoHeight = CGFloat(infoRows) * MagnifierLensPanelLayout.infoRowHeight
            + MagnifierLensPanelLayout.infoGroupSpacing
            + MagnifierLensPanelLayout.infoVerticalInset * 2
        let width = MagnifierLensPanelLayout.panelWidth
        let height = width + infoHeight
        return NSSize(width: ceil(width), height: ceil(height))
    }

    /// How often the lens may redraw (and re-sample) while the pointer moves.
    ///
    /// The pointer delivers events at the display's rate (60–120Hz, more for a
    /// high-polling-rate mouse). Re-sampling the pixel and repainting the whole
    /// panel on *every* one of those events was the most expensive thing the
    /// idle overlay did. The lens is a static swatch that follows the pointer, so
    /// 30Hz is visually indistinguishable while costing a quarter of the work.
    /// A trailing update guarantees the final position of a movement is applied.
    static let contentRefreshInterval: TimeInterval = 1.0 / 30.0

    private let lensView: MagnifierLensPanelView
    private let panelSize: NSSize

    /// Latest request from the overlay's pointer stream. Coalesced into one
    /// `applyPendingUpdate()` per `contentRefreshInterval`.
    private struct PendingUpdate {
        var snapshot: CGImage?
        var screenFrame: NSRect = .zero
        var mouseLocation: NSPoint = .zero
        var format: Format = .hex
    }

    private var pendingUpdate: PendingUpdate?
    private var trailingRefresh: DispatchWorkItem?
    private var lastAppliedTime: CFTimeInterval = 0
    private var lastAppliedPixelPoint: CGPoint?
    private var lastAppliedScreenFrame: NSRect = .zero
    private var lastAppliedFormat: Format = .hex

    init() {
        let size = Self.computePanelSize()
        self.panelSize = size
        self.lensView = MagnifierLensPanelView(frame: NSRect(origin: .zero, size: size))
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver + 1
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        sharingType = .none
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = lensView
    }

    deinit {
        cancelPendingRefresh()
    }

    func show() {
        orderFrontRegardless()
        updatePosition()
    }

    func dismiss() {
        cancelPendingRefresh()
        pendingUpdate = nil
        MagnifierLensPanelSampler.releaseCachedPixels()
        orderOut(nil)
    }

    /// Records the latest pointer state. The actual sample + repaint happens at
    /// most `contentRefreshInterval` times a second (see `applyPendingUpdate`),
    /// so a 120–1000Hz pointer stream cannot drive the lens that often.
    func update(
        snapshot: CGImage?,
        screenFrame: NSRect,
        mouseLocation: NSPoint,
        format: Format
    ) {
        pendingUpdate = PendingUpdate(
            snapshot: snapshot,
            screenFrame: screenFrame,
            mouseLocation: mouseLocation,
            format: format
        )
        scheduleRefreshIfNeeded()
    }

    func setFormat(_ format: Format) {
        lensView.format = format
    }

    func refreshDisplay() {
        lensView.needsDisplay = true
    }

    /// Returns the current sample and pixel location the lens is displaying.
    /// Used by the overlay controller to perform the actual copy on ⌘+C.
    var currentSample: Sample? { lensView.currentSample }
    var currentPixelPoint: CGPoint { lensView.currentPixelPoint }

    // MARK: - Refresh cadence

    /// Runs `applyPendingUpdate` now when the last one is older than the
    /// interval, otherwise schedules exactly one trailing update.
    private func scheduleRefreshIfNeeded() {
        guard pendingUpdate != nil else { return }
        let elapsed = CACurrentMediaTime() - lastAppliedTime
        if elapsed >= Self.contentRefreshInterval {
            trailingRefresh?.cancel()
            trailingRefresh = nil
            applyPendingUpdate()
            return
        }
        guard trailingRefresh == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.trailingRefresh = nil
            self.applyPendingUpdate()
        }
        trailingRefresh = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + (Self.contentRefreshInterval - elapsed),
            execute: work
        )
    }

    private func cancelPendingRefresh() {
        trailingRefresh?.cancel()
        trailingRefresh = nil
    }

    private func applyPendingUpdate() {
        guard let pending = pendingUpdate else { return }
        pendingUpdate = nil
        lastAppliedTime = CACurrentMediaTime()

        guard let snapshot = pending.snapshot else {
            lensView.clear()
            lastAppliedPixelPoint = nil
            updatePosition()
            return
        }
        let pixelPoint = MagnifierLensPanelSampler.pixelCoordinate(
            globalPoint: pending.mouseLocation,
            screenFrame: pending.screenFrame,
            snapshotSize: CGSize(width: snapshot.width, height: snapshot.height)
        )
        // The panel sits below/right of the pointer and does not cover it, so a
        // still pointer means an identical sample: keep the painted frame and
        // only make sure the panel is where it belongs.
        let sampleUnchanged = pixelPoint == lastAppliedPixelPoint
            && pending.screenFrame == lastAppliedScreenFrame
            && pending.format == lastAppliedFormat
        guard !sampleUnchanged else {
            updatePosition()
            return
        }
        let sample = MagnifierLensPanelSampler.sample(image: snapshot, at: pixelPoint)
            ?? Sample(r: 0, g: 0, b: 0)
        lastAppliedPixelPoint = pixelPoint
        lastAppliedScreenFrame = pending.screenFrame
        lastAppliedFormat = pending.format
        lensView.update(
            sample: sample,
            pixelPoint: pixelPoint,
            mouseLocation: pending.mouseLocation,
            snapshot: snapshot,
            screenFrame: pending.screenFrame,
            format: pending.format
        )
        updatePosition()
    }

    private func updatePosition() {
        let loc = NSEvent.mouseLocation
        let offsetX = CGFloat(Defaults.magnifierLensPanelOffsetX)
        let offsetY = CGFloat(Defaults.magnifierLensPanelOffsetY)
        // Default: panel sits directly below the cursor. AppKit panel origin
        // is the bottom-left corner, so panel.top = origin.y + height →
        // origin.y = cursor.y - offsetY - height.
        var origin = NSPoint(
            x: loc.x + offsetX,
            y: loc.y - offsetY - panelSize.height
        )
        if let screen = NSScreen.screens.first(where: { screen in
            let f = screen.frame
            return loc.x >= f.minX && loc.x <= f.maxX
                && loc.y >= f.minY && loc.y <= f.maxY
        }) {
            let frame = screen.frame
            let panelRight = origin.x + panelSize.width
            if panelRight > frame.maxX - Self.edgeMargin {
                origin.x = loc.x - offsetX - panelSize.width
            }
            if origin.y < frame.minY + Self.edgeMargin {
                origin.y = loc.y + offsetY
            }
        }
        setFrameOrigin(origin)
    }
}

/// Pure helpers for reading a single pixel from a `CGImage` and mapping a
/// global mouse location onto the image's coordinate space. Kept as a free
/// namespace so unit tests can exercise them without an `NSPanel`.
enum MagnifierLensPanelSampler {

    /// Maps an AppKit global mouse location (y-up) onto the CGImage coordinate
    /// space (y-down) of the supplied snapshot, accounting for the screen's
    /// pixel-to-point scale factor.
    static func pixelCoordinate(
        globalPoint: NSPoint,
        screenFrame: NSRect,
        snapshotSize: CGSize
    ) -> CGPoint {
        let scaleX = snapshotSize.width / max(screenFrame.width, 1)
        let scaleY = snapshotSize.height / max(screenFrame.height, 1)
        let xInScreen = ((globalPoint.x - screenFrame.origin.x) * scaleX).rounded()
        let yInScreenFromTop = ((screenFrame.maxY - globalPoint.y) * scaleY).rounded()
        let maxX = max(0, snapshotSize.width - 1)
        let maxY = max(0, snapshotSize.height - 1)
        return CGPoint(
            x: min(max(0, xInScreen), maxX),
            y: min(max(0, yInScreenFromTop), maxY)
        )
    }

    /// Samples a single pixel from `image` at `point` (CGImage coords). Returns
    /// `nil` if the point lies outside the image bounds or the context cannot
    /// be allocated.
    ///
    /// The snapshot is decoded into one cached RGBA8 buffer per image, so a
    /// sample is an array index. The previous implementation drew the *whole*
    /// snapshot into a 1×1 context to read a single pixel, which re-rasterised
    /// ~7 million pixels per pointer event (see `applyPendingUpdate`).
    static func sample(image: CGImage, at point: CGPoint) -> MagnifierLensPanelWindow.Sample? {
        guard point.x >= 0, point.y >= 0,
              point.x < CGFloat(image.width),
              point.y < CGFloat(image.height) else {
            return nil
        }
        guard decodeIfNeeded(image: image) else { return nil }
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, x < cachedWidth, y >= 0, y < cachedHeight else { return nil }
        let offset = (y * cachedWidth + x) * 4
        return MagnifierLensPanelWindow.Sample(
            r: Int(cachedPixels[offset]),
            g: Int(cachedPixels[offset + 1]),
            b: Int(cachedPixels[offset + 2])
        )
    }

    // MARK: - Snapshot decode cache

    /// The image the cache belongs to. Reference identity is the right test:
    /// the overlay hands the same `CGImage` over for every pointer event of a
    /// session and only replaces it when a new snapshot lands.
    private static var cachedImage: CGImage?
    private static var cachedPixels: [UInt8] = []
    private static var cachedWidth = 0
    private static var cachedHeight = 0

    /// Drops the decoded buffer. Called when the lens is dismissed so a 30MB
    /// snapshot copy never outlives the capture session.
    static func releaseCachedPixels() {
        cachedImage = nil
        cachedPixels = []
        cachedWidth = 0
        cachedHeight = 0
    }

    /// Decodes `image` 1:1 into a device-RGB premultiplied buffer, once per
    /// snapshot. Returns false when the buffer cannot be allocated.
    private static func decodeIfNeeded(image: CGImage) -> Bool {
        if let cachedImage, cachedImage === image { return true }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return false }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let decoded = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard decoded else { return false }
        cachedImage = image
        cachedPixels = pixels
        cachedWidth = width
        cachedHeight = height
        return true
    }

    /// Picks the dark- or light-mode background color according to the user's
    /// `followSystemAppearance` preference. Pass `effectiveAppearance` from
    /// the view that needs to draw so this works regardless of AppKit quirks.
    static func backgroundColor(forAppearance appearance: NSAppearance) -> NSColor {
        if Defaults.magnifierLensPanelFollowSystemAppearance {
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) == .darkAqua
            return isDark ? darkBackgroundColor() : lightBackgroundColor()
        }
        return darkBackgroundColor()
    }

    static func darkBackgroundColor() -> NSColor {
        NSColor(
            srgbRed: CGFloat(Defaults.magnifierLensPanelDarkBackgroundRed),
            green: CGFloat(Defaults.magnifierLensPanelDarkBackgroundGreen),
            blue: CGFloat(Defaults.magnifierLensPanelDarkBackgroundBlue),
            alpha: CGFloat(Defaults.magnifierLensPanelDarkBackgroundAlpha)
        )
    }

    static func lightBackgroundColor() -> NSColor {
        NSColor(
            srgbRed: CGFloat(Defaults.magnifierLensPanelLightBackgroundRed),
            green: CGFloat(Defaults.magnifierLensPanelLightBackgroundGreen),
            blue: CGFloat(Defaults.magnifierLensPanelLightBackgroundBlue),
            alpha: CGFloat(Defaults.magnifierLensPanelLightBackgroundAlpha)
        )
    }
}

final class MagnifierLensPanelView: NSView {

    var format: MagnifierLensPanelWindow.Format = .hex {
        didSet { needsDisplay = true }
    }

    private(set) var currentSample: MagnifierLensPanelWindow.Sample?
    private(set) var currentPixelPoint: CGPoint = .zero
    private var mouseLocation: NSPoint = .zero
    private var snapshot: CGImage?
    private var screenFrame: NSRect = .zero

    // Layout
    private let infoLeftPadding: CGFloat = 10
    private let infoRightPadding: CGFloat = 10
    private let infoColumnGap: CGFloat = 6
    private let colorSwatchGap: CGFloat = 6

    private static let labelFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private static let tipFont = NSFont.systemFont(ofSize: 10.5, weight: .regular)
    /// Fixed slot sized from the widest valid `#RRGGBB` candidate so the HEX
    /// value stays aligned while sampled characters change.
    private static let hexValueSlotWidth: CGFloat = {
        let attrs: [NSAttributedString.Key: Any] = [.font: valueFont]
        return "0123456789ABCDEF".reduce(CGFloat.zero) { widest, character in
            let candidate = "#" + String(repeating: String(character), count: 6)
            let width = (candidate as NSString).size(withAttributes: attrs).width
            return max(widest, width)
        }.rounded(.up)
    }()

    /// The rounded panel outline, built once per size.
    private static var cachedPathSize: NSSize = .zero
    private static var cachedPath: NSBezierPath?

    static func panelPath(for bounds: NSRect) -> NSBezierPath {
        if let cachedPath, cachedPathSize == bounds.size { return cachedPath }
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: MagnifierLensPanelLayout.cornerRadius,
            yRadius: MagnifierLensPanelLayout.cornerRadius
        )
        cachedPath = path
        cachedPathSize = bounds.size
        return path
    }

    /// Panel background resolved from the current appearance (and the
    /// `Defaults` palette). Invalidated when the effective appearance changes.
    private var cachedPanelBackgroundColor: NSColor?
    private var cachedAppearanceName: NSAppearance.Name?

    var panelBackgroundColor: NSColor {
        let appearance = effectiveAppearance
        let name = appearance.bestMatch(from: [.darkAqua, .aqua]) ?? .darkAqua
        if let cachedPanelBackgroundColor, cachedAppearanceName == name {
            return cachedPanelBackgroundColor
        }
        let resolved = MagnifierLensPanelSampler.backgroundColor(forAppearance: appearance)
        cachedPanelBackgroundColor = resolved
        cachedAppearanceName = name
        return resolved
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        cachedPanelBackgroundColor = nil
        cachedAppearanceName = nil
    }

    /// Static text styles: rebuilt per frame before, which allocated two
    /// paragraph styles and three attribute dictionaries on every repaint.
    private static let labelParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }()

    private static let valueParagraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .right
        style.lineBreakMode = .byTruncatingHead
        return style
    }()

    private static let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: labelFont,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: labelParagraphStyle,
    ]

    private static let valueAttrs: [NSAttributedString.Key: Any] = [
        .font: valueFont,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: valueParagraphStyle,
    ]

    private static let tipAttrs: [NSAttributedString.Key: Any] = [
        .font: tipFont,
        .foregroundColor: NSColor.labelColor.withAlphaComponent(0.7)
    ]

    func clear() {
        currentSample = nil
        snapshot = nil
        needsDisplay = true
    }

    func update(
        sample: MagnifierLensPanelWindow.Sample,
        pixelPoint: CGPoint,
        mouseLocation: NSPoint,
        snapshot: CGImage,
        screenFrame: NSRect,
        format: MagnifierLensPanelWindow.Format
    ) {
        self.currentSample = sample
        self.currentPixelPoint = pixelPoint
        self.mouseLocation = mouseLocation
        self.snapshot = snapshot
        self.screenFrame = screenFrame
        self.format = format
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let panelWidth = bounds.width
        let panelHeight = bounds.height
        let magnifiedRect = NSRect(
            x: 0,
            y: panelHeight - panelWidth,
            width: panelWidth,
            height: panelWidth
        )

        // Panel background — pick dark or light based on appearance + setting.
        // Both the palette (six `Defaults` reads) and the rounded path are
        // resolved once: the lens repaints up to 30 times a second while the
        // pointer moves and neither input changes between frames.
        let bgPath = Self.panelPath(for: bounds)
        panelBackgroundColor.setFill()
        bgPath.fill()

        NSGraphicsContext.current?.saveGraphicsState()
        bgPath.addClip()
        drawMagnifiedArea(in: magnifiedRect)
        drawInfo()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawMagnifiedArea(in rect: NSRect) {
        // Fill the entire area with a visually distinct out-of-bounds
        // colour so the user can tell which region sits beyond the
        // screen boundary. The valid crop is drawn on top afterwards.
        NSColor(calibratedWhite: 0.15, alpha: 0.6).setFill()
        NSBezierPath(rect: rect).fill()

        guard let snapshot else { return }

        // Source region (in pixels) = display size / zoom factor.
        let regionSize = max(2, rect.width / CGFloat(Defaults.magnifierLensPanelMagnification))
        let sourceX = max(0, currentPixelPoint.x - regionSize / 2)
        let sourceY = max(0, currentPixelPoint.y - regionSize / 2)
        let clampedWidth = min(regionSize, CGFloat(snapshot.width) - sourceX)
        let clampedHeight = min(regionSize, CGFloat(snapshot.height) - sourceY)

        guard clampedWidth > 0, clampedHeight > 0,
              let cropped = snapshot.cropping(to: CGRect(
                x: sourceX, y: sourceY, width: clampedWidth, height: clampedHeight
              )),
              let context = NSGraphicsContext.current?.cgContext else { return }

        // Compute where the valid crop should sit inside the display
        // rect so the out-of-bounds portion stays visible as the dimmed
        // background fill. The cursor pixel must land at rect.mid.
        // CGContext maps CGImage y=0 to drawRect.maxY (AppKit y-up),
        // so the cursor (at crop-y cursorOffsetY) sits at
        // drawRect.maxY - cursorOffsetY * scale == rect.midY.
        let scale = rect.width / regionSize
        let missingLeft = sourceX - (currentPixelPoint.x - regionSize / 2)  // ≥ 0
        let cursorOffsetY = currentPixelPoint.y - sourceY  // in crop (y-down)
        let drawMaxY = rect.midY + cursorOffsetY * scale
        let drawRect = NSRect(
            x: rect.minX + missingLeft * scale,
            y: drawMaxY - clampedHeight * scale,
            width: clampedWidth * scale,
            height: clampedHeight * scale
        )

        context.saveGState()
        context.clip(to: rect)
        context.interpolationQuality = .none
        context.draw(cropped, in: drawRect)
        context.restoreGState()

        // Thin selection-accent crosshair spanning the full magnified area.
        // Same blue as the capture frame and the editor's handles, so the lens
        // reads as part of the selection chrome rather than a second green.
        let centerX = rect.midX
        let centerY = rect.midY
        selectionAccent.setStroke()
        let bigCross = NSBezierPath()
        bigCross.lineWidth = 2
        bigCross.move(to: NSPoint(x: rect.minX, y: centerY))
        bigCross.line(to: NSPoint(x: rect.maxX, y: centerY))
        bigCross.move(to: NSPoint(x: centerX, y: rect.minY))
        bigCross.line(to: NSPoint(x: centerX, y: rect.maxY))
        bigCross.stroke()
    }

    private func drawInfo() {
        let labelAttrs = Self.labelAttrs
        let valueAttrs = Self.valueAttrs
        let tipAttrs = Self.tipAttrs

        // Compute the row index (from the bottom) for each row that exists.
        // We always render coords + color (rows 3 and 2 in old layout).
        // Tip rows occupy 1 and 0 conditionally.
        var rowFromBottom = 0
        // totalRows in info area (coords + color + ratio + optional shortcut hints)
        let totalRows = 3
            + (Defaults.magnifierLensPanelShowCopyHint ? 1 : 0)
            + (Defaults.magnifierLensPanelShowFormatHint ? 1 : 0)

        func rowY(forIndex i: Int) -> CGFloat {
            // i is 0-based from bottom
            let baseY = MagnifierLensPanelLayout.infoVerticalInset
                + CGFloat(i) * MagnifierLensPanelLayout.infoRowHeight
            let firstInfoItemRow = totalRows - 2
            return baseY + (i >= firstInfoItemRow
                ? MagnifierLensPanelLayout.infoGroupSpacing
                : 0)
        }

        // Coordinates row (always)
        if currentSample != nil {
            let coordsValue: String
            switch Defaults.magnifierLensPanelCoordinateMode {
            case .points:
                let x = String(Int(mouseLocation.x))
                let y = String(Int(mouseLocation.y))
                coordsValue = "\(x), \(y)"
            case .pixels:
                let x = String(Int(currentPixelPoint.x))
                let y = String(Int(currentPixelPoint.y))
                coordsValue = "\(x), \(y)"
            }
            drawInfoRow(
                label: L10n.magnifierLensPanelCoordinatesLabel,
                value: coordsValue,
                labelAttrs: labelAttrs,
                valueAttrs: valueAttrs,
                at: rowY(forIndex: totalRows - 1)
            )
        }

        // HEX/RGB row (always)
        if let sample = currentSample {
            let rowIndex = totalRows - 2
            let colorValue: String
            switch format {
            case .hex:
                colorValue = hexString(sample)
            case .rgb:
                colorValue = "\(sample.r), \(sample.g), \(sample.b)"
            }
            drawColorInfoRow(
                label: L10n.magnifierLensPanelColorValueLabel,
                value: colorValue,
                sample: sample,
                labelAttrs: labelAttrs,
                valueAttrs: valueAttrs,
                at: rowY(forIndex: rowIndex)
            )
        }

        drawHintRow(
            label: L10n.magnifierLensPanelAspectHint,
            value: aspectHintValue(),
            attrs: tipAttrs,
            at: rowY(forIndex: totalRows - 3)
        )

        // Tip rows (conditional)
        if Defaults.magnifierLensPanelShowCopyHint {
            drawHintRow(
                label: L10n.magnifierLensPanelCopyHint,
                value: nil,
                attrs: tipAttrs,
                at: rowY(forIndex: rowFromBottom)
            )
            rowFromBottom += 1
        }
        if Defaults.magnifierLensPanelShowFormatHint {
            let colorFormat: String
            switch format {
            case .hex: colorFormat = "HEX"
            case .rgb: colorFormat = "RGB"
            }
            drawHintRow(
                label: L10n.magnifierLensPanelFormatHint,
                value: colorFormat,
                attrs: tipAttrs,
                at: rowY(forIndex: rowFromBottom)
            )
        }
    }

    private func drawInfoRow(
        label: String,
        value: String,
        labelAttrs: [NSAttributedString.Key: Any],
        valueAttrs: [NSAttributedString.Key: Any],
        at y: CGFloat
    ) {
        let valueRightEdge = bounds.width - infoRightPadding
        let availableColumnWidth = max(
            0,
            valueRightEdge - infoLeftPadding - infoColumnGap
        )
        let measuredLabelWidth = ceil((label as NSString).size(withAttributes: labelAttrs).width)
        let labelWidth = min(measuredLabelWidth, floor(availableColumnWidth * 0.44))
        let valueX = infoLeftPadding + labelWidth + infoColumnGap
        let valueWidth = max(0, valueRightEdge - valueX)
        let labelRect = NSRect(
            x: infoLeftPadding,
            y: y,
            width: labelWidth,
            height: MagnifierLensPanelLayout.infoRowHeight
        )
        let valueRect = NSRect(
            x: valueX,
            y: y,
            width: valueWidth,
            height: MagnifierLensPanelLayout.infoRowHeight
        )
        (label as NSString).draw(in: labelRect, withAttributes: labelAttrs)
        (value as NSString).draw(in: valueRect, withAttributes: valueAttrs)
    }

    private func drawColorInfoRow(
        label: String,
        value: String,
        sample: MagnifierLensPanelWindow.Sample,
        labelAttrs: [NSAttributedString.Key: Any],
        valueAttrs: [NSAttributedString.Key: Any],
        at y: CGFloat
    ) {
        let valueRect = NSRect(
            x: bounds.width - infoRightPadding - Self.hexValueSlotWidth,
            y: y,
            width: Self.hexValueSlotWidth,
            height: MagnifierLensPanelLayout.infoRowHeight
        )
        let sourceLabelLine = CTLineCreateWithAttributedString(
            NSAttributedString(string: label, attributes: labelAttrs)
        )
        let sourceLabelInkBounds = CTLineGetBoundsWithOptions(
            sourceLabelLine,
            [.useGlyphPathBounds]
        )
        let swatchSide = min(
            MagnifierLensPanelLayout.infoRowHeight,
            max(8, floor(sourceLabelInkBounds.height))
        )
        let measuredLabelWidth = ceil(CGFloat(CTLineGetTypographicBounds(
            sourceLabelLine,
            nil,
            nil,
            nil
        )))
        let labelWidth = min(
            measuredLabelWidth,
            max(
                0,
                valueRect.minX
                    - infoColumnGap
                    - swatchSide
                    - colorSwatchGap
                    - infoLeftPadding
            )
        )
        let labelRect = NSRect(
            x: infoLeftPadding,
            y: y,
            width: labelWidth,
            height: MagnifierLensPanelLayout.infoRowHeight
        )
        let labelLine = coreTextLine(
            label,
            attrs: labelAttrs,
            fitting: labelRect.width,
            truncation: .end
        )
        let valueLine = coreTextLine(
            value,
            attrs: valueAttrs,
            fitting: valueRect.width,
            truncation: .start
        )
        let swatchRect = NSRect(
            x: labelRect.maxX + colorSwatchGap,
            y: labelRect.midY - swatchSide / 2,
            width: swatchSide,
            height: swatchSide
        )
        drawCoreTextLine(labelLine, inkCenteredIn: labelRect, rightAligned: false)
        drawCoreTextLine(valueLine, inkCenteredIn: valueRect, rightAligned: true)

        let swatchColor = NSColor(
            srgbRed: CGFloat(sample.r) / 255.0,
            green: CGFloat(sample.g) / 255.0,
            blue: CGFloat(sample.b) / 255.0,
            alpha: 1
        )
        let swatchPath = NSBezierPath(roundedRect: swatchRect, xRadius: 3, yRadius: 3)
        swatchColor.setFill()
        swatchPath.fill()
        NSColor.labelColor.withAlphaComponent(0.35).setStroke()
        swatchPath.lineWidth = 0.5
        swatchPath.stroke()
    }

    private func coreTextLine(
        _ text: String,
        attrs: [NSAttributedString.Key: Any],
        fitting width: CGFloat,
        truncation: CTLineTruncationType
    ) -> CTLine {
        let sourceLine = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attrs)
        )
        let sourceWidth = CGFloat(CTLineGetTypographicBounds(sourceLine, nil, nil, nil))
        guard sourceWidth > width else { return sourceLine }

        let tokenLine = CTLineCreateWithAttributedString(
            NSAttributedString(string: "…", attributes: attrs)
        )
        return CTLineCreateTruncatedLine(
            sourceLine,
            Double(max(0, width)),
            truncation,
            tokenLine
        ) ?? sourceLine
    }

    private func drawCoreTextLine(
        _ line: CTLine,
        inkCenteredIn rect: NSRect,
        rightAligned: Bool
    ) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        var inkBounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
        let typographicWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        if inkBounds.isEmpty {
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            inkBounds = CGRect(
                x: 0,
                y: -descent,
                width: typographicWidth,
                height: ascent + descent
            )
        }
        let originX = rightAligned
            ? rect.maxX - min(typographicWidth, rect.width)
            : rect.minX
        let baselineY = rect.midY - inkBounds.midY

        context.saveGState()
        context.clip(to: rect)
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: originX, y: baselineY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func drawHintRow(
        label: String,
        value: String?,
        attrs: [NSAttributedString.Key: Any],
        at y: CGFloat
    ) {
        let rowRect = NSRect(
            x: infoLeftPadding,
            y: y,
            width: bounds.width - infoLeftPadding - infoRightPadding,
            height: MagnifierLensPanelLayout.infoRowHeight
        )
        var labelRect = rowRect

        if let value {
            let sourceValueLine = CTLineCreateWithAttributedString(
                NSAttributedString(string: value, attributes: attrs)
            )
            let valueWidth = min(
                rowRect.width,
                ceil(CGFloat(CTLineGetTypographicBounds(
                    sourceValueLine,
                    nil,
                    nil,
                    nil
                )))
            )
            let valueRect = NSRect(
                x: rowRect.maxX - valueWidth,
                y: y,
                width: valueWidth,
                height: MagnifierLensPanelLayout.infoRowHeight
            )
            labelRect.size.width = max(
                0,
                valueRect.minX - infoColumnGap - labelRect.minX
            )
            let valueLine = coreTextLine(
                value,
                attrs: attrs,
                fitting: valueRect.width,
                truncation: .end
            )
            drawCoreTextLine(valueLine, inkCenteredIn: valueRect, rightAligned: true)
        }

        let labelLine = coreTextLine(
            label,
            attrs: attrs,
            fitting: labelRect.width,
            truncation: .end
        )
        drawCoreTextLine(labelLine, inkCenteredIn: labelRect, rightAligned: false)
    }

    private func hexString(_ sample: MagnifierLensPanelWindow.Sample) -> String {
        String(format: "#%02X%02X%02X", sample.r, sample.g, sample.b)
    }

    private func aspectHintValue() -> String {
        if Defaults.hasSelectionAspectRatio {
            return aspectRatioLabel(for: CGFloat(Defaults.selectionAspectRatio))
        }
        return L10n.magnifierLensPanelAspectFree
    }

    private func aspectRatioLabel(for aspectRatio: CGFloat) -> String {
        let presets: [(CGFloat, String)] = [
            (1.0, "1:1"),
            (2.35, "2.35:1"),
            (3.0, "3:1"),
            (3.0 / 2.0, "3:2"),
            (4.0 / 3.0, "4:3"),
            (9.0 / 16.0, "9:16"),
            (16.0 / 9.0, "16:9"),
        ]
        if let preset = presets.first(where: { abs($0.0 - aspectRatio) < 0.000_001 }) {
            return preset.1
        }
        return String(format: "%.2f:1", Double(aspectRatio))
    }
}
