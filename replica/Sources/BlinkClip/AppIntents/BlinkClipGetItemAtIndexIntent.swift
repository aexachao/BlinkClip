import AppIntents
import Foundation
import BlinkClipCore

/// Reads the first original representation; it does not restore the clipboard or synthesize OCR text.
struct BlinkClipGetItemAtIndexIntent: AppIntent {
    static var title: LocalizedStringResource = "Get BlinkClip Item at Index"

    @Parameter(title: "Index", description: "Item Index", controlStyle: .stepper)
    var index: Int

    @Parameter(title: "BlinkClip")
    var pinboard: BlinkClipPinboardEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        let store = try BlinkClipAppIntentStore.refreshedStore()
        guard let items = pinboard.items(in: store) else {
            throw BlinkClipIndexedItemError.pinboardNotFound
        }
        // Use the actual local collection order, without claiming the original repository order.
        guard items.indices.contains(index) else { throw BlinkClipIndexedItemError.itemNotFound }
        let representations = (try? ClipboardStore.originalPasteboardItems(from: items[index].payloads)) ?? []
        return .result(value: representations.first?.plainTextString())
    }
}

private enum BlinkClipIndexedItemError: LocalizedError {
    case pinboardNotFound
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .pinboardNotFound: return "\(AppBrand.name) 分组不存在。"
        case .itemNotFound: return "\(AppBrand.name) 项目不存在。"
        }
    }
}
