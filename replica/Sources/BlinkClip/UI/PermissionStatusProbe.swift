import Darwin
import Foundation
import BlinkClipCore

struct PermissionStatusReading: Equatable, Sendable {
    let currentProcess: PermissionStatusSnapshot
    let freshProcess: PermissionStatusSnapshot?
    let checkFailed: Bool

    var authorization: PermissionStatusSnapshot { freshProcess ?? currentProcess }
    var needsRestart: Bool {
        guard let freshProcess else { return false }
        return (freshProcess.accessibility && !currentProcess.accessibility)
            || (freshProcess.postEvents && !currentProcess.postEvents)
            || (freshProcess.screenRecording && !currentProcess.screenRecording)
    }
}

enum PermissionStatusProbe {
    enum Failure: Error { case unavailable, launch, timeout, cancelled, identity, invalidReply }

    /// Only the actual app uses the child process. Test harnesses and previews
    /// fall back to their own checks instead of recursively launching themselves.
    static func read() async -> PermissionStatusReading {
        let local = await Task.detached(priority: .utility) { PermissionStatusSnapshot.current() }.value
        guard isAppExecutable(bundleIdentifier: Bundle.main.bundleIdentifier,
                              executableName: Bundle.main.executableURL?.lastPathComponent) else {
            return PermissionStatusReading(currentProcess: local, freshProcess: nil, checkFailed: false)
        }
        guard let identity = PermissionProbeIdentity.current() else {
            return PermissionStatusReading(currentProcess: local, freshProcess: nil, checkFailed: true)
        }
        do {
            let fresh = try await run(executable: URL(fileURLWithPath: identity.executablePath), expected: identity)
            return PermissionStatusReading(currentProcess: local, freshProcess: fresh, checkFailed: false)
        } catch {
            return PermissionStatusReading(currentProcess: local, freshProcess: nil, checkFailed: true)
        }
    }

    static func isAppExecutable(bundleIdentifier: String?, executableName: String?) -> Bool {
        bundleIdentifier == "com.chrisli.blinkclip"
            && executableName == "BlinkClip"
    }

    static func validate(_ data: Data, expected: PermissionProbeIdentity) throws -> PermissionStatusSnapshot {
        guard data.count <= 4096, let reply = try? JSONDecoder().decode(PermissionProbeReply.self, from: data),
              reply.version == 1 else { throw Failure.invalidReply }
        guard reply.identity == expected else { throw Failure.identity }
        return reply.status
    }

    static func run(executable: URL, expected: PermissionProbeIdentity, timeout: TimeInterval = 2,
                    arguments: [String] = [PermissionProbeCommand.argument]) async throws -> PermissionStatusSnapshot {
        let cancellation = ProbeCancellation()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    let process = Process()
                    let output = Pipe()
                    process.executableURL = executable
                    process.arguments = arguments
                    process.standardOutput = output
                    process.standardError = FileHandle.nullDevice
                    do {
                        guard !cancellation.isCancelled else { throw Failure.cancelled }
                        try process.run()
                        try output.fileHandleForWriting.close()
                        let deadline = Date().addingTimeInterval(timeout)
                        while process.isRunning && Date() < deadline && !cancellation.isCancelled {
                            Thread.sleep(forTimeInterval: 0.01)
                        }
                        if process.isRunning {
                            process.terminate()
                            let grace = Date().addingTimeInterval(0.1)
                            while process.isRunning && Date() < grace { Thread.sleep(forTimeInterval: 0.005) }
                            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
                            let reapDeadline = Date().addingTimeInterval(0.3)
                            while process.isRunning && Date() < reapDeadline { Thread.sleep(forTimeInterval: 0.005) }
                            throw cancellation.isCancelled ? Failure.cancelled : Failure.timeout
                        }
                        guard !cancellation.isCancelled else { throw Failure.cancelled }
                        guard process.terminationStatus == 0 else { throw Failure.launch }
                        let data = try output.fileHandleForReading.read(upToCount: 4097) ?? Data()
                        continuation.resume(returning: try validate(data, expected: expected))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                    try? output.fileHandleForReading.close()
                    try? output.fileHandleForWriting.close()
                }
            }
        }, onCancel: { cancellation.cancel() })
    }
}

private final class ProbeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
