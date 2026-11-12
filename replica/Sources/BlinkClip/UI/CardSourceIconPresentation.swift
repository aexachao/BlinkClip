import AppKit
import BlinkClipCore

/// Source icons keep the launch artwork's own shape and alpha, inside the header.
@MainActor
enum CardSourceIconPresentation {
    static func side(headerHeight: CGFloat, compact: Bool) -> CGFloat {
        max(1, min(compact ? 20 : 44, headerHeight - 12))
    }

    static func fittedSize(_ imageSize: NSSize, inside bounds: NSSize) -> NSSize? {
        guard imageSize.width > 0, imageSize.height > 0,
              bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        return NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    static func image(data: Data?, boundingSize: NSSize?) -> NSImage? {
        guard let data, let image = NSImage(data: data), image.isValid,
              image.size.width > 0, image.size.height > 0 else { return nil }
        guard let boundingSize else { return image }
        guard let size = fittedSize(image.size, inside: boundingSize) else { return nil }
        return ImagePreviewMetadataGenerator.resizedImage(image, width: size.width, height: size.height)
    }
}
