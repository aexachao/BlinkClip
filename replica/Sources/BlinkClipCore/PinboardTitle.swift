import Foundation

/// The shared tab-name value mapping.
public enum PinboardTitle {
    public static func normalizedRename(_ value: String) -> String {
        value.isEmpty ? String(localized: PreviewLocalization.generalUntitled()) : value
    }
}
