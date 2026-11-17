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

/// Reads the snap-guide geometry out of the live view/layer tree — the same
/// numbers the window server receives, without a second copy of the layout
/// maths. The overlay installs exactly one guide subview; the pointer is the
/// system crosshair and is not part of this view at all.
private struct SnapGuideGeometry {
    let band: NSView?
    let subviewCount: Int
    let layer: CAShapeLayer?
    /// The hover highlight is a sibling layer of the guide (dimming cut-out,
    /// accent frame and size label). Counting it separately keeps the "exactly
    /// one guide layer, no self-drawn pointer" property meaningful after the
    /// hover chrome moved out of `draw(_:)`.
    let hoverLayerCount: Int

    private static func typeName(_ view: NSView) -> String {
        String(describing: type(of: view))
    }

    init(view: SelectionView) {
        let subviews = view.subviews
        subviewCount = subviews.count
        hoverLayerCount = subviews.filter { Self.typeName($0) == "HoverHighlightView" }.count
        let guides = subviews.filter { Self.typeName($0) == "SnapGuideView" }
        band = guides.count == 1 ? guides[0] : nil
        layer = band?.layer?.sublayers?.first as? CAShapeLayer
    }

    var frame: NSRect { band?.frame ?? .null }
    var isHidden: Bool { band?.isHidden ?? true }
    var dashPattern: [CGFloat] { (layer?.lineDashPattern ?? []).map { CGFloat($0.doubleValue) } }
    var pathBounds: CGRect? { layer?.path?.boundingBox }

    /// Number of move-to elements in the drawn path: one subpath for the four
    /// edges, three when the centre lines are enabled too.
    var subpathCount: Int {
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

private func rgbaComponents(_ color: CGColor?) -> [CGFloat]? {
    guard let color,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let converted = color.converted(to: space, intent: .defaultIntent, options: nil) else {
        return nil
    }
    return converted.components
}

/// One overlay-sized view plus an injected window list, so the production
/// hover → guide path can be driven with exact screen points and no pointer
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
        view.updateHover(screenPoint: NSPoint(
            x: cgPoint.x,
            y: (NSScreen.screens.first?.frame.height ?? 0) - cgPoint.y
        ))
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
private func reportSnapSweep(rows: [String], measuredRate: Double,
                             primaryHeight: CGFloat, displayFrame: NSRect) {
    print("SNAP-SWEEP samples=\(rows.count - 1) rate=\(String(format: "%.1f", measuredRate))Hz "
          + "primaryHeight=\(Int(primaryHeight)) display=\(Int(displayFrame.width))x\(Int(displayFrame.height))")
    guard let directory = ProcessInfo.processInfo.environment["SG_SNAP_EVIDENCE"],
          let data = rows.joined(separator: "\n").data(using: .utf8) else { return }
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let url = URL(fileURLWithPath: directory).appendingPathComponent("snap-guide-frames-120hz.csv")
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
        // --- SG: snap guides follow the hovered window, not the pointer -----
        // The guide is one layer drawn on the four edges of the window under
        // the pointer (plus optional centre lines). The pointer is the system
        // crosshair; nothing here draws or hides it. Moving inside one window
        // writes nothing; crossing into another window replaces the path
        // synchronously, so the guide jumps without a frame of lag.
        guard let mainScreen = NSScreen.main ?? NSScreen.screens.first else {
            preconditionFailure("a screen is required for the snap-guide checks")
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
        let snapView = primaryFixture.view

        let initialSnap = SnapGuideGeometry(view: snapView)
        check(initialSnap.subviewCount == 2 && initialSnap.hoverLayerCount == 1,
              "the overlay installs exactly one guide layer, one hover-highlight layer and no self-drawn pointer")
        check(initialSnap.isHidden, "no guide before the pointer is over a window")

        // A point inside A resolves to A's four edges in this view's coordinates.
        primaryFixture.hover(cgPoint: CGPoint(x: 200, y: 200))
        var snap = SnapGuideGeometry(view: snapView)
        check(!snap.isHidden, "hovering a window shows the guide")
        check(snap.frame == primaryFixture.localRect(cgFrame: winA),
              "the guide sits exactly on the hovered window's rect (got \(snap.frame))")
        if let bounds = snap.pathBounds {
            // The 1.5pt stroke is inset by half its width so it stays on the
            // window edge instead of spilling outside it.
            check(abs(bounds.width - (winA.width - 1.5)) < 0.01
                  && abs(bounds.height - (winA.height - 1.5)) < 0.01,
                  "the path spans the window's four edges (got \(bounds.size))")
        } else {
            check(false, "the guide has a drawn path")
        }
        check(snap.subpathCount == 1, "four edges are one closed subpath; no centre lines by default")

        // Style: dashed 6/4, 1.5pt, systemGray at 50%.
        guard let guideLayer = snap.layer else {
            preconditionFailure("the snap guide is one shape layer")
        }
        check(abs(guideLayer.lineWidth - 1.5) < 0.001, "the guide is 1.5pt")
        check(guideLayer.lineDashPattern?.map(\.doubleValue) == [6, 4],
              "the guide is dashed 6/4 (pattern \(String(describing: guideLayer.lineDashPattern)))")
        let expectedGray = NSColor.systemGray.withAlphaComponent(0.5)
        if let components = rgbaComponents(guideLayer.strokeColor),
           let expected = rgbaComponents(expectedGray.cgColor),
           components.count == 4, expected.count == 4 {
            check(zip(components, expected).allSatisfy { abs($0 - $1) < 0.02 },
                  "the guide is systemGray at 50%")
        } else {
            check(false, "the guide has an sRGB stroke colour")
        }

        // Centre lines are optional and off by default; turning them on writes
        // once and adds two subpaths to the same four-edge frame.
        snapView.showsGuideCenterLines = true
        snap = SnapGuideGeometry(view: snapView)
        check(snap.subpathCount == 3, "centre lines add exactly one horizontal and one vertical line")
        check(snap.frame == primaryFixture.localRect(cgFrame: winA),
              "centre lines do not move the four-edge rect")
        snapView.showsGuideCenterLines = false
        check(SnapGuideGeometry(view: snapView).subpathCount == 1, "turning centre lines off removes them again")

        // Same window, 200 points on a fast circle: zero repaint, zero guide
        // writes, zero hover-target changes, and the guide never moves.
        snapView.display()
        snapView.needsDisplay = false
        let drawBeforeCircle = snapView.drawCount
        let changesBeforeCircle = snapView.hoverTargetChangeCount
        let writesBeforeCircle = snapView.snapGuideWriteCount
        for step in 0..<200 {
            let angle = Double(step) / 200.0 * 2.0 * Double.pi
            primaryFixture.hover(cgPoint: CGPoint(
                x: 300 + 120 * cos(angle),
                y: 250 + 90 * sin(angle)
            ))
        }
        check(snapView.hoverTargetChangeCount == changesBeforeCircle,
              "200 moves inside one window change the hover target 0 times")
        check(snapView.snapGuideWriteCount == writesBeforeCircle,
              "200 moves inside one window write the guide 0 times")
        check(snapView.drawCount == drawBeforeCircle,
              "200 moves inside one window call draw(_:) 0 times")
        check(!snapView.needsDisplay, "200 moves inside one window schedule no repaint")
        check(SnapGuideGeometry(view: snapView).frame == primaryFixture.localRect(cgFrame: winA),
              "the guide is completely static while the pointer circles inside A")

        // Blank desktop hides the guide; coming back to a window shows it again.
        primaryFixture.hover(cgPoint: CGPoint(x: 1300, y: 900))
        check(SnapGuideGeometry(view: snapView).isHidden, "the guide disappears over blank desktop")
        check(primaryFixture.expectedTarget(CGPoint(x: 1300, y: 900)) == nil,
              "the blank point really is outside every test window")
        primaryFixture.hover(cgPoint: CGPoint(x: 560, y: 300))
        check(!SnapGuideGeometry(view: snapView).isHidden, "moving back onto a window shows the guide")
        check(SnapGuideGeometry(view: snapView).frame == primaryFixture.localRect(cgFrame: winB),
              "the guide jumps straight to the new window")

        // Frame-sequence evidence: 240 samples paced at 120Hz across three
        // overlapping windows + blank desktop. Every sample must be on the
        // correct window in the very same call (no interpolation, no lag).
        func sequencePoint(_ index: Int) -> CGPoint {
            let phase = index % 5
            switch phase {
            case 0: return CGPoint(x: 120, y: 120)   // A only
            case 1: return CGPoint(x: 300, y: 250)   // A on top of B (front-to-back)
            case 2: return CGPoint(x: 560, y: 300)   // B only
            case 3: return CGPoint(x: 700, y: 500)   // C only
            default: return CGPoint(x: 1300, y: 900) // blank desktop
            }
        }

        // Start from "no target" so the first sample is a real transition.
        primaryFixture.hover(cgPoint: CGPoint(x: 1300, y: 900))
        let changesBeforeSweep = snapView.hoverTargetChangeCount
        let writesBeforeSweep = snapView.snapGuideWriteCount
        var expectedTargetChanges = 0
        var expectedGuideWrites = 0
        var previousTarget: CGWindowID?
        var sweepMismatches = 0
        var csvRows = ["index,timestamp_s,interval_ms,cg_x,cg_y,expected_window,guide_x,guide_y,guide_w,guide_h,hidden"]
        let sweepStart = ProcessInfo.processInfo.systemUptime
        var previousSampleTime = sweepStart
        for index in 0..<240 {
            let targetTime = sweepStart + Double(index) / 120.0
            let now = ProcessInfo.processInfo.systemUptime
            if targetTime > now {
                Thread.sleep(forTimeInterval: targetTime - now)
            }
            let cgPoint = sequencePoint(index)
            let expected = primaryFixture.expectedTarget(cgPoint)
            if expected != previousTarget {
                expectedGuideWrites += 1
                if expected != nil { expectedTargetChanges += 1 }
                previousTarget = expected
            }
            primaryFixture.hover(cgPoint: cgPoint)
            let geometry = SnapGuideGeometry(view: snapView)
            let hidden = geometry.isHidden
            let expectedHidden = expected == nil
            var matched = hidden == expectedHidden
            if let expected, !hidden {
                matched = matched && geometry.frame == primaryFixture.localRect(cgFrame: primaryFixture.windowFrame(expected)!)
            }
            if !matched { sweepMismatches += 1 }
            let sampledAt = ProcessInfo.processInfo.systemUptime
            let interval = (sampledAt - previousSampleTime) * 1000
            previousSampleTime = sampledAt
            csvRows.append(String(
                format: "%d,%.6f,%.3f,%.1f,%.1f,%@,%.1f,%.1f,%.1f,%.1f,%@",
                index,
                sampledAt - sweepStart,
                interval,
                cgPoint.x,
                cgPoint.y,
                expected.map(String.init) ?? "blank",
                geometry.frame.origin.x,
                geometry.frame.origin.y,
                geometry.frame.width,
                geometry.frame.height,
                hidden ? "yes" : "no"
            ))
        }
        let sweepElapsed = ProcessInfo.processInfo.systemUptime - sweepStart
        check(sweepMismatches == 0,
              "120Hz sweep: every one of 240 samples is on the correct window in the same call (mismatches \(sweepMismatches))")
        let measuredRate = 240.0 / max(sweepElapsed, 0.000_001)
        check(measuredRate >= 100,
              "the sweep ran at \(Int(measuredRate)) samples/s (target 120Hz)")
        check(snapView.hoverTargetChangeCount - changesBeforeSweep == expectedTargetChanges,
              "the hover target changed exactly \(expectedTargetChanges) times during the sweep "
              + "(actual \(snapView.hoverTargetChangeCount - changesBeforeSweep))")
        check(snapView.snapGuideWriteCount - writesBeforeSweep == expectedGuideWrites,
              "the guide was written exactly once per visibility/target change "
              + "(\(expectedGuideWrites), actual \(snapView.snapGuideWriteCount - writesBeforeSweep))")

        // Burst sweep: 1000 samples with no pacing. Still zero stale frames,
        // and still exactly one write per target change.
        let changesBeforeBurst = snapView.hoverTargetChangeCount
        let writesBeforeBurst = snapView.snapGuideWriteCount
        var burstMismatches = 0
        var burstExpectedTargetChanges = 0
        var burstExpectedWrites = 0
        var burstPrevious: CGWindowID?
        for index in 0..<1000 {
            let cgPoint = sequencePoint(index)
            let expected = primaryFixture.expectedTarget(cgPoint)
            if expected != burstPrevious {
                burstExpectedWrites += 1
                if expected != nil { burstExpectedTargetChanges += 1 }
                burstPrevious = expected
            }
            primaryFixture.hover(cgPoint: cgPoint)
            let geometry = SnapGuideGeometry(view: snapView)
            var matched = geometry.isHidden == (expected == nil)
            if let expected, !geometry.isHidden {
                matched = matched && geometry.frame == primaryFixture.localRect(cgFrame: primaryFixture.windowFrame(expected)!)
            }
            if !matched { burstMismatches += 1 }
        }
        check(burstMismatches == 0, "burst sweep: 1000 samples, 0 stale frames")
        check(snapView.hoverTargetChangeCount - changesBeforeBurst == burstExpectedTargetChanges,
              "burst sweep: \(burstExpectedTargetChanges) target changes, nothing else")
        check(snapView.snapGuideWriteCount - writesBeforeBurst == burstExpectedWrites,
              "burst sweep: exactly one guide write per visibility/target change")

        // Per-display snapping: a point on another display never targets this
        // overlay, and each display resolves its own window in its own space.
        let rightFrame = NSRect(x: primaryFrame.maxX, y: primaryFrame.minY, width: 1200, height: 900)
        let rightWindowCG = CGRect(x: primaryFrame.maxX + 100, y: 300, width: 300, height: 200)
        let rightFixture = HoverFixture(
            displayFrame: rightFrame,
            windows: [(7101, rightWindowCG, false)]
        )
        let rightPoint = CGPoint(x: rightWindowCG.midX, y: rightWindowCG.midY)
        let primaryHoverBefore = SnapGuideGeometry(view: snapView)
        primaryFixture.hover(cgPoint: rightPoint)
        let primaryAfterCross = SnapGuideGeometry(view: snapView)
        check(primaryAfterCross.isHidden,
              "a pointer on another display does not target this screen's guide")
        check(primaryHoverBefore.frame != primaryAfterCross.frame || primaryAfterCross.isHidden,
              "the cross-display point had no stale local target")
        rightFixture.hover(cgPoint: rightPoint)
        check(rightFixture.window.frame == rightFrame,
              "off-screen fixture window keeps its requested frame (got \(rightFixture.window.frame))")
        check(!SnapGuideGeometry(view: rightFixture.view).isHidden,
              "the second display snaps to its own window")
        check(SnapGuideGeometry(view: rightFixture.view).frame == rightFixture.localRect(cgFrame: rightWindowCG),
              "the second display's guide uses its own origin (got \(SnapGuideGeometry(view: rightFixture.view).frame), "
              + "expected \(rightFixture.localRect(cgFrame: rightWindowCG)))")
        check(SnapGuideGeometry(view: snapView).isHidden,
              "updating the second display writes nothing on the first (no cross-screen bleed)")

        // A display above the primary exercises the CG → AppKit Y flip. The
        // flip must use the primary display's height (the shared origin), not
        // the secondary display's own height.
        let aboveHeight: CGFloat = 900
        let aboveFrame = NSRect(x: 0, y: primaryHeight, width: 1200, height: aboveHeight)
        let aboveWindowCG = CGRect(x: 100, y: -aboveHeight, width: 300, height: 200)
        let aboveFixture = HoverFixture(
            displayFrame: aboveFrame,
            windows: [(7102, aboveWindowCG, false)]
        )
        aboveFixture.hover(cgPoint: CGPoint(x: aboveWindowCG.midX, y: aboveWindowCG.midY))
        let aboveSnap = SnapGuideGeometry(view: aboveFixture.view)
        check(!aboveSnap.isHidden, "a display above the primary snaps too")
        let expectedAbove = aboveFixture.localRect(cgFrame: aboveWindowCG)
        check(aboveSnap.frame == expectedAbove,
              "the Y flip is correct on a display above the primary (got \(aboveSnap.frame), expected \(expectedAbove))")
        let localHeightFlip = aboveHeight - aboveWindowCG.minY - aboveWindowCG.height
        check(abs(aboveSnap.frame.minY - localHeightFlip) > 1,
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

        // Visibility contract: the guide follows the idle hover, and every
        // state that takes the overlay out of aiming hides it immediately.
        primaryFixture.hover(cgPoint: CGPoint(x: 200, y: 200))
        check(!SnapGuideGeometry(view: snapView).isHidden, "idle over a window shows the guide")
        snapView.selectionLocked = true
        check(SnapGuideGeometry(view: snapView).isHidden, "a committed/locked selection hides the guide")
        snapView.selectionLocked = false
        snapView.scrollCaptureActive = true
        check(SnapGuideGeometry(view: snapView).isHidden, "scroll capture hides the guide")
        snapView.scrollCaptureActive = false
        snapView.selectionInteractionEnabled = false
        check(SnapGuideGeometry(view: snapView).isHidden, "editor hand-off hides the guide")
        snapView.selectionInteractionEnabled = true
        primaryFixture.hover(cgPoint: CGPoint(x: 200, y: 200))
        check(!SnapGuideGeometry(view: snapView).isHidden, "resuming the overlay shows the guide again")
        snapView.updateSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 160))
        check(SnapGuideGeometry(view: snapView).isHidden, "an established selection shows no guide")

        reportSnapSweep(rows: csvRows, measuredRate: measuredRate,
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
