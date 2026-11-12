import Foundation

public typealias ShortcutTelemetryConfiguration = (
    isEnabled: Bool, distributionType: String, tracesSampleRate: CGFloat
)

/// Configuration and construction recovered independently of the Sentry sinks.
/// Error capture and breadcrumb delivery remain separate migration work.
public final class ShortcutTelemetry {
    public static let configuration = InitializedValue<ShortcutTelemetryConfiguration>()

    public let isEnabled: Bool
    public let distributionType: String
    public let tracesSampleRate: CGFloat

    private init(isEnabled: Bool, distributionType: String, tracesSampleRate: CGFloat) {
        self.isEnabled = isEnabled
        self.distributionType = distributionType
        self.tracesSampleRate = tracesSampleRate
    }

    public static func shortcutTelemetry() -> ShortcutTelemetry {
        Dependencies.resolveDependency(file: "PasteTelemetry/DI+PasteTelemetry.swift", line: 13, column: 19) {
            makeShortcutTelemetry()
        }
    }

    public static func makeShortcutTelemetry() -> ShortcutTelemetry {
        let configuration = Self.configuration
        if configuration.currentValue() == nil {
            configuration.setValueOnce((isEnabled: false, distributionType: "unknown", tracesSampleRate: 0))
        }
        return ShortcutTelemetry(
            isEnabled: configuration.memberAtKeyPath(\ShortcutTelemetryConfiguration.isEnabled),
            distributionType: configuration.memberAtKeyPath(\ShortcutTelemetryConfiguration.distributionType),
            tracesSampleRate: configuration.memberAtKeyPath(\ShortcutTelemetryConfiguration.tracesSampleRate)
        )
    }

    /// Keep the existing local diagnostic adapter while the original Sentry
    /// error/breadcrumb methods are unresolved. This is not their replacement.
    func localDiagnostic(_ diagnostic: ShortcutDiagnostic) {
        GlobalShortcutMonitor.writeDiagnostic(diagnostic)
    }
}
