import Combine
import Foundation
import BlinkClipCore
import ServiceManagement

@MainActor
enum BackgroundService {
    static let identifier = "com.chrisli.blinkclip.helper"
    static let sessionDefaults = UserDefaults(suiteName: "com.chrisli.blinkclip.session")
    private static let diagnostic = NamedDiagnostic.makeNamedDiagnostic(name: "PasteHelper")
    private static let enabledSubject = CurrentValueSubject<Bool, Never>(
        SMAppService.loginItem(identifier: identifier).status == .enabled)
    private static let enabledPublisher = enabledSubject.eraseToAnyPublisher()
    static var enabledChanges: AnyPublisher<Bool, Never> { enabledPublisher }
    static var isEnabled: Bool { enabledSubject.value }

    /// publish requested state before attempting any service operation.
    static func setEnabled(_ enabled: Bool) {
        enabledSubject.send(enabled)
        let service = SMAppService.loginItem(identifier: identifier)
        do {
            if enabled {
                if service.status == .enabled {
                    // The original intentionally ignores failure of the preliminary removal.
                    try? SMAppService.loginItem(identifier: identifier).unregister()
                }
                try SMAppService.loginItem(identifier: identifier).register()
                diagnostic.diagnosticSink().emitInfo("Registered background helper")
            } else {
                try service.unregister()
                diagnostic.diagnosticSink().emitInfo("Unregistered background helper")
            }
        } catch {
            let operation = enabled ? "registering" : "unregistering"
            diagnostic.diagnosticSink().emitFault("Error \(operation) background item: \(error.localizedDescription)")
        }
    }

    static func markRunning(_ running: Bool) {
        sessionDefaults?.set(running, forKey: "pasteIsRunning")
        sessionDefaults?.synchronize()
    }
}
