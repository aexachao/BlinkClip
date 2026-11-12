import Foundation

public enum SearchSuggestions {
    public enum Suggestion: Equatable, Sendable, CustomStringConvertible {
        case query([SearchQueryNode])
        case filter(UInt8, String)

        // the registered CustomStringConvertible witness.
        public var description: String { SearchSuggestions.listNameForSuggestion(self) }
    }

    /// Applies a suggestion to the query nodes; the caller normalizes the resulting query afterwards.
    public static func nodesApplyingSuggestion(_ suggestion: Suggestion, index: Int, addMode: UInt8,
                                  nodes: [SearchQueryNode]) -> [SearchQueryNode] {
        switch suggestion {
        case let .query(query):
            return query
        case let .filter(tag, value):
            let filter = SearchQueryNode.filter(tag, value)
            guard !nodes.contains(filter) else { return nodes }
            if addMode == 1 {
                // This is the generic dropLast operation.
                return Array(nodes.dropLast()) + [filter]
            }
            guard index < nodes.count else { return nodes }
            precondition(index >= 0)
            var result = nodes
            result[index] = filter
            return result
        }
    }

    private static var listNameResolver: ((String) -> String?)?

    public static func setListNameResolver(_ resolver: ((String) -> String?)?) {
        listNameResolver = resolver
    }

    public static func resolveListName(_ identifier: String) -> String? {
        let resolver = listNameResolver
        return resolver?(identifier)
    }

    // 2dc9b8: preserve node order, raw text and empty components when joining.
    public static func listNameForSuggestion(_ suggestion: Suggestion,
                                  listName: (String) -> String? = { resolveListName($0) }) -> String {
        switch suggestion {
        case let .filter(kind, value):
            return listNameForKind(kind: kind, value: value, listName: listName)
        case let .query(nodes):
            return nodes.map { node in
                switch node {
                case let .text(text): return text
                case let .filter(kind, value):
                    let prefix: String
                    switch kind {
                    case 0: prefix = "app"
                    case 1: prefix = "type"
                    case 2: prefix = "title"
                    case 3: prefix = "date"
                    case 4: prefix = "device"
                    default: prefix = "pinboard"
                    }
                    return prefix + ":" + listNameForKind(kind: kind, value: value, listName: listName)
                }
            }.joined(separator: " ")
        }
    }

    // 2ddc10: only dates and list identifiers have a resolved caption.
    public static func listNameForKind(kind: UInt8, value: String,
                                  listName: (String) -> String? = { resolveListName($0) }) -> String {
        switch kind {
        case 5: return listName(value) ?? value
        case 3: return SearchDateEncoding.titleForFilterValue(value) ?? value
        default: return value
        }
    }

    public struct Provider {
        public let app: (String) throws -> [String]
        public let type: (String) throws -> [String]
        public let device: (String) throws -> [String]
        public let pinboard: (String) throws -> [(identifier: String, name: String)]

        public init(
            app: @escaping (String) throws -> [String],
            type: @escaping (String) throws -> [String] = SearchSuggestions.itemTypeNames,
            device: @escaping (String) throws -> [String],
            pinboard: @escaping (String) throws -> [(identifier: String, name: String)]
        ) {
            self.app = app
            self.type = type
            self.device = device
            self.pinboard = pinboard
        }
    }

    // optional provider, independently suppressed source errors, dates always.
    public static func filterGroups(provider: () -> Provider?,
                                  dateFilters: [SearchDateFilter]? = nil) -> [UInt8: [SearchQueryNode]] {
        var filters: [UInt8: [SearchQueryNode]] = [:]
        let types = try? (provider()?.type("") ?? [])
        filters[1] = types.map { $0.map { .filter(1, $0) } }
        let apps = try? (provider()?.app("") ?? [])
        filters[0] = apps.map { $0.map { .filter(0, $0) } }
        let devices = try? (provider()?.device("") ?? [])
        filters[4] = devices.map { $0.map { .filter(4, $0) } }
        filters[3] = (dateFilters ?? SearchDateRanges.dateFilters()).map { date in
            // The available-filters builder truncates both endpoints toward zero.
            let start = Int(date.range.lowerBound.timeIntervalSince1970)
            let end = Int(date.range.upperBound.timeIntervalSince1970)
            return .filter(3, "\(start) \(end)")
        }
        let pinboards = try? (provider()?.pinboard("") ?? [])
        filters[5] = pinboards.map { $0.map { .filter(5, $0.identifier) } }
        return filters
    }

    public static func itemTypeNames(_ query: String) -> [String] {
        let values = ["Unknown", "Image", "Color", "File", "Link", "Text"]
        guard !query.isEmpty else { return values }
        let prefix = query.lowercased()
        return values.filter { $0.lowercased().hasPrefix(prefix) }
    }

    public static func splitOnWhitespace(
        _ text: String,
        maxSplits: Int = Int.max,
        omittingEmptySubsequences: Bool = true
    ) -> [Substring] {
        text.split(
            maxSplits: maxSplits,
            omittingEmptySubsequences: omittingEmptySubsequences,
            whereSeparator: { $0.isWhitespace }
        )
    }

    public static func wordPatterns(_ text: String) -> [String] {
        splitOnWhitespace(text).map { "\\b" + NSRegularExpression.escapedPattern(for: String($0)) }
    }

    public static func fuzzyPattern(_ text: String) -> String {
        ".*" + wordPatterns(text).joined(separator: ".*") + ".*"
    }

    public static func matchRanges(_ query: String, in target: String) -> [Range<String.Index>] {
        var matches: [Range<String.Index>] = []
        var lowerBound = target.startIndex
        for pattern in wordPatterns(query) {
            guard let match = target.range(
                of: pattern,
                options: [.caseInsensitive, .regularExpression],
                range: lowerBound..<target.endIndex,
                locale: nil
            ) else { return [] }
            matches.append(match)
            lowerBound = match.upperBound
        }
        return matches
    }

    public static func contextSuggestions(
        contextNode: SearchQueryNode,
        currentNodes: [SearchQueryNode],
        provider: Provider,
        dateFilters: [SearchDateFilter]? = nil
    ) -> [SearchQueryNode] {
        guard case let .text(text) = contextNode,
              !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let applied = currentNodes.filter {
            if case .filter = $0 { return true }
            return false
        }
        // Each source is independent: an error suppresses only that group's rows.
        let groups: [(UInt8, (String) throws -> [String])] = [
            (0, provider.app),
            (1, provider.type),
            (4, provider.device),
            (5, { try provider.pinboard($0).map { $0.identifier } })
        ]
        var suggestions: [SearchQueryNode] = []
        for (kind, source) in groups {
            do {
                let candidates = try source(query)
                suggestions.append(contentsOf: candidates
                    .map { SearchQueryNode.filter(kind, $0) }
                    .filter { !applied.contains($0) }
                    .prefix(30))
            } catch {
                continue
            }
        }
        for dateFilter in dateFilters ?? SearchDateRanges.dateFilters()
            where !matchRanges(query, in: dateFilter.title).isEmpty {
            let node = SearchDateEncoding.filterNodeForRange(dateFilter.range)
            if !applied.contains(node) { suggestions.append(node) }
        }
        return suggestions
    }
}
