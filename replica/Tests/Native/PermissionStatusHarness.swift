import AppKit
import Combine
import Foundation
import BlinkClipCore
import SwiftUI

@main
struct PermissionStatusHarness {
    @MainActor static func main() async throws {
        if let status = PermissionProbeCommand.handleIfRequested() { exit(status) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        app.appearance = NSAppearance(named: .aqua)
        let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        func settle(_ model: PermissionStatusModel) async {
            let deadline = Date().addingTimeInterval(3)
            while model.isRefreshing || model.isRequestingScreen, Date() < deadline { try? await Task.sleep(nanoseconds: 5_000_000) }
            check(!model.isRefreshing && !model.isRequestingScreen, "Status refresh must be bounded")
        }
        var policy = PermissionPromptPolicy()
        check(policy.shouldRemind(canPostEvents: false), "First denial must remind")
        check(!policy.shouldRemind(canPostEvents: false), "Repeated denial must not remind")
        check(!policy.shouldRemind(canPostEvents: true), "Grant must not remind")
        check(policy.shouldRemind(canPostEvents: false), "New revocation must allow a reminder")
        let suite = "blinkclip.permission-harness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = out.appendingPathComponent("data-a")
        let second = out.appendingPathComponent("data-b")
        check(PermissionGuidePersistence.shouldShow(directory: first, defaults: defaults), "Fresh store must show guide")
        PermissionGuidePersistence.complete(directory: first, defaults: defaults)
        check(!PermissionGuidePersistence.shouldShow(directory: first, defaults: defaults), "Completed guide must not return")
        check(PermissionGuidePersistence.shouldShow(directory: second, defaults: defaults), "Store namespaces must remain isolated")
        var ax = false
        var post = false
        var screen = false
        var requestedScreen = 0
        var openedScreen = 0
        var requestedAccessibility = 0
        let model = PermissionStatusModel(readAccessibility: { ax }, readPostEvents: { post },
            readScreenRecording: { screen }, requestScreenAccess: { requestedScreen += 1 },
            openScreenSettings: { openedScreen += 1 }, requestAccessibilityAccess: { requestedAccessibility += 1 })
        model.start()
        model.refresh()
        await settle(model)
        check(requestedScreen == 0 && openedScreen == 0 && requestedAccessibility == 0, "Observation must never request access")
        model.requestAccessibility()
        await settle(model)
        check(requestedAccessibility == 1, "Explicit accessibility action must request once")
        check(model.requestedSystemSettings, "A 「前往授权…」 press must surface the remove-and-re-add steps while denied")
        check(!model.accessibilityReady && !model.screenRecording, "Missing permissions state")
        post = true
        model.refresh()
        await settle(model)
        check(!model.accessibilityReady && model.postEvents, "AX/post mismatch must remain visible")
        ax = true
        screen = true
        model.refresh()
        await settle(model)
        check(model.accessibilityReady && model.screenRecording, "Live grants must refresh")
        model.requestScreenRecording()
        await settle(model)
        check(requestedScreen == 0 && openedScreen == 1, "Granted screen must only open settings")
        screen = false
        model.requestScreenRecording()
        await settle(model)
        check(requestedScreen == 1 && openedScreen == 2, "Explicit denied-screen action must request once")
        ax = false
        post = false
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: app)
        await settle(model)
        check(!model.accessibility && !model.postEvents, "Return-to-app notification must refresh revocation")
        ax = true
        post = true
        try await Task.sleep(nanoseconds: 3_200_000_000)
        await settle(model)
        check(model.accessibilityReady, "Visible periodic observation must refresh grants")
        model.stop()
        ax = false
        post = false
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: app)
        check(model.accessibilityReady, "Stopped view must remove notification observers")
        // AX authorization must stay green even when event posting is unavailable.
        ax = true; post = false
        model.refresh()
        await settle(model)
        check(model.accessibilityReady && !model.postEvents, "AX grant must not be conflated with event posting")
        var publications = 0
        let stableObservation = model.objectWillChange.sink { publications += 1 }
        model.refresh()
        await settle(model)
        check(publications == 0, "Unchanged polling must not publish view updates")
        stableObservation.cancel()

        let denied = PermissionStatusSnapshot(accessibility: false, postEvents: false, screenRecording: false)
        let granted = PermissionStatusSnapshot(accessibility: true, postEvents: true, screenRecording: true)
        var localStatus = denied, freshStatus = granted
        let stale = PermissionStatusModel(readStatus: {
            PermissionStatusReading(currentProcess: localStatus, freshProcess: freshStatus, checkFailed: false)
        })
        await settle(stale)
        check(stale.accessibility && stale.screenRecording && stale.needsRestart, "Fresh grant with stale process must require restart")
        localStatus = granted; freshStatus = denied
        stale.refresh()
        await settle(stale)
        check(!stale.accessibility && !stale.screenRecording && !stale.needsRestart,
              "Fresh revocation must replace a stale granted current process")
        let unknown = PermissionStatusModel(readStatus: {
            PermissionStatusReading(currentProcess: granted, freshProcess: nil, checkFailed: true)
        })
        await settle(unknown)
        check(unknown.statusUnknown && unknown.checkFailed && !unknown.hasChecked,
              "An initial failure must be unknown, not a confirmed denial or grant")
        var failFresh = false
        let neutral = PermissionStatusModel(readStatus: {
            PermissionStatusReading(currentProcess: denied, freshProcess: failFresh ? nil : granted, checkFailed: failFresh)
        })
        await settle(neutral)
        failFresh = true
        neutral.refresh()
        await settle(neutral)
        check(neutral.accessibility && neutral.screenRecording && neutral.statusUnknown && neutral.checkFailed,
              "Failed fresh check must preserve last grant but present neutral state")
        var concurrent = 0, peakConcurrent = 0, deliveries = 0
        let slow = PermissionStatusModel(readStatus: {
            concurrent += 1; peakConcurrent = max(peakConcurrent, concurrent)
            try? await Task.sleep(nanoseconds: 150_000_000)
            concurrent -= 1; deliveries += 1
            return PermissionStatusReading(currentProcess: granted, freshProcess: nil, checkFailed: false)
        })
        for _ in 0..<20 { slow.refresh() }
        await settle(slow)
        check(peakConcurrent == 1 && deliveries == 1, "Refreshes must not overlap")
        slow.refresh(); slow.stop()
        try await Task.sleep(nanoseconds: 180_000_000)
        check(!slow.isRefreshing && slow.accessibility, "Stopped refresh must not publish a late result")

        let appBundleID = "com.chrisli.blinkclip"
        for name in ["BlinkClip", "BlinkClip"] {
            check(PermissionStatusProbe.isAppExecutable(bundleIdentifier: appBundleID, executableName: name),
                  "Current and legacy app executable must support fresh permission probes")
            check(!PermissionStatusProbe.isAppExecutable(bundleIdentifier: "local.other.app", executableName: name),
                  "Executable name must not bypass the bundle identity guard")
        }
        for name: String? in [nil, "harness", "BlinkClipHelper", "blinkclip-mcp", "blinkclip", "BlinkClip.other"] {
            check(!PermissionStatusProbe.isAppExecutable(bundleIdentifier: appBundleID, executableName: name),
                  "Only exact app executable names may launch a fresh permission probe")
        }
        check(!PermissionStatusProbe.isAppExecutable(bundleIdentifier: nil, executableName: "BlinkClip"),
              "Missing bundle identity must not launch a fresh permission probe")

        if let identity = PermissionProbeIdentity.current() {
            let encoded = try JSONEncoder().encode(PermissionProbeReply(identity: identity, status: granted))
            check(try PermissionStatusProbe.validate(encoded, expected: identity) == granted, "Validated probe reply must retain all fields")
            let wrong = PermissionProbeIdentity(executablePath: identity.executablePath + ".other", bundleIdentifier: identity.bundleIdentifier, codeHash: identity.codeHash)
            do { _ = try PermissionStatusProbe.validate(encoded, expected: wrong); check(false, "Wrong executable accepted") }
            catch { checks += 1 }
            let otherCode = PermissionProbeIdentity(executablePath: identity.executablePath, bundleIdentifier: identity.bundleIdentifier, codeHash: "different")
            do { _ = try PermissionStatusProbe.validate(encoded, expected: otherCode); check(false, "Wrong code identity accepted") }
            catch { checks += 1 }
            let otherBundle = PermissionProbeIdentity(executablePath: identity.executablePath, bundleIdentifier: "local.other.app", codeHash: identity.codeHash)
            do { _ = try PermissionStatusProbe.validate(encoded, expected: otherBundle); check(false, "Wrong bundle identity accepted") }
            catch { checks += 1 }
            let beforeProbe = Date()
            _ = try await PermissionStatusProbe.run(executable: URL(fileURLWithPath: identity.executablePath), expected: identity)
            check(Date().timeIntervalSince(beforeProbe) < 3, "Same-executable probe must exit without UI/store startup")
            do {
                _ = try await PermissionStatusProbe.run(executable: URL(fileURLWithPath: "/bin/sleep"), expected: identity,
                                                       timeout: 0.15, arguments: ["5"])
                check(false, "Hung child accepted")
            } catch { checks += 1 }
            let cancelled = Task {
                try await PermissionStatusProbe.run(executable: URL(fileURLWithPath: "/bin/sleep"), expected: identity,
                                                   arguments: ["5"])
            }
            try await Task.sleep(nanoseconds: 30_000_000)
            cancelled.cancel()
            do { _ = try await cancelled.value; check(false, "Cancelled probe accepted") }
            catch { checks += 1 }
        } else { check(false, "Signed test process identity unavailable") }
        // --- Stale TCC requirement: ticked in System Settings, this build denied ---
        let ledgerSuite = "blinkclip.permission-ledger.\(UUID().uuidString)"
        let ledger = UserDefaults(suiteName: ledgerSuite)!
        defer { ledger.removePersistentDomain(forName: ledgerSuite) }
        // The permission page is trilingual now: expectations come from the one
        // shared resolver instead of assuming "any zh is Simplified".
        let permissionLanguage = SettingsLanguage.resolved()
        func permissionCopy(_ hans: String, _ hant: String, _ en: String) -> String {
            SettingsStrings.trilingual(hans, hant, en, language: permissionLanguage)
        }
        let newBuild = PermissionProbeIdentity(executablePath: "/Applications/BlinkClip.app/Contents/MacOS/BlinkClip",
                                               bundleIdentifier: "com.chrisli.blinkclip", codeHash: "cdhash-new",
                                               teamIdentifier: "4NJM425J3B")
        let oldBuild = PermissionProbeIdentity(executablePath: "/Applications/BlinkClip.app/Contents/MacOS/BlinkClip",
                                               bundleIdentifier: "com.chrisli.blinkclip", codeHash: "cdhash-old",
                                               teamIdentifier: nil)
        check(!PermissionGrantLedger.requirementMismatch(isTrusted: false, identity: newBuild, defaults: ledger),
              "Without a recorded grant a denial cannot be called a requirement mismatch")
        check(PermissionGrantLedger.memory(defaults: ledger) == nil, "Grant ledger starts empty")
        PermissionGrantLedger.recordGrant(identity: oldBuild, shortVersion: "1.0.9", defaults: ledger)
        check(PermissionGrantLedger.memory(defaults: ledger)?.shortVersion == "1.0.9",
              "Grant record keeps the build that owned the grant")
        check(!PermissionGrantLedger.requirementMismatch(isTrusted: true, identity: oldBuild, defaults: ledger),
              "A live grant is never a mismatch")
        check(PermissionGrantLedger.requirementMismatch(isTrusted: false, identity: newBuild, defaults: ledger),
              "Denied after the signing identity changed must be reported as a stale requirement")
        check(!PermissionGrantLedger.requirementMismatch(isTrusted: false, identity: oldBuild, defaults: ledger),
              "Denied with the same identity is a revocation, not a stale requirement")
        let deniedReading = PermissionStatusProbe.recorded(
            PermissionStatusReading(currentProcess: denied, freshProcess: nil, checkFailed: false),
            identity: newBuild, defaults: ledger, version: "1.0.10")
        check(deniedReading.requirementMismatch, "The probe must surface the stale requirement")
        _ = PermissionStatusProbe.recorded(
            PermissionStatusReading(currentProcess: denied, freshProcess: nil, checkFailed: true),
            identity: newBuild, defaults: ledger, version: "1.0.11")
        check(PermissionGrantLedger.memory(defaults: ledger)?.codeHash == "cdhash-old",
              "A failed check must not overwrite the recorded grant")
        let grantedReading = PermissionStatusProbe.recorded(
            PermissionStatusReading(currentProcess: granted, freshProcess: nil, checkFailed: false),
            identity: newBuild, defaults: ledger, version: "1.0.10")
        check(!grantedReading.requirementMismatch, "A new grant clears the mismatch")
        check(PermissionGrantLedger.memory(defaults: ledger)?.teamIdentifier == "4NJM425J3B",
              "Grant ledger records the Developer ID team")
        var liveMismatch = false
        let mismatchModel = PermissionStatusModel(readStatus: {
            PermissionStatusReading(currentProcess: denied, freshProcess: nil, checkFailed: false,
                                    requirementMismatch: liveMismatch)
        })
        await settle(mismatchModel)
        check(!mismatchModel.requirementMismatch, "No stale requirement before the flag is set")
        mismatchModel.start()
        liveMismatch = true
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: app)
        await settle(mismatchModel)
        check(mismatchModel.requirementMismatch, "Returning to the app must refresh the stale-requirement hint")
        // The row title already names the capability; the status line is only
        // granted / not granted — no colon, no repeated capability name.
        let notGranted = permissionCopy("未授权", "未授權", "Not granted")
        let grantedCopy = permissionCopy("已授权", "已授權", "Granted")
        check(mismatchModel.accessibilityStatus == notGranted,
              "Denied Accessibility status is exactly 未授权 / Not granted")
        check(!mismatchModel.accessibilityStatus.contains(":") && !mismatchModel.accessibilityStatus.contains("："),
              "The status line carries no colon")
        check(!mismatchModel.accessibilityStatus.contains(permissionCopy("辅助功能", "輔助功能", "Accessibility")),
              "The status line does not repeat the capability name")
        check(mismatchModel.screenRecordingStatus == notGranted,
              "Denied Screen Recording status is exactly 未授权 / Not granted")
        check(!mismatchModel.screenRecordingStatus.contains(permissionCopy("屏幕录制", "螢幕錄製", "Screen Recording")),
              "Screen Recording status does not repeat the capability name")
        // J1-e: event posting is reported inside the Accessibility row, so a
        // mismatch between the two is one inline hint, never a second row.
        check(mismatchModel.postEventsHint == nil,
              "A denied Accessibility row shows no event-posting hint")
        var axOnly = true
        let mergedRow = PermissionStatusModel(readAccessibility: { axOnly }, readPostEvents: { false },
            readScreenRecording: { true }, requestScreenAccess: {}, openScreenSettings: {},
            requestAccessibilityAccess: {})
        await settle(mergedRow)
        check(mergedRow.accessibilityStatus == grantedCopy,
              "Granted Accessibility status is exactly 已授权 / Granted")
        check(mergedRow.postEventsHint?.contains(permissionCopy("辅助功能", "輔助功能", "Accessibility")) == true,
              "AX granted + event posting denied surfaces one inline hint on the Accessibility row")
        mergedRow.stop()
        mismatchModel.stop()
        let controllerDirectory = out.appendingPathComponent("guide-controller-close")
        let completionKey = PermissionGuidePersistence.key(for: controllerDirectory)
        UserDefaults.standard.removeObject(forKey: completionKey)
        defer { UserDefaults.standard.removeObject(forKey: completionKey) }
        let guide = PermissionGuideWindowController(directory: controllerDirectory)
        check(PermissionGuidePersistence.shouldShow(directory: controllerDirectory), "Unseen guide must remain incomplete")
        guide.close()
        check(!PermissionGuidePersistence.shouldShow(directory: controllerDirectory), "Closing guide must persist completion")
        let lifecycle = PermissionStatusModel(readAccessibility: { ax }, readPostEvents: { post },
            readScreenRecording: { screen }, requestScreenAccess: {}, openScreenSettings: {}, requestAccessibilityAccess: {})
        let lifecycleWindow = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 520, height: 450),
                                       styleMask: [.titled, .closable], backing: .buffered, defer: false)
        lifecycleWindow.isReleasedWhenClosed = false
        lifecycleWindow.contentView = NSHostingView(rootView: PermissionStatusView(model: lifecycle))
        lifecycleWindow.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 180_000_000)
        await settle(lifecycle)
        check(lifecycle.isObserving, "Visible production permission view must start monitoring")
        lifecycleWindow.close()
        try await Task.sleep(nanoseconds: 50_000_000)
        check(!lifecycle.isObserving, "Closing real host window must stop monitoring")
        ax = false
        lifecycleWindow.makeKeyAndOrderFront(nil)
        try await Task.sleep(nanoseconds: 180_000_000)
        await settle(lifecycle)
        check(lifecycle.isObserving && !lifecycle.accessibility, "Reopening the same retained host must restart and refresh monitoring")
        lifecycleWindow.close()
        for axState in [false, true] {
            for postState in [false, true] {
                var calls: [String] = []
                AccessibilityRequestAction.perform(isAXTrusted: axState, canPostEvents: postState,
                    requestAX: { calls.append("ax") }, requestPostEvents: { calls.append("post") },
                    openSettings: { _ in calls.append("settings") })
                check(calls == ((!axState ? ["ax"] : (!postState ? ["post"] : [])) + ["settings"]),
                      "Explicit request branch must target only missing capability")
            }
        }
        model.stop()
        let language = Locale.preferredLanguages.first?.hasPrefix("zh") == true ? "zh" : "en"
        for granted in [false, true] {
            let preview = PermissionStatusModel(readAccessibility: { granted }, readPostEvents: { granted },
                readScreenRecording: { granted }, requestScreenAccess: {}, openScreenSettings: {}, requestAccessibilityAccess: {})
            await settle(preview)
            let host = NSHostingView(rootView: PermissionGuideContent(complete: {}, statusModel: preview))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 450),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
            window.orderFront(nil)
            try await Task.sleep(nanoseconds: 200_000_000)
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Missing bitmap") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = bitmap.representation(using: .png, properties: [:])!
            try png.write(to: out.appendingPathComponent("guide-\(language)-\(granted ? "granted" : "denied").png"))
            check(host.bounds.width == 520 && host.bounds.height == 450, "Guide must fit its viewport")
            preview.stop()
            window.orderOut(nil)
        }
        // Fresh offscreen renders of the permission page itself, so the layout
        // changes can be checked without a real System Settings round trip:
        // one Accessibility row (event posting merged in), one Screen Recording
        // row, no removed captions, a divider above the refresh button.
        for (tag, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            app.appearance = NSAppearance(named: appearanceName)
            for state in ["granted", "denied", "post-gap"] {
                let accessibility = state != "denied"
                let preview = PermissionStatusModel(
                    readAccessibility: { accessibility },
                    readPostEvents: { state == "granted" },
                    readScreenRecording: { accessibility },
                    requestScreenAccess: {}, openScreenSettings: {}, requestAccessibilityAccess: {})
                await settle(preview)
                let host = NSHostingView(rootView: PermissionStatusView(model: preview)
                    .padding(18)
                    .frame(width: 520, alignment: .leading)
                    .background(Color(nsColor: .windowBackgroundColor)))
                host.frame = NSRect(x: 0, y: 0, width: 520, height: 340)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
                window.orderFront(nil)
                try await Task.sleep(nanoseconds: 200_000_000)
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("Missing bitmap") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = bitmap.representation(using: .png, properties: [:])!
                try png.write(to: out.appendingPathComponent("permission-page-\(tag)-\(state).png"))
                preview.stop()
                window.orderOut(nil)
            }
        }
        app.appearance = NSAppearance(named: .aqua)
        let result: [String: Any] = ["passed": true, "checks": checks, "language": language,
            "limits": ["Permission decision assertions use injected states; guide controller may read system status without requesting access",
                       "No TCC request, real-store launch, or installed app modification",
                       "Offscreen host close/reopen and SwiftUI rendering; real OS grant/revocation remains manual",
                       "Permission page renders use injected grant states in a 520x340 offscreen host, not a real System Settings round trip",
                       "Same-executable CLI and signature checks are structural; launch responsibility still requires installed-app validation"]]
        let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: out.appendingPathComponent("permission-\(language).json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
