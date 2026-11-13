import AppKit
import Combine

/// What the settings window should do after the user comes back from the
/// permission pane. Kept as a value so the decision can be tested without a GUI.
struct SettingsWindowFocusPlan: Equatable {
    var activate = false
    var orderFront = false
    var makeKey = false

    var isEmpty: Bool { !activate && !orderFront && !makeKey }
}

enum SettingsWindowFocusTrigger: Equatable {
    /// The app itself became active again (`NSApplication.didBecomeActive`).
    case appBecameActive
    /// System Settings left the screen (closed, quit, or deactivated), which is
    /// the only return path a menu-bar-only app sees.
    case systemSettingsLeft
}

enum SettingsWindowFocusPolicy {
    /// A menu-bar-only app (`LSUIElement`) never comes forward by itself, so the
    /// permission flow has to ask for it on the return paths it can observe.
    ///
    /// The plan deliberately never raises `NSWindow.level` and never touches any
    /// window other than the settings window: the window is only ordered front
    /// while it is still the window the user left there, so nothing stays pinned
    /// above other apps afterwards and a second return is a no-op.
    static func plan(trigger: SettingsWindowFocusTrigger, windowVisible: Bool,
                     windowIsKey: Bool, awaitingReturn: Bool) -> SettingsWindowFocusPlan {
        guard windowVisible, awaitingReturn else { return SettingsWindowFocusPlan() }
        switch trigger {
        case .appBecameActive:
            return SettingsWindowFocusPlan(activate: true, orderFront: true, makeKey: !windowIsKey)
        case .systemSettingsLeft:
            return SettingsWindowFocusPlan(activate: true, orderFront: true, makeKey: true)
        }
    }
}

/// Puts the settings window back in front after "去授权…" sent the user to
/// System Settings. Before this existed nothing re-activated the app, so the
/// settings window stayed behind whatever the user came back to.
@MainActor
final class SettingsWindowFocusRestore {
    static let systemSettingsBundleIdentifier = "com.apple.systempreferences"
    /// Production instance; `ReplicaUIController` attaches the settings window
    /// and `AccessibilityRequestAction` arms the return expectation.
    static let shared = SettingsWindowFocusRestore()

    private(set) weak var window: NSWindow?
    /// Armed by a permission action that opens System Settings; consumed by the
    /// first return, so repeated activation bursts cannot keep re-ordering the
    /// window.
    private(set) var awaitingReturn = false
    private(set) var restores = 0
    private(set) var lastPlan = SettingsWindowFocusPlan()
    private var observations: [NSObjectProtocol] = []
    private let activate: @MainActor (Bool) -> Void

    init(activate: (@MainActor (Bool) -> Void)? = nil) {
        self.activate = activate ?? { NSApp.activate(ignoringOtherApps: $0) }
    }

    deinit {
        MainActor.assumeIsolated {
            let tokens = observations
            observations = []
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
                NSWorkspace.shared.notificationCenter.removeObserver(token)
            }
        }
    }

    func attach(to window: NSWindow?) {
        self.window = window
    }

    /// The user asked for a permission; System Settings is about to take focus.
    func expectReturnFromSystemSettings() {
        awaitingReturn = true
        startObserving()
    }

    func handle(_ trigger: SettingsWindowFocusTrigger) {
        let plan = SettingsWindowFocusPolicy.plan(
            trigger: trigger,
            windowVisible: window?.isVisible == true,
            windowIsKey: window?.isKeyWindow == true,
            awaitingReturn: awaitingReturn)
        guard !plan.isEmpty, let window else {
            return
        }
        lastPlan = plan
        if plan.activate { activate(true) }
        if plan.orderFront {
            if plan.makeKey { window.makeKeyAndOrderFront(nil) }
            else { window.orderFront(nil) }
        }
        restores += 1
        // One restore per visit: a later activation must not steal focus again.
        if plan.activate { awaitingReturn = false }
    }

    /// Test/observer seam: only the real System Settings bundle identifier counts
    /// as "the user is done with the permission pane".
    func handleFrontmostApplicationChange(bundleIdentifier: String?) {
        guard bundleIdentifier == Self.systemSettingsBundleIdentifier else { return }
        handle(.systemSettingsLeft)
    }

    func stop() {
        let tokens = observations
        observations = []
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        awaitingReturn = false
    }

    private func startObserving() {
        guard observations.isEmpty else { return }
        let center = NotificationCenter.default
        observations.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle(.appBecameActive) }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didDeactivateApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            observations.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let self,
                          let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    else { return }
                    self.handleFrontmostApplicationChange(bundleIdentifier: application.bundleIdentifier)
                }
            })
        }
    }
}
