import AppKit
import Foundation

@main struct HistoryRetentionHarness {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    static var assertions = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        assertions += 1
        if !value() { throw Failure(message: message) }
    }
    @MainActor static func settle(_ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < deadline
        throw Failure(message: "native sheet did not finish")
    }
    @MainActor static func choose(_ view: HistoryCapacityControl, _ days: Int) {
        view.optionButtons.first { $0.tag == days }!.performClick(nil)
    }
    @MainActor static func key(_ view: NSView, _ chars: String, _ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: view.window!.windowNumber, context: nil, characters: chars,
            charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }
    @MainActor static func capture(_ view: NSView, _ name: String, _ out: URL) throws {
        guard ProcessInfo.processInfo.environment["BLINKCLIP_SKIP_SCREENSHOTS"] != "1" else { return }
        view.wantsLayer = true
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        view.layoutSubtreeIfNeeded()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
    }
    @MainActor static func captureParentAndAlert(_ parent: NSWindow, _ alert: NSWindow, _ name: String, _ out: URL) throws {
        guard ProcessInfo.processInfo.environment["BLINKCLIP_SKIP_SCREENSHOTS"] != "1" else { return }
        let union = parent.frame.union(alert.frame)
        let image = NSImage(size: union.size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill(); NSRect(origin: .zero, size: union.size).fill()
        for window in [parent, alert] {
            guard let content = window.contentView,
                  let frameView = content.superview,
                  let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { continue }
            frameView.effectiveAppearance.performAsCurrentDrawingAppearance {
                frameView.cacheDisplay(in: frameView.bounds, to: rep)
            }
            let rect = window.frame.offsetBy(dx: -union.minX, dy: -union.minY)
            rep.draw(in: rect)
        }
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name + ".png"))
    }
    @MainActor static func main() {
        do { try run() } catch { print("FAIL \(error)"); exit(1) }
    }
    @MainActor static func run() throws {
        let env = ProcessInfo.processInfo.environment
        guard let task = env["ARTIFACT_TASK_DIR"], let run = env["BLINKCLIP_RETENTION_RUN_ID"], ["1","2","3"].contains(run) else { exit(64) }
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let lang = Locale.preferredLanguages.first ?? "unknown"
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory); NSApp.finishLaunching()
        NSApp.appearance = NSAppearance(named: .aqua)
        let view = HistoryCapacityControl(frame: NSRect(x: 0,y: 0,width: 400,height: 208))
        let host = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 600), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.titleVisibility = .hidden; host.titlebarAppearsTransparent = true
        let toolbar = NSToolbar(identifier: "BlinkClipSettings"); toolbar.showsBaselineSeparator = false
        host.toolbar = toolbar; host.toolbarStyle = .unified
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 648, height: 600))
        view.frame.origin = NSPoint(x: 220, y: 300)
        container.addSubview(view)
        host.contentView = container; host.orderFront(nil)
        defer { host.orderOut(nil); host.contentView = nil; host.close() }
        try check(host.contentView!.bounds.width == 648 && host.toolbar?.identifier == "BlinkClipSettings" && host.styleMask.contains(.fullSizeContentView), "actual settings parent dimensions and toolbar style")
        let initialInvalidations = view.intrinsicInvalidations
        for _ in 0..<100 { view.setDays(7); view.layoutSubtreeIfNeeded() }
        try check(view.intrinsicInvalidations == initialInvalidations, "same-value redraw does not invalidate intrinsic size")
        try check(view.requiredHeight < 150, "normal control does not reserve empty error space")
        var values: [Int] = []
        view.onCommit = { values.append($0) }
        try check(view.optionButtons.map(\.tag) == [1,3,7,15,30,60,0], "only seven choices")
        try check(view.optionButtons.allSatisfy { $0.accessibilityRole() == .radioButton }, "native accessible radio roles")
        for existing in [14,21,365,50_000,Int.max,-5] {
            view.setDays(existing); view.propose(existing)
            try check(view.currentDays == existing && values.isEmpty, "legacy retained without writing")
            try check(view.optionButtons.filter { $0.state == .on }.count == (existing <= 0 ? 1 : 0), "no extra legacy choice")
        }
        for bad in [2,14,21,365,-1,Int.max] { view.propose(bad) }
        try check(values.isEmpty && view.currentDays == -5, "arbitrary new values rejected")
        view.confirmShortening = { _, done in done(true) }
        for days in HistoryCapacityControl.presets {
            choose(view, days)
            try check(view.optionButtons.first { $0.tag == days }?.state == .on, "real button retains selected state after action")
        }
        try check(values == HistoryCapacityControl.presets, "real seven button actions")
        for days in HistoryCapacityControl.presets {
            view.setDays(days)
            try check(view.optionButtons.first { $0.tag == days }?.state == .on, "selected native state")
            try check(view.optionButtons.first { $0.tag == days }?.accessibilityValue() as? Int == 1, "selected accessibility value")
        }
        var decision: ((Bool)->Void)?
        view.confirmShortening = { _, done in decision = done }
        values.removeAll(); view.setDays(0); choose(view, 7)
        try check(view.isAwaitingConfirmation && values.isEmpty && view.currentDays == 0, "forever shortening awaits")
        try check(view.optionButtons.allSatisfy { !$0.isEnabled }, "pending controls disabled")
        decision?(false)
        try check(values.isEmpty && view.currentDays == 0 && view.optionButtons.last!.state == .on, "cancel no write")
        choose(view, 7); view.setDays(30); decision?(true)
        try check(values.isEmpty && view.currentDays == 30 && !view.errorMessage.isEmpty, "stale confirmation ignored")
        let fixture = URL(fileURLWithPath: task).appendingPathComponent("build/preference-\(run)-\(lang).json")
        var preference = 7; var fail = false
        view.setDays(7)
        view.onCommit = { days in
            try HistoryRetentionSaving.apply(days, previous: preference, assign: { preference = $0 }, save: {
                if fail { throw Failure(message: "fixture save failure") }
                try JSONEncoder().encode(preference).write(to: fixture, options: .atomic)
            })
        }
        let fifteen = view.optionButtons.first { $0.tag == 15 }!
        host.makeFirstResponder(fifteen); fifteen.keyDown(with: key(fifteen," ",49))
        try check(view.currentDays == 15 && preference == 15, "keyboard space activates focused choice")
        let reread = try JSONDecoder().decode(Int.self, from: Data(contentsOf: fixture))
        try check(reread == 15, "saved preference reread")
        fail = true; choose(view,30); view.setDays(preference)
        try check(view.currentDays == 15 && preference == 15 && !view.errorMessage.isEmpty, "failed save preserves preference selection and error")
        fail = false; view.confirmShortening = nil
        for (chars,code) in [("\r",UInt16(36)),("\u{3}",UInt16(76)),("\u{1b}",UInt16(53))] {
            view.setDays(60); choose(view,1)
            try settle { host.attachedSheet != nil }
            guard let alert = view.activeAlert else { throw Failure(message: "native alert owner missing") }
            let sheet = alert.window
            try check(host.attachedSheet === sheet && sheet.isVisible, "native NSAlert visible and attached")
            try check(alert.buttons.count == 2 && alert.buttons.allSatisfy { !$0.isHidden && $0.bounds.width > 0 && $0.bounds.height > 0 }, "native alert buttons laid out")
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: sheet.windowNumber, context: nil, characters: chars,
                charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            NSApp.sendEvent(event)
            try settle { host.attachedSheet == nil && !view.isAwaitingConfirmation }
            try check(view.currentDays == 60 && preference == 15, "confirmation keyboard safely cancels \(code)")
        }
        choose(view,3)
        try settle { host.attachedSheet != nil }
        view.activeAlert!.buttons[1].performClick(nil)
        try settle { host.attachedSheet == nil && view.currentDays == 3 }
        try check(preference == 3, "explicit native confirm commits fixture")
        try check(view.activeAlert == nil && view.optionButtons.allSatisfy(\.isEnabled), "native completion clears owner and restores interaction")
        let normalHeight = view.requiredHeight
        fail = true; choose(view, 30)
        try check(view.requiredHeight > normalHeight && !view.errorLabel.isHidden, "failure occupies space only while visible")
        fail = false; choose(view, 30)
        try check(view.requiredHeight == normalHeight && view.errorLabel.isHidden, "success releases error height")
        host.makeFirstResponder(nil)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            host.appearance = NSAppearance(named: appearance); NSApp.appearance = host.appearance
            view.setDays(7); view.frame.size.height = view.requiredHeight
            try capture(view,"\(lang)-tiles-\(appearance.rawValue)-400pt-2x",out)
            try check(view.optionButtons.allSatisfy { $0.frame.maxX <= 400 && $0.frame.minX >= 0 && $0.frame.height == 44 }, "tile layout bounds")
        }
        host.appearance = NSAppearance(named: .aqua); NSApp.appearance = host.appearance
        view.setDays(21); view.frame.size.height = view.requiredHeight
        if lang.hasPrefix("zh") { try capture(view,"zh-legacy-400pt-2x",out) }
        try check(!view.legacyLabel.isHidden && view.optionButtons.count == 7, "legacy readonly explanation")
        view.confirmShortening = nil; view.setDays(60); choose(view,1)
        try settle { host.attachedSheet?.isVisible == true }
        let alert = view.activeAlert!
        try check(alert.window.frame.intersects(host.frame), "native sheet is positioned with parent")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            host.appearance = NSAppearance(named: appearance); NSApp.appearance = host.appearance
            alert.window.appearance = host.appearance
            alert.window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
            alert.window.displayIfNeeded()
            try check(!alert.buttons[1].hasDestructiveAction, "confirmation uses ordinary system button styling")
            try check(alert.window.defaultButtonCell === alert.buttons[0].cell && alert.buttons[0].keyEquivalent == "\r" && alert.buttons[1].keyEquivalent.isEmpty, "cancel remains safe native default")
            // AppKit button bounds include shadows that can overlap in native alert layout.
            // Compare alignment rectangles for the visible controls instead.
            let frames = alert.buttons.map { button in
                button.superview!.convert(button.alignmentRect(forFrame: button.frame), to: alert.window.contentView)
            }
            print("ALERT_GEOMETRY \(lang) \(appearance.rawValue) content=\(alert.window.contentView!.bounds) buttons=\(frames)")
            try check(frames.allSatisfy { alert.window.contentView!.bounds.contains($0) } && !frames[0].intersects(frames[1]), "native adjacent buttons fit without clipping or overlap")
            try captureParentAndAlert(host, alert.window, "\(lang)-native-parent-alert-\(appearance.rawValue)-composite", out)
        }
        alert.buttons[0].performClick(nil)
        try settle { host.attachedSheet == nil && view.activeAlert == nil }
        try check(view.optionButtons.allSatisfy(\.isEnabled), "cancel restores all controls")
        view.setDays(60); choose(view,1)
        try settle { host.attachedSheet?.isVisible == true }
        host.close()
        try settle { view.activeAlert == nil && !view.isAwaitingConfirmation }
        try check(preference == 30, "parent close cancels without save")
        let result: [String: Any] = ["passed":true,"assertions":assertions,"language":lang,"runID":run,"fixture":fixture.path,"boundaries":["Real NSButtons, focused Space, and sheet keys; isolated JSON only.","Offscreen AppKit cacheDisplay, not a visible settings page or real history deletion.","No ClipboardStore, defaults, TCC, global keys, or app launch."]]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]).write(to: out.appendingPathComponent("result-\(lang).json"))
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted,.sortedKeys]), encoding:.utf8)!)
    }
}
