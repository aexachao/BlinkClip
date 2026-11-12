import os

/// List identities remain local strings; these are the original history/pinboard context cases.
public enum CollectionListContext: Equatable {
    case history(identifier: String)
    case pinboard(identifier: String)

    private static let logger = Logger(subsystem: "com.chrisli.blinkclip", category: "collection-context")

    // 3b80f0: type2 pinboard, type1 history; log an unsupported type before resolving the fallback history.
    public static func listContext(identifier: String, rawType: Int64,
                                   historyIdentifier: () -> String) -> CollectionListContext {
        switch rawType {
        case 2: return .pinboard(identifier: identifier)
        case 1: return .history(identifier: identifier)
        default:
            logger.error("Unsupported list type \(rawType) for \(identifier, privacy: .private)")
            return .history(identifier: historyIdentifier())
        }
    }
}
