import AppKit
import Foundation
import SwiftUI
import BlinkClipCore
import BlinkClipCapture

@MainActor private final class OffscreenSettingsWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@main struct SettingsArchitectureHarness {
    struct Failure: Error { let message: String }
    static var assertions = 0
    @MainActor static var captures: [(String, NSImage)] = []
    static func check(_ value: Bool, _ message: String) throws {
        assertions += 1
        if !value { throw Failure(message: message) }
    }
    @MainActor static func pause() async { try? await Task.sleep(nanoseconds: 250_000_000) }
    @MainActor static func capture(_ view: NSView, name: String, out: URL) throws {
        guard ProcessInfo.processInfo.environment["BLINKCLIP_SKIP_SCREENSHOTS"] != "1" else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw Failure(message: "no bitmap") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if ProcessInfo.processInfo.environment["BLINKCLIP_SETTINGS_CLIPBOARD_SCREENSHOTS_ONLY"] == "1",
           !name.contains("-3-") { return }
        captures.append((name, NSImage(cgImage: bitmap.cgImage!, size: view.bounds.size)))
    }
    @MainActor static func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, of: type) }
    }
    @MainActor static func pixels(_ view: NSView, headerOnly: Bool) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let target: NSView
        if headerOnly {
            guard let frameView = view.window?.contentView?.superview,
                  let label = descendants(frameView, of: NSTextField.self).first(where: { $0.accessibilityIdentifier() == "BlinkClipSettingsPaneTitle" }) else {
                throw Failure(message: "native toolbar title missing")
            }
            target = label
        } else { target = view }
        guard let bitmap = target.bitmapImageRepForCachingDisplay(in: target.bounds) else { throw Failure(message: "no navigation bitmap") }
        target.cacheDisplay(in: target.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw Failure(message: "no navigation PNG") }
        return data
    }
    @MainActor static func accessibilityTree(_ element: Any) -> [NSObject] {
        var seen = Set<ObjectIdentifier>()
        func visit(_ value: Any) -> [NSObject] {
            guard let node = value as? NSObject, seen.insert(ObjectIdentifier(node)).inserted else { return [] }
            let selector = NSSelectorFromString("accessibilityChildren")
            let children = node.responds(to: selector)
                ? (node.perform(selector)?.takeUnretainedValue() as? [Any] ?? []) : []
            let legacy = node.accessibilityAttributeValue(.children) as? [Any] ?? []
            let views = (node as? NSView)?.subviews ?? []
            return [node] + (children + legacy + views).flatMap(visit)
        }
        return visit(element)
    }
    @MainActor static func axID(_ element: NSObject) -> String? {
        let selector = NSSelectorFromString("accessibilityIdentifier")
        return (element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() as? String : nil)
            ?? element.accessibilityAttributeValue(.identifier) as? String
    }
    @MainActor static func axFrame(_ element: NSObject) -> NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        if element.responds(to: selector) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
            return unsafeBitCast(element.method(for: selector), to: Getter.self)(element, selector)
        }
        let point = (element.accessibilityAttributeValue(.position) as? NSValue)?.pointValue ?? .zero
        let size = (element.accessibilityAttributeValue(.size) as? NSValue)?.sizeValue ?? .zero
        return NSRect(origin: point, size: size)
    }
    @MainActor static func press(_ node: NSObject) -> Bool {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        guard node.responds(to: selector) else { return false }
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(node.method(for: selector), to: Press.self)(node, selector)
    }
    @MainActor static func verifyShortcutRows(store: ClipboardStore, state: ReplicaUIState, model: PermissionStatusModel, out: URL, language: String) async throws {
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix("local.blinkclip.regression.") else { throw Failure(message: "isolated test app domain required") }
        defer { UserDefaults.standard.removePersistentDomain(forName: domain) }
        for row in SettingsShortcutRow.allCases {
            if let path = row.path { store.preferences[keyPath: path] = row.shortcutDefault }
            if let path = row.modifierPath { store.preferences[keyPath: path] = row.modifierDefault }
        }
        BlinkClipScreenshotSettings.setShortcut(BlinkClipScreenshotSettings.regionDefault, for: .region)
        BlinkClipScreenshotSettings.setShortcut(BlinkClipScreenshotSettings.fullScreenDefault, for: .fullScreen)
        try store.save()
        let host = NSHostingView(rootView: ReplicaSettingsView(state: state, initialTab: 4, permissionModel: model))
        let window = OffscreenSettingsWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 800), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil; window.close() }
        await pause()
        func restoreNodes() -> [NSObject] { accessibilityTree(host).filter { (axID($0) ?? "").hasPrefix("settings.shortcut.restore.") } }
        try check(restoreNodes().isEmpty, "all eight default rows hide restore button")
        for row in SettingsShortcutRow.allCases {
            if let path = row.path { store.preferences[keyPath: path] = nil }
            if let path = row.modifierPath { store.preferences[keyPath: path] = 0 }
        }
        BlinkClipScreenshotSettings.setShortcut(.init(keyCode: 98, modifierRawValue: NSEvent.ModifierFlags.command.rawValue), for: .region)
        BlinkClipScreenshotSettings.setShortcut(.init(keyCode: 99, modifierRawValue: NSEvent.ModifierFlags.command.rawValue), for: .fullScreen)
        try store.save()
        await pause()
        let visibleRestoreIDs = Set(restoreNodes().compactMap { axID($0) })
        try check(visibleRestoreIDs.count == 8, "all eight changed rows display restore buttons, including cleared app rows; actual \(visibleRestoreIDs.sorted()); tree \(accessibilityTree(host).map { "\(type(of: $0)):\(axID($0) ?? "-")" })")
        if let frame = window.contentView?.superview, let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(language)-modified-shortcuts-complete-window.png"))
        }
        let restoreRightEdges = Set(restoreNodes().map { axFrame($0).maxX.rounded() })
        try check(restoreRightEdges.count == 1, "all eight restore labels align immediately left of 120pt controls: \(restoreRightEdges)")
        let recorders = accessibilityTree(host).filter { (axID($0) ?? "").hasPrefix("settings.shortcut.recorder.") }
        try check(Set(recorders.compactMap { axID($0) }).count == 6, "six actual recorder accessibility slots")
        var recorderSizes: [NSSize] = []
        for row in SettingsShortcutRow.allCases where row.shortcutDefault != nil {
            let slots = recorders.filter { axID($0) == "settings.shortcut.recorder." + row.rawValue }
            if let slot = slots.first(where: { abs(axFrame($0).width - 120) <= 1 && abs(axFrame($0).height - 24) <= 1 }) { recorderSizes.append(axFrame(slot).size) }
            try check(slots.contains { let frame = axFrame($0); return abs(frame.width - 120) <= 1 && abs(frame.height - 24) <= 1 }, "recorder content is 120 by 24 with at most 1pt outline: \(row), actual \(slots.map { axFrame($0) })")
        }
        try check(recorderSizes.count == 6 && recorderSizes.allSatisfy { $0 == recorderSizes.first! }, "all six recorders have exactly equal outer sizes")
        for row in SettingsShortcutRow.allCases {
            let buttons = restoreNodes().filter { axID($0) == "settings.shortcut.restore." + row.rawValue }
            try check(buttons.contains { press($0) }, "actual modern AX press accepts row \(row)")
            await pause()
            try check(!restoreNodes().contains(where: { axID($0) == "settings.shortcut.restore." + row.rawValue }), "restored row hides its button immediately: \(row)")
        }
        try check(restoreNodes().isEmpty, "all actual buttons disappear after individual restores")
        for slot in BlinkClipScreenshotHotKeySlot.allCases {
            let row = slot == .region ? "region" : "fullScreen"
            let nodes = accessibilityTree(host).filter { axID($0) == "settings.shortcut.recorder." + row }
            var rects: [NSRect] = []
            for node in nodes {
                let rect: NSRect = axFrame(node)
                if abs(rect.width - CGFloat(120)) <= CGFloat(1), abs(rect.height - CGFloat(24)) <= CGFloat(1) {
                    rects.append(rect)
                }
            }
            var clearButtons: [NSObject] = []
            for node in accessibilityTree(host) {
                let rect = axFrame(node)
                guard abs(rect.width - 24) <= 1, abs(rect.height - 24) <= 1 else { continue }
                if rects.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(rect) }) {
                    clearButtons.append(node)
                }
            }
            try check(clearButtons.contains { press($0) }, "actual screenshot recorder x is present and accepts AX press: \(slot)")
            await pause()
            try check(BlinkClipScreenshotSettings.effectiveShortcut(for: slot) == nil, "actual screenshot x clears persisted effective shortcut: \(slot)")
            try check(BlinkClipScreenshotSettings.recordingCount == 0, "clearing screenshot does not begin recording: \(slot)")
            try check(restoreNodes().contains { axID($0) == "settings.shortcut.restore." + row }, "cleared screenshot row displays individual restore: \(slot)")
            if slot == .region, let frame = window.contentView?.superview,
               let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                frame.cacheDisplay(in: frame.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(language)-cleared-region-complete-window.png"))
            }
            var labels: [String] = []
            for node in accessibilityTree(host) {
                for attribute in [NSAccessibility.Attribute.value, .title, .description] {
                    if let text = node.accessibilityAttributeValue(attribute) as? String { labels.append(text) }
                }
                for name in ["accessibilityLabel", "accessibilityValue"] {
                    let selector = NSSelectorFromString(name)
                    if node.responds(to: selector), let text = node.perform(selector)?.takeUnretainedValue() as? String {
                        labels.append(text)
                    }
                }
            }
            try check(labels.contains(SettingsCopy.bilingual("未设置", "Not Set")), "cleared screenshot row displays localized Not Set: \(slot)")
            try check(restoreNodes().filter { axID($0) == "settings.shortcut.restore." + row }.contains { press($0) }, "actual screenshot individual restore accepts AX press: \(slot)")
            await pause()
            try check(BlinkClipScreenshotSettings.effectiveShortcut(for: slot) == BlinkClipScreenshotSettings.default(for: slot), "individual restore re-enables screenshot default: \(slot)")
            try check(!restoreNodes().contains { axID($0) == "settings.shortcut.restore." + row }, "restored screenshot hides individual restore: \(slot)")
        }

        if let frame = window.contentView?.superview, let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(language)-restored-shortcuts-complete-window.png"))
        }
    }
    @MainActor static func main() async {
        do { try await run() } catch { print("FAIL \(error)"); exit(1) }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)
        NSApp.finishLaunching()
        NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        let language = Locale.preferredLanguages.first ?? "unknown"
        let runID = ProcessInfo.processInfo.environment["BLINKCLIP_SETTINGS_RUN_ID"] ?? "1"
        guard ["1", "2", "3"].contains(runID),
              let artifactRoot = ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"] else {
            throw Failure(message: "managed artifact directory and valid run ID required")
        }
        let fixture = URL(fileURLWithPath: artifactRoot, isDirectory: true)
            .appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent("fixture-\(runID)-\(language)", isDirectory: true)
        let store = try ClipboardStore(directoryURL: fixture)
        let state = ReplicaUIState(store: store)
        let model = PermissionStatusModel(readAccessibility: { true }, readPostEvents: { true }, readScreenRecording: { true }, requestScreenAccess: {}, requestAccessibilityAccess: {})
        try check(SettingsSection.allCases.map(\.rawValue) == [0,3,2,4,1,5], "stable ordered section IDs")
        try check(SettingsSection(rawValue: 2) == .screenshot, "screenshot deep link preserved")
        let originalRetention = store.preferences.historyRetentionDays
        var screenshotHeader: Data?
        for appearance in ["light", "dark"] {
        NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        captures = []
        for section in SettingsSection.allCases {
            let hosting = NSHostingView(rootView: ReplicaSettingsView(state: state, initialTab: section.rawValue, permissionModel: model).background(Color(nsColor: .windowBackgroundColor)))
            let window = OffscreenSettingsWindow(contentRect: NSRect(x: -5000,y: -5000,width: 648,height: 600),styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],backing: .buffered,defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = false
            window.toolbarStyle = .unified
            window.setFrame(NSRect(x: -5000, y: -5000, width: 648, height: 600), display: false)
            window.contentView = hosting
            window.orderFront(nil)
            await pause()
            hosting.layoutSubtreeIfNeeded()
            try check(hosting.bounds.width >= 640, "minimum width")
            if appearance == "light", section == .screenshot { screenshotHeader = try pixels(hosting, headerOnly: true) }
            guard let themeFrame = window.contentView?.superview,
                  let title = descendants(themeFrame, of: NSTextField.self).first(where: { $0.accessibilityIdentifier() == "BlinkClipSettingsPaneTitle" }) else { throw Failure(message: "missing complete native titlebar") }
            let titleFrame = title.convert(title.bounds, to: nil)
            try check(title.stringValue == section.title, "native toolbar title matches section")
            try check(titleFrame.minY >= window.contentLayoutRect.maxY, "title above contentLayoutRect: \(titleFrame), layout \(window.contentLayoutRect)")
            try check(titleFrame.minX >= 200, "toolbar title right of sidebar")
            try check(window.frame.maxX < 0 && window.frame.maxY < 0, "window remains entirely off physical screens")
            try check(window.frame.size == NSSize(width: 648, height: 600), "fixed complete window frame: \(window.frame)")
            guard let toolbar = window.toolbar, let owner = toolbar.delegate as? SettingsSplitViewController else { throw Failure(message: "production toolbar delegate missing") }
            try check(title.isEnabled, "native toolbar title label remains enabled")
            try check(toolbar.items.first(where: { $0.view === title })?.isEnabled == true, "native title toolbar item remains enabled")
            let originalItems = toolbar.items.map { ObjectIdentifier($0) }
            for _ in 0..<100 {
                owner.paneTitle = section.title
                owner.viewDidLayout()
            }
            try check(window.toolbar === toolbar && toolbar.items.map { ObjectIdentifier($0) } == originalItems, "100 same-title/layout updates preserve toolbar and item identity")

            try capture(themeFrame, name: "\(language)-\(section.rawValue)-top-640pt", out: out)
            let beforeScrollHeader = try pixels(hosting, headerOnly: true)
            if true {
                let scrolls = descendants(hosting, of: NSScrollView.self)
                for scroll in scrolls where scroll.documentView != nil {
                    let document = scroll.documentView!
                    scroll.contentView.scroll(to: NSPoint(x: 0,y: max(0,document.bounds.height-scroll.contentView.bounds.height)))
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                await pause()
                try capture(themeFrame, name: "\(language)-\(section.rawValue)-bottom-648x600", out: out)
                try check(title.convert(title.bounds, to: nil) == titleFrame, "native toolbar frame stable after scroll")
                try check(try pixels(hosting, headerOnly: true) == beforeScrollHeader, "\(appearance) \(section) header pixels unchanged after scrolling")
            }
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        if !captures.isEmpty {
            let cell = NSSize(width: 648, height: 622)
            let sheet = NSImage(size: NSSize(width: cell.width * 4, height: cell.height * 3))
            sheet.lockFocus()
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: sheet.size).fill()
            for (index, pair) in captures.enumerated() {
                let x = CGFloat(index % 4) * cell.width
                let y = CGFloat(2 - index / 4) * cell.height
                pair.1.draw(in: NSRect(x: x, y: y, width: 648, height: 600))
                (pair.0 as NSString).draw(at: NSPoint(x: x + 8, y: y + 602), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor])
            }
            sheet.unlockFocus()
            let bitmap = NSBitmapImageRep(data: sheet.tiffRepresentation!)!
            try bitmap.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent("\(language)-\(appearance)-six-pages-top-scroll-offscreen.png"))
        }
        }
        NSApp.appearance = NSAppearance(named: .aqua)
                // Independent navigation path: real native outline selection, compared with
        // the rendered screenshot deep-link header. The sidebar is excluded from ROI.
        let navigationHost = NSHostingView(rootView: ReplicaSettingsView(state: state, initialTab: 0, permissionModel: model).background(Color(nsColor: .windowBackgroundColor)))
        let navigationWindow = OffscreenSettingsWindow(contentRect: NSRect(x: -5000,y: -5000,width: 648,height: 600),styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],backing: .buffered,defer: false)
        navigationWindow.isReleasedWhenClosed = false
        navigationWindow.titlebarAppearsTransparent = false
        navigationWindow.toolbarStyle = .unified
        navigationWindow.setFrame(NSRect(x: -5000, y: -5000, width: 648, height: 600), display: false)
        navigationWindow.contentView = navigationHost
        navigationWindow.orderFront(nil)
        await pause()
        let beforeHeader = try pixels(navigationHost, headerOnly: true)
        let beforeBody = try pixels(navigationHost, headerOnly: false)
        guard let targetHeader = screenshotHeader else { throw Failure(message: "missing screenshot reference") }
        try check(beforeHeader != targetHeader, "general and screenshot headers differ before navigation")
        guard let navigation = descendants(navigationHost, of: NSOutlineView.self).first(where: { $0.numberOfRows == 6 }) else { throw Failure(message: "native six-row outline not found") }
        navigation.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        navigation.delegate?.outlineViewSelectionDidChange?(Notification(name: NSOutlineView.selectionDidChangeNotification, object: navigation))
        let deadline = Date().addingTimeInterval(3)
        while (navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle != SettingsSection.screenshot.title && Date() < deadline { await pause() }
        try capture(navigationHost, name: "\(language)-navigation-to-screenshot-640pt", out: out)
        try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == SettingsSection.screenshot.title, "native sidebar updates exact screenshot title")
        guard let navigationFrame = navigationWindow.contentView?.superview,
              let nativeTitle = descendants(navigationFrame, of: NSTextField.self).first(where: { $0.accessibilityIdentifier() == "BlinkClipSettingsPaneTitle" }) else { throw Failure(message: "navigation native title missing") }
        try check(nativeTitle.stringValue == SettingsSection.screenshot.title, "native toolbar rendered label receives screenshot title")
        try check(try pixels(navigationHost, headerOnly: false) != beforeBody, "right content changes after native navigation")
        let navigationToolbar = navigationWindow.toolbar
        for (row, section) in SettingsSection.allCases.enumerated() {
            navigation.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            navigation.delegate?.outlineViewSelectionDidChange?(Notification(name: NSOutlineView.selectionDidChangeNotification, object: navigation))
            await pause()
            try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == section.title, "native selection title \(section)")
            try check(navigationWindow.toolbar === navigationToolbar, "navigation retains toolbar")
        }
        navigationWindow.contentView = NSHostingView(rootView: ReplicaSettingsView(state: state, initialTab: 2, permissionModel: model))
        await pause()
        try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == SettingsSection.screenshot.title, "deep-link root replacement installs current title delegate")
        navigationWindow.orderOut(nil)
        navigationWindow.orderFront(nil)
        await pause()
        try check((navigationWindow.toolbar?.delegate as? SettingsSplitViewController)?.paneTitle == SettingsSection.screenshot.title, "reopen preserves title and delegate")
        navigationWindow.orderOut(nil); navigationWindow.contentView = nil; navigationWindow.close()
        try await verifyShortcutRows(store: store, state: state, model: model, out: out, language: language)
        model.stop()
        try check(store.preferences.historyRetentionDays == originalRetention, "viewing pages does not change retention")
        let reopened = try ClipboardStore(directoryURL: fixture)
        try check(reopened.preferences.historyRetentionDays == originalRetention, "persisted retention unchanged")
        let result: [String: Any] = ["passed":true,"assertions":assertions,"language":language,"runID":runID,"fixtureDirectory":fixture.path,"sections":SettingsSection.allCases.map(\.title),"evidence":"Actual ReplicaSettingsView offscreen complete NSWindow theme frame including traffic lights and native NSToolbar; 648x600 window with production SettingsSplitView toolbar delegate path, six pages light/dark top/scrolled header pixel invariance; isolated store and injected permissions. No live user history/TCC requests. Initial-tab navigation plus native NSOutlineView selection and exact native toolbar title checked; right content also changes. No physical mouse clicks."]
        let data = try JSONSerialization.data(withJSONObject: result, options:[.prettyPrinted,.sortedKeys])
        try data.write(to: out.appendingPathComponent("result-\(language).json"))
        print(String(decoding:data,as:UTF8.self))
    }
}
