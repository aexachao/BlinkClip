import AppKit
import Foundation
import SwiftUI
import BlinkClipCore

/// 设置窗口是无边框离屏窗口：保持 648×600 的出货尺寸，不吸附到任何屏幕。
@MainActor private final class AboutOffscreenWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

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

    // MARK: - 关于页（设置窗口内容区里的第七页）

    /// 关于不再是独立窗口：页面在生产 `ReplicaSettingsView` 里，几何与语义都从
    /// 一个真实设置窗口的无障碍树里量，文案则从页面复用的 `BlinkClipAboutModel`
    /// 读。宿主窗口离屏摆放，不动用户的窗口位置。
    struct AboutPageHost {
        let window: NSWindow
        let hosting: NSView
        let model: BlinkClipAboutModel
        let fixture: URL
        var frameView: NSView? { window.contentView?.superview }
    }

    /// 页面承诺的几何（屏幕坐标，y 向上）：状态行压在唯一主按钮上方 ≤12pt、
    /// 两者同一条中轴；状态行在链接之上，链接在许可之上。
    struct AboutPageLayout {
        let statusButtonGap: CGFloat
        let statusButtonAxisOffset: CGFloat
        let actionButtonCount: Int
        let actionButtonIDs: [String]
        let pageTopGap: CGFloat
        let cardTopPadding: CGFloat
        let cardBottomPadding: CGFloat
        var debugDescription: String = ""

        var json: [String: Any] {
            ["status_button_gap": Double(statusButtonGap),
             "status_button_axis_offset": Double(statusButtonAxisOffset),
             "action_button_count": actionButtonCount,
             "action_button_ids": actionButtonIDs,
             "page_top_gap": Double(pageTopGap),
             "card_top_padding": Double(cardTopPadding),
             "card_bottom_padding": Double(cardBottomPadding)]
        }
    }

    @MainActor static func accessibilityTree(_ element: Any) -> [NSObject] {
        var seen = Set<ObjectIdentifier>()
        func visit(_ value: Any) -> [NSObject] {
            guard let node = value as? NSObject, seen.insert(ObjectIdentifier(node)).inserted else { return [] }
            let selector = NSSelectorFromString("accessibilityChildren")
            let children = node.responds(to: selector)
                ? (node.perform(selector)?.takeUnretainedValue() as? [Any] ?? []) : []
            let legacy = node.accessibilityAttributeValue(.children) as? [Any] ?? []
            let views = (node as? NSView)?.subviews ?? []
            return [node] + (children + legacy + views).flatMap(visit)
        }
        return visit(element)
    }

    @MainActor static func axID(_ element: NSObject) -> String? {
        let selector = NSSelectorFromString("accessibilityIdentifier")
        return (element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() as? String : nil)
            ?? element.accessibilityAttributeValue(.identifier) as? String
    }

    @MainActor static func axRole(_ element: NSObject) -> String {
        let selector = NSSelectorFromString("accessibilityRole")
        if element.responds(to: selector),
           let role = element.perform(selector)?.takeUnretainedValue() as? String { return role }
        return element.accessibilityAttributeValue(.role) as? String ?? ""
    }

    @MainActor static func axText(_ element: NSObject) -> String {
        for name in ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"] {
            let selector = NSSelectorFromString(name)
            if element.responds(to: selector),
               let value = element.perform(selector)?.takeUnretainedValue() as? String,
               !value.isEmpty { return value }
        }
        for attribute in [NSAccessibility.Attribute.value, .title, .description] {
            if let value = element.accessibilityAttributeValue(attribute) as? String, !value.isEmpty { return value }
        }
        return ""
    }

    @MainActor static func axEnabled(_ element: NSObject) -> Bool? {
        if let value = element.accessibilityAttributeValue(.enabled) as? Bool { return value }
        if let number = element.accessibilityAttributeValue(.enabled) as? NSNumber { return number.boolValue }
        let selector = NSSelectorFromString("accessibilityEnabled")
        guard element.responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(element.method(for: selector), to: Getter.self)(element, selector)
    }

    @MainActor static func axFrame(_ element: NSObject) -> NSRect {
        let selector = NSSelectorFromString("accessibilityFrame")
        if element.responds(to: selector) {
            typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
            return unsafeBitCast(element.method(for: selector), to: Getter.self)(element, selector)
        }
        let point = (element.accessibilityAttributeValue(.position) as? NSValue)?.pointValue ?? .zero
        let size = (element.accessibilityAttributeValue(.size) as? NSValue)?.sizeValue ?? .zero
        return NSRect(origin: point, size: size)
    }

    /// 离屏设置窗口 + 生产 `ReplicaSettingsView`，初始页就是关于页。
    @MainActor static func makeAboutPageHost(_ model: BlinkClipAboutModel,
                                             appearance: NSAppearance.Name) async throws -> AboutPageHost {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("blinkclip-about-page-\(UUID().uuidString)", isDirectory: true)
        let store = try ClipboardStore(directoryURL: fixture)
        let state = ReplicaUIState(store: store)
        let permissions = PermissionStatusModel(readAccessibility: { true }, readPostEvents: { true },
                                                readScreenRecording: { true },
                                                requestScreenAccess: {}, requestAccessibilityAccess: {})
        NSApp.appearance = NSAppearance(named: appearance)
        let hosting = NSHostingView(rootView: ReplicaSettingsView(
            state: state, initialTab: SettingsAboutPane.tabIndex,
            permissionModel: permissions, aboutModel: model)
            .background(Color(nsColor: .windowBackgroundColor)))
        let window = AboutOffscreenWindow(
            contentRect: NSRect(x: -5000, y: -5000, width: 648, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.setFrame(NSRect(x: -5000, y: -5000, width: 648, height: 600), display: false)
        window.contentView = hosting
        window.orderFront(nil)
        await pause()
        hosting.layoutSubtreeIfNeeded()
        return AboutPageHost(window: window, hosting: hosting, model: model, fixture: fixture)
    }

    @MainActor static func pageNode(_ tree: [NSObject], _ identifier: String) -> NSObject? {
        tree.first { axID($0) == identifier }
    }

    /// 页面几何 + 结构：单按钮、状态行与按钮 ≤12pt 同轴、状态在链接之前、
    /// 无关闭按钮、页顶 16pt、卡片内容垂直居中。
    @MainActor static func aboutPageLayout(_ host: AboutPageHost) throws -> AboutPageLayout {
        host.hosting.layoutSubtreeIfNeeded()
        let tree = accessibilityTree(host.hosting)
        func frame(_ identifier: String) throws -> NSRect {
            guard let node = pageNode(tree, identifier) else {
                throw Failure(message: "the About page is missing \(identifier)")
            }
            let rect = axFrame(node)
            guard rect.width > 0.5, rect.height > 0.5 else {
                throw Failure(message: "the About page element \(identifier) has no frame")
            }
            return rect
        }
        // 「关闭」按钮已随独立窗口一起删掉：关于页上不得再有任何认领它的控件。
        try check(!tree.contains { axID($0) == "about-close" },
                  "the removed Close button is back on the About page")
        let actionButtons = tree.filter { axRole($0) == "AXButton" && (axID($0) ?? "").hasPrefix("about-") }
        let icon = try frame("about-application-icon")
        let name = try frame("about-product-name")
        let version = try frame("about-current-version")
        let description = try frame("about-description")
        let status = try frame("about-update-status")
        let button = try frame("about-check-updates")
        let project = try frame("about-project-link")
        let releases = try frame("about-release-notes-link")
        let copyright = try frame("about-copyright")
        let license = try frame("about-license-link")
        let card = try frame("settings.card")
        let contentTop = host.window.convertPoint(toScreen: NSPoint(x: 0, y: host.window.contentLayoutRect.maxY)).y
        try check(icon.height >= 90 && icon.height <= 100,
                  "the app icon is not about 96pt: \(icon.height)")
        // 顺序：图标 → 名称 → 版本 → 说明 → 状态 → 按钮 → 链接 → 版权/许可。
        try check(status.maxY <= description.minY,
                  "the status line is not below the product description: \(status) vs \(description)")
        try check(project.maxY <= status.minY,
                  "the status line is not above the links (status + button must come first): \(status) vs \(project)")
        try check(license.maxY <= min(project.minY, releases.minY),
                  "the license row is not below the link row: \(license) vs \(project)")
        try check(copyright.minY < license.maxY || abs(copyright.midY - license.midY) <= 2,
                  "the copyright is not on the licence row: \(copyright) vs \(license)")
        // 页顶 16pt（设置页统一节奏，关于页不另写一套）。
        let pageTopGap = contentTop - card.maxY
        try check(abs(pageTopGap - SettingsPageMetrics.topInset) <= 0.5,
                  "the About page does not start \(SettingsPageMetrics.topInset)pt from the top: \(pageTopGap)")
        // 卡片内容垂直居中：卡顶 → 图标框顶 == 版权框底 → 卡底（≤0.5pt）。
        let cardTopPadding = card.maxY - icon.maxY
        let cardBottomPadding = copyright.minY - card.minY
        try check(abs(cardTopPadding - cardBottomPadding) <= 0.5,
                  "the About card content is not vertically centred: top \(cardTopPadding) bottom \(cardBottomPadding)")
        return AboutPageLayout(statusButtonGap: status.minY - button.maxY,
                               statusButtonAxisOffset: status.midX - button.midX,
                               actionButtonCount: actionButtons.count,
                               actionButtonIDs: actionButtons.compactMap { axID($0) },
                               pageTopGap: pageTopGap,
                               cardTopPadding: cardTopPadding,
                               cardBottomPadding: cardBottomPadding)
    }

    @MainActor static func assertAboutPageLayout(_ host: AboutPageHost) throws {
        let measured = try aboutPageLayout(host)
        try check(measured.actionButtonCount == 1,
                  "the About page shows \(measured.actionButtonCount) action buttons \(measured.actionButtonIDs), expected only Check for Updates")
        try check(measured.actionButtonIDs == ["about-check-updates"],
                  "the About page action button is not the Check for Updates button: \(measured.actionButtonIDs)")
        try check(measured.statusButtonGap >= 4 && measured.statusButtonGap <= 12,
                  "the status line is not within 12pt above the button: \(measured.statusButtonGap)")
        try check(abs(measured.statusButtonAxisOffset) <= 1,
                  "the status line is not on the button's centred axis: \(measured.statusButtonAxisOffset)")
        let tree = accessibilityTree(host.hosting)
        for (identifier, expected) in [
            ("about-product-name", ReplicaBrand.name),
            ("about-current-version", String(format: SettingsLocalization.text("updates.current-version"),
                                              host.model.checker.currentVersion)),
            ("about-description", SettingsLocalization.text("updates.description")),
            ("about-update-status", host.model.statusText),
            ("about-copyright", SettingsLocalization.text("updates.copyright")),
            ("about-project-link", SettingsLocalization.text("updates.link-project")),
            ("about-release-notes-link", SettingsLocalization.text("updates.link-releases")),
            ("about-license-link", SettingsLocalization.text("updates.link-license")),
        ] {
            guard let node = pageNode(tree, identifier) else {
                throw Failure(message: "the About page is missing \(identifier)")
            }
            try check(axText(node) == expected,
                      "the About page \(identifier) reads \(axText(node)), expected \(expected)")
        }
        if let button = tree.first(where: { axID($0) == "about-check-updates" }) {
            try check(axText(button) == SettingsLocalization.text("updates.check"),
                      "the About page button reads \(axText(button))")
        }
    }

    /// A completed check reports the timestamp only. Sparkle's own
    /// user-initiated alert carries the "you're up to date" sentence; the inline
    /// line must not repeat it (and Sparkle 2.10.1 has no public hook to
    /// suppress that alert).
    @MainActor static func assertUpToDateAbout(_ checker: BlinkClipUpdateChecker, installed: String) throws {
        let model = BlinkClipAboutModel(checker: checker, sparkleCheck: {})
        guard let checkedAt = checker.lastCheckDate else {
            throw Failure(message: "the About page has no completed-check timestamp for \(installed)")
        }
        let expected = lastCheckedText(checkedAt)
        try check(model.statusText == expected,
                  "the About page does not report the check time for \(installed): \(model.statusText)")
        try check(!model.statusText.lowercased().contains("up to date")
                  && !model.statusText.contains("已是最新"),
                  "the About page repeats Sparkle's no-update sentence: \(model.statusText)")
    }

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
                let model = BlinkClipAboutModel(checker: comparison, sparkleCheck: {})
                try check(model.statusText.contains(update.version),
                          "the About page does not mention the live version \(update.version): \(model.statusText)")
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
            // SwiftUI 的文字/链接节点要经过增强的无障碍接口才会出现在 AX 树里，
            // 关于页的单按钮、状态行几何都从这棵树里量。
            NSApp.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
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
                let model = BlinkClipAboutModel(checker: checker, sparkleCheck: {})
                let host = try await makeAboutPageHost(model, appearance: .aqua)
                host.window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
                host.window.makeKeyAndOrderFront(nil)
                Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in NSApp.terminate(nil) }
                print("PREVIEW_READY")
                fflush(stdout)
                app.run()
                withExtendedLifetime(host) { }
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
            let summary = "{\"passed\":true,\"version_comparison\":true,\"appcast_parsing\":true,\"gentle_failures\":true,\"throttle_and_retry\":true,\"concurrent_checks\":true,\"about_page\":true,\"about_layout\":true,\"last_check_timestamp\":true}"
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

        // ── 关于页（设置窗口内容区里的第七页）──────────────────────────────
        // 关于不再是独立窗口：页面住在一个真实的设置窗口里，断言走无障碍树
        // （单按钮 / 状态行 ≤12pt 同轴 / 状态行在链接之前 / 无关闭按钮）。
        // 1. 还没检查过：不报「已是最新」，文案中性，状态行属于动作块。
        let aboutDefaults = freshDefaults()
        var sparkleChecks = 0
        let idleChecker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session,
                                                 feedURL: feedURL, defaults: aboutDefaults)
        let idleModel = BlinkClipAboutModel(checker: idleChecker, sparkleCheck: { sparkleChecks += 1 })
        let idleHost = try await makeAboutPageHost(idleModel, appearance: .aqua)
        try check(idleModel.statusText == neverCheckedText,
                  "the About page claims a result before any check: \(idleModel.statusText)")
        try check(!idleModel.statusText.lowercased().contains("up to date")
                  && !idleModel.statusText.contains("已是最新"),
                  "the About page asserts freshness without a check: \(idleModel.statusText)")
        try check(!idleModel.isChecking, "a fresh About page starts in the checking state")
        try check(idleChecker.lastCheckDate == nil, "A fresh checker started with a timestamp")
        try assertAboutPageLayout(idleHost)
        print(String(data: try JSONSerialization.data(withJSONObject: ["about_page_layout": (try aboutPageLayout(idleHost)).json]), encoding: .utf8)!)
        idleHost.window.orderOut(nil)
        idleHost.window.contentView = nil
        idleHost.window.close()

        // 2. 检查中：内联文案 + 主按钮置灰。
        try reply(feed: [FeedItem()], delay: 1.2)
        let checkingChecker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session,
                                                     feedURL: feedURL, defaults: freshDefaults())
        var checkingSparkleChecks = 0
        let checkingModel = BlinkClipAboutModel(checker: checkingChecker, sparkleCheck: { checkingSparkleChecks += 1 })
        let checkingHost = try await makeAboutPageHost(checkingModel, appearance: .aqua)
        let inFlight = Task { await checkingChecker.check(force: true) }
        try await Task.sleep(for: .milliseconds(150))
        try check(checkingModel.statusText == SettingsLocalization.text("updates.checking"),
                  "checking is not announced inline: \(checkingModel.statusText)")
        try check(checkingModel.isChecking, "the model does not report the in-flight check")
        try assertAboutPageLayout(checkingHost)
        // 「检查中置灰」不只是颜色：按下必须无效（页面用 `.disabled(aboutModel.isChecking)`
        // 把按钮真的禁用，而不是只换个底色）。
        if let button = pageNode(accessibilityTree(checkingHost.hosting), "about-check-updates") {
            let selector = NSSelectorFromString("accessibilityPerformPress")
            if button.responds(to: selector) {
                typealias Press = @convention(c) (AnyObject, Selector) -> Bool
                _ = unsafeBitCast(button.method(for: selector), to: Press.self)(button, selector)
            }
        }
        try check(checkingSparkleChecks == 0,
                  "a disabled (checking) Check for Updates button still started Sparkle's update flow")
        checkingHost.window.orderOut(nil)
        checkingHost.window.contentView = nil
        checkingHost.window.close()
        await inFlight.value
        try reply(feed: [FeedItem()])

        // 3. 检查完成：时间戳（不是「已是最新」），且「检查更新」按钮真的会改写状态行。
        let fixed = Date(timeIntervalSince1970: 1_760_000_000)
        let aboutChecker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session,
                                                  feedURL: feedURL, defaults: aboutDefaults)
        await aboutChecker.check(force: true, now: fixed)
        let checkedModel = BlinkClipAboutModel(checker: aboutChecker, sparkleCheck: { sparkleChecks += 1 })
        let availableCopy = String(format: SettingsLocalization.text("updates.available-format"),
                                   "1.0.11", BlinkClipUpdateChecker.timeText(fixed))
        try check(checkedModel.statusText == availableCopy,
                  "available copy is not version + time: \(checkedModel.statusText)")
        try check(checkedModel.statusText.contains("1.0.11"),
                  "the About page omitted the newer version: \(checkedModel.statusText)")
        let checkedHost = try await makeAboutPageHost(checkedModel, appearance: .aqua)
        try assertAboutPageLayout(checkedHost)
        // 按页面上的那颗按钮（AX press，不是直接调模型）：状态行变化说明接线在。
        let beforeClick = checkedModel.statusText
        guard let checkButton = pageNode(accessibilityTree(checkedHost.hosting), "about-check-updates") else {
            throw Failure(message: "the About page has no Check for Updates button")
        }
        let pressSelector = NSSelectorFromString("accessibilityPerformPress")
        guard checkButton.responds(to: pressSelector) else {
            throw Failure(message: "the About page button cannot be pressed through accessibility")
        }
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        let pressed = unsafeBitCast(checkButton.method(for: pressSelector), to: Press.self)(checkButton, pressSelector)
        try check(pressed, "pressing the About page button through accessibility failed")
        try check(sparkleChecks == 1, "the About page button did not start Sparkle's update flow")
        var changed = false
        for _ in 0..<150 {
            if checkedModel.statusText != beforeClick { changed = true; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try check(changed, "pressing Check for Updates left the status line unchanged: \(checkedModel.statusText)")
        try check(checkedModel.statusText == SettingsLocalization.text("updates.checking")
                  || checkedModel.statusText == lastCheckedText(fixed)
                  || checkedModel.statusText.contains("1.0.11"),
                  "the status line changed to an unexpected copy: \(checkedModel.statusText)")
        for _ in 0..<150 where aboutChecker.lastCheckDate == fixed {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard case .available = aboutChecker.state else {
            throw Failure(message: "the About page button did not refresh the appcast summary")
        }
        try check(aboutChecker.lastCheckDate != nil, "the clicked check left no timestamp")
        try check(aboutChecker.lastCheckDate != fixed,
                  "the clicked check reused the seeded timestamp instead of recording a completion")
        let recordedBeforeFailure = aboutChecker.lastCheckDate
        checkedHost.window.orderOut(nil)
        checkedHost.window.contentView = nil
        checkedHost.window.close()

        // 4. 失败：温和文案、不染色、不把状态码漏到页面，也不移动「上次检查」。
        let failureChecker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session,
                                                    feedURL: feedURL, defaults: aboutDefaults)
        try reply(feed: [FeedItem()], status: 403)
        await failureChecker.check(force: true, now: fixed.addingTimeInterval(60))
        let failureModel = BlinkClipAboutModel(checker: failureChecker, sparkleCheck: {})
        try check(failureModel.statusText == gentle, "the About page does not show the gentle failure copy")
        try check(!failureModel.statusText.contains("403"), "the About page shows the status code")
        try check(failureChecker.lastCheckDate == recordedBeforeFailure,
                  "a failed check moved the last-checked timestamp")
        try check(failureChecker.lastDiagnostic?.contains("403") == true, "a failed check left no diagnostic")
        let failureHost = try await makeAboutPageHost(failureModel, appearance: .aqua)
        try assertAboutPageLayout(failureHost)
        failureHost.window.orderOut(nil)
        failureHost.window.contentView = nil
        failureHost.window.close()

        // 5. 已是最新：只报时间戳，并且跨一次「重开设置」仍在。
        try reply(feed: [FeedItem()])
        let currentChecker = BlinkClipUpdateChecker(currentVersion: "1.0.11", session: session,
                                                    feedURL: feedURL, defaults: aboutDefaults)
        await currentChecker.check(force: true, now: fixed)
        let currentModel = BlinkClipAboutModel(checker: currentChecker, sparkleCheck: {})
        try check(currentModel.statusText == lastCheckedText(fixed),
                  "up-to-date status is not a timestamp: \(currentModel.statusText)")
        try check(!currentModel.statusText.lowercased().contains("up to date")
                  && !currentModel.statusText.contains("已是最新"),
                  "the About page repeats Sparkle's no-update sentence: \(currentModel.statusText)")
        let currentHost = try await makeAboutPageHost(currentModel, appearance: .aqua)
        try assertAboutPageLayout(currentHost)
        currentHost.window.orderOut(nil)
        currentHost.window.contentView = nil
        currentHost.window.close()
        try check(aboutDefaults.object(forKey: BlinkClipUpdateChecker.lastCheckDateKey) as? Date == fixed,
                  "updates.lastCheckDate was not persisted")
        let relaunched = BlinkClipUpdateChecker(currentVersion: "1.0.11", session: session,
                                                feedURL: feedURL, defaults: aboutDefaults)
        try check(relaunched.lastCheckDate == fixed, "A new checker lost the persisted timestamp")
        let relaunchedModel = BlinkClipAboutModel(checker: relaunched, sparkleCheck: {})
        try check(relaunchedModel.statusText == lastCheckedText(fixed),
                  "a reopened About page does not show the persisted time: \(relaunchedModel.statusText)")
        let relaunchedHost = try await makeAboutPageHost(relaunchedModel, appearance: .aqua)
        try assertAboutPageLayout(relaunchedHost)
        relaunchedHost.window.orderOut(nil)
        relaunchedHost.window.contentView = nil
        relaunchedHost.window.close()

        // 6. 提供了一个跑不起来的版本也算一次完成的检查。
        let tooNewDefaults = freshDefaults()
        let tooNewChecker = BlinkClipUpdateChecker(currentVersion: "1.0.10", session: session,
                                                   feedURL: feedURL, defaults: tooNewDefaults)
        try reply(feed: [FeedItem(version: "1.0.12", minimumSystem: "99.0")])
        await tooNewChecker.check(force: true, now: fixed.addingTimeInterval(30))
        let tooNewModel = BlinkClipAboutModel(checker: tooNewChecker, sparkleCheck: {})
        try check(tooNewModel.statusText == lastCheckedText(fixed.addingTimeInterval(30)),
                  "an unrunnable feed did not record its check time: \(tooNewModel.statusText)")

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

    /// 截图用的场景：每个场景一份独立 defaults + 一个真实设置窗口里的关于页。
    struct PreparedAbout {
        let appearance: String
        let scenario: String
        let host: AboutPageHost
    }

    /// Runs every scenario's check before the app event loop starts, so the
    /// timer only has to make each settings window key, snapshot it and sample
    /// the button emphasis. Copy and layout are asserted here, where async work
    /// is allowed.
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
                let model = BlinkClipAboutModel(checker: checker, sparkleCheck: {})
                if scenario.kind == "checking" {
                    let inFlight = Task { await checker.check(force: true) }
                    try await Task.sleep(for: .milliseconds(250))
                    try check(model.statusText == SettingsLocalization.text("updates.checking"),
                              "\(appearance)/checking is not announced: \(model.statusText)")
                    try check(model.isChecking, "\(appearance)/checking leaves the button enabled")
                    _ = inFlight
                }
                switch scenario.kind {
                case "initial":
                    try check(model.statusText == neverCheckedText,
                              "\(appearance)/initial claims a result: \(model.statusText)")
                case "checked":
                    if scenario.failure != nil {
                        try check(model.statusText == gentle,
                                  "\(appearance)/offline is not gentle: \(model.statusText)")
                    } else if scenario.name == "latest" {
                        try check(model.statusText == lastCheckedText(fixed),
                                  "\(appearance)/latest is not a timestamp: \(model.statusText)")
                    } else {
                        let expected = String(format: SettingsLocalization.text("updates.available-format"),
                                              "1.0.11", BlinkClipUpdateChecker.timeText(fixed))
                        try check(model.statusText == expected,
                                  "\(appearance)/available lost the timestamp: \(model.statusText)")
                    }
                default:
                    break
                }
                let host = try await makeAboutPageHost(model, appearance: name)
                try assertAboutPageLayout(host)
                prepared.append(PreparedAbout(appearance: appearance, scenario: scenario.name, host: host))
            }
        }
        return prepared
    }

    /// 数一个屏幕矩形里「明显是 accent 蓝」的像素：主按钮（`.borderedProminent`）
    /// 在 key window 里整块 accent 填充，普通按钮的灰白底一个也数不到；检查中
    /// 按钮是禁用的，AppKit 画成灰底，强调色为 0。
    @MainActor static func accentPixels(_ bitmap: NSBitmapImageRep, screenRect: NSRect,
                                        in frameView: NSView) -> Int {
        guard let window = frameView.window else { return -1 }
        let rect = frameView.convert(window.convertFromScreen(screenRect), from: nil)
        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, frameView.bounds.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, frameView.bounds.height)
        var count = 0
        var y = rect.minY + 2
        while y <= rect.maxY - 2 {
            var x = rect.minX + 2
            while x <= rect.maxX - 2 {
                let px = Int(x * scaleX)
                let py = bitmap.pixelsHigh - Int(y * scaleY) - 1
                if px >= 0, py >= 0, px < bitmap.pixelsWide, py < bitmap.pixelsHigh,
                   let color = bitmap.colorAt(x: px, y: py)?.usingColorSpace(.sRGB) {
                    let red = color.redComponent * 255, green = color.greenComponent * 255, blue = color.blueComponent * 255
                    if blue >= 120, blue - red >= 60, blue - green >= 40 { count += 1 }
                }
                x += 1
            }
            y += 1
        }
        return count
    }

    /// Synchronous, key-window snapshot pass: in a key window the prominent
    /// button keeps its accent fill, so the two appearances can be compared for
    /// the same weighting and a disabled (checking) button shows none.
    @MainActor static func snapshot(_ prepared: [PreparedAbout], into directory: URL) throws -> Int {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written = 0
        var weights: [[String: Any]] = []
        for item in prepared {
            let name = item.appearance == "light" ? NSAppearance.Name.aqua : .darkAqua
            NSApp.appearance = NSAppearance(named: name)
            let window = item.host.window
            guard let frameView = window.contentView?.superview else {
                throw Failure(message: "the About page host has no content")
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
                throw Failure(message: "no About page bitmap")
            }
            frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
            let tree = accessibilityTree(item.host.hosting)
            guard let buttonNode = pageNode(tree, "about-check-updates") else {
                throw Failure(message: "the About page has no Check for Updates button to sample")
            }
            let buttonRect = axFrame(buttonNode)
            let accent = window.isKeyWindow ? accentPixels(bitmap, screenRect: buttonRect, in: frameView) : -1
            // 可用状态：唯一主按钮必须是主按钮强调态（key window 里整块 accent 填充）；
            // 「检查中置灰」单独在循环后按同一外观的可用渲染对比（禁用时强调色被压暗）。
            if !item.host.model.isChecking, window.isKeyWindow {
                try check(accent >= 200,
                          "\(item.appearance)/\(item.scenario): the only action button renders without prominent emphasis (\(accent) accent pixels)")
            } else if !window.isKeyWindow {
                print("{\"warning\":\"\(item.appearance)/\(item.scenario): the settings window is not key; emphasis not measured\"}")
            }
            weights.append(["appearance": item.appearance, "state": item.scenario,
                            "checking": item.host.model.isChecking ? 1 : 0,
                            "accent_pixels": accent,
                            "layout": (try aboutPageLayout(item.host)).json])
            let url = directory.appendingPathComponent("about-page-\(item.appearance)-\(item.scenario).png")
            try bitmap.representation(using: .png, properties: [:])!.write(to: url)
            written += 1
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        try check(written == 10, "expected ten About page renders, wrote \(written)")
        print(String(data: try JSONSerialization.data(withJSONObject: ["button_weights": weights], options: [.sortedKeys]), encoding: .utf8)!)
        return written
    }
}
