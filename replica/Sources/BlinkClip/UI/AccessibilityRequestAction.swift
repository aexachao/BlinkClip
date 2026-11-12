import AppKit
import ApplicationServices
import IOKit.hidsystem

/// The system action performed by an explicit permission button, separate from modal results.
@MainActor
enum AccessibilityRequestAction {
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    static func perform() {
        NSApp.deactivate()
        perform(isAXTrusted: AXIsProcessTrusted(), canPostEvents: CGPreflightPostEventAccess(),
                requestAX: {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }, requestPostEvents: { _ = CGRequestPostEventAccess() }, openSettings: openSettings)
    }

    static func perform(isAXTrusted: Bool, canPostEvents: Bool, requestAX: () -> Void,
                        requestPostEvents: () -> Void, openSettings: (URL) -> Void) {
        if !isAXTrusted { requestAX() }
        else if !canPostEvents { requestPostEvents() }
        openSettings(settingsURL)
    }

    static func openSettings(_ url: URL) {
        NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { application, _ in
            application?.activate(options: [.activateAllWindows])
        }
    }

    static func perform(accessStatus: IOHIDAccessType, requestAccess: () -> Void, openSettings: (URL) -> Void) {
        if accessStatus == kIOHIDAccessTypeUnknown {
            requestAccess()
        }
        // First use also navigates directly; requesting event access alone may show no settings window.
        openSettings(settingsURL)
    }
}
