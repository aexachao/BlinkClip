// TEMP-STUB (P1-A)
//
// Why this file exists: `Capture/PinLauncher.swift` casts `NSApp.delegate as? AppDelegate`
// to route "edit pinned image" through the app delegate. `App/AppDelegate.swift`
// is the capcap application entry point and is out of the vendoring scope
// (it owns the status bar, hotkey registration, overlay lifecycle and every
// other controller of the standalone app).
//
// Behaviour: `handlePinnedImageEditRequest(_:beforePresent:)` does nothing and
// returns false, i.e. the request is declined. Note that the cast
// `NSApp.delegate as? AppDelegate` will also fail at runtime inside BlinkClip,
// because BlinkClip's own app delegate is a different type — so the pinned-text /
// pinned-image "Edit" action is a deliberate no-op until a real adapter is
// written. No crash risk: both paths guard with `guard let`.

import AppKit
import Foundation

/// TEMP-STUB (P1-A) — see file header.
class AppDelegate: NSObject, NSApplicationDelegate {
    /// Upstream signature: `(_ image: NSImage, beforePresent: () -> Void) -> Bool`.
    func handlePinnedImageEditRequest(_ image: NSImage, beforePresent: () -> Void) -> Bool {
        _ = image
        _ = beforePresent
        return false
    }
}
