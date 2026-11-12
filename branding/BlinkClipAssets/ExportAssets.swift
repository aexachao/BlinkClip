import AppKit
import Foundation

/// Run together with BlinkClipAssetRenderer.swift. All exports require an explicit external output path.
@main struct ExportBlinkClipAssets {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 3 else { fatalError("Usage: export-assets OUT REPO") }
        let out=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let repo=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
        try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
        func raster(_ image:NSImage, _ scale:Int) -> NSBitmapImageRep {
            let w=Int(image.size.width)*scale,h=Int(image.size.height)*scale
            let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
            rep.size=image.size
            NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
            image.draw(in:NSRect(origin:.zero,size:image.size),from:.zero,operation:.copy,fraction:1)
            NSGraphicsContext.restoreGraphicsState();return rep
        }
        func save(_ image:NSImage,_ name:String,_ scale:Int) throws {
            try raster(image,scale).representation(using:.png,properties:[:])!.write(to:out.appendingPathComponent(name+(scale==2 ? "@2x" : "")+".png"))
        }
        var rows:[(String,NSImage)]=[]
        for dark in [false,true] {
            for direct in [true,false] {
                let name="BlinkClipSettings"+(direct ? "DirectPaste" : "Clipboard")+(dark ? "Dark" : "Light")
                let image=BlinkClipAssetRenderer.settings(directPaste:direct,dark:dark)
                for scale in [1,2] { try save(image,name,scale) };rows.append((name,image))
            }
            let name="BlinkClipPermission"+(dark ? "Dark" : "Light")
            let image=BlinkClipAssetRenderer.permission(dark:dark)
            for scale in [1,2] { try save(image,name,scale) }; rows.append((name,image))
        }
        for kind in BlinkClipAssetRenderer.Category.allCases {
            for scale in [1,2] { try save(BlinkClipAssetRenderer.category(kind),"BlinkClipCategory-"+kind.rawValue,scale) }
        }
        let sheet=NSImage(size:.init(width:720,height:620),flipped:true) { _ in
            for (i,row) in rows.enumerated() {
                let x=CGFloat(i%3)*240,y=CGFloat(i/3)*200
                (i>=3 ? NSColor(white:0.10,alpha:1) : .init(white:0.95,alpha:1)).setFill()
                NSRect(x:x,y:y,width:240,height:200).fill()
                row.1.draw(in:.init(x:x+(240-row.1.size.width)/2,y:y+26,width:row.1.size.width,height:row.1.size.height))
                (row.0 as NSString).draw(at:.init(x:x+8,y:y+174),withAttributes:[.font:NSFont.systemFont(ofSize:10),.foregroundColor:i>=3 ? NSColor.white : NSColor.black])
            }
            for (j,dark) in [false,true].enumerated() {
                let y=CGFloat(420+j*80)
                (dark ? NSColor(white:0.1,alpha:1) : .white).setFill();NSRect(x:0,y:y,width:720,height:80).fill()
                for (i,kind) in BlinkClipAssetRenderer.Category.allCases.enumerated() {
                    let image=BlinkClipAssetRenderer.category(kind)
                    image.isTemplate=false
                    let tinted=NSImage(size:image.size,flipped:true) { _ in
                        image.draw(at:.zero,from:.zero,operation:.sourceOver,fraction:1)
                        (dark ? NSColor.white : .black).setFill();NSRect(origin:.zero,size:image.size).fill(using:.sourceIn);return true
                    }
                    tinted.draw(in:.init(x:20+CGFloat(i)*170,y:y+12,width:20,height:20))
                    tinted.draw(in:.init(x:55+CGFloat(i)*170,y:y+8,width:40,height:40))
                    (kind.rawValue as NSString).draw(at:.init(x:20+CGFloat(i)*170,y:y+54),withAttributes:[.font:NSFont.systemFont(ofSize:11),.foregroundColor:dark ? NSColor.white : .black])
                }
            }
            return true
        }
        try save(sheet,"review-sheet",2)
        let icon=NSImage(contentsOf:repo.appendingPathComponent("replica/Assets/BlinkClipIcon.png"))!
        let iconSheet=NSImage(size:.init(width:384,height:160),flipped:true) { _ in
            for i in 0..<2 {
                (i==0 ? NSColor.white : NSColor(white:0.12,alpha:1)).setFill();NSRect(x:CGFloat(i)*192,y:0,width:192,height:160).fill()
                icon.draw(in:.init(x:CGFloat(i)*192+16,y:20,width:64,height:64))
                icon.draw(in:.init(x:CGFloat(i)*192+96,y:20,width:80,height:80))
            };return true
        }
        try save(iconSheet,"existing-icon-64-boundary",2)
        let rep=raster(icon,1)
        let corners=[(0,0),(rep.pixelsWide-1,0),(0,rep.pixelsHigh-1),(rep.pixelsWide-1,rep.pixelsHigh-1)].map { rep.colorAt(x:$0.0,y:$0.1)!.alphaComponent }
        let report:[String:Any]=["exportedPNGCount":22,"settingsLogicalSize":[192,128],"settingsDisplaySize":[96,64],"categoryLogicalSize":[20,20],"permissionLogicalSize":[240,144],"scales":[1,2],"iconSize":[rep.pixelsWide,rep.pixelsHigh],"iconCornerAlpha":corners,"integration":"not performed"]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("asset-validation.json"))
        print(out.path)
    }
}
