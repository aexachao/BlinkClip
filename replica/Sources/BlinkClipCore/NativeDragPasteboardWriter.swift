import AppKit

/// The writer owns the identifier source and reads it for each item-ID request.
/// A replica UUID snapshot adapter does not claim original CoreData identity.
public protocol DragItemIdentifierSource: AnyObject {
    var pasteboardIdentifier: String { get }
}

public final class NativeDragPasteboardWriter: NSObject, NSPasteboardWriting {
    public static let itemIdentifierType = NSPasteboard.PasteboardType("com.chrisli.blinkclip.item-id")

    private let source: any DragItemIdentifierSource
    private let pasteboardItems: [PasteboardItem]

    public init(source: any DragItemIdentifierSource, pasteboardItems: [PasteboardItem]) {
        self.source = source
        self.pasteboardItems = pasteboardItems
        super.init()
    }

    @MainActor
    public static func writers(sources: [any DragItemIdentifierSource],
                               groups: [[PasteboardItem]]) -> [NativeDragPasteboardWriter] {
        zip(sources, groups).map { source, items in
            NativeDragPasteboardWriter(source: source, pasteboardItems: items)
        }
    }

    public func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = pasteboardItems.flatMap { item in
            item.currentOrderedTypes().map { NSPasteboard.PasteboardType($0) }
        }
        types.append(Self.itemIdentifierType)
        return types
    }

    public func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == Self.itemIdentifierType { return source.pasteboardIdentifier }
        for item in pasteboardItems {
            if let data = item.dataForType(forType: type.rawValue) { return data }
        }
        return nil
    }
}
