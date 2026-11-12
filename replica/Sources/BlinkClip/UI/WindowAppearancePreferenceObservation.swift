import Combine
import Foundation

/// Only these preference fields affect window appearance or panel geometry.
struct WindowAppearancePreferences: Equatable {
    let appearance: String
    let panelHeight: Double

    init(appearance: String, panelHeight: Double) {
        self.appearance = ["light", "dark"].contains(appearance) ? appearance : "system"
        self.panelHeight = panelHeight.isFinite && panelHeight > 0 ? panelHeight : 332
    }
}

@MainActor
final class WindowAppearancePreferenceObservation {
    private var observation: AnyCancellable?
    private var applied: WindowAppearancePreferences
    private var pending: WindowAppearancePreferences?
    private var scheduled = false
    private let applyAppearance: () -> Void
    private let positionPanel: () -> Void

    init(initial: WindowAppearancePreferences,
         changes: AnyPublisher<WindowAppearancePreferences, Never>,
         applyAppearance: @escaping () -> Void,
         positionPanel: @escaping () -> Void) {
        applied = initial
        self.applyAppearance = applyAppearance
        self.positionPanel = positionPanel
        observation = changes.removeDuplicates().sink { [weak self] value in
            self?.enqueue(value)
        }
        applyAppearance()
    }

    private func enqueue(_ value: WindowAppearancePreferences) {
        // @Published emits before the store assignment finishes. Defer UI work,
        // and use the latest preference projection if several changes arrive.
        if scheduled { pending = value; return }
        guard value != applied else { return }
        pending = value
        scheduled = true
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    private func flush() {
        scheduled = false
        guard let next = pending else { return }
        pending = nil
        let appearanceChanged = next.appearance != applied.appearance
        let heightChanged = next.panelHeight != applied.panelHeight
        applied = next
        if appearanceChanged {
            // The existing appearance operation also positions a visible panel.
            applyAppearance()
        } else if heightChanged {
            positionPanel()
        }
    }
}
