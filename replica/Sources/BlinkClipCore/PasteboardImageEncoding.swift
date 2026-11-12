import AppKit
import Foundation

public enum PasteboardImageEncoding {
    public static func pngData(_ image: NSImage) -> Data? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        let scale = bitmap.size.width / image.size.width
        bitmap.size = NSSize(width: bitmap.size.width / scale, height: bitmap.size.height / scale)
        return bitmap.representation(using: .png, properties: [:])
    }
}
