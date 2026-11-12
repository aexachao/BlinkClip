import AppKit
import SwiftUI

@MainActor
public enum ShortcutControlFunctions {
    /// Unknown characters are omitted, as in the original compact-map/reduce.
    public static func modifierSymbolsText(_ modifiers: String) -> Text {
        let symbols: [Character: String] = ["⌃": "control", "⌥": "option",
                                             "⇧": "shift", "⌘": "command"]
        return modifiers.reduce(Text("")) { text, character in
            guard let name = symbols[character] else { return text }
            return text + Text(Image(systemName: name))
        }
    }

    @ViewBuilder
    public static func presentationText(_ presentation: (String, String?, Bool)) -> some View {
        if presentation.2 {
            modifierSymbolsText(presentation.0).font(.footnote)
            Text(presentation.1 ?? "").font(.body)
        } else {
            Text(presentation.0).font(.body)
        }
    }

    public static func makeClearIcon() -> some View {
        Image(systemName: "xmark").font(.caption2)
    }

    @ViewBuilder
    public static func presentationLabel(_ presentation: (String, String?, Bool), recording: Bool) -> some View {
        let label = HStack(spacing: 1) { presentationText(presentation) }
        if recording { label.help(ShortcutMessages.value("general.action.cancel")) }
        else { label }
    }
}

public struct ShortcutPrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func styledButtonLabel(_ configuration: Configuration) -> some View {
        let outline = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return configuration.label
            .font(.body)
            .frame(width: 120, height: 24)
            .background(Color(nsColor: .controlColor))
            .clipShape(outline)
            .overlay(outline.stroke(.separator, lineWidth: 1))
    }

    public func makeBody(configuration: Configuration) -> some View { styledButtonLabel(configuration) }
}

public struct ShortcutRemoveButtonStyle: ButtonStyle {
    public init() {}

    public func styledLabel(_ configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(.primary.opacity(configuration.isPressed ? 0.5 : 0.85))
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }

    public func makeBody(configuration: Configuration) -> some View { styledLabel(configuration) }
}

/// The recovered label, primary style and assigned-only remove control.
@MainActor
public struct ShortcutControls: View {
    public let presentation: (String, String?, Bool)
    public let state: ShortcutRecorderState
    public let begin: () -> Void
    public let clear: () -> Void
    public let allowsClearing: Bool

    public init(presentation: (String, String?, Bool), state: ShortcutRecorderState,
                begin: @escaping () -> Void, clear: @escaping () -> Void,
                allowsClearing: Bool = true) {
        self.presentation = presentation
        self.state = state
        self.begin = begin
        self.clear = clear
        self.allowsClearing = allowsClearing
    }

    @ViewBuilder
    public func shortcutControlView() -> some View {
        Button(action: begin) {
            ShortcutControlFunctions.presentationLabel(presentation, recording: state.isRecording)
        }
        .buttonStyle(ShortcutPrimaryButtonStyle())
        if allowsClearing, case .assigned = state {
            Button(action: clear) { ShortcutControlFunctions.makeClearIcon() }
                .buttonStyle(ShortcutRemoveButtonStyle())
                .help(ShortcutRecorder.removeTitle)
        }
    }

    public var body: some View { ZStack(alignment: .topTrailing) { shortcutControlView() } }
}
