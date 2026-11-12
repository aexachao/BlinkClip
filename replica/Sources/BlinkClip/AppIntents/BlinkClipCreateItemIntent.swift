import AppIntents
import Foundation
import BlinkClipCore

struct BlinkClipCreateItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Create BlinkClip Item"

    @Parameter(title: "Content", description: "Text")
    var content: String

    @Parameter(title: "BlinkClip")
    var destination: BlinkClipPinboardEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        guard !content.isEmpty else { throw PasteboardItemCreationError.emptyContent }
        let target: ClipboardStore.IntentTextDestination
        if destination.id == BlinkClipPinboardEntity.historyID {
            target = .history
        } else if let id = UUID(uuidString: destination.id) {
            target = .pinboard(id)
        } else {
            throw BlinkClipCreateItemError.destinationNotFound
        }
        let store = try BlinkClipAppIntentStore.requireStore()
        let item = try store.createIntentText(content, destination: target)
        let representations = (try? ClipboardStore.originalPasteboardItems(from: item.payloads)) ?? []
        return .result(value: representations.first?.plainTextString())
    }
}

private enum BlinkClipCreateItemError: LocalizedError {
    case destinationNotFound

    var errorDescription: String? { "\(AppBrand.name) 分组不存在。" }
}
