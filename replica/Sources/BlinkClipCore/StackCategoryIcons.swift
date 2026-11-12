import AppKit
import Foundation

public enum StackCategoryIcons {
    // these are category images, independent of the source application.
    public static func name(for kind: PasteboardContentKind) -> String {
        switch kind {
        case .files: return "icon.file"
        case .color, .text: return "icon.text"
        case .link: return "icon.link"
        case .unknown, .image: return "icon.unknown"
        }
    }

    @MainActor private static let images: [String: NSImage] = [
        "icon.file": BlinkClipAssetRenderer.category(.file),
        "icon.link": BlinkClipAssetRenderer.category(.link),
        "icon.text": BlinkClipAssetRenderer.category(.text),
        "icon.unknown": BlinkClipAssetRenderer.category(.unknown)
    ]

    @MainActor public static func image(for kind: PasteboardContentKind) -> NSImage {
        images[name(for: kind)]!
    }
}
