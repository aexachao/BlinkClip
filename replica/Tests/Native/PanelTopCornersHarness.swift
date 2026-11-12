import AppKit
import ImageIO
import BlinkClipObjC
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct PanelTopCornersHarness {
    struct Failure: Error { let message: String }
    struct Bitmap {
        let width: Int
        let height: Int
        let bytes: [UInt8]
        func alpha(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * width + x) * 4 + 3]) }
    }

    @MainActor static func main() {
        do { try run() }
        catch {
            print("FAIL: \(error)")
            exit(1)
        }
    }

    @MainActor static func run() throws {
        _ = NSApplication.shared
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var checks = 0
        var observations: [[String: Any]] = []
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure(message: message) }
            checks += 1
        }
        func raster(size: CGSize, name: String, draw: (CGContext) -> Void) throws -> Bitmap {
            let width = Int(size.width), height = Int(size.height)
            let data = NSMutableData(length: width * height * 4)!
            let context = CGContext(data: data.mutableBytes, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
            draw(context)
            guard let image = context.makeImage(),
                  let destination = CGImageDestinationCreateWithURL(out.appendingPathComponent(name + ".png") as CFURL,
                                                                    UTType.png.identifier as CFString, 1, nil) else {
                throw Failure(message: "Cannot create raster evidence")
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure(message: "Cannot write PNG") }
            return Bitmap(width: width, height: height,
                          bytes: Array(Data(bytes: data.bytes, count: data.length)))
        }

        let background = PRPanelGlassBackground(frame: CGRect(x: 0, y: 0, width: 320, height: 80))
        background.cornerRadius = 26
        try check(!background.isFlipped, "Production background must use the tested unflipped coordinate system")
        try check(background.layer?.mask is CAShapeLayer, "Native background must own its top-corner mask")
        try check(background.layer?.cornerRadius == 0, "Native wrapper must not reintroduce four-corner rounding")
        try check(background.layer?.masksToBounds == true, "Native effect must be clipped by its wrapper")
        try check(background.hitTest(.zero) == nil, "Background must not intercept collection interaction")
        let effect = background.subviews[0]
        try check(effect.layer?.cornerRadius ?? 0 == 0, "Inner effect must not round bottom corners")

        for (index, size) in [CGSize(width: 320, height: 80), CGSize(width: 96, height: 48), CGSize(width: 512, height: 120)].enumerated() {
            let bounds = CGRect(origin: .zero, size: size)
            let surface = ReplicaPanelSurface.shape(cornerRadius: 26)
            let path = surface.path(in: bounds)
            try check(!path.contains(CGPoint(x: 1, y: 1)), "SwiftUI top-left must be cut out")
            try check(!path.contains(CGPoint(x: size.width - 1, y: 1)), "SwiftUI top-right must be cut out")
            try check(path.contains(CGPoint(x: 1, y: size.height - 1)), "SwiftUI bottom-left must be square")
            try check(path.contains(CGPoint(x: size.width - 1, y: size.height - 1)), "SwiftUI bottom-right must be square")
            let fill = try raster(size: size, name: "surface-fill-\(index)") { context in
                // SwiftUI paths use top-down coordinates; Quartz draws bottom-up.
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                context.setFillColor(CGColor(gray: 1, alpha: 1))
                context.addPath(path.cgPath)
                context.fillPath()
            }
            let outline = try raster(size: size, name: "surface-outline-\(index)") { context in
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
                context.setStrokeColor(CGColor(gray: 1, alpha: 1))
                context.setLineWidth(2)
                context.addPath(surface.inset(by: 1).path(in: bounds).cgPath)
                context.strokePath()
            }
            try check(fill.alpha(1, 1) < 10 && fill.alpha(fill.width - 2, 1) < 10, "Rendered SwiftUI top pixels must be transparent")
            try check(fill.alpha(1, fill.height - 2) > 245 && fill.alpha(fill.width - 2, fill.height - 2) > 245,
                      "Rendered SwiftUI bottom pixels must remain filled")
            try check(outline.alpha(1, 1) < 10 && outline.alpha(outline.width - 2, 1) < 10,
                      "Rendered outline must not restore top square corners")
            try check(outline.alpha(0, outline.height - 1) > 100 && outline.alpha(outline.width - 1, outline.height - 1) > 100,
                      "Rendered outline must reach both bottom corners")

            background.frame = bounds
            background.layoutSubtreeIfNeeded()
            let layer = background.layer!
            let mask = layer.mask as! CAShapeLayer
            let stablePath = mask.path!
            background.cornerRadius = 26
            background.needsLayout = true
            background.layoutSubtreeIfNeeded()
            try check(mask.path === stablePath, "Unchanged bounds/radius must retain the existing native mask path")
            layer.backgroundColor = CGColor(gray: 1, alpha: 1)
            let native = try raster(size: size, name: "native-wrapper-\(index)") { context in
                layer.render(in: context)
            }
            let nativeAlphas = [native.alpha(1, 1), native.alpha(native.width - 2, 1),
                                native.alpha(1, native.height - 2), native.alpha(native.width - 2, native.height - 2)]
            observations.append(["size": [size.width, size.height], "nativeAlphaTopThenBottom": nativeAlphas,
                                 "nativeGeometryFlipped": layer.isGeometryFlipped])
            try check(nativeAlphas[0] < 10 && nativeAlphas[1] < 10, "Native top pixels must be cut out after resize")
            try check(nativeAlphas[2] > 245 && nativeAlphas[3] > 245, "Native bottom pixels must remain filled after resize")
            try check(layer.bounds.size == size, "Native layer must track its resized view")
        }
        let result: [String: Any] = ["passed": true, "checks": checks, "observations": observations,
                                   "limits": ["Offscreen shape/layer raster evidence only; no real window screenshot or scrolling acceptance",
                                              "macOS 26 intrinsic glass reset is source-checked; this host uses the older visual-effect branch",
                                              "No claim that this change resolves whole-app lag"]]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: out.appendingPathComponent("result.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
