import Combine
import Foundation
import os

/// Version strings accepted by the release scripts, by Sparkle's appcast
/// (`sparkle:version`) and by the installed bundle:
///
/// - three or four numeric components — `1.0.11`, `1.0.11.3`, `v1.0.11`
/// - an optional pre-release suffix — `1.0.12-dev.4`, `1.0.12-beta.1`
///
/// Comparison is numeric per component, so `1.0.10 < 1.0.11` (a string compare
/// would invert them) and a four-part build `1.0.11.3` sorts after `1.0.11`.
/// Missing trailing components count as zero. A pre-release sorts before the
/// release it leads up to, ordered by channel: alpha < beta < rc < dev.
public struct BlinkClipReleaseVersion: Comparable, Sendable, CustomStringConvertible {
    /// The version as written, without a leading `v`.
    public let text: String
    private let numbers: [Int]
    private let prerelease: Prerelease?

    private struct Prerelease: Equatable, Sendable {
        let channel: String
        let ordinal: Int
    }

    /// Channel order for pre-release comparison; a plain release is greater than all of them.
    private static let channels = ["alpha", "beta", "rc", "dev"]
    private static let pattern = #"\Av?([0-9]+(?:\.[0-9]+){2,3})(?:-(alpha|beta|rc|dev)\.([0-9]+))?\z"#

    /// The `-dev.N` ordinal of a development build, `nil` for any other version.
    public var development: Int? { prerelease?.channel == "dev" ? prerelease?.ordinal : nil }

    /// Whether this version is a pre-release of the release with the same numbers.
    public var isPrerelease: Bool { prerelease != nil }

    public var description: String { text }

    public init?(_ value: String) {
        guard !value.isEmpty,
              let regex = try? NSRegularExpression(pattern: Self.pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              match.range == NSRange(value.startIndex..<value.endIndex, in: value) else { return nil }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: value).map { String(value[$0]) }
        }
        guard let core = group(1) else { return nil }
        // A component that does not fit an Int (e.g. 21 digits) drops out here and the count check fails.
        let components = core.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 || components.count == 4 else { return nil }
        numbers = components
        text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        if let channel = group(2), let ordinal = group(3).flatMap(Int.init) {
            prerelease = Prerelease(channel: channel, ordinal: ordinal)
        } else {
            prerelease = nil
        }
    }

    /// `1.0.11` and `1.0.11.0` describe the same build.
    private var comparableNumbers: [Int] {
        numbers + Array(repeating: 0, count: max(0, 4 - numbers.count))
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.comparableNumbers == rhs.comparableNumbers && lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.comparableNumbers != rhs.comparableNumbers {
            return lhs.comparableNumbers.lexicographicallyPrecedes(rhs.comparableNumbers)
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (left?, right?):
            let leftRank = Self.channels.firstIndex(of: left.channel) ?? Self.channels.count
            let rightRank = Self.channels.firstIndex(of: right.channel) ?? Self.channels.count
            if leftRank != rightRank { return leftRank < rightRank }
            return left.ordinal < right.ordinal
        }
    }
}

public struct BlinkClipAvailableUpdate: Equatable, Sendable {
    public let version: String
    public let downloadURL: URL
    public let minimumSystemVersion: String?

    public init(version: String, downloadURL: URL, minimumSystemVersion: String? = nil) {
        self.version = version
        self.downloadURL = downloadURL
        self.minimumSystemVersion = minimumSystemVersion
    }
}

/// The signed appcast Sparkle reads (`SUFeedURL`), parsed without Sparkle so the
/// About window can show a version summary before the updater starts.
///
/// Reading the appcast instead of `api.github.com/repos/.../releases/latest`
/// keeps the check on a CDN asset: anonymous GitHub API calls are limited to 60
/// requests per hour per IP and answer `403` once that budget is gone, which the
/// About window then showed verbatim as “(HTTP 403)”.
struct BlinkClipAppcast {
    struct Item: Equatable {
        let version: BlinkClipReleaseVersion
        let shortVersion: String?
        let minimumSystemVersion: String?
        let downloadURL: URL?
        let publishedAt: String?
    }

    enum ParseError: Error { case malformed, empty }

    static func items(from data: Data) throws -> [Item] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw ParseError.malformed }
        let items = delegate.rawItems.compactMap { raw -> Item? in
            guard let text = raw.version, let version = BlinkClipReleaseVersion(text) else { return nil }
            let url = raw.enclosureURL.flatMap(URL.init(string:))
            return Item(version: version, shortVersion: raw.shortVersion,
                        minimumSystemVersion: raw.minimumSystemVersion,
                        downloadURL: url, publishedAt: raw.publishedAt)
        }
        guard !items.isEmpty else { throw ParseError.empty }
        return items
    }

    /// The newest stable item this Mac can run. A feed whose newest item needs a
    /// newer macOS falls through to the next one instead of offering an
    /// uninstallable update.
    static func newestApplicable(_ items: [Item],
                                 running: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> Item? {
        items
            .filter { !$0.version.isPrerelease && supports(running, minimum: $0.minimumSystemVersion) }
            .max { $0.version < $1.version }
    }

    static func supports(_ running: OperatingSystemVersion, minimum: String?) -> Bool {
        guard let minimum else { return true }
        guard let required = components(minimum) else { return true }
        let current = [running.majorVersion, running.minorVersion, running.patchVersion]
        return !current.lexicographicallyPrecedes(required)
    }

    private static func components(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard let number = Int(part), number >= 0 else { return nil }
            numbers.append(number)
        }
        return numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        struct RawItem {
            var version: String?
            var shortVersion: String?
            var minimumSystemVersion: String?
            var enclosureURL: String?
            var publishedAt: String?
        }

        private(set) var rawItems: [RawItem] = []
        private var current: RawItem?
        private var buffer = ""

        /// Handles both `sparkle:version` (namespaces not processed) and a
        /// namespace-aware `version`, so a re-serialized feed parses the same.
        private func localName(_ elementName: String, _ qualifiedName: String?) -> String {
            let name = qualifiedName ?? elementName
            return String(name.split(separator: ":").last ?? Substring(name))
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            let name = localName(elementName, qName)
            switch name {
            case "item": current = RawItem()
            case "enclosure": current?.enclosureURL = attributes["url"]
            default: break
            }
            buffer = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            buffer += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            defer { buffer = "" }
            guard var item = current else { return }
            let name = localName(elementName, qName)
            let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            switch name {
            case "version": item.version = text
            case "shortVersionString": item.shortVersion = text
            case "minimumSystemVersion": item.minimumSystemVersion = text
            case "pubDate": item.publishedAt = text
            case "item":
                rawItems.append(item)
                current = nil
                return
            default: break
            }
            current = item
        }
    }
}

@MainActor
public final class BlinkClipUpdateChecker: ObservableObject {
    public enum State: Equatable {
        case idle, checking, upToDate
        case available(BlinkClipAvailableUpdate)
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    /// Diagnostics for logs and tests. Never rendered: users only ever see the
    /// gentle copy in `State.failed`, so a status code can't leak into the UI.
    @Published public private(set) var lastDiagnostic: String?

    public let currentVersion: String
    /// `SUFeedURL` from the app bundle: the signed Sparkle appcast.
    public let feedURL: URL?

    private let session: URLSession
    private var lastAttempt: Date?
    private static let log = Logger(subsystem: "com.chrisli.blinkclip", category: "updates")
    private static let minimumCheckInterval: TimeInterval = 6 * 60 * 60

    public init(currentVersion: String? = nil, session: URLSession = .shared, feedURL: URL? = nil) {
        self.currentVersion = currentVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "BlinkClipSourceVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "unknown"
        self.feedURL = feedURL ?? Self.configuredFeedURL()
        self.session = session
    }

    /// The release feed the shipped app advertises to Sparkle.
    public static func configuredFeedURL(bundle: Bundle = .main) -> URL? {
        guard let raw = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil else { return nil }
        return url
    }

    /// Called when About BlinkClip opens. Manual checks bypass the six-hour throttle.
    public func check(force: Bool = false, now: Date = Date()) async {
        guard state != .checking else { return }
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.minimumCheckInterval { return }
        lastAttempt = now
        state = .checking
        do {
            guard let current = BlinkClipReleaseVersion(currentVersion) else {
                throw CheckError.invalidCurrentVersion
            }
            guard let feedURL else {
                lastDiagnostic = "SUFeedURL missing or not https in Info.plist"
                Self.log.error("appcast unavailable: SUFeedURL missing or not https")
                throw CheckError.unreachable
            }
            var request = URLRequest(url: feedURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/xml, text/xml;q=0.9", forHTTPHeaderField: "Accept")
            request.setValue("BlinkClip/\(current.text)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastDiagnostic = "appcast response was not HTTP"
                Self.log.error("appcast response was not HTTP")
                throw CheckError.unreachable
            }
            guard (200..<300).contains(http.statusCode) else {
                lastDiagnostic = "appcast HTTP status \(http.statusCode) for \(feedURL.absoluteString)"
                Self.log.error("appcast status=\(http.statusCode, privacy: .public) url=\(feedURL.absoluteString, privacy: .public)")
                throw CheckError.unreachable
            }
            let items: [BlinkClipAppcast.Item]
            do {
                items = try BlinkClipAppcast.items(from: data)
            } catch {
                lastDiagnostic = "appcast parse failed for \(data.count) bytes"
                Self.log.error("appcast parse failed bytes=\(data.count, privacy: .public)")
                throw CheckError.unreachable
            }
            let stable = items.filter { !$0.version.isPrerelease }
            guard !stable.isEmpty else {
                lastDiagnostic = "appcast carries no stable item (\(items.count) items)"
                Self.log.error("appcast stable items=0 total=\(items.count, privacy: .public)")
                throw CheckError.unreachable
            }
            guard let newest = BlinkClipAppcast.newestApplicable(stable) else {
                // Every stable item needs a newer macOS than this one: nothing to offer.
                lastDiagnostic = "appcast items=\(items.count) none-applicable"
                Self.log.notice("appcast items=\(items.count, privacy: .public) none applicable, treated as up to date")
                state = .upToDate
                return
            }
            lastDiagnostic = "appcast items=\(items.count) newest=\(newest.version.text)"
            Self.log.notice("""
                appcast ok items=\(items.count, privacy: .public) \
                newest=\(newest.version.text, privacy: .public) \
                installed=\(current.text, privacy: .public)
                """)
            if newest.version <= current {
                state = .upToDate
                return
            }
            guard let url = newest.downloadURL, url.scheme?.lowercased() == "https" else {
                lastDiagnostic = "appcast item \(newest.version.text) has no https enclosure"
                Self.log.error("appcast item=\(newest.version.text, privacy: .public) enclosure missing")
                throw CheckError.missingInstaller
            }
            state = .available(BlinkClipAvailableUpdate(version: newest.version.text,
                                                        downloadURL: url,
                                                        minimumSystemVersion: newest.minimumSystemVersion))
        } catch let error as CheckError {
            Self.log.error("update check failed: \(error.logDescription, privacy: .public)")
            state = .failed(error.errorDescription ?? SettingsLocalization.text("updates.unreachable"))
        } catch {
            lastDiagnostic = "appcast request failed: \(error.localizedDescription)"
            Self.log.error("appcast request failed: \(String(describing: error), privacy: .public)")
            state = .failed(SettingsLocalization.text("updates.unreachable"))
        }
    }

    private enum CheckError: LocalizedError {
        case invalidCurrentVersion, unreachable, missingInstaller

        /// What goes to the log; the user copy below never carries a status code.
        var logDescription: String {
            switch self {
            case .invalidCurrentVersion: return "installed version unreadable"
            case .unreachable: return "appcast unreachable or unreadable"
            case .missingInstaller: return "appcast enclosure missing"
            }
        }

        var errorDescription: String? {
            switch self {
            case .invalidCurrentVersion: return SettingsLocalization.text("updates.invalid-version")
            case .unreachable: return SettingsLocalization.text("updates.unreachable")
            case .missingInstaller: return SettingsLocalization.text("updates.missing-installer")
            }
        }
    }
}
