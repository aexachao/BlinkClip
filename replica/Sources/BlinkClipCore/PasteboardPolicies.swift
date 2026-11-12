import AppKit
import Foundation

public enum PasteboardPolicies {
    public static let accessRequestNotification = Notification.Name("pasteboardHistoryManagerDidRequestAccess")

    public static func permitsBackgroundRead(_ pasteboard: NSPasteboard) -> Bool {
        if #available(macOS 15.4, *) {
            // The source uses accessBehavior (NSInteger) on 15.4+. Resolve the
            // same getter when building with an SDK that predates its header.
            let selector = NSSelectorFromString("accessBehavior")
            guard pasteboard.responds(to: selector), let implementation = pasteboard.method(for: selector) else {
                return false
            }
            typealias Getter = @convention(c) (AnyObject, Selector) -> Int
            let getter = unsafeBitCast(implementation, to: Getter.self)
            return getter(pasteboard, selector) == 2
        }
        return true
    }

    public static func setsEqual(_ first: Set<String>, _ second: Set<String>) -> Bool {
        first == second
    }

    @MainActor
    public static func shouldCaptureChange(allTypes: [String], excludedApplications: Set<String>, ignoredTypes: Set<String>,
                                  diagnostics: NamedDiagnostic) -> Bool {
        guard let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            diagnostics.diagnosticSink().emitDebug("Undefined frontmost application, skipping pasteboard change")
            return false
        }
        let ignored = sourceBundleID == "org.mozilla.firefoxdeveloperedition"
            ? excludedApplications.contains(sourceBundleID)
            : excludedApplications.contains { sourceBundleID.contains($0) }
        if ignored {
            diagnostics.diagnosticSink().emitDebug("Ignored application \(sourceBundleID), skipping pasteboard change")
            return false
        }
        for type in allTypes {
            if ignoredTypes.contains(where: { type.contains($0) || $0.contains(type) }) {
                diagnostics.diagnosticSink().emitInfo("Ignored pasteboard type \(type), skipping pasteboard change")
                return false
            }
        }
        return true
    }

    @MainActor
    public static func shouldCaptureType(type: String, allTypes: [String]) -> Bool {
        let sourceBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if sourceBundleID?.lowercased() == "com.microsoft.excel" {
            return ["public.utf16-plain-text", "public.utf8-plain-text"].contains(type)
        }
        if setsEqual(Set(allTypes), ["public.file-url", "public.png"]), type == "public.file-url" {
            return false
        }
        // The last identifier is truncated in the original static string too.
        return !["com.microsoft.ObjectLink", "com.microsoft.Link-Source", "com.microsoft.DataObjec"].contains(type)
    }

    public static func permitsRemoteType(_ type: String, allTypes: [String]) -> Bool {
        !allTypes.contains("com.apple.is-remote-clipboard")
            || ["public.utf8-plain-text", "public.text", "public.rtf"].contains(type)
    }
}
