import Foundation

/// Keep the displayed preference consistent if the existing store save fails.
enum HistoryRetentionSaving {
    static func apply(_ days: Int, previous: Int, assign: (Int) -> Void, save: () throws -> Void) throws {
        guard days != previous else { return }
        assign(days)
        do { try save() }
        catch { assign(previous); throw error }
    }
}
