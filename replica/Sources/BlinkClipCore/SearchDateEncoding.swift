import Foundation

public enum SearchDateEncoding {
    public static func filterNodeForRange(_ range: Range<Date>) -> SearchQueryNode {
        let start = Int(range.lowerBound.timeIntervalSince1970.rounded(.down))
        let end = Int(range.upperBound.timeIntervalSince1970.rounded(.up))
        return .filter(3, "\(start) \(end)")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    public static func titleForFilterValue(_ value: String) -> String? {
        for preset in SearchDateRanges.dateFilters() {
            if filterNodeForRange(preset.range) == .filter(3, value) { return preset.title }
        }
        let parts = value.split(separator: " ")
        guard parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]) else { return nil }
        return dateFormatter.string(from: Date(timeIntervalSince1970: Double(start)))
            + " to " + dateFormatter.string(from: Date(timeIntervalSince1970: Double(end)))
    }

    public static func title(for range: Range<Date>) -> String {
        guard case let .filter(_, value) = filterNodeForRange(range) else { preconditionFailure() }
        return titleForFilterValue(value) ?? value
    }
}
