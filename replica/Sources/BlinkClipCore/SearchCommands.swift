import AppKit

/// Dispatch the two SearchField command selectors to optional
/// callbacks. Callback storage is supplied explicitly instead of the original x20 self.
@MainActor public enum SearchCommands {
    public static func handleCommandSelector(selector: Selector, onEnter: (() -> Void)?, onCancel: (() -> Void)?) -> Bool {
        if selector == NSSelectorFromString("insertNewline:") {
            onEnter?()
            return true
        }
        if selector == NSSelectorFromString("cancelOperation:") {
            onCancel?()
            return true
        }
        return false
    }
}
