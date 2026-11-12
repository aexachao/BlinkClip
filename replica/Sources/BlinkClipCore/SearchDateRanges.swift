import Foundation

public struct SearchDateFilter: Hashable, Sendable {
    public let title: String
    public let range: Range<Date>

    public init(title: String, range: Range<Date>) {
        self.title = title
        self.range = range
    }
}

public enum SearchDateRanges {
    private static func range(_ start: Date, _ end: Date) -> Range<Date> {
        precondition(start < end)
        return start..<end
    }

    public static func today() -> Range<Date> {
        let start = Calendar.current.startOfDay(for: Date())
        return range(start, Calendar.current.date(byAdding: .day, value: 1, to: start)!)
    }

    public static func yesterday() -> Range<Date> {
        let end = Calendar.current.startOfDay(for: Date())
        return range(Calendar.current.date(byAdding: .day, value: -1, to: end)!, end)
    }

    public static func thisWeek() -> Range<Date> {
        let now = Date()
        let components = Calendar.current.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: now)
        let start = components.date!
        return range(start, Calendar.current.date(byAdding: .day, value: 7, to: start)!)
    }

    public static func lastWeek() -> Range<Date> {
        let now = Date()
        let components = Calendar.current.dateComponents([.calendar, .yearForWeekOfYear, .weekOfYear], from: now)
        let end = components.date!
        return range(Calendar.current.date(byAdding: .weekOfYear, value: -1, to: end)!, end)
    }

    public static func last30Days() -> Range<Date> {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -30, to: today)!
        let end = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        return range(start, end)
    }

    public static func dateFilters() -> [SearchDateFilter] {
        [
            .init(title: "Today", range: today()),
            .init(title: "Yesterday", range: yesterday()),
            .init(title: "This week", range: thisWeek()),
            .init(title: "Last week", range: lastWeek()),
            .init(title: "Last 30 days", range: last30Days())
        ]
    }
}
