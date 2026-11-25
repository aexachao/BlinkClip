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

    /// A monochrome template rendition of the BlinkClip viewfinder + peeled-corner card mark for both
    /// menu bar appearances.
    ///
    /// The construction follows `Assets/BlinkClipIcon.png` measured on its 1024pt canvas: the viewfinder
    /// box is the full mark, the card is 60% of that box, the bar slot sits a quarter down the card, the
    /// page corner peels at the bottom right, and the four-point sparkle straddles the card's top-right
    /// corner. At 18pt the mark needs optical corrections over the pure scale: thicker strokes, a wider
    /// slot, a slightly larger sparkle, and a negative-space ring around the sparkle so it stays
    /// readable in one colour. Measurements and trade-offs: `evidence/patches/menubar-icon-report.md`
    /// (kept outside this repository, next to the project checkout).
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
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

            // 2. Card: 8.0 x 7.9pt rounded note, 1.4pt corners, bottom-right corner cut for the peel.
            let cardLeft: CGFloat = 4.75
            let cardRight: CGFloat = 12.75
            let cardTop: CGFloat = 5.3
            let cardBottom: CGFloat = 13.2
            let cardRadius: CGFloat = 1.4
            let cardHandle: CGFloat = cardRadius * 0.5523
            let foldLeg: CGFloat = 3.2
            let foldGap: CGFloat = 0.5
            let foldCorner: CGFloat = 0.65
            let slotLeft: CGFloat = 1.4
            let slotTop: CGFloat = 2.12
            let slotWidth: CGFloat = 5.2
            let slotHeight: CGFloat = 0.8

            let starCentre = NSPoint(x: cardRight - 0.48, y: cardTop + 0.12)
            let starTip: CGFloat = 1.5                 // 3.0pt across the diagonal
            let starInner: CGFloat = 1.5 * 0.51        // concave waist, measured from the app icon
            let starRing: CGFloat = 0.6                // negative-space ring, exists only over the card

            func sparkle(tip: CGFloat, inner: CGFloat) -> NSBezierPath {
                let waist = inner / 2.0.squareRoot()
                let path = NSBezierPath()
                path.move(to: NSPoint(x: starCentre.x, y: starCentre.y - tip))
                path.line(to: NSPoint(x: starCentre.x + waist, y: starCentre.y - waist))
                path.line(to: NSPoint(x: starCentre.x + tip, y: starCentre.y))
                path.line(to: NSPoint(x: starCentre.x + waist, y: starCentre.y + waist))
                path.line(to: NSPoint(x: starCentre.x, y: starCentre.y + tip))
                path.line(to: NSPoint(x: starCentre.x - waist, y: starCentre.y + waist))
                path.line(to: NSPoint(x: starCentre.x - tip, y: starCentre.y))
                path.line(to: NSPoint(x: starCentre.x - waist, y: starCentre.y - waist))
                path.close()
                return path
            }

            let outline = NSBezierPath()
            outline.move(to: NSPoint(x: cardLeft + cardRadius, y: cardTop))
            outline.line(to: NSPoint(x: cardRight - cardRadius, y: cardTop))
            outline.curve(to: NSPoint(x: cardRight, y: cardTop + cardRadius),
                          controlPoint1: NSPoint(x: cardRight - cardRadius + cardHandle, y: cardTop),
                          controlPoint2: NSPoint(x: cardRight, y: cardTop + cardRadius - cardHandle))
            outline.line(to: NSPoint(x: cardRight, y: cardBottom - foldLeg))
            outline.line(to: NSPoint(x: cardRight - foldLeg, y: cardBottom))
            outline.line(to: NSPoint(x: cardLeft + cardRadius, y: cardBottom))
            outline.curve(to: NSPoint(x: cardLeft, y: cardBottom - cardRadius),
                          controlPoint1: NSPoint(x: cardLeft + cardRadius - cardHandle, y: cardBottom),
                          controlPoint2: NSPoint(x: cardLeft, y: cardBottom - cardRadius + cardHandle))
            outline.line(to: NSPoint(x: cardLeft, y: cardTop + cardRadius))
            outline.curve(to: NSPoint(x: cardLeft + cardRadius, y: cardTop),
                          controlPoint1: NSPoint(x: cardLeft, y: cardTop + cardRadius - cardHandle),
                          controlPoint2: NSPoint(x: cardLeft + cardRadius - cardHandle, y: cardTop))
            outline.close()

            // Bar slot: negative-space capsule, as on the icon where the orange bar sits a quarter down.
            let body = NSBezierPath()
            body.windingRule = .evenOdd
            body.append(outline)
            body.append(NSBezierPath(roundedRect: NSRect(x: cardLeft + slotLeft, y: cardTop + slotTop,
                                                         width: slotWidth, height: slotHeight),
                                     xRadius: slotHeight / 2, yRadius: slotHeight / 2))
            body.fill()

            // 3. Sparkle ring: clear the card under an inflated sparkle, clipped to the card so the ring
            //    never eats into the gap between the card and the viewfinder.
            if let context = NSGraphicsContext.current?.cgContext {
                NSGraphicsContext.saveGraphicsState()
                outline.addClip()
                context.setBlendMode(.clear)
                sparkle(tip: starTip + starRing, inner: starInner + starRing).fill()
                context.setBlendMode(.normal)
                NSGraphicsContext.restoreGraphicsState()
            }

            // 4. Peeled page corner: the flap sits inside the cut, offset by the gap.
            let diagonal = foldLeg / 2.0.squareRoot()
            let shorten = (diagonal - foldGap) / diagonal
            let flapEdge = foldLeg * shorten
            let flapHandle = foldCorner * 0.5523
            let flap = NSBezierPath()
            flap.move(to: NSPoint(x: cardRight - flapEdge, y: cardBottom))
            flap.line(to: NSPoint(x: cardRight - foldCorner, y: cardBottom))
            flap.curve(to: NSPoint(x: cardRight, y: cardBottom - foldCorner),
                       controlPoint1: NSPoint(x: cardRight - foldCorner + flapHandle, y: cardBottom),
                       controlPoint2: NSPoint(x: cardRight, y: cardBottom - foldCorner + flapHandle))
            flap.line(to: NSPoint(x: cardRight, y: cardBottom - flapEdge))
            flap.close()
            flap.fill()

            // 5. Four-point sparkle, straddling the card's top-right corner like the app icon.
            sparkle(tip: starTip, inner: starInner).fill()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }
}
