import AppKit
import Foundation
import SwiftUI
import BlinkClipCore

@main struct CardSourceIconHarness {
    struct Failure: Error { let message: String }
    static var assertions = 0
    static func check(_ condition: Bool, _ message: String) throws {
        assertions += 1
        if !condition { throw Failure(message: message) }
    }
    @MainActor static func artwork(_ size: NSSize) -> Data {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill(); NSRect(origin: .zero, size: size).fill(using: .copy)
        let w = size.width * 0.16, h = size.height * 0.16
        for (color, x, y) in [(NSColor.red, 0.0, 0.0), (.green, size.width-w, 0.0),
                               (.blue, 0.0, size.height-h), (.yellow, size.width-w, size.height-h)] {
            color.setFill(); NSRect(x: x, y: y, width: w, height: h).fill()
        }
        image.unlockFocus()
        return image.tiffRepresentation!
    }
    @MainActor static func render<V: View>(_ view: V, size: NSSize) async throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(NSApp.appearance?.name == .darkAqua ? .dark : .light))
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -5000, y: -5000), size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSApp.appearance
        window.isReleasedWhenClosed = false; window.contentView = hosting; window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw Failure(message: "no bitmap") }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }
    static func markers(_ bitmap: NSBitmapImageRep) -> (counts: [Int], rect: CGRect) {
        var counts = [0,0,0,0], minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = 0, maxY = 0
        for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
            guard let c = bitmap.colorAt(x: x,y: y), c.alphaComponent > 0.9 else { continue }
            let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
            let index: Int?
            if r > 0.9 && g < 0.1 && b < 0.1 { index = 0 }
            else if g > 0.9 && r < 0.1 && b < 0.1 { index = 1 }
            else if b > 0.9 && r < 0.1 && g < 0.1 { index = 2 }
            else if r > 0.9 && g > 0.9 && b < 0.1 { index = 3 }
            else { index = nil }
            if let index { counts[index] += 1; minX=min(minX,x); minY=min(minY,y); maxX=max(maxX,x); maxY=max(maxY,y) }
        }}
        return (counts, CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1))
    }
    static func save(_ bitmap: NSBitmapImageRep, _ name: String, _ out: URL) throws {
        if ProcessInfo.processInfo.environment["BLINKCLIP_SKIP_SCREENSHOTS"] == "1" { return }
        try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
    }
    @MainActor static func main() async {
        do { try await run() } catch { print("FAIL \(error)"); exit(1) }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        guard let task = ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"] else { throw Failure(message: "managed root required") }
        let runID = ProcessInfo.processInfo.environment["BLINKCLIP_ICON_RUN_ID"] ?? "1"
        guard ["1","2","3"].contains(runID) else { throw Failure(message: "invalid run") }
        let fixture = URL(fileURLWithPath: task).appendingPathComponent("build/fixture-\(runID)")
        let store = try ClipboardStore(directoryURL: fixture)
        let state = ReplicaUIState(store: store)
        let sizes: [CGFloat] = [180,220,260,300]
        var examples: [(ClipboardItem, String)] = []
        for (name, dimensions) in [("square",NSSize(width:100,height:100)),("wide",NSSize(width:160,height:80)),("tall",NSSize(width:80,height:160))] {
            let app = SourceApplicationRecord(bundleIdentifier:"fixture.\(name)",name:name,rawIcon:artwork(dimensions))
            let item = ClipboardItem(title:"Source title",plainText:"Fixture body",sourceName:name,sourceBundleID:app.bundleIdentifier,payloads:["public.utf8-plain-text":Data(name.utf8)])
            let id = try store.add(item,sourceApplication:app)
            examples.append((store.items.first(where:{$0.id==id})!,name))
        }
        for mode in [NSAppearance.Name.aqua,.darkAqua] {
            NSApp.appearance = NSAppearance(named:mode)
            for (item,name) in examples {
                for side in sizes {
                    let bitmap = try await render(ReplicaClipboardCard(state:state,item:item,sideLength:side),size:NSSize(width:side,height:side))
                    let marks = markers(bitmap)
                    if marks.counts.contains(0) {
                        print("diagnostic source", store.sourceApplication(for:item)?.rawIcon?.count ?? -1, CardSourceIconPresentation.image(data:store.sourceApplication(for:item)?.rawIcon,boundingSize:NSSize(width:20,height:20))?.size ?? .zero, "bitmap", bitmap.pixelsWide, bitmap.pixelsHigh)
                        try save(bitmap,"diagnostic-failure",out)
                    }
                    try check(marks.counts.allSatisfy{$0 > 0}, "all four artwork edges visible: \(mode.rawValue) \(name) \(side) \(marks.counts)")
                    let ratio = marks.rect.width / marks.rect.height
                    let expected: CGFloat = name == "wide" ? 2 : name == "tall" ? 0.5 : 1
                    try check(abs(ratio-expected) < 0.2, "aspect ratio preserved: \(name) \(side) \(ratio)")
                    let scale = CGFloat(bitmap.pixelsWide) / side
                    try check(marks.rect.maxX <= CGFloat(bitmap.pixelsWide) - 6*scale, "trailing inset retained")
                    try check(marks.rect.minX > side*scale*0.55, "icon stays at trailing edge; text area preserved")
                    if side == 300 && name == "square" || side == 180 && name == "square" || side == 300 && name == "wide" {
                        try save(bitmap,"\(mode.rawValue)-\(name)-\(Int(side))",out)
                    }
                }
            }
        }
        try check(CardSourceIconPresentation.image(data:Data([0,1,2]),boundingSize:NSSize(width:44,height:44)) == nil,"bad icon uses fallback")
        try check(CardSourceIconPresentation.image(data:nil,boundingSize:NSSize(width:44,height:44)) == nil,"missing icon uses fallback")
        let unknownID = try store.add(ClipboardItem(title:"Unknown",plainText:"Unknown body",sourceName:"Unknown",sourceBundleID:"fixture.invalid",payloads:["public.utf8-plain-text":Data("unique invalid content".utf8)]),sourceApplication:SourceApplicationRecord(bundleIdentifier:"fixture.invalid",name:"Unknown",rawIcon:Data([0,1,2])))
        let unknown = store.items.first{$0.id==unknownID}!
        let fallback = try await render(SourceAppIcon(item:unknown,store:store).frame(width:44,height:44),size:NSSize(width:44,height:44))
        var distinct = Set<String>()
        for y in 0..<fallback.pixelsHigh { for x in 0..<fallback.pixelsWide {
            if let c=fallback.colorAt(x:x,y:y) { distinct.insert("\(Int(c.redComponent*255))-\(Int(c.greenComponent*255))-\(Int(c.blueComponent*255))") }
        }}
        try check(distinct.count > 2,"actual bad source icon renders nonblank app fallback")
        let board = try store.createPinboard(name:"Fixture group",colorHex:"#808080")
        let grouped = ClipboardItem(title:"Grouped",plainText:"Grouped body",sourceName:"square",sourceBundleID:"fixture.square",payloads:["public.utf8-plain-text":Data("unique grouped content".utf8)],pinboardIDs:[board.id],pinboardOwnerID:board.id)
        let groupedID = try store.add(grouped,sourceApplication:SourceApplicationRecord(bundleIdentifier:"fixture.square",name:"square",rawIcon:artwork(NSSize(width:100,height:100))))
        let groupedItem = store.items.first{$0.id==groupedID}!
        try check(store.pinboardOwner(for:groupedItem)?.id == board.id,"group fixture has actual owning pinboard")
        let groupedBitmap = try await render(ReplicaClipboardCard(state:state,item:groupedItem,sideLength:300),size:NSSize(width:300,height:300))
        try check(markers(groupedBitmap).counts.allSatisfy{$0==0},"pinboard owner keeps its own header icon")
        try save(groupedBitmap,"pinboard-owner",out)
        let terminal = NSWorkspace.shared.icon(forFile:"/System/Applications/Utilities/Terminal.app")
        let terminalApp = SourceApplicationRecord(bundleIdentifier:"fixture.terminal",name:"Terminal",rawIcon:terminal.tiffRepresentation)
        let terminalID = try store.add(ClipboardItem(title:"Terminal",plainText:"Read-only system launch icon fixture",sourceName:"Terminal",sourceBundleID:terminalApp.bundleIdentifier,payloads:["public.utf8-plain-text":Data("unique terminal content".utf8)]),sourceApplication:terminalApp)
        try check(store.sourceApplication(for:store.items.first{$0.id==terminalID}!)?.bundleIdentifier == terminalApp.bundleIdentifier,"terminal fixture source identity")
        let terminalBitmap = try await render(ReplicaClipboardCard(state:state,item:store.items.first{$0.id==terminalID}!,sideLength:300),size:NSSize(width:300,height:300))
        try save(terminalBitmap,"system-terminal-launch-icon",out)
        let result: [String:Any] = ["passed":true,"assertions":assertions,"runID":runID,"fixtureDirectory":fixture.path,"screenshots":"Actual SourceAppIcon and ReplicaClipboardCard, offscreen AppKit, not visible app acceptance","scope":"Synthetic four-edge artwork; isolated store; read-only Terminal icon; no history/TCC/hotkeys/monitor"]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("result.json"))
        print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
    }
}
