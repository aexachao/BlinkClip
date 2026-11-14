import SwiftUI
import BlinkClipCore

/// A row releases only the recording interval that it started, even if removal and cancellation overlap.
@MainActor
final class ReplicaShortcutRecordingSession: ObservableObject {
    private(set) var isRecording = false

    func update(_ recording: Bool, notify: (Bool) -> Void) {
        guard isRecording != recording else { return }
        isRecording = recording
        notify(recording)
    }
}

@MainActor
struct ReplicaShortcutRecorder: View {
    @Binding var shortcut: BlinkClipCore.KeyboardShortcut?
    let label: String
    let error: (String) -> Void
    let recordingChanged: (Bool) -> Void
    var allowsClearing = true
    @StateObject private var recordingSession = ReplicaShortcutRecordingSession()

    var body: some View {
        ShortcutRecorderView(shortcut: Binding(get: { shortcut?.originalValue }, set: { value in
            shortcut = value.flatMap { BlinkClipCore.KeyboardShortcut(originalValue: $0) }
        }), errorChanged: error, recordingChanged: { recording in
            recordingSession.update(recording, notify: recordingChanged)
        }, allowsClearing: allowsClearing, emptyLabel: SettingsCopy.trilingual("未设置", "未設定", "Not Set"))
        .accessibilityLabel(ScreenshotSettingsCopy.shortcutAccessibilityLabel(for: label))
        .accessibilityValue(shortcut.map {
            ShortcutFunctions.modifierLabel(verbose: true, modifierRawValue: $0.modifierRawValue)
                + ShortcutFunctions.displayLabel(keyCode: $0.keyCode)
        } ?? SettingsCopy.trilingual("未设置", "未設定", "Not Set"))
        .onDisappear { recordingSession.update(false, notify: recordingChanged) }
    }
}
