import Dispatch
import Foundation
import OSLog

public final class ConsoleLogConfiguration {
    public var level: UInt8

    private init(level: UInt8) { self.level = level }

    public static func makeConsoleLogConfiguration() -> ConsoleLogConfiguration {
        ConsoleLogConfiguration(level: 1)
    }

    public func currentLevel() -> UInt8 { level }

    public func setLevel(_ level: UInt8) { self.level = level }
}

public protocol DiagnosticOutput: AnyObject {
    func emit(level: UInt8, name: String, message: String)
}

/// All outputs share the original serial queue; their mutable caches are used
/// only inside the dispatcher's synchronous output pass.
public final class DiagnosticDispatcher: DiagnosticSink {
    private static let queue = makeLoggingQueue()
    public let name: String
    public let configuration: ConsoleLogConfiguration
    private let outputs: [any DiagnosticOutput]

    private init(name: String, configuration: ConsoleLogConfiguration,
                 outputs: [any DiagnosticOutput]) {
        self.name = name
        self.configuration = configuration
        self.outputs = outputs
    }

    public static func consoleLogConfiguration() -> ConsoleLogConfiguration {
        Dependencies.resolveDependency(file: "PasteLogging/DI+PasteLogging.swift", line: 37, column: 19,
                                         factory: ConsoleLogConfiguration.makeConsoleLogConfiguration)
    }

    public static func fileLogOutput() -> FileLogOutput {
        Dependencies.resolveDependency(file: "PasteLogging/DI+PasteLogging.swift", line: 43, column: 19,
                                         factory: FileLogOutput.makeFileLogOutput)
    }

    public static func diagnosticSink(name: String) -> any DiagnosticSink {
        let configuration = consoleLogConfiguration()
        let system = Dependencies.resolveDependency(
            file: "PasteLogging/DI+PasteLogging.swift", line: 56, column: 31,
            factory: SystemLogOutput.makeSystemLogOutput)
        let file = fileLogOutput()
        return DiagnosticDispatcher(name: name, configuration: configuration, outputs: [system, file])
    }

    private static func makeLoggingQueue() -> DispatchQueue {
        DispatchQueue(label: "com.chrisli.blinkclip.logger", qos: .utility,
                      attributes: [], autoreleaseFrequency: .inherit)
    }

    public func emit(level: UInt8, message: String) {
        guard configuration.currentLevel() <= level else { return }
        Self.queue.sync { emitToOutputs(level: level, message: message) }
    }

    private func emitToOutputs(level: UInt8, message: String) {
        for output in outputs { output.emit(level: level, name: name, message: message) }
    }
}

public final class SystemLogOutput: DiagnosticOutput {
    private var loggers: [String: Logger] = [:]

    private init() {}

    public static func makeSystemLogOutput() -> SystemLogOutput { SystemLogOutput() }

    public func emit(level: UInt8, name: String, message: String) {
        emitToSystemLog(level: level, name: name, message: message)
    }

    public func emitToSystemLog(level: UInt8, name: String, message: String) {
        let logger = loggerForName(name: name)
        let type: OSLogType
        switch level {
        case 0: type = .debug
        case 1: type = .info
        case 2: type = .error
        default: type = .fault
        }
        logger.log(level: type, "\(message, privacy: .public)")
    }

    private func loggerForName(name: String) -> Logger {
        if let logger = loggers[name] { return logger }
        let logger = Logger(subsystem: name, category: name)
        setLogger(logger, name: name)
        return logger
    }

    private func setLogger(_ logger: Logger?, name: String) { loggers[name] = logger }
}

public final class FileLogOutput: DiagnosticOutput {
    public var enabled: Bool
    public var directoryURL: URL?
    public private(set) var fileURL: URL?
    private var fileHandle: FileHandle?
    private static let timestampFormat = makeTimestampFormat()

    private init() {
        enabled = false
        directoryURL = nil
        fileURL = nil
        fileHandle = nil
    }

    public static func makeFileLogOutput() -> FileLogOutput { FileLogOutput() }

    public func setDirectoryURL(_ url: URL?) { directoryURL = url }

    private static func makeTimestampFormat() -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(dateSeparator: .dash, dateTimeSeparator: .standard,
                               timeSeparator: .colon, timeZoneSeparator: .omitted,
                               includingFractionalSeconds: true, timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    public func emit(level: UInt8, name: String, message: String) {
        appendLogEntry(level: level, name: name, message: message)
    }

    public func appendLogEntry(level: UInt8, name: String, message: String) {
        guard enabled, let directoryURL else { return }
        let timestamp = Date.now.formatted(Self.timestampFormat)
        let tag: String
        switch level {
        case 0: tag = "DEBUG"
        case 1: tag = "INFO"
        case 2: tag = "WARN"
        default: tag = "ERROR"
        }
        guard let data = "[\(timestamp)] [\(tag)] [\(name)] \(message)\n".data(using: .utf8, allowLossyConversion: false) else { return }
        if fileHandle == nil {
            if let fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
                fileHandle = try? FileHandle(forWritingTo: fileURL)
                fileHandle?.seekToEndOfFile()
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd-HHmmss"
                let filename = "paste-diagnostics-" + formatter.string(from: Date()) + "-"
                    + ProcessInfo.processInfo.processIdentifier.description + ".log"
                let url = directoryURL.appendingPathComponent(filename)
                _ = FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
                fileHandle = try? FileHandle(forWritingTo: url)
                fileURL = url
            }
        }
        fileHandle?.write(data)
        fileHandle?.synchronizeFile()
    }

    public func close() {
        try? fileHandle?.close()
        fileHandle = nil
    }
}
