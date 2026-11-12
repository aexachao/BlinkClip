import ApplicationServices
import CoreGraphics
import Foundation
import Security

/// Read-only checks. This type never requests access or captures screen contents.
public struct PermissionStatusSnapshot: Codable, Equatable, Sendable {
    public var accessibility: Bool
    public var postEvents: Bool
    public var screenRecording: Bool

    public init(accessibility: Bool, postEvents: Bool, screenRecording: Bool) {
        self.accessibility = accessibility
        self.postEvents = postEvents
        self.screenRecording = screenRecording
    }

    public static func current() -> Self {
        Self(accessibility: AXIsProcessTrusted(), postEvents: CGPreflightPostEventAccess(),
             screenRecording: CGPreflightScreenCaptureAccess())
    }
}

public struct PermissionProbeIdentity: Codable, Equatable, Sendable {
    public let executablePath: String
    public let bundleIdentifier: String?
    public let codeHash: String

    public init(executablePath: String, bundleIdentifier: String?, codeHash: String) {
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.codeHash = codeHash
    }

    public static func current() -> Self? {
        guard let executable = Bundle.main.executableURL else { return nil }
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let hash = dictionary[kSecCodeInfoUnique as String] as? Data, !hash.isEmpty else { return nil }
        return Self(executablePath: executable.standardizedFileURL.resolvingSymlinksInPath().path,
                    bundleIdentifier: Bundle.main.bundleIdentifier,
                    codeHash: hash.map { String(format: "%02x", $0) }.joined())
    }
}

public struct PermissionProbeReply: Codable, Equatable, Sendable {
    public let version: Int
    public let identity: PermissionProbeIdentity
    public let status: PermissionStatusSnapshot

    public init(identity: PermissionProbeIdentity, status: PermissionStatusSnapshot) {
        version = 1
        self.identity = identity
        self.status = status
    }
}

/// Called before NSApplication, the delegate, preferences, or the clipboard store.
public enum PermissionProbeCommand {
    public static let argument = "--permission-status-probe-v1"

    public static func handleIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.contains(argument) else { return nil }
        guard arguments.count == 2, arguments[1] == argument,
              let identity = PermissionProbeIdentity.current(),
              let data = try? JSONEncoder().encode(PermissionProbeReply(identity: identity, status: .current())) else {
            return 64
        }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
        return 0
    }
}
