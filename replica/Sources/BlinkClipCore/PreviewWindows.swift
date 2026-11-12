import AppKit
import Combine
import Foundation

@MainActor
public enum WindowVisualEffects {
    /// collect direct NSVisualEffectView siblings and return the first.
    public static func visualEffectView(window: NSWindow) -> NSVisualEffectView? {
        guard let parent = window.contentView?.superview else { return nil }
        return parent.subviews.compactMap { $0 as? NSVisualEffectView }.first
    }
}

@MainActor
public final class PreviewWindow: NSPanel {
    /// The recovered original calls NSPanel's designated initializer.
    public init(recovered: Void = ()) {
        super.init(contentRect: .zero, styleMask: .init(rawValue: 0x801b),
                   backing: .buffered, defer: true)
        animationBehavior = .none
        WindowVisualEffects.visualEffectView(window: self)?.blendingMode = .behindWindow
        WindowVisualEffects.visualEffectView(window: self)?.material = .popover
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        level = .init(rawValue: 3)
    }

    /// activation precedes the superclass key-window transition.
    public override func becomeKey() {
        NSApp.activate(ignoringOtherApps: true)
        super.becomeKey()
    }
}

public struct TopmostPreview: Equatable {
    public var itemIdentifier: String
    public var isEditing: Bool

    public init(itemIdentifier: String, isEditing: Bool) {
        self.itemIdentifier = itemIdentifier
        self.isEditing = isEditing
    }

    /// compare the string before the editing flag.
    public static func isEqual(_ lhs: Self, _ rhs: Self) -> Bool {
        guard lhs.itemIdentifier == rhs.itemIdentifier else { return false }
        return lhs.isEditing == rhs.isEditing
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { isEqual(lhs, rhs) }
}

/// Original entries use Core Data object-ID URLs as AnyHashable identities.
/// The independent replica supplies its stable local item identity at the boundary.
@MainActor
public final class PreviewWindowRegistry: NSObject, ObservableObject {
    private struct Entry {
        var itemIdentity: AnyHashable
        var itemIdentifier: String
        var window: PreviewWindow
        var isEditing: Bool
    }

    private var entries: [Entry] = []
    /// Replica appearance propagation; this adapter does not represent an original function.
    public var windows: [PreviewWindow] { entries.map(\.window) }
    public var popoverItemIdentifier: String?
    @Published public private(set) var topmost: TopmostPreview?
    public var onAllPreviewsClosed: (() -> Void)?

    /// the empty registry and published nil state.
    public override init() { super.init() }

    /// return the first window with an equal stable item identity.
    public func windowForItem(itemIdentity: AnyHashable) -> PreviewWindow? {
        entries.first { $0.itemIdentity == itemIdentity }?.window
    }

    /// replace the item's window, append, observe closing, publish topmost.
    public func registerPreviewWindow(window: PreviewWindow, itemIdentity: AnyHashable,
                          itemIdentifier: String, isEditing: Bool) {
        windowForItem(itemIdentity: itemIdentity)?.close()
        entries.removeAll { $0.itemIdentity == itemIdentity }
        entries.append(Entry(itemIdentity: itemIdentity, itemIdentifier: itemIdentifier,
                             window: window, isEditing: isEditing))
        NotificationCenter.default.addObserver(self, selector: #selector(handleWindowWillClose(_:)),
                                              name: NSWindow.willCloseNotification, object: window)
        updateTopmostPreview()
    }

    /// update the last matching identifier; publish only if it is topmost.
    public func setEditingState(isEditing: Bool, itemIdentifier: String) {
        guard let index = entries.lastIndex(where: { $0.itemIdentifier == itemIdentifier }) else { return }
        entries[index].isEditing = isEditing
        if index == entries.count - 1 { updateTopmostPreview() }
    }

    /// detached windows take precedence over a nonediting popover.
    public func updateTopmostPreview() {
        if let last = entries.last {
            topmost = TopmostPreview(itemIdentifier: last.itemIdentifier, isEditing: last.isEditing)
        } else if let popoverItemIdentifier {
            topmost = TopmostPreview(itemIdentifier: popoverItemIdentifier, isEditing: false)
        } else { topmost = nil }
    }

    /// remove all equal windows, then notify the nonempty-to-empty transition.
    public func removePreviewWindow(window: PreviewWindow) {
        let previousCount = entries.count
        entries.removeAll { $0.window.isEqual(window) }
        updateTopmostPreview()
        if previousCount > 0, entries.isEmpty { onAllPreviewsClosed?() }
    }

    /// unrelated or absent notification objects have no effect.
    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? PreviewWindow else { return }
        removePreviewWindow(window: window)
    }

    /// unregister the selector observations before object destruction.
    deinit { NotificationCenter.default.removeObserver(self) }
}
