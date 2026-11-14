import AppKit
import Sparkle

/// Sparkle owns download verification, replacement, and relaunch. The About
/// window's appcast query only supplies the version summary shown to the user;
/// its check button starts this flow.
@MainActor
final class BlinkClipInAppUpdater {
    /// One Sparkle controller per process. The menu item and the settings
    /// sidebar each reach the About window through their own wrapper instance,
    /// so the controller — not the wrapper — is what must be shared; Sparkle
    /// does not support two updaters in one process.
    private static let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private static var started = false

    func checkForUpdates() throws {
        if !Self.started {
            try Self.controller.updater.start()
            Self.started = true
        }
        Self.controller.checkForUpdates(nil)
    }
}
