import Foundation

/// One unsolicited reminder per denied period in this process. Explicit settings
/// actions remain available; a subsequent grant resets the reminder for revocation.
public struct PermissionPromptPolicy {
    private var hasReminded = false

    public init() {}

    public mutating func shouldRemind(canPostEvents: Bool) -> Bool {
        if canPostEvents {
            hasReminded = false
            return false
        }
        guard !hasReminded else { return false }
        hasReminded = true
        return true
    }
}

public enum PermissionGuidePersistence {
    public static func key(for directory: URL) -> String {
        "BlinkClip.PermissionGuide.v1." + directory.standardizedFileURL.resolvingSymlinksInPath().path
    }

    public static func shouldShow(directory: URL, defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: key(for: directory))
    }

    public static func complete(directory: URL, defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: key(for: directory))
    }
}
