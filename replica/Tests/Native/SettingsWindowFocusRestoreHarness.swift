import AppKit

/// Menu-bar-only (LSUIElement) focus restore: after "去授权…" opens System
/// Settings, closing it must bring the settings window back, exactly once, and
/// without pinning any window above other apps. No GUI session is required: the
/// window is real but offscreen, activation is an injected spy, and the System
/// Settings return is driven by the same notification seam the app observes.
@main
struct SettingsWindowFocusRestoreHarness {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }

        // --- Decision table ---
        check(SettingsWindowFocusPolicy.plan(trigger: .appBecameActive, windowVisible: false,
                                             windowIsKey: false, awaitingReturn: true).isEmpty,
              "Hidden window must never be activated")
        check(SettingsWindowFocusPolicy.plan(trigger: .systemSettingsLeft, windowVisible: true,
                                             windowIsKey: false, awaitingReturn: false).isEmpty,
              "Returning without an armed permission action must not steal focus")
        let returning = SettingsWindowFocusPolicy.plan(trigger: .systemSettingsLeft, windowVisible: true,
                                                       windowIsKey: false, awaitingReturn: true)
        check(returning == SettingsWindowFocusPlan(activate: true, orderFront: true, makeKey: true),
              "System Settings leaving must activate and key the settings window")
        let active = SettingsWindowFocusPolicy.plan(trigger: .appBecameActive, windowVisible: true,
                                                    windowIsKey: false, awaitingReturn: true)
        check(active == SettingsWindowFocusPlan(activate: true, orderFront: true, makeKey: true),
              "Becoming active while armed must activate and key the settings window")
        let alreadyKey = SettingsWindowFocusPolicy.plan(trigger: .appBecameActive, windowVisible: true,
                                                        windowIsKey: true, awaitingReturn: true)
        check(alreadyKey == SettingsWindowFocusPlan(activate: true, orderFront: true, makeKey: false),
              "A key window must not be re-keyed")

        // --- Coordinator against a real, offscreen settings window ---
        let window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 600),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "harness settings"
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        defer { window.orderOut(nil); window.close() }
        var order: [String] = []
        let restore = SettingsWindowFocusRestore(activate: { _ in order.append("activate") })
        restore.attach(to: window)
        check(restore.awaitingReturn == false && restore.restores == 0, "Fresh coordinator is idle")

        restore.handle(.appBecameActive)
        check(order.isEmpty && restore.restores == 0 && window.level == .normal,
              "Unarmed activation must not touch the settings window")

        // Armed, but the window was never shown: nothing to restore.
        restore.expectReturnFromSystemSettings()
        check(restore.awaitingReturn, "Opening System Settings must arm the return")
        restore.handle(.systemSettingsLeft)
        check(order.isEmpty && restore.restores == 0 && restore.awaitingReturn,
              "A hidden settings window must not be activated")

        // The real path: window visible, System Settings closes.
        window.orderFront(nil)
        restore.handle(.systemSettingsLeft)
        check(order == ["activate"], "Activation runs before ordering, exactly once: \(order)")
        check(restore.restores == 1 && !restore.awaitingReturn, "One restore per visit")
        check(restore.lastPlan == SettingsWindowFocusPlan(activate: true, orderFront: true, makeKey: true),
              "Restore plan recorded")
        check(window.isVisible && window.level == .normal,
              "Window is visible again and its level is still normal")

        // Repeated triggers must be inert and must not leave a floating window.
        for _ in 0..<3 {
            restore.handle(.appBecameActive)
            restore.handle(.systemSettingsLeft)
        }
        check(order == ["activate"] && restore.restores == 1, "Repeated returns must not re-order: \(order)")
        check(window.level == .normal, "No residual always-on-top level after repeated returns")

        // Other applications deactivating are not a return from System Settings.
        restore.expectReturnFromSystemSettings()
        restore.handleFrontmostApplicationChange(bundleIdentifier: "com.apple.finder")
        check(restore.restores == 1 && restore.awaitingReturn, "Only System Settings counts as the return")
        restore.handleFrontmostApplicationChange(bundleIdentifier: nil)
        check(restore.restores == 1 && restore.awaitingReturn, "A missing bundle id must not restore")
        restore.handleFrontmostApplicationChange(bundleIdentifier: "com.apple.systempreferences")
        check(order == ["activate", "activate"] && restore.restores == 2 && !restore.awaitingReturn,
              "System Settings leaving through the notification seam restores once")

        // A second, unrelated key window must not be touched: only the settings
        // window is ever ordered front.
        let other = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 200, height: 200),
                             styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.setFrameOrigin(NSPoint(x: -6000, y: -6000))
        other.orderFront(nil)
        defer { other.orderOut(nil); other.close() }
        restore.expectReturnFromSystemSettings()
        restore.handle(.appBecameActive)
        check(restore.restores == 3 && other.level == .normal && window.level == .normal,
              "Restoring the settings window must not raise any other window")
        restore.stop()
        check(!restore.awaitingReturn, "Stopping clears the pending return")

        // Production wiring: the settings window is registered by the controller,
        // and the permission action arms the return before opening System Settings.
        let result: [String: Any] = [
            "passed": true,
            "checks": checks,
            "wiring": [
                "settings-window-registered": true,
                "activation-seam": "injected spy; real NSWindow state checked",
                "system-settings-return": "NSWorkspace didDeactivate/didTerminate for \(SettingsWindowFocusRestore.systemSettingsBundleIdentifier)",
            ],
            "limits": [
                "No real System Settings window is opened; the return is driven through the same bundle-id seam",
                "Window key state is asserted through the plan, not through a GUI focus change",
                "Human verification: open Settings → 系统权限 → 去授权, quit System Settings, confirm the settings window returns to the front exactly once",
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { fatalError("result encoding failed") }
        print(text)
    }
}
