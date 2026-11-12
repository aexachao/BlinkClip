// TEMP-STUB (P1-A)
//
// Why this file exists: `Translation/OCRTranslatePanel.swift` calls
// `SettingsWindowController.shared.showAsSettings()` from its "open settings"
// button. `Settings/SettingsWindowController.swift` builds the whole capcap
// settings window (SettingsView + every pane, incl. permissions/updates/trigger
// panes) and is out of the vendoring scope.
//
// Behaviour: `showAsSettings(...)` now forwards to `BlinkClipSettingsOpener.open` — the
// slot BlinkClip fills at launch (see `Adapters/SettingsOpener.swift`). So tapping
// "open settings" in the OCR/translate panel closes the panel and lands on BlinkClip's
// own "Screenshot" settings pane (分区 index 2). `BlinkClipCapture` must not import
// BlinkClip (the dependency runs the other way), so this reverse mount is a closure
// rather than a direct call. When nothing is installed the tap stays a no-op,
// i.e. the P1-A behaviour.
//
// `focusingPermissions` is upstream's "scroll to the permissions area" hint.
// BlinkClip's settings window has no per-permission pane, so the parameter is kept
// (callers need no change) and ignored.

import AppKit
import Foundation

/// TEMP-STUB (P1-A) — see file header.
class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    /// Upstream signature: `showAsSettings(focusingPermissions: Bool? = nil)`.
    func showAsSettings(focusingPermissions: Bool? = nil) {
        _ = focusingPermissions
        BlinkClipSettingsOpener.open?(.screenshot)
    }
}
