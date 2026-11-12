import AppKit
import Combine
import BlinkClipCore

/// Mirrors the local NSWindow.sharingType policy used by the reference application.
@MainActor
final class WindowSharingPolicy {
    private let store: ClipboardStore
    private var preferenceObservation: AnyCancellable?
    private var windowObservations: [NSObjectProtocol] = []

    init(store: ClipboardStore) {
        self.store = store
        preferenceObservation = store.preferenceChanges
            .map { change in
                ConfigurationFunctions.decodeOldAndNew(
                    old: change.old.showDuringScreenSharing,
                    new: change.new.showDuringScreenSharing,
                    decode: { ConfigurationFunctions.castStoredValue(storedValue: $0, as: Bool.self) },
                    defaultValue: { true }
                )
            }
            .filter { $0.old != $0.new }
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.applyToAllWindows() }
            }
        observeKeyWindow()
        for name in [NSWindow.didExposeNotification, NSWindow.didUpdateNotification] {
            windowObservations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) {
                [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                Task { @MainActor in self?.apply(to: window) }
            })
        }
        applyToAllWindows()
    }

    func apply(to window: NSWindow) {
        set(window, visible: currentVisibility)
    }

    /// observe key-window notifications on the main operation queue.
    private func observeKeyWindow() {
        windowObservations.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyToKeyWindow() }
        })
    }

    /// read NSApp.keyWindow; a missing key window is a no-op.
    private func applyToKeyWindow() {
        guard let window = NSApp.keyWindow else { return }
        set(window, visible: currentVisibility)
    }

    /// apply the current sharing policy to every application window.
    private func applyToAllWindows() {
        for window in NSApp.windows { set(window, visible: currentVisibility) }
    }

    private var currentVisibility: Bool {
        ConfigurationFunctions.decodeOrDefault(
            storedValue: store.preferences.showDuringScreenSharing,
            decode: { ConfigurationFunctions.castStoredValue(storedValue: $0, as: Bool.self) },
            defaultValue: { true }
        )
    }

    private func set(_ window: NSWindow, visible: Bool) {
        window.sharingType = visible ? .readOnly : .none
    }

    deinit {
        for observer in windowObservations { NotificationCenter.default.removeObserver(observer) }
    }
}
