import AppKit

/// Independently authored BlinkClip artwork. No extracted bitmap, symbol font, or third-party logo.
/// All coordinates are logical points in a flipped canvas. Integrators may cache returned NSImages.
@MainActor public enum BlinkClipAssetRenderer {
    public enum Category: String, CaseIterable { case file, link, text, unknown }
    private static let blue = NSColor(srgbRed: 0.055, green: 0.396, blue: 0.965, alpha: 1)
    private static let cyan = NSColor(srgbRed: 0.18, green: 0.78, blue: 0.98, alpha: 1)
    private static func ink(_ dark: Bool) -> NSColor { dark ? .init(white: 0.87, alpha: 1) : .init(white: 0.20, alpha: 1) }
    private static func surface(_ dark: Bool) -> NSColor { dark ? .init(white: 0.19, alpha: 1) : .white }
    private static func muted(_ dark: Bool) -> NSColor { dark ? .init(white: 0.38, alpha: 1) : .init(white: 0.78, alpha: 1) }
    private static func box(_ r: NSRect, _ radius: CGFloat, _ color: NSColor) {
        color.setFill(); NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
    }
    private static func line(_ points: [NSPoint], _ color: NSColor, _ width: CGFloat = 2) {
        guard let first = points.first else { return }
        let p = NSBezierPath(); p.move(to: first)
        for point in points.dropFirst() { p.line(to: point) }
        p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round
        color.setStroke(); p.stroke()
    }
    private static func window(_ r: NSRect, dark: Bool) {
        box(r, 6, muted(dark)); box(r.insetBy(dx: 1, dy: 1), 5, surface(dark))
        box(NSRect(x: r.minX + 1, y: r.minY + 1, width: r.width - 2, height: 12), 5, muted(dark).withAlphaComponent(0.25))
        for x in [CGFloat(7), 13, 19] {
            box(NSRect(x: r.minX + x, y: r.minY + 5, width: 3, height: 3), 1.5, muted(dark))
        }
    }
    /// A source note card. Plain geometry is original to this renderer, not a traced application logo.
    private static func note(_ r: NSRect, dark: Bool, accent: Bool = true) {
        box(r, 5, accent ? blue : surface(dark))
        let c: NSColor = accent ? .white : ink(dark)
        line([.init(x:r.minX+7,y:r.minY+10),.init(x:r.maxX-7,y:r.minY+10)], c, 2)
        line([.init(x:r.minX+7,y:r.minY+17),.init(x:r.maxX-11,y:r.minY+17)], c.withAlphaComponent(0.7), 2)
    }
    private static func arrow(from a: NSPoint, to b: NSPoint) {
        line([a,b], blue, 3)
        let dx = b.x-a.x, dy = b.y-a.y, d = max(1, hypot(dx,dy))
        let ux=dx/d, uy=dy/d
        line([.init(x:b.x-7*ux-4*uy,y:b.y-7*uy+4*ux),b,
              .init(x:b.x-7*ux+4*uy,y:b.y-7*uy-4*ux)],blue,3)
    }
    /// Logical 192×128, intended to be displayed at 96×64 or larger. Clear outer background.
    /// Direct paste shows content landing in a window; clipboard mode shows content stored on a board.
    public static func settings(directPaste: Bool, dark: Bool) -> NSImage {
        NSImage(size: .init(width: 192, height: 128), flipped: true) { _ in
            box(.init(x:8,y:12,width:176,height:104),14,blue.withAlphaComponent(dark ? 0.12 : 0.055))
            note(.init(x:19,y:47,width:36,height:42),dark:dark)
            if directPaste {
                window(.init(x:100,y:27,width:73,height:73),dark:dark)
                arrow(from:.init(x:64,y:68),to:.init(x:110,y:68))
                box(.init(x:119,y:54,width:43,height:6),2,cyan)
                box(.init(x:119,y:66,width:34,height:4),2,muted(dark))
                box(.init(x:119,y:76,width:39,height:4),2,muted(dark))
                line([.init(x:157,y:65),.init(x:157,y:83)],ink(dark),1.5)
            } else {
                box(.init(x:111,y:25,width:54,height:78),7,ink(dark))
                box(.init(x:114,y:29,width:48,height:70),5,surface(dark))
                box(.init(x:125,y:23,width:26,height:10),4,cyan)
                note(.init(x:121,y:47,width:34,height:39),dark:dark)
                arrow(from:.init(x:64,y:68),to:.init(x:105,y:68))
            }
            return true
        }
    }
    /// Draws the flipped logical canvas into a real bitmap at `scale` device pixels per point.
    private static func bitmapRepresentation(size: NSSize, scale: Int,
                                             body: () -> Void) -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(size.width) * scale,
                                            pixelsHigh: Int(size.height) * scale,
                                            bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // x → scale·x, y → scale·(height − y): keep the flipped logical points, scale to pixels.
        context.cgContext.concatenate(CGAffineTransform(a: CGFloat(scale), b: 0, c: 0, d: -CGFloat(scale),
                                                       tx: 0, ty: size.height * CGFloat(scale)))
        body()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
    /// Samples the 2× master once per logical pixel. A second antialiased pass at 1×
    /// spends different sub-pixel coverage on the same thin strokes, so the two
    /// scales would disagree; sampling keeps the 1× copy pixel-crisp and identical
    /// in geometry to retina drawing.
    private static func singleScaleSample(_ master: NSBitmapImageRep, size: NSSize) -> NSBitmapImageRep? {
        guard let sample = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: Int(size.width),
                                            pixelsHigh: Int(size.height),
                                            bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: sample) else { return nil }
        sample.size = size
        let masterImage = NSImage(size: size)
        masterImage.addRepresentation(master)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .none
        masterImage.draw(in: NSRect(origin: .zero, size: size))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return sample
    }
    /// Produces the 1×/2× bitmaps a template icon needs instead of the block-based
    /// `NSImage` initialiser, which only records an `NSCustomImageRep` on macOS 15
    /// — `representations` came back empty, so pixel consumers (packaging checks,
    /// template tinting, renderers) had nothing to read. The 2× bitmap is drawn at
    /// device scale from the same flipped logical geometry; the 1× bitmap samples
    /// it so both scales share one rendering. Callers set `isTemplate` and
    /// accessibility on the returned image.
    private static func bitmapImage(size: NSSize, body: () -> Void) -> NSImage {
        let image = NSImage(size: size)
        guard let master = bitmapRepresentation(size: size, scale: 2, body: body) else { return image }
        image.addRepresentation(master)
        if let single = singleScaleSample(master, size: size) { image.addRepresentation(single) }
        return image
    }
    /// Monochrome 20pt templates. Caller tint follows appearance; no separate dark bitmap is required.
    public static func category(_ kind: Category) -> NSImage {
        let image = bitmapImage(size: .init(width: 20, height: 20)) {
            let c = NSColor.black
            switch kind {
            case .file:
                line([.init(x:5,y:2.5),.init(x:11,y:2.5),.init(x:16,y:7.5),.init(x:16,y:17.5),.init(x:4,y:17.5),.init(x:4,y:3.5),.init(x:5,y:2.5)],c,1.5)
                line([.init(x:11,y:3),.init(x:11,y:7.5),.init(x:15.5,y:7.5)],c,1.5)
            case .link:
                let a=NSBezierPath(roundedRect:.init(x:2.5,y:7,width:9,height:6),xRadius:3,yRadius:3)
                let b=NSBezierPath(roundedRect:.init(x:8.5,y:7,width:9,height:6),xRadius:3,yRadius:3)
                a.lineWidth=1.5;b.lineWidth=1.5;c.setStroke();a.stroke();b.stroke()
                line([.init(x:7,y:10),.init(x:13,y:10)],c,1.5)
            case .text:
                line([.init(x:3.5,y:4.5),.init(x:16.5,y:4.5)],c,1.5)
                line([.init(x:3.5,y:8.5),.init(x:13.5,y:8.5)],c,1.5)
                line([.init(x:3.5,y:12.5),.init(x:16.5,y:12.5)],c,1.5)
                line([.init(x:3.5,y:16.5),.init(x:10.5,y:16.5)],c,1.5)
            case .unknown:
                let p=NSBezierPath(roundedRect:.init(x:3,y:3,width:14,height:14),xRadius:4,yRadius:4)
                p.lineWidth=1.5;c.setStroke();p.stroke()
                for x in [CGFloat(6),10,14] { box(.init(x:x-0.8,y:9.2,width:1.6,height:1.6),0.8,c) }
            }
        }
        image.isTemplate=true; image.accessibilityDescription=kind.rawValue
        return image
    }
    /// Logical 240×144: three generic windows and one transfer card; no application logos.
    public static func permission(dark: Bool) -> NSImage {
        NSImage(size:.init(width:240,height:144),flipped:true) { _ in
            box(.init(x:9,y:8,width:222,height:128),24,blue.withAlphaComponent(dark ? 0.12 : 0.055))
            window(.init(x:23,y:26,width:87,height:62),dark:dark)
            box(.init(x:34,y:49,width:22,height:25),4,cyan.withAlphaComponent(0.4))
            for y in [CGFloat(50),58,66] { box(.init(x:63,y:y,width:34,height:3),1.5,muted(dark)) }
            window(.init(x:132,y:24,width:83,height:59),dark:dark)
            for i in 0..<3 { box(.init(x:143+CGFloat(i)*20,y:48,width:14,height:21),3,blue.withAlphaComponent(0.18+CGFloat(i)*0.13)) }
            window(.init(x:85,y:86,width:91,height:44),dark:dark)
            box(.init(x:98,y:108,width:62,height:4),2,cyan)
            note(.init(x:103,y:50,width:35,height:40),dark:dark)
            arrow(from:.init(x:72,y:96),to:.init(x:88,y:81))
            arrow(from:.init(x:148,y:74),to:.init(x:165,y:88))
            return true
        }
    }
}
