import AppKit
import Sparkle

/// Sparkle owns download verification, replacement, and relaunch. The About
/// page's appcast query only supplies the version summary shown to the user;
/// its check button starts this flow.
///
/// A user-initiated check with nothing to install keeps Sparkle's standard
/// "you're up to date" alert. Sparkle 2.10.1 offers no public hook to suppress
/// that alert (`SPUStandardUserDriverDelegate` only observes modal alerts, and
/// `showUpdateNotFoundWithError:` belongs to a custom `SPUUserDriver`, which we
/// do not ship), so the About page's status line deliberately shows only the
/// verification time instead of repeating the sentence inline.
@MainActor
final class BlinkClipInAppUpdater {
    /// One Sparkle controller per process. Every entry (app menu, panel ⋯ and
    /// status-bar menus, the About page button) reaches the same settings page
    /// through its own wrapper instance, so the controller — not the wrapper —
    /// is what must be shared; Sparkle does not support two updaters in one
    /// process.
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

    /// 「自动检查更新」开关读写的就是 Sparkle 自己那一个偏好
    /// （`SPUUpdater.automaticallyChecksForUpdates` → 默认域里的
    /// `SUEnableAutomaticChecks`）。不另存一份副本，所以设置页、菜单和 Sparkle
    /// 的调度器看到的永远是同一个值，重启后仍保持；关掉它只影响后台定时检查，
    /// 手动「检查更新」永远可用。
    ///
    /// 写入发生在 updater 还没 `start()` 时也安全：Sparkle 只是把键落进默认域
    /// 并等下次调度时读，不会因此发一次网络请求。
    static var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }
}
