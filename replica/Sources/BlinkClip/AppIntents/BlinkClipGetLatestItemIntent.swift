import AppIntents
import Foundation
import BlinkClipCore

enum BlinkClipLatestItemType: String, AppEnum {
    case text
    case link

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "BlinkClip Item Type"
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .text: "Text",
        .link: "Link"
    ]
}

struct BlinkClipGetLatestItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Latest BlinkClip Item"

    @Parameter(title: "Type", description: "Text or Link")
    var type: BlinkClipLatestItemType

    @Parameter(title: "BlinkClip")
    var pinboard: BlinkClipPinboardEntity

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String?> {
        let store = try BlinkClipAppIntentStore.refreshedStore()
        guard let items = pinboard.items(in: store) else {
            throw BlinkClipLatestItemError.pinboardNotFound
        }
        // The recovered body accepts raw types 4/5; dependence on its Type parameter is unproven.
        // Keep the real local collection order, including the existing History order.
        let item = items.first {
            $0.kind == .link || $0.kind == .text || $0.kind == .richText
        }
        let text: String?
        if let item {
            let representations = (try? ClipboardStore.originalPasteboardItems(from: item.payloads)) ?? []
            text = PasteboardRestore.textOnlyItems(representations).first?.plainTextString()
        } else {
            text = nil
        }
        return .result(value: text)
    }
}

private enum BlinkClipLatestItemError: LocalizedError {
    case pinboardNotFound

    var errorDescription: String? { "\(AppBrand.name) 分组不存在。" }
}
