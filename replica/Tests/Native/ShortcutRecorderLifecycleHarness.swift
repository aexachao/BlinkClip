import AppKit
import Foundation
import BlinkClipCore

/// Compile with the production UI/ShortcutRecorder.swift and the fresh BlinkClipCore target.
@main
struct ShortcutRecorderLifecycleHarness {
    enum Failure: Error { case assertion(String) }

    @MainActor static func main() throws {
        _ = NSApplication.shared
        var checks = 0
        func require(_ value: Bool, _ message: String) throws {
            guard value else { throw Failure.assertion(message) }
            checks += 1
        }

        let original = ShortcutValue(keyCode: 0, internalModifiers: NSEvent.ModifierFlags.command.rawValue)
        var requiredDetections: [ShortcutValue?] = []
        let required = ShortcutRecorder(shortcut: original, allowsClearing: false) {
            requiredDetections.append($0)
        }
        required.handleClearKey()
        try require(required.state == .assigned(original), "Required assigned value cannot be removed")
        try require(requiredDetections.isEmpty, "A rejected clear must not write nil through the binding")
        required.startRecording()
        try require(required.state.isRecording, "Required recorder starts recording")
        let delete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, characters: "\u{7f}",
                                      charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
        _ = required.handleKeyEvent(delete)
        try require(required.state == .assigned(original), "Delete cancels required recording and preserves its value")
        try require(requiredDetections.isEmpty, "Delete cancellation does not emit a detection")

        func commandEvent(_ key: String) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                             windowNumber: 0, context: nil, characters: key,
                             charactersIgnoringModifiers: key, isARepeat: false,
                             keyCode: UInt16(ShortcutFunctions.keyCodeForKey(key)))!
        }
        for key in ["w", "q"] {
            required.startRecording()
            let event = commandEvent(key)
            let forwarded = required.handleKeyEvent(event)
            try require(forwarded === event, "Required Command-\(key) passes through the original event")
            try require(required.state == .assigned(original), "Required Command-\(key) ends recording and preserves its value")
            try require(requiredDetections.isEmpty, "Required Command-\(key) does not change the binding")
        }

        var optionalDetections: [ShortcutValue?] = []
        let optional = ShortcutRecorder(shortcut: original) { optionalDetections.append($0) }
        optional.handleClearKey()
        try require(optional.state == .unassigned, "Default recorder still allows clearing")
        try require(optionalDetections.count == 1 && optionalDetections[0] == nil, "Default clear writes nil")

        for key in ["w", "q"] {
            var detections: [ShortcutValue?] = []
            let optionalClosing = ShortcutRecorder(shortcut: original) { detections.append($0) }
            optionalClosing.startRecording()
            let event = commandEvent(key)
            let forwarded = optionalClosing.handleKeyEvent(event)
            try require(forwarded === event, "Optional Command-\(key) passes through the original event")
            try require(optionalClosing.state == .unassigned, "Optional Command-\(key) retains the legacy model state")
            try require(detections.isEmpty, "Optional Command-\(key) retains the legacy binding behavior")
        }

        let a = ReplicaShortcutRecordingSession()
        let b = ReplicaShortcutRecordingSession()
        let inactive = ReplicaShortcutRecordingSession()
        var transitions: [String] = []
        func notify(_ name: String) -> (Bool) -> Void {
            { transitions.append(name + ($0 ? "+" : "-")) }
        }
        inactive.update(false, notify: notify("inactive"))
        a.update(true, notify: notify("A"))
        a.update(true, notify: notify("A"))
        b.update(true, notify: notify("B"))
        b.update(false, notify: notify("B"))
        b.update(false, notify: notify("B"))
        inactive.update(false, notify: notify("inactive"))
        try require(a.isRecording && !b.isRecording, "Ending B or an inactive row does not end A")
        try require(transitions == ["A+", "B+", "B-"], "Repeated state/disappearance notifications are ignored")
        a.update(false, notify: notify("A"))
        a.update(false, notify: notify("A"))
        try require(transitions == ["A+", "B+", "B-", "A-"], "Each row ends only its own recording interval once")
        a.update(true, notify: notify("A"))
        a.update(false, notify: notify("A"))
        try require(transitions.suffix(2) == ["A+", "A-"], "A row can own a subsequent interval")

        let report: [String: Any] = ["passed": true, "checks": checks,
            "scope": "Production required/optional recorder clear and Command-W/Q behavior plus per-row recording session ownership; no UI click or global Carbon test"]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
    }
}
