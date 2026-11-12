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

    /// A monochrome template rendition of the BlinkClip viewfinder + folded-card mark for both menu bar appearances.
    static func menuBarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            // 1. Four rounded viewfinder brackets (Scan)
            let brackets = NSBezierPath()
            brackets.lineWidth = 1.6
            brackets.lineCapStyle = .round
            brackets.lineJoinStyle = .round

            // Top-Left
            brackets.move(to: NSPoint(x: 2.25, y: 6.0))
            brackets.appendArc(from: NSPoint(x: 2.25, y: 2.25), to: NSPoint(x: 6.0, y: 2.25), radius: 2.0)
            brackets.line(to: NSPoint(x: 6.0, y: 2.25))

            // Top-Right
            brackets.move(to: NSPoint(x: 12.0, y: 2.25))
            brackets.appendArc(from: NSPoint(x: 15.75, y: 2.25), to: NSPoint(x: 15.75, y: 6.0), radius: 2.0)
            brackets.line(to: NSPoint(x: 15.75, y: 6.0))

            // Bottom-Right
            brackets.move(to: NSPoint(x: 15.75, y: 12.0))
            brackets.appendArc(from: NSPoint(x: 15.75, y: 15.75), to: NSPoint(x: 12.0, y: 15.75), radius: 2.0)
            brackets.line(to: NSPoint(x: 12.0, y: 15.75))

            // Bottom-Left
            brackets.move(to: NSPoint(x: 6.0, y: 15.75))
            brackets.appendArc(from: NSPoint(x: 2.25, y: 15.75), to: NSPoint(x: 2.25, y: 12.0), radius: 2.0)
            brackets.line(to: NSPoint(x: 2.25, y: 12.0))
            brackets.stroke()

            // 2. Center folded-corner note card with negative-space top capsule slot (Clip)
            let card = NSBezierPath()
            card.windingRule = .evenOdd
            card.move(to: NSPoint(x: 6.4, y: 4.8))
            card.line(to: NSPoint(x: 9.9, y: 4.8))
            card.line(to: NSPoint(x: 9.9, y: 7.0))
            card.appendArc(from: NSPoint(x: 9.9, y: 8.1), to: NSPoint(x: 11.0, y: 8.1), radius: 0.9)
            card.line(to: NSPoint(x: 13.2, y: 8.1))
            card.line(to: NSPoint(x: 13.2, y: 11.6))
            card.appendArc(from: NSPoint(x: 13.2, y: 13.2), to: NSPoint(x: 11.6, y: 13.2), radius: 1.6)
            card.line(to: NSPoint(x: 6.4, y: 13.2))
            card.appendArc(from: NSPoint(x: 4.8, y: 13.2), to: NSPoint(x: 4.8, y: 11.6), radius: 1.6)
            card.line(to: NSPoint(x: 4.8, y: 6.4))
            card.appendArc(from: NSPoint(x: 4.8, y: 4.8), to: NSPoint(x: 6.4, y: 4.8), radius: 1.6)
            card.close()

            // Negative-space top capsule cutout
            let pill = NSBezierPath(roundedRect: NSRect(x: 5.9, y: 6.15, width: 3.1, height: 1.15), xRadius: 0.575, yRadius: 0.575)
            card.append(pill)
            card.fill()

            // 3. Top-right folded corner flap
            let flap = NSBezierPath()
            flap.move(to: NSPoint(x: 10.85, y: 4.95))
            flap.line(to: NSPoint(x: 13.05, y: 7.15))
            flap.line(to: NSPoint(x: 11.2, y: 7.15))
            flap.appendArc(from: NSPoint(x: 10.85, y: 7.15), to: NSPoint(x: 10.85, y: 6.8), radius: 0.35)
            flap.close()
            flap.fill()

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }
}
