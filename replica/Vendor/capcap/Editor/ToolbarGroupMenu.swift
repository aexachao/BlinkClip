import AppKit

/// The row currently highlighted by the keyboard (↑/↓), plus the member list
/// it indexes. Pure value type so the wrap-around rules are testable without a
/// window.
struct ToolbarGroupMenuSelection: Equatable {
    let members: [ToolbarItemID]
    private(set) var index: Int
    /// Keyboard navigation has started. Until it does, only the pointer hovers
    /// a row; the selected member's own fill still marks it.
    private(set) var isKeyboardActive: Bool = false

    init(members: [ToolbarItemID], selected: ToolbarItemID?) {
        self.members = members
        if let selected, let position = members.firstIndex(of: selected) {
            index = position
        } else {
            index = 0
        }
    }

    var currentMember: ToolbarItemID? {
        guard members.indices.contains(index) else { return nil }
        return members[index]
    }

    /// ↑/↓ movement with wrap-around, matching how menu keyboards behave.
    mutating func move(by delta: Int) {
        guard !members.isEmpty else { return }
        isKeyboardActive = true
        let count = members.count
        index = ((index + delta) % count + count) % count
    }

    func isHighlighted(_ position: Int) -> Bool {
        isKeyboardActive && position == index
    }
}

/// Key mapping for the group dropdown. Kept separate from the panel so the
/// bindings can be asserted directly.
enum ToolbarGroupMenuKeyCommand: Equatable {
    case moveUp
    case moveDown
    case commit
    case cancel

    static func command(forKeyCode keyCode: UInt16) -> ToolbarGroupMenuKeyCommand? {
        switch keyCode {
        case 126: return .moveUp          // ↑
        case 125: return .moveDown        // ↓
        case 36, 76: return .commit       // Return, keypad Enter
        case 53: return .cancel           // Esc
        default: return nil
        }
    }
}

/// One row of the grouped-tool dropdown: icon + name, left aligned, with a
/// trailing checkmark on the group's current member. Hover and selected fills
/// come from `ToolbarChrome` — the same fill, radius and inset as a toolbar
/// button — so the dropdown reads as part of the bar.
final class ToolbarGroupMenuRow: NSView, ToolbarHoverable {
    /// Horizontal inset of the row's content inside the highlight.
    static let contentInsetX: CGFloat = 10
    /// Gap between the icon and the name.
    static let iconTextGap: CGFloat = 8
    /// Width of the trailing selected checkmark.
    static let checkmarkWidth: CGFloat = 12
    /// Gap between the name and the checkmark.
    static let textCheckmarkGap: CGFloat = 8

    let member: ToolbarItemID
    let isSelected: Bool

    private let icon: NSImage?
    private let title: String
    private let checkmark: NSImage?

    /// Rows live in a panel that is deliberately never key, so a
    /// key-window-scoped tracking area would never deliver `mouseEntered`
    /// here. Rows follow the pointer regardless of key status; the bar's own
    /// controls keep their `.activeInKeyWindow` rule.
    var hoverRequiresKeyWindow: Bool { false }

    /// Pointer is over the row.
    private(set) var isHovered = false {
        didSet { if oldValue != isHovered { needsDisplay = true } }
    }
    /// Keyboard highlight (↑/↓).
    var isKeyboardHighlighted = false {
        didSet { if oldValue != isKeyboardHighlighted { needsDisplay = true } }
    }

    var hoverTrackingArea: NSTrackingArea?
    var onClick: (() -> Void)?
    private var isPressed = false

    init(frame: NSRect, member: ToolbarItemID, isSelected: Bool) {
        self.member = member
        self.isSelected = isSelected
        self.title = member.localizedTitle
        self.icon = member.iconImage(pointSize: ToolbarChrome.symbolPointSize)
        self.checkmark = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel(title)
        setAccessibilitySelected(isSelected)
        setAccessibilityEnabled(true)
        setAccessibilityIdentifier("capcap.toolbar.groupRow.\(member.rawValue)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshHoverTrackingArea(&hoverTrackingArea)
    }

    /// Reinstalls the tracking area and re-derives the hover state from the
    /// pointer. The panel can move under a stationary pointer (it is placed
    /// by `ToolbarGroupMenuPanel.placement`), where AppKit does not deliver
    /// the matching enter/exit, so the highlight is re-derived instead of
    /// trusting the last event. Called by the content view on window moves.
    func refreshHoverTracking() {
        guard window != nil else {
            setHovered(false)
            return
        }
        refreshHoverTrackingArea(&hoverTrackingArea)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setHovered(false) }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(false)
    }

    func setHovered(_ hovered: Bool) {
        let allowed = hovered && (!hoverRequiresKeyWindow || (window?.isKeyWindow ?? true))
        guard allowed != isHovered else { return }
        isHovered = allowed
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isSelected {
            ToolbarChrome.drawSelectedBackground(in: bounds)
        } else {
            ToolbarChrome.drawHoverBackground(
                in: bounds,
                hovered: isHovered || isKeyboardHighlighted
            )
        }

        let symbolSize = ToolbarChrome.symbolPointSize
        let midY = bounds.midY
        if let icon {
            let iconRect = NSRect(
                x: Self.contentInsetX,
                y: midY - symbolSize / 2,
                width: symbolSize,
                height: symbolSize
            )
            draw(tinted: icon, in: iconRect, color: isSelected ? accentGreen : .labelColor)
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: ToolbarGroupMenuPanel.nameFont,
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let textOrigin = NSPoint(
            x: Self.contentInsetX + symbolSize + Self.iconTextGap,
            y: midY - textSize.height / 2
        )
        (title as NSString).draw(at: textOrigin, withAttributes: attributes)

        if isSelected, let checkmark {
            let checkRect = NSRect(
                x: bounds.maxX - Self.contentInsetX - Self.checkmarkWidth,
                y: midY - checkmark.size.height / 2,
                width: Self.checkmarkWidth,
                height: checkmark.size.height
            )
            draw(tinted: checkmark, in: checkRect, color: accentGreen)
        }
    }

    private func draw(tinted symbol: NSImage, in rect: NSRect, color: NSColor) {
        let tinted = NSImage(size: symbol.size, flipped: false) { imageRect in
            symbol.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
            color.setFill()
            imageRect.fill(using: .sourceAtop)
            return true
        }
        let target = NSRect(
            x: rect.midX - symbol.size.width / 2,
            y: rect.midY - symbol.size.height / 2,
            width: symbol.size.width,
            height: symbol.size.height
        )
        tinted.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1,
                    respectFlipped: true, hints: nil)
    }
}

/// Content view of the group dropdown. Draws the toolbar surface itself (same
/// material, radius and border tokens as the bar) and hosts one row per group
/// member.
final class ToolbarGroupMenuContentView: NSView {
    private(set) var rows: [ToolbarGroupMenuRow] = []
    /// How many times the rows re-derived their hover state. Lets the native
    /// harness prove that a panel move rebuilds the tracking areas instead of
    /// leaving a stale highlight behind.
    private(set) var hoverRefreshCount = 0

    private var windowMoveObserver: NSObjectProtocol?

    deinit {
        if let windowMoveObserver {
            NotificationCenter.default.removeObserver(windowMoveObserver)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        ToolbarChrome.drawSurface(in: bounds, bordered: true)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let windowMoveObserver {
            NotificationCenter.default.removeObserver(windowMoveObserver)
            self.windowMoveObserver = nil
        }
        guard let window else {
            rows.forEach { $0.setHovered(false) }
            return
        }
        // The panel is positioned with `setFrameOrigin` and can be moved under
        // a stationary pointer; AppKit then delivers no enter/exit, so the
        // rows' hover is re-derived here.
        windowMoveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.refreshRowHover()
        }
        refreshRowHover()
    }

    /// Reinstalls every row's tracking area and re-derives its hover state
    /// from where the pointer actually is. A row the pointer has left clears
    /// its highlight; the row now under the pointer lights up. Never touches
    /// the selected member, so a hover cannot change the group's choice.
    func refreshRowHover() {
        hoverRefreshCount += 1
        guard window != nil else {
            rows.forEach { $0.setHovered(false) }
            return
        }
        rows.forEach { $0.refreshHoverTracking() }
    }

    func configure(members: [ToolbarItemID], selected: ToolbarItemID, selection: ToolbarGroupMenuSelection) {
        rows.forEach { $0.removeFromSuperview() }
        rows = members.enumerated().map { position, member in
            let row = ToolbarGroupMenuRow(
                frame: rowFrame(at: position, count: members.count),
                member: member,
                isSelected: member == selected
            )
            row.isKeyboardHighlighted = selection.isHighlighted(position)
            addSubview(row)
            return row
        }
    }

    func setKeyboardSelection(_ selection: ToolbarGroupMenuSelection) {
        for (position, row) in rows.enumerated() {
            row.isKeyboardHighlighted = selection.isHighlighted(position)
        }
    }

    func rowFrame(at position: Int, count: Int) -> NSRect {
        let padding = ToolbarChrome.surfacePadding
        let rowHeight = ToolbarChrome.rowHeight
        // Rows stack downward from the top edge (AppKit's y axis points up).
        let y = bounds.height - padding - rowHeight * CGFloat(position + 1)
        return NSRect(
            x: padding,
            y: y,
            width: max(0, bounds.width - padding * 2),
            height: rowHeight
        )
    }
}

/// Self-drawn dropdown for the toolbar's grouped tools (shapes / lines /
/// brush). It replaces `NSMenu` on purpose: a system menu brings its own
/// material, row height, corner radius and padding, which reads as a different
/// surface next to the toolbar capsule. Everything here — surface, radius,
/// row height, symbol size, hover fill — comes from `ToolbarChrome`.
final class ToolbarGroupMenuPanel: NSPanel {
    /// Row name font. Kept at 13pt so a dropdown row reads at the same weight
    /// as the bar's controls without dwarfing them.
    static let nameFont = NSFont.systemFont(ofSize: 13)
    /// Narrowest the panel may get, so a one-word member list still looks like
    /// a menu and not a sliver.
    static let minimumWidth: CGFloat = 132
    /// Smallest gap kept between the panel and the screen edge.
    static let edgeInset: CGFloat = 4

    /// Only one group dropdown is ever on screen at a time.
    private(set) static var presentedPanel: ToolbarGroupMenuPanel?

    let group: ToolbarGroup
    let members: [ToolbarItemID]
    private(set) var selection: ToolbarGroupMenuSelection
    private var selectedMember: ToolbarItemID
    private let content: ToolbarGroupMenuContentView

    private weak var owner: NSView?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var onPick: ((ToolbarItemID) -> Void)?

    // MARK: - Presentation

    /// Opens the group's dropdown under `anchor`. A second call for the same
    /// owner dismisses it, so the chevron behaves as a toggle.
    @discardableResult
    static func present(
        group: ToolbarGroup,
        members: [ToolbarItemID],
        selected: ToolbarItemID,
        anchor: NSView,
        owner: NSView,
        onPick: @escaping (ToolbarItemID) -> Void
    ) -> ToolbarGroupMenuPanel? {
        if let existing = presentedPanel, existing.owner === owner {
            existing.dismiss()
            return nil
        }
        presentedPanel?.dismiss()
        guard !members.isEmpty, anchor.window != nil else { return nil }
        let panel = ToolbarGroupMenuPanel(
            group: group,
            members: members,
            selected: selected,
            owner: owner,
            onPick: onPick
        )
        presentedPanel = panel
        panel.show(relativeTo: anchor)
        return panel
    }

    static func isPresented(ownedBy owner: NSView) -> Bool {
        presentedPanel?.owner === owner
    }

    static func dismissPresented() {
        presentedPanel?.dismiss()
    }

    init(
        group: ToolbarGroup,
        members: [ToolbarItemID],
        selected: ToolbarItemID,
        owner: NSView,
        onPick: @escaping (ToolbarItemID) -> Void
    ) {
        self.group = group
        self.members = members
        self.selectedMember = selected
        self.selection = ToolbarGroupMenuSelection(members: members, selected: selected)
        self.owner = owner
        self.onPick = onPick
        let size = Self.preferredSize(members: members)
        let rect = NSRect(origin: .zero, size: size)
        self.content = ToolbarGroupMenuContentView(frame: rect)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // A floating panel by default; `show(relativeTo:)` raises it just above
        // the editor's own window, which in a capture session sits at
        // `.screenSaver` level and would otherwise cover the dropdown.
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace]
        contentView = content
        content.configure(members: members, selected: selected, selection: selection)
        content.rows.enumerated().forEach { position, row in
            row.onClick = { [weak self] in
                guard let self, let member = self.members[safe: position] else { return }
                self.commit(member)
            }
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
        setAccessibilityLabel(selectedMember.localizedTitle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Never takes key: the editor window keeps focus and the panel handles
    // ↑/↓/Return/Esc through its own local monitor, so the bar hovering under
    // the pointer keeps its state and text editing is untouched.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Height/width the panel needs for a member list. Exposed for the layout
    /// harness; the rows themselves are laid out by the content view.
    static func preferredSize(members: [ToolbarItemID]) -> NSSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: nameFont]
        let widestText = members
            .map { ($0.localizedTitle as NSString).size(withAttributes: attributes).width }
            .max() ?? 0
        let padding = ToolbarChrome.surfacePadding
        let rowWidth = ToolbarGroupMenuRow.contentInsetX * 2
            + ToolbarChrome.symbolPointSize
            + ToolbarGroupMenuRow.iconTextGap
            + widestText
            + ToolbarGroupMenuRow.textCheckmarkGap
            + ToolbarGroupMenuRow.checkmarkWidth
        let width = max(minimumWidth, padding * 2 + rowWidth)
        let height = padding * 2 + ToolbarChrome.rowHeight * CGFloat(members.count)
        return NSSize(width: ceil(width), height: ceil(height))
    }

    /// One step above the window that owns the toolbar, and never below the
    /// pop-up menu level — the capture overlay window is a `.screenSaver`-level
    /// panel, so a fixed pop-up level would hide the dropdown behind it.
    static func level(above anchorWindow: NSWindow) -> NSWindow.Level {
        let above = NSWindow.Level(rawValue: anchorWindow.level.rawValue + 1)
        return above.rawValue >= NSWindow.Level.popUpMenu.rawValue ? above : .popUpMenu
    }

    /// Where the panel goes for a given anchor rect: below it by default,
    /// flipped above when it would run past the bottom edge, and always kept
    /// inside the screen's visible frame (the "cannot go off screen" rule).
    static func placement(
        anchorOnScreen: NSRect,
        size: NSSize,
        visibleFrame: NSRect,
        gap: CGFloat = ToolbarChrome.dropdownGap,
        edgeInset: CGFloat = ToolbarGroupMenuPanel.edgeInset
    ) -> NSPoint {
        var origin = NSPoint(
            x: anchorOnScreen.minX,
            y: anchorOnScreen.minY - size.height - gap
        )
        if origin.y < visibleFrame.minY + edgeInset {
            let above = anchorOnScreen.maxY + gap
            origin.y = above + size.height <= visibleFrame.maxY - edgeInset
                ? above
                : visibleFrame.minY + edgeInset
        }
        let maxX = max(visibleFrame.minX + edgeInset, visibleFrame.maxX - size.width - edgeInset)
        let maxY = max(visibleFrame.minY + edgeInset, visibleFrame.maxY - size.height - edgeInset)
        origin.x = min(max(origin.x, visibleFrame.minX + edgeInset), maxX)
        origin.y = min(max(origin.y, visibleFrame.minY + edgeInset), maxY)
        return origin
    }

    private func show(relativeTo anchor: NSView) {
        guard let anchorWindow = anchor.window else { return }
        let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visibleFrame = (anchorWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchorRect
        level = Self.level(above: anchorWindow)
        setFrameOrigin(Self.placement(
            anchorOnScreen: anchorRect,
            size: frame.size,
            visibleFrame: visibleFrame
        ))
        orderFront(nil)
        // The panel is placed under the pointer's anchor, not under the
        // pointer itself, but a click that lands on a row must not leave the
        // previous position's row looking hovered. Re-derive from the pointer
        // once the panel is actually on screen.
        content.refreshRowHover()
        installMonitors(for: anchorWindow)
    }

    private func installMonitors(for anchorWindow: NSWindow) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handleKeyDown(event) else { return event }
            return nil
        }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            // Clicks inside the panel, or on the chevron that opened it, are
            // the panel's own business (the chevron toggles it closed).
            if event.window === self { return event }
            if self.eventIsOnOwner(event) { return event }
            self.dismiss()
            return event
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: anchorWindow,
                queue: .main
            ) { [weak self] _ in
                self?.dismiss()
            })
        }
    }

    /// Routes one key event through the panel. Returns `true` when the panel
    /// consumed it (the local monitor, or the editor's early key hook, then
    /// swallows the event); `false` leaves every other key with the editor.
    @discardableResult
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let command = ToolbarGroupMenuKeyCommand.command(forKeyCode: event.keyCode) else {
            return false
        }
        switch command {
        case .moveUp:
            moveHighlight(by: -1)
        case .moveDown:
            moveHighlight(by: 1)
        case .commit:
            commitHighlighted()
        case .cancel:
            dismiss()
        }
        return true
    }

    private func eventIsOnOwner(_ event: NSEvent) -> Bool {
        guard let owner, let ownerWindow = owner.window, event.window === ownerWindow else {
            return false
        }
        return owner.bounds.contains(owner.convert(event.locationInWindow, from: nil))
    }

    private func moveHighlight(by delta: Int) {
        selection.move(by: delta)
        content.setKeyboardSelection(selection)
    }

    private func commitHighlighted() {
        guard let member = selection.currentMember else {
            dismiss()
            return
        }
        commit(member)
    }

    private func commit(_ member: ToolbarItemID) {
        // Capture the handler first: `dismiss()` tears the panel down, including
        // its callbacks, before the pick is delivered.
        let handler = onPick
        dismiss()
        handler?(member)
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        for observer in windowObservers { NotificationCenter.default.removeObserver(observer) }
        windowObservers.removeAll()
        onPick = nil
        if Self.presentedPanel === self { Self.presentedPanel = nil }
        orderOut(nil)
        close()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
