import AppKit
import Foundation
import Translation

// This test target compiles the unchanged BlinkClipCapture sources in the same
// module. No test doubles replace config, OCR, TranslationService or Apple.
@MainActor
@main
struct TranslationIntegrationHarness {
    static var cases: [[String: Any]] = []
    static var outputPath = ""

    static func record(_ name: String, _ passed: Bool, _ details: [String: Any] = [:]) {
        var entry = details
        entry["case"] = name
        entry["passed"] = passed
        cases.append(entry)
        if let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
           let line = String(data: data, encoding: .utf8) { print(line); fflush(stdout) }
    }

    static func main() {
        guard CommandLine.arguments.count == 3,
              let bundleID = Bundle.main.bundleIdentifier,
              bundleID.hasPrefix("local.blinkclip.translation-integration.") else {
            fputs("Unique test bundle identity and output path required\n", stderr)
            exit(64)
        }
        let mode = CommandLine.arguments[1]
        outputPath = CommandLine.arguments[2]
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        Task { @MainActor in
            switch mode {
            case "defaults-unset":
                runDefaultSemantics()
            case "defaults-reopen":
                runDefaultReopen()
            case "settings-write":
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                for kind in TranslationProviderKind.allCases {
                    TranslationConfigStore.setEnabled(false, for: kind)
                }
                TranslationSettingsBridge.appleTranslationEnabled = true
                UserDefaults.standard.synchronize()
                record("bridge-write-persistence", TranslationConfigStore.isEnabled(.apple)
                       && UserDefaults.standard.bool(forKey: "translation.apple.enabled"))
            case "settings-read":
                record("bridge-reopen-read", TranslationSettingsBridge.appleTranslationEnabled
                       && TranslationConfigStore.isEnabled(.apple))
                TranslationSettingsBridge.appleTranslationEnabled = false
                UserDefaults.standard.synchronize()
                record("bridge-disable-after-reopen", !TranslationConfigStore.isEnabled(.apple)
                       && TranslationConfigStore.usableKinds().isEmpty
                       && !TranslationSettingsBridge.hasUsableTranslationProvider)
            case "cleanup":
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.synchronize()
                record("preferences-cleanup", UserDefaults.standard.persistentDomain(forName: bundleID) == nil)
            default:
                await runIntegration()
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                UserDefaults.standard.synchronize()
            }
            let payload: [String: Any] = [
                "bundleID": bundleID,
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
                "cases": cases,
                "passed": cases.allSatisfy { $0["passed"] as? Bool == true },
                "boundaries": [
                    "Unmodified production sources compiled with the harness in one independent target.",
                    "No public OCRTranslatePanel.present entry is called: those activate the app. Panel private runOCR/runTranslation and visible failure cards remain outside this harness.",
                    "OCR input is generated text on an image; no screen capture, user content, TCC change or remote keyed API.",
                    "Only en and zh-Hans already-installed Apple models are used; no prepareTranslation/download call.",
                    "Missing-provider failure and pending real-provider cancellation are checked separately from successful translation.",
                    "Settings adapter destination is tested with a spy; visible ReplicaUIController navigation belongs to the separate UI verification.",
                    "Default-on semantics are read-only: an unset translation.apple.enabled key never becomes a stored value, so an explicit false from the user always survives a restart. System-unavailable is simulated through the store's availability override, never by changing the real #available gate."
                ]
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: outputPath))
            }
            exit(cases.allSatisfy { $0["passed"] as? Bool == true } ? 0 : 1)
        }
        app.run()
    }

    /// 「从未设置过」的缺省语义：Apple 翻译在系统支持时按「开」读，且读取不落盘。
    /// 这个模式自带一份空域，随后显式写入 false，交给下一个进程（`defaults-reopen`）验证重启后仍是关。
    static func runDefaultSemantics() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            record("default-mode-bundle-identity", false)
            return
        }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()
        let available = TranslationSettingsBridge.isAppleTranslationAvailableOnSystem
        let read = TranslationSettingsBridge.appleTranslationEnabled
        let kinds = TranslationConfigStore.usableKinds()

        record("default-unset-reads-enabled", read == available, ["read": read, "systemAvailable": available])
        if #available(macOS 15.0, *) {
            record("default-unset-enabled-on-macos15", read)
        }
        // 读取只做读适配，不得顺手把键写进 UserDefaults：写过之后就无法区分
        // 「用户显式关掉」与「缺省值」，重启就可能把用户的 false 覆盖回 true。
        record("default-unset-writes-nothing",
               UserDefaults.standard.object(forKey: "translation.apple.enabled") == nil)
        // 设置页开关（bridge）、OCR 面板（usableKinds）与 store 必须看到同一个值。
        record("default-unset-consistent-across-consumers",
               TranslationConfigStore.isEnabled(.apple) == TranslationSettingsBridge.appleTranslationEnabled
               && TranslationConfigStore.isUsable(.apple) == !kinds.isEmpty
               && TranslationSettingsBridge.hasUsableTranslationProvider == !kinds.isEmpty
               && kinds == (TranslationSettingsBridge.appleTranslationEnabled ? [.apple] : []),
               ["usableKinds": kinds.map(\.rawValue)])

        // 缺省策略是可注入的：清空它即回到上游「默认关」，恢复后又是 true。
        let policy = TranslationConfigStore.defaultEnabledProvider
        TranslationConfigStore.defaultEnabledProvider = nil
        record("default-policy-injection-clears-to-opt-in",
               !TranslationSettingsBridge.appleTranslationEnabled
               && TranslationConfigStore.usableKinds().isEmpty
               && !TranslationSettingsBridge.hasUsableTranslationProvider)
        TranslationConfigStore.defaultEnabledProvider = policy
        record("default-policy-injection-restores", TranslationSettingsBridge.appleTranslationEnabled)

        // 系统不支持（模拟 macOS 14）：缺省值不能把不可用的供应商算成可用。
        TranslationConfigStore.availabilityOverride = { $0.isAppleTranslation ? false : $0.isAvailableOnCurrentSystem }
        record("default-unset-unavailable-system-not-usable",
               !TranslationSettingsBridge.isAppleTranslationAvailableOnSystem
               && !TranslationSettingsBridge.appleTranslationEnabled
               && !TranslationConfigStore.isEnabled(.apple)
               && !TranslationConfigStore.isUsable(.apple)
               && TranslationConfigStore.usableKinds().isEmpty
               && !TranslationSettingsBridge.hasUsableTranslationProvider)
        TranslationConfigStore.availabilityOverride = nil
        record("availability-override-restored", TranslationSettingsBridge.isAppleTranslationAvailableOnSystem)

        // 显式 true / 显式 false：写过的值永远优先。
        TranslationSettingsBridge.appleTranslationEnabled = true
        record("explicit-true-enabled",
               TranslationSettingsBridge.appleTranslationEnabled
               && TranslationConfigStore.isEnabled(.apple)
               && UserDefaults.standard.bool(forKey: "translation.apple.enabled")
               && TranslationConfigStore.usableKinds() == (available ? [.apple] : []))
        TranslationSettingsBridge.appleTranslationEnabled = false
        UserDefaults.standard.synchronize()
        record("explicit-false-disables",
               !TranslationSettingsBridge.appleTranslationEnabled
               && !TranslationConfigStore.isEnabled(.apple)
               && TranslationConfigStore.usableKinds().isEmpty
               && UserDefaults.standard.object(forKey: "translation.apple.enabled") != nil)
    }

    /// 新进程读取上一个进程写下的显式 false：必须仍然是关，缺省 true 不能重新打开它。
    static func runDefaultReopen() {
        record("explicit-false-survives-restart",
               UserDefaults.standard.object(forKey: "translation.apple.enabled") != nil
               && !TranslationSettingsBridge.appleTranslationEnabled
               && !TranslationConfigStore.isEnabled(.apple)
               && TranslationConfigStore.usableKinds().isEmpty
               && !TranslationSettingsBridge.hasUsableTranslationProvider,
               ["storedKeys": UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?.keys
                              .filter { $0.hasPrefix("translation.") }.sorted() ?? []])
    }

    static func runIntegration() async {
        // 先把路由显式关掉：本模式不依赖前一个进程留下的键状态。
        TranslationSettingsBridge.appleTranslationEnabled = false
        record("explicit-disable-leaves-no-route", !TranslationSettingsBridge.appleTranslationEnabled
               && !TranslationSettingsBridge.hasUsableTranslationProvider
               && TranslationConfigStore.usableKinds().isEmpty)
        var notifications = 0
        let observer = NotificationCenter.default.addObserver(forName: .translationConfigDidChange,
                                                              object: nil, queue: nil) { _ in notifications += 1 }
        TranslationSettingsBridge.appleTranslationEnabled = true
        record("bridge-enable-apple-route", TranslationConfigStore.usableKinds() == [.apple]
               && TranslationSettingsBridge.appleTranslationEnabled
               && TranslationSettingsBridge.hasUsableTranslationProvider
               && TranslationSettingsBridge.isAppleTranslationAvailableOnSystem
               && notifications == 1,
               ["usableKinds": TranslationConfigStore.usableKinds().map(\.rawValue), "notifications": notifications])
        NotificationCenter.default.removeObserver(observer)

        BlinkClipSettingsOpener.open = nil
        SettingsWindowController.shared.showAsSettings()
        record("settings-uninstalled-slot-noop", true)
        var destinations: [BlinkClipSettingsPane] = []
        BlinkClipSettingsOpener.open = { destinations.append($0) }
        SettingsWindowController.shared.showAsSettings()
        SettingsWindowController.shared.showAsSettings(focusingPermissions: true)
        record("settings-adapter-screenshot-destination", destinations.count == 2
               && destinations.allSatisfy { if case .screenshot = $0 { return true }; return false })
        BlinkClipSettingsOpener.open = nil

        let absent = await collect(text: "The blue book is on the table.", target: .chinese, provider: nil)
        record("service-missing-provider-finishes", absent.error == "appleTranslationUnavailable"
               && !absent.timedOut, absent.details)

        guard #available(macOS 15.0, *) else {
            record("apple-system-availability", false, ["limitation": "macOS 15 required"])
            return
        }
        let availability = LanguageAvailability()
        let en = Locale.Language(identifier: "en")
        let zh = Locale.Language(identifier: "zh-Hans")
        let forward = await availability.status(from: en, to: zh)
        let reverse = await availability.status(from: zh, to: en)
        record("installed-model-precondition", forward == .installed && reverse == .installed,
               ["en-to-zh-Hans": String(describing: forward), "zh-Hans-to-en": String(describing: reverse)])
        guard forward == .installed, reverse == .installed else { return }
        guard let provider = AppleTranslationSessionProviderFactory.makeProvider() else {
            record("apple-provider-factory", false)
            return
        }
        let panel = NSPanel(contentRect: NSRect(x: -16000, y: -16000, width: 400, height: 160),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.stationary, .ignoresCycle]
        panel.contentView = provider.hostView
        panel.orderFront(nil)
        defer {
            provider.cancel()
            panel.orderOut(nil)
            panel.contentView = nil
            panel.close()
        }
        record("factory-real-host-attached-offscreen", provider.hostView.window === panel
               && panel.isVisible && !panel.isKeyWindow && !panel.isMainWindow,
               ["hostClass": NSStringFromClass(type(of: provider.hostView)),
                "offscreenFrame": NSStringFromRect(panel.frame), "appActive": NSApp.isActive])
        try? await Task.sleep(nanoseconds: 400_000_000)

        let english = "The blue book is on the table."
        let chinese = "桌子上有一本蓝色的书。"
        let forwardResult = await collect(text: english, target: .chinese, provider: provider)
        record("service-real-apple-english-to-chinese", validChinese(forwardResult.text, source: english)
               && forwardResult.error.isEmpty && !forwardResult.timedOut, forwardResult.details)
        // Chinese matches the saved preferred Chinese target; the production
        // direction resolver must flip it to English, as in the actual panel.
        let reverseResult = await collect(text: chinese, target: .chinese, provider: provider)
        record("service-real-apple-chinese-auto-to-english", validEnglish(reverseResult.text, source: chinese)
               && reverseResult.error.isEmpty && !reverseResult.timedOut, reverseResult.details)

        do {
            let image = syntheticImage(english)
            Defaults.ocrProviderKind = .apple
            let result = try await OCRService.recognizeResult(image: image)
            let recognized = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            record("real-ocr-synthetic-input", result.provider == .apple && !recognized.isEmpty,
                   ["recognizedText": recognized, "lines": result.lines.count])
            if !recognized.isEmpty {
                let kinds = TranslationConfigStore.usableKinds()
                guard let kind = kinds.first else {
                    record("ocr-text-service-route", false, ["limitation": "No configured provider"])
                    return
                }
                let translated = await collect(text: recognized, target: .chinese, provider: provider, kind: kind)
                record("ocr-text-service-real-apple-route", validChinese(translated.text, source: recognized)
                       && translated.error.isEmpty && !translated.timedOut,
                       translated.details.merging(["ocrText": recognized, "routedKind": kind.rawValue]) { $1 })
            }
        } catch {
            record("real-ocr-synthetic-input", false, ["error": String(describing: error)])
        }

        // With no window the real provider stays pending. This isolates
        // cancellation from translation speed and never supplies fake output.
        if let pending = AppleTranslationSessionProviderFactory.makeProvider() {
            let cancelled = await collect(text: english, target: .chinese, provider: pending,
                                          cancelAfter: 0.05, cancelConsumer: false)
            record("real-provider-explicit-cancel-finishes-service", cancelled.error == "CancellationError"
                   && !cancelled.timedOut, cancelled.details)
            let taskCancelled = await collect(text: english, target: .chinese, provider: pending,
                                              cancelAfter: 0.05, cancelConsumer: true)
            record("service-consumer-task-cancel-finishes", !taskCancelled.timedOut
                   && taskCancelled.text.isEmpty, taskCancelled.details)
            pending.cancel()
        }
        TranslationSettingsBridge.appleTranslationEnabled = false
        record("bridge-disable-removes-route", !TranslationSettingsBridge.hasUsableTranslationProvider
               && TranslationConfigStore.usableKinds().isEmpty)
    }

    static func syntheticImage(_ text: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 1000, height: 180))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 180).fill()
        (text as NSString).draw(at: NSPoint(x: 30, y: 70), withAttributes: [
            .font: NSFont.systemFont(ofSize: 43), .foregroundColor: NSColor.black
        ])
        image.unlockFocus()
        return image
    }

    static func validChinese(_ text: String, source: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text != source
        && text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }
    static func validEnglish(_ text: String, source: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text != source
        && text.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
        && !text.unicodeScalars.contains { (0x4E00...0x9FFF).contains($0.value) }
    }

    struct Collected {
        var text = ""
        var error = ""
        var timedOut = false
        var elapsed = 0.0
        var details: [String: Any] { ["text": text, "error": error, "timedOut": timedOut, "seconds": elapsed] }
    }
    final class Completion {
        var continuation: CheckedContinuation<Collected, Never>?
        var task: Task<Void, Never>?
        var timer: Task<Void, Never>?
        func finish(_ value: Collected) {
            guard let continuation else { return }
            self.continuation = nil
            timer?.cancel()
            continuation.resume(returning: value)
        }
    }
    static func collect(text: String, target: TranslationLanguage, provider: AppleTranslationSessionProviding?,
                        kind: TranslationProviderKind = .apple, cancelAfter: Double? = nil,
                        cancelConsumer: Bool = false) async -> Collected {
        let start = Date()
        let completion = Completion()
        return await withCheckedContinuation { continuation in
            completion.continuation = continuation
            completion.task = Task { @MainActor in
                var value = Collected()
                do {
                    for try await delta in TranslationService.stream(text: text, target: target, kind: kind,
                                                                     config: TranslationConfigStore.load(kind),
                                                                     appleProvider: provider) { value.text += delta }
                } catch is CancellationError {
                    value.error = "CancellationError"
                } catch TranslationError.appleTranslationUnavailable {
                    value.error = "appleTranslationUnavailable"
                } catch { value.error = String(describing: error) }
                value.elapsed = Date().timeIntervalSince(start)
                completion.finish(value)
            }
            completion.timer = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 15_000_000_000) } catch { return }
                completion.task?.cancel()
                provider?.cancel()
                completion.finish(Collected(error: "request-timeout", timedOut: true,
                                             elapsed: Date().timeIntervalSince(start)))
            }
            if let cancelAfter {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(cancelAfter * 1_000_000_000))
                    if cancelConsumer { completion.task?.cancel() } else { provider?.cancel() }
                }
            }
        }
    }
}
