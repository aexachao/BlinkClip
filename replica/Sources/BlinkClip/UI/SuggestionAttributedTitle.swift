import AppKit
import BlinkClipCore

@MainActor
enum SuggestionAttributedTitle {
    /// only matching titles are assembled as mutable segments.
    static func highlightedTitle(primary: NSColor, secondary: NSColor,
                            title: String, query: String?) -> NSAttributedString {
        if let query, !query.isEmpty {
            let matches = SearchSuggestions.matchRanges(query, in: title)
            if !matches.isEmpty {
                let result = NSMutableAttributedString(string: "")
                var cursor = title.startIndex
                for match in matches {
                    if cursor < match.lowerBound {
                        result.append(NSAttributedString(string: String(title[cursor..<match.lowerBound]),
                            attributes: [.foregroundColor: secondary]))
                    }
                    result.append(NSAttributedString(string: String(title[match]),
                        attributes: [.foregroundColor: primary]))
                    cursor = match.upperBound
                }
                if cursor < title.endIndex {
                    result.append(NSAttributedString(string: String(title[cursor...]),
                        attributes: [.foregroundColor: secondary]))
                }
                return result
            }
        }
        return NSAttributedString(string: title, attributes: [.foregroundColor: primary])
    }
}
