import AppKit
import Combine
import Foundation
import os

enum HelperApplicationLocator {
    /// Prefer the app containing this helper, regardless of its visible filename.
    /// A stale Launch Services registration must not redirect a renamed installation.
    static func resolve(helperBundleURL: URL, mainID: String,
                        registeredApplication: () -> URL?,
                        applicationsDirectory: URL = URL(fileURLWithPath: "/Applications")) -> URL {
        func matchesMainApplication(_ url: URL) -> Bool {
            url.pathExtension.caseInsensitiveCompare("app") == .orderedSame
                && Bundle(url: url)?.bundleIdentifier == mainID
        }

        var enclosing = helperBundleURL
        for _ in 0..<4 { enclosing.deleteLastPathComponent() }
        if matchesMainApplication(enclosing) { return enclosing }
        if let registered = registeredApplication(), matchesMainApplication(registered) {
            return registered
        }
        let current = applicationsDirectory.appendingPathComponent("BlinkClip.app")
        if matchesMainApplication(current) { return current }
        // Keep a deterministic target when no installed copy can be found.
        return current
    }
}

@main
enum HelperMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = HelperDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.prohibited)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class HelperDelegate: NSObject, NSApplicationDelegate {
    private var defaults: UserDefaults? {
        UserDefaults(suiteName: "com.chrisli.blinkclip.session")
    }
    private let mainID = "com.chrisli.blinkclip"
    private let logger = Logger(subsystem: "com.chrisli.blinkclip.helper", category: "general")
    private var cancellables: Set<AnyCancellable> = []
    private var isLaunching = false
    private var retryCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        startMonitoring()
    }

    /// BlinkClip Helper, with this independent app's bundle and defaults identities.
    private func startMonitoring() {
        logger.info("BlinkClip Helper started at \(Bundle.main.bundleURL)")
        let url = applicationURL()
        let markedRunning = defaults?.bool(forKey: "pasteIsRunning") ?? false
        let running = isMainApplicationRunning()
        logger.info("BlinkClip located at: \(url)")
        logger.info("BlinkClip is marked as running: \(markedRunning)")
        logger.info("BlinkClip is running: \(running)")
        observeRunningApplications()
    }

    /// BlinkClip Helper: enclosing app, Launch Services, then the Applications fallback.
    private func applicationURL() -> URL {
        HelperApplicationLocator.resolve(helperBundleURL: Bundle.main.bundleURL, mainID: mainID,
                                         registeredApplication: {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: mainID)
        })
    }

    /// BlinkClip Helper; the KVO publisher includes its initial value.
    private func observeRunningApplications() {
        logger.info("Starting to monitor running applications")
        NSWorkspace.shared.publisher(for: \.runningApplications, options: [.initial, .new])
            .sink { [weak self] _ in
                // enqueue a MainActor task for each publication.
                MainActor.assumeIsolated {
                    _ = Task { @MainActor [weak self] in self?.checkRunning() }
                }
            }
            .store(in: &cancellables)
    }

    /// BlinkClip Helper: ignore missing identifiers; stop at the first matching app.
    private func isMainApplicationRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == mainID }
    }

    /// BlinkClip Helper: the launch guard covers an attempt, not the retry cooldown.
    private func checkRunning() {
        logger.info("Checking if BlinkClip needs to be launched...")
        guard !isLaunching else {
            logger.info("Launch already in progress")
            return
        }
        guard defaults?.bool(forKey: "pasteIsRunning") == true else {
            logger.info("BlinkClip is not marked as running")
            return
        }
        guard !isMainApplicationRunning() else {
            logger.info("BlinkClip is already running")
            return
        }
        logger.info("BlinkClip not running \n will launch in 3 seconds...")
        isLaunching = true
        Task { @MainActor [weak self] in
            // cancellation also proceeds to the post-delay check.
            try? await ContinuousClock().sleep(for: .seconds(3))
            await self?.launchAfterDelay()
        }
    }

    /// BlinkClip Helper: recheck the process, without rereading isRunning.
    private func launchAfterDelay() async {
        guard !isMainApplicationRunning() else {
            // The recovered branch returns without clearing isLaunching.
            logger.info("BlinkClip is already running")
            return
        }
        completeLaunchAttempt(succeeded: await launchApplication())
    }

    /// BlinkClip Helper.
    private func launchApplication() async -> Bool {
        defaults?.set(true, forKey: "pasteLaunchedByHelper")
        let url = applicationURL()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        logger.info("Launching BlinkClip at \(url.path)")
        do {
            _ = try await openApplication(at: url, configuration: configuration)
            logger.info("BlinkClip launched successfully.")
            return true
        } catch {
            logger.error("Failed to launch BlinkClip: \(error.localizedDescription)")
            return false
        }
    }

    /// BlinkClip Helper: error takes precedence; a successful callback must carry an app.
    private func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> NSRunningApplication {
        try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { application, error in
                if let error { continuation.resume(throwing: error) }
                else {
                    guard let application else {
                        preconditionFailure("NSWorkspace returned neither an application nor an error")
                    }
                    continuation.resume(returning: application)
                }
            }
        }
    }

    /// BlinkClip Helper: success resets the persistent retry counter; failure schedules retry.
    private func completeLaunchAttempt(succeeded: Bool) {
        if succeeded { retryCount = 0 }
        else {
            retryCount += 1
            let retryDelay = retryCount * 10
            logger.info("Retry in \(retryDelay) seconds...")
            Task { @MainActor [weak self] in
                // recheck even if sleep throws.
                try? await ContinuousClock().sleep(for: .seconds(retryDelay))
                self?.checkRunning()
            }
        }
        isLaunching = false
    }
}
