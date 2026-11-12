import AppKit
import UniformTypeIdentifiers

@MainActor
public enum TextPreviewSubmission {
    /// only emphasis traits and the two style keys require RTF.
    public static func attributesForSubmission(attributes: [NSAttributedString.Key: Any],
                                  isRich: inout Bool, stop: UnsafeMutablePointer<ObjCBool>) {
        for (key, value) in attributes {
            if key == .font, let font = value as? NSFont {
                if font.fontDescriptor.symbolicTraits.rawValue & 3 == 0 { continue }
            } else if key != .underlineStyle && key != .strikethroughStyle {
                continue
            }
            isRich = true
            stop.pointee = true
        }
    }

    /// The value preparation, including the optional RTF result.
    public static func makeItem(_ content: NSAttributedString) -> PasteboardItem {
        var isRich = false
        content.enumerateAttributes(in: NSRange(location: 0, length: content.length), options: []) { attributes, _, stop in
            attributesForSubmission(attributes: attributes, isRich: &isRich, stop: stop)
        }
        guard isRich else { return PasteboardItem.itemWithString(content.string) }
        let item = PasteboardItem()
        item.setData(PasteboardRestore.rtfData(content), forType: UTType.rtf.identifier)
        item.setString(content.string, forType: UTType.utf8PlainText.identifier)
        return item
    }
}
