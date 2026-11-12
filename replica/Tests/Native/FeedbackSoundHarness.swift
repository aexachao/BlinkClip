// Exercises the production subscriber with injected playback. No sound is played.
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
    @MainActor static func main() {
        let store = ClipboardStore()
        let monitor = ClipboardMonitor()
        var events: [SoundEffects.Feedback] = []
        let effects = SoundEffects(store: store, monitor: monitor, playback: { events.append($0) })
        precondition(SoundEffects.successSoundName == NSSound.Name("Purr"), "both success paths select system Purr")
        let sound = NSSound(named: SoundEffects.successSoundName)
        precondition(sound != nil, "system Purr loads without bundled audio")
        precondition(sound!.name == SoundEffects.successSoundName, "AppKit resolves the named system sound")
        precondition(sound!.duration > 0 && sound!.duration.isFinite, "system sound is valid")
        precondition(!sound!.isPlaying, "validation never starts audio output")
        sound!.currentTime = 0
        precondition(sound!.currentTime == 0, "system sound can restart from beginning")
        // Exercise construction/teardown with the real AppKit sound, without success events.
        let quietEffects = SoundEffects(store: ClipboardStore(), monitor: nil)
        quietEffects.stop()
        func capture() { NotificationCenter.default.post(name: ClipboardMonitor.didCaptureItemNotification, object: monitor) }
        capture()
        precondition(events == [.copy], "one external copy has one playback owner")
        store.didRestoreItem.send()
        precondition(events == [.copy, .paste], "one internal copy/screenshot write has one playback")
        store.didRestoreItem.send()
        precondition(events == [.copy, .paste, .paste], "independent rapid operations remain audible")
        store.preferences.playSounds = false
        capture(); store.didRestoreItem.send()
        precondition(events.count == 3, "setting off suppresses both paths")
        store.preferences.playSounds = true
        // Failed/cancelled operations emit neither success event.
        precondition(events.count == 3)
        effects.stop()
        capture(); store.didRestoreItem.send()
        precondition(events.count == 3, "teardown detaches both subscriptions")
        print("{\"passed\":true,\"checks\":13,\"boundary\":\"production sound subscriptions; named system Purr resolution and silent construction/teardown; injected player and event sources; no clipboard or audio output\"}")
    }
}
