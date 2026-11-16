import AppKit
import ObjectiveC
@testable import BlinkClipCapture

private final class SnapshotRecorder: ScreenSnapshotProviding {
    var requests: [Set<CGWindowID>] = []
    var handlers: [(ScreenSnapshotEvent) -> Void] = []
    var cancelled = 0
    func prewarm() {}
    func capture(targets: [ScreenSnapshotTarget], eventHandler: @escaping (ScreenSnapshotEvent) -> Void) -> ScreenSnapshotCancellation {
        preconditionFailure("Production must call the explicit exclusion overload")
    }
    func capture(targets: [ScreenSnapshotTarget], excludingWindowIDs: Set<CGWindowID>, eventHandler: @escaping (ScreenSnapshotEvent) -> Void) -> ScreenSnapshotCancellation {
        requests.append(excludingWindowIDs)
        handlers.append(eventHandler)
        return { [weak self] in self?.cancelled += 1 }
    }
}

/// Drives the real `SystemCursorHider` without touching the user's cursor:
/// the counters and the read-back are what production sees.
private final class CursorDriverState {
    var hides = 0
    var unhides = 0
    var probeAvailable = true
    var cursorVisible = true
    /// When false the hide is silently ignored (what happens when the app does
    /// not own the foreground), so a visible read-back proves the failure.
    var hideIsHonoured = true
    /// AppKit drops cursor calls from a background app. This is the injection
    /// point for the activation timing (production reads `NSApp.isActive`).
    var appActive = true
    /// Drop the effect of this many `unhide()` calls, as AppKit does when the
    /// app is in the background — the counter moves, the cursor stays hidden.
    var swallowUnhides = 0
    /// The body the hider is waiting to run on the next activation.
    var activationBody: (() -> Void)?
    var watchdogDelay: TimeInterval = 0.5
    var logs: [String] = []

    func makeHider() -> SystemCursorHider {
        SystemCursorHider(
            drivers: .init(
                hide: { [weak self] in
                    self?.hides += 1
                    if self?.hideIsHonoured ?? true {
                        self?.cursorVisible = false
                    }
                },
                unhide: { [weak self] in
                    guard let self else { return }
                    self.unhides += 1
                    if self.swallowUnhides > 0 {
                        self.swallowUnhides -= 1
                    } else {
                        self.cursorVisible = true
                    }
                },
                isCursorVisible: { [weak self] in
                    guard let self, self.probeAvailable else { return nil }
                    return self.cursorVisible
                },
                isAppActive: { [weak self] in self?.appActive ?? true },
                waitForActivation: { [weak self] body in
                    guard let self else { return {} }
                    self.activationBody = body
                    return { [weak self] in self?.activationBody = nil }
                }
            ),
            watchdogDelay: watchdogDelay,
            log: { [weak self] message in self?.logs.append(message) }
        )
    }

    /// Delivers the activation the hider is waiting for.
    func fireActivation() {
        let body = activationBody
        activationBody = nil
        body?()
    }
}

/// Reads the crosshair geometry out of the live view/layer tree — the same
/// numbers the window server receives, without a second copy of the layout
/// maths. The overlay installs exactly three crosshair subviews: the horizontal
/// guide, the vertical guide, then the pointer on top. They are view-backed
/// layers, so their view frames are their layer frames.
private struct CrosshairLayerGeometry {
    let horizontalBand: NSView?
    let verticalBand: NSView?
    let pointer: NSView?
    let subviewCount: Int

    init(view: SelectionView) {
        let subviews = view.subviews
        subviewCount = subviews.count
        horizontalBand = subviews.count == 3 ? subviews[0] : nil
        verticalBand = subviews.count == 3 ? subviews[1] : nil
        pointer = subviews.count == 3 ? subviews[2] : nil
    }

    /// Where the two strands cross, in view coordinates.
    var crossing: NSPoint? {
        guard let horizontalBand, let verticalBand else { return nil }
        return NSPoint(x: verticalBand.frame.midX, y: horizontalBand.frame.midY)
    }

    var pointerCentre: NSPoint? {
        pointer.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) }
    }
}

@main struct CaptureChromeExclusionHarness {

    @MainActor static func main() {
        _ = NSApplication.shared
        // Exercise real production window construction/show calls without
        // placing full-screen selection panels over the user's desktop.
        var fronted: [NSWindow] = []
        let method = class_getInstanceMethod(NSWindow.self, #selector(NSWindow.orderFrontRegardless))!
        let original = method_getImplementation(method)
        let replacement: @convention(block) (NSWindow) -> Void = { fronted.append($0) }
        let replacementIMP = imp_implementationWithBlock(replacement)
        method_setImplementation(method, replacementIMP)
        defer { method_setImplementation(method, original); imp_removeBlock(replacementIMP) }
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        let settings = NSWindow(contentRect: NSRect(x: -3000, y: -3000, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let settingsID = CGWindowID(settings.windowNumber)
        check(settings.windowNumber > 0, "normal target has a native ID")
        for action in [OverlayWindowController.PostCaptureAction.edit, .quickPin, .textRecognition, .copyImageText, .screenshotTranslation] {
            let provider = SnapshotRecorder()
            var completions = 0
            var priorHUD: NSWindow?
            for attempt in 0..<2 {
                fronted.removeAll()
                // Never hide the real cursor in a test run.
                let cursorDriver = CursorDriverState()
                let controller = OverlayWindowController(postCaptureAction: action, snapshotProvider: provider,
                    cursorHider: cursorDriver.makeHider(),
                    windowSnapshotLoader: { _ in .success([]) }, eventTrackingStateProvider: { false },
                    colorSamplerActiveProvider: { false }, modalWindowProvider: { nil },
                    onComplete: { _ in completions += 1 })
                controller.activate()
                check(provider.requests.count == attempt + 1, "one capture request per session")
                let exclusions = provider.requests.last!
                let huds = fronted.filter { $0 is MagnifierLensPanelWindow || $0 is CursorChipWindow }
                check(huds.count == 1, "one HUD instance is presented")
                let hud = huds[0]
                check(hud.windowNumber > 0, "HUD has a native ID")
                check(exclusions.contains(CGWindowID(hud.windowNumber)), "presented HUD was excluded before the asynchronous request")
                check(!exclusions.contains(settingsID), "normal app/settings target stays capturable")
                let overlays = fronted.filter { $0 is OverlayPanel }
                check(!overlays.isEmpty, "selection overlays were presented")
                check(overlays.allSatisfy { exclusions.contains(CGWindowID($0.windowNumber)) }, "selection windows remain excluded")
                check(exclusions.count == overlays.count + 1, "only session-owned selection and HUD windows are excluded")
                if action == .edit || action == .quickPin {
                    check(hud is MagnifierLensPanelWindow, "edit/pin use the same precreated lens")
                } else {
                    check(hud is CursorChipWindow, "other screenshot actions use the same precreated hint")
                }
                if let priorHUD {
                    check(hud !== priorHUD, "retry creates a fresh session HUD")
                    check(!exclusions.contains(CGWindowID(priorHUD.windowNumber)), "retry does not retain the old HUD exclusion")
                }
                priorHUD = hud
                if attempt == 1 {
                    provider.handlers.last?(.finished)
                    check(!controller.isMagnifierLensPanelPresented || hud is MagnifierLensPanelWindow, "snapshot completion preserves the intended HUD type")
                }
                controller.cancel()
                check(provider.cancelled == attempt + 1, "cancel detaches in-flight capture")
                check(controller.isCaptureSessionEnded, "cancel ends the session")
                check(!controller.isMagnifierLensPanelPresented, "cancel releases the lens")
                check(!hud.isVisible, "cancel leaves no visible HUD")
                check(completions == attempt + 1, "cancel completes exactly once")
                controller.cancel()
                check(completions == attempt + 1, "repeated cancellation is harmless")
            }
        }
        for action in [OverlayWindowController.PostCaptureAction.edit, .textRecognition] {
            fronted.removeAll()
            let provider = SnapshotRecorder()
            var blocked = true
            var dismissals = 0
            let cursorDriver = CursorDriverState()
            let controller = OverlayWindowController(postCaptureAction: action, snapshotProvider: provider,
                cursorHider: cursorDriver.makeHider(),
                windowSnapshotLoader: { _ in .success([]) }, eventTrackingStateProvider: { false },
                colorSamplerActiveProvider: { false }, modalWindowProvider: { blocked ? settings : nil },
                modalWindowDismissal: { window in
                    precondition(window === settings); blocked = false; dismissals += 1
                }, onComplete: { _ in })
            controller.activate()
            check(provider.requests.count == 1, "modal path still starts snapshot before presentation")
            check(fronted.isEmpty, "modal path does not prematurely show capture chrome")
            let pendingHUDs = NSApp.windows.filter {
                ($0 is MagnifierLensPanelWindow || $0 is CursorChipWindow) && provider.requests[0].contains(CGWindowID($0.windowNumber))
            }
            check(pendingHUDs.count == 1, "hidden precreated HUD has a stable excluded ID")
            provider.handlers[0](.finished)
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            check(dismissals == 1, "snapshot resolves modal presentation once")
            check(fronted.filter { $0 === pendingHUDs[0] }.count == 1, "deferred presentation shows the exact excluded HUD once")
            check(!provider.requests[0].contains(settingsID), "modal settings window remains a valid screenshot target")
            controller.cancel()
            check(controller.isCaptureSessionEnded && !pendingHUDs[0].isVisible, "deferred session cleans up")
        }
        fronted.removeAll()
        let recordingProvider = SnapshotRecorder()
        let recordingCursorDriver = CursorDriverState()
        let recording = OverlayWindowController(postCaptureAction: .record, snapshotProvider: recordingProvider,
            cursorHider: recordingCursorDriver.makeHider(),
            windowSnapshotLoader: { _ in .success([]) }, eventTrackingStateProvider: { false },
            colorSamplerActiveProvider: { false }, modalWindowProvider: { nil }, onComplete: { _ in })
        recording.activate()
        check(recordingProvider.requests.isEmpty, "recording keeps its non-snapshot path")
        check(fronted.filter { $0 is CursorChipWindow }.count == 1, "non-snapshot path creates and shows only one hint")
        recording.cancel()
        check(recording.isCaptureSessionEnded, "non-snapshot cancellation remains intact")
        // --- CUR: the overlay paints the pointer itself ---------------------
        // The pointer must move in the *same* layer update as the two guides
        // (relative displacement 0), must never enter the frozen snapshot, and
        // must fall back to guides-only when the system cursor cannot be
        // confirmed hidden.
        let pointerWindow = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 800, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        pointerWindow.backgroundColor = .white
        let pointerView = SelectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        pointerWindow.contentView = pointerView
        pointerView.drawsPointerCursor = true
        var pointerDrawnStates: [Bool] = []
        pointerView.onPointerCursorDrawnChanged = { pointerDrawnStates.append($0) }

        var deviation: CGFloat = 0
        var geometrySamples = 0
        for offset in [(0.0, 0.0), (0.3, 0.7), (0.5, 0.5), (0.13, 0.87), (0.49, 0.51)] {
            let local = NSPoint(x: 400 + offset.0, y: 300 + offset.1)
            pointerView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: local))
            let geometry = CrosshairLayerGeometry(view: pointerView)
            guard let pointerCentre = geometry.pointerCentre,
                  let crossing = geometry.crossing else { continue }
            geometrySamples += 1
            deviation = max(
                deviation,
                abs(pointerCentre.x - crossing.x),
                abs(pointerCentre.y - crossing.y)
            )
        }
        check(geometrySamples == 5, "every sample drew both guides and the pointer")
        check(deviation == 0,
              "self-drawn pointer centre is exactly on the guide crossing (deviation \(deviation)pt)")

        // The callback is a state signal, never a per-move one: the hide/show
        // pair must not sit on the pointer-move path.
        let statesBeforeMoving = pointerDrawnStates.count
        for step in 0..<200 {
            let local = NSPoint(x: 200 + CGFloat(step), y: 150 + CGFloat(step % 40))
            pointerView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: local))
        }
        check(pointerDrawnStates.count == statesBeforeMoving,
              "200 pointer moves add no cursor show/hide transition")
        check(pointerDrawnStates == [true], "the pointer state is reported exactly once")

        pointerView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: NSPoint(x: 400, y: 300)))
        let pointerGeometry = CrosshairLayerGeometry(view: pointerView)
        check(pointerGeometry.pointer?.isHidden == false, "the pointer layer is visible while the guides are")
        pointerView.selectionLocked = true
        check(pointerGeometry.pointer?.isHidden == true,
              "a committed selection hides the self-drawn pointer")
        check(pointerDrawnStates.last == false, "hiding the pointer reports the state change")
        pointerView.selectionLocked = false
        check(pointerGeometry.pointer?.isHidden == false, "resuming the overlay shows the pointer again")
        pointerView.scrollCaptureActive = true
        check(pointerGeometry.pointer?.isHidden == true,
              "scroll capture keeps the pointer out of the frame")
        pointerView.scrollCaptureActive = false

        // Fallback: no confirmed hide means no self-drawn pointer, guides stay.
        pointerView.drawsPointerCursor = false
        check(pointerGeometry.pointer?.isHidden == true, "fallback mode draws no second pointer")
        check(pointerGeometry.horizontalBand?.isHidden == false
              && pointerGeometry.verticalBand?.isHidden == false, "fallback mode keeps the guides")
        pointerView.drawsPointerCursor = true

        // The pointer is two shape layers (dark outline + white core) inside the
        // overlay view — layer content, never `draw(_:)` pixels, so moving it
        // cannot repaint the frozen snapshot (no `needsDisplay` on that path).
        let pointerLayers = pointerGeometry.pointer?.layer?.sublayers ?? []
        check(pointerLayers.count == 2 && pointerLayers.allSatisfy { $0 is CAShapeLayer },
              "the pointer is two shape layers (outline + core), not snapshot pixels")

        // Hit testing: the pointer sits under the mouse by definition, so it
        // must never become the event target itself.
        check(pointerView.hitTest(NSPoint(x: 400, y: 300)) === pointerView,
              "the pointer is not a mouse target")

        // A pointer on one display draws nothing on the others.
        let sideWindow = NSWindow(
            contentRect: NSRect(x: -3200, y: -4000, width: 300, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let sideView = SelectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        sideWindow.contentView = sideView
        sideView.drawsPointerCursor = true
        sideView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: NSPoint(x: 400, y: 300)))
        let sideGeometry = CrosshairLayerGeometry(view: sideView)
        check(sideGeometry.pointer?.isHidden == true,
              "a display the pointer is not on draws no pointer")
        check(sideGeometry.verticalBand?.isHidden == true,
              "…and no vertical guide")
        check(sideGeometry.horizontalBand?.isHidden == false,
              "…while the horizontal guide still continues across it")

        // Hider contract: balanced, idempotent, and honest about a probe that
        // cannot confirm anything.
        let unitState = CursorDriverState()
        let unitHider = unitState.makeHider()
        check(unitHider.hide(), "hide reports success when the read-back confirms")
        check(unitHider.hide(), "a second hide is a no-op")
        check(unitState.hides == 1, "the cursor is hidden once")
        unitHider.restore()
        unitHider.restore()
        check(unitState.unhides == 1, "one hide is undone by exactly one unhide")

        let blindState = CursorDriverState()
        blindState.probeAvailable = false
        let blindHider = blindState.makeHider()
        check(!blindHider.hide(), "an unverifiable hide reports failure")
        check(blindState.unhides == 1, "the unverified hide is balanced")
        check(blindState.logs.contains { $0.contains("could not be hidden") },
              "the fallback is logged")

        let dyingState = CursorDriverState()
        var dyingHider: SystemCursorHider? = dyingState.makeHider()
        _ = dyingHider?.hide()
        check(dyingState.hides == 1 && dyingState.unhides == 0,
              "a hidden session is hidden before deallocation")
        dyingHider = nil
        check(dyingState.unhides == 1, "deinit restores the system cursor")

        // --- The 1.0.23 cursor-loss failure ---------------------------------
        // Observed on a real machine: the overlay lost activation while the
        // cursor was hidden, the unhide was issued from the background (AppKit
        // dropped it), the flag then said "restored", and no later path ever
        // tried again — the cursor stayed hidden until another app took the
        // foreground. The hider must keep the hide on the books until an
        // unhide can actually land, and a watchdog must prove it afterwards.

        // 1) restore() while inactive: no dropped unhide, one unhide on activation.
        let deferredState = CursorDriverState()
        deferredState.appActive = false
        let deferredHider = deferredState.makeHider()
        check(deferredHider.hide(), "the hide itself still confirms")
        deferredHider.restore()
        check(deferredHider.hideDepth == 1, "a restore from the background keeps the hide on the books")
        check(deferredState.unhides == 0, "…and issues no unhide that AppKit would drop")
        check(deferredHider.restoreRequests == 1, "the exit path reached restore()")
        check(deferredState.logs.contains { $0.contains("restore deferred") },
              "the deferral is logged")
        deferredState.appActive = true
        deferredState.fireActivation()
        check(deferredHider.hideDepth == 0, "activation balances the deferred hide")
        check(deferredState.unhides == 1, "exactly one unhide once the app is active")
        deferredHider.restore()
        check(deferredState.unhides == 1, "restore stays idempotent after the deferral")

        // 2) A restore whose unhide the WindowServer drops: one watchdog retry.
        let stuckState = CursorDriverState()
        stuckState.swallowUnhides = 1
        let stuckHider = stuckState.makeHider()
        check(stuckHider.hide(), "the cursor is hidden before the stuck-restore test")
        stuckHider.restore()
        check(stuckHider.hideDepth == 0 && stuckState.unhides == 1,
              "the first unhide is issued but dropped by the simulated WindowServer")
        check(stuckState.cursorVisible == false, "…so the cursor is still hidden")
        stuckHider.runRestoreWatchdog()
        check(stuckState.unhides == 2, "the watchdog forces exactly one extra unhide")
        check(stuckState.cursorVisible == true, "the watchdog leaves the cursor visible")
        check(stuckHider.forcedUnhides == 1, "the extra unhide is counted once")
        check(stuckState.logs.contains { $0.contains("watchdog") && $0.contains("forced one unhide") },
              "the watchdog recovery is logged")

        // 3) No read-back at all: the watchdog restores visibility blindly.
        let blindWatchdogState = CursorDriverState()
        let blindWatchdogHider = blindWatchdogState.makeHider()
        check(blindWatchdogHider.hide(), "the cursor is hidden before the blind-watchdog test")
        blindWatchdogHider.restore()
        blindWatchdogState.probeAvailable = false
        blindWatchdogHider.runRestoreWatchdog()
        check(blindWatchdogState.unhides == 2, "without a read-back the watchdog forces one unhide")
        check(blindWatchdogState.cursorVisible == true, "…which restores a visible cursor")
        check(blindWatchdogState.logs.contains { $0.contains("no cursor read-back") },
              "the unverifiable watchdog path is logged")

        // 4) A session that never hid the cursor must not steal an unhide.
        let untouchedState = CursorDriverState()
        let untouchedHider = untouchedState.makeHider()
        untouchedHider.runRestoreWatchdog()
        check(untouchedState.unhides == 0, "a session that never hid the cursor forces no unhide")
        untouchedHider.scheduleRestoreWatchdog()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(untouchedState.unhides == 0, "…and arms no watchdog")

        // 5) The reported timing, end to end: hide, lose activation, tear down
        //    (Esc) before activation returns. The watchdog is the last net and
        //    must leave the counter at 0 with the cursor visible.
        fronted.removeAll()
        let dragState = CursorDriverState()
        // Long enough that the willResignActive watchdog cannot fire while the
        // test still checks the deferred state; the teardown one is verified
        // below by running the loop past it.
        dragState.watchdogDelay = 0.2
        let dragHider = dragState.makeHider()
        let dragController = OverlayWindowController(
            postCaptureAction: .edit,
            snapshotProvider: SnapshotRecorder(),
            cursorHider: dragHider,
            windowSnapshotLoader: { _ in .success([]) },
            eventTrackingStateProvider: { false },
            colorSamplerActiveProvider: { false },
            modalWindowProvider: { nil },
            onComplete: { _ in }
        )
        dragController.activate()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(dragState.hides == 1 && dragHider.hideDepth == 1,
              "drag-before-first-frame: the overlay hid the cursor exactly once")
        // The drag starts before the first frame; the overlay loses activation.
        dragState.appActive = false
        NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        check(dragHider.hideDepth == 1,
              "drag-before-first-frame: losing activation keeps the hide on the books")
        check(dragHider.restoreRequests >= 1,
              "drag-before-first-frame: the lost-activation path asked for a restore")
        check(dragState.unhides == 0,
              "drag-before-first-frame: no unhide is issued from the background")
        // Esc: the session tears down before activation ever returns.
        dragController.cancel()
        check(dragController.isCaptureSessionEnded, "drag-before-first-frame: Esc ends the session")
        check(dragHider.hideDepth == 1,
              "drag-before-first-frame: teardown alone cannot finish the deferred restore")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        check(dragHider.hideDepth == 0, "drag-before-first-frame: the watchdog leaves hideDepth 0")
        check(dragState.unhides == 1 && dragState.hides == 1,
              "drag-before-first-frame: one hide, one unhide after everything settles")
        check(dragState.cursorVisible, "drag-before-first-frame: the system cursor is visible again")
        check(dragState.logs.contains { $0.contains("watchdog") },
              "drag-before-first-frame: the watchdog reported the closed session")
        dragController.cancel()

        // 6) The watchdog must outlive the controller: production releases the
        //    controller right after `tearDown`, and a weakly held watchdog would
        //    die with it (the hole that made the fix ineffective on a real run).
        var releasedState: CursorDriverState?
        do {
            fronted.removeAll()
            let state = CursorDriverState()
            state.watchdogDelay = 0.01
            releasedState = state
            let hider = state.makeHider()
            let controller = OverlayWindowController(
                postCaptureAction: .edit,
                snapshotProvider: SnapshotRecorder(),
                cursorHider: hider,
                windowSnapshotLoader: { _ in .success([]) },
                eventTrackingStateProvider: { false },
                colorSamplerActiveProvider: { false },
                modalWindowProvider: { nil },
                onComplete: { _ in }
            )
            controller.activate()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            controller.cancel()
            check(hider.hideDepth == 0, "released controller: teardown restored the cursor")
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        check(releasedState?.logs.contains { $0.contains("watchdog") && $0.contains("visible") } == true,
              "the watchdog still runs after the controller is released")

        // 7) Five open/close cycles: the counter never drifts.
        for cycle in 0..<5 {
            fronted.removeAll()
            let state = CursorDriverState()
            state.watchdogDelay = 0.01
            let hider = state.makeHider()
            let controller = OverlayWindowController(
                postCaptureAction: .edit,
                snapshotProvider: SnapshotRecorder(),
                cursorHider: hider,
                windowSnapshotLoader: { _ in .success([]) },
                eventTrackingStateProvider: { false },
                colorSamplerActiveProvider: { false },
                modalWindowProvider: { nil },
                onComplete: { _ in }
            )
            controller.activate()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            controller.cancel()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            check(hider.hideDepth == 0, "cycle \(cycle): the closed overlay leaves hideDepth 0")
            check(state.hides == 1 && state.unhides == 1,
                  "cycle \(cycle): one hide and one unhide per session")
            check(state.cursorVisible, "cycle \(cycle): the cursor is visible after closing")
        }

        // Controller contract: confirmed hide -> overlays paint the pointer;
        // unconfirmed hide -> guides only; teardown restores exactly once.
        for scenario in ["confirmed", "hide-ignored", "probe-missing"] {
            fronted.removeAll()
            let state = CursorDriverState()
            state.hideIsHonoured = scenario != "hide-ignored"
            state.probeAvailable = scenario != "probe-missing"
            let hider = state.makeHider()
            let controller = OverlayWindowController(
                postCaptureAction: .edit,
                snapshotProvider: SnapshotRecorder(),
                cursorHider: hider,
                windowSnapshotLoader: { _ in .success([]) },
                eventTrackingStateProvider: { false },
                colorSamplerActiveProvider: { false },
                modalWindowProvider: { nil },
                onComplete: { _ in }
            )
            controller.activate()
            // One run-loop turn lets the post-activation retry run.
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if scenario == "confirmed" {
                check(state.hides == 1, "confirmed: one hide per session")
                check(hider.isHidden, "confirmed: the system cursor stays hidden while the overlay is up")
                check(controller.activeSelectionViews.contains(where: \.drawsPointerCursor),
                      "confirmed: overlays paint the pointer")
                check(state.unhides == 0, "confirmed: nothing is unhidden while the overlay is up")
            } else {
                check(!hider.isHidden, "\(scenario): the system cursor is visible again")
                check(state.hides == state.unhides,
                      "\(scenario): every attempted hide is balanced by exactly one unhide")
                check(controller.activeSelectionViews.allSatisfy { !$0.drawsPointerCursor },
                      "\(scenario): nothing draws a second pointer")
                check(state.logs.contains { $0.contains("could not be hidden") },
                      "\(scenario): the fallback is logged")
            }
            controller.cancel()
            check(state.unhides == state.hides, "teardown leaves hide/unhide balanced")
            check(!hider.isHidden, "nothing stays hidden after teardown")
            controller.cancel()
            check(state.unhides == state.hides, "repeated cancellation cannot unhide twice")
        }

        // 8) A released hider's activation retry must not steal a hide that a
        //    live session has taken over (NSCursor's counter is process-wide).
        let staleState = CursorDriverState()
        staleState.appActive = false
        var staleHider: SystemCursorHider? = staleState.makeHider()
        check(staleHider?.hide() == true, "stale-retry: the released session hid the cursor")
        staleHider = nil
        check(staleState.activationBody != nil, "stale-retry: release left one activation retry")
        let liveState = CursorDriverState()
        let liveHider = liveState.makeHider()
        check(liveHider.hide(), "stale-retry: a new session hides the cursor again")
        check(liveHider.hideDepth == 1, "stale-retry: the live session owns the hide")
        staleState.fireActivation()
        check(liveState.unhides == 0 && liveState.cursorVisible == false,
              "stale-retry: the released hider does not steal the live session's hide")
        liveHider.restore()
        check(liveState.unhides == 1, "stale-retry: the live session still restores exactly once")

        print("{\"passed\":true,\"checks\":\(checks),\"boundary\":\"Real capture controller, native window IDs and explicit snapshot exclusion request; injected snapshot provider and intercepted orderFrontRegardless (no desktop overlay, ScreenCaptureKit pixels, TCC, user clipboard, or physical key event)\"}")
    }
}
