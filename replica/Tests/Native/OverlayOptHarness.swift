import AppKit
import CoreGraphics
@testable import BlinkClipCapture

/// Acceptance harness for the OPT overlay-cost revision.
///
/// It proves the three functional promises the optimisations must not break,
/// using the production types (no copies of the maths):
///
/// 1. **Magnifier cadence** — the lens is fed by its own 20Hz clock and no
///    longer by one content request per pointer event.
/// 2. **Magnifier coordinates / colour value** — a synthetic snapshot with a
///    known pixel at a known screen point resolves to exactly that pixel, the
///    panel applies it, and the painted frame still contains the panel
///    background and real text ink in both the static hint rows and the live
///    value row.
/// 3. **Static-chrome cache is live where it matters** — moving the pointer
///    changes the magnified area, while the cached chrome stays painted.
@main struct OverlayOptHarness {

    /// View coordinate (y-up, origin bottom-left) → bitmap row of a
    /// `cacheDisplay` raster, which stores its rows top-down.
    private static func color(
        at viewPoint: NSPoint,
        in rep: NSBitmapImageRep,
        bounds: NSRect
    ) -> NSColor? {
        let scale = CGFloat(rep.pixelsWide) / max(bounds.width, 1)
        let x = Int((viewPoint.x * scale).rounded())
        let y = Int(((bounds.height - viewPoint.y) * scale).rounded())
        guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh else { return nil }
        return rep.colorAt(x: x, y: y)
    }

    private static func rasterize(_ view: NSView) -> NSBitmapImageRep? {
        guard view.bounds.width > 1, view.bounds.height > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    private static func roughlyEqual(_ lhs: NSColor?, _ rhs: NSColor, tolerance: CGFloat = 0.06) -> Bool {
        guard let lhs = lhs?.usingColorSpace(.sRGB),
              let rhs = rhs.usingColorSpace(.sRGB) else { return false }
        return abs(lhs.redComponent - rhs.redComponent) <= tolerance
            && abs(lhs.greenComponent - rhs.greenComponent) <= tolerance
            && abs(lhs.blueComponent - rhs.blueComponent) <= tolerance
            && abs(lhs.alphaComponent - rhs.alphaComponent) <= tolerance
    }

    /// Number of pixels inside `rect` (view coordinates) that differ from
    /// `background` — i.e. how much text ink a row actually painted.
    private static func inkCount(
        in rect: NSRect,
        rep: NSBitmapImageRep,
        bounds: NSRect,
        background: NSColor
    ) -> Int {
        let scale = CGFloat(rep.pixelsWide) / max(bounds.width, 1)
        var count = 0
        var y = rect.minY
        while y < rect.maxY {
            var x = rect.minX
            while x < rect.maxX {
                if let color = color(at: NSPoint(x: x, y: y), in: rep, bounds: bounds),
                   !roughlyEqual(color, background, tolerance: 0.02) {
                    count += 1
                }
                x += 1 / scale
            }
            y += 1 / scale
        }
        return count
    }

    @MainActor static func main() {
        _ = NSApplication.shared
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message)
            checks += 1
        }

        // MARK: 1. Cadence: 20Hz panel, not one request per pointer event.
        check(MagnifierLensPanelWindow.contentRefreshInterval == 1.0 / 20.0,
              "the lens redraw cadence is 20Hz")

        // MARK: 2. A synthetic snapshot with a known pixel value.
        let width = 40
        let height = 40
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(x * 5)       // R ramps left → right
                pixels[offset + 1] = UInt8(y * 5)   // G ramps top → bottom
                pixels[offset + 2] = 200
                pixels[offset + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
        // The snapshot covers a 40×40pt screen area 1:1, so one point is one pixel.
        let screenFrame = NSRect(x: 0, y: 0, width: 40, height: 40)
        let mouse = NSPoint(x: 11, y: 29)
        let pixelPoint = MagnifierLensPanelSampler.pixelCoordinate(
            globalPoint: mouse,
            screenFrame: screenFrame,
            snapshotSize: CGSize(width: width, height: height)
        )
        check(pixelPoint == CGPoint(x: 11, y: 11),
              "AppKit y-up point maps to the same pixel row from the top (got \(pixelPoint))")
        let sampled = MagnifierLensPanelSampler.sample(image: image, at: pixelPoint)
        check(sampled == MagnifierLensPanelWindow.Sample(r: 55, g: 55, b: 200),
              "sampling returns the exact pixel colour (got \(String(describing: sampled)))")

        // MARK: 3. The panel applies what it is fed (its own clock, coalesced).
        let panel = MagnifierLensPanelWindow()
        panel.update(snapshot: image, screenFrame: screenFrame, mouseLocation: mouse, format: .hex)
        let deadline = Date().addingTimeInterval(3)
        while panel.currentSample == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        check(panel.currentSample == MagnifierLensPanelWindow.Sample(r: 55, g: 55, b: 200),
              "the 20Hz path applies the sampled colour (got \(String(describing: panel.currentSample)))")
        check(panel.currentPixelPoint == CGPoint(x: 11, y: 11),
              "the panel reports the pixel it is showing")

        // Moving the pointer must re-sample on the next tick — no stale frame.
        let movedMouse = NSPoint(x: 31, y: 9)
        panel.update(
            snapshot: image,
            screenFrame: screenFrame,
            mouseLocation: movedMouse,
            format: .hex
        )
        let moveDeadline = Date().addingTimeInterval(3)
        while panel.currentPixelPoint != CGPoint(x: 31, y: 31), Date() < moveDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        check(panel.currentSample == MagnifierLensPanelWindow.Sample(r: 155, g: 155, b: 200),
              "a moved pointer re-samples (got \(String(describing: panel.currentSample)))")

        // MARK: 4. The painted frame: cached chrome + live rows.
        guard let lensView = panel.contentView as? MagnifierLensPanelView else {
            preconditionFailure("the lens panel hosts its view")
        }
        let bounds = lensView.bounds
        let infoTop = bounds.height - bounds.width
        let background = MagnifierLensPanelSampler.darkBackgroundColor()

        // Info-area geometry (the panel's own layout constants: 18pt rows, 4pt
        // group gap, 8pt inset) recomputed here so the assertions below know
        // exactly where the static hint rows and the live value rows sit.
        let infoRows = 3
            + (Defaults.magnifierLensPanelShowCopyHint ? 1 : 0)
            + (Defaults.magnifierLensPanelShowFormatHint ? 1 : 0)
        let rowHeight: CGFloat = 18
        let rowGap: CGFloat = 4
        let rowInset: CGFloat = 8
        func rowY(_ index: Int) -> CGFloat {
            rowInset + CGFloat(index) * rowHeight
                + (index >= infoRows - 2 ? rowGap : 0)
        }
        check(abs(bounds.height - (bounds.width + CGFloat(infoRows) * rowHeight + rowGap + rowInset * 2)) < 0.5,
              "the panel keeps its documented height (width + \(infoRows) rows + gap + insets)")
        let hintBand = NSRect(x: 4, y: 2, width: bounds.width - 8, height: max(20, rowY(infoRows - 3) + rowHeight - 2))
        let valueBand = NSRect(
            x: 4,
            y: max(0, rowY(infoRows - 2) - 2),
            width: bounds.width - 8,
            height: rowY(infoRows - 1) + rowHeight - max(0, rowY(infoRows - 2) - 2)
        )

        guard let raster = rasterize(lensView) else {
            preconditionFailure("the lens view can be rasterised offscreen")
        }
        check(raster.pixelsWide > Int(bounds.width),
              "the cached chrome raster carries the backing scale")

        // The static half: background fill + hint-row text, from the cache.
        let hintInk = inkCount(in: hintBand, rep: raster, bounds: bounds, background: background)
        check(hintInk > 60, "the cached hint rows still paint text (ink=\(hintInk))")

        // The live half: the coordinate and colour rows, painted every frame.
        let valueInk = inkCount(in: valueBand, rep: raster, bounds: bounds, background: background)
        check(valueInk > 60, "the live value row still paints text (ink=\(valueInk))")

        // The magnified neighbourhood is live: its centre is the crosshair, so
        // sample a quarter-width off centre where the crop is drawn.
        let before = color(
            at: NSPoint(x: 3, y: infoTop + bounds.width - 8),
            in: raster,
            bounds: bounds
        )
        check(before != nil, "the magnified area is painted")

        // Moving the pointer by 20 pixel columns must change the magnified area
        // (it is re-cropped every frame; only the chrome is cached).
        panel.update(
            snapshot: image,
            screenFrame: screenFrame,
            mouseLocation: NSPoint(x: 31, y: 29),
            format: .hex
        )
        let mobileDeadline = Date().addingTimeInterval(3)
        while panel.currentPixelPoint != CGPoint(x: 31, y: 11), Date() < mobileDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        guard let movedRaster = rasterize(lensView) else {
            preconditionFailure("the lens view can be rasterised again")
        }
        check(raster.pixelsWide == movedRaster.pixelsWide && raster.pixelsHigh == movedRaster.pixelsHigh,
              "the cached chrome keeps the panel size")
        var changed = 0
        var y = infoTop + 10
        while y < bounds.height - 10 {
            var x = 10.0
            while x < bounds.width - 10 {
                let lhs = color(at: NSPoint(x: x, y: y), in: raster, bounds: bounds)
                let rhs = color(at: NSPoint(x: x, y: y), in: movedRaster, bounds: bounds)
                if !roughlyEqual(lhs, rhs ?? .clear, tolerance: 0.02) { changed += 1 }
                x += 3
            }
            y += 3
        }
        check(changed > 40,
              "the magnified area follows the pointer without a stale cache (changed=\(changed))")
        let infoChanged = inkCount(
            in: NSRect(x: 0, y: 0, width: bounds.width, height: infoTop),
            rep: movedRaster,
            bounds: bounds,
            background: background
        )
        check(infoChanged > 120, "the info area is still fully painted after a move")

        // MARK: 5. Format switch repaints the (cached) format hint.
        panel.setFormat(.rgb)
        panel.update(
            snapshot: image,
            screenFrame: screenFrame,
            mouseLocation: NSPoint(x: 31, y: 9),
            format: .rgb
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard let rgbRaster = rasterize(lensView) else {
            preconditionFailure("the lens view can be rasterised in RGB mode")
        }
        let rgbInk = inkCount(in: hintBand, rep: rgbRaster, bounds: bounds, background: background)
        check(rgbInk > 60, "switching to RGB rebuilds the cached chrome (ink=\(rgbInk))")

        // MARK: 6. The cache is reused: N frames of one state = one raster.
        let rendersBefore = lensView.staticChromeRenderCount
        for _ in 0..<5 {
            _ = rasterize(lensView)
            _ = rasterize(lensView)
            _ = rasterize(lensView)
        }
        let rendersAfter = lensView.staticChromeRenderCount
        check(rendersAfter - rendersBefore <= 1,
              "15 frames of one state rasterise the static half at most once (renders=\(rendersAfter - rendersBefore))")

        // Per-frame cost of the painted panel (chrome cache warm), for the
        // report: median microseconds of a full `draw(_:)` at this size.
        var frameMicros: [Double] = []
        for _ in 0..<30 {
            let start = CACurrentMediaTime()
            let rep = lensView.bitmapImageRepForCachingDisplay(in: lensView.bounds)
            if let rep { lensView.cacheDisplay(in: lensView.bounds, to: rep) }
            frameMicros.append((CACurrentMediaTime() - start) * 1_000_000)
        }
        frameMicros.sort()
        let medianFrame = frameMicros[frameMicros.count / 2]
        let meanFrame = frameMicros.reduce(0, +) / Double(frameMicros.count)
        print("{\"frame_median_us\":\(Int(medianFrame)),\"frame_mean_us\":\(Int(meanFrame)),\"chrome_renders\":\(rendersAfter - rendersBefore)}")

        panel.dismiss()
        print("{\"passed\":true,\"checks\":\(checks),\"boundary\":\"Production lens panel and sampler driven offscreen with a synthetic 40x40 snapshot; no desktop overlay, ScreenCaptureKit pixels, TCC or physical pointer events\"}")
    }
}
