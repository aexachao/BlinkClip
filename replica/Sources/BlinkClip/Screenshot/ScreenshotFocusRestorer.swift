import AppKit

/// 对应 capcap 的 `SourceAppFocusRestorer`（`Capture/SourceAppFocusRestorer.swift`，
/// 未 vendored）。编辑器关闭后把焦点还给截图前的前台 App。
@MainActor
final class ScreenshotFocusRestorer {
    private let processIdentifier: pid_t?
    private var restoreScheduled = false

    private init(processIdentifier: pid_t?) {
        self.processIdentifier = processIdentifier
    }

    static func captureFrontmost() -> ScreenshotFocusRestorer {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let app = NSWorkspace.shared.frontmostApplication
        let targetPID = app?.processIdentifier == ownPID ? nil : app?.processIdentifier
        return ScreenshotFocusRestorer(processIdentifier: targetPID)
    }

    func restore() {
        guard !restoreScheduled else { return }
        restoreScheduled = true
        let processIdentifier = self.processIdentifier
        DispatchQueue.main.async {
            guard let processIdentifier,
                  let app = NSRunningApplication(processIdentifier: processIdentifier),
                  !app.isTerminated,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier
            else { return }
            app.activate(options: [.activateAllWindows])
        }
    }
}
