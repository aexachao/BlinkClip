import AppKit
import Combine
import BlinkClipCore

// Native text/color/image/link creation reads its captured entity; other content keeps its adapter.
@MainActor
func makeReplicaNativePreview(state: ReplicaUIState, input: ClipboardRestoreItem) -> ItemPreviewView {
    let rawType = input.previewRawType()
    if rawType == 5 {
        return makeReplicaTextPreview(state: state, item: nil, input: input)
    }
    if rawType == 2 {
        let content = ReplicaColorPreviewContent(state: state, item: nil, input: input)
        return makeReplicaContentPreview(state: state, item: nil, input: input, content: content,
            contentSize: content.preferredPreviewSize, metadata: content.previewMetadataView)
    }
    if rawType == 1 {
        let content = ReplicaImagePreviewContent(state: state, item: nil, input: input)
        return makeReplicaContentPreview(state: state, item: nil, input: input, content: content,
            contentSize: content.preferredPreviewSize, metadata: content.previewMetadataView)
    }
    if rawType == 4 {
        let content = ReplicaLinkPreviewContent(state: state, item: nil, input: input)
        return makeReplicaContentPreview(state: state, item: nil, input: input, content: content,
            contentSize: content.preferredPreviewSize, metadata: content.previewMetadataView)
    }
    return makeReplicaPreview(state: state, item: input.resolvedItem(), input: input)
}

/// Shares preview chrome and editing transitions; per-kind content retains its own contract.
@MainActor
func makeReplicaPreview(state: ReplicaUIState, item: ClipboardItem,
                                input: ClipboardRestoreItem? = nil) -> ItemPreviewView {
    if let textPreview = makeReplicaTextPreview(state: state, item: item, input: input) { return textPreview }
    let content: NSView
    let contentSize: NSSize
    let metadata: NSView?
    let screenSize = NSScreen.main?.frame.size ?? .zero
    switch item.kind {
    case .image:
        let image = ReplicaImagePreviewContent(state: state, item: item, input: input)
        content = image
        contentSize = image.preferredPreviewSize
        metadata = image.previewMetadataView
    case .color:
        let color = ReplicaColorPreviewContent(state: state, item: item, input: input)
        content = color
        contentSize = color.preferredPreviewSize
        metadata = color.previewMetadataView
    case .link:
        let link = ReplicaLinkPreviewContent(state: state, item: item, input: input)
        content = link
        contentSize = link.preferredPreviewSize
        metadata = link.previewMetadataView
    case .files:
        let files = ReplicaFilePreviewContent(state: state, item: item)
        content = files
        contentSize = files.preferredPreviewSize
        metadata = files.previewMetadataView
    case .unknown:
        content = UnavailablePreviewContentView(frame: .zero)
        contentSize = .init(width: screenSize.width * 0.25,
                            height: screenSize.height * 0.25)
        metadata = nil
    default:
        content = makeReplicaReadOnlyPreviewContent(store: state.store, item: item)
        contentSize = .init(width: screenSize.width * 0.25,
                            height: screenSize.height * 0.25)
        metadata = nil
    }
    return makeReplicaContentPreview(state: state, item: item, input: input, content: content,
        contentSize: contentSize, metadata: metadata)
}

@MainActor
private func makeReplicaContentPreview(state: ReplicaUIState, item: ClipboardItem?, input: ClipboardRestoreItem?,
                                       content: NSView, contentSize: NSSize, metadata: NSView?) -> ItemPreviewView {
    let header = ReplicaInlinePreviewHeader(state: state, item: item, input: input)
    let editorHeader = ReplicaInlinePreviewEditorHeader()
    let footer = PreviewFooterView()
    if let metadata { footer.setContentView(metadata) }
    else {
        let emptyMetadata = NSView()
        emptyMetadata.heightAnchor.constraint(equalToConstant: 0).isActive = true
        footer.setContentView(emptyMetadata)
    }
    let view = ReplicaInlinePreviewContainer(previewHeader: header, editorHeader: editorHeader,
                                            contentView: content, footer: footer,
                                            contentSize: contentSize)
    view.applyContentAppearance()
    connectReplicaPreviewHeader(header, view: view, state: state, item: item, input: input)
    editorHeader.onCancel = { [weak view] in view?.cancelPreviewEditing() }
    editorHeader.onSave = { [weak view] in view?.commitPreviewEditing() }
    view.setCanCommitEditing = { [weak editorHeader] enabled in editorHeader?.setCanCommit(enabled) }
    if let image = content as? ReplicaImagePreviewContent { editorHeader.setCanCommit(image.canCommit) }
    return view
}

/// Connects recovered preview mode transitions to the replica's local text model.
/// Other kinds use their own content adapters in the shared factory above.
@MainActor
func makeReplicaTextPreview(state: ReplicaUIState, item: ClipboardItem,
                                    input: ClipboardRestoreItem? = nil) -> ItemPreviewView? {
    let isText: Bool
    if let rawType = input?.previewRawType() { isText = rawType == 5 }
    else { isText = item.kind == .text || item.kind == .richText }
    guard isText else { return nil }
    return makeReplicaTextPreview(state: state, item: item, input: input)
}

@MainActor
private func makeReplicaTextPreview(state: ReplicaUIState, item: ClipboardItem?,
                                    input: ClipboardRestoreItem?) -> ItemPreviewView {
    let content = ReplicaInlineTextPreviewContent(state: state, item: item, input: input)
    let header = ReplicaInlinePreviewHeader(state: state, item: item, input: input)
    let editorHeader = ReplicaInlinePreviewEditorHeader(document: content.document)
    let footer = ReplicaInlinePreviewFooter(document: content.document)
    let view = ReplicaInlinePreviewContainer(previewHeader: header, editorHeader: editorHeader,
                                            contentView: content, footer: footer,
                                            contentSize: content.preferredPreviewSize)
    view.applyContentAppearance()
    connectReplicaPreviewHeader(header, view: view, state: state, item: item, input: input)
    editorHeader.onCancel = { [weak view] in view?.cancelPreviewEditing() }
    editorHeader.onSave = { [weak view] in view?.commitPreviewEditing() }
    view.setCanCommitEditing = { [weak editorHeader] enabled in editorHeader?.setCanCommit(enabled) }
    content.onCancel = { [weak view] in view?.cancelPreviewEditing() }
    content.onSave = { [weak view, weak content] in
        guard content?.canCommit == true else { return }
        view?.commitPreviewEditing()
    }
    return view
}

@MainActor
private func connectReplicaPreviewHeader(_ header: ReplicaInlinePreviewHeader,
                                         view: ItemPreviewView,
                                         state: ReplicaUIState, item: ClipboardItem?,
                                         input: ClipboardRestoreItem?) {
    header.onEdit = { [weak view] in view?.beginPreviewEditing() }
    header.onClose = { [weak view] in
        guard let view else { return }
        (view.previewHeader as! ReplicaInlinePreviewHeader).titleLabel.cancelEditing()
        view.window?.performClose(nil)
    }
    header.titleLabel.onCommitEditing = { [weak view, weak state] title in
        guard let view, let state else { return }
        withExtendedLifetime(view) {
            if let input {
                state.perform { try state.store.updateItem(input, title: title) }
            } else if let item {
                state.perform { try state.store.updateItem(id: item.id, title: title, text: nil) }
            }
        }
    }
}

@MainActor
private final class ReplicaInlinePreviewContainer: ItemPreviewView {
    /// Decorates the actual content; text keeps the zero border.
    func applyContentAppearance() {
        itemContentView.effectiveAppearance.performAsCurrentDrawingAppearance {
            ViewLayerFunctions.setBorderColor(
                SearchSurfaceAppearance.borderColorSlot().pointee, view: itemContentView)
            itemContentView.layer?.borderWidth = itemContentView is ReplicaInlineTextPreviewContent ? 0 : 0.5
            ViewLayerFunctions.setCornerRadius(5, curve: .circular, view: itemContentView)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyContentAppearance()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let shortcut = ShortcutFunctions.shortcutForEvent(event)
        if shortcut.modifierRawValue == NSEvent.ModifierFlags.command.rawValue,
           shortcut.keyCode == ShortcutFunctions.keyCodeForKey("r"),
           editorHeader.isHidden {
            (previewHeader as! ReplicaInlinePreviewHeader).titleLabel.beginEditing()
            return true
        }
        if shortcut.modifierRawValue == NSEvent.ModifierFlags.command.rawValue,
           shortcut.keyCode == ShortcutFunctions.keyCodeForKey("e"),
           editorHeader.isHidden {
            beginPreviewEditing()
            return true
        }
        if shortcut.modifierRawValue == 0, shortcut.keyCode == 0x35 {
            if !editorHeader.isHidden { cancelPreviewEditing() }
            else {
                (previewHeader as! ReplicaInlinePreviewHeader).titleLabel.cancelEditing()
                window?.performClose(nil)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class ReplicaInlinePreviewTextView: NSTextView {
    weak var document: ReplicaRichTextDocument?
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    // normalize rich text before one undoable replacement.
    override func paste(_ sender: Any?) {
        guard let source = NSPasteboard.general.readObjects(forClasses: [NSAttributedString.self],
                                                           options: nil)?.first as? NSAttributedString else {
            super.paste(sender)
            return
        }
        undoManager?.beginUndoGrouping()
        textStorage?.beginEditing()
        if let storage = textStorage {
            let range = selectedRange()
            // has the same font/underline/strike rules.
            let replacement = PreviewAttributedText.normalizedEditingText(source)
            storage.replaceCharacters(in: range, with: replacement)
        }
        textStorage?.endEditing()
        undoManager?.endUndoGrouping()
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == NSSelectorFromString("changeLayoutOrientation:") { return false }
        return super.validateUserInterfaceItem(item)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event)
        if let menu { SearchMenu.compactMenuItems(menu) }
        return menu
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEditable, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers {
            case "s": onSave?(); return true
            case "b": document?.toggle(.bold); return true
            case "i": document?.toggle(.italic); return true
            case "u": document?.toggle(.underline); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if isEditable { onCancel?() }
        else { super.cancelOperation(sender) }
    }
}

@MainActor
private final class ReplicaInlineTextPreviewContent: NSScrollView, PreviewEditableContent {
    let document: ReplicaRichTextDocument
    private let text: ReplicaInlinePreviewTextView
    private weak var state: ReplicaUIState?
    private let itemID: UUID
    private let editInput: ClipboardRestoreItem?
    private let nativeTextModel: TextPreviewModel?
    private var nativeItemObservation: ClipboardItemObservation?
    private var itemObservation: AnyCancellable?
    private var contentObservation: AnyCancellable?
    private var storageBridge: PreviewTextStorageBridge?
    private var fallbackText: NSAttributedString
    private var fallbackEditingText: NSAttributedString
    private var originalText: NSAttributedString { nativeTextModel?.originalText ?? fallbackText }
    private var editingText: NSAttributedString { nativeTextModel?.editingText ?? fallbackEditingText }
    private(set) var canCommit = false
    var onCanCommitEditing: ((Bool) -> Void)?
    var onCancel: (() -> Void)?
    var onSave: (() -> Void)?
    var previewEditingToolbar: NSView? { nil }

    init(state: ReplicaUIState, item: ClipboardItem?, input: ClipboardRestoreItem?) {
        self.state = state
        guard let itemID = input?.id ?? item?.id else { preconditionFailure("Missing preview input") }
        self.itemID = itemID
        editInput = input
        let nativeModel = input.flatMap { TextPreviewModel(input: $0) }
        nativeTextModel = nativeModel
        let nativeSource: ClipboardItemObservation?
        if nativeModel != nil { nativeSource = nil }
        else if let input { nativeSource = input.observeItem() }
        else { nativeSource = state.store.observeItem(id: itemID) }
        nativeItemObservation = nativeSource
        let initial: NSAttributedString
        if let nativeModel {
            initial = nativeModel.originalText
        } else if let nativeSource {
            initial = nativeSource.attributedText ?? NSAttributedString(string: "")
        } else if let item = item ?? input?.resolvedItem() {
            initial = Self.attributedContent(item)
        } else { preconditionFailure("Missing preview content") }
        fallbackText = initial
        fallbackEditingText = nativeModel?.editingText ?? PreviewAttributedText.normalizedEditingText(initial)
        document = ReplicaRichTextDocument(content: initial)
        text = ReplicaInlinePreviewTextView(frame: .zero)
        super.init(frame: .zero)
        hasVerticalScroller = true
        autohidesScrollers = true
        hasHorizontalScroller = false
        borderType = .noBorder
        drawsBackground = false
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = true
        text.allowsUndo = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.maxSize = .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = .init(width: 500, height: CGFloat.greatestFiniteMagnitude)
        text.usesAdaptiveColorMappingForDarkAppearance = true
        let bridge = PreviewTextStorageBridge(editor: text)
        PreviewAttributedText.setEditorText(initial, editor: text)
        PreviewTextColors.applyPreviewTextColors(original: initial, editor: text)
        text.delegate = document
        text.document = document
        text.onSave = { [weak self] in self?.onSave?() }
        text.onCancel = { [weak self] in self?.onCancel?() }
        document.textView = text
        document.usesRecoveredContentEvents = true
        bridge.onTraitsChange = { [weak document] traits in document?.applyRecoveredTraits(traits) }
        bridge.onAttributedTextChange = { [weak document] value in document?.receiveRecoveredContent(value) }
        storageBridge = bridge
        documentView = text
        contentObservation = document.$content.sink { [weak self] content in
            MainActor.assumeIsolated {
                guard let self, let onCanCommitEditing = self.onCanCommitEditing else { return }
                self.canCommit = PreviewAttributedText.hasDifferentText(
                    candidate: content, original: self.originalText, editing: self.editingText)
                onCanCommitEditing(self.canCommit)
            }
        }
        if let nativeModel {
            nativeModel.onChange = { [weak self] in
                guard let self, !self.text.isEditable else { return }
                self.displayStoredModel()
            }
        } else if let nativeSource {
            nativeSource.onTextChange = { [weak self] current in
                self?.receiveStoredText(current)
            }
        } else {
            // No native source is available; retain the existing store adapter.
            itemObservation = state.store.$items.sink { [weak self] items in
                MainActor.assumeIsolated {
                    guard let self,
                          let current = items.first(where: { $0.id == self.itemID }), !current.isDeleted else { return }
                    self.receiveStoredModel(current)
                }
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance { self.applyPreviewTextColors() }
    }

    private func applyPreviewTextColors() {
        PreviewTextColors.applyPreviewTextColors(original: originalText, editor: text)
    }

    var preferredPreviewSize: NSSize {
        let screenSize = NSScreen.main?.frame.size
        let maximum = NSSize(width: (screenSize?.width ?? 2000) * 0.5,
                             height: (screenSize?.height ?? 2000) * 0.5)
        // Measures the stored value, not the editing text.
        let attributed = originalText
        let sample = attributed.length > 2000
            ? attributed.attributedSubstring(from: NSRange(location: 0, length: 2000)) : attributed
        let bounds = sample.boundingRect(with: maximum, options: [.usesLineFragmentOrigin, .usesFontLeading])
        let insets = text.textContainerInset
        let width = bounds.width + (insets.width + insets.width + 20)
        let height = bounds.height + (insets.height + insets.height)
        return .init(width: maximum.width < width ? maximum.width : width,
                     height: maximum.height < height ? maximum.height : height)
    }

    func beginPreviewEditing() {
        text.isEditable = true
        displayStoredModel()
    }

    // runs after the editing window is presented.
    func focusPreviewEditing() {
        window?.makeFirstResponder(text)
    }

    func cancelPreviewEditing() {
        text.isEditable = false
        displayStoredModel()
    }

    func commitPreviewEditing() {
        text.isEditable = false
        guard let state else { return }
        do {
            let content = PreviewAttributedText.previewAttributedString(editor: text)
            if let editInput = nativeTextModel?.item ?? editInput {
                try state.store.updateTextPreviewItem(editInput, attributedString: content)
            } else {
                try state.store.updateTextPreviewItem(id: itemID, attributedString: content)
            }
            state.normalizeSelection()
        } catch {
            // 3c0e08: consume the transaction error and continue the editing cleanup.
        }
        reloadStoredContent()
    }

    private func reloadStoredContent() {
        if let nativeTextModel {
            nativeTextModel.reload()
        } else if let nativeItemObservation {
            guard let current = nativeItemObservation.attributedText else { return }
            replaceStoredText(current)
        } else {
            guard let item = state?.store.items.first(where: { $0.id == itemID }) else { return }
            replaceStoredModel(item)
        }
        displayStoredModel()
    }

    private func receiveStoredText(_ text: NSAttributedString) {
        replaceStoredText(text)
        if !self.text.isEditable { displayStoredModel() }
    }

    private func receiveStoredModel(_ item: ClipboardItem) {
        replaceStoredModel(item)
        if !text.isEditable { displayStoredModel() }
    }

    private func replaceStoredModel(_ item: ClipboardItem) {
        replaceStoredText(Self.attributedContent(item))
    }

    private func replaceStoredText(_ text: NSAttributedString) {
        // Legacy value input keeps its existing two stored baselines.
        fallbackText = text
        fallbackEditingText = PreviewAttributedText.normalizedEditingText(fallbackText)
    }

    private func displayStoredModel() {
        PreviewAttributedText.displayedText(original: originalText, editing: editingText, editor: text)
        PreviewTextColors.applyPreviewTextColors(original: originalText, editor: text)
    }

    private static func attributedContent(_ item: ClipboardItem) -> NSAttributedString {
        // Reads only the first representation.
        // Its rich-text priority, table removal and same-item plain fallback are shared here.
        let items = (try? ClipboardStore.originalPasteboardItems(from: item.payloads)) ?? []
        return items.first?.attributedString() ?? NSAttributedString(string: "")
    }
}

@MainActor
private final class ReplicaPreviewActionMenuItem: NSMenuItem {
    private let invoke: () -> Void
    init(title: String, invoke: @escaping () -> Void) {
        self.invoke = invoke
        super.init(title: title, action: #selector(performMenuAction), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func performMenuAction() { invoke() }
}

@MainActor
private final class ReplicaInlinePreviewHeader: NSView {
    var onEdit: (() -> Void)?
    var onClose: (() -> Void)?
    let titleLabel = PreviewTitleLabel()
    private var itemObservation: AnyCancellable?
    private var pinboardObservation: AnyCancellable?
    private weak var state: ReplicaUIState?
    private let itemID: UUID
    private var pinButton: ToolbarButton?
    private var sharingPicker: NSSharingServicePicker?
    private var input: ClipboardRestoreItem?

    init(state: ReplicaUIState, item: ClipboardItem?, input: ClipboardRestoreItem?) {
        self.state = state
        guard let itemID = input?.id ?? item?.id else { preconditionFailure("Missing preview input") }
        self.itemID = itemID
        self.input = input
        super.init(frame: .zero)
        let close = NSButton()
        configureCloseButton(close)
        let edit = ToolbarButton(title: String(localized: PreviewLocalization.generalActionEdit())) { [weak self] _ in self?.onEdit?() }
        let pin = ToolbarButton(symbol: "circle.dashed", toolTip: String(localized: PreviewLocalization.generalActionPin())) { [weak self] button in
            self?.showPinMenu(from: button)
        }
        pin.hasPullDownArrow = true
        pinButton = pin
        let share = ToolbarButton(symbol: "square.and.arrow.up", toolTip: String(localized: PreviewLocalization.generalActionShare())) { [weak self] button in
            self?.showSharingPicker(from: button)
        }
        let row = NSStackView(views: [pin, share, edit])
        row.spacing = 8
        row.alignment = .centerY
        for child in [close, titleLabel, row] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            close.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: close.trailingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: row.leadingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        let update: (ClipboardItem) -> Void = { [weak self, weak share] current in
            guard let self else { return }
            let field = self.titleLabel.makeTextField()
            let rawType: Int
            switch current.kind {
            case .unknown: rawType = 0
            case .image: rawType = 1
            case .color: rawType = 2
            case .files: rawType = 3
            case .link: rawType = 4
            case .text, .richText: rawType = 5
            }
            let defaultTitle = PreviewTitles.itemTypeTitle(rawType: rawType,
                fileCount: current.kind == .files ? current.decodedFilePreviewMetadata?.paths.count : nil)
            field.setPlaceholder(defaultTitle)
            field.updateText(PreviewTitles.titleOrDefault(current.originalTitle, defaultTitle: defaultTitle))
            share?.isEnabled = (try? Self.sharingContent(current))
                .map { PreviewSharing.hasShareableItems($0) } ?? false
            self.refreshPinAppearance(current)
        }
        let receive: (ClipboardRestoreItem) -> Void = { [weak self, weak share] current in
            guard let self else { return }
            self.input = current
            if current.isDeleted {
                self.titleLabel.cancelEditing()
                self.window?.performClose(nil)
                return
            }
            if let title = current.previewTitle() {
                let field = self.titleLabel.makeTextField()
                field.setPlaceholder(title.defaultTitle)
                field.updateText(title.title)
                if let pin = current.previewPinboard() {
                    self.refreshNativePinAppearance(isPinned: pin.isPinned, colorCode: pin.colorCode)
                }
                share?.isEnabled = current.previewSharingContent().map(PreviewSharing.hasShareableItems) ?? false
            } else {
                update(current.resolvedItem())
            }
        }
        itemObservation = input?.observeChanges(receive)
        if itemObservation != nil, let input {
            receive(input)
        } else {
            itemObservation = state.store.$items.sink { items in
                MainActor.assumeIsolated {
                    guard let current = items.first(where: { $0.id == itemID }) else { return }
                    update(current)
                }
            }
        }
        pinboardObservation = state.store.$pinboards.sink { [weak self] boards in
            MainActor.assumeIsolated {
                guard let self, self.input?.isDeleted != true else { return }
                if let pin = self.input?.previewPinboard() {
                    self.refreshNativePinAppearance(isPinned: pin.isPinned, colorCode: pin.colorCode)
                } else if let item = self.state?.store.items.first(where: { $0.id == self.itemID }) {
                    self.refreshPinAppearance(item, boards: boards)
                }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func refreshNativePinAppearance(isPinned: Bool, colorCode: UInt64?) {
        pinButton?.symbol = isPinned ? "circle.fill" : "circle.dashed"
        pinButton?.contentTintColor = colorCode.map { PinboardColor(canonicalColorCode: $0).color() }
    }

    private func refreshPinAppearance(_ item: ClipboardItem, boards: [Pinboard]? = nil) {
        let owner: Pinboard?
        if let boards {
            owner = item.pinboardOwnerID.flatMap { ownerID in boards.first { $0.id == ownerID } }
        } else {
            owner = state?.store.pinboardOwner(for: item)
        }
        let pinboard = owner?.rawType == 2 ? owner : nil
        pinButton?.symbol = pinboard == nil ? "circle.dashed" : "circle.fill"
        pinButton?.contentTintColor = pinboard.flatMap { board in
            guard let code = PinboardAttributes.colorCode(from: board.rawAttributes) else { return nil }
            return PinboardColor(canonicalColorCode: code).color()
        }
    }

    private static func pinColor(_ hex: String) -> NSColor? {
        let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                       green: CGFloat((rgb >> 8) & 255) / 255,
                       blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    private func showNativePinMenu(from button: NSButton, input: ClipboardRestoreItem) {
        guard let state else { return }
        // 3c24a8/3c24b8 creates and reads a collection for each preview menu invocation.
        let targets = state.store.makePinboardCollection().value
        let menu = NSMenu()
        for target in targets {
            let entry = ReplicaPreviewActionMenuItem(title: target.name) { [weak self] in
                guard let self, let state = self.state, let current = self.input else { return }
                // 3c3590 reads the model's current item when the action runs.
                state.perform { try state.store.assign(items: [current], to: target) }
            }
            entry.state = input.isAssigned(to: target) == true ? .on : .off
            let color = target.colorCode.map { PinboardColor(canonicalColorCode: $0).color() } ?? .clear
            entry.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { bounds in
                color.setFill()
                NSBezierPath(ovalIn: bounds).fill()
                return true
            }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(ReplicaPreviewActionMenuItem(title: SearchLocalization.text("blinkclip.action.create-group") + "...") { [weak self] in
            self?.createPinboardForCurrentItem()
        })
        if input.previewPinboard()?.isPinned == true {
            menu.addItem(ReplicaPreviewActionMenuItem(title: String(localized: PreviewLocalization.generalActionUnpin())) { [weak self] in
                guard let self, let state = self.state, let current = self.input else { return }
                state.perform { try state.store.assign(items: [current], to: nil) }
            })
        }
        menu.popUp(positioning: nil, at: NSPoint(x: -10, y: 0), in: button)
    }

    private func showPinMenu(from button: NSButton) {
        if let input, input.hasNativeEntity {
            showNativePinMenu(from: button, input: input)
            return
        }
        guard let state, let item = state.store.items.first(where: { $0.id == itemID }) else { return }
        let menu = NSMenu()
        for board in state.store.pinboards {
            let entry = ReplicaPreviewActionMenuItem(title: board.name) { [weak self] in
                guard let self, let state = self.state else { return }
                state.perform { try state.store.assign(ids: [self.itemID], to: board.id) }
            }
            entry.state = item.pinboardIDs.contains(board.id) ? .on : .off
            let color = Self.pinColor(board.colorHex) ?? .clear
            let image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { bounds in
                color.setFill()
                NSBezierPath(ovalIn: bounds).fill()
                return true
            }
            entry.image = image
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(ReplicaPreviewActionMenuItem(title: SearchLocalization.text("blinkclip.action.create-group") + "...") { [weak self] in
            self?.createPinboardForCurrentItem()
        })
        if !item.pinboardIDs.isEmpty {
            menu.addItem(ReplicaPreviewActionMenuItem(title: String(localized: PreviewLocalization.generalActionUnpin())) { [weak self] in
                guard let self, let state = self.state else { return }
                state.perform { try state.store.assign(ids: [self.itemID], to: nil) }
            })
        }
        menu.popUp(positioning: nil, at: NSPoint(x: -10, y: 0), in: button)
    }

    private func createPinboardForCurrentItem() {
        guard let state else { return }
        if input?.hasNativeEntity == true {
            state.perform {
                let board = try state.store.createPinboardTarget(name: String(localized: PreviewLocalization.generalUntitled()))
                guard let current = self.input else { return }
                try state.store.assign(items: [current], to: board)
            }
            return
        }
        let alert = NSAlert()
        alert.messageText = SearchLocalization.text("blinkclip.action.create-group")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: String(localized: PreviewLocalization.generalActionSave()))
        alert.addButton(withTitle: String(localized: PreviewLocalization.generalActionCancel()))
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        state.perform {
            let board = try state.store.createPinboard(name: name)
            try state.store.assign(ids: [itemID], to: board.id)
        }
    }

    private static func sharingContent(_ item: ClipboardItem) throws -> PreviewSharing.Content {
        let content = try ClipboardStore.originalPasteboardItems(from: item.payloads)
        let kind: PasteboardContentKind
        switch item.kind {
        case .image: kind = .image
        case .files: kind = .files
        case .link: kind = .link
        case .color: kind = .color
        case .text, .richText: kind = .text
        case .unknown: kind = .unknown
        }
        return .init(items: content, rawType: Int(kind.rawValue))
    }

    private func showSharingPicker(from button: NSButton) {
        if let content = input?.previewSharingContent() {
            let picker = PreviewSharing.makeSharingServicePicker([content])
            sharingPicker = picker
            picker.show(relativeTo: .zero, of: button, preferredEdge: .minY)
            return
        }
        guard let state, let item = state.store.items.first(where: { $0.id == itemID }) else { return }
        do {
            let picker = PreviewSharing.makeSharingServicePicker([try Self.sharingContent(item)])
            sharingPicker = picker
            picker.show(relativeTo: .zero, of: button, preferredEdge: .minY)
        } catch { state.controller?.presentError(error) }
    }

    private func configureCloseButton(_ button: NSButton) {
        if NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil) == nil {
            button.image = NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)!
        } else {
            button.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)!
        }
        button.imagePosition = .imageOnly
        button.contentTintColor = SearchAppearance.foregroundColor()
        button.isBordered = false
        button.alphaValue = 0.6
        button.action = #selector(closeAction)
        button.target = self
    }

    @objc private func editAction() { onEdit?() }
    @objc private func closeAction() { onClose?() }
    override func cancelOperation(_ sender: Any?) { titleLabel.cancelEditing() }
}

@MainActor
private final class ReplicaInlinePreviewEditorHeader: NSView {
    var onCancel: (() -> Void)?
    var onSave: (() -> Void)?
    private var saveButton: NSButton?
    init(document: ReplicaRichTextDocument? = nil) {
        super.init(frame: .zero)
        let cancel = ToolbarButton(title: String(localized: PreviewLocalization.generalActionCancel()), shortcut: .init(keyCode: ShortcutFunctions.escapeKeyCode(), internalModifiers: 0), toolTip: String(localized: PreviewLocalization.editItemToolbarDiscardChanges())) { [weak self] _ in self?.onCancel?() }
        let save = ToolbarButton(title: String(localized: PreviewLocalization.generalActionSave()), shortcut: .init(keyCode: Int(ShortcutFunctions.keyCodeForKey("s")), internalModifiers: NSEvent.ModifierFlags.command.rawValue), toolTip: String(localized: PreviewLocalization.editItemToolbarSaveChanges())) { [weak self] _ in self?.onSave?() }
        save.isPrimary = true
        save.isEnabled = false
        saveButton = save
        for view in [cancel, save] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        NSLayoutConstraint.activate([
            cancel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            cancel.centerYAnchor.constraint(equalTo: centerYAnchor),
            save.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            save.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        if let document {
            let toolbar = ReplicaInlinePreviewFormatting(document: document)
            toolbar.translatesAutoresizingMaskIntoConstraints = false
            addSubview(toolbar)
            NSLayoutConstraint.activate([
                toolbar.centerXAnchor.constraint(equalTo: centerXAnchor),
                toolbar.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setCanCommit(_ enabled: Bool) { saveButton?.isEnabled = enabled }
    @objc private func cancelAction() { onCancel?() }
    @objc private func saveAction() { onSave?() }
}

@MainActor
private final class ReplicaInlinePreviewFormatting: NSView {
    private let buttons: [ToolbarButton]

    init(document: ReplicaRichTextDocument) {
        buttons = [
            ToolbarButton(symbol: "bold", shortcut: .init(keyCode: Int(ShortcutFunctions.keyCodeForKey("b")), internalModifiers: NSEvent.ModifierFlags.command.rawValue), toolTip: String(localized: PreviewLocalization.editItemToolbarTextBold())) { [weak document] _ in document?.toggle(.bold) },
            ToolbarButton(symbol: "italic", shortcut: .init(keyCode: Int(ShortcutFunctions.keyCodeForKey("i")), internalModifiers: NSEvent.ModifierFlags.command.rawValue), toolTip: String(localized: PreviewLocalization.editItemToolbarTextItalic())) { [weak document] _ in document?.toggle(.italic) },
            ToolbarButton(symbol: "underline", shortcut: .init(keyCode: Int(ShortcutFunctions.keyCodeForKey("u")), internalModifiers: NSEvent.ModifierFlags.command.rawValue), toolTip: String(localized: PreviewLocalization.editItemToolbarTextUnderline())) { [weak document] _ in document?.toggle(.underline) },
            ToolbarButton(symbol: "strikethrough", toolTip: String(localized: PreviewLocalization.editItemToolbarTextStrikethrough())) { [weak document] _ in document?.toggle(.strikethrough) }
        ]
        super.init(frame: .zero)
        let row = NSStackView(views: buttons)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        document.onRecoveredTraitsChange = { [weak self] traits in _ = self?.updateTraitButtons(traits) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    private func updateTraitButtons(_ traits: Set<PreviewTextTraits.Trait>) -> Int {
        for (index, trait) in [PreviewTextTraits.Trait.bold, .italic, .underline, .strikethrough].enumerated() {
            buttons[index].isSelected = PreviewTextTraits.contains(trait, in: traits)
        }
        return 0
    }
}

@MainActor
private final class ReplicaInlinePreviewFooter: PreviewFooterView {
    private var contentObservation: AnyCancellable?
    init(document: ReplicaRichTextDocument) {
        super.init()
        contentObservation = document.$content.sink { [weak self] content in
            MainActor.assumeIsolated {
                self?.setContentView(PreviewTextMetaView(text: content.string))
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
