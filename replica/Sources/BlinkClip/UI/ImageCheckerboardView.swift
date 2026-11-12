import AppKit
import BlinkClipCore
import QuartzCore

@MainActor
final class ImageCheckerboardView: LayerBackedView {
    override func layout() { updateLayout() }

    private func updateLayout() {
        super.layout()
        let tile = Self.makeCheckerboardTile(width: 8, height: 8,
                                  color: ToolbarAppearance.borderAndHover())
        backgroundColor = NSColor(patternImage: tile)
        layer?.contentsGravity = .resizeAspectFill
    }

    private static func makeCheckerboardTile(width: CGFloat, height: CGFloat, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: width + width, height: height + height))
        image.lockFocus()
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        NSBezierPath(rect: NSRect(x: width, y: height, width: width, height: height)).fill()
        image.unlockFocus()
        return image
    }
}
