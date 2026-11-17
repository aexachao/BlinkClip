import AppKit
import ObjectiveC
@testable import BlinkClipCapture

private final class SnapshotRecorder: ScreenSnapshotProviding {
    var requests: [Set<CGWindowID>] = []
    var handlers: [(ScreenSnapshotEvent) -> Void] = []
    var cancelled = 0
    func prewarm() {}
    func capture(targets: [ScreenSnapshotTarget], eventHandler: @escaping (ScreenSnapshotEvent) -> Void) -> ScreenSnapshotCancellation {
        preconditionFailure("Production must call the explicit exclusion overload")
    }
    func capture(targets: [ScreenSnapshotTarget], excludingWindowIDs: Set<CGWindowID>, eventHandler: @escaping (ScreenSnapshotEvent) -> Void) -> ScreenSnapshotCancellation {
        requests.append(excludingWindowIDs)
        handlers.append(eventHandler)
        return { [weak self] in self?.cancelled += 1 }
    }
}

/// Reads the pointer-guide geometry out of the live view/layer tree — the same
/// numbers the window server receives, without a second copy of the layout
/// maths. The overlay installs exactly two guide bands (horizontal, vertical);
/// the pointer itself is the system crosshair and is not part of this view.
private struct CrosshairGeometry {
    let horizontal: NSView?
    let vertical: NSView?
    let subviewCount: Int
    /// The hover highlight is a sibling layer of the guides (dimming cut-out,
    /// accent frame and size label). Counting it separately keeps the "exactly
    /// two guide layers, no self-drawn pointer" property meaningful after the
    /// hover chrome moved out of `draw(_:)`.
    let hoverLayerCount: Int
    /// The selection chrome (dim + frame + handles + label) is one layer, so a
    /// drag writes a layer instead of repainting the snapshot.
    let chromeLayerCount: Int
    let bandCount: Int
    let horizontalLayer: CAShapeLayer?
    let verticalLayer: CAShapeLayer?

    private static func typeName(_ view: NSView) -> String {
        String(describing: type(of: view))
    }

    init(view: SelectionView) {
        let subviews = view.subviews
        subviewCount = subviews.count
        hoverLayerCount = subviews.filter { Self.typeName($0) == "HoverHighlightView" }.count
        chromeLayerCount = subviews.filter { Self.typeName($0) == "SelectionChromeView" }.count
        let bands = subviews.filter { Self.typeName($0) == "CrosshairBandView" }
        bandCount = bands.count
        // `installOverlayLayers` adds the horizontal band first.
        horizontal = bands.count == 2 ? bands[0] : nil
        vertical = bands.count == 2 ? bands[1] : nil
        horizontalLayer = horizontal?.layer?.sublayers?.first as? CAShapeLayer
        verticalLayer = vertical?.layer?.sublayers?.first as? CAShapeLayer
    }

    var horizontalHidden: Bool { horizontal?.isHidden ?? true }
    var verticalHidden: Bool { vertical?.isHidden ?? true }

    /// Centre of the horizontal line in view coordinates, or nil when hidden.
    var lineY: CGFloat? { horizontalHidden ? nil : horizontal?.frame.midY }
    /// Centre of the vertical line in view coordinates, or nil when hidden.
    var lineX: CGFloat? { verticalHidden ? nil : vertical?.frame.midX }

    /// One horizontal subpath and one vertical subpath: a solid line, not an
    /// outline.
    var horizontalSubpathCount: Int { subpathCount(in: horizontalLayer) }
    var verticalSubpathCount: Int { subpathCount(in: verticalLayer) }

    private func subpathCount(in layer: CAShapeLayer?) -> Int {
        guard let path = layer?.path else { return 0 }
        var moves = 0
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { moves += 1 }
        }
        return moves
    }
}

/// Counts `draw(_:)` calls so a guide move can be shown to repaint nothing.
private final class CountingSelectionView: SelectionView {
    private(set) var drawCount = 0

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        super.draw(dirtyRect)
    }
}

/// Records the rect a drag commits, so the harness sees the exact geometry the
/// capture path would crop.
private final class DragDelegate: NSObject, SelectionViewDelegate {
    private(set) var completed: [(rect: NSRect, isWindowSelection: Bool)] = []
    private(set) var changes: [NSRect] = []

    func selectionDidStart(reason: SelectionStartReason) {}
    func selectionDidHoverWindow(_ window: DetectedWindow?) {}
    func selectionDidChange(rect: NSRect, inView view: NSView) { changes.append(rect) }
    func selectionDidComplete(rect: NSRect, inView view: NSView, isWindowSelection: Bool, windowID: CGWindowID?) {
        completed.append((rect, isWindowSelection))
    }
    func selectionMaskDidDoubleClick(inView view: NSView) {}
    func selectionDidDoubleClickInsideSelection(inView view: NSView) {}
}

private func rgbaComponents(_ color: CGColor?) -> [CGFloat]? {
    guard let color,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let converted = color.converted(to: space, intent: .defaultIntent, options: nil) else {
        return nil
    }
    return converted.components
}

/// One overlay-sized view plus an injected window list, so the production
/// hover and guide paths can be driven with exact screen points and no pointer
/// synthesis. Writes nothing to the desktop: the window is never ordered front.
@MainActor
private struct HoverFixture {
    let window: NSWindow
    let view: CountingSelectionView
    let detector: WindowDetector
    let displayFrame: NSRect
    private let windows: [(CGWindowID, CGRect)]

    init(displayFrame: NSRect, windows: [(CGWindowID, CGRect, Bool)]) {
        self.displayFrame = displayFrame
        let window = NSWindow(
            contentRect: displayFrame,
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.setFrame(displayFrame, display: false)
        self.window = window
        let view = CountingSelectionView(frame: NSRect(origin: .zero, size: displayFrame.size))
        window.contentView = view
        self.view = view
        let detector = WindowDetector()
        detector.apply(windows.map {
            DetectedWindow(
                name: "fixture-\($0.0)",
                windowID: $0.0,
                layer: 0,
                frame: $0.1,
                ownerPID: 4242,
                isProductChrome: $0.2
            )
        })
        self.detector = detector
        view.windowDetector = detector
        self.windows = windows.map { ($0.0, $0.1) }
    }

    /// Drives the production hover entry point with a CG-coordinate point.
    func hover(cgPoint: CGPoint) {
        view.updateHover(screenPoint: screenPoint(cgPoint: cgPoint))
    }

    /// Drives the production guide entry point with a CG-coordinate point.
    func crosshair(cgPoint: CGPoint) {
        view.updateCrosshair(globalPoint: screenPoint(cgPoint: cgPoint))
    }

    /// CG point (top-left origin, y down) → AppKit screen point (y up).
    func screenPoint(cgPoint: CGPoint) -> NSPoint {
        NSPoint(x: cgPoint.x, y: (NSScreen.screens.first?.frame.height ?? 0) - cgPoint.y)
    }

    /// Expected local (view) point for a CG-coordinate point.
    func localPoint(cgPoint: CGPoint) -> NSPoint {
        localRect(cgFrame: CGRect(x: cgPoint.x, y: cgPoint.y, width: 0, height: 0)).origin
    }

    /// Expected view-space rect for a CG window frame on this fixture's display.
    func localRect(cgFrame: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitY = primaryHeight - cgFrame.origin.y - cgFrame.height
        return NSRect(
            x: cgFrame.origin.x - displayFrame.origin.x,
            y: appKitY - displayFrame.origin.y,
            width: cgFrame.width,
            height: cgFrame.height
        )
    }

    /// Drives the production mouse path with a real `NSEvent` — no test-only
    /// hook: `mouseDown` / `mouseDragged` / `mouseUp` are the shipping code.
    /// `point` is in this view's coordinates (the fixture's content view fills
    /// the window, so window and view coordinates are the same).
    @discardableResult
    func mouse(_ type: NSEvent.EventType, at point: NSPoint) -> Bool {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ) else { return false }
        switch type {
        case .leftMouseDown: view.mouseDown(with: event)
        case .leftMouseDragged: view.mouseDragged(with: event)
        case .leftMouseUp: view.mouseUp(with: event)
        case .mouseMoved: view.mouseMoved(with: event)
        default: return false
        }
        return true
    }

    /// Independent front-to-back scan (not the detector) for expected targets.
    func expectedTarget(_ cgPoint: CGPoint) -> CGWindowID? {
        windows.first { $0.1.contains(cgPoint) }?.0
    }

    func windowFrame(_ id: CGWindowID) -> CGRect? {
        windows.first { $0.0 == id }?.1
    }
}

/// Writes the raw 120Hz sweep (when the evidence directory is set) so the
/// report can carry the frame sequence instead of only an assertion count.
private func reportCrosshairSweep(rows: [String], measuredRate: Double,
                                  primaryHeight: CGFloat, displayFrame: NSRect) {
    print("CROSSHAIR-SWEEP samples=\(rows.count - 1) rate=\(String(format: "%.1f", measuredRate))Hz "
          + "primaryHeight=\(Int(primaryHeight)) display=\(Int(displayFrame.width))x\(Int(displayFrame.height))")
    guard let directory = ProcessInfo.processInfo.environment["BLINKCLIP_CROSSHAIR_EVIDENCE"],
          let data = rows.joined(separator: "\n").data(using: .utf8) else { return }
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let url = URL(fileURLWithPath: directory).appendingPathComponent("crosshair-frames-120hz.csv")
    try? data.write(to: url)
}

// MARK: - CL: size label clamp evidence

/// A flat snapshot stand-in so the overlay draws the same pass it draws on the
/// real desktop (snapshot → dimming → cutout → chrome).
private func solidBackground(size: NSSize, gray: CGFloat) -> NSImage? {
    let scale: CGFloat = 2
    let width = max(1, Int((size.width * scale).rounded()))
    let height = max(1, Int((size.height * scale).rounded()))
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.setFillColor(CGColor(gray: gray, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { return nil }
    return NSImage(cgImage: image, size: size)
}

/// A synthetic full-display snapshot whose red channel encodes the pixel
/// column, so a crop can be checked back to the coordinates it came from.
private func gradientSnapshot(width: Int, height: Int) -> CGImage? {
    guard width > 0, height > 0,
          let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ),
          let data = context.data else { return nil }
    let bytes = data.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
        for x in 0..<width {
            let index = (y * width + x) * 4
            bytes[index] = UInt8(x * 255 / max(width - 1, 1))
            bytes[index + 1] = UInt8(y * 255 / max(height - 1, 1))
            bytes[index + 2] = 0
            bytes[index + 3] = 255
        }
    }
    return context.makeImage()
}

/// The top-left pixel of a `CGImage` as (red, green).
private func firstPixel(of image: CGImage) -> (Int, Int)? {
    guard let topLeft = image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)) else { return nil }
    var bytes = [UInt8](repeating: 0, count: 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(topLeft, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return true
    }
    guard drawn else { return nil }
    return (Int(bytes[0]), Int(bytes[1]))
}

/// Strict accent blue (`#007AFF` fill) and the label's white glyph pixels.
private func isAccentBlue(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    b >= 240 && b - r >= 200 && g >= 90 && g <= 160
}

private func isLabelWhite(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    r >= 235 && g >= 235 && b >= 235
}

/// The rendered chrome of a view, normalised to RGBA8 with row 0 = top of the
/// image (same orientation as `EditorChromeParityHarness`). Coordinates used by
/// `count` are view coordinates (origin bottom-left).
private struct LabelBitmap {
    let image: CGImage
    let width: Int
    let height: Int
    let scale: CGFloat
    let bytes: [UInt8]

    init?(_ view: NSView) {
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0,
              let rep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        view.cacheDisplay(in: bounds, to: rep)
        guard let image = rep.cgImage else { return nil }
        let width = image.width
        let height = image.height
        let data = NSMutableData(length: width * height * 4)!
        guard let context = CGContext(
            data: data.mutableBytes, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.image = image
        self.width = width
        self.height = height
        self.scale = CGFloat(width) / bounds.width
        self.bytes = [UInt8](Data(bytes: data.bytes, count: data.length))
    }

    private func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        guard x >= 0, x < width, y >= 0, y < height else { return (-1, -1, -1) }
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    /// Counts pixels of a view-coordinate rect that match one predicate.
    func count(in rect: NSRect, matching match: (Int, Int, Int) -> Bool) -> Int {
        let x0 = max(0, Int((rect.minX * scale).rounded(.down)))
        let x1 = min(width - 1, Int((rect.maxX * scale).rounded(.up)) - 1)
        let y0 = max(0, Int((rect.minY * scale).rounded(.down)))
        let y1 = min(height - 1, Int((rect.maxY * scale).rounded(.up)) - 1)
        guard x0 <= x1, y0 <= y1 else { return 0 }
        var matched = 0
        for y in y0...y1 {
            let row = height - 1 - y
            for x in x0...x1 {
                let (r, g, b) = rgb(x, row)
                if match(r, g, b) { matched += 1 }
            }
        }
        return matched
    }

    /// Every strict-accent pixel index, for a whole-frame set comparison.
    func accentPixels() -> Set<Int> {
        var set = Set<Int>()
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = rgb(x, y)
                if isAccentBlue(r, g, b) { set.insert(y * width + x) }
            }
        }
        return set
    }
}

/// Writes a PNG of `crop` (view coordinates, origin bottom-left) at `scale`×.
@discardableResult
private func writePNG(_ image: CGImage, sourceSize: NSSize, crop: NSRect, scale: Int, to path: String) -> Bool {
    let width = Int((crop.width * CGFloat(scale)).rounded())
    let height = Int((crop.height * CGFloat(scale)).rounded())
    guard width > 0, height > 0,
          let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
          ) else { return false }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = scale > 1 ? .none : .default
    NSImage(cgImage: image, size: sourceSize).draw(
        in: NSRect(x: 0, y: 0, width: crop.width * CGFloat(scale), height: crop.height * CGFloat(scale)),
        from: crop, operation: .copy, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: URL(fileURLWithPath: path))) != nil
}

/// Renders the overlay's guide layers to a PNG, so the report can show the
/// guides without photographing the desktop. `SelectionView` is not itself
/// layer-backed (the snapshot is painted in `draw(_:)`), so the two guide
/// layers are composited from the live layer tree: their real frames, real
/// `CAShapeLayer` paths, real stroke colour and width. Only used when
/// BLINKCLIP_CROSSHAIR_RENDER_DIR is set.
private func renderOverlayLayers(_ view: SelectionView, background: CGFloat, to path: String) -> Bool {
    let bounds = view.bounds
    guard bounds.width > 0, bounds.height > 0 else { return false }
    let scale = 2
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: Int(bounds.width * CGFloat(scale)),
            height: Int(bounds.height * CGFloat(scale)),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else { return false }
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    // A flat stand-in for the frozen desktop snapshot: the guides are quiet by
    // design, so a mid-dark background is the honest way to show them.
    context.setFillColor(NSColor(white: background, alpha: 1).cgColor)
    context.fill(CGRect(origin: .zero, size: bounds.size))
    for band in view.subviews where String(describing: type(of: band)) == "CrosshairBandView" {
        guard !band.isHidden,
              let shape = band.layer?.sublayers?.first as? CAShapeLayer,
              let line = shape.path,
              let stroke = shape.strokeColor else { continue }
        context.saveGState()
        context.translateBy(x: band.frame.minX, y: band.frame.minY)
        context.addPath(line)
        context.setStrokeColor(stroke)
        context.setLineWidth(shape.lineWidth)
        context.setLineCap(.butt)   // `CrosshairBandView` sets `.butt`
        if let dash = shape.lineDashPattern, !dash.isEmpty {
            context.setLineDash(phase: 0, lengths: dash.map { CGFloat($0.doubleValue) })
        }
        context.strokePath()
        context.restoreGState()
    }
    guard let image = context.makeImage() else { return false }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: URL(fileURLWithPath: path))) != nil
}

@main struct CaptureChromeExclusionHarness {

    @MainActor static func main() {
        _ = NSApplication.shared
        // Exercise real production window construction/show calls without
        // placing full-screen selection panels over the user's desktop.
        var fronted: [NSWindow] = []
        let method = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.orderFrontRegardless))!
        let original = method_getImplementation(method)
        let replacement: @convention(block) (NSWindow) -> Void = { fronted.append($0) }
        let replacementIMP = imp_implementationWithBlock(replacement)
        method_setImplementation(method, replacementIMP)
        defer { method_setImplementation(method, original); imp_removeBlock(replacementIMP) }
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        let settings = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let settingsID = CGWindowID(settings.windowNumber)
        check(settings.windowNumber > 0, "normal target has a native ID")
        for action in [OverlayWindowController.PostCaptureAction.edit, .quickPin, .textRecognition, .copyImageText, .screenshotTranslation] {
            let provider = SnapshotRecorder()
            var completions = 0
            var priorHUD: NSWindow?
            for attempt in 0..<2 {
                fronted.removeAll()
                let controller = OverlayWindowController(postCaptureAction: action, snapshotProvider: provider,
                    windowSnapshotLoader: { _ in .success([]) }, eventTrackingStateProvider: { false },
                    colorSamplerActiveProvider: { false }, modalWindowProvider: { nil },
                    onComplete: { _ in completions += 1 })
                controller.activate()
                check(provider.requests.count == attempt + 1, "one capture request per session")
                let exclusions = provider.requests.last!
                let huds = fronted.filter { $0 is MagnifierLensPanelWindow || $0 is CursorChipWindow }
                check(huds.count == 1, "one HUD instance is presented")
                let hud = huds[0]
                check(hud.windowNumber > 0, "HUD has a native ID")
                check(exclusions.contains(CGWindowID(hud.windowNumber)), "presented HUD was excluded before the asynchronous request")
                check(!exclusions.contains(settingsID), "normal app/settings target stays capturable")
                let overlays = fronted.filter { $0 is OverlayPanel }
                check(!overlays.isEmpty, "selection overlays were presented")
                check(overlays.allSatisfy { exclusions.contains(CGWindowID($0.windowNumber)) }, "selection windows remain excluded")
                check(exclusions.count == overlays.count + 1, "only session-owned selection and HUD windows are excluded")
                if action == .edit || action == .quickPin {
                    check(hud is MagnifierLensPanelWindow, "edit/pin use the same precreated lens")
                } else {
                    check(hud is CursorChipWindow, "other screenshot actions use the same precreated hint")
                }
                if let priorHUD {
                    check(hud !== priorHUD, "retry creates a fresh session HUD")
                    check(!exclusions.contains(CGWindowID(priorHUD.windowNumber)), "retry does not retain the old HUD exclusion")
                }
                priorHUD = hud
                if attempt == 1 {
                    provider.handlers.last?(.finished)
                    check(!controller.isMagnifierLensPanelPresented || hud is MagnifierLensPanelWindow, "snapshot completion preserves the intended HUD type")
                }
                controller.cancel()
                check(provider.cancelled == attempt + 1, "cancel detaches in-flight capture")
                check(controller.isCaptureSessionEnded, "cancel ends the session")
                check(!controller.isMagnifierLensPanelPresented, "cancel releases the lens")
                check(!hud.isVisible, "cancel leaves no visible HUD")
                check(completions == attempt + 1, "cancel completes exactly once")
                controller.cancel()
                check(completions == attempt + 1, "repeated cancellation is harmless")
            }
        }
        for action in [OverlayWindowController.PostCaptureAction.edit, .textRecognition] {
            fronted.removeAll()
            let provider = SnapshotRecorder()
            var blocked = true
            var dismissals = 0
            let controller = OverlayWindowController(postCaptureAction: action, snapshotProvider: provider,
                windowSnapshotLoader: { _ in .success([]) }, eventTrackingStateProvider: { false },
                colorSamplerActiveProvider: { false }, modalWindowProvider: { blocked ? settings : nil },
                modalWindowDismissal: { window in
                    precondition(window === settings); blocked = false; dismissals += 1
                }, onComplete: { _ in })
            controller.activate()
            check(provider.requests.count == 1, "modal path still starts snapshot before presentation")
            check(fronted.isEmpty, "modal path does not prematurely show capture chrome")
            let pendingHUDs = NSApp.windows.filter {
                ($0 is MagnifierLensPanelWindow || $0 is CursorChipWindow) && provider.requests[0].contains(CGWindowID($0.windowNumber))
            }
            check(pendingHUDs.count == 1, "hidden precreated HUD has a stable excluded ID")
            provider.handlers[0](.finished)
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            check(dismissals == 1, "snapshot resolves modal presentation once")
            check(fronted.filter { $0 === pendingHUDs[0] }.count == 1, "deferred presentation shows the exact excluded HUD once")
            check(!provider.requests[0].contains(settingsID), "modal settings window remains a valid screenshot target")
            controller.cancel()
            check(controller.isCaptureSessionEnded && !pendingHUDs[0].isVisible, "deferred session cleans up")
        }
        fronted.removeAll()
        let recordingProvider = SnapshotRecorder()
        let recording = OverlayWindowController(postCaptureAction: .record, snapshotProvider: recordingProvider,
            windowSnapshotLoader: { _ in .success([]) }, eventTrackingStateProvider: { false },
            colorSamplerActiveProvider: { false }, modalWindowProvider: { nil }, onComplete: { _ in })
        recording.activate()
        check(recordingProvider.requests.isEmpty, "recording keeps its non-snapshot path")
        check(fronted.filter { $0 is CursorChipWindow }.count == 1, "non-snapshot path creates and shows only one hint")
        recording.cancel()
        check(recording.isCaptureSessionEnded, "non-snapshot cancellation remains intact")
        // --- REV: full-screen guides follow the pointer, not the window -----
        // Two bands (one per axis), each a view-backed `CAShapeLayer` spanning
        // the whole display and centred on the pointer. The pointer itself is
        // the system crosshair; nothing here draws or hides it. A pointer move
        // writes the two bands and never calls `draw(_:)`.
        guard let mainScreen = NSScreen.main ?? NSScreen.screens.first else {
            preconditionFailure("a screen is required for the guide checks")
        }
        let primaryHeight = mainScreen.frame.height
        let primaryFrame = mainScreen.frame
        let winA = CGRect(x: 100, y: 100, width: 400, height: 300)
        let winB = CGRect(x: 250, y: 200, width: 400, height: 300)
        let winC = CGRect(x: 400, y: 300, width: 400, height: 300)
        let orderedWindows: [(CGWindowID, CGRect)] = [(7001, winA), (7002, winB), (7003, winC)]
        let primaryFixture = HoverFixture(
            displayFrame: primaryFrame,
            windows: orderedWindows.map { ($0.0, $0.1, false) }
        )
        let guideView = primaryFixture.view

        let initialGuide = CrosshairGeometry(view: guideView)
        check(initialGuide.subviewCount == 4
              && initialGuide.hoverLayerCount == 1
              && initialGuide.chromeLayerCount == 1
              && initialGuide.bandCount == 2,
              "the overlay installs one chrome layer, one hover-highlight layer and exactly two guide bands "
              + "(got \(initialGuide.subviewCount) subviews: chrome \(initialGuide.chromeLayerCount), "
              + "hover \(initialGuide.hoverLayerCount), bands \(initialGuide.bandCount))")
        check(initialGuide.horizontalHidden && initialGuide.verticalHidden,
              "no guide before the pointer position is known")

        // Guide geometry at three horizontal positions: the crossing point is
        // the pointer's own point in this view, and each line spans the display.
        let guidePoints: [(name: String, cg: CGPoint)] = [
            ("left", CGPoint(x: 80, y: 300)),
            ("middle", CGPoint(x: primaryFrame.midX, y: 420)),
            ("right", CGPoint(x: primaryFrame.maxX - 60, y: 260)),
        ]
        for point in guidePoints {
            primaryFixture.crosshair(cgPoint: point.cg)
            let geometry = CrosshairGeometry(view: guideView)
            let expected = primaryFixture.localPoint(cgPoint: point.cg)
            check(!geometry.horizontalHidden && !geometry.verticalHidden,
                  "\(point.name): both guides are visible while aiming")
            if let y = geometry.lineY, let x = geometry.lineX {
                check(abs(y - expected.y) <= 1,
                      "\(point.name): horizontal line y=\(y) equals the pointer y=\(expected.y) (±1pt)")
                check(abs(x - expected.x) <= 1,
                      "\(point.name): vertical line x=\(x) equals the pointer x=\(expected.x) (±1pt)")
            } else {
                check(false, "\(point.name): both guide lines are positioned")
            }
            if let band = geometry.horizontal {
                check(band.frame.minX == guideView.bounds.minX
                      && band.frame.width == guideView.bounds.width,
                      "\(point.name): the horizontal line spans the whole display width")
            }
            if let band = geometry.vertical {
                check(band.frame.minY == guideView.bounds.minY
                      && band.frame.height == guideView.bounds.height,
                      "\(point.name): the vertical line spans the whole display height")
            }
            check(geometry.horizontalSubpathCount == 1 && geometry.verticalSubpathCount == 1,
                  "\(point.name): each band draws exactly one line segment")
        }

        // Style: solid, 1.5pt, systemGray at 50%. A dashed or thin guide was
        // the rejected snap-window shape; this pins the 1.0.25 one.
        guard let horizontalLayer = CrosshairGeometry(view: guideView).horizontalLayer,
              let verticalLayer = CrosshairGeometry(view: guideView).verticalLayer else {
            preconditionFailure("each guide band owns one shape layer")
        }
        for (name, layer) in [("horizontal", horizontalLayer), ("vertical", verticalLayer)] {
            check(abs(layer.lineWidth - 1.5) < 0.001, "\(name) guide is 1.5pt")
            check(layer.lineDashPattern == nil || layer.lineDashPattern?.isEmpty == true,
                  "\(name) guide is solid")
            let expectedGray = NSColor.systemGray.withAlphaComponent(0.5)
            if let components = rgbaComponents(layer.strokeColor),
               let expected = rgbaComponents(expectedGray.cgColor),
               components.count == 4, expected.count == 4 {
                check(zip(components, expected).allSatisfy { abs($0 - $1) < 0.02 },
                      "\(name) guide is systemGray at 50%")
            } else {
                check(false, "\(name) guide has an sRGB stroke colour")
            }
        }

        // Evidence renders: the same three pointer positions, offscreen, from
        // the live layer tree. The overlay is never ordered front.
        if let renderDirectory = ProcessInfo.processInfo.environment["BLINKCLIP_CROSSHAIR_RENDER_DIR"] {
            try? FileManager.default.createDirectory(atPath: renderDirectory, withIntermediateDirectories: true)
            for point in guidePoints {
                primaryFixture.crosshair(cgPoint: point.cg)
                let path = (renderDirectory as NSString)
                    .appendingPathComponent("crosshair-\(point.name).png")
                if renderOverlayLayers(guideView, background: 0.22, to: path) {
                    print("CROSSHAIR-RENDER \(point.name) \(path)")
                } else {
                    check(false, "\(point.name): the overlay renders to a PNG")
                }
            }
            primaryFixture.crosshair(cgPoint: guidePoints[1].cg)
        }

        // 200 pointer moves: the guides track every one of them, the frozen
        // snapshot is never repainted, and nothing schedules a repaint.
        guideView.display()
        guideView.needsDisplay = false
        let drawsBeforeMoves = guideView.drawCount
        let writesBeforeMoves = guideView.crosshairWriteCount
        var moveMismatches = 0
        for step in 0..<200 {
            let angle = CGFloat(Double(step) / 200.0 * 2.0 * Double.pi)
            let cgPoint = CGPoint(x: 300 + 120 * cos(angle), y: 250 + 90 * sin(angle))
            primaryFixture.crosshair(cgPoint: cgPoint)
            let geometry = CrosshairGeometry(view: guideView)
            let expected = primaryFixture.localPoint(cgPoint: cgPoint)
            guard let y = geometry.lineY, let x = geometry.lineX else {
                moveMismatches += 1
                continue
            }
            if abs(y - expected.y) > 1 || abs(x - expected.x) > 1 {
                moveMismatches += 1
            }
        }
        check(moveMismatches == 0,
              "200 pointer moves: both lines sit on the pointer every time (±1pt, mismatches \(moveMismatches))")
        check(guideView.drawCount == drawsBeforeMoves,
              "200 pointer moves call draw(_:) 0 times (got \(guideView.drawCount - drawsBeforeMoves))")
        check(!guideView.needsDisplay, "200 pointer moves schedule no snapshot repaint")
        let moveWrites = guideView.crosshairWriteCount - writesBeforeMoves
        check(moveWrites >= 200 && moveWrites <= 400,
              "200 pointer moves write the bands at most once per axis (no redundant writes) "
              + "(got \(moveWrites), expected 200…400)")

        // Visibility contract: only `.idle` / `.drawing` own the guides.
        primaryFixture.crosshair(cgPoint: CGPoint(x: 200, y: 200))
        check(!CrosshairGeometry(view: guideView).horizontalHidden,
              "idle shows the guides")
        guideView.selectionLocked = true
        check(CrosshairGeometry(view: guideView).horizontalHidden
              && CrosshairGeometry(view: guideView).verticalHidden,
              "a locked selection hides the guides")
        guideView.selectionLocked = false
        guideView.scrollCaptureActive = true
        check(CrosshairGeometry(view: guideView).horizontalHidden,
              "scroll capture hides the guides")
        guideView.scrollCaptureActive = false
        guideView.selectionInteractionEnabled = false
        check(CrosshairGeometry(view: guideView).horizontalHidden,
              "editor hand-off hides the guides")
        guideView.selectionInteractionEnabled = true
        primaryFixture.crosshair(cgPoint: CGPoint(x: 200, y: 200))
        check(!CrosshairGeometry(view: guideView).horizontalHidden,
              "resuming the overlay shows the guides again")
        guideView.updateSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 160))
        check(CrosshairGeometry(view: guideView).horizontalHidden
              && CrosshairGeometry(view: guideView).verticalHidden,
              "an established selection hides the guides")

        // --- 设置开关：关闭「显示十字辅助线」只摘掉两条辅线 --------------
        // 偏好缺键 = 开（升级上来的用户与之前完全一致）；关掉后同一个指针位置也不再
        // 出现辅线，选框本体 / 尺寸标签 / hover 高亮 / 两个 band 视图一律照旧。
        let toggleFixture = HoverFixture(
            displayFrame: primaryFrame,
            windows: orderedWindows.map { ($0.0, $0.1, false) }
        )
        let toggleView = toggleFixture.view
        let storedGuidePreference = UserDefaults.standard.object(forKey: BlinkClipScreenshotSettings.showCrosshairGuidesKey)
        defer {
            if let storedGuidePreference {
                UserDefaults.standard.set(storedGuidePreference, forKey: BlinkClipScreenshotSettings.showCrosshairGuidesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: BlinkClipScreenshotSettings.showCrosshairGuidesKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: BlinkClipScreenshotSettings.showCrosshairGuidesKey)
        check(BlinkClipScreenshotSettings.showCrosshairGuides, "an unset preference reads as on")
        check(toggleView.crosshairGuidesEnabled, "a fresh overlay starts with the guides on")
        toggleFixture.crosshair(cgPoint: CGPoint(x: 200, y: 200))
        check(!CrosshairGeometry(view: toggleView).horizontalHidden
              && !CrosshairGeometry(view: toggleView).verticalHidden,
              "the toggle is on: both guides are visible")
        toggleView.crosshairGuidesEnabled = false
        check(CrosshairGeometry(view: toggleView).horizontalHidden
              && CrosshairGeometry(view: toggleView).verticalHidden,
              "the toggle is off: both guides are hidden at the same pointer position")
        toggleFixture.crosshair(cgPoint: CGPoint(x: 260, y: 240))
        let guidesOffGeometry = CrosshairGeometry(view: toggleView)
        check(guidesOffGeometry.horizontalHidden && guidesOffGeometry.verticalHidden,
              "the toggle is off: moving the pointer does not bring the guides back")
        check(guidesOffGeometry.bandCount == 2
              && guidesOffGeometry.chromeLayerCount == 1
              && guidesOffGeometry.hoverLayerCount == 1,
              "the toggle only hides the two guides: chrome, hover highlight and both band views stay installed")
        // 选框本体仍在：建立选区照样写 chrome 图层，尺寸标签也照旧有值。
        let chromeWritesBeforeSelection = toggleView.selectionChromeWriteCount
        toggleView.updateSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 160))
        check(toggleView.selectionChromeWriteCount > chromeWritesBeforeSelection,
              "the selection chrome still writes its layer with the guides off")
        check(toggleView.currentSelectionRect == NSRect(x: 100, y: 100, width: 200, height: 160),
              "the selection rect is unchanged with the guides off")
        UserDefaults.standard.set(false, forKey: BlinkClipScreenshotSettings.showCrosshairGuidesKey)
        check(!BlinkClipScreenshotSettings.showCrosshairGuides, "a stored false reads back as off")
        let reopenedView = HoverFixture(
            displayFrame: primaryFrame,
            windows: orderedWindows.map { ($0.0, $0.1, false) }
        )
        check(!reopenedView.view.crosshairGuidesEnabled,
              "a new overlay honours the stored off preference")
        UserDefaults.standard.set(true, forKey: BlinkClipScreenshotSettings.showCrosshairGuidesKey)
        let reopenedOnView = HoverFixture(
            displayFrame: primaryFrame,
            windows: orderedWindows.map { ($0.0, $0.1, false) }
        )
        reopenedOnView.crosshair(cgPoint: CGPoint(x: 200, y: 200))
        check(reopenedOnView.view.crosshairGuidesEnabled,
              "a new overlay honours the stored on preference")
        check(!CrosshairGeometry(view: reopenedOnView.view).horizontalHidden
              && !CrosshairGeometry(view: reopenedOnView.view).verticalHidden,
              "the toggle is on again: both guides are visible")

        // A single pointer position is mirrored to every display, exactly like
        // `OverlayWindowController` does: the horizontal line continues onto
        // the neighbouring screen, the vertical line only lands on the
        // pointer's own screen. Driven by real `mouseMoved` events.
        let crossFixture = HoverFixture(
            displayFrame: primaryFrame,
            windows: orderedWindows.map { ($0.0, $0.1, false) }
        )
        let crossView = crossFixture.view
        let rightFrame = NSRect(x: primaryFrame.maxX, y: primaryFrame.minY, width: 1200, height: 900)
        let rightWindowCG = CGRect(x: primaryFrame.maxX + 100, y: 300, width: 300, height: 200)
        let rightFixture = HoverFixture(
            displayFrame: rightFrame,
            windows: [(7101, rightWindowCG, false)]
        )
        let mirrored: (NSPoint) -> Void = { screenPoint in
            crossView.updateCrosshair(globalPoint: screenPoint)
            rightFixture.view.updateCrosshair(globalPoint: screenPoint)
        }
        crossView.onCrosshairMoved = mirrored
        rightFixture.view.onCrosshairMoved = mirrored

        // The pointer sits on the right-hand display.
        let onRightCG = CGPoint(x: rightWindowCG.midX, y: 400)
        let rightLocal = rightFixture.localPoint(cgPoint: onRightCG)
        check(rightFixture.mouse(.mouseMoved, at: rightLocal),
              "the harness can synthesise a real pointer move")
        let rightGeometry = CrosshairGeometry(view: rightFixture.view)
        let primaryGeometry = CrosshairGeometry(view: crossView)
        check(rightFixture.window.frame == rightFrame,
              "off-screen fixture window keeps its requested frame (got \(rightFixture.window.frame))")
        if let rightY = rightGeometry.lineY, let primaryY = primaryGeometry.lineY {
            check(abs(rightY - rightLocal.y) <= 1,
                  "the pointer's own display draws the horizontal line through the pointer "
                  + "(got \(rightY), expected \(rightLocal.y))")
            check(abs(primaryY - rightY) <= 1,
                  "the horizontal line is continuous across displays (primary \(primaryY), right \(rightY))")
        } else {
            check(false, "both displays draw the horizontal guide for a shared pointer")
        }
        check(primaryGeometry.verticalHidden,
              "the vertical line stays off the display the pointer is not on")
        if let rightX = rightGeometry.lineX {
            check(abs(rightX - rightLocal.x) <= 1,
                  "the pointer's own display draws the vertical line through the pointer")
        } else {
            check(false, "the pointer's own display shows the vertical line")
        }

        // The pointer moves back onto the primary display: the vertical line
        // is now there and gone from the right-hand display.
        let onPrimary = NSPoint(x: crossView.bounds.midX, y: 300)
        check(crossFixture.mouse(.mouseMoved, at: onPrimary),
              "the harness can synthesise a pointer move on the primary display")
        check(!CrosshairGeometry(view: crossView).verticalHidden,
              "the vertical line appears on the display the pointer is on")
        if let x = CrosshairGeometry(view: crossView).lineX {
            check(abs(x - onPrimary.x) <= 1,
                  "the vertical line follows the pointer on the primary display")
        }
        check(CrosshairGeometry(view: rightFixture.view).verticalHidden,
              "the vertical line disappears from the display the pointer left")
        check(!CrosshairGeometry(view: rightFixture.view).horizontalHidden,
              "the horizontal line still spans the display the pointer left")
        if let renderDirectory = ProcessInfo.processInfo.environment["BLINKCLIP_CROSSHAIR_RENDER_DIR"] {
            let path = (renderDirectory as NSString)
                .appendingPathComponent("crosshair-second-display-horizontal-only.png")
            if renderOverlayLayers(rightFixture.view, background: 0.22, to: path) {
                print("CROSSHAIR-RENDER second-display \(path)")
            } else {
                check(false, "the second display's guide renders to a PNG")
            }
        }
        crossView.onCrosshairMoved = nil
        rightFixture.view.onCrosshairMoved = nil

        // A display above the primary exercises the CG → AppKit Y flip. The
        // flip must use the primary display's height (the shared origin), not
        // the secondary display's own height.
        let aboveHeight: CGFloat = 900
        let aboveFrame = NSRect(x: 0, y: primaryHeight, width: 1200, height: aboveHeight)
        let aboveFixture = HoverFixture(displayFrame: aboveFrame, windows: [])
        let aboveCG = CGPoint(x: 400, y: -150)
        aboveFixture.crosshair(cgPoint: aboveCG)
        let aboveGeometry = CrosshairGeometry(view: aboveFixture.view)
        let expectedAbove = aboveFixture.localPoint(cgPoint: aboveCG)
        if let y = aboveGeometry.lineY, let x = aboveGeometry.lineX {
            check(abs(y - expectedAbove.y) <= 1,
                  "the Y flip is correct on a display above the primary "
                  + "(got \(y), expected \(expectedAbove.y))")
            check(abs(x - expectedAbove.x) <= 1,
                  "the vertical line is correct on a display above the primary")
        } else {
            check(false, "a display above the primary shows both guides")
        }
        let localHeightFlip = aboveHeight + aboveCG.y
        check(abs((aboveGeometry.lineY ?? .nan) - localHeightFlip) > 1,
              "the flip is not computed against the secondary display's own height")

        // Own/twin product chrome is never a hover target.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let floatingLayer = Int(NSWindow.Level.floating.rawValue)
        let screenSaverLayer = Int(CGWindowLevelForKey(.screenSaverWindow))
        let chromeDetector = WindowDetector()
        chromeDetector.apply([
            DetectedWindow(name: "own HUD", windowID: 9001, layer: screenSaverLayer,
                           frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                           ownerPID: ownPID, isProductChrome: true),
            DetectedWindow(name: "twin HUD", windowID: 9002, layer: floatingLayer,
                           frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                           ownerPID: 9902, isProductChrome: true),
            DetectedWindow(name: "document", windowID: 9003, layer: 0,
                           frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                           ownerPID: 9903, isProductChrome: false),
        ])
        check(chromeDetector.windowAt(cgPoint: CGPoint(x: 10, y: 10))?.windowID == 9003,
              "own/twin floating chrome is skipped; the document underneath is the target")
        // Own popup menus sit at the popup level and stay valid capture targets;
        // only this process's screen-saver-level chrome is dropped.
        let ownPopupDetector = WindowDetector()
        ownPopupDetector.apply([
            DetectedWindow(name: "own popup", windowID: 9011, layer: 101,
                           frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                           ownerPID: ownPID, isProductChrome: false),
            DetectedWindow(name: "document", windowID: 9012, layer: 0,
                           frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                           ownerPID: 9903, isProductChrome: false),
        ])
        check(ownPopupDetector.windowAt(cgPoint: CGPoint(x: 10, y: 10))?.windowID == 9011,
              "the app's own popup menu stays a capturable hover target")
        check(WindowDetector.isProductChrome(
                layer: screenSaverLayer, ownerPID: ownPID, ownPID: ownPID,
                ownerBundleID: "com.other", ownBundleID: "com.example.app"),
              "this process's screen-saver chrome is product chrome")
        check(!WindowDetector.isProductChrome(
                layer: floatingLayer, ownerPID: ownPID, ownPID: ownPID,
                ownerBundleID: "com.other", ownBundleID: "com.example.app"),
              "this process's own popup-level windows are not product chrome")
        check(WindowDetector.isProductChrome(
                layer: floatingLayer, ownerPID: 4242, ownPID: ownPID,
                ownerBundleID: "com.example.app", ownBundleID: "com.example.app"),
              "a twin instance's floating chrome is product chrome")
        check(!WindowDetector.isProductChrome(
                layer: floatingLayer, ownerPID: 4242, ownPID: ownPID,
                ownerBundleID: "com.other", ownBundleID: "com.example.app"),
              "another product's floating window is not product chrome")
        check(!WindowDetector.isProductChrome(
                layer: 0, ownerPID: 4242, ownPID: ownPID,
                ownerBundleID: "com.example.app", ownBundleID: "com.example.app"),
              "a twin instance's normal window is still capturable")

        // Frame-sequence evidence: 240 samples paced at 120Hz with the pointer
        // sweeping the display. Every sample must put both lines on the pointer
        // in the very same call, and `draw(_:)` must stay at zero throughout.
        // A fresh fixture: the view above was deliberately committed to
        // `.selected` to prove the guides hide there.
        let sweepFixture = HoverFixture(
            displayFrame: primaryFrame,
            windows: orderedWindows.map { ($0.0, $0.1, false) }
        )
        let sweepView = sweepFixture.view
        sweepView.display()
        sweepView.needsDisplay = false
        let sweepStart = ProcessInfo.processInfo.systemUptime
        let drawsBeforeSweep = sweepView.drawCount
        var sweepMismatches = 0
        var csvRows = ["index,timestamp_s,interval_ms,cg_x,cg_y,local_x,local_y,guide_x,guide_y"]
        var previousSampleTime = sweepStart
        for index in 0..<240 {
            let targetTime = sweepStart + Double(index) / 120.0
            let now = ProcessInfo.processInfo.systemUptime
            if targetTime > now {
                Thread.sleep(forTimeInterval: targetTime - now)
            }
            let phase = CGFloat(Double(index) / 240.0 * 2.0 * Double.pi)
            let cgPoint = CGPoint(
                x: primaryFrame.midX + 0.4 * primaryFrame.width * cos(phase),
                y: primaryFrame.midY + 0.4 * primaryFrame.height * sin(phase)
            )
            sweepFixture.crosshair(cgPoint: cgPoint)
            let sampledAt = ProcessInfo.processInfo.systemUptime
            let geometry = CrosshairGeometry(view: sweepView)
            let expected = sweepFixture.localPoint(cgPoint: cgPoint)
            guard let y = geometry.lineY, let x = geometry.lineX,
                  abs(y - expected.y) <= 1, abs(x - expected.x) <= 1 else {
                sweepMismatches += 1
                previousSampleTime = sampledAt
                continue
            }
            csvRows.append(String(
                format: "%d,%.6f,%.3f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f",
                index,
                sampledAt - sweepStart,
                (sampledAt - previousSampleTime) * 1000,
                cgPoint.x,
                cgPoint.y,
                expected.x,
                expected.y,
                x,
                y
            ))
            previousSampleTime = sampledAt
        }
        let sweepElapsed = ProcessInfo.processInfo.systemUptime - sweepStart
        let measuredRate = 240.0 / max(sweepElapsed, 0.000_001)
        check(sweepMismatches == 0,
              "120Hz sweep: every one of 240 samples has both lines on the pointer (±1pt, mismatches \(sweepMismatches))")
        check(measuredRate >= 100,
              "the sweep ran at \(Int(measuredRate)) samples/s (target 120Hz)")
        let drawsDuringSweep = sweepView.drawCount - drawsBeforeSweep
        check(drawsDuringSweep == 0,
              "240 pointer samples call draw(_:) 0 times (got \(drawsDuringSweep))")
        check(!sweepView.needsDisplay, "240 pointer samples schedule no snapshot repaint")

        // Dragging is back to plain geometry: the box follows the pointer, no
        // edge is glued to a window, and the snapshot is never repainted.
        let dragWindowCG = CGRect(x: 100, y: 100, width: 400, height: 300)
        let dragWindow = primaryFixture.localRect(cgFrame: dragWindowCG)
        let dragFixture = HoverFixture(displayFrame: primaryFrame, windows: [(7301, dragWindowCG, false)])
        let dragView = dragFixture.view
        let dragDelegate = DragDelegate()
        dragView.delegate = dragDelegate
        let start = NSPoint(x: dragWindow.minX + 60, y: dragWindow.minY + 60)

        dragView.display()
        dragView.needsDisplay = false
        let drawsBeforeDrag = dragView.drawCount
        let chromeWritesBeforeDrag = dragView.selectionChromeWriteCount

        dragFixture.mouse(.leftMouseDown, at: start)
        dragFixture.mouse(.leftMouseDragged, at: NSPoint(x: dragWindow.maxX + 3, y: start.y + 140))
        check(dragView.currentSelectionRect?.maxX == dragWindow.maxX + 3,
              "a dragged edge 3pt from a window edge is not snapped "
              + "(got \(String(describing: dragView.currentSelectionRect?.maxX)), "
              + "expected \(dragWindow.maxX + 3))")
        check(dragView.currentSelectionRect?.maxY == start.y + 140,
              "the dragged box ends exactly at the pointer on both axes")
        for step in 0..<120 {
            let angle = CGFloat(Double(step) / 120.0 * 2.0 * Double.pi)
            dragFixture.mouse(.leftMouseDragged, at: NSPoint(
                x: dragWindow.maxX + 3 * cos(angle),
                y: start.y + 140 + 2 * sin(angle)
            ))
        }
        let drawsDuringDrag = dragView.drawCount - drawsBeforeDrag
        let chromeWritesDuringDrag = dragView.selectionChromeWriteCount - chromeWritesBeforeDrag
        let repaintScheduled = dragView.needsDisplay
        check(drawsDuringDrag == 0,
              "120 drag samples call draw(_:) 0 times (got \(drawsDuringDrag))")
        check(!repaintScheduled, "120 drag samples schedule no snapshot repaint")
        check(chromeWritesDuringDrag > 0,
              "a drag writes the chrome layer instead of the snapshot")
        // Settle on a known point before the mouse-up commits the rect.
        dragFixture.mouse(.leftMouseDragged, at: NSPoint(x: dragWindow.maxX + 3, y: start.y + 140))
        dragFixture.mouse(.leftMouseUp, at: NSPoint(x: dragWindow.maxX + 3, y: start.y + 140))
        let committed = dragDelegate.completed.last?.rect
        check(committed?.maxX == dragWindow.maxX + 3,
              "the committed capture rect is the raw pointer rect "
              + "(got \(String(describing: committed?.maxX)))")
        check(CrosshairGeometry(view: dragView).horizontalHidden,
              "the guides stay hidden once the selection is committed")

        print("REV-CROSSHAIR bands=2 lineWidth=1.5 solid=yes "
              + "sweepSamples=240 sweepRate=\(String(format: "%.1f", measuredRate))Hz "
              + "sweepMismatches=\(sweepMismatches) sweepDraws=\(drawsDuringSweep) "
              + "moveWrites=\(moveWrites) "
              + "dragDraws=\(drawsDuringDrag) dragChromeWrites=\(chromeWritesDuringDrag) "
              + "repaintScheduled=\(repaintScheduled) committedMaxX=\(committed?.maxX ?? .nan)")

        reportCrosshairSweep(rows: csvRows, measuredRate: measuredRate,
                             primaryHeight: primaryHeight, displayFrame: primaryFrame)


        // --- CL: the size label never leaves the screen's visibleFrame ------
        // The capsule is chrome and stays outside the selection whenever it
        // fits. A selection hugging an edge used to push it off the screen,
        // where macOS crops it. The render view below covers exactly the main
        // display's `visibleFrame` (origin included), so "inside the bitmap"
        // and "inside visibleFrame" are the same statement — measured, not
        // inferred. Both the capture overlay and the editor's live chrome are
        // rendered, because they share the one painter.
        guard let display = NSScreen.main else {
            preconditionFailure("a main screen is required to measure visibleFrame")
        }
        let visible = display.visibleFrame
        let clampWindow = NSWindow(
            contentRect: NSRect(origin: visible.origin, size: visible.size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        clampWindow.isReleasedWhenClosed = false
        let clampContainer = NSView(frame: NSRect(origin: .zero, size: visible.size))
        clampWindow.contentView = clampContainer
        let clampView = SelectionView(frame: clampContainer.bounds)
        clampContainer.addSubview(clampView)
        clampView.backgroundSnapshot = solidBackground(size: visible.size, gray: 0.75)
        clampView.selectionInteractionEnabled = true
        let clampEditorOverlay = SelectionChromeOverlay(frame: clampContainer.bounds)
        clampEditorOverlay.selectionView = clampView
        clampContainer.addSubview(clampEditorOverlay)

        let screenTolerance: CGFloat = 0.01
        let renderRoot = ProcessInfo.processInfo.environment["BLINKCLIP_LABEL_RENDER_DIR"]
        if let renderRoot {
            try? FileManager.default.createDirectory(atPath: renderRoot, withIntermediateDirectories: true)
        }

        struct LabelCase {
            let name: String
            let rect: NSRect
            let flippedBelow: Bool
            let allowsOverlap: Bool
        }
        let labelCases = [
            LabelCase(name: "top", rect: NSRect(x: visible.minX + 300, y: visible.maxY - 220, width: 320, height: 220),
                      flippedBelow: true, allowsOverlap: false),
            LabelCase(name: "bottom", rect: NSRect(x: visible.minX + 300, y: visible.minY, width: 320, height: 220),
                      flippedBelow: false, allowsOverlap: false),
            LabelCase(name: "left", rect: NSRect(x: visible.minX, y: visible.minY + 380, width: 44, height: 260),
                      flippedBelow: false, allowsOverlap: false),
            LabelCase(name: "right", rect: NSRect(x: visible.maxX - 44, y: visible.minY + 380, width: 44, height: 260),
                      flippedBelow: false, allowsOverlap: false),
            LabelCase(name: "default", rect: NSRect(x: visible.minX + 600, y: visible.minY + 450, width: 300, height: 200),
                      flippedBelow: false, allowsOverlap: false),
            // Extreme: full-height selection, no room above or below on this
            // display. The capsule is allowed to sit over the selection, but it
            // still must stay completely inside visibleFrame.
            LabelCase(name: "full-height", rect: NSRect(x: visible.minX + 200, y: visible.minY, width: 400, height: visible.height),
                      flippedBelow: false, allowsOverlap: true),
        ]

        var labelRects: [String: NSRect] = [:]
        var clampObservations: [[String: Any]] = []
        for item in labelCases {
            clampView.updateSelectionRect(item.rect)
            clampEditorOverlay.update(rect: item.rect, active: true)
            let label = SelectionView.sizeLabelRect(for: item.rect, in: clampView)
            labelRects[item.name] = label
            let onScreen = clampWindow.convertToScreen(clampView.convert(label, to: nil))
            check(onScreen.minX >= visible.minX - screenTolerance
                  && onScreen.maxX <= visible.maxX + screenTolerance
                  && onScreen.minY >= visible.minY - screenTolerance
                  && onScreen.maxY <= visible.maxY + screenTolerance,
                  "\(item.name): label \(onScreen) must be inside visibleFrame \(visible)")
            check(label.minX >= -screenTolerance && label.maxX <= visible.width + screenTolerance
                  && label.minY >= -screenTolerance && label.maxY <= visible.height + screenTolerance,
                  "\(item.name): label \(label) must be inside the rendered canvas")

            let overlap = item.rect.intersection(label)
            let overlapArea = overlap.isNull ? 0 : overlap.width * overlap.height
            clampObservations.append([
                "case": item.name,
                "selection": [item.rect.minX, item.rect.minY, item.rect.width, item.rect.height],
                "label": [label.minX, label.minY, label.width, label.height],
                "labelOnScreen": [onScreen.minX, onScreen.minY, onScreen.width, onScreen.height],
                "visibleFrame": [visible.minX, visible.minY, visible.width, visible.height],
                "overlapAreaWithSelection": overlapArea,
                "placement": item.flippedBelow ? "below" : (item.allowsOverlap ? "over-selection" : "above"),
            ])
            if item.allowsOverlap {
                check(overlapArea > 0, "\(item.name): the no-room case is allowed to overlap the selection")
            } else {
                check(overlapArea < 0.01, "\(item.name): label must not overlap the selection (area \(overlapArea))")
            }
            if item.flippedBelow {
                check(label.maxY <= item.rect.minY - 8 + screenTolerance,
                      "top edge: label must flip below the selection (label maxY \(label.maxY), selection minY \(item.rect.minY))")
            } else if !item.allowsOverlap {
                check(label.minY >= item.rect.maxY + 8 - screenTolerance,
                      "\(item.name): label must sit 8pt above the selection")
            }
            switch item.name {
            case "left":
                check(label.minX >= visible.minX + 4 - screenTolerance, "left edge: 4pt screen margin")
                check(label.minX > item.rect.minX + 1, "left edge: label slid right instead of clipping")
            case "right":
                check(label.maxX <= visible.maxX - 4 + screenTolerance, "right edge: 4pt screen margin")
                check(label.minX < item.rect.minX - 1, "right edge: label slid left instead of clipping")
            case "default":
                check(abs(label.minX - item.rect.minX) < screenTolerance, "default: left edges stay aligned")
                check(abs(label.minY - (item.rect.maxY + 8)) < screenTolerance, "default: label stays 8pt above")
            default:
                break
            }

            guard let render = LabelBitmap(clampView) else {
                preconditionFailure("cannot render the clamped selection view")
            }
            let capsule = render.count(in: label.insetBy(dx: 2, dy: 2), matching: isAccentBlue)
            check(capsule > 300, "\(item.name): capsule painted inside labelRect (accent pixels \(capsule))")
            let glyphs = render.count(in: label, matching: isLabelWhite)
            check(glyphs > 20, "\(item.name): size text painted (white pixels \(glyphs))")
            let edgeBands: [(String, NSRect)] = [
                ("left", NSRect(x: label.minX + 0.25, y: label.midY - 4, width: 1.5, height: 8)),
                ("right", NSRect(x: label.maxX - 1.75, y: label.midY - 4, width: 1.5, height: 8)),
                ("bottom", NSRect(x: label.midX - 4, y: label.minY + 0.25, width: 8, height: 1.5)),
                ("top", NSRect(x: label.midX - 4, y: label.maxY - 1.75, width: 8, height: 1.5)),
            ]
            for (edge, band) in edgeBands {
                let painted = render.count(in: band, matching: isAccentBlue)
                check(painted > 0, "\(item.name): capsule \(edge) edge is visible (not clipped)")
            }
            if !item.allowsOverlap {
                // 14pt inside the selection excludes the 1pt frame, the 4pt
                // edge bars and the 12pt corner brackets: only an intruding
                // label could leave accent pixels there.
                let intrusion = render.count(in: item.rect.insetBy(dx: 14, dy: 14), matching: isAccentBlue)
                check(intrusion == 0, "\(item.name): no label pixels inside the selection (found \(intrusion))")
            }

            if let renderRoot {
                let canvas = NSRect(origin: .zero, size: visible.size)
                writePNG(render.image, sourceSize: visible.size, crop: canvas, scale: 1,
                         to: "\(renderRoot)/cl-label-\(item.name).png")
                let crop = label.insetBy(dx: -8, dy: -8).intersection(canvas)
                writePNG(render.image, sourceSize: visible.size, crop: crop, scale: 4,
                         to: "\(renderRoot)/cl-label-\(item.name)-4x.png")
            }
        }

        // Screen coordinates must be mapped through the window's own frame, not
        // assumed to equal view coordinates: the editor's panel is a small
        // window somewhere on the display, not a full-screen overlay. This
        // window sits in the screen's top-right corner with a selection touching
        // both the top and the right screen edges, so one case exercises the
        // flip-down rule and the horizontal slide through a non-zero origin.
        let offsetSize = NSSize(width: 600, height: 460)
        let offsetWindow = NSWindow(
            contentRect: NSRect(
                origin: NSPoint(x: visible.maxX - offsetSize.width,
                                y: visible.maxY - offsetSize.height),
                size: offsetSize
            ),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        offsetWindow.isReleasedWhenClosed = false
        let offsetView = SelectionView(frame: NSRect(origin: .zero, size: offsetSize))
        offsetWindow.contentView = offsetView
        let offsetRect = NSRect(x: offsetSize.width - 40, y: offsetSize.height - 220, width: 40, height: 220)
        offsetView.updateSelectionRect(offsetRect)
        let offsetLabel = SelectionView.sizeLabelRect(for: offsetRect, in: offsetView)
        let offsetOnScreen = offsetWindow.convertToScreen(offsetView.convert(offsetLabel, to: nil))
        let offsetOverlap = offsetRect.intersection(offsetLabel)
        let offsetOverlapArea = offsetOverlap.isNull ? 0 : offsetOverlap.width * offsetOverlap.height
        check(offsetOnScreen.minX >= visible.minX - screenTolerance
              && offsetOnScreen.maxX <= visible.maxX + screenTolerance
              && offsetOnScreen.minY >= visible.minY - screenTolerance
              && offsetOnScreen.maxY <= visible.maxY + screenTolerance,
              "offset window: label \(offsetOnScreen) must be inside visibleFrame \(visible)")
        check(offsetLabel.maxY <= offsetRect.minY - 8 + screenTolerance,
              "offset window: label must flip below the selection")
        check(offsetOnScreen.maxX <= visible.maxX - 4 + screenTolerance,
              "offset window: label keeps the 4pt right margin")
        check(offsetLabel.minX < offsetRect.minX - 1,
              "offset window: label slid left of the selection")
        check(offsetOverlapArea < 0.01, "offset window: label must not overlap the selection")
        if let offsetRender = LabelBitmap(offsetView) {
            let capsule = offsetRender.count(in: offsetLabel.insetBy(dx: 2, dy: 2), matching: isAccentBlue)
            check(capsule > 300, "offset window: capsule painted (accent pixels \(capsule))")
            let bands: [(String, NSRect)] = [
                ("left", NSRect(x: offsetLabel.minX + 0.25, y: offsetLabel.midY - 4, width: 1.5, height: 8)),
                ("right", NSRect(x: offsetLabel.maxX - 1.75, y: offsetLabel.midY - 4, width: 1.5, height: 8)),
                ("bottom", NSRect(x: offsetLabel.midX - 4, y: offsetLabel.minY + 0.25, width: 8, height: 1.5)),
                ("top", NSRect(x: offsetLabel.midX - 4, y: offsetLabel.maxY - 1.75, width: 8, height: 1.5)),
            ]
            for (edge, band) in bands {
                check(offsetRender.count(in: band, matching: isAccentBlue) > 0,
                      "offset window: capsule \(edge) edge is visible (not clipped)")
            }
            if let renderRoot {
                writePNG(offsetRender.image, sourceSize: offsetSize, crop: NSRect(origin: .zero, size: offsetSize),
                         scale: 1, to: "\(renderRoot)/cl-label-offset-top-right.png")
                let crop = offsetLabel.insetBy(dx: -8, dy: -8)
                    .intersection(NSRect(origin: .zero, size: offsetSize))
                writePNG(offsetRender.image, sourceSize: offsetSize, crop: crop, scale: 4,
                         to: "\(renderRoot)/cl-label-offset-top-right-4x.png")
            }
        } else {
            preconditionFailure("cannot render the offset selection view")
        }
        let offsetSelectionOnScreen = offsetWindow.convertToScreen(offsetView.convert(offsetRect, to: nil))
        clampObservations.append([
            "case": "offset-top-right",
            "selection": [offsetSelectionOnScreen.minX, offsetSelectionOnScreen.minY,
                          offsetSelectionOnScreen.width, offsetSelectionOnScreen.height],
            "label": [offsetLabel.minX, offsetLabel.minY, offsetLabel.width, offsetLabel.height],
            "labelOnScreen": [offsetOnScreen.minX, offsetOnScreen.minY, offsetOnScreen.width, offsetOnScreen.height],
            "visibleFrame": [visible.minX, visible.minY, visible.width, visible.height],
            "overlapAreaWithSelection": offsetOverlapArea,
            "placement": "below",
        ])
        offsetWindow.orderOut(nil)
        offsetWindow.contentView = nil
        offsetWindow.close()

        if let renderRoot,
           let payload = try? JSONSerialization.data(withJSONObject: [
               "passed": true,
               "visibleFrame": [visible.minX, visible.minY, visible.width, visible.height],
               "cases": clampObservations,
           ], options: [.prettyPrinted, .sortedKeys]) {
            try? payload.write(to: URL(fileURLWithPath: "\(renderRoot)/cl-label-clamp-geometry.json"))
        }

        // Editor parity under clamping: the editor's layer must paint the very
        // same clamped capsule as the capture overlay (one shared painter, one
        // geometry). Assert on strict-accent pixels only, so the dimming and
        // snapshot underneath cannot mask a difference.
        let parityCase = labelCases[0]
        clampView.updateSelectionRect(parityCase.rect)
        clampEditorOverlay.update(rect: parityCase.rect, active: true)
        // Parity is judged on the chrome alone, with the same (absent)
        // background as `EditorChromeParityHarness`: an opaque snapshot changes
        // how the anti-aliased capsule edge composites and would blur the
        // pixel-set comparison.
        let parityBackground = clampView.backgroundSnapshot
        clampView.backgroundSnapshot = nil
        clampEditorOverlay.isHidden = true
        guard let captureChrome = LabelBitmap(clampContainer) else {
            preconditionFailure("cannot render the capture overlay chrome")
        }
        clampEditorOverlay.isHidden = false
        clampView.isHidden = true
        guard let editorChrome = LabelBitmap(clampContainer) else {
            preconditionFailure("cannot render the editor chrome")
        }
        clampView.isHidden = false
        clampView.backgroundSnapshot = parityBackground
        let captureMask = captureChrome.accentPixels()
        let editorMask = editorChrome.accentPixels()
        let onlyCapture = captureMask.subtracting(editorMask).count
        let onlyEditor = editorMask.subtracting(captureMask).count
        check(!captureMask.isEmpty, "clamped chrome must paint accent pixels")
        check(onlyCapture == 0 && onlyEditor == 0,
              "editor chrome must be pixel-identical to the overlay under clamping"
              + " (only-capture \(onlyCapture), only-editor \(onlyEditor))")
        let parityLabel = labelRects["top"] ?? .zero
        check(captureChrome.count(in: parityLabel.insetBy(dx: 2, dy: 2), matching: isAccentBlue) > 300,
              "the clamped label is part of the parity comparison")

        clampWindow.orderOut(nil)
        clampContainer.subviews.forEach { $0.removeFromSuperview() }
        clampWindow.contentView = nil
        clampWindow.close()

        // The reported timing, end to end, and the strongest assertion the
        // process can make about the fix: drive the real controller through
        // five open/close cycles while the cursor-hide entry points are
        // intercepted, and require that nobody calls them at all. A cursor that
        // is never hidden cannot stay hidden — that is the whole CUR4 contract.
        var hideCalls = 0
        var unhideCalls = 0
        let hideSelector = NSSelectorFromString("hide")
        let unhideSelector = NSSelectorFromString("unhide")
        let hideMethod = class_getClassMethod(NSCursor.self, hideSelector)!
        let unhideMethod = class_getClassMethod(NSCursor.self, unhideSelector)!
        let originalHide = method_getImplementation(hideMethod)
        let originalUnhide = method_getImplementation(unhideMethod)
        let hideBlock: @convention(block) (AnyObject) -> Void = { _ in hideCalls += 1 }
        let unhideBlock: @convention(block) (AnyObject) -> Void = { _ in unhideCalls += 1 }
        let hideIMP = imp_implementationWithBlock(hideBlock)
        let unhideIMP = imp_implementationWithBlock(unhideBlock)
        method_setImplementation(hideMethod, hideIMP)
        method_setImplementation(unhideMethod, unhideIMP)
        defer {
            method_setImplementation(hideMethod, originalHide)
            method_setImplementation(unhideMethod, originalUnhide)
            imp_removeBlock(hideIMP)
            imp_removeBlock(unhideIMP)
        }

        for cycle in 0..<5 {
            fronted.removeAll()
            let controller = OverlayWindowController(
                postCaptureAction: .edit,
                snapshotProvider: SnapshotRecorder(),
                windowSnapshotLoader: { _ in .success([]) },
                eventTrackingStateProvider: { false },
                colorSamplerActiveProvider: { false },
                modalWindowProvider: { nil },
                onComplete: { _ in }
            )
            controller.activate()
            // The reported timing: the drag starts before the first frame, and
            // the session may lose activation while it is still on screen.
            NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)
            controller.cancel()
            check(controller.isCaptureSessionEnded,
                  "cycle \(cycle): drag-before-first-frame ends the session")
            controller.cancel()
            check(controller.isCaptureSessionEnded,
                  "cycle \(cycle): repeated cancellation stays harmless")
        }
        check(hideCalls == 0 && unhideCalls == 0,
              "five overlay sessions never hide or unhide the system cursor (hide=\(hideCalls), unhide=\(unhideCalls))")

        print("{\"passed\":true,\"checks\":\(checks),\"boundary\":\"Real capture controller, native window IDs and explicit snapshot exclusion request; injected snapshot provider and intercepted orderFrontRegardless (no desktop overlay, ScreenCaptureKit pixels, TCC, user clipboard, or physical key event)\"}")
    }
}
