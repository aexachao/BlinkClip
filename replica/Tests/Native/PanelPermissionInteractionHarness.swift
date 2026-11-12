import AppKit
import Foundation
import BlinkClipCore
import SwiftUI

/// A safe default launcher for visible regression checks. It never constructs the
/// application delegate, reads the user's store, or registers global shortcuts.
@main
struct PanelPermissionInteractionHarness {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = PanelPermissionQADelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class PanelPermissionQADelegate: NSObject, NSApplicationDelegate {
    private var ui: ReplicaUIController!
    private var privatePasteboard: NSPasteboard!
    private var statusItem: NSStatusItem!
    private var controlWindow: NSWindow!
    private var permissionWindow: NSWindow?
    private var timer: Timer?
    private var mouseMonitor: Any?
    private var frames: [[String: Any]] = []
    private var events: [[String: Any]] = []
    private var selfChecks: [String] = []
    private var fakeGranted = false
    private var fakePermissions: PermissionStatusModel!
    private let started = Date()
    private var tick = 0
    private let statusLabel = NSTextField(wrappingLabelWithString: "Preparing isolated QA…")
    private var qaRoot: URL {
        Bundle.main.bundleURL.deletingLastPathComponent()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let directory = qaRoot.appendingPathComponent("isolated-store", isDirectory: true)
            let store = try ClipboardStore(directoryURL: directory)
            if store.items.isEmpty {
                _ = try store.add(ClipboardItem(title: "QA fixture", plainText: "Synthetic QA clipboard content", sourceName: "QA"))
            }
            privatePasteboard = NSPasteboard(name: .init("BlinkClipPanelQA-\(UUID().uuidString)"))
            ui = ReplicaUIController(store: store)
            ui.pasteboard = privatePasteboard
            statusItem = NSStatusBar.system.statusItem(withLength: 34)
            statusItem.button?.title = "PQ"
            statusItem.button?.setAccessibilityLabel("BlinkClip isolated panel QA")
            statusItem.button?.setAccessibilityIdentifier("blinkclip-isolated-panel-qa")
            statusItem.button?.target = self
            statusItem.button?.action = #selector(statusClicked(_:))
            statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            ui.panelToggleButton = statusItem.button
            ui.panelDidShow = { [weak self] in self?.record("panel-did-show") }
            ui.panelWillClose = { [weak self] _ in self?.record("panel-will-close") }
            fakePermissions = PermissionStatusModel(
                readAccessibility: { [weak self] in self?.fakeGranted ?? false },
                readPostEvents: { [weak self] in self?.fakeGranted ?? false },
                readScreenRecording: { [weak self] in self?.fakeGranted ?? false },
                requestScreenAccess: {}, openScreenSettings: {}, requestAccessibilityAccess: {})
            makeControls()
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]) { [weak self] event in
                MainActor.assumeIsolated { self?.record("mouse-\(event.type.rawValue)") }
                return event
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            NSApp.activate(ignoringOtherApps: true)
            controlWindow.makeKeyAndOrderFront(nil)
            Task { @MainActor [weak self] in await self?.runSelfChecks() }
        } catch {
            write(["passed": false, "error": String(describing: error)], name: "qa-start-error.json")
            NSApp.terminate(nil)
        }
    }

    private func makeControls() {
        controlWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
        controlWindow.title = "BlinkClip isolated QA — \(Locale.preferredLanguages.first ?? "?")"
        controlWindow.isReleasedWhenClosed = false
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        let header = NSTextField(wrappingLabelWithString: "Synthetic fixtures only. Use the PQ menu-bar button to test panel toggling. Permission preview buttons do not request system access.")
        stack.addArrangedSubview(header)
        statusLabel.setAccessibilityIdentifier("qa-panel-status")
        stack.addArrangedSubview(statusLabel)
        for (title, action) in [
            ("Show panel", #selector(showPanel)),
            ("Hide panel", #selector(hidePanel)),
            ("Permission preview: red", #selector(showDenied)),
            ("Permission preview: green", #selector(showGranted)),
            ("Open actual Settings (isolated store)", #selector(showSettings)),
            ("Quit QA / next language", #selector(quitQA))
        ] {
            let button = NSButton(title: title, target: self, action: action)
            button.setAccessibilityIdentifier("qa-" + title)
            stack.addArrangedSubview(button)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        controlWindow.contentView = content
        controlWindow.center()
    }

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            record("status-right-action")
            let menu = NSMenu()
            let open = NSMenuItem(title: "Open QA panel", action: #selector(showPanel), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            let close = NSMenuItem(title: "Close QA panel", action: #selector(hidePanel), keyEquivalent: "")
            close.target = self
            menu.addItem(close)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            record("status-left-action-before")
            ui.togglePanel()
            record("status-left-action-after")
        }
    }

    @objc private func showPanel() { record("control-show"); ui.showPanel() }
    @objc private func hidePanel() { record("control-hide"); ui.hidePanel() }
    @objc private func showSettings() { record("control-settings"); ui.showSettings() }
    @objc private func showDenied() { fakeGranted = false; showPermissions() }
    @objc private func showGranted() { fakeGranted = true; showPermissions() }
    @objc private func quitQA() { record("quit"); flush(); NSApp.terminate(nil) }

    private func showPermissions() {
        ui.hidePanel()
        fakePermissions.refresh()
        if permissionWindow == nil {
            permissionWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 450),
                                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
            permissionWindow?.title = "QA permission preview — \(Locale.preferredLanguages.first ?? "?")"
            permissionWindow?.isReleasedWhenClosed = false
        }
        // Every permission action on this model is a no-op spy. Continue remains
        // interactive so the actual production button can be checked safely.
        permissionWindow?.contentView = NSHostingView(rootView:
            PermissionGuideContent(complete: { [weak self] in
                self?.record("permission-guide-continue")
                self?.permissionWindow?.close()
            }, statusModel: fakePermissions))
        permissionWindow?.center()
        permissionWindow?.makeKeyAndOrderFront(nil)
        record(fakeGranted ? "permissions-green" : "permissions-red")
    }

    private func record(_ name: String) {
        guard ui != nil else { return }
        events.append(["t": Date().timeIntervalSince(started), "name": name,
                       "ordered": ui.isPanelOrderedVisible, "visible": ui.isPanelVisible,
                       "contentY": ui.panel.contentView?.frame.origin.y ?? 0])
        if events.count > 400 { events.removeFirst(events.count - 400) }
    }

    private func sample() {
        guard ui != nil else { return }
        frames.append(["t": Date().timeIntervalSince(started), "ordered": ui.isPanelOrderedVisible,
                       "visible": ui.isPanelVisible, "contentY": ui.panel.contentView?.frame.origin.y ?? 0])
        if frames.count > 1800 { frames.removeFirst(frames.count - 1800) }
        tick += 1
        if tick % 15 == 0 { flush() }
        if FileManager.default.fileExists(atPath: qaRoot.appendingPathComponent("finish").path) { quitQA() }
    }

    private func flush() {
        guard ui != nil else { return }
        var rectangle: [String: CGFloat] = [:]
        if let button = statusItem.button, let window = button.window {
            let r = window.convertToScreen(button.convert(button.bounds, to: nil))
            rectangle = ["x": r.minX, "y": r.minY, "width": r.width, "height": r.height]
        }
        statusLabel.stringValue = "Panel ordered: \(ui.isPanelOrderedVisible), visible: \(ui.isPanelVisible); private fixture"
        write(["pid": ProcessInfo.processInfo.processIdentifier,
               "language": Locale.preferredLanguages.first ?? "?",
               "bundleID": Bundle.main.bundleIdentifier ?? "?",
               "store": ui.store.directoryURL.path,
               "privatePasteboard": privatePasteboard.name.rawValue,
               "ordered": ui.isPanelOrderedVisible, "visible": ui.isPanelVisible,
               "contentY": ui.panel.contentView?.frame.origin.y ?? 0,
               "windowClear": ui.panel.backgroundColor.alphaComponent == 0,
               "statusButtonRect": rectangle, "selfChecks": selfChecks,
               "fakePermissionsGranted": fakeGranted, "events": events, "frames": frames], name: "qa-state.json")
    }

    private func write(_ object: [String: Any], name: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: qaRoot.appendingPathComponent(name), options: .atomic)
    }

    private func awaitState(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try? await Task.sleep(nanoseconds: 10_000_000) }
        return condition()
    }

    private func runSelfChecks() async {
        ui.showPanel()
        let shown = await awaitState { ui.isPanelVisible && ui.isPanelOrderedVisible }
        if shown { selfChecks.append("production-show-completed") }
        if ui.panel.backgroundColor.alphaComponent == 0 { selfChecks.append("production-window-transparent") }
        ui.hidePanel()
        if await awaitState({ !ui.isPanelVisible && !ui.isPanelOrderedVisible }) { selfChecks.append("production-hide-completed") }
        ui.showPanel()
        try? await Task.sleep(nanoseconds: 30_000_000)
        ui.hidePanel()
        try? await Task.sleep(nanoseconds: 30_000_000)
        ui.showPanel()
        if await awaitState({ ui.isPanelVisible && ui.isPanelOrderedVisible }) {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if ui.isPanelVisible && ui.isPanelOrderedVisible { selfChecks.append("reopen-ignores-stale-hide-completion") }
        }
        ui.togglePanel()
        if await awaitState({ !ui.isPanelVisible && !ui.isPanelOrderedVisible }) { selfChecks.append("toggle-closes") }
        ui.togglePanel()
        if await awaitState({ ui.isPanelVisible && ui.isPanelOrderedVisible }) { selfChecks.append("toggle-opens") }
        ui.hidePanel()
        _ = await awaitState { !ui.isPanelOrderedVisible }
        write(["passed": selfChecks.count == 6, "checks": selfChecks,
               "scope": "Production controller show/hide/reopen. No synthetic status clicks or real TCC requests."],
              name: "self-checks-\(Locale.preferredLanguages.first ?? "unknown").json")
        record("ready-for-cua")
        flush()
    }

    func applicationWillTerminate(_ notification: Notification) {
        flush()
        timer?.invalidate()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        privatePasteboard?.releaseGlobally()
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
    }
}
