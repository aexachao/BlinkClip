import AppKit

/// TextEditor uses a union of all selected runs, not the first run's attributes.
@MainActor
public enum PreviewTextTraits {
    public enum Trait: UInt8, Hashable, Sendable { case bold = 0, italic = 1, underline = 2, strikethrough = 3 }

    public static func traitsFromAttributes(_ attributes: [NSAttributedString.Key: Any]) -> Set<Trait> {
        var result: Set<Trait> = []
        if let font = attributes[.font] as? NSFont {
            if font.fontDescriptor.symbolicTraits.contains(.bold) { result.insert(.bold) }
            if font.fontDescriptor.symbolicTraits.contains(.italic) { result.insert(.italic) }
        }
        if let underline = attributes[.underlineStyle] as? Int, underline == 1 { result.insert(.underline) }
        if let strike = attributes[.strikethroughStyle] as? Int, strike == 1 { result.insert(.strikethrough) }
        return result
    }

    public static func contains(_ trait: Trait, in traits: Set<Trait>) -> Bool {
        traits.contains(trait)
    }

    public static func formUnion(_ traits: Set<Trait>, accumulating result: inout Set<Trait>) {
        result.formUnion(traits)
    }

    public static func accumulateTraits(_ attributes: [NSAttributedString.Key: Any],
                                  accumulating result: inout Set<Trait>) {
        formUnion(traitsFromAttributes(attributes), accumulating: &result)
    }

    public static func accumulateEnumeratedTraits(_ attributes: [NSAttributedString.Key: Any],
                                  accumulating result: inout Set<Trait>) {
        accumulateTraits(attributes, accumulating: &result)
    }

    public static func traitsAtSelection(editor: NSTextView) -> Set<Trait> {
        let range = editor.selectedRange()
        let content = PreviewAttributedText.editorAttributedString(editor: editor)
        if range.location <= content.length {
            let end = range.location + range.length
            if end <= content.length, editor.selectedRange().length != 0 {
                var traits: Set<Trait> = []
                let selectedContent = PreviewAttributedText.editorAttributedString(editor: editor)
                selectedContent.enumerateAttributes(in: editor.selectedRange(), options: []) { attributes, _, _ in
                    accumulateEnumeratedTraits(attributes, accumulating: &traits)
                }
                return traits
            }
        }
        return traitsFromAttributes(editor.typingAttributes)
    }

    /// The second flag forces removal; false toggles according to this run's attributes.
    public static func attributesApplyingTrait(_ trait: Trait, forceRemove: Bool,
                                   attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        let remove = forceRemove || contains(trait, in: traitsFromAttributes(attributes))
        var result = attributes
        switch trait {
        case .underline, .strikethrough:
            let key: NSAttributedString.Key = trait == .underline ? .underlineStyle : .strikethroughStyle
            if remove { result.removeValue(forKey: key) }
            else { result[key] = 1 }
        case .bold, .italic:
            guard let font = attributes[.font] as? NSFont else { return result }
            let originalTraits = font.fontDescriptor.symbolicTraits
            let cleared = PreviewAttributedText.descriptorWithTraits(font.fontDescriptor, traits: [])
            let changed = cleared.flatMap { descriptor in
                let mask: NSFontDescriptor.SymbolicTraits = trait == .bold ? .bold : .italic
                let traits = remove ? originalTraits.subtracting(mask) : originalTraits.union(mask)
                return PreviewAttributedText.descriptorWithTraits(descriptor, traits: traits)
            }
            if let changedFont = NSFont(descriptor: changed ?? font.fontDescriptor, size: font.pointSize) {
                result[.font] = changedFont
            } else { result.removeValue(forKey: .font) }
        }
        return result
    }

    @discardableResult
    public static func setTraitInStorage(_ attributes: [NSAttributedString.Key: Any], range: NSRange,
                                   storage: NSTextStorage, trait: Trait, forceRemove: Bool) -> Int {
        for key in attributes.keys { storage.removeAttribute(key, range: range) }
        storage.addAttributes(attributesApplyingTrait(trait, forceRemove: forceRemove, attributes: attributes), range: range)
        return 0
    }

    public static func toggleTrait(_ trait: Trait, editor: NSTextView, range requestedRange: NSRange? = nil) {
        let range = requestedRange ?? editor.selectedRange()
        if range.length < 1 {
            editor.typingAttributes = attributesApplyingTrait(trait, forceRemove: false, attributes: editor.typingAttributes)
        } else if let storage = editor.textStorage {
            let first = storage.attributes(at: range.location, effectiveRange: nil)
            let forceRemove = contains(trait, in: traitsFromAttributes(first))
            storage.beginEditing()
            storage.enumerateAttributes(in: range, options: []) { attributes, run, _ in
                setTraitInStorage(attributes, range: run, storage: storage, trait: trait, forceRemove: forceRemove)
            }
            storage.endEditing()
        }
        editor.undoManager?.registerUndo(withTarget: editor) { [weak editor] _ in
            MainActor.assumeIsolated {
                guard let editor else { return }
                toggleTrait(trait, editor: editor, range: range)
            }
        }
    }
}

/// Bridges the two original asynchronous paths without synthesizing text-change
/// notifications for typing-attribute changes.
@MainActor
public final class PreviewTextStorageBridge: NSObject, NSTextStorageDelegate {
    public var onTraitsChange: ((Set<PreviewTextTraits.Trait>) -> Void)?
    public var onAttributedTextChange: ((NSAttributedString) -> Void)?
    private let editor: NSTextView
    private var typingAttributesObserver: NSKeyValueObservation?

    public init(editor: NSTextView) {
        self.editor = editor
        super.init()
        setupEditor(editor: editor)
        // Passes options=1 (.new), without .initial.
        typingAttributesObserver = editor.observe(\.typingAttributes, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                _ = Self.deliverTraits(from: { [weak self] in self })
            }
        }
    }

    @discardableResult
    public func setupEditor(editor: NSTextView) -> Int {
        editor.isEditable = false
        editor.font = PreviewAttributedText.plainTextFont()
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.linkTextAttributes = [.cursor: NSCursor.pointingHand]
        editor.autoresizingMask = [.width]
        editor.textStorage?.delegate = self
        return 0
    }

    @discardableResult
    public func updateTraits() -> Bool {
        let traits = PreviewTextTraits.traitsAtSelection(editor: editor)
        onTraitsChange?(traits)
        return false
    }

    public func deliverStorageChange() {
        Self.deliverStorageChange(from: { [weak self] in self })
    }

    private static func deliverStorageChange(from loadOwner: () -> PreviewTextStorageBridge?) {
        _ = deliverTraits(from: loadOwner)
        deliverContent(from: loadOwner)
    }

    // Separate calls end the first strong-owner scope before the second weak load (214998/2149a4).
    @inline(never)
    private static func deliverTraits(from loadOwner: () -> PreviewTextStorageBridge?) -> Bool {
        guard let owner = loadOwner() else { return true }
        return owner.updateTraits()
    }

    @inline(never)
    private static func deliverContent(from loadOwner: () -> PreviewTextStorageBridge?) {
        guard let owner = loadOwner(), let callback = owner.onAttributedTextChange else { return }
        callback(PreviewAttributedText.editorAttributedString(editor: owner.editor))
    }

    public func scheduleStorageChangeDelivery() {
        Task { @MainActor [weak self] in
            Self.deliverStorageChange(from: { [weak self] in self })
        }
    }

    nonisolated public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                            range editedRange: NSRange, changeInLength delta: Int) {
        MainActor.assumeIsolated { scheduleStorageChangeDelivery() }
    }
}
