import AppKit
import SwiftUI

@MainActor
struct HistoryRetentionPicker: NSViewRepresentable {
    let days: Int
    let onCommit: (Int) throws -> Void
    func makeNSView(context: Context) -> HistoryCapacityControl { HistoryCapacityControl() }
    func updateNSView(_ view: HistoryCapacityControl, context: Context) {
        view.onCommit = onCommit
        view.setDays(days)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HistoryCapacityControl, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: nsView.requiredHeight)
    }
}

/// Seven explicit choices. Existing values are never changed merely by opening settings.
@MainActor
final class HistoryCapacityControl: NSView {
    static let presets = [1, 3, 7, 15, 30, 60, 0]
    let optionButtons: [HistoryRetentionOptionButton]
    let legacyLabel = NSTextField(wrappingLabelWithString: "")
    let explanation = NSTextField(wrappingLabelWithString: "")
    let errorLabel = NSTextField(wrappingLabelWithString: "")
    var onCommit: ((Int) throws -> Void)?
    var confirmShortening: ((Int, @escaping (Bool) -> Void) -> Void)?
    private(set) var currentDays = 7
    private(set) var errorMessage = ""
    private(set) var isAwaitingConfirmation = false
    private var generation = 0
    var hasLegacyPeriod: Bool { currentDays > 0 && !Self.presets.contains(currentDays) }
    private(set) var intrinsicInvalidations = 0
    private var measuredWidth: CGFloat = 400
    private var lastRequiredHeight: CGFloat = 0
    private(set) var activeAlert: NSAlert?
    private var alertKeyMonitor: Any?
    private var parentCloseObserver: NSObjectProtocol?
    var requiredHeight: CGFloat { contentHeight(width: measuredWidth) }

    private func textHeight(_ field: NSTextField, width: CGFloat) -> CGFloat {
        guard !field.stringValue.isEmpty else { return 0 }
        return ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: max(1, width), height: 10000)).height ?? 0)
    }
    private func contentHeight(width: CGFloat) -> CGFloat {
        let legacy = hasLegacyPeriod ? textHeight(legacyLabel, width: width) + 8 : 0
        let error = errorMessage.isEmpty ? 0 : textHeight(errorLabel, width: width) + 8
        return 106 + legacy + textHeight(explanation, width: width) + error
    }
    private func updateMeasuredHeight() {
        let next = contentHeight(width: measuredWidth)
        guard next != lastRequiredHeight else { return }
        lastRequiredHeight = next
        intrinsicInvalidations += 1
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override init(frame frameRect: NSRect) {
        optionButtons = Self.presets.map { HistoryRetentionOptionButton(days: $0) }
        super.init(frame: frameRect)
        for button in optionButtons {
            button.target = self
            button.action = #selector(optionPressed(_:))
            addSubview(button)
        }
        for label in [legacyLabel, explanation, errorLabel] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            addSubview(label)
        }
        legacyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        errorLabel.setAccessibilityIdentifier("history-retention-error")
        setAccessibilityRole(.group)
        setAccessibilityLabel(HistoryRetentionCopy.text("历史记录保留时间", "History retention"))
        updateSelection()
    }
    required init?(coder: NSCoder) { nil }
    deinit {
        if let token = alertKeyMonitor { NSEvent.removeMonitor(token) }
        if let token = parentCloseObserver { NotificationCenter.default.removeObserver(token) }
    }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: requiredHeight) }
    override func layout() {
        super.layout()
        for (index, button) in optionButtons.enumerated() {
            let row = index < 4 ? 0 : 1
            let count = row == 0 ? 4 : 3
            let column = row == 0 ? index : index - 4
            let width = max(0, (bounds.width - CGFloat(count - 1) * 8) / CGFloat(count))
            button.frame = NSRect(x: CGFloat(column) * (width + 8), y: CGFloat(row) * 52, width: width, height: 44)
        }
        if bounds.width > 0 && measuredWidth != bounds.width {
            measuredWidth = bounds.width
            updateMeasuredHeight()
        }
        let legacyHeight = hasLegacyPeriod ? textHeight(legacyLabel, width: bounds.width) : 0
        legacyLabel.frame = NSRect(x: 0, y: 106, width: bounds.width, height: legacyHeight)
        let textTop: CGFloat = 106 + (hasLegacyPeriod ? legacyHeight + 8 : 0)
        let explanationHeight = textHeight(explanation, width: bounds.width)
        explanation.frame = NSRect(x: 0, y: textTop, width: bounds.width, height: explanationHeight)
        errorLabel.frame = NSRect(x: 0, y: textTop + explanationHeight + 8, width: bounds.width, height: errorMessage.isEmpty ? 0 : textHeight(errorLabel, width: bounds.width))
    }
    func setDays(_ days: Int) {
        guard days != currentDays else { updateSelection(); return }
        currentDays = days
        generation += 1
        if !isAwaitingConfirmation { showError("") }
        updateSelection()
    }
    private func updateSelection() {
        for button in optionButtons {
            let selected = button.tag == (currentDays <= 0 ? 0 : currentDays)
            let state: NSControl.StateValue = selected ? .on : .off
            if button.state != state { button.state = state; button.setAccessibilityValue(selected ? 1 : 0); button.needsDisplay = true }
            if button.isEnabled != !isAwaitingConfirmation { button.isEnabled = !isAwaitingConfirmation; button.needsDisplay = true }
        }
        legacyLabel.isHidden = !hasLegacyPeriod
        let legacyText = HistoryRetentionCopy.text("当前：\(currentDays) 天（原设置）", "Current: \(currentDays) days (existing setting)")
        if legacyLabel.stringValue != legacyText { legacyLabel.stringValue = legacyText }
        let explanationText = currentDays > 0
            ? HistoryRetentionCopy.text("按记录进入历史的时间计算；只清理过期且未加入分组的内容。", "Retention starts when an item enters history. Only expired items outside groups are removed.")
            : HistoryRetentionCopy.text("不按时间自动清理历史记录，仍可手动删除。", "History is not removed based on age. You can still delete it manually.")
        if explanation.stringValue != explanationText { explanation.stringValue = explanationText }
        updateMeasuredHeight()
    }
    @objc private func optionPressed(_ sender: NSButton) { propose(sender.tag) }
    func propose(_ days: Int) {
        updateSelection()
        guard !isAwaitingConfirmation else { return }
        guard days != currentDays else { showError(""); return }
        guard Self.presets.contains(days) else { return }
        showError("")
        let previous = currentDays
        let ticket = generation
        if HistoryRetentionCopy.isShorter(from: previous, to: days) {
            isAwaitingConfirmation = true
            updateSelection()
            let completion: (Bool) -> Void = { [weak self] confirmed in
                guard let self else { return }
                self.isAwaitingConfirmation = false
                guard ticket == self.generation, previous == self.currentDays else {
                    self.showError(HistoryRetentionCopy.text("保留时间已在其他位置更改，请重新选择。", "Retention changed elsewhere. Choose the period again."))
                    self.updateSelection()
                    return
                }
                if confirmed { self.commit(days) } else { self.updateSelection() }
            }
            if let confirmShortening { confirmShortening(days, completion) }
            else { presentShortening(days, completion: completion) }
        } else { commit(days) }
    }
    private func commit(_ days: Int) {
        do {
            guard let onCommit else { throw HistoryRetentionSaveError.unavailable }
            try onCommit(days)
            currentDays = days
            generation += 1
            showError("")
        } catch {
            showError(HistoryRetentionCopy.text("未能保存：", "Could not save: ") + error.localizedDescription)
        }
        updateSelection()
    }
    private func showError(_ message: String) {
        errorMessage = message
        errorLabel.stringValue = message
        errorLabel.toolTip = message
        errorLabel.isHidden = message.isEmpty
        updateMeasuredHeight()
    }
    private func presentShortening(_ days: Int, completion: @escaping (Bool) -> Void) {
        guard let parent = window, parent.attachedSheet == nil else { completion(false); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = HistoryRetentionCopy.text("缩短历史保留时间？", "Shorten history retention?")
        alert.informativeText = HistoryRetentionCopy.shorteningWarning(days)
        // Cancel is the safe default. AppKit supplies the icon, sizing and button layout.
        alert.addButton(withTitle: HistoryRetentionCopy.text("取消", "Cancel"))
        alert.addButton(withTitle: HistoryRetentionCopy.text("缩短并清理", "Shorten and Remove"))
        activeAlert = alert
        parentCloseObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: parent, queue: .main) { [weak self, weak parent] _ in
            MainActor.assumeIsolated {
                if let sheet = self?.activeAlert?.window { parent?.endSheet(sheet, returnCode: .alertFirstButtonReturn) }
            }
        }
        alert.beginSheetModal(for: parent) { [weak self] response in
            guard let self else { completion(false); return }
            let retainedAlert = self.activeAlert
            self.finishAlert()
            completion(response == .alertSecondButtonReturn)
            withExtendedLifetime(retainedAlert) {}
        }
        // NSAlert configures equivalents during presentation; apply our safe default afterwards.
        alert.window.defaultButtonCell = alert.buttons[0].cell as? NSButtonCell
        alert.buttons[0].keyEquivalent = "\r"
        alert.buttons[1].keyEquivalent = ""
        // Native NSAlert has one key equivalent per button. Keep both Enter variants and
        // Escape safe, scoped exclusively to this alert's window (never global key events).
        alertKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak parent] event in
            guard let self, let sheet = self.activeAlert?.window, event.window === sheet,
                  [36, 76, 53].contains(Int(event.keyCode)) else { return event }
            parent?.endSheet(sheet, returnCode: .alertFirstButtonReturn)
            return nil
        }
    }
    private func finishAlert() {
        if let token = alertKeyMonitor { NSEvent.removeMonitor(token); alertKeyMonitor = nil }
        if let token = parentCloseObserver { NotificationCenter.default.removeObserver(token); parentCloseObserver = nil }
        activeAlert = nil
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window, let parent = window, let sheet = activeAlert?.window {
            parent.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        }
        super.viewWillMove(toWindow: newWindow)
    }

}

/// Native button actions/accessibility, with the app's quiet accent selection style.
@MainActor
final class HistoryRetentionOptionButton: NSButton {
    init(days: Int) {
        super.init(frame: .zero)
        tag = days
        title = HistoryRetentionCopy.option(days)
        setButtonType(.momentaryPushIn)
        isBordered = false
        focusRingType = .exterior
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(HistoryRetentionCopy.period(days))
        setAccessibilityIdentifier("history-retention-\(days)")
    }
    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if [" ", "\r", "\u{3}"].contains(event.charactersIgnoringModifiers ?? "") { performClick(nil) }
        else { super.keyDown(with: event) }
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        let selected = state == .on
        let accent = NSColor.controlAccentColor
        (selected ? accent.withAlphaComponent(isEnabled ? 0.17 : 0.08) : NSColor.controlBackgroundColor.withAlphaComponent(isEnabled ? 0.7 : 0.35)).setFill()
        path.fill()
        (selected ? accent : NSColor.separatorColor).setStroke()
        path.lineWidth = selected ? 1.5 : 1
        path.stroke()
        if isHighlighted { NSColor.labelColor.withAlphaComponent(0.06).setFill(); path.fill() }
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let color = isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: selected ? .semibold : .regular), .foregroundColor: color, .paragraphStyle: style]
        (title as NSString).draw(in: NSRect(x: 12, y: (bounds.height - 17) / 2, width: bounds.width - 24, height: 18), withAttributes: attrs)
        if window?.firstResponder === self {
            NSGraphicsContext.saveGraphicsState()
            NSFocusRingPlacement.only.set()
            path.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}

private enum HistoryRetentionSaveError: LocalizedError {
    case unavailable
    var errorDescription: String? { HistoryRetentionCopy.text("保存暂不可用，请重试。", "Saving is unavailable. Try again.") }
}

