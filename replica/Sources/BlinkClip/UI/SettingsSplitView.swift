import AppKit
import SwiftUI

/// fixed sidebar and content split items.
@MainActor
struct SettingsSplitView: NSViewControllerRepresentable {
    let title: String
    let sidebar: AnyView
    let detail: AnyView

    func makeNSViewController(context: Context) -> SettingsSplitViewController {
        let controller = SettingsSplitViewController()
        controller.paneTitle = title
        let navigation = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: sidebar))
        navigation.canCollapse = false
        navigation.minimumThickness = 200
        navigation.maximumThickness = 200
        let content = NSSplitViewItem(viewController: NSHostingController(rootView: detail))
        content.minimumThickness = 440
        controller.splitViewItems = [navigation, content]
        return controller
    }

    func updateNSViewController(_ controller: SettingsSplitViewController, context: Context) {
        controller.paneTitle = title
        (controller.splitViewItems[0].viewController as! NSHostingController<AnyView>).rootView = sidebar
        (controller.splitViewItems[1].viewController as! NSHostingController<AnyView>).rootView = detail
    }
}

/// The split controller owns the toolbar delegate for the lifetime of this settings root.
/// Replacing the root for a deep link installs a fresh delegate on the same window.
@MainActor
final class SettingsSplitViewController: NSSplitViewController, NSToolbarDelegate {
    private static let separatorID = NSToolbarItem.Identifier("BlinkClipSettings.sidebarSeparator")
    private static let titleID = NSToolbarItem.Identifier("BlinkClipSettings.paneTitle")
    private let titleLabel = NSTextField(labelWithString: "")
    private weak var toolbarWindow: NSWindow?
    var paneTitle = "" {
        didSet {
            guard oldValue != paneTitle else { return }
            titleLabel.stringValue = paneTitle
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        installToolbarIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installToolbarIfNeeded()
    }

    private func installToolbarIfNeeded() {
        guard let window = view.window else { return }
        guard toolbarWindow !== window || window.toolbar?.delegate !== self else { return }
        toolbarWindow = window
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.setAccessibilityIdentifier("BlinkClipSettingsPaneTitle")
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        let toolbar = NSToolbar(identifier: "BlinkClipSettings")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        let frame = window.frame
        window.toolbar = toolbar
        window.setFrame(NSRect(origin: frame.origin, size: NSSize(width: 648, height: 600)), display: false)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.separatorID, Self.titleID, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if identifier == Self.separatorID {
            return NSTrackingSeparatorToolbarItem(identifier: identifier, splitView: splitView, dividerIndex: 0)
        }
        guard identifier == Self.titleID else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.view = titleLabel
        item.label = paneTitle
        item.isBordered = false
        return item
    }
}
