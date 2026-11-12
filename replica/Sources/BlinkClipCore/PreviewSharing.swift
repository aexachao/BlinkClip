import AppKit
import UniformTypeIdentifiers

@MainActor
public enum PreviewSharing {
    public struct Content {
        public let items: [PasteboardItem]
        public let rawType: Int
        public init(items: [PasteboardItem], rawType: Int) {
            self.items = items
            self.rawType = rawType
        }
    }

    /// keep data-item order and discard missing representations.
    public static func shareableItems(items: [PasteboardItem], rawType: Int) -> [Any] {
        switch rawType {
        case 1: return items.compactMap { $0.imageData().flatMap(NSImage.init(data:)) }
        case 2, 5: return items.compactMap { $0.plainTextString() }
        case 3:
            return items.compactMap { item -> URL? in
                guard let data = item.dataForType(forType: UTType.fileURL.identifier),
                      let string = String(data: data, encoding: .utf8) else { return nil }
                return URL(string: string)
            }
        case 4: return items.compactMap { $0.url() }
        default: return []
        }
    }

    /// file sharing additionally requires reachable local URLs.
    public static func hasShareableItems(_ content: Content) -> Bool {
        switch content.rawType {
        case 1, 2, 4, 5:
            return !shareableItems(items: content.items, rawType: content.rawType).isEmpty
        case 3:
            let urls = shareableItems(items: content.items, rawType: content.rawType).compactMap { $0 as? URL }
            return !urls.isEmpty && urls.allSatisfy {
                $0.isFileURL && (try? $0.checkResourceIsReachable()) == true
            }
        default:
            return false
        }
    }

    /// The picker consumes a flattened sequence, without starting any network work.
    public static func makeSharingServicePicker(_ contents: [Content]) -> NSSharingServicePicker {
        NSSharingServicePicker(items: contents.flatMap { shareableItems(items: $0.items, rawType: $0.rawType) })
    }
}
