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

/// The one combination the owning row refused during the current recording interval.
///
/// The production recorder (`ShortcutRecorder`) commits a detected combination
/// before the row can veto it, so the veto has to live next to the model: the row
/// writes the combination here, and the view rolls the model back and re-enters
/// the recording state instead of ending it.
@MainActor
final class ReplicaShortcutRejection: ObservableObject {
    var pending: BlinkClipCore.KeyboardShortcut?
}

/// 设置页的一行快捷键录制器。
///
/// 复用 Core 的 `ShortcutRecorder` 模型与 `ShortcutControls` 控件（同一套 120×24
/// 主按钮、同一个已赋值才出现的清除按钮、同一份本地事件监视器），但把「这一次
/// 赋值被这一行拒绝」变成一等状态：**拒绝不会结束录制**，偏好值一个字节都不变，
/// 用户可以直接改按别的组合键。旧实现把冲突文案交给整页共享的 `shortcutError`，
/// 提示离正在编辑的那一行很远，而且核心视图在绑定被拒后会把模型翻回旧值、
/// 顺手退出录制态。
@MainActor
struct ReplicaShortcutRecorder: View {
    @Binding var shortcut: BlinkClipCore.KeyboardShortcut?
    let label: String
    /// 校验类提示（例如 macOS 版本对 Option 组合的兼容提醒）。
    let error: (String) -> Void
    let recordingChanged: (Bool) -> Void
    var allowsClearing = true
    /// 返回非空文案表示这一行不接受该组合；`nil` 表示可以赋值。
    var conflict: ((BlinkClipCore.KeyboardShortcut) -> String?)?
    /// 冲突文案的落点：父视图把它放在**正在编辑的那一行正下方**。
    var conflictChanged: (String?) -> Void = { _ in }

    @StateObject private var model: ShortcutRecorder
    @StateObject private var recordingSession = ReplicaShortcutRecordingSession()
    @State private var rejection = ReplicaShortcutRejection()
    @State private var recordingFlag = false

    init(shortcut: Binding<BlinkClipCore.KeyboardShortcut?>, label: String,
         error: @escaping (String) -> Void,
         recordingChanged: @escaping (Bool) -> Void,
         allowsClearing: Bool = true,
         conflict: ((BlinkClipCore.KeyboardShortcut) -> String?)? = nil,
         conflictChanged: @escaping (String?) -> Void = { _ in }) {
        _shortcut = shortcut
        self.label = label
        self.error = error
        self.recordingChanged = recordingChanged
        self.allowsClearing = allowsClearing
        self.conflict = conflict
        self.conflictChanged = conflictChanged
        let rejection = ReplicaShortcutRejection()
        _rejection = State(initialValue: rejection)
        _model = StateObject(wrappedValue: ShortcutRecorder(shortcut: shortcut.wrappedValue?.originalValue,
                                                           allowsClearing: allowsClearing) { detected in
            guard let detected else {
                rejection.pending = nil
                conflictChanged(nil)
                shortcut.wrappedValue = nil
                return
            }
            guard let converted = BlinkClipCore.KeyboardShortcut(originalValue: detected) else {
                rejection.pending = nil
                conflictChanged(nil)
                shortcut.wrappedValue = nil
                return
            }
            if let conflict, let message = conflict(converted) {
                // 拒绝这次赋值：不写偏好，不动录制区间，只把占用者报给本行。
                rejection.pending = converted
                conflictChanged(message)
                return
            }
            rejection.pending = nil
            conflictChanged(nil)
            shortcut.wrappedValue = converted
        })
    }

    var body: some View {
        let controls = ShortcutControls(presentation: model.presentation(), state: model.state,
                                        begin: { model.beginRecording() },
                                        clear: { model.handleClearKey() },
                                        allowsClearing: allowsClearing)
        return ZStack(alignment: .topTrailing) { controls.shortcutControlView() }
            .id(model.state)
            .accessibilityLabel(ScreenshotSettingsCopy.shortcutAccessibilityLabel(for: label))
            .accessibilityValue(shortcut.map {
                ShortcutFunctions.modifierLabel(verbose: true, modifierRawValue: $0.modifierRawValue)
                    + ShortcutFunctions.displayLabel(keyCode: $0.keyCode)
            } ?? SettingsCopy.trilingual("未设置", "未設定", "Not Set"))
            .onReceive(model.$state) { state in
                // 冲突被拒后模型已经把自己当成「已赋值」；这里翻回真实偏好值，
                // 并立刻重新等键，保持「正在录制」。顺序很关键：先回到真实值再
                // 进入录制态，`previous` 才是用户原来那一条，而不是被拒的组合。
                if rejection.pending != nil, case .assigned = state {
                    let previous = shortcut
                    Task { @MainActor in
                        model.setShortcut(previous?.originalValue)
                        model.beginRecording()
                        rejection.pending = nil
                    }
                }
                updateRecordingFlag(state)
            }
            // 外部重置（恢复默认、恢复全部快捷键）也要把录制器拉回偏好值。
            .onChange(of: shortcut) { _, updated in
                guard rejection.pending == nil else { return }
                model.setShortcut(updated?.originalValue)
            }
            .onReceive(model.$validationError) { value in
                error(value?.localizedDescription ?? "")
            }
            .onDisappear {
                recordingSession.update(false, notify: recordingChanged)
                recordingFlag = false
            }
    }

    /// 「仍在录制」只在被拒的那一次赋值上额外保持：期间不能把全局热键挂回去，
    /// 否则用户接下来想改按的组合可能先被 Carbon 热键吞掉。
    private func updateRecordingFlag(_ state: ShortcutRecorderState) {
        let recording = state.isRecording || rejection.pending != nil
        guard recordingFlag != recording else { return }
        recordingFlag = recording
        recordingSession.update(recording, notify: recordingChanged)
    }
}
