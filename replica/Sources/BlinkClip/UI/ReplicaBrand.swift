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

    /// The menu bar mark is a **vector PDF** transcribed point-for-point from the 24 × 24 SVG the
    /// user drew and confirmed (`1.svg`: one compound path, `fill="black"`, nonzero winding).
    ///
    /// - card: rounded rect x 2…22, y 2…24, r ≈ 2, with its top-right corner bitten off by a
    ///   large four-pointed star whose tips reach y = 0 and x = 23;
    /// - the star itself is inked and sits in that bite with a ≈ 0.8pt negative-space gap, so the
    ///   corner reads as "card corner replaced by a star" rather than a blob;
    /// - two horizontal bars are knocked **out** of the solid card (y 13…15 short, y 18…20 long,
    ///   both starting at x = 5), i.e. negative space, not ink.
    ///
    /// The PDF page is 18 × 18pt and the 24-unit box is uniformly scaled to 16pt and centred, so
    /// the ink keeps the SVG's proportions and leaves 1pt of optical padding on every side (macOS
    /// status-bar art is ~16pt tall in an 18pt slot). Nothing about the shape is redrawn: the path
    /// commands are the SVG's own `m/l/c/h` with a y-flip, filled nonzero like SVG's default.
    ///
    /// `isTemplate = true`: AppKit tints it black on a light menu bar, white on a dark one, and
    /// inverts it while the item is highlighted. Resource: `Assets/BlinkClipMenuBarMark.pdf`,
    /// copied to `Contents/Resources` by `build-app.sh` (whose packaged-resource whitelist fails the
    /// build if it is missing, undeclared, or not an 18pt PDF).
    static func menuBarImage() -> NSImage {
        let image = menuBarMarkURL().flatMap { NSImage(contentsOf: $0) } ?? missingMenuBarMark()
        image.size = menuBarMarkSize
        image.isTemplate = true
        image.accessibilityDescription = name
        return image
    }

    /// Logical size every consumer measures (status item, two-line composite, tests).
    private static let menuBarMarkSize = NSSize(width: 18, height: 18)
    private static let menuBarMarkResource = (name: "BlinkClipMenuBarMark", extension: "pdf")

    private static func menuBarMarkURL() -> URL? {
        Bundle.main.url(forResource: menuBarMarkResource.name,
                        withExtension: menuBarMarkResource.extension)
    }

    /// Unreachable in a real build (`build-app.sh` refuses to package without the PDF, and
    /// `test-network-speed.sh` copies it into the harness bundle). Kept so a broken resource can
    /// never crash the status bar: log it, hand back an empty 18pt template so the item still
    /// lays out at 24/68pt instead of trapping.
    private static func missingMenuBarMark() -> NSImage {
        NSLog("BlinkClip: 缺少菜单栏图标资源 %@.%@",
              menuBarMarkResource.name, menuBarMarkResource.extension)
        return NSImage(size: menuBarMarkSize)
    }
}
