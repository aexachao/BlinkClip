import AppKit
import Combine

/// Local sound feedback follows the history notifications, rather than capture creation.
/// Success feedback uses the macOS-provided Purr sound without bundling system audio.
@MainActor
public final class SoundEffects {
    public enum Feedback { case copy, paste }
    private let playback: ((Feedback) -> Void)?
    static let successSoundName = NSSound.Name("Purr")
    private let successSound: NSSound?
    private var observations = Set<AnyCancellable>()

    public init(store: ClipboardStore, monitor: ClipboardMonitor?, playback: ((Feedback) -> Void)? = nil) {
        self.playback = playback
        successSound = playback == nil ? NSSound(named: Self.successSoundName) : nil
        if let monitor {
            NotificationCenter.default.publisher(for: ClipboardMonitor.didCaptureItemNotification, object: monitor)
                .sink { [weak self, weak store] _ in
                    MainActor.assumeIsolated {
                        guard let self, store?.preferences.playSounds == true else { return }
                        self.play(feedback: .copy)
                    }
                }.store(in: &observations)
        }
        store.didRestoreItem.sink { [weak self, weak store] _ in
            MainActor.assumeIsolated {
                guard let self, store?.preferences.playSounds == true else { return }
                self.play(feedback: .paste)
            }
        }.store(in: &observations)
    }

    public func stop() {
        observations.removeAll()
        successSound?.stop()
    }

    private func play(feedback: Feedback) {
        if let playback { playback(feedback); return }
        // Each operation restarts the same system sound, without layering or time-based suppression.
        successSound?.stop()
        successSound?.currentTime = 0
        successSound?.play()
    }
}
