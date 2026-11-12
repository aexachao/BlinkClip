import AppKit
import Foundation

/// The recovered image metadata value; its storage does not claim original rawPreview byte compatibility.
public struct ImagePreviewMetadata: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let previewData: Data

    public var size: NSSize { NSSize(width: width, height: height) }
}

public enum ImagePreviewMetadataGenerator {
    public static func previewMetadata(_ items: [PasteboardItem]) -> ImagePreviewMetadata? {
        let images = items.compactMap { $0.imageData().flatMap(NSImage.init(data:)) }
        guard let image = images.first,
              let thumbnail = aspectFittedImage(image, width: 280, height: 230) else { return nil }
        let preview: Data?
        if let cgImage = thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil),
           hasTransparency(cgImage) {
            preview = PasteboardImageEncoding.pngData(thumbnail)
        } else {
            preview = jpegData(thumbnail, compression: 0.6)
        }
        guard let preview else { return nil }
        return ImagePreviewMetadata(width: image.size.width, height: image.size.height,
                                            previewData: preview)
    }

    private static func aspectFittedImage(_ image: NSImage, width: CGFloat, height: CGFloat) -> NSImage? {
        guard let representation = image.bestRepresentation(for: NSRect(x: 0, y: 0, width: width, height: height),
                                                              context: nil, hints: nil) else { return nil }
        var targetWidth = width
        var targetHeight = height
        if !(representation.size.width <= width) || !(representation.size.height <= height) {
            let widthScale = width / representation.size.width
            let heightScale = height / representation.size.height
            if widthScale < heightScale {
                targetHeight = (widthScale * representation.size.height).rounded(.toNearestOrAwayFromZero)
            } else {
                targetWidth = (heightScale * representation.size.width).rounded(.toNearestOrAwayFromZero)
            }
        } else {
            targetWidth = representation.size.width
            targetHeight = representation.size.height
        }
        return resizedImage(image, width: targetWidth, height: targetHeight)
    }

    public static func resizedImage(_ image: NSImage, width: CGFloat, height: CGFloat) -> NSImage? {
        guard image.isValid, width > 0, height > 0,
              let representation = image.bestRepresentation(for: NSRect(x: 0, y: 0, width: width, height: height),
                                                              context: nil, hints: nil) else { return nil }
        let result = NSImage(size: NSSize(width: width, height: height))
        result.lockFocus()
        representation.draw(in: NSRect(x: 0, y: 0, width: width, height: height), from: .zero,
                            operation: .copy, fraction: 1, respectFlipped: true, hints: nil)
        result.unlockFocus()
        return result
    }

    private static func hasTransparency(_ image: CGImage) -> Bool {
        let alpha = image.alphaInfo.rawValue
        if alpha == 0 || alpha == 5 || alpha == 6 { return false }
        var pixels = [UInt8](repeating: 0, count: 4096)
        let drew = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: 32, height: 32,
                                          bitsPerComponent: 8, bytesPerRow: 128,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: 1) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return true
        }
        guard drew else { return false }
        let transparentPixels = stride(from: 3, to: pixels.count, by: 4).reduce(0) {
            $0 + (pixels[$1] < 250 ? 1 : 0)
        }
        return Double(transparentPixels) * (1.0 / 1024.0) >= 0.05
    }

    public static func jpegData(_ image: NSImage, compression: CGFloat) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg,
                                                               properties: [.compressionFactor: compression])
    }
}
