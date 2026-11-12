import AppKit

public final class ShortcutValidatorService: Sendable {
    private init() {}

    public static func makeShortcutValidatorService() -> ShortcutValidatorService {
        ShortcutValidatorService()
    }

    @MainActor
    public func validate(_ shortcut: ShortcutValue) -> Error? {
        ShortcutValidation.validateAgainstSystemHotKeys(shortcut: shortcut, menu: NSApp.mainMenu)
    }
}

public extension DependencyValues {
    static func resolveDependency<Value>(line: UInt, factory: () -> Value) -> Value {
        Dependencies.resolveDependency(file: "PasteShortcut/DI+PasteShortcut.swift", line: line, column: 19,
                                         factory: factory)
    }

    func globalShortcutMonitor() -> GlobalShortcutMonitor {
        Self.resolveDependency(line: 6, factory: GlobalShortcutMonitor.makeGlobalShortcutMonitor)
    }

    var shortcutDiagnostic: (ShortcutDiagnostic) -> Void {
        ShortcutTelemetry.shortcutTelemetry().localDiagnostic
    }

    var shortcutValidator: ShortcutValidatorService {
        shortcutValidatorService()
    }

    func shortcutValidatorService() -> ShortcutValidatorService {
        Self.resolveDependency(line: 12) {
            ShortcutValidatorService.makeShortcutValidatorService()
        }
    }
}
