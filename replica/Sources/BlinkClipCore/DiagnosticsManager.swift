import Foundation

/// Local diagnostics controls, using the same shared outputs as named loggers.
/// The caller owns preference persistence and restores the saved flag at launch.
@MainActor
public final class DiagnosticsManager {
    public static let preferenceKey = "isDiagnosticsEnabled"
    public private(set) var enabled = false
    public let logDirectory: URL
    private let configuration: ConsoleLogConfiguration
    private let fileOutput: FileLogOutput
    private let persist: (Bool) -> Void

    public init(logDirectory: URL, configuration: ConsoleLogConfiguration,
                fileOutput: FileLogOutput, persist: @escaping (Bool) -> Void) {
        self.logDirectory = logDirectory
        self.configuration = configuration
        self.fileOutput = fileOutput
        self.persist = persist
    }

    public static func makeLocal(logDirectory: URL, persist: @escaping (Bool) -> Void) -> DiagnosticsManager {
        DiagnosticsManager(logDirectory: logDirectory,
                                   configuration: DiagnosticDispatcher.consoleLogConfiguration(),
                                   fileOutput: DiagnosticDispatcher.fileLogOutput(), persist: persist)
    }

    public func startFileLogging() {
        try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true, attributes: nil)
        fileOutput.close()
        fileOutput.setDirectoryURL(logDirectory)
        fileOutput.enabled = true
        configuration.setLevel(0)
    }

    public func setDiagnosticsEnabled(_ enabled: Bool) {
        let previous = self.enabled
        self.enabled = enabled
        guard previous != enabled else { return }
        persist(enabled)
        if self.enabled {
            startFileLogging()
        } else {
            fileOutput.enabled = false
            fileOutput.close()
            configuration.setLevel(1)
        }
    }

    public func currentFileURL() -> URL? { fileOutput.fileURL }

    public func logFileURLs() -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(at: logDirectory,
                                                                    includingPropertiesForKeys: nil,
                                                                    options: [])) ?? []
        return contents.filter { $0.pathExtension == "log" && $0.lastPathComponent.hasPrefix("paste-diagnostics-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
