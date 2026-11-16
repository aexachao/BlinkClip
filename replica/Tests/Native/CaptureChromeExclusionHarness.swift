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
                    self?.unhides += 1
                    self?.cursorVisible = true
                },
                isCursorVisible: { [weak self] in
                    guard let self, self.probeAvailable else { return nil }
                    return self.cursorVisible
                }
            ),
            log: { [weak self] message in self?.logs.append(message) }
        )
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

        print("{\"passed\":true,\"checks\":\(checks),\"boundary\":\"Real capture controller, native window IDs and explicit snapshot exclusion request; injected snapshot provider and intercepted orderFrontRegardless (no desktop overlay, ScreenCaptureKit pixels, TCC, user clipboard, or physical key event)\"}")
    }
}
