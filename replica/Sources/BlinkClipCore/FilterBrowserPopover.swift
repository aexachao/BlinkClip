import AppKit

@MainActor
public final class FilterBrowserPopover: NSPopover, NSPopoverDelegate {
    public private(set) var isDisplayed = false
    public var onWillClose: (() -> Void)?

    public override init() {
        super.init()
        behavior = .transient
        animates = true
        delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(close),
            name: PreviewPopover.mainWindowWillCloseNotification, object: nil)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present(_ controller: NSViewController, relativeTo anchor: NSView) {
        if isDisplayed { close(); return }
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = CGColor.clear
        contentViewController = controller
        show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        animates = false
    }

    public func hidePopover() {
        animates = true
        isDisplayed = false
        contentViewController = nil
        onWillClose?()
    }

    public func popoverWillClose(_ notification: Notification) { hidePopover() }
    public func popoverWillShow(_ notification: Notification) { isDisplayed = true }

    deinit { NotificationCenter.default.removeObserver(self) }
}
