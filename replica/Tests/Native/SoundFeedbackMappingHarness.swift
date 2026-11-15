// Verifies the shipped per-action mapping against the packaged Core bundle:
// copy / cut → CopySound.mp3, paste → PasteSound.mp3, unclassified success → macOS
// Purr. Only loads players and never starts audio output.
import AppKit
import BlinkClipCore
import Combine
import Foundation

@main
struct SoundFeedbackMappingHarness {
    struct Failure: Error { let message: String }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlinkClipSoundMapping-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardStore(directoryURL: directory)
        store.preferences.historyRetentionDays = 0
        defer { store.preferences.playSounds = true }

        // 1. The two files ship inside the Core resource bundle the app copies verbatim.
        guard let copyURL = SoundEffects.bundledURL(for: .copy),
              let cutURL = SoundEffects.bundledURL(for: .cut),
              let pasteURL = SoundEffects.bundledURL(for: .paste) else {
            throw Failure(message: "Bundled feedback audio is missing from the resource bundle")
        }
        try require(copyURL.lastPathComponent == SoundEffects.copySoundFileName, "Copy resolves CopySound.mp3")
        try require(cutURL == copyURL, "Cut resolves the same copy audio")
        try require(pasteURL.lastPathComponent == SoundEffects.pasteSoundFileName, "Paste resolves PasteSound.mp3")
        try require(SoundEffects.bundledURL(for: .success) == nil, "Unclassified success has no bundled file")
        for url in [copyURL, pasteURL] {
            try require(url.deletingLastPathComponent().lastPathComponent == "BlinkClip_BlinkClipCore.bundle",
                        "Feedback audio ships inside the Core resource bundle: \(url.path)")
            let data = try Data(contentsOf: url)
            try require(data.count >= 4096, "Feedback audio is not a stub: \(url.lastPathComponent)")
            try require(data.prefix(3) == Data("ID3".utf8), "Feedback audio is a tagged MP3: \(url.lastPathComponent)")
            guard let player = NSSound(contentsOf: url, byReference: true) else {
                throw Failure(message: "NSSound cannot open \(url.lastPathComponent)")
            }
            try require(player.duration > 0.3 && player.duration < 3,
                        "\(url.lastPathComponent) is a short UI tone, not a long clip")
            try require(!player.isPlaying, "Resolving a file never starts audio output")
        }

        // 2. Actions reach the production subscriber with the right feedback class.
        var events: [SoundEffects.Feedback] = []
        let recorder = SoundEffects(store: store, monitor: nil, playback: { events.append($0) })
        defer { recorder.stop() }
        SoundEffects.withFeedback(.copy) { store.didRestoreItem.send() }
        try require(events == [.copy], "A declared copy produces exactly one copy feedback")
        SoundEffects.withFeedback(.cut) { store.didRestoreItem.send() }
        try require(events == [.copy, .cut], "A declared cut produces exactly one cut feedback")
        SoundEffects.withFeedback(.paste) { store.didRestoreItem.send() }
        try require(events == [.copy, .cut, .paste], "A declared paste produces exactly one paste feedback")
        store.didRestoreItem.send()
        try require(events == [.copy, .cut, .paste, .success], "An unclassified restore keeps the legacy tone")
        store.preferences.playSounds = false
        SoundEffects.withFeedback(.copy) { store.didRestoreItem.send() }
        SoundEffects.withFeedback(.cut) { store.didRestoreItem.send() }
        SoundEffects.withFeedback(.paste) { store.didRestoreItem.send() }
        try require(events.count == 4, "playSounds off suppresses copy, cut and paste feedback")
        store.preferences.playSounds = true
        SoundEffects.withFeedback(.paste) { store.didRestoreItem.send() }
        try require(events.count == 5 && events.last == .paste, "Re-enabling playSounds restores feedback")

        // 3. Stack 粘贴：`AppMain.stackPasteHotKey.action` 直接调 `AppMain.paste(...)`，不经过
        //    `ReplicaUIController.paste` 的 `.paste` 声明，所以调用点自己包了一层。这里用同一条
        //    store 写入（有 restoreItems 与只有 ids 两条分支）验证包装后确实归类为粘贴。
        let board = NSPasteboard(name: .init("BlinkClipSoundMapping-\(UUID())"))
        defer { board.releaseGlobally() }
        let stackItem = ClipboardItem(createdAt: Date(timeIntervalSince1970: 1_700_000_200),
                                      plainText: "stack paste fixture")
        store.items = [stackItem]
        events.removeAll()
        try SoundEffects.withFeedback(.paste) {
            try store.writeToPasteboard(ids: [stackItem.id], pasteboard: board, options: [])
        }
        try require(events == [.paste], "Stack paste by ids inside the declaration is a paste tone, not the legacy tone")
        try require(board.pasteboardItems?.isEmpty == false, "Stack paste wrote the clipboard")
        events.removeAll()
        try SoundEffects.withFeedback(.paste) {
            try store.writeToPasteboard(restoreItems: [ClipboardRestoreItem(item: stackItem)],
                                        pasteboard: board, options: [])
        }
        try require(events == [.paste], "Stack paste by restore item inside the declaration is a paste tone")
        events.removeAll()
        try store.writeToPasteboard(ids: [stackItem.id], pasteboard: board, options: [])
        try require(events == [.success], "Without a declaration the same write stays unclassified")

        // 4. One cached instance per file, so repeated triggers restart instead of layering.
        let effects = SoundEffects(store: store, monitor: nil)
        defer { effects.stop() }
        guard let copyPlayer = effects.player(for: .copy), let pastePlayer = effects.player(for: .paste) else {
            throw Failure(message: "Bundled players did not load from the resource bundle")
        }
        try require(effects.player(for: .copy) === copyPlayer, "Copy reuses one cached player")
        try require(effects.player(for: .cut) === copyPlayer, "Cut reuses the copy player instead of adding a voice")
        try require(effects.player(for: .paste) === pastePlayer, "Paste reuses one cached player")
        try require(pastePlayer !== copyPlayer, "Paste does not share the copy player")
        try require(!copyPlayer.isPlaying && !pastePlayer.isPlaying, "No audio output while resolving")
        try require(effects.player(for: .success)?.name == NSSound.Name("Purr"),
                    "Unclassified success still resolves macOS Purr")
        print(String(data: try JSONSerialization.data(withJSONObject: [
            "passed": true,
            "copy_sound": copyURL.lastPathComponent,
            "cut_sound": cutURL.lastPathComponent,
            "paste_sound": pasteURL.lastPathComponent,
            "copy_bytes": try Data(contentsOf: copyURL).count,
            "paste_bytes": try Data(contentsOf: pasteURL).count,
            "feedback_events": events.map { String(describing: $0) },
            "stack_paste": "AppMain's direct paste is declared .paste at the call site; the same write without a declaration stays .success",
            "scope": "Production SoundEffects and ClipboardStore; packaged BlinkClip_BlinkClipCore.bundle; a private pasteboard and an injected playback recorder. Loads players without emitting audio."
        ], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
