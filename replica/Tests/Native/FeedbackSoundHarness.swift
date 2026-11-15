// Exercises the production subscriber and the action classification with injected
// playback. No sound is played and no clipboard is written.
import AppKit
import Combine
import Foundation

enum ResourceBundle { static let bundle = Bundle.main }
@MainActor public final class ClipboardStore: NSObject {
    struct Preferences { var playSounds = true }
    var preferences = Preferences()
    let didRestoreItem = PassthroughSubject<Void, Never>()
}
@MainActor public final class ClipboardMonitor: NSObject {
    static let didCaptureItemNotification = Notification.Name("feedback-fixture.capture")
}
@main struct FeedbackSoundHarness {
    struct Rejected: Error { }

    @MainActor static func main() {
        let store = ClipboardStore()
        let monitor = ClipboardMonitor()
        var events: [SoundEffects.Feedback] = []
        let effects = SoundEffects(store: store, monitor: monitor, playback: { events.append($0) })
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool) {
            precondition(condition())
            checks += 1
        }
        check(SoundEffects.successSoundName == NSSound.Name("Purr"))
        check(SoundEffects.copySoundFileName == "CopySound.mp3")
        check(SoundEffects.pasteSoundFileName == "PasteSound.mp3")
        let sound = NSSound(named: SoundEffects.successSoundName)
        check(sound != nil)
        check(sound!.name == SoundEffects.successSoundName)
        check(sound!.duration > 0 && sound!.duration.isFinite)
        check(!sound!.isPlaying)
        sound!.currentTime = 0
        check(sound!.currentTime == 0)
        // This bare test binary ships no feedback audio: the mapping still says when to
        // play what, and playback stays silent instead of failing or beeping.
        check(SoundEffects.bundledURL(for: .copy) == nil)
        check(SoundEffects.bundledURL(for: .cut) == nil)
        check(SoundEffects.bundledURL(for: .paste) == nil)
        check(SoundEffects.bundledURL(for: .success) == nil)
        // Real (uninjected) instance: missing resources resolve to no player at all.
        let quietEffects = SoundEffects(store: ClipboardStore(), monitor: nil)
        check(quietEffects.player(for: .copy) == nil)
        check(quietEffects.player(for: .cut) == nil)
        check(quietEffects.player(for: .paste) == nil)
        check(quietEffects.player(for: .success) === sound)
        quietEffects.stop()
        func capture() { NotificationCenter.default.post(name: ClipboardMonitor.didCaptureItemNotification, object: monitor) }
        // An external copy is a copy.
        capture()
        check(events == [.copy])
        // A restore nobody classified keeps the previous success tone.
        store.didRestoreItem.send()
        check(events == [.copy, .success])
        // Declared actions decide the tone for the restore that follows them.
        SoundEffects.withFeedback(.copy) { store.didRestoreItem.send() }
        check(events == [.copy, .success, .copy])
        SoundEffects.withFeedback(.cut) { store.didRestoreItem.send() }
        check(events == [.copy, .success, .copy, .cut])
        SoundEffects.withFeedback(.paste) { store.didRestoreItem.send() }
        check(events == [.copy, .success, .copy, .cut, .paste])
        // Nested declarations resolve innermost first, and the outer one is restored after.
        SoundEffects.withFeedback(.copy) {
            SoundEffects.withFeedback(.paste) { store.didRestoreItem.send() }
            store.didRestoreItem.send()
        }
        check(events == [.copy, .success, .copy, .cut, .paste, .paste, .copy])
        // The declaration ends with its operation, even when that operation throws.
        do { try SoundEffects.withFeedback(.cut) { throw Rejected() } } catch { }
        store.didRestoreItem.send()
        check(events.count == 8 && events.last == .success)
        // Independent rapid operations stay independent instead of being merged.
        SoundEffects.withFeedback(.copy) { store.didRestoreItem.send() }
        SoundEffects.withFeedback(.copy) { store.didRestoreItem.send() }
        check(events.suffix(2) == [.copy, .copy])
        // The preference is checked before any feedback is produced, declared or not.
        store.preferences.playSounds = false
        capture()
        SoundEffects.withFeedback(.cut) { store.didRestoreItem.send() }
        store.didRestoreItem.send()
        check(events.count == 10)
        store.preferences.playSounds = true
        SoundEffects.withFeedback(.cut) { store.didRestoreItem.send() }
        check(events.count == 11 && events.last == .cut)
        effects.stop()
        capture()
        SoundEffects.withFeedback(.paste) { store.didRestoreItem.send() }
        check(events.count == 11)
        print("{\"passed\":true,\"checks\":\(checks),\"boundary\":\"production sound subscriptions and action classification; system Purr resolution, missing bundled audio, injected player and event sources; no clipboard or audio output\"}")
    }
}
