import SwiftUI

@MainActor
public struct ShortcutRecorderView: View {
    @StateObject private var model: ShortcutRecorder
    @Binding private var shortcut: ShortcutValue?
    private let errorChanged: (String) -> Void
    private let recordingChanged: (Bool) -> Void
    private let allowsClearing: Bool
    private let emptyLabel: String?

    public init(shortcut: Binding<ShortcutValue?>,
                errorChanged: @escaping (String) -> Void = { _ in },
                recordingChanged: @escaping (Bool) -> Void = { _ in },
                allowsClearing: Bool = true,
                emptyLabel: String? = nil) {
        _shortcut = shortcut
        // StateObject's autoclosure preserves the reference factory's lazy
        // binding read and the model's identity across parent view updates.
        _model = StateObject(wrappedValue: Self.makeShortcutRecorder(shortcut, allowsClearing: allowsClearing))
        self.errorChanged = errorChanged
        self.recordingChanged = recordingChanged
        self.allowsClearing = allowsClearing
        self.emptyLabel = emptyLabel
    }

    public static func makeShortcutRecorder(_ shortcut: Binding<ShortcutValue?>,
                                  allowsClearing: Bool = true) -> ShortcutRecorder {
        ShortcutRecorder(shortcut: shortcut.wrappedValue, allowsClearing: allowsClearing) { value in
            shortcut.wrappedValue = value
        }
    }

    public func okButton() -> some View {
        let model = self.model
        return Button(ShortcutMessages.value("general.action.ok")) { model.clearValidationError() }
    }

    public func recorderView() -> some View {
        let model = self.model
        let presentation = !model.state.isRecording && shortcut == nil && emptyLabel != nil
            ? (emptyLabel!, nil as String?, false) : model.presentation()
        let controls = ShortcutControls(presentation: presentation, state: model.currentState(),
            begin: { model.beginRecording() }, clear: { model.handleClearKey() },
            allowsClearing: allowsClearing)
        let content = ZStack(alignment: .topTrailing) { controls.shortcutControlView() }
            .id(model.state)
            .onChange(of: shortcut, initial: false) { _, updated in
                // External resets must also remove a monitor owned by an in-progress recording.
                model.updateState(newState: updated.map(ShortcutRecorderState.assigned) ?? .unassigned)
            }
        let title = Text(model.currentValidationError()?.localizedDescription ?? "")
        let isPresented = model.currentValidationError() != nil
        return content.alert(title, isPresented: .constant(isPresented)) { okButton() }
    }

    public var body: some View {
        recorderView()
            .onChange(of: model.state.isRecording, initial: false) { _, value in recordingChanged(value) }
            .onChange(of: model.state, initial: false) { _, state in
                // An application binding may reject a conflicting assignment.
                // Keep the label consistent with the preference it actually kept.
                if case let .assigned(detected) = state, shortcut != detected {
                    model.setShortcut(shortcut)
                }
            }
            .onReceive(model.$validationError) { value in errorChanged(value?.localizedDescription ?? "") }
            .onDisappear {
                if model.state.isRecording { model.startRecording() }
            }
    }
}
