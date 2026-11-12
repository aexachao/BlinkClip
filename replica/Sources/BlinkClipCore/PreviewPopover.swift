import AppKit
import Combine
import Foundation

/// Native popover lifecycle recovered from ItemCollectionView.PreviewPopover.
/// Content rendering and inline editing are supplied by the replica's item-view adapter.
@MainActor
public final class PreviewPopover: NSPopover, NSPopoverDelegate {
    public static let mainWindowWillCloseNotification = Notification.Name("mainWindowWillClose")
    public private(set) var isDisplayed = false
    public private(set) var itemIdentity: AnyHashable?
    public private(set) var itemIdentifier: String?
    public var onWillClose: (() -> Void)?
    public var makeContentView: ((_ input: ClipboardRestoreItem) -> ItemPreviewView?)?
    private var item: ClipboardRestoreItem?
    private let registry: PreviewWindowRegistry
    private let isScreenSharingContentVisible: () -> Bool
    private var visibilityObservation: AnyCancellable?

    public init(registry: PreviewWindowRegistry,
                isScreenSharingContentVisible: @escaping () -> Bool,
                visibilityChanges: AnyPublisher<Bool, Never>) {
        self.registry = registry
        self.isScreenSharingContentVisible = isScreenSharingContentVisible
        super.init()
        behavior = .transient
        animates = true
        delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(close),
                                              name: Self.mainWindowWillCloseNotification, object: nil)
        visibilityObservation = visibilityChanges.prepend(isScreenSharingContentVisible())
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateSharingType() }
            }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The recovered display mechanics, after the item-view factory returns.
    public func show(itemIdentity: AnyHashable, itemIdentifier: String, input: ClipboardRestoreItem,
                     contentView: NSView, relativeTo anchor: NSView) {
        self.itemIdentity = itemIdentity
        self.itemIdentifier = itemIdentifier
        item = input
        registry.windowForItem(itemIdentity: itemIdentity)?.close()
        if let preview = contentView as? ItemPreviewView {
            preview.onBeginEditing = { [weak self] in
                self?.detachForEditingIfNeeded(itemIdentity: input.previewIdentity)
            }
        }
        let controller = NSViewController()
        controller.preferredContentSize = contentView.frame.size
        controller.view = contentView
        contentViewController = controller
        show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        animates = false
        anchor.window?.makeFirstResponder(nil)
    }

    /// only the content controller's actual window is affected.
    public func updateSharingType() {
        guard let window = contentViewController?.view.window else { return }
        window.sharingType = isScreenSharingContentVisible() ? .readOnly : .none
    }

    /// mark displayed, apply sharing policy, publish changed item identity.
    @discardableResult
    public func showPopover() -> Int {
        isDisplayed = true
        updateSharingType()
        if let item {
            let itemIdentifier = item.previewIdentifier
            self.itemIdentifier = itemIdentifier
            if registry.popoverItemIdentifier != itemIdentifier {
                registry.popoverItemIdentifier = itemIdentifier
                registry.updateTopmostPreview()
            }
        }
        return 0
    }

    /// restore animation, notify owner, then clear the tracked popover.
    @discardableResult
    public func closePopover() -> Int {
        animates = true
        isDisplayed = false
        onWillClose?()
        if registry.popoverItemIdentifier != nil {
            registry.popoverItemIdentifier = nil
            registry.updateTopmostPreview()
        }
        return 0
    }

    public func popoverWillShow(_ notification: Notification) { showPopover() }
    public func popoverWillClose(_ notification: Notification) { closePopover() }

    /// AppKit may detach this popover.
    public func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }

    /// detaching requests a nonediting window kept open after editing.
    public func detachableWindow(for popover: NSPopover) -> NSWindow? {
        makePreviewWindow(beginEditing: false, keepOpenAfterEditing: true)
    }

    /// an existing detached preview prevents a second edit transition.
    public func detachForEditingIfNeeded(itemIdentity: AnyHashable) {
        guard registry.windowForItem(itemIdentity: itemIdentity) == nil else { return }
        detachForEditing()
    }

    /// after the local item-view adapter resolves the content dependency.
    public func makePreviewWindow(beginEditing: Bool, keepOpenAfterEditing: Bool) -> PreviewWindow? {
        guard let item else { return nil }
        let window = PreviewWindow()
        guard let preview = makeContentView?(item) else { return nil }
        preview.onEndEditing = {
            if !keepOpenAfterEditing { window.close() }
        }
        let manager = registry
        preview.onEditingStateChanged = { editing in
            manager.setEditingState(isEditing: editing, itemIdentifier: item.previewIdentifier)
        }
        if beginEditing { preview.beginPreviewEditing() }
        let controller = NSViewController()
        controller.view = preview
        window.contentViewController = controller
        manager.registerPreviewWindow(window: window, itemIdentity: item.previewIdentity,
                           itemIdentifier: item.previewIdentifier, isEditing: beginEditing)
        return window
    }

    /// The screen-geometry transition recovered.
    public func detachForEditing() {
        guard let view = contentViewController?.view, let oldWindow = view.window else { return }
        let screenFrame = oldWindow.convertToScreen(view.frame)
        oldWindow.alphaValue = 0
        close()
        guard let window = makePreviewWindow(beginEditing: true, keepOpenAfterEditing: false) else { return }
        window.setFrame(screenFrame, display: false)
        window.makeKeyAndOrderFront(nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
