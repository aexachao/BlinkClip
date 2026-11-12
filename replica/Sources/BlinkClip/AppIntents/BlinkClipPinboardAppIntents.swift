import AppIntents
import AppKit
import Foundation
import BlinkClipCore
import _AppIntents_AppKit

/// The app supplies its live store so intent actions use the same directory and transaction path.
@MainActor
enum BlinkClipAppIntentStore {
    private static weak var store: ClipboardStore?

    static func configure(store: ClipboardStore) {
        self.store = store
    }

    static func requireStore() throws -> ClipboardStore {
        guard let store else { throw BlinkClipAppIntentAccessError.storeUnavailable }
        return store
    }

    static func refreshedStore() throws -> ClipboardStore {
        let store = try requireStore()
        try store.reload()
        return store
    }
}

private enum BlinkClipAppIntentAccessError: LocalizedError {
    case storeUnavailable

    var errorDescription: String? { "\(AppBrand.name) 本地资料尚未就绪。" }
}

struct BlinkClipPinboardEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "BlinkClip"
    static var defaultQuery = BlinkClipPinboardQuery()
    static let historyID = "sharedPasteboardHistory"

    static func history(name: String) -> Self {
        Self(id: historyID, name: name, symbolName: "clock.arrow.circlepath")
    }

    let id: String
    let name: String
    private let symbolName: String
    private let tintColor: NSColor?

    @MainActor
    init(_ pinboard: Pinboard) {
        id = pinboard.id.uuidString
        name = pinboard.name
        // The local model has no shared-list entity; the original shared symbol remains separate.
        symbolName = pinboard.rawType == 1 ? "clock.arrow.circlepath" : "circle.fill"
        // Projects only the decoded pinboard attributes into the
        // original palette; absent/other attributes retain an uncolored image.
        tintColor = PinboardAttributes.colorCode(from: pinboard.rawAttributes).map {
            PinboardColor(canonicalColorCode: $0).color()
        }
    }

    private init(id: String, name: String, symbolName: String) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        tintColor = nil
    }

    @MainActor
    func items(in store: ClipboardStore) -> [ClipboardItem]? {
        if id == Self.historyID { return store.search(query: "") }
        guard let pinboard = store.pinboards.first(where: { $0.id.uuidString == id }) else { return nil }
        return store.items(in: pinboard.id)
    }

    var displayRepresentation: DisplayRepresentation {
        // Uses the AppKit image initializer and body symbol style.
        // Preserve its optional result, without substituting another image if construction fails.
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbolName,
            tintColor: tintColor, symbolConfiguration: NSImage.SymbolConfiguration(textStyle: .body)))
    }
}

struct BlinkClipPinboardQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [BlinkClipPinboardEntity] {
        let store = try BlinkClipAppIntentStore.refreshedStore()
        let pinboards = store.pinboards
        return identifiers.compactMap { identifier in
            if identifier == BlinkClipPinboardEntity.historyID {
                return .history(name: store.preferences.historyTitle)
            }
            return pinboards.first(where: { $0.id.uuidString == identifier }).map(BlinkClipPinboardEntity.init)
        }
    }

    @MainActor
    func suggestedEntities() async throws -> [BlinkClipPinboardEntity] {
        let store = try BlinkClipAppIntentStore.refreshedStore()
        let pinboards = store.pinboards
        // This local presentation puts History first; the original metadata.index ordering is unresolved.
        return [.history(name: store.preferences.historyTitle)] + pinboards.map(BlinkClipPinboardEntity.init)
    }
}

struct BlinkClipCreatePinboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Create BlinkClip"

    @Parameter(title: "Name", description: "Text")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<BlinkClipPinboardEntity> {
        let store = try BlinkClipAppIntentStore.requireStore()
        let pinboard = try store.createPinboardFromIntent(name: name)
        return .result(value: BlinkClipPinboardEntity(pinboard))
    }
}
