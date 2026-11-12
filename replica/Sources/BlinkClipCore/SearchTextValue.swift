import AppKit

public extension NSTextView {
    @MainActor func currentString() -> String { string }

    /// BlinkClip's independent plain-text setter, matching the observed String → setString: effect.
    /// The original Swift declaration and caller binding remain unconfirmed.
    @MainActor func setString(_ value: String) {
        string = value
    }
}
