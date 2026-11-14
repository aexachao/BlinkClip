import AppKit
import Foundation
import BlinkClipCore

private final class UpdateProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var payload = Data()
    private static var status = 200
    private static var failure: Error?
    private static var delay: TimeInterval = 0.02
    private static var requests: [URLRequest] = []

    static func reply(_ data: Data, status: Int = 200, failure: Error? = nil,
                      delay: TimeInterval = 0.02) {
        lock.withLock {
            payload = data
            self.status = status
            self.failure = failure
            Self.delay = delay
            requests = []
        }
    }

    static var capturedRequests: [URLRequest] { lock.withLock { requests } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() { }

    override func startLoading() {
        let (data, status, failure, delay) = Self.lock.withLock {
            Self.requests.append(request)
            return (Self.payload, Self.status, Self.failure, Self.delay)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [self] in
            if let failure {
                client?.urlProtocol(self, didFailWithError: failure)
                return
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/xml"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }
}

@main
struct AppUpdateHarness {
    struct Failure: Error { let message: String }
    static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw Failure(message: message) }
    }

    static let feedURL = URL(string: "https://github.com/aexachao/BlinkClip/releases/latest/download/appcast.xml")!
    static let dmgURL = "https://github.com/aexachao/BlinkClip/releases/download/v1.0.11/BlinkClip-1.0.11-macos-universal.dmg"

    struct FeedItem {
        var version = "1.0.11"
        var shortVersion: String? = nil
        var minimumSystem: String? = "14.0"
        var enclosure: String? = dmgURL
    }

    /// A Sparkle-shaped appcast, including the trailing signature comment the
    /// real signed feed carries.
    static func appcast(_ items: [FeedItem] = [FeedItem()]) -> Data {
        let entries = items.map { item -> String in
            var lines = [
                "<item>",
                "<title>BlinkClip \(item.version)</title>",
                "<link>https://github.com/aexachao/BlinkClip/releases/tag/v\(item.version)</link>",
                "<pubDate>Sat, 14 Nov 2026 04:47:06 +0000</pubDate>",
                "<sparkle:version>\(item.version)</sparkle:version>",
                "<sparkle:shortVersionString>\(item.shortVersion ?? item.version)</sparkle:shortVersionString>"
            ]
            if let minimum = item.minimumSystem {
                lines.append("<sparkle:minimumSystemVersion>\(minimum)</sparkle:minimumSystemVersion>")
            }
            if let enclosure = item.enclosure {
                lines.append("<enclosure url=\"\(enclosure)\" sparkle:edSignature=\"c2lnbmF0dXJl\" length=\"16301712\" type=\"application/octet-stream\"></enclosure>")
            }
            lines.append("</item>")
            return lines.joined(separator: "\n")
        }
        let xml = """
        <?xml version="1.0" encoding="utf-8" standalone="yes"?><!-- sparkle-sign-warning:
        IMPORTANT: This file was signed by Sparkle.
        --><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">\
        <channel><title>BlinkClip Updates</title>\
        <link>https://aexachao.github.io/BlinkClip/</link>\
        <description>BlinkClip stable macOS updates</description>\
        \(entries.joined())</channel></rss><!-- sparkle-signatures:
        edSignature: c2lnbmF0dXJl
        length: 1167
        -->
        """
        return Data(xml.utf8)
    }

    static func reply(_ data: Data, status: Int = 200, delay: TimeInterval = 0.02) {
        UpdateProtocol.reply(data, status: status, delay: delay)
    }
    static func reply(feed items: [FeedItem], status: Int = 200, delay: TimeInterval = 0.02) {
        reply(appcast(items), status: status, delay: delay)
    }

    @MainActor static func pause() async { try? await Task.sleep(nanoseconds: 250_000_000) }

    // ── live feed ────────────────────────────────────────────────────────────
    /// Raised when the live probe cannot decide anything because the network is
    /// gone. `test-app-updates.sh` turns this into `skipped`, never a failure:
    /// an unreachable CDN is not a product defect and must not go red.
    struct LiveSkip: Error { let reason: String }

    static func argumentValue(_ name: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: name),
              index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    static func printSkipped(_ reason: String) {
        print("skipped: \(reason)")
        let payload: [String: Any] = ["live_appcast": "skipped", "reason": reason]
        print(String(data: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data(), encoding: .utf8) ?? "{}")
    }

    /// The live expectations come from the script, which reads the real
    /// appcast. No version is written down here: a new release bumps the feed,
    /// and the assertions follow it.
    static func liveArguments() throws -> (feed: URL, version: BlinkClipReleaseVersion, installed: BlinkClipReleaseVersion?) {
        guard let versionText = argumentValue("--live-version") else {
            throw Failure(message: "--live needs --live-version <version>; run replica/scripts/test-app-updates.sh --live")
        }
        guard let version = BlinkClipReleaseVersion(versionText) else {
            throw Failure(message: "--live-version is not a release version: \(versionText)")
        }
        let feedText = argumentValue("--live-feed") ?? feedURL.absoluteString
        guard let feed = URL(string: feedText) else {
            throw Failure(message: "--live-feed is not a URL: \(feedText)")
        }
        var installed: BlinkClipReleaseVersion?
        if let installedText = argumentValue("--live-installed") {
            guard let parsed = BlinkClipReleaseVersion(installedText) else {
                throw Failure(message: "--live-installed is not a release version: \(installedText)")
            }
            installed = parsed
        }
        return (feed, version, installed)
    }

    /// A raw fetch of the feed, used only to tell "the network is gone" (skip)
    /// from "the feed answers but the product cannot read it" (a real failure).
    @MainActor static func feedProbe(_ url: URL) async -> (reachable: Bool, detail: String) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
            guard let http = response as? HTTPURLResponse else { return (false, "no HTTP response") }
            guard http.statusCode == 200 else { return (false, "HTTP \(http.statusCode)") }
            guard !data.isEmpty else { return (false, "the feed answered with an empty body") }
            return (true, "HTTP 200, \(data.count) bytes")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    @MainActor static func liveChecker(installed: String, feed: URL) async -> BlinkClipUpdateChecker {
        let checker = BlinkClipUpdateChecker(currentVersion: installed,
                                             session: URLSession(configuration: .ephemeral),
                                             feedURL: feed, defaults: freshDefaults())
        await checker.check(force: true)
        return checker
    }

    /// A failed check against a feed that still answers is a product defect;
    /// against a feed that does not answer it is the network, which is a skip.
    @MainActor static func refine(_ checker: BlinkClipUpdateChecker, feed: URL) async throws {
        guard case let .failed(reason) = checker.state else { return }
        let probe = await feedProbe(feed)
        guard probe.reachable else { throw LiveSkip(reason: "appcast unreachable: \(probe.detail)") }
        let diagnostic = checker.lastDiagnostic.map { " (diagnostic: \($0))" } ?? ""
        throw Failure(message: "the appcast answers (\(probe.detail)) but the product cannot read it: \(reason)\(diagnostic)")
    }

    /// Every About controller in this harness gets its own defaults domain, so
    /// one scenario's persisted timestamp cannot leak into the next.
    static func freshDefaults() -> UserDefaults {
        let suite = "local.blinkclip.regression.updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @MainActor static func lastCheckedText(_ date: Date) -> String {
        String(format: SettingsLocalization.text("updates.last-check-format"),
               BlinkClipUpdateChecker.timeText(date))
    }

    @MainActor static var neverCheckedText: String { SettingsLocalization.text("updates.never-checked") }

    /// Geometry the About window promises, measured in content coordinates:
    /// the status line sits 8 pt above the button row on the same centred axis,
    /// and the button group is centred with equal left/right margins.
    struct AboutLayout {
        let statusButtonGap: CGFloat
        let statusRowCenterOffset: CGFloat
        let buttonLeftInset: CGFloat
        let buttonRightInset: CGFloat
        let statusHeight: CGFloat
        let buttonGroupWidth: CGFloat
        var debugDescription: String = ""

        var json: [String: Any] {
            ["status_button_gap": Double(statusButtonGap),
             "status_row_center_offset": Double(statusRowCenterOffset),
             "button_left_inset": Double(buttonLeftInset),
             "button_right_inset": Double(buttonRightInset),
             "status_height": Double(statusHeight),
             "button_group_width": Double(buttonGroupWidth)]
        }
    }

    @MainActor static func layout(_ controller: BlinkClipAboutWindowController) -> AboutLayout {
        guard let content = controller.window?.contentView else {
            return AboutLayout(statusButtonGap: -1, statusRowCenterOffset: -1,
                               buttonLeftInset: -1, buttonRightInset: -1,
                               statusHeight: -1, buttonGroupWidth: -1)
        }
        content.layoutSubtreeIfNeeded()
        let status = controller.statusLabel.convert(controller.statusLabel.bounds, to: content)
        let check = controller.checkButton.convert(controller.checkButton.bounds, to: content)
        let close = controller.closeButton.convert(controller.closeButton.bounds, to: content)
        let group = check.union(close)
        var measured = AboutLayout(statusButtonGap: status.minY - group.maxY,
                                   statusRowCenterOffset: status.midX - group.midX,
                                   buttonLeftInset: group.minX,
                                   buttonRightInset: content.bounds.width - group.maxX,
                                   statusHeight: status.height,
                                   buttonGroupWidth: group.width)
        let row = controller.checkButton.superview
        let holder = row?.superview
        let rowFrame = row.map { $0.convert($0.bounds, to: content) }
        let holderFrame = holder.map { $0.convert($0.bounds, to: content) }
        measured.debugDescription = "status=\(status) check=\(check) close=\(close) row=\(String(describing: rowFrame)) holder=\(String(describing: holderFrame)) content=\(content.bounds)"
        return measured
    }

    @MainActor static func assertAboutLayout(_ controller: BlinkClipAboutWindowController) throws {
        let measured = layout(controller)
        try check(measured.statusButtonGap >= 8 && measured.statusButtonGap <= 12,
                  "Status line is not 8–10 pt above the buttons: \(measured.statusButtonGap) \(measured.debugDescription)")
        try check(abs(measured.statusRowCenterOffset) <= 2,
                  "Status line is not centred over the buttons: \(measured.statusRowCenterOffset)")
        try check(abs(measured.buttonLeftInset - measured.buttonRightInset) <= 2,
                  "Button group is not centred in the window: left \(measured.buttonLeftInset) right \(measured.buttonRightInset)")
    }

    /// A completed check reports the timestamp only. Sparkle's own
    /// user-initiated alert carries the "you're up to date" sentence; the inline
    /// line must not repeat it (and Sparkle 2.10.1 has no public hook to
    /// suppress that alert).
    @MainActor static func assertUpToDateAbout(_ checker: BlinkClipUpdateChecker, installed: String) throws {
        let controller = BlinkClipAboutWindowController(checker: checker, sparkleCheck: {})
        guard let checkedAt = checker.lastCheckDate else {
            throw Failure(message: "About has no completed-check timestamp for \(installed)")
        }
        let expected = lastCheckedText(checkedAt)
        try check(controller.statusLabel.stringValue == expected,
                  "About does not report the check time for \(installed): \(controller.statusLabel.stringValue)")
        try check(!controller.statusLabel.stringValue.lowercased().contains("up to date")
                  && !controller.statusLabel.stringValue.contains("已是最新"),
                  "About repeats Sparkle's no-update sentence: \(controller.statusLabel.stringValue)")
    }

    /// `--live`: compare the installed version against the version the real
    /// appcast serves right now.
    @MainActor static func liveCheck(feed: URL, feedVersion: BlinkClipReleaseVersion,
                                     installed: BlinkClipReleaseVersion?) async throws {
        guard let scheme = feed.scheme?.lowercased(), scheme == "https" || scheme == "http" else {
            throw Failure(message: "the live feed is not an http(s) URL: \(feed.absoluteString)")
        }
        let probe = await feedProbe(feed)
        guard probe.reachable else { throw LiveSkip(reason: "appcast unreachable: \(probe.detail)") }

        // An install that already runs the live version must read as current.
        let atLive = await liveChecker(installed: feedVersion.text, feed: feed)
        try await refine(atLive, feed: feed)
        if case let .available(update) = atLive.state {
            throw LiveSkip(reason: "the appcast advanced to \(update.version) during the run; \(feedVersion.text) was read a moment ago")
        }
        try check(atLive.state == .upToDate,
                  "installed \(feedVersion.text) was not reported as up to date: \(atLive.state)")
        try assertUpToDateAbout(atLive, installed: feedVersion.text)

        // The compared install: one patch below the feed, or --live-installed.
        var reported = "up-to-date"
        if let installed {
            let comparison = await liveChecker(installed: installed.text, feed: feed)
            try await refine(comparison, feed: feed)
            if installed < feedVersion {
                reported = "available"
                guard case let .available(update) = comparison.state else {
                    if case .upToDate = comparison.state {
                        throw Failure(message: "the live appcast (\(feedVersion.text)) was not offered to the older install \(installed.text)")
                    }
                    throw Failure(message: "the live check for installed \(installed.text) ended in \(comparison.state)")
                }
                guard BlinkClipReleaseVersion(update.version) == feedVersion else {
                    throw LiveSkip(reason: "the appcast offered \(update.version) to \(installed.text), not the \(feedVersion.text) read a moment ago")
                }
                try check(update.downloadURL.scheme?.lowercased() == "https",
                          "the live enclosure is not https: \(update.downloadURL)")
                try check(update.downloadURL.pathExtension.lowercased() == "dmg",
                          "the live enclosure is not a DMG: \(update.downloadURL)")
                let controller = BlinkClipAboutWindowController(checker: comparison, sparkleCheck: {})
                try check(controller.statusLabel.stringValue.contains(update.version),
                          "About does not mention the live version \(update.version): \(controller.statusLabel.stringValue)")
            } else {
                if case let .available(update) = comparison.state,
                   let offered = BlinkClipReleaseVersion(update.version), offered > feedVersion {
                    throw LiveSkip(reason: "the appcast advanced to \(update.version) while the run expected \(feedVersion.text) to be newest")
                }
                try check(comparison.state == .upToDate,
                          "installed \(installed.text) was offered an update by the live appcast: \(comparison.state)")
                try assertUpToDateAbout(comparison, installed: installed.text)
            }
        }
        let payload: [String: Any] = ["live_appcast": true,
                                      "feed": feed.absoluteString,
                                      "feed_version": feedVersion.text,
                                      "installed": installed?.text ?? feedVersion.text,
                                      "expectation": reported]
        print(String(data: (try? JSONSerialization.data(withJSONObject: payload)) ?? Data(), encoding: .utf8) ?? "{}")
    }

    @MainActor static func main() async {
        do {
            let app = NSApplication.shared
            app.setActivationPolicy(.accessory)
            app.finishLaunching()
            let icon = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets/BlinkClipIcon.png")
            if let image = NSImage(contentsOf: icon) { app.applicationIconImage = image }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [UpdateProtocol.self]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            if CommandLine.arguments.contains("--preview") {
                try reply(feed: [FeedItem(version: "1.0.11")])
                let checker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
                let controller = BlinkClipAboutWindowController(checker: checker, sparkleCheck: {})
                controller.showWindow(nil)
                Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in NSApp.terminate(nil) }
                print("PREVIEW_READY")
                fflush(stdout)
                app.run()
                withExtendedLifetime(controller) { }
                return
            }
            try await run(session: session)
            if CommandLine.arguments.contains("--live") {
                // All expected versions come from the feed the script just read,
                // so a new release cannot turn this mode red.
                let live = try liveArguments()
                do {
                    try await liveCheck(feed: live.feed, feedVersion: live.version, installed: live.installed)
                } catch let skip as LiveSkip {
                    printSkipped(skip.reason)
                }
            }
            let summary = "{\"passed\":true,\"version_comparison\":true,\"appcast_parsing\":true,\"gentle_failures\":true,\"throttle_and_retry\":true,\"concurrent_checks\":true,\"about_controls\":true,\"about_layout\":true,\"last_check_timestamp\":true}"
            if let index = CommandLine.arguments.firstIndex(of: "--render"), index + 1 < CommandLine.arguments.count {
                let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
                let prepared = try await prepareRenders(session: session)
                // A default button is only emphasised in a key window, and a key
                // window only exists once the app runs its event loop. Prepare
                // (async) first, then snapshot from a timer inside a real app
                // run, so the screenshots show the weight a user actually sees
                // in both appearances instead of an inactive grey pair.
                NSApp.activate(ignoringOtherApps: true)
                Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { _ in
                    var code: Int32 = 0
                    do {
                        let written = try snapshot(prepared, into: directory)
                        print("{\"renders\":\(written),\"directory\":\"\(directory.path)\"}")
                        print(summary)
                    } catch {
                        print("{\"passed\":false,\"error\":\"\(String(describing: error))\"}")
                        code = 1
                    }
                    fflush(stdout)
                    exit(code)
                }
                app.run()
                return
            }
            print(summary)
        } catch {
            let result: [String: Any] = ["passed": false, "error": String(describing: error)]
            print(String(data: try! JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
            exit(1)
        }
    }

    @MainActor static func run(session: URLSession) async throws {
        // ── numeric version ordering ─────────────────────────────────────────
        for (older, newer) in [("1.0.9", "1.0.10"), ("1.0.10", "1.0.11"), ("1.99.99", "2.0.0"),
            ("1.0.11", "1.0.11.1"), ("1.0.11.1", "1.0.12"), ("1.0.11.9", "1.0.12"),
            ("1.0.5-dev.2", "1.0.5-dev.10"), ("1.0.5-dev.10", "1.0.5"),
            ("1.0.5-alpha.9", "1.0.5-beta.1"), ("1.0.5-beta.9", "1.0.5-rc.1"),
            ("1.0.5", "1.0.6-dev.1"), ("1.0.5-alpha.1", "1.0.5-dev.1")] {
            try check(BlinkClipReleaseVersion(older)! < BlinkClipReleaseVersion(newer)!, "Incorrect version order: \(older) < \(newer)")
            try check(!(BlinkClipReleaseVersion(newer)! < BlinkClipReleaseVersion(older)!), "Order is not antisymmetric: \(newer) < \(older)")
        }
        try check(BlinkClipReleaseVersion("v1.0.11") == BlinkClipReleaseVersion("1.0.11"), "Tag prefix changed comparison")
        try check(BlinkClipReleaseVersion("1.0.11") == BlinkClipReleaseVersion("1.0.11.0"), "Trailing zero component changed comparison")
        for value in ["", "1.0", "1.0.5\n", "1.-1.5", "1.0.5-beta", "1.0.5-dev.", "999999999999999999999.0.0",
                      "1.0.11.2.3", " 1.0.11", "1.0.11 "] {
            try check(BlinkClipReleaseVersion(value) == nil, "Invalid version accepted: \(value)")
        }

        // ── the feed URL comes from SUFeedURL ───────────────────────────────
        let probe = FileManager.default.temporaryDirectory
            .appendingPathComponent("blinkclip-feed-probe-\(UUID().uuidString).bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: probe, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "local.blinkclip.feedprobe",
                                    "CFBundlePackageType": "BNDL",
                                    "SUFeedURL": feedURL.absoluteString]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: probe.appendingPathComponent("Info.plist"))
        defer { try? FileManager.default.removeItem(at: probe) }
        try check(Bundle(url: probe) != nil, "probe bundle not loadable")
        try check(BlinkClipUpdateChecker.configuredFeedURL(bundle: Bundle(url: probe)!) == feedURL,
                  "SUFeedURL from the app bundle is not the feed source")
        try check(BlinkClipUpdateChecker.configuredFeedURL(bundle: .main) == nil,
                  "harness bundle unexpectedly declares SUFeedURL")

        // ── appcast happy path ──────────────────────────────────────────────
        try reply(feed: [FeedItem()])
        let checker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        await checker.check(force: true)
        guard case let .available(update) = checker.state else { throw Failure(message: "Missing newer appcast item: \(checker.state)") }
        try check(update.version == "1.0.11" && update.minimumSystemVersion == "14.0", "Wrong appcast version metadata")
        try check(update.downloadURL.absoluteString == dmgURL, "Wrong enclosure URL: \(update.downloadURL)")
        let request = UpdateProtocol.capturedRequests[0]
        try check(request.url == feedURL && request.httpMethod == "GET" && request.httpBody == nil,
                  "Unexpected update request: \(String(describing: request.url))")
        try check(request.url?.host != "api.github.com", "Update check still calls the GitHub API")
        try check(request.value(forHTTPHeaderField: "Authorization") == nil, "Update check sent credentials")
        try check(request.value(forHTTPHeaderField: "Accept")?.contains("xml") == true, "Update check did not ask for XML")
        try check(checker.lastDiagnostic?.contains("newest=1.0.11") == true, "Successful check left no diagnostic: \(checker.lastDiagnostic ?? "nil")")

        // Installed version is the current one, or newer: no update offered.
        for installed in ["1.0.11", "1.0.12", "1.0.11.0"] {
            let current = BlinkClipUpdateChecker(currentVersion: installed, session: session, feedURL: feedURL)
            try reply(feed: [FeedItem()])
            await current.check(force: true)
            try check(current.state == .upToDate, "Installed \(installed) was offered an update: \(current.state)")
        }
        // Four-part and pre-release feed entries must not be misread.
        let fourPart = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        try reply(feed: [FeedItem(version: "1.0.11.2", enclosure: dmgURL)])
        await fourPart.check(force: true)
        guard case let .available(four) = fourPart.state else { throw Failure(message: "Four-part appcast version rejected: \(fourPart.state)") }
        try check(four.version == "1.0.11.2", "Four-part version text changed")
        let preReleaseFeed = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        try reply(feed: [FeedItem(version: "1.0.12-dev.1", enclosure: dmgURL)])
        await preReleaseFeed.check(force: true)
        guard case .failed = preReleaseFeed.state else { throw Failure(message: "Pre-release-only feed offered an update") }
        // The stable item wins even when a newer pre-release sits next to it.
        let mixedFeed = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        try reply(feed: [FeedItem(version: "1.0.12-dev.1", enclosure: dmgURL), FeedItem()])
        await mixedFeed.check(force: true)
        guard case let .available(stable) = mixedFeed.state else { throw Failure(message: "Mixed feed lost its stable item: \(mixedFeed.state)") }
        try check(stable.version == "1.0.11", "Pre-release item was offered: \(stable.version)")
        // A newest item that needs a newer macOS falls back to one this Mac can run.
        let fallback = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        try reply(feed: [FeedItem(version: "1.0.12", minimumSystem: "99.0"), FeedItem()])
        await fallback.check(force: true)
        guard case let .available(supported) = fallback.state else { throw Failure(message: "Applicable fallback item ignored: \(fallback.state)") }
        try check(supported.version == "1.0.11", "Unrunnable newer item was offered: \(supported.version)")
        // Nothing runnable at all is "up to date", not an error.
        let tooNew = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        try reply(feed: [FeedItem(version: "1.0.12", minimumSystem: "99.0")])
        await tooNew.check(force: true)
        try check(tooNew.state == .upToDate, "Unrunnable feed was not treated as up to date: \(tooNew.state)")

        // ── gentle, code-free failures with diagnostics kept ────────────────
        let gentle = SettingsLocalization.text("updates.unreachable")
        for status in [403, 404, 429, 500] {
            let failing = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
            try reply(feed: [FeedItem()], status: status)
            await failing.check(force: true)
            guard case let .failed(message) = failing.state else { throw Failure(message: "HTTP \(status) reported as success") }
            try check(message == gentle, "HTTP \(status) produced non-gentle copy: \(message)")
            try check(!message.contains("HTTP") && !message.contains("\(status)"),
                      "HTTP \(status) leaked into the user copy: \(message)")
            try check(failing.lastDiagnostic?.contains("\(status)") == true,
                      "HTTP \(status) was not preserved for diagnostics: \(failing.lastDiagnostic ?? "nil")")
        }
        try reply(Data("invalid XML".utf8))
        let malformed = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        await malformed.check(force: true)
        guard case let .failed(malformedMessage) = malformed.state else { throw Failure(message: "Malformed appcast accepted") }
        try check(malformedMessage == gentle, "Malformed appcast produced non-gentle copy: \(malformedMessage)")
        try check(malformed.lastDiagnostic != nil, "Malformed appcast left no diagnostic")
        try reply(appcast([FeedItem(version: "", shortVersion: "")]))
        let emptyVersion = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        await emptyVersion.check(force: true)
        guard case .failed = emptyVersion.state else { throw Failure(message: "Item without a version accepted") }
        let noEnclosure = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        try reply(feed: [FeedItem(enclosure: nil)])
        await noEnclosure.check(force: true)
        guard case let .failed(noEnclosureMessage) = noEnclosure.state else { throw Failure(message: "Feed without an enclosure accepted") }
        try check(noEnclosureMessage == SettingsLocalization.text("updates.missing-installer"),
                  "Missing enclosure copy changed: \(noEnclosureMessage)")
        UpdateProtocol.reply(Data(), failure: URLError(.notConnectedToInternet))
        let offline = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        await offline.check(force: true)
        guard case let .failed(offlineMessage) = offline.state else { throw Failure(message: "Offline check reported as success") }
        try check(offlineMessage == gentle, "Offline check produced non-gentle copy: \(offlineMessage)")
        try check(offline.lastDiagnostic != nil, "Offline check left no diagnostic")
        // No SUFeedURL configured: no request at all, still gentle.
        try reply(feed: [FeedItem()])
        let noFeed = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session)
        await noFeed.check(force: true)
        guard case let .failed(noFeedMessage) = noFeed.state else { throw Failure(message: "Check without a feed URL reported success") }
        try check(noFeedMessage == gentle && UpdateProtocol.capturedRequests.isEmpty,
                  "Missing SUFeedURL was not handled locally: \(noFeedMessage)")

        // ── About window ────────────────────────────────────────────────────
        // 1. Nothing checked yet: no freshness claim, neutral copy, and the
        // status line belongs to the action block.
        let aboutDefaults = freshDefaults()
        var sparkleChecks = 0
        let idleChecker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session,
                                                 feedURL: feedURL, defaults: aboutDefaults)
        let controller = BlinkClipAboutWindowController(checker: idleChecker, sparkleCheck: { sparkleChecks += 1 })
        controller.window?.contentView?.layoutSubtreeIfNeeded()
        try check(controller.window?.contentView?.bounds.size == BlinkClipAboutWindowController.contentSize,
                  "About content size changed: \(String(describing: controller.window?.contentView?.bounds.size))")
        try check(controller.window?.contentView?.bounds.size == NSSize(width: 380, height: 420), "About window is not 380 by 420")
        try check(!controller.checkButton.isHidden && controller.checkButton.isEnabled, "Check button unavailable")
        try check(controller.checkButton.keyEquivalent == "\r", "Return does not start a check")
        try check(controller.closeButton.keyEquivalent == "\u{1b}", "Escape does not close the window")
        try check(controller.statusLabel.stringValue == neverCheckedText,
                  "About claims a result before any check: \(controller.statusLabel.stringValue)")
        try check(!controller.statusLabel.stringValue.lowercased().contains("up to date")
                  && !controller.statusLabel.stringValue.contains("已是最新"),
                  "About asserts freshness without a check: \(controller.statusLabel.stringValue)")
        try check(idleChecker.lastCheckDate == nil, "A fresh checker started with a timestamp")
        let initialLayout = layout(controller)
        try assertAboutLayout(controller)
        print(String(data: try JSONSerialization.data(withJSONObject: ["about_layout": initialLayout.json]), encoding: .utf8)!)
        // Both appearances get the same primary/secondary relationship: the
        // check button is the window's default button, close is not.
        try check(controller.checkButton.bezelStyle == .rounded && controller.closeButton.bezelStyle == .rounded,
                  "About buttons lost their rounded bezel")
        try check(controller.window?.defaultButtonCell === controller.checkButton.cell,
                  "Check for Updates is not the default button")
        try check(controller.window?.defaultButtonCell !== controller.closeButton.cell,
                  "Close became the default button")
        if let versionField = descendants(controller.window!.contentView!, of: NSTextField.self)
            .first(where: { $0.accessibilityIdentifier() == "about-current-version" }) {
            let expectedVersion = String(format: SettingsLocalization.text("updates.current-version"), "1.0.10")
            try check(versionField.stringValue == expectedVersion,
                      "Version line is not neutral: \(versionField.stringValue)")
            try check(!versionField.stringValue.contains("已安装") && !versionField.stringValue.contains("Installed"),
                      "Version line still says installed: \(versionField.stringValue)")
        } else {
            throw Failure(message: "About is missing about-current-version")
        }
        for identifier in ["about-current-version", "about-update-status", "about-project-link",
                           "about-release-notes-link", "about-license-link", "about-copyright"] {
            try check(descendants(controller.window!.contentView!, of: NSView.self)
                .contains { $0.accessibilityIdentifier() == identifier }, "About is missing \(identifier)")
        }

        // 2. Checking: inline copy and a disabled button while the request runs.
        try reply(feed: [FeedItem()], delay: 1.2)
        let checkingChecker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session,
                                                     feedURL: feedURL, defaults: freshDefaults())
        let checkingController = BlinkClipAboutWindowController(checker: checkingChecker, sparkleCheck: {})
        let inFlight = Task { await checkingChecker.check(force: true) }
        try await Task.sleep(for: .milliseconds(120))
        try check(checkingController.statusLabel.stringValue == SettingsLocalization.text("updates.checking"),
                  "Checking is not announced inline: \(checkingController.statusLabel.stringValue)")
        try check(!checkingController.checkButton.isEnabled, "Check button stays enabled while checking")
        try assertAboutLayout(checkingController)
        await inFlight.value

        // 3. A completed check shows a timestamp, not "you're up to date".
        let fixed = Date(timeIntervalSince1970: 1_760_000_000)
        try reply(feed: [FeedItem()])
        let aboutChecker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session,
                                                  feedURL: feedURL, defaults: aboutDefaults)
        await aboutChecker.check(force: true, now: fixed)
        let checkedController = BlinkClipAboutWindowController(checker: aboutChecker, sparkleCheck: { sparkleChecks += 1 })
        let availableCopy = String(format: SettingsLocalization.text("updates.available-format"),
                                   "1.0.11", BlinkClipUpdateChecker.timeText(fixed))
        try check(checkedController.statusLabel.stringValue == availableCopy,
                  "Available copy is not version + time: \(checkedController.statusLabel.stringValue)")
        try check(checkedController.statusLabel.stringValue.contains("1.0.11"), "About omitted the newer version: \(checkedController.statusLabel.stringValue)")
        try check(checkedController.statusLabel.textColor == .secondaryLabelColor, "Status line is not secondary colour")
        try check(statusIsAboveButtons(checkedController), "Status line is not above the buttons")
        try assertAboutLayout(checkedController)
        checkedController.checkButton.performClick(nil)
        try check(sparkleChecks == 1, "Check button did not start Sparkle's update flow")
        for _ in 0..<100 where aboutChecker.lastCheckDate == fixed {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard case .available = aboutChecker.state else { throw Failure(message: "Check button did not refresh the appcast summary") }
        try check(aboutChecker.lastCheckDate != nil, "The clicked check left no timestamp")
        try check(aboutChecker.lastCheckDate != fixed,
                  "The clicked check reused the seeded timestamp instead of recording a completion")
        let recordedBeforeFailure = aboutChecker.lastCheckDate

        // 4. Failures keep the gentle copy, never a status code, and do not
        // move the "last checked" timestamp (no answer was received).
        let failureChecker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session,
                                                    feedURL: feedURL, defaults: aboutDefaults)
        try reply(feed: [FeedItem()], status: 403)
        await failureChecker.check(force: true, now: fixed.addingTimeInterval(60))
        let failureController = BlinkClipAboutWindowController(checker: failureChecker, sparkleCheck: {})
        try check(failureController.statusLabel.stringValue == gentle, "About does not show the gentle failure copy")
        try check(failureController.statusLabel.textColor != .systemRed, "About paints the failure red")
        try check(!failureController.statusLabel.stringValue.contains("403"), "About shows the status code")
        try check(statusIsAboveButtons(failureController), "Status line moved into the body")
        try check(failureChecker.lastCheckDate == recordedBeforeFailure,
                  "A failed check moved the last-checked timestamp")
        try check(failureChecker.lastDiagnostic?.contains("403") == true, "A failed check left no diagnostic")
        try assertAboutLayout(failureController)

        // 5. Up to date: timestamp only, persisted across a relaunch.
        try reply(feed: [FeedItem()])
        let currentChecker = BlinkClipUpdateChecker(currentVersion: "1.0.11", session: session,
                                                    feedURL: feedURL, defaults: aboutDefaults)
        await currentChecker.check(force: true, now: fixed)
        let currentController = BlinkClipAboutWindowController(checker: currentChecker, sparkleCheck: {})
        try check(currentController.statusLabel.stringValue == lastCheckedText(fixed),
                  "Up-to-date status is not a timestamp: \(currentController.statusLabel.stringValue)")
        try check(!currentController.statusLabel.stringValue.lowercased().contains("up to date")
                  && !currentController.statusLabel.stringValue.contains("已是最新"),
                  "About repeats Sparkle's no-update sentence: \(currentController.statusLabel.stringValue)")
        try assertAboutLayout(currentController)
        try check(aboutDefaults.object(forKey: BlinkClipUpdateChecker.lastCheckDateKey) as? Date == fixed,
                  "updates.lastCheckDate was not persisted")
        let relaunched = BlinkClipUpdateChecker(currentVersion: "1.0.11", session: session,
                                                feedURL: feedURL, defaults: aboutDefaults)
        try check(relaunched.lastCheckDate == fixed, "A new checker lost the persisted timestamp")
        let relaunchedController = BlinkClipAboutWindowController(checker: relaunched, sparkleCheck: {})
        try check(relaunchedController.statusLabel.stringValue == lastCheckedText(fixed),
                  "A reopened About window does not show the persisted time: \(relaunchedController.statusLabel.stringValue)")
        try assertAboutLayout(relaunchedController)

        // 6. A feed that offers nothing runnable is a completed check too.
        let tooNewDefaults = freshDefaults()
        let tooNewChecker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session,
                                                   feedURL: feedURL, defaults: tooNewDefaults)
        try reply(feed: [FeedItem(version: "1.0.12", minimumSystem: "99.0")])
        await tooNewChecker.check(force: true, now: fixed.addingTimeInterval(30))
        let tooNewController = BlinkClipAboutWindowController(checker: tooNewChecker, sparkleCheck: {})
        try check(tooNewController.statusLabel.stringValue == lastCheckedText(fixed.addingTimeInterval(30)),
                  "An unrunnable feed did not record its check time: \(tooNewController.statusLabel.stringValue)")

        // ── throttle and concurrency ────────────────────────────────────────
        try reply(feed: [FeedItem()])
        let throttled = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        let date = Date(timeIntervalSince1970: 1000)
        await throttled.check(now: date)
        await throttled.check(now: date.addingTimeInterval(1))
        try check(UpdateProtocol.capturedRequests.count == 1, "Automatic checks were not throttled")
        await throttled.check(now: date.addingTimeInterval(6 * 60 * 60))
        try check(UpdateProtocol.capturedRequests.count == 2, "Throttle never expires")
        await throttled.check(force: true, now: date.addingTimeInterval(6 * 60 * 60 + 1))
        try check(UpdateProtocol.capturedRequests.count == 3, "Manual check did not bypass throttle")

        try reply(feed: [FeedItem()])
        let concurrent = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session, feedURL: feedURL)
        async let first: Void = concurrent.check(force: true)
        async let second: Void = concurrent.check(force: true)
        _ = await (first, second)
        try check(UpdateProtocol.capturedRequests.count == 1, "Concurrent requests were duplicated")
        try reply(feed: [FeedItem()])
        let unknown = BlinkClipUpdateChecker(currentVersion: "unknown", session: session, feedURL: feedURL)
        await unknown.check(force: true)
        try check(UpdateProtocol.capturedRequests.isEmpty, "Invalid installed version reached the network")
        guard case .failed = unknown.state else { throw Failure(message: "Invalid installed version reported success") }
    }

    /// The status line belongs directly above the action row, in window coordinates.
    @MainActor static func statusIsAboveButtons(_ controller: BlinkClipAboutWindowController) -> Bool {
        guard let content = controller.window?.contentView else { return false }
        content.layoutSubtreeIfNeeded()
        let status = controller.statusLabel.convert(controller.statusLabel.bounds, to: content)
        let button = controller.checkButton.convert(controller.checkButton.bounds, to: content)
        return status.minY >= button.maxY
    }

    @MainActor static func descendants<T: NSView>(_ view: NSView, of type: T.Type) -> [T] {
        let children = view.subviews.flatMap { descendants($0, of: type) }
        return ((view as? T).map { [$0] } ?? []) + children
    }

    struct RGB: Equatable {
        let red: Int
        let green: Int
        let blue: Int
        var json: [String: Int] { ["r": red, "g": green, "b": blue] }
    }

    /// The fill colour under a button's left third, away from the title glyphs.
    @MainActor static func fillColor(_ bitmap: NSBitmapImageRep, of view: NSView, in frameView: NSView) -> RGB {
        let point = view.convert(NSPoint(x: view.bounds.width * 0.25, y: view.bounds.height * 0.5), to: frameView)
        let scaleX = CGFloat(bitmap.pixelsWide) / frameView.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / frameView.bounds.height
        let x = Int((point.x * scaleX).rounded())
        let y = bitmap.pixelsHigh - Int((point.y * scaleY).rounded()) - 1
        guard let data = bitmap.bitmapData, x >= 0, y >= 0,
              x < bitmap.pixelsWide, y < bitmap.pixelsHigh else {
            return RGB(red: -1, green: -1, blue: -1)
        }
        // The cached bitmap is 8-bit RGBA with the origin at the top left.
        let offset = y * bitmap.bytesPerRow + x * 4
        return RGB(red: Int(data[offset]), green: Int(data[offset + 1]), blue: Int(data[offset + 2]))
    }

    struct PreparedAbout {
        let appearance: String
        let scenario: String
        let controller: BlinkClipAboutWindowController
    }

    /// Runs every scenario's check before the app event loop starts, so the
    /// timer only has to make each window key, snapshot it and sample the
    /// button fills. Copy and layout are asserted here, where async work is
    /// allowed.
    @MainActor static func prepareRenders(session: URLSession) async throws -> [PreparedAbout] {
        let fixed = Date(timeIntervalSince1970: 1_760_000_000)
        struct Scenario {
            let name: String
            let installed: String
            let kind: String
            let items: [FeedItem]
            let failure: Error?
        }
        let scenarios = [
            Scenario(name: "initial", installed: "1.0.11", kind: "initial", items: [], failure: nil),
            Scenario(name: "checking", installed: "1.0.11", kind: "checking", items: [FeedItem()], failure: nil),
            Scenario(name: "latest", installed: "1.0.11", kind: "checked", items: [FeedItem()], failure: nil),
            Scenario(name: "available", installed: "1.0.10", kind: "checked", items: [FeedItem()], failure: nil),
            Scenario(name: "offline", installed: "1.0.11", kind: "checked", items: [], failure: URLError(.notConnectedToInternet))
        ]
        let gentle = SettingsLocalization.text("updates.unreachable")
        var prepared: [PreparedAbout] = []
        for appearance in ["light", "dark"] {
            let name = appearance == "light" ? NSAppearance.Name.aqua : .darkAqua
            NSApp.appearance = NSAppearance(named: name)
            for scenario in scenarios {
                let checker = BlinkClipUpdateChecker(currentVersion: scenario.installed, session: session,
                                                     feedURL: feedURL, defaults: freshDefaults())
                switch scenario.kind {
                case "checking":
                    // Keep the request in flight long enough to photograph it.
                    UpdateProtocol.reply(appcast(scenario.items), status: 200, failure: nil, delay: 30)
                case "checked":
                    UpdateProtocol.reply(appcast(scenario.items), status: 200, failure: scenario.failure)
                    await checker.check(force: true, now: fixed)
                default:
                    break
                }
                let controller = BlinkClipAboutWindowController(checker: checker, sparkleCheck: {})
                if scenario.kind == "checking" {
                    let inFlight = Task { await checker.check(force: true) }
                    try await Task.sleep(for: .milliseconds(250))
                    try check(controller.statusLabel.stringValue == SettingsLocalization.text("updates.checking"),
                              "\(appearance)/checking is not announced: \(controller.statusLabel.stringValue)")
                    try check(!controller.checkButton.isEnabled, "\(appearance)/checking leaves the button enabled")
                    _ = inFlight
                }
                switch scenario.kind {
                case "initial":
                    try check(controller.statusLabel.stringValue == neverCheckedText,
                              "\(appearance)/initial claims a result: \(controller.statusLabel.stringValue)")
                case "checked":
                    if scenario.failure != nil {
                        try check(controller.statusLabel.stringValue == gentle,
                                  "\(appearance)/offline is not gentle: \(controller.statusLabel.stringValue)")
                    } else if scenario.name == "latest" {
                        try check(controller.statusLabel.stringValue == lastCheckedText(fixed),
                                  "\(appearance)/latest is not a timestamp: \(controller.statusLabel.stringValue)")
                    } else {
                        let expected = String(format: SettingsLocalization.text("updates.available-format"),
                                              "1.0.11", BlinkClipUpdateChecker.timeText(fixed))
                        try check(controller.statusLabel.stringValue == expected,
                                  "\(appearance)/available lost the timestamp: \(controller.statusLabel.stringValue)")
                    }
                default:
                    break
                }
                try assertAboutLayout(controller)
                prepared.append(PreparedAbout(appearance: appearance, scenario: scenario.name,
                                              controller: controller))
            }
        }
        return prepared
    }

    /// Synchronous, key-window snapshot pass: in a key window the default
    /// button keeps its emphasis, so the two appearances can be compared for
    /// the same primary/secondary weighting.
    @MainActor static func snapshot(_ prepared: [PreparedAbout], into directory: URL) throws -> Int {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written = 0
        var weights: [[String: Any]] = []
        for item in prepared {
            let name = item.appearance == "light" ? NSAppearance.Name.aqua : .darkAqua
            NSApp.appearance = NSAppearance(named: name)
            guard let window = item.controller.window, let frameView = window.contentView?.superview else {
                throw Failure(message: "About window has no content")
            }
            window.appearance = NSAppearance(named: name)
            window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
            window.makeKeyAndOrderFront(nil)
            // Ask for activation once a window is on screen, then let the AppKit
            // loop deliver it: an accessory app with no visible window has
            // nothing to activate.
            NSApp.activate(ignoringOtherApps: true)
            for _ in 0..<40 where !window.isKeyWindow {
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            }
            frameView.layoutSubtreeIfNeeded()
            guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else {
                throw Failure(message: "no about bitmap")
            }
            frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
            // A key window is the only place AppKit draws the default button's
            // emphasis; without a window server (headless CI) the renders are
            // still written, but the weight comparison is not asserted.
            if window.isKeyWindow {
                let checkFill = fillColor(bitmap, of: item.controller.checkButton, in: frameView)
                let closeFill = fillColor(bitmap, of: item.controller.closeButton, in: frameView)
                try check(checkFill != closeFill,
                          "\(item.appearance)/\(item.scenario): primary and secondary buttons render identically (\(checkFill))")
                weights.append(["appearance": item.appearance, "state": item.scenario,
                                "check": checkFill.json, "close": closeFill.json,
                                "layout": layout(item.controller).json])
            } else {
                print("{\"warning\":\"\(item.appearance)/\(item.scenario): About window is not key; weight not measured\"}")
            }
            let url = directory.appendingPathComponent("about-\(item.appearance)-\(item.scenario).png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
            written += 1
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        try check(written == 10, "expected ten About renders, wrote \(written)")
        print(String(data: try JSONSerialization.data(withJSONObject: ["button_weights": weights], options: [.sortedKeys]), encoding: .utf8)!)
        return written
    }
}
