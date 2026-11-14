import AppKit
import Combine
import BlinkClipCore
import os

/// The About window: app icon, product name, version, a one-line summary,
/// links, and a single action row.
///
/// The status line belongs to the action block: it sits just above the button
/// row (8 pt stack spacing, 9 pt frame to frame), on the same centred axis, so it can never float in the loose space
/// above the buttons. It always uses secondary colour, so a failed check never
/// pushes the layout around and never shows raw network detail — the gentle copy
/// comes from `BlinkClipUpdateChecker`. The status line only ever reports a
/// timestamp ("上次检查 21:04") or a concrete pending/available/failure fact; it
/// never claims the install is current. Sparkle's own dialog already says
/// "you're up to date" for a user-initiated check, and Sparkle 2.10.1 has no
/// public hook to suppress that modal, so the inline line deliberately does not
/// repeat it (`SPUStandardUserDriverDelegate` only observes modal alerts).
/// The check button starts Sparkle's own update flow; those are two jobs and
/// stay separate.
@MainActor
final class BlinkClipAboutWindowController: NSWindowController, NSWindowDelegate {
    static let windowIdentifier = "blinkclip-about-window"
    static let contentSize = NSSize(width: 380, height: 420)

    private static let horizontalInset: CGFloat = 28
    private static let projectURL = URL(string: "https://github.com/aexachao/BlinkClip")!
    private static let releaseNotesURL = URL(string: "https://github.com/aexachao/BlinkClip/releases")!
    private static let licenseURL = URL(string: "https://github.com/aexachao/BlinkClip/blob/main/LICENSE")!
    private static let log = Logger(subsystem: "com.chrisli.blinkclip", category: "updates")

    private let checker: BlinkClipUpdateChecker
    /// Sparkle's own check (`BlinkClipInAppUpdater` / `SPUUpdater`). Injected so
    /// the window stays free of Sparkle for the native harness.
    private let sparkleCheck: () throws -> Void
    private var observation: AnyCancellable?
    private var linkTargets: [URL] = []
    /// 窗口关闭回调。设置侧栏用它把选中态落回点击「关于闪贴」之前的分区；窗口
    /// 从菜单打开时没有人登记，回调为空、行为不变。回调只触发一次。
    var onClose: (() -> Void)?

    let statusLabel = NSTextField(wrappingLabelWithString: "")
    let checkButton = NSButton()
    let closeButton = NSButton()
    private let versionLabel = NSTextField(labelWithString: "")

    init(checker: BlinkClipUpdateChecker, sparkleCheck: @escaping () throws -> Void) {
        self.checker = checker
        self.sparkleCheck = sparkleCheck
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = SettingsLocalization.text("updates.about-title")
        window.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        configureContent()
        refresh(checker.state)
        observation = checker.$state.sink { [weak self] state in
            MainActor.assumeIsolated { self?.refresh(state) }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func showWindow(_ sender: Any?) {
        // The menu item and the settings sidebar each own a controller; only one
        // About window should ever be on screen.
        for other in NSApp.windows
        where other !== window && other.identifier?.rawValue == Self.windowIdentifier {
            other.close()
        }
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
        Task { await checker.check() }
    }

    private func text(_ key: String) -> String { SettingsLocalization.text(key) }

    private func configureContent() {
        guard let content = window?.contentView else { return }

        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setAccessibilityIdentifier("about-application-icon")

        let name = NSTextField(labelWithString: ReplicaBrand.name)
        name.font = .systemFont(ofSize: 24, weight: .semibold)
        name.alignment = .center
        name.setAccessibilityIdentifier("about-product-name")

        versionLabel.stringValue = String(format: text("updates.current-version"), checker.currentVersion)
        versionLabel.font = .systemFont(ofSize: 12.5)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        versionLabel.setAccessibilityIdentifier("about-current-version")

        let description = NSTextField(wrappingLabelWithString: text("updates.description"))
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        description.alignment = .center
        description.preferredMaxLayoutWidth = Self.contentSize.width - 2 * Self.horizontalInset
        description.setAccessibilityIdentifier("about-description")

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let projectLink = makeLink(text("updates.link-project"), url: Self.projectURL, identifier: "about-project-link")
        let releaseNotesLink = makeLink(text("updates.link-releases"), url: Self.releaseNotesURL, identifier: "about-release-notes-link")
        let links = NSStackView(views: [projectLink, releaseNotesLink])
        links.orientation = .horizontal
        links.spacing = 18
        links.alignment = .centerY
        links.translatesAutoresizingMaskIntoConstraints = false

        let copyright = NSTextField(labelWithString: text("updates.copyright"))
        copyright.font = .systemFont(ofSize: 11)
        copyright.textColor = .tertiaryLabelColor
        copyright.alignment = .center
        copyright.setAccessibilityIdentifier("about-copyright")
        let licenseLink = makeLink(text("updates.link-license"), url: Self.licenseURL,
                                   identifier: "about-license-link", fontSize: 11.5)
        let legal = NSStackView(views: [copyright, licenseLink])
        legal.orientation = .horizontal
        legal.spacing = 8
        legal.alignment = .centerY
        legal.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 11.5)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.preferredMaxLayoutWidth = Self.contentSize.width - 2 * Self.horizontalInset
        statusLabel.setAccessibilityIdentifier("about-update-status")

        checkButton.title = text("updates.check")
        checkButton.target = self
        checkButton.action = #selector(check)
        checkButton.bezelStyle = .rounded
        checkButton.keyEquivalent = "\r"
        checkButton.setAccessibilityIdentifier("about-check-updates")
        closeButton.title = text("updates.close")
        closeButton.target = self
        closeButton.action = #selector(closeWindow)
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\u{1b}"
        closeButton.setAccessibilityIdentifier("about-close")

        let buttonRow = NSStackView(views: [checkButton, closeButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .centerY
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        let buttonHolder = NSView()
        buttonHolder.translatesAutoresizingMaskIntoConstraints = false
        buttonHolder.addSubview(buttonRow)

        // One flexible band above the identity block and one between the legal
        // row and the action block: the identity block stays optically centred,
        // and the status line is anchored just above the buttons instead of
        // floating in leftover space.
        let topSpacer = NSView()
        let bottomSpacer = NSView()
        for spacer in [topSpacer, bottomSpacer] {
            spacer.translatesAutoresizingMaskIntoConstraints = false
            spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
            spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)
        }

        let stack = NSStackView(views: [topSpacer, icon, name, versionLabel, description, divider,
                                        links, legal, bottomSpacer, statusLabel, buttonHolder])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: icon)
        stack.setCustomSpacing(2, after: name)
        stack.setCustomSpacing(16, after: description)
        stack.setCustomSpacing(14, after: divider)
        stack.setCustomSpacing(16, after: legal)
        stack.setCustomSpacing(8, after: statusLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: Self.horizontalInset),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -Self.horizontalInset),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),

            topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor),

            icon.widthAnchor.constraint(equalToConstant: 88),
            icon.heightAnchor.constraint(equalToConstant: 88),

            divider.widthAnchor.constraint(equalTo: stack.widthAnchor),

            // The status line and the buttons form one action block: same
            // centred axis, 8 pt apart. The divider/links/legal rows above stay
            // centred too, so the whole window keeps one vertical axis.
            statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),

            buttonHolder.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.centerXAnchor.constraint(equalTo: buttonHolder.centerXAnchor),
            buttonRow.topAnchor.constraint(equalTo: buttonHolder.topAnchor),
            buttonRow.bottomAnchor.constraint(equalTo: buttonHolder.bottomAnchor),
            // The buttons must never be squeezed by the flexible bands: their
            // row keeps its native height, so the 8 pt gap above is real.
            buttonHolder.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
            checkButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 104),
            closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 84)
        ])

        // Emphasis is a window-level decision, not an appearance-level one: the
        // check button is the default action (Return) in light and dark alike.
        // Setting the cell explicitly matters because this window is built in
        // code; without it AppKit may not resolve a default button at all.
        window?.defaultButtonCell = checkButton.cell as? NSButtonCell
    }

    /// A borderless link button: no new dependency, and VoiceOver still reads it
    /// as a button with the link text.
    private func makeLink(_ title: String, url: URL, identifier: String, fontSize: CGFloat = 12) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(openLink(_:)))
        button.isBordered = false
        button.bezelStyle = .inline
        button.tag = linkTargets.count
        linkTargets.append(url)
        button.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.linkColor
        ])
        button.setAccessibilityIdentifier(identifier)
        return button
    }

    private func refresh(_ state: BlinkClipUpdateChecker.State) {
        checkButton.isEnabled = state != .checking
        // Every state, failures included, uses the secondary colour: the line is
        // a quiet status, not an error banner in the middle of the layout.
        statusLabel.textColor = .secondaryLabelColor
        switch state {
        case .idle:
            // Reopening About before anything ran shows either "尚未检查更新"
            // or the persisted time of the last completed check — never a
            // freshness claim.
            statusLabel.stringValue = checker.lastCheckSummary
        case .checking:
            statusLabel.stringValue = text("updates.checking")
        case .upToDate:
            // Sparkle's user-initiated check shows its own "you're up to date"
            // alert. Repeating that sentence inline would be two places saying
            // the same thing, so the inline line carries only the verification
            // time.
            statusLabel.stringValue = checker.lastCheckSummary
        case let .available(update):
            statusLabel.stringValue = String(format: text("updates.available-format"),
                                             update.version, checker.lastCheckTime)
        case let .failed(message):
            statusLabel.stringValue = message
        }
    }

    /// Refreshes the appcast summary and hands the install to Sparkle. The
    /// button is the updater entry point, not a page refresh.
    @objc func check() {
        Task { await checker.check(force: true) }
        do {
            try sparkleCheck()
        } catch {
            Self.log.error("sparkle check failed: \(String(describing: error), privacy: .public)")
            statusLabel.stringValue = text("updates.unreachable")
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    @objc func closeWindow() {
        window?.performClose(nil)
    }

    /// 关窗前把一次性的回调取走：重复关闭（菜单入口 vs 侧栏入口、`showWindow` 关掉
    /// 另一个关于窗）不会把回调触发第二次。
    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        let handler = onClose
        onClose = nil
        handler?()
    }

    @objc private func openLink(_ sender: NSButton) {
        guard linkTargets.indices.contains(sender.tag) else { return }
        NSWorkspace.shared.open(linkTargets[sender.tag])
    }
}
