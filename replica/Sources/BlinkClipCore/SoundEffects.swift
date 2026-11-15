import AppKit
import Combine

/// Per-action sound feedback for successful clipboard operations.
///
/// Copy, cut and paste all finish by writing the clipboard through the same
/// `ClipboardStore` entry point, so the store itself cannot say which tone an
/// action deserves. The action's call site therefore declares it with
/// `withFeedback(_:perform:)` around the write it performs, and the store's own
/// success notification only supplies the moment. A restore that no call site
/// declared (a screenshot copied to the clipboard, MCP / App Intent writes)
/// keeps the previous macOS Purr tone.
///
/// The clipboard path never reads the declaration; it is only live while the
/// synchronous write it wraps runs.
@MainActor
public final class SoundEffects {
    /// The action that produced one successful feedback.
    public enum Feedback: Equatable, Sendable {
        /// Copying history content, including the multi-selection aggregate.
        case copy
        /// Cutting history content.
        case cut
        /// Pasting into the front application, including Stack paste.
        case paste
        /// A successful action no call site classified; keeps the previous tone.
        case success
    }

    /// Bundled files. Renamed from the supplied `Write.mp3` / `Knock.mp3` so the
    /// mapping is readable at the call site and in the build whitelist.
    public static let copySoundFileName = "CopySound.mp3"
    public static let pasteSoundFileName = "PasteSound.mp3"
    /// macOS system tone that unclassified successes keep.
    static let successSoundName = NSSound.Name("Purr")

    private let playback: ((Feedback) -> Void)?
    private let successSound: NSSound?
    private var bundledPlayers: [Feedback: NSSound] = [:]
    private var unavailableFeedback: Set<Feedback> = []
    private var observations = Set<AnyCancellable>()
    /// The actions whose store writes are in flight, innermost last.
    private static var declared: [Feedback] = []

    public init(store: ClipboardStore, monitor: ClipboardMonitor?, playback: ((Feedback) -> Void)? = nil) {
        self.playback = playback
        successSound = playback == nil ? NSSound(named: Self.successSoundName) : nil
        if let monitor {
            NotificationCenter.default.publisher(for: ClipboardMonitor.didCaptureItemNotification, object: monitor)
                .sink { [weak self, weak store] _ in
                    MainActor.assumeIsolated {
                        guard let self, store?.preferences.playSounds == true else { return }
                        // An external copy is a copy: one capture, one sound.
                        self.play(feedback: .copy)
                    }
                }.store(in: &observations)
        }
        store.didRestoreItem.sink { [weak self, weak store] _ in
            MainActor.assumeIsolated {
                guard let self, store?.preferences.playSounds == true else { return }
                self.play(feedback: Self.declared.last ?? .success)
            }
        }.store(in: &observations)
        if playback == nil { preloadBundledPlayers() }
    }

    /// Declares which action the wrapped store write belongs to.
    ///
    /// Nested declarations resolve innermost first, and the declaration is only
    /// visible while `operation` runs, so an unrelated notification cannot be
    /// mis-attributed. Playback is not started here: the store's success
    /// notification still decides whether the operation actually succeeded.
    public static func withFeedback<Result>(_ feedback: Feedback,
                                            perform operation: () throws -> Result) rethrows -> Result {
        declared.append(feedback)
        defer { declared.removeLast() }
        return try operation()
    }

    public func stop() {
        observations.removeAll()
        successSound?.stop()
        for player in bundledPlayers.values { player.stop() }
        bundledPlayers.removeAll()
        unavailableFeedback.removeAll()
    }

    /// The player one feedback uses, or `nil` when its resource did not ship.
    ///
    /// Copy and cut play the same file, so they share one instance and a second
    /// trigger restarts it instead of layering a second voice. Exposed so a test
    /// can assert the resolution without emitting audio.
    public func player(for feedback: Feedback) -> NSSound? {
        if feedback == .success { return successSound }
        let key = Self.soundKey(for: feedback)
        if let cached = bundledPlayers[key] { return cached }
        guard !unavailableFeedback.contains(key) else { return nil }
        let sound = Self.bundledURL(for: feedback).flatMap { NSSound(contentsOf: $0, byReference: true) }
        if let sound { bundledPlayers[key] = sound } else { unavailableFeedback.insert(key) }
        return sound
    }

    /// Where a feedback's bundled audio lives, or `nil` when the resource is missing.
    ///
    /// A missing file only costs the tone: the clipboard action itself already
    /// succeeded and no code path treats this as an error.
    public static func bundledURL(for feedback: Feedback) -> URL? {
        switch feedback {
        case .success: return nil
        case .copy, .cut: return ResourceBundle.bundle.url(forResource: copySoundFileName, withExtension: nil)
        case .paste: return ResourceBundle.bundle.url(forResource: pasteSoundFileName, withExtension: nil)
        }
    }

    /// Copy and cut share one file, so they share one cached player.
    nonisolated private static func soundKey(for feedback: Feedback) -> Feedback {
        feedback == .cut ? .copy : feedback
    }

    private func play(feedback: Feedback) {
        if let playback { playback(feedback); return }
        guard let player = player(for: feedback) else { return }
        // Each operation restarts the same instance, without layering or time-based suppression.
        player.stop()
        player.currentTime = 0
        player.play()
    }

    /// Opens both bundled files once, off the main thread, so the first copy
    /// after launch never pays for it while the panel is closing.
    private func preloadBundledPlayers() {
        let entries: [(Feedback, URL)] = [Feedback.copy, .paste].compactMap { feedback in
            Self.bundledURL(for: feedback).map { (Self.soundKey(for: feedback), $0) }
        }
        guard !entries.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let loaded = entries.compactMap { key, url in
                NSSound(contentsOf: url, byReference: true).map { PreloadedPlayer(key: key, player: $0) }
            }
            guard !loaded.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for entry in loaded where self.bundledPlayers[entry.key] == nil {
                        self.bundledPlayers[entry.key] = entry.player
                    }
                }
            }
        }
    }
}

/// Carries a player from the preload queue to the main actor.
///
/// Only construction happens off the main thread; every `play()` / `stop()` call
/// stays on the main actor, which is where AppKit expects audio output.
private final class PreloadedPlayer: @unchecked Sendable {
    let key: SoundEffects.Feedback
    let player: NSSound

    init(key: SoundEffects.Feedback, player: NSSound) {
        self.key = key
        self.player = player
    }
}
