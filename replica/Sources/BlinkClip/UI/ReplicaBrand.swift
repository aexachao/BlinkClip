import Foundation
import AppKit
import BlinkClipCore

enum ReplicaBrand {
    static var name: String { AppBrand.name }

    /// Only apply to recovered UI copy that explicitly names the original app.
    /// User content, app names from other processes, and paste commands are not brand copy.
    static func replacingName(in text: String) -> String {
        text
            .replacingOccurrences(of: "Paste Replica", with: name)
            .replacingOccurrences(of: "Paste", with: name)
    }

    // MARK: - Menu bar mark

    /// The card block of the 18pt mark, in the `NSImage(flipped: true)` space (y grows downwards).
    ///
    /// The mark is the BlinkClip app icon in one colour: four viewfinder brackets around a card
    /// whose bottom-right corner is cut open, with a solid bar a quarter down the card. Card
    /// centre (8.75, 9.25) keeps the app icon's 0.25pt down-left offset from the viewfinder centre,
    /// so the mark sits where the previous one sat in the status bar. Measurements and trade-offs:
    /// `evidence/patches/menubar-icon-final-report.md`.
    private enum MenuBarMarkMetrics {
        /// 8.0 x 7.9pt card at (4.75, 5.3).
        static let card = NSRect(x: 4.75, y: 5.3, width: 8.0, height: 7.9)
        /// 1.4pt outer corner radius.
        static let cardRadius: CGFloat = 1.4
        /// The card is hollow: a 1.2pt stroke, the thinnest line in the mark after the solid bar.
        static let cardStrokeWidth: CGFloat = 1.2
        /// Bottom-right corner sliced off along this leg; the cut is the only trace of the peeled page.
        static let foldLeg: CGFloat = 3.2
        /// Solid 5.2 x 0.9pt capsule at (6.15, 7.42), a quarter down the card and centred on it.
        static let bar = NSRect(x: 6.15, y: 7.42, width: 5.2, height: 0.9)
    }

    /// A monochrome template rendition of the BlinkClip viewfinder + cut-corner card mark for both
    /// menu bar appearances.
    ///
    /// The construction follows `Assets/BlinkClipIcon.png` measured on its 1024pt canvas: the
    /// viewfinder box is the full mark, the card is the note in the middle, the bar sits a quarter
    /// down the card, and the page corner peels at the bottom right. At 18pt the mark needs optical
    /// corrections over the pure scale — a 1.2pt card stroke, a solid bar instead of the icon's
    /// negative-space slot, and no sparkle: the four-point star survives the scale only as partial
    /// pixels and needs a negative-space ring that eats the card's top edge.
    ///
    /// `isTemplate = true`: AppKit tints it black on a light menu bar, white on a dark one, and
    /// inverts it while the item is highlighted.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            drawMenuBarMark()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }

    private static func drawMenuBarMark() {
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let halfStroke: CGFloat = 0.7        // 1.4pt stroke

        // 1. Viewfinder: four brackets. 14.4pt outer box (1.8 … 16.2), 1.7pt outer corner radius,
        //    3.6pt arms with round caps.
        let loop: CGFloat = 1.8 + halfStroke           // 2.5 centre line of the outer box
        let farLoop: CGFloat = 16.2 - halfStroke       // 15.5
        let cornerRadius: CGFloat = 1.0                // centre line (1.7 outer radius)
        let nearArm: CGFloat = 1.8 + 3.6 - halfStroke  // 4.7 centre line, cap tip at 5.4
        let farArm: CGFloat = 16.2 - 3.6 + halfStroke  // 13.3 centre line, cap tip at 12.6
        let cornerHandle: CGFloat = cornerRadius * 0.5523

        let brackets = NSBezierPath()
        brackets.lineWidth = halfStroke * 2
        brackets.lineCapStyle = .round
        brackets.lineJoinStyle = .round

        brackets.move(to: NSPoint(x: loop, y: nearArm))
        brackets.line(to: NSPoint(x: loop, y: loop + cornerRadius))
        brackets.curve(to: NSPoint(x: loop + cornerRadius, y: loop),
                       controlPoint1: NSPoint(x: loop, y: loop + cornerRadius - cornerHandle),
                       controlPoint2: NSPoint(x: loop + cornerRadius - cornerHandle, y: loop))
        brackets.line(to: NSPoint(x: nearArm, y: loop))

        brackets.move(to: NSPoint(x: farArm, y: loop))
        brackets.line(to: NSPoint(x: farLoop - cornerRadius, y: loop))
        brackets.curve(to: NSPoint(x: farLoop, y: loop + cornerRadius),
                       controlPoint1: NSPoint(x: farLoop - cornerRadius + cornerHandle, y: loop),
                       controlPoint2: NSPoint(x: farLoop, y: loop + cornerRadius - cornerHandle))
        brackets.line(to: NSPoint(x: farLoop, y: nearArm))

        brackets.move(to: NSPoint(x: farLoop, y: farArm))
        brackets.line(to: NSPoint(x: farLoop, y: farLoop - cornerRadius))
        brackets.curve(to: NSPoint(x: farLoop - cornerRadius, y: farLoop),
                       controlPoint1: NSPoint(x: farLoop, y: farLoop - cornerRadius + cornerHandle),
                       controlPoint2: NSPoint(x: farLoop - cornerRadius + cornerHandle, y: farLoop))
        brackets.line(to: NSPoint(x: farArm, y: farLoop))

        brackets.move(to: NSPoint(x: nearArm, y: farLoop))
        brackets.line(to: NSPoint(x: loop + cornerRadius, y: farLoop))
        brackets.curve(to: NSPoint(x: loop, y: farLoop - cornerRadius),
                       controlPoint1: NSPoint(x: loop + cornerRadius - cornerHandle, y: farLoop),
                       controlPoint2: NSPoint(x: loop, y: farLoop - cornerRadius + cornerHandle))
        brackets.line(to: NSPoint(x: loop, y: farArm))
        brackets.stroke()

        // 2. Card: hollow note, bottom-right corner sliced off. The cut edge is the only trace of the
        //    peeled page — at 18pt a filled flap would close up against the card into a blob.
        let card = cardOutline()
        card.lineWidth = MenuBarMarkMetrics.cardStrokeWidth
        card.lineJoinStyle = .round
        card.stroke()

        // 3. Bar: solid capsule, where the app icon's orange bar sits a quarter down the card. Solid
        //    rather than the icon's negative-space slot, because a 0.9pt slot inside a stroked card
        //    has no card body to be knocked out of.
        barPath().fill()
    }

    /// The card silhouette: rounded note with the bottom-right corner sliced off along the fold leg.
    private static func cardOutline() -> NSBezierPath {
        let card = MenuBarMarkMetrics.card
        let radius = MenuBarMarkMetrics.cardRadius
        let handle = radius * 0.5523
        let fold = MenuBarMarkMetrics.foldLeg
        let left = card.minX, right = card.maxX
        let top = card.minY, bottom = card.maxY
        let outline = NSBezierPath()
        outline.move(to: NSPoint(x: left + radius, y: top))
        outline.line(to: NSPoint(x: right - radius, y: top))
        outline.curve(to: NSPoint(x: right, y: top + radius),
                      controlPoint1: NSPoint(x: right - radius + handle, y: top),
                      controlPoint2: NSPoint(x: right, y: top + radius - handle))
        outline.line(to: NSPoint(x: right, y: bottom - fold))
        outline.line(to: NSPoint(x: right - fold, y: bottom))
        outline.line(to: NSPoint(x: left + radius, y: bottom))
        outline.curve(to: NSPoint(x: left, y: bottom - radius),
                      controlPoint1: NSPoint(x: left + radius - handle, y: bottom),
                      controlPoint2: NSPoint(x: left, y: bottom - radius + handle))
        outline.line(to: NSPoint(x: left, y: top + radius))
        outline.curve(to: NSPoint(x: left + radius, y: top),
                      controlPoint1: NSPoint(x: left, y: top + radius - handle),
                      controlPoint2: NSPoint(x: left + radius - handle, y: top))
        outline.close()
        return outline
    }

    private static func barPath() -> NSBezierPath {
        let bar = MenuBarMarkMetrics.bar
        return NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2)
    }
}
