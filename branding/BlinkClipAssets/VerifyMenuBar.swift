import AppKit
import Foundation
// Verification-only stub; actual source file is compiled from a read-only copy with its module import removed.
enum AppBrand { static let name="BlinkClip"; static func replacingLegacyName(in text:String)->String { text } }
@main struct VerifyMenuBar {
    @MainActor static func main() throws {
        let out=URL(fileURLWithPath:CommandLine.arguments[1])
        let image=ReplicaBrand.menuBarImage()
        precondition(image.isTemplate && image.size == NSSize(width:18,height:18))
        precondition(image.accessibilityDescription == "BlinkClip")
        let sheet=NSImage(size:.init(width:300,height:100),flipped:true) { _ in
            for i in 0..<2 {
                let x=CGFloat(i)*150
                (i==0 ? NSColor.white : NSColor(white:0.12,alpha:1)).setFill();NSRect(x:x,y:0,width:150,height:100).fill()
                let tinted=NSImage(size:image.size,flipped:true) { _ in
                    image.draw(in:NSRect(origin:.zero,size:image.size),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                    (i==0 ? NSColor.black : .white).setFill();NSRect(origin:.zero,size:image.size).fill(using:.sourceIn);return true
                }
                tinted.draw(in:.init(x:x+20,y:20,width:18,height:18),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
                tinted.draw(in:.init(x:x+64,y:20,width:36,height:36),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:true,hints:nil)
            };return true
        }
        let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:600,pixelsHigh:200,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        rep.size=sheet.size;NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        sheet.draw(in:NSRect(origin:.zero,size:sheet.size));NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent("menu-bar-review@2x.png"))
        print("Menu template size/name assertions passed")
    }
}
