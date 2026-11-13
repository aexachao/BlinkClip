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
    /// Developer ID builds sign for a team; ad-hoc and Apple Development builds
    /// either have no team or a team TCC never stores, which is why their TCC
    /// requirement is pinned to the cdhash instead of to this identity.
    public let teamIdentifier: String?

    public init(executablePath: String, bundleIdentifier: String?, codeHash: String,
                teamIdentifier: String? = nil) {
        self.executablePath = executablePath
        self.bundleIdentifier = bundleIdentifier
        self.codeHash = codeHash
        self.teamIdentifier = teamIdentifier
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
                    codeHash: hash.map { String(format: "%02x", $0) }.joined(),
                    teamIdentifier: dictionary[kSecCodeInfoTeamIdentifier as String] as? String)
    }
}

/// What the last successful authorization was granted to. macOS stores a TCC
/// grant against the *code requirement* of the build that was ticked in System
/// Settings, so a rebuilt binary can hold a checked checkbox and still be
/// denied. Remembering the winning identity is the only signal the app itself
/// can observe about that mismatch: TCC's database is not readable without Full
/// Disk Access.
public struct PermissionGrantMemory: Codable, Equatable, Sendable {
    public let codeHash: String
    public let bundleIdentifier: String?
    public let teamIdentifier: String?
    public let shortVersion: String?
    public let recordedAt: Date

    public init(codeHash: String, bundleIdentifier: String?, teamIdentifier: String?,
                shortVersion: String?, recordedAt: Date) {
        self.codeHash = codeHash
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.shortVersion = shortVersion
        self.recordedAt = recordedAt
    }
}

public enum PermissionGrantLedger {
    /// Bundle-scoped and path-independent: the record must survive moving the
    /// app out of /tmp, re-installing over /Applications, and Sparkle updates.
    public static let defaultsKey = "BlinkClip.PermissionGrant.v1"

    public static func memory(defaults: UserDefaults = .standard) -> PermissionGrantMemory? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(PermissionGrantMemory.self, from: data)
    }

    /// Only a live grant overwrites the record. A denial must never erase the
    /// identity that previously worked, or the mismatch signal would disappear
    /// exactly when it is needed.
    @discardableResult
    public static func recordGrant(identity: PermissionProbeIdentity, shortVersion: String?,
                                   recordedAt: Date = Date(),
                                   defaults: UserDefaults = .standard) -> PermissionGrantMemory {
        let memory = PermissionGrantMemory(codeHash: identity.codeHash,
                                           bundleIdentifier: identity.bundleIdentifier,
                                           teamIdentifier: identity.teamIdentifier,
                                           shortVersion: shortVersion, recordedAt: recordedAt)
        if let data = try? JSONEncoder().encode(memory) {
            defaults.set(data, forKey: defaultsKey)
        }
        return memory
    }

    /// A checked-but-denied state. True only when a grant is on record for a
    /// *different* code identity, i.e. the system still holds the previous
    /// build's requirement (ad-hoc or another certificate) and re-ticking the
    /// existing list entry cannot match this one. The fix is to remove the old
    /// entry and add the current bundle again.
    public static func requirementMismatch(isTrusted: Bool, identity: PermissionProbeIdentity,
                                           defaults: UserDefaults = .standard) -> Bool {
        guard !isTrusted, let memory = memory(defaults: defaults) else { return false }
        return memory.codeHash != identity.codeHash
            || memory.bundleIdentifier != identity.bundleIdentifier
    }

    public static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
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
