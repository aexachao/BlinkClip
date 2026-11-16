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

/// Reads the crosshair geometry out of the live view/layer tree — the same
/// numbers the window server receives, without a second copy of the layout
/// maths. The overlay installs exactly two crosshair subviews: the horizontal
/// guide and the vertical guide. The pointer is the system crosshair and is not
/// part of this view at all.
private struct CrosshairLayerGeometry {
    let horizontalBand: NSView?
    let verticalBand: NSView?
    let subviewCount: Int

    init(view: SelectionView) {
        let subviews = view.subviews
        subviewCount = subviews.count
        horizontalBand = subviews.count == 2 ? subviews[0] : nil
        verticalBand = subviews.count == 2 ? subviews[1] : nil
    }

    /// Where the two guide bands cross, in view coordinates.
    var crossing: NSPoint? {
        guard let horizontalBand, let verticalBand else { return nil }
        return NSPoint(x: verticalBand.frame.midX, y: horizontalBand.frame.midY)
    }

    /// The two solid line layers, one per axis.
    var guideLayers: [CAShapeLayer] {
        [horizontalBand, verticalBand].compactMap { $0?.layer?.sublayers?.first as? CAShapeLayer }
    }
}

/// Counts `draw(_:)` calls so a guide move can be shown to repaint nothing.
private final class CountingSelectionView: SelectionView {
    private(set) var drawCount = 0

    override func draw(_ dirtyRect: NSRect) {
        drawCount += 1
        super.draw(dirtyRect)
    }
}

private func rgbaComponents(_ color: CGColor?) -> [CGFloat]? {
    guard let color,
          let space = CGColorSpace(name: CGColorSpace.sRGB),
          let converted = color.converted(to: space, intent: .defaultIntent, options: nil) else {
        return nil
    }
    return converted.components
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
                let controller = OverlayWindowController(postCaptureAction: action, snapshotProvider: provider,
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
            let controller = OverlayWindowController(postCaptureAction: action, snapshotProvider: provider,
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
        let recording = OverlayWindowController(postCaptureAction: .record, snapshotProvider: recordingProvider,
            windowSnapshotLoader: { _ in .success([]) }, eventTrackingStateProvider: { false },
            colorSamplerActiveProvider: { false }, modalWindowProvider: { nil }, onComplete: { _ in })
        recording.activate()
        check(recordingProvider.requests.isEmpty, "recording keeps its non-snapshot path")
        check(fronted.filter { $0 is CursorChipWindow }.count == 1, "non-snapshot path creates and shows only one hint")
        recording.cancel()
        check(recording.isCaptureSessionEnded, "non-snapshot cancellation remains intact")
        // --- CUR4: system crosshair + layers-only guides ---------------------
        // The overlay never hides or paints the pointer: the pointer is the
        // system `NSCursor.crosshair` (hardware-composited, so it cannot trail).
        // The two guides live in their own layers, are moved inside one
        // disabled-actions transaction and are displayed synchronously. Their
        // style is deliberately quiet: a solid 1.5pt systemGray line at 50%.
        let pointerWindow = NSWindow(
            contentRect: NSRect(x: -4000, y: -4000, width: 800, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        pointerWindow.backgroundColor = .white
        let pointerView = CountingSelectionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        pointerWindow.contentView = pointerView

        let initialGeometry = CrosshairLayerGeometry(view: pointerView)
        check(initialGeometry.subviewCount == 2,
              "the overlay installs exactly two guide layers and no self-drawn pointer")

        var deviation: CGFloat = 0
        var geometrySamples = 0
        for offset in [(0.0, 0.0), (0.3, 0.7), (0.5, 0.5), (0.13, 0.87), (0.49, 0.51)] {
            let local = NSPoint(x: 400 + offset.0, y: 300 + offset.1)
            pointerView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: local))
            guard let crossing = CrosshairLayerGeometry(view: pointerView).crossing else { continue }
            geometrySamples += 1
            deviation = max(deviation, abs(crossing.x - local.x), abs(crossing.y - local.y))
        }
        check(geometrySamples == 5, "every sample showed both guide bands")
        check(deviation <= 1.0,
              "the guide crossing is within one device pixel of the pointer (max \(deviation)pt)")

        // Style: solid, 1.5pt, systemGray at 50% — the low-contrast style that
        // keeps a one-frame offset nearly invisible.
        let guideLayers = CrosshairLayerGeometry(view: pointerView).guideLayers
        check(guideLayers.count == 2, "each guide is a shape layer")
        check(guideLayers.allSatisfy { abs($0.lineWidth - 1.5) < 0.001 },
              "guides are 1.5pt")
        check(guideLayers.allSatisfy { layer in
                  let pattern = layer.lineDashPattern?.map(\.doubleValue) ?? []
                  return pattern.isEmpty
              },
              "guides are solid (no dash pattern)")
        let expectedGray = NSColor.systemGray.withAlphaComponent(0.5)
        check(guideLayers.allSatisfy { layer in
            guard let components = rgbaComponents(layer.strokeColor),
                  let expected = rgbaComponents(expectedGray.cgColor),
                  components.count == 4, expected.count == 4 else { return false }
            return zip(components, expected).allSatisfy { abs($0 - $1) < 0.02 }
        }, "guides are systemGray at 50%")

        // Moving a guide must not repaint the frozen snapshot: 200 pointer
        // moves change layers only, never `draw(_:)` of the full-screen view.
        let drawCountBeforeSweep = pointerView.drawCount
        for step in 0..<200 {
            let local = NSPoint(x: 200 + CGFloat(step), y: 150 + CGFloat(step % 40))
            pointerView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: local))
        }
        check(pointerView.drawCount == drawCountBeforeSweep,
              "200 guide moves add no overlay draw(_:) pass")

        // State contract: guides show while aiming/drawing, and disappear as
        // soon as the selection is committed, scroll capture starts, the editor
        // takes over, or interaction is disabled.
        let centre = NSPoint(x: 400, y: 300)
        pointerView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: centre))
        var geometry = CrosshairLayerGeometry(view: pointerView)
        check(geometry.horizontalBand?.isHidden == false && geometry.verticalBand?.isHidden == false,
              "idle shows both guides")
        pointerView.selectionLocked = true
        geometry = CrosshairLayerGeometry(view: pointerView)
        check(geometry.horizontalBand?.isHidden == true && geometry.verticalBand?.isHidden == true,
              "a committed selection hides the guides")
        pointerView.selectionLocked = false
        pointerView.scrollCaptureActive = true
        geometry = CrosshairLayerGeometry(view: pointerView)
        check(geometry.horizontalBand?.isHidden == true && geometry.verticalBand?.isHidden == true,
              "scroll capture hides the guides")
        pointerView.scrollCaptureActive = false
        pointerView.selectionInteractionEnabled = false
        geometry = CrosshairLayerGeometry(view: pointerView)
        check(geometry.horizontalBand?.isHidden == true && geometry.verticalBand?.isHidden == true,
              "editor hand-off hides the guides")
        pointerView.selectionInteractionEnabled = true
        check(CrosshairLayerGeometry(view: pointerView).horizontalBand?.isHidden == false,
              "resuming the overlay shows the guides again")
        pointerView.updateSelectionRect(NSRect(x: 100, y: 100, width: 200, height: 160))
        geometry = CrosshairLayerGeometry(view: pointerView)
        check(geometry.horizontalBand?.isHidden == true && geometry.verticalBand?.isHidden == true,
              "an established selection shows no guides")

        // A pointer on one display continues the horizontal line onto its
        // neighbours, while the vertical line only lands on the pointer's own
        // display: the other overlays stay empty at the crossing point.
        let sideWindow = NSWindow(
            contentRect: NSRect(x: -3200, y: -4000, width: 300, height: 600),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        let sideView = SelectionView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        sideWindow.contentView = sideView
        sideView.updateCrosshair(globalPoint: pointerWindow.convertPoint(toScreen: centre))
        let sideGeometry = CrosshairLayerGeometry(view: sideView)
        check(sideGeometry.verticalBand?.isHidden == true,
              "a display the pointer is not on draws no vertical guide")
        check(sideGeometry.horizontalBand?.isHidden == false,
              "…while the horizontal guide still continues across it")

        // The reported timing, end to end, and the strongest assertion the
        // process can make about the fix: drive the real controller through
        // five open/close cycles while the cursor-hide entry points are
        // intercepted, and require that nobody calls them at all. A cursor that
        // is never hidden cannot stay hidden — that is the whole CUR4 contract.
        var hideCalls = 0
        var unhideCalls = 0
        let hideSelector = NSSelectorFromString("hide")
        let unhideSelector = NSSelectorFromString("unhide")
        let hideMethod = class_getClassMethod(NSCursor.self, hideSelector)!
        let unhideMethod = class_getClassMethod(NSCursor.self, unhideSelector)!
        let originalHide = method_getImplementation(hideMethod)
        let originalUnhide = method_getImplementation(unhideMethod)
        let hideBlock: @convention(block) (AnyObject) -> Void = { _ in hideCalls += 1 }
        let unhideBlock: @convention(block) (AnyObject) -> Void = { _ in unhideCalls += 1 }
        let hideIMP = imp_implementationWithBlock(hideBlock)
        let unhideIMP = imp_implementationWithBlock(unhideBlock)
        method_setImplementation(hideMethod, hideIMP)
        method_setImplementation(unhideMethod, unhideIMP)
        defer {
            method_setImplementation(hideMethod, originalHide)
            method_setImplementation(unhideMethod, originalUnhide)
            imp_removeBlock(hideIMP)
            imp_removeBlock(unhideIMP)
        }

        for cycle in 0..<5 {
            fronted.removeAll()
            let controller = OverlayWindowController(
                postCaptureAction: .edit,
                snapshotProvider: SnapshotRecorder(),
                windowSnapshotLoader: { _ in .success([]) },
                eventTrackingStateProvider: { false },
                colorSamplerActiveProvider: { false },
                modalWindowProvider: { nil },
                onComplete: { _ in }
            )
            controller.activate()
            // The reported timing: the drag starts before the first frame, and
            // the session may lose activation while it is still on screen.
            NotificationCenter.default.post(name: NSApplication.willResignActiveNotification, object: nil)
            controller.cancel()
            check(controller.isCaptureSessionEnded,
                  "cycle \(cycle): drag-before-first-frame ends the session")
            controller.cancel()
            check(controller.isCaptureSessionEnded,
                  "cycle \(cycle): repeated cancellation stays harmless")
        }
        check(hideCalls == 0 && unhideCalls == 0,
              "five overlay sessions never hide or unhide the system cursor (hide=\(hideCalls), unhide=\(unhideCalls))")

        print("{\"passed\":true,\"checks\":\(checks),\"boundary\":\"Real capture controller, native window IDs and explicit snapshot exclusion request; injected snapshot provider and intercepted orderFrontRegardless (no desktop overlay, ScreenCaptureKit pixels, TCC, user clipboard, or physical key event)\"}")
    }
}
