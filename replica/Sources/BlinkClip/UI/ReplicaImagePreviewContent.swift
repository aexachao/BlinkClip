import AppKit
import Combine
import BlinkClipCore

/// The editable image renderer shares the already recovered zoom/Live Text view.
@MainActor
final class ReplicaImagePreviewContent: NSView, PreviewEditableContent, NSUserInterfaceValidations {
    private weak var state: ReplicaUIState?
    private let itemID: UUID
    private let editInput: ClipboardRestoreItem?
    private let checkerboardView = ImageCheckerboardView(frame: .zero)
    private let zoomView = ZoomableImageView()
    private let metadataHost = NSView()
    private let editingUndoManager = UndoManager()
    private var itemObservation: AnyCancellable?
    private var sourcePayloads: [String: Data] = [:]
    private var imageMetadataSize: NSSize = .zero
    private var quarterTurns = 0
    private var isEditing = false
    private(set) var canCommit = false
    var onCanCommitEditing: ((Bool) -> Void)?
    var previewMetadataView: NSView? { metadataHost }

    private lazy var toolbar: NSStackView = {
        let left = ToolbarButton(symbol: "rotate.left",
            shortcut: .init(keyCode: Int(ShortcutFunctions.keyCodeForKey("l")),
                            internalModifiers: NSEvent.ModifierFlags.command.rawValue),
            toolTip: String(localized: PreviewLocalization.editItemToolbarImageRotateLeft())) { [weak self] _ in
                self?.rotateLeft()
            }
        let right = ToolbarButton(symbol: "rotate.right",
            shortcut: .init(keyCode: Int(ShortcutFunctions.keyCodeForKey("r")),
                            internalModifiers: NSEvent.ModifierFlags.command.rawValue),
            toolTip: String(localized: PreviewLocalization.editItemToolbarImageRotateRight())) { [weak self] _ in
                self?.rotateRight()
            }
        return NSStackView(views: [left, right])
    }()

    var previewEditingToolbar: NSView? { toolbar }

    init(state: ReplicaUIState, item: ClipboardItem?, input: ClipboardRestoreItem? = nil) {
        self.state = state
        guard let itemID = input?.id ?? item?.id else { preconditionFailure("Missing image preview input") }
        self.itemID = itemID
        editInput = input
        super.init(frame: .zero)
        addSubview(checkerboardView)
        checkerboardView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zoomView)
        zoomView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(checkerboardConstraints())
        if input?.hasNativeEntity == true {
            zoomView.setImage(input?.previewImage())
            zoomView.setTextRecognitionEnabled(false)
            updateMetadataAndCommitState()
        } else if let item = item ?? input?.resolvedItem() {
            replaceDisplayedItem(item)
            itemObservation = state.store.$items.sink { [weak self] items in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard let current = items.first(where: { $0.id == self.itemID }),
                          !current.isDeleted, current.kind == .image else {
                        self.window?.performClose(nil)
                        return
                    }
                    if !self.isEditing { self.replaceDisplayedItem(current) }
                }
            }
        } else { preconditionFailure("Missing image preview content") }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func checkerboardConstraints() -> [NSLayoutConstraint] {
        [
            checkerboardView.topAnchor.constraint(equalTo: topAnchor),
            checkerboardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            checkerboardView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -CGFloat.zero),
            checkerboardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -CGFloat.zero),
            zoomView.topAnchor.constraint(equalTo: topAnchor),
            zoomView.leadingAnchor.constraint(equalTo: leadingAnchor),
            zoomView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -CGFloat.zero),
            zoomView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -CGFloat.zero)
        ]
    }

    override var acceptsFirstResponder: Bool { true }
    override var undoManager: UndoManager? { editingUndoManager }

    var preferredPreviewSize: NSSize {
        let imageSize = editInput?.previewImageSize() ?? imageMetadataSize
        let screen = NSScreen.main!.frame.size
        let halfWidth = screen.width * 0.5
        let halfHeight = screen.height * 0.5
        // Returns the source dimensions when both comparisons
        // are nonnegative or unordered; it does not impose a minimum canvas size.
        if !(halfWidth < imageSize.width), !(halfHeight < imageSize.height) { return imageSize }
        let widthScale = halfWidth / imageSize.width
        let heightScale = halfHeight / imageSize.height
        let scale = heightScale < widthScale ? heightScale : widthScale
        return NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    func beginPreviewEditing() {
        isEditing = true
        zoomView.setTextRecognitionEnabled(true)
        window?.makeFirstResponder(self)
    }

    func cancelPreviewEditing() {
        finishEditing(reloadNativeImage: true)
    }

    func commitPreviewEditing() {
        if let image = zoomView.currentImage(), let state {
            do {
                if let editInput {
                    try state.store.updateImagePreviewItem(editInput, payloads: Self.encodedPayloads(image))
                } else {
                    try state.store.updateImagePreviewItem(id: itemID, payloads: Self.encodedPayloads(image))
                }
                state.normalizeSelection()
            } catch {
                // 3bde74: consume the transaction error and continue the editing cleanup.
            }
        }
        finishEditing(reloadNativeImage: false)
    }

    private func finishEditing(reloadNativeImage: Bool) {
        isEditing = false
        if editInput?.hasNativeEntity == true {
            if reloadNativeImage { zoomView.setImage(editInput?.previewImage()) }
            zoomView.setTextRecognitionEnabled(false)
            quarterTurns = 0
            editingUndoManager.removeAllActions()
            updateMetadataAndCommitState()
            return
        }
        quarterTurns = 0
        editingUndoManager.removeAllActions()
        if let current = state?.store.items.first(where: { $0.id == itemID }) {
            replaceDisplayedItem(current, force: true)
        }
    }

    private func replaceDisplayedItem(_ item: ClipboardItem, force: Bool = false) {
        imageMetadataSize = item.decodedImagePreviewMetadata?.size ?? .zero
        let payloads = item.payloads.filter { !$0.key.hasPrefix("com.chrisli.blinkclip.internal.recognized-") }
        guard force || payloads != sourcePayloads else { return }
        sourcePayloads = payloads
        zoomView.setImage(Self.previewImage(from: item.payloads))
        zoomView.setTextRecognitionEnabled(false)
        updateMetadataAndCommitState()
    }

    private static func previewImage(from payloads: [String: Data]) -> NSImage? {
        guard let items = try? ClipboardStore.originalPasteboardItems(from: payloads) else { return nil }
        for item in items {
            guard let data = item.imageData(), NSImage(data: data) != nil else { continue }
            return item.imageData().flatMap(NSImage.init(data:))
        }
        return nil
    }

    private func rotateRight() {
        let next = quarterTurns + 1
        quarterTurns = next > 3 ? 0 : next
        rotateDisplayedImage(degrees: -90)
        editingUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            MainActor.assumeIsolated { self?.rotateLeft() }
        }
    }

    private func rotateLeft() {
        let next = quarterTurns - 1
        quarterTurns = next < 0 ? 3 : next
        rotateDisplayedImage(degrees: 90)
        editingUndoManager.registerUndo(withTarget: self) { [weak self] _ in
            MainActor.assumeIsolated { self?.rotateRight() }
        }
    }

    private func rotateDisplayedImage(degrees: Double) {
        let rotated = zoomView.currentImage().map { Self.rotatedImage($0, degrees: degrees) }
        zoomView.setImage(rotated)
        updateMetadataAndCommitState()
    }

    private func updateMetadataAndCommitState() {
        guard let image = zoomView.currentImage() else { return }
        let metadata = ReplicaImageDimensionsView(image: image)
        metadataHost.subviews = []
        metadata.translatesAutoresizingMaskIntoConstraints = false
        metadataHost.addSubview(metadata)
        NSLayoutConstraint.activate([
            metadata.topAnchor.constraint(equalTo: metadataHost.topAnchor),
            metadata.leadingAnchor.constraint(equalTo: metadataHost.leadingAnchor),
            metadata.bottomAnchor.constraint(equalTo: metadataHost.bottomAnchor),
            metadata.trailingAnchor.constraint(equalTo: metadataHost.trailingAnchor)
        ])
        canCommit = quarterTurns != 0
        onCanCommitEditing?(canCommit)
    }

    @objc private func undo(_ sender: Any?) { editingUndoManager.undo() }
    @objc private func redo(_ sender: Any?) { editingUndoManager.redo() }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return isEditing && editingUndoManager.canUndo }
        if item.action == #selector(redo(_:)) { return isEditing && editingUndoManager.canRedo }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isEditing, event.charactersIgnoringModifiers?.lowercased() == "z" {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command { editingUndoManager.undo(); return true }
            if flags == [.command, .shift] { editingUndoManager.redo(); return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// always swaps the canvas dimensions, including for
    /// angles other than the two quarter-turns used by the image toolbar.
    static func rotatedImage(_ image: NSImage, degrees: Double) -> NSImage {
        let originalSize = image.size
        let size = NSSize(width: image.size.height, height: image.size.width)
        let rotated = NSImage(size: size)
        rotated.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        let transform = CGAffineTransform.identity.translatedBy(x: size.width * 0.5, y: size.height * 0.5)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: image.size.width * -0.5, y: image.size.height * -0.5)
        NSGraphicsContext.current?.cgContext.concatenate(transform)
        image.draw(at: .zero, from: NSRect(origin: .zero, size: originalSize), operation: .copy, fraction: 1)
        rotated.unlockFocus()
        return rotated
    }

    private static func encodedPayloads(_ image: NSImage) -> [String: Data] {
        if let data = PasteboardImageEncoding.pngData(image) {
            return [NSPasteboard.PasteboardType.png.rawValue: data]
        }
        if let data = ImagePreviewMetadataGenerator.jpegData(image, compression: 0.5) {
            return ["public.jpeg": data]
        }
        return [:]
    }

}

@MainActor
private final class ReplicaImageDimensionsView: NSStackView {
    init(image: NSImage) {
        super.init(frame: .zero)
        let size = image.size
        let label = NSTextField(labelWithString: "\(Int(size.width)) × \(Int(size.height))")
        label.font = SearchAppearance.bodyFont()
        label.textColor = ToolbarAppearance.secondaryForeground()
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.drawsBackground = false
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(250), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(250), for: .horizontal)
        addArrangedSubview(label)
        addArrangedSubview(spacer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
