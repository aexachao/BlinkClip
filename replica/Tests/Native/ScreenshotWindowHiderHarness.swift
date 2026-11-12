import AppKit

// Only the private Stack type identity is represented by a fixture. The window
// selection, ordering, delegate and restoration code is the production source.
@MainActor private final class ReplicaStackPanel: NSPanel {}
@MainActor private final class ReplicaEditorWindow: NSWindow {}
@MainActor private final class ProbeDelegate: NSObject, NSWindowDelegate {
    var closes = 0
    var resigns = 0
    func windowWillClose(_ notification: Notification) { closes += 1 }
    func windowDidResignKey(_ notification: Notification) { resigns += 1 }
}

@main struct ScreenshotWindowHiderHarness {
    enum Failure: Error { case assertion(String) }
    @MainActor static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        var checks: [String] = []
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure.assertion(message) }
            checks.append(message)
        }
        func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.04)) }
        let rect = NSRect(x: -20000, y: -20000, width: 300, height: 200)
        func window() -> NSWindow {
            let w = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            return w
        }
        let panel = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.identifier = NSUserInterfaceItemIdentifier("blinkclip-panel")
        let child = window()
        panel.addChildWindow(child, ordered: .above)
        let stack = ReplicaStackPanel(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        stack.isReleasedWhenClosed = false
        let settings = window(), ordinary = window(), about = window()
        about.identifier = NSUserInterfaceItemIdentifier("blinkclip-about-window")
        let editor = ReplicaEditorWindow(contentRect: rect, styleMask: .titled, backing: .buffered, defer: false)
        editor.isReleasedWhenClosed = false
        let menuLevelPanel = NSPanel(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
        menuLevelPanel.isReleasedWhenClosed = false
        menuLevelPanel.level = .mainMenu
        let impostor = window()
        impostor.identifier = panel.identifier
        let fixtures = [panel, child, stack, settings, ordinary, about, editor, menuLevelPanel, impostor]
        let delegate = ProbeDelegate(), replacement = ProbeDelegate()
        panel.delegate = delegate
        for w in fixtures { w.orderFront(nil) }
        let alert = NSAlert()
        alert.messageText = "Capture settings fixture"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        var sheetCompletions = 0
        alert.beginSheetModal(for: settings) { _ in sheetCompletions += 1 }
        drain()
        // AppKit positions sheets against their parent; keep this fixture offscreen too.
        alert.window.setFrameOrigin(rect.origin)
        defer {
            settings.endSheet(alert.window)
            for w in fixtures { w.orderOut(nil) }
        }
        try require(settings.attachedSheet === alert.window && alert.window.isVisible, "real NSAlert sheet attached and visible")
        let preserved = [settings, ordinary, about, editor, menuLevelPanel, impostor]
        let hider = ScreenshotWindowHider()
        hider.hideVisibleBlinkClipWindows()
        drain()
        try require(!panel.isVisible && !stack.isVisible, "only history and exact Stack panels hidden")
        try require(!child.isVisible && child.parent === panel, "child menu follows parent without detachment")
        try require(preserved.allSatisfy(\.isVisible), "settings about editor ordinary and unrelated panels stay visible")
        try require(settings.attachedSheet === alert.window && alert.window.isVisible && sheetCompletions == 0, "settings sheet retained without confirm cancel or completion")
        try require(panel.delegate == nil && delegate.closes == 0 && delegate.resigns == 0, "delegate detached before temporary hide without close")
        hider.hideVisibleBlinkClipWindows()
        hider.reattachDelegates()
        try require(panel.delegate === delegate, "next-turn delegate reattachment")
        // A replacement installed during capture must not be overwritten on restore.
        panel.delegate = replacement
        let activeBeforeRestore = app.isActive
        hider.restore()
        drain()
        try require(panel.isVisible && stack.isVisible, "idempotent hide retains original restore entries")
        try require(child.parent === panel && child.isVisible, "attached child follows restored parent")
        try require(panel.delegate === replacement, "restore preserves replacement delegate")
        try require(!activeBeforeRestore && !app.isActive && !panel.isKeyWindow, "inactive restoration does not activate or steal key focus")
        try require(settings.attachedSheet === alert.window && alert.window.isVisible && sheetCompletions == 0, "restore leaves real sheet lifecycle untouched")
        panel.orderOut(nil)
        hider.restore()
        try require(!panel.isVisible, "second restore cannot resurrect a subsequently hidden panel")
        // Closed/dismissed child windows must not be independently resurrected.
        panel.orderFront(nil)
        child.orderFront(nil)
        hider.hideVisibleBlinkClipWindows()
        panel.removeChildWindow(child)
        child.orderOut(nil)
        hider.restore()
        try require(!child.isVisible && child.parent == nil, "dismissed child not resurrected")
        let output: [String: Any] = ["passed": checks.count, "checks": checks,
            "production": "ScreenshotWindowHider.swift", "boundaries": ["offscreen AppKit fixtures, no app activation", "Stack identity fixture; actual private UI type not linked", "active-app key restoration branch not exercised"]]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
