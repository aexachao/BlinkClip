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

/// Reads the crosshair geometry out of the live view/layer tree — the same
/// numbers the window server receives, without a second copy of the layout
/// maths. The overlay installs exactly two crosshair subviews: the horizontal
/// guide and the vertical guide. The pointer is the system crosshair and is not
/// part of this view at all.
private struct CrosshairLayerGeometry {
    let horizontalBand: NSView?
    let verticalBand: NSView?
    let subviewCount: Int

    init(view: SelectionView) {
        let subviews = view.subviews
        subviewCount = subviews.count
        horizontalBand = subviews.count == 2 ? subviews[0] : nil
        verticalBand = subviews.count == 2 ? subviews[1] : nil
    }

    /// Where the two guide bands cross, in view coordinates.
    var crossing: NSPoint? {
        guard let horizontalBand, let verticalBand else { return nil }
        return NSPoint(x: verticalBand.frame.midX, y: horizontalBand.frame.midY)
    }

    /// The two solid line layers, one per axis.
    var guideLayers: [CAShapeLayer] {
        [horizontalBand, verticalBand].compactMap { $0?.layer?.sublayers?.first as? CAShapeLayer }
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
        // --- CUR4: system crosshair + layers-only guides ---------------------
        // The overlay never hides or paints the pointer: the pointer is the
        // system `NSCursor.crosshair` (hardware-composited, so it cannot trail).
        // The two guides live in their own layers, are moved inside one
        // disabled-actions transaction and are displayed synchronously. Their
        // style is deliberately quiet: a solid 1.5pt systemGray line at 50%.
        let pointerWindow = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 800, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        pointerWindow.backgroundColor = .white
        let pointerView = CountingSelectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        pointerWindow.contentView = pointerView

        let initialGeometry = CrosshairLayerGeometry(view: pointerView)
        check(initialGeometry.subviewCount == 2,
              "the overlay installs exactly two guide layers and no self-drawn pointer")

        var deviation: CGFloat = 0
        var geometrySamples = 0
        for offset in [(0.0, 0.0), (0.3, 0.7), (0.5, 0.5), (0.13, 0.87), (0.49, 0.51)] {
            let local = NSPoint(x: 400 + offset.0, y: 300 + offset.1)
            pointerView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: local))
            guard let crossing = CrosshairLayerGeometry(view: pointerView).crossing else { continue }
            geometrySamples += 1
            deviation = max(deviation, abs(crossing.x - local.x), abs(crossing.y - local.y))
        }
        check(geometrySamples == 5, "every sample showed both guide bands")
        check(deviation <= 1.0,
              "the guide crossing is within one device pixel of the pointer (max \(deviation)pt)")

        // Style: solid, 1.5pt, systemGray at 50% — the low-contrast style that
        // keeps a one-frame offset nearly invisible.
        let guideLayers = CrosshairLayerGeometry(view: pointerView).guideLayers
        check(guideLayers.count == 2, "each guide is a shape layer")
        check(guideLayers.allSatisfy { abs($0.lineWidth - 1.5) < 0.001 },
              "guides are 1.5pt")
        check(guideLayers.allSatisfy { layer in
                  let pattern = layer.lineDashPattern?.map(\.doubleValue) ?? []
                  return pattern.isEmpty
              },
              "guides are solid (no dash pattern)")
        let expectedGray = NSColor.systemGray.withAlphaComponent(0.5)
        check(guideLayers.allSatisfy { layer in
            guard let components = rgbaComponents(layer.strokeColor),
                  let expected = rgbaComponents(expectedGray.cgColor),
                  components.count == 4, expected.count == 4 else { return false }
            return zip(components, expected).allSatisfy { abs($0 - $1) < 0.02 }
        }, "guides are systemGray at 50%")

        // Moving a guide must not repaint the frozen snapshot: 200 pointer
        // moves change layers only, never `draw(_:)` of the full-screen view.
        let drawCountBeforeSweep = pointerView.drawCount
        for step in 0..<200 {
            let local = NSPoint(x: 200 + CGFloat(step), y: 150 + CGFloat(step % 40))
            pointerView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: local))
        }
        check(pointerView.drawCount == drawCountBeforeSweep,
              "200 guide moves add no overlay draw(_:) pass")

        // State contract: guides show while aiming/drawing, and disappear as
        // soon as the selection is committed, scroll capture starts, the editor
        // takes over, or interaction is disabled.
        let centre = NSPoint(x: 400, y: 300)
        pointerView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: centre))
        var geometry = CrosshairLayerGeometry(view: pointerView)
        check(geometry.horizontalBand?.isHidden == false && geometry.verticalBand?.isHidden == false,
              "idle shows both guides")
        pointerView.selectionLocked = true
        geometry = CrosshairLayerGeometry(view: pointerView)
        check(geometry.horizontalBand?.isHidden == true && geometry.verticalBand?.isHidden == true,
              "a committed selection hides the guides")
        pointerView.selectionLocked = false
        pointerView.scrollCaptureActive = true
        geometry = CrosshairLayerGeometry(view: pointerView)
        check(geometry.horizontalBand?.isHidden == true && geometry.verticalBand?.isHidden == true,
              "scroll capture hides the guides")
        pointerView.scrollCaptureActive = false
        pointerView.selectionInteractionEnabled = false
        geometry = CrosshairLayerGeometry(view: pointerView)
        check(geometry.horizontalBand?.isHidden == true && geometry.verticalBand?.isHidden == true,
              "editor hand-off hides the guides")
        pointerView.selectionInteractionEnabled = true
        check(CrosshairLayerGeometry(view: pointerView).horizontalBand?.isHidden == false,
              "resuming the overlay shows the guides again")
        pointerView.updateSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 160))
        geometry = CrosshairLayerGeometry(view: pointerView)
        check(geometry.horizontalBand?.isHidden == true && geometry.verticalBand?.isHidden == true,
              "an established selection shows no guides")

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

        // A pointer on one display continues the horizontal line onto its
        // neighbours, while the vertical line only lands on the pointer's own
        // display: the other overlays stay empty at the crossing point.
        let sideWindow = NSWindow(
            contentRect: NSRect(x: -3200, y: -4000, width: 300, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let sideView = SelectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        sideWindow.contentView = sideView
        sideView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: centre))
        let sideGeometry = CrosshairLayerGeometry(view: sideView)
        check(sideGeometry.verticalBand?.isHidden == true,
              "a display the pointer is not on draws no vertical guide")
        check(sideGeometry.horizontalBand?.isHidden == false,
              "…while the horizontal guide still continues across it")

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
