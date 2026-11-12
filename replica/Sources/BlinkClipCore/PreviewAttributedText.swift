import AppKit

/// Recovered local attributed-text operations used by the preview content model.
@MainActor
public enum PreviewAttributedText {
    /// the platform body font with an empty options dictionary.
    public static func bodyFont() -> NSFont {
        NSFont.preferredFont(forTextStyle: .body, options: [:])
    }

    /// the original's fixed editing font, with its nil trap.
    public static func plainTextFont() -> NSFont {
        NSFont(name: "HelveticaNeue", size: 13)!
    }

    /// clear traits, apply the requested traits, preserve both fallbacks.
    public static func fontWithTraits(font: NSFont,
                                 traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = font.fontDescriptor
        let cleared = descriptorWithTraits(descriptor, traits: [])
        let requested = cleared.flatMap { descriptorWithTraits($0, traits: traits) }
        return NSFont(descriptor: requested ?? font.fontDescriptor, size: font.pointSize) ?? font
    }

    // The older build SDK imports this selector as nonnull. The recovered binary
    // explicitly checks both returned descriptors for nil, so retain that ObjC ABI.
    static func descriptorWithTraits(_ descriptor: NSFontDescriptor,
                                             traits: NSFontDescriptor.SymbolicTraits) -> NSFontDescriptor? {
        let selector = NSSelectorFromString("fontDescriptorWithSymbolicTraits:")
        typealias Getter = @convention(c) (NSFontDescriptor, Selector, UInt32) -> Unmanaged<NSFontDescriptor>?
        let getter = unsafeBitCast(descriptor.method(for: selector)!, to: Getter.self)
        return getter(descriptor, selector, traits.rawValue)?.takeUnretainedValue()
    }

    /// Foundation ranges use the attributed string's UTF-16 length.
    public static func fullRange(_ source: NSAttributedString) -> NSRange {
        NSRange(location: 0, length: source.length)
    }

    /// the first nonempty run clears the flag and stops enumeration.
    public static func markIfAttributed(attributes: [NSAttributedString.Key: Any],
                                  isUnattributed: inout Bool,
                                  stop: UnsafeMutablePointer<ObjCBool>) {
        if !attributes.isEmpty {
            isUnattributed = false
            stop.pointee = true
        }
    }

    /// empty text or text with no attributes is considered plain.
    public static func isPlainText(_ source: NSAttributedString) -> Bool {
        var isUnattributed = true
        source.enumerateAttributes(in: fullRange(source), options: []) { attributes, _, stop in
            markIfAttributed(attributes: attributes, isUnattributed: &isUnattributed, stop: stop)
        }
        return isUnattributed
    }

    /// clear text blocks only when a run has a paragraph style.
    public static func applyParagraphStyle(attributes: [NSAttributedString.Key: Any], range: NSRange,
                                  destination: NSMutableAttributedString) {
        guard !attributes.isEmpty,
              let paragraph = attributes[.paragraphStyle] as? NSParagraphStyle,
              let mutable = paragraph.mutableCopy() as? NSMutableParagraphStyle else { return }
        mutable.textBlocks = []
        destination.addAttribute(.paragraphStyle, value: mutable, range: range)
    }

    /// return a mutable copy with paragraph table blocks removed.
    public static func attributedStringWithNormalizedParagraphs(_ source: NSAttributedString) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        result.enumerateAttributes(in: fullRange(result), options: []) { attributes, range, _ in
            applyParagraphStyle(attributes: attributes, range: range, destination: result)
        }
        return result
    }

    /// retain only the original bold/italic traits and underline/strike.
    public static func copyFontTraits(attributes: [NSAttributedString.Key: Any], range: NSRange,
                                  destination: NSMutableAttributedString) {
        for (key, value) in attributes {
            if key == .font, let font = value as? NSFont {
                let traits = NSFontDescriptor.SymbolicTraits(rawValue: font.fontDescriptor.symbolicTraits.rawValue & 3)
                destination.addAttribute(.font, value: fontWithTraits(font: plainTextFont(), traits: traits), range: range)
            } else if key == .underlineStyle || key == .strikethroughStyle {
                destination.addAttribute(key, value: value, range: range)
            }
        }
    }

    /// The editing-text half, after local source data has been decoded.
    public static func normalizedEditingText(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: source.string, attributes: [.font: plainTextFont()])
        result.beginEditing()
        source.enumerateAttributes(in: fullRange(source), options: []) { attributes, range, _ in
            copyFontTraits(attributes: attributes, range: range, destination: result)
        }
        result.endEditing()
        return result
    }

    /// nonempty changed text, with the original plain/rich baseline choice.
    public static func hasDifferentText(candidate: NSAttributedString,
                                  original: @autoclosure () -> NSAttributedString,
                                  editing: @autoclosure () -> NSAttributedString) -> Bool {
        guard !candidate.string.isEmpty else { return false }
        let isPlain = isPlainText(original())
        // The model's selected slot is read after attribute enumeration, not before it.
        return (isPlain ? editing() : original()) != candidate
    }

    /// PastePlatform's NSTextView.attributedText Objective-C getter.
    public static func editorAttributedString(editor: NSTextView) -> NSAttributedString {
        editorTextStorage(editor: editor)
    }

    /// preserve the actual storage identity; only nil creates empty storage.
    public static func editorTextStorage(editor: NSTextView) -> NSAttributedString {
        editor.textStorage ?? NSTextStorage(string: "")
    }

    /// PastePlatform's NSTextView.attributedText Objective-C setter.
    @discardableResult
    public static func setEditorTextStorage(_ value: NSAttributedString, editor: NSTextView) -> Int {
        setTextStorage(value, editor: editor)
    }

    /// a nil textStorage causes no mutation.
    @discardableResult
    public static func setTextStorage(_ value: NSAttributedString, editor: NSTextView) -> Int {
        editor.textStorage?.setAttributedString(value)
        return 0
    }

    /// the content getter forwards through the platform category.
    public static func previewAttributedString(editor: NSTextView) -> NSAttributedString {
        editorAttributedString(editor: editor)
    }

    /// last-character attributes become typingAttributes before content.
    public static func updateEditorText(_ value: NSAttributedString, editor: NSTextView) {
        editor.typingAttributes = value.length < 1 ? [:]
            : value.attributes(at: value.length - 1, effectiveRange: nil)
        setEditorTextStorage(value, editor: editor)
    }

    /// the public TextEditor attributed-text setter returns zero.
    @discardableResult
    public static func setEditorText(_ value: NSAttributedString, editor: NSTextView) -> Int {
        updateEditorText(value, editor: editor)
        return 0
    }

    /// the two actual isEditable reads select content and plain styling.
    @discardableResult
    public static func displayedText(original: @autoclosure () -> NSAttributedString,
                                  editing: @autoclosure () -> NSAttributedString,
                                  editor: NSTextView) -> Int {
        var displayed = editor.isEditable ? editing() : original()
        if !editor.isEditable, isPlainText(original()) {
            let plain = NSMutableAttributedString(attributedString: displayed)
            let range = fullRange(plain)
            plain.removeAttribute(.foregroundColor, range: range)
            plain.removeAttribute(.backgroundColor, range: range)
            displayed = plain
        }
        setEditorText(displayed, editor: editor)
        return 0
    }
}
