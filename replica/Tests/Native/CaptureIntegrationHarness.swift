// Only the capcap engine boundary and OS side effects are doubled. Production
// Settings, CaptureEntry, HistoryManagerBridge, Coordinator, HistoryBridge and
// ClipboardStore are compiled unchanged; this file contains no routing replica.
import AppKit
import Foundation

#if CAPTURE_BOUNDARY
public enum CaptureProbe {
    public static var actions: [String] = []
    public static var activations = 0
    public static var fullScreenLaunches = 0
    public static var failFullScreen = false
    public static var suspendedToken: UUID?
    public static var resumedToken: UUID?
    static var current: OverlayWindowController?
    public static func complete(_ image: NSImage?) { current?.completion(image); current = nil }
    public static func suspend() {
        suspendedToken = current?.draft.token
        current?.suspension(current!.draft); current = nil
    }
    public static func historyImage(_ image: NSImage) { HistoryManager.shared.add(image: image) }
    public static func historyText(_ text: String) { HistoryManager.shared.addText(text) }
    public static func historyColor(_ hex: String) { HistoryManager.shared.addColor(hex: hex) }
}
struct CaptureTriggerContext {
    enum Source { case keyboardShortcut }
    let source: Source
}
final class OverlayWindowController {
    enum PostCaptureAction: String { case edit, quickPin, textRecognition, copyImageText, screenshotTranslation }
    struct SuspendedEditDraft {
        let screenDisplayID: CGDirectDisplayID? = nil
        let screenFrame: CGRect
        let token = UUID()
    }
    let draft: SuspendedEditDraft
    let completion: (NSImage?) -> Void
    let suspension: (SuspendedEditDraft) -> Void
    init(postCaptureAction: PostCaptureAction, triggerContext: CaptureTriggerContext,
         onFirstFramePresented: (() -> Void)?, onRecordingSelection: @escaping (CGRect, NSScreen) -> Void,
         onRequestFocusReturn: @escaping () -> Void, onSuspend: @escaping (SuspendedEditDraft) -> Void,
         onComplete: @escaping (NSImage?) -> Void) {
        draft = SuspendedEditDraft(screenFrame: NSScreen.screens.first?.frame ?? .zero)
        completion = onComplete; suspension = onSuspend
        CaptureProbe.actions.append(postCaptureAction.rawValue)
    }
    init(suspendedDraft: SuspendedEditDraft, onRecordingSelection: @escaping (CGRect, NSScreen) -> Void,
         onRequestFocusReturn: @escaping () -> Void, onSuspend: @escaping (SuspendedEditDraft) -> Void,
         onComplete: @escaping (NSImage?) -> Void) {
        draft = suspendedDraft; completion = onComplete; suspension = onSuspend
        CaptureProbe.resumedToken = suspendedDraft.token
    }
    func activate() { CaptureProbe.activations += 1; CaptureProbe.current = self }
}
enum ScreenCapturer {
    static func capture(rect: CGRect, screen: NSScreen, excludingWindowNumbers: [CGWindowID] = [], timeout: TimeInterval) -> NSImage? {
        CaptureProbe.failFullScreen ? nil : NSImage(size: NSSize(width: 2, height: 2))
    }
}
enum ImageEditLauncher {
    enum Source { case fullScreen }
    static func launch(generatedImage: NSImage, source: Source, onRequestFocusReturn: @escaping () -> Void,
                       onSuspend: @escaping (OverlayWindowController.SuspendedEditDraft) -> Void,
                       onComplete: @escaping (NSImage?) -> Void) -> AnyObject? {
        CaptureProbe.fullScreenLaunches += 1
        let controller = OverlayWindowController(postCaptureAction: .edit,
            triggerContext: CaptureTriggerContext(source: .keyboardShortcut), onFirstFramePresented: nil,
            onRecordingSelection: { _, _ in }, onRequestFocusReturn: onRequestFocusReturn,
            onSuspend: onSuspend, onComplete: onComplete)
        controller.activate()
        return controller
    }
}
#else
import Combine
import CryptoKit
import CoreData
import BlinkClipCore
import BlinkClipCapture

@MainActor final class GlobalHotKey {
    static var events: [String] = []
    static var status: OSStatus = 0
    var action: (() -> Void)?
    func register(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, identifier: UInt32) -> OSStatus {
        Self.events.append("register:\(identifier):\(keyCode):\(modifiers.rawValue)"); return Self.status
    }
    func unregister() { Self.events.append("unregister") }
}
struct ScreenshotFocusRestorer {
    static func captureFrontmost() -> Self { Self() }
    func restore() {}
}
enum ReplicaBrand { static let name = "BlinkClip" }

@main struct CaptureIntegrationHarness {
    enum Failure: Error { case assertion(String) }
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier!
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "read-action" {
            guard BlinkClipScreenshotSettings.postCaptureAction.rawValue == args[2] else { exit(3) }
            exit(0)
        }
        if args.count == 3 && args[1] == "read-cleared" {
            let slot = BlinkClipScreenshotHotKeySlot(rawValue: args[2])!
            guard BlinkClipScreenshotSettings.effectiveShortcut(for: slot) == nil else { exit(4) }
            exit(0)
        }
        defer { defaults.removePersistentDomain(forName: domain); defaults.synchronize() }
        defaults.removePersistentDomain(forName: domain)
        var checks: [String] = []
        func require(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure.assertion(message) }
            checks.append(message)
            fputs("PASS \(message)\n", stderr)
        }
        func reopenAction(_ expected: String) throws {
            defaults.synchronize()
            let p = Process(); p.executableURL = Bundle.main.executableURL
            p.arguments = ["read-action", expected]; try p.run(); p.waitUntilExit()
            try require(p.terminationStatus == 0, "fresh-process preference read: \(expected)")
        }
        func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.025)) }
        try require(BlinkClipScreenshotSettings.postCaptureAction == .edit, "missing action falls back to edit")
        defaults.set("unsupported", forKey: BlinkClipScreenshotSettings.postCaptureActionKey)
        try require(BlinkClipScreenshotSettings.postCaptureAction == .edit, "invalid action falls back to edit")
        // Start from a non-default value so `.edit` must really be written,
        // rather than passing only because the invalid value falls back to it.
        BlinkClipScreenshotSettings.postCaptureAction = .screenshotTranslation
        var actionNotifications = 0
        let observer = NotificationCenter.default.addObserver(forName: BlinkClipScreenshotSettings.didChange,
            object: nil, queue: .main) { _ in actionNotifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }
        for action in BlinkClipScreenshotAction.allCases {
            BlinkClipScreenshotSettings.postCaptureAction = action
            try require(defaults.string(forKey: BlinkClipScreenshotSettings.postCaptureActionKey) == action.rawValue,
                        "selected action is serialized: \(action.rawValue)")
            try reopenAction(action.rawValue)
            _ = CaptureEntry.presentRegionEditor(onFocusReturn: {}, onComplete: { _ in })
            try require(CaptureProbe.actions.last == action.rawValue, "real CaptureEntry forwards \(action.rawValue)")
            CaptureProbe.complete(nil)
        }
        try require(actionNotifications == 5, "all five changed effective actions notify")
        let before = actionNotifications
        BlinkClipScreenshotSettings.postCaptureAction = .screenshotTranslation
        try require(actionNotifications == before, "same action does not notify")
        _ = CaptureEntry.presentFullScreenEditor(onFocusReturn: {}, onComplete: { _ in })
        try require(CaptureProbe.fullScreenLaunches == 1 && CaptureProbe.actions.last == "edit", "full screen uses editor regardless of region preference")
        CaptureProbe.complete(nil)

        try require(BlinkClipScreenshotSettings.effectiveShortcut(for: .region) == BlinkClipScreenshotSettings.regionDefault && BlinkClipScreenshotSettings.effectiveShortcut(for: .fullScreen) == BlinkClipScreenshotSettings.fullScreenDefault, "legacy preferences without enabled keys preserve both defaults")
        for bad: Any in ["abc", true, -1, 70000] {
            defaults.set(bad, forKey: BlinkClipScreenshotSettings.regionKeyCodeKey)
            try require(BlinkClipScreenshotSettings.regionShortcut == BlinkClipScreenshotSettings.regionDefault, "malformed region key falls back: \(bad)")
        }
        BlinkClipScreenshotSettings.setShortcut(BlinkClipScreenshotSettings.regionDefault, for: .region, force: true)
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CAPTURE_STORE_ROOT"]!)
        let store = try ClipboardStore(directoryURL: root)
        try require(store.items.isEmpty, "capture integration starts with an empty isolated Store")
        var savedContext: NSManagedObjectContext?
        var saveCount = 0
        let saveObserver = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave,
            object: nil, queue: nil) { notification in
                guard let context = notification.object as? NSManagedObjectContext,
                      context.persistentStoreCoordinator?.persistentStores.contains(where: {
                          $0.url?.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL
                      }) == true else { return }
                savedContext = context; saveCount += 1
            }
        defer { NotificationCenter.default.removeObserver(saveObserver) }
        let pb = NSPasteboard(name: NSPasteboard.Name("local.blinkclip.capture-test.\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let coordinator = ScreenshotCoordinator(store: store, pasteboard: pb)
        defer { coordinator.stop() }
        GlobalHotKey.status = -9878
        coordinator.start()
        try require(BlinkClipScreenshotSettings.lastRegistration[.region]?.status == -9878, "registration failure reaches settings")
        GlobalHotKey.status = 0; GlobalHotKey.events.removeAll()
        BlinkClipScreenshotSettings.requestHotKeyReload()
        try require(GlobalHotKey.events.prefix(2).allSatisfy { $0 == "unregister" } && GlobalHotKey.events.count == 4,
                    "retry with unchanged preference unregisters both before registering")
        try require(BlinkClipScreenshotSettings.lastRegistration.values.allSatisfy(\.succeeded), "retry replaces failed registration results")
        GlobalHotKey.events.removeAll()
        let custom = BlinkClipScreenshotHotKey(keyCode: 40, modifierRawValue: NSEvent.ModifierFlags([.control, .option]).rawValue)
        BlinkClipScreenshotSettings.regionShortcut = custom
        try require(GlobalHotKey.events.count == 4 && GlobalHotKey.events[2].hasPrefix("register:101:40:"), "settings notification registers selected key after old keys removed")
        GlobalHotKey.events.removeAll()
        BlinkClipScreenshotSettings.beginRecording(); BlinkClipScreenshotSettings.beginRecording()
        try require(GlobalHotKey.events == ["unregister", "unregister"], "overlapping recording suspends keys once")
        BlinkClipScreenshotSettings.fullScreenShortcut = BlinkClipScreenshotHotKey(keyCode: 41, modifierRawValue: custom.modifierRawValue)
        BlinkClipScreenshotSettings.endRecording()
        try require(GlobalHotKey.events.count == 2, "first recorder ending leaves keys suspended")
        BlinkClipScreenshotSettings.endRecording()
        try require(GlobalHotKey.events.count == 6 && GlobalHotKey.events.last!.hasPrefix("register:102:41:"), "last recorder restores current preferences")
        let endedCount = GlobalHotKey.events.count
        BlinkClipScreenshotSettings.endRecording()
        try require(GlobalHotKey.events.count == endedCount, "extra recording end does not re-register")

        // Clearing is persisted independently from the legacy key/modifier pair.
        for slot in BlinkClipScreenshotHotKeySlot.allCases {
            let other: BlinkClipScreenshotHotKeySlot = slot == .region ? .fullScreen : .region
            let otherValue = BlinkClipScreenshotSettings.effectiveShortcut(for: other)
            let oldValue = BlinkClipScreenshotSettings.shortcut(for: slot)
            GlobalHotKey.events.removeAll()
            BlinkClipScreenshotSettings.clearShortcut(for: slot)
            let identifier = slot == .region ? "101" : "102"
            try require(BlinkClipScreenshotSettings.effectiveShortcut(for: slot) == nil, "cleared shortcut is unset: \(slot)")
            try require(BlinkClipScreenshotSettings.lastRegistration[slot] == nil, "cleared slot removes stale registration status: \(slot)")
            try require(GlobalHotKey.events.contains("unregister") && !GlobalHotKey.events.contains(where: { $0.hasPrefix("register:\(identifier):") }), "cleared slot is really unregistered and never registered: \(slot)")
            try require(BlinkClipScreenshotSettings.effectiveShortcut(for: other) == otherValue, "clearing leaves other slot unchanged: \(slot)")
            try require(BlinkClipScreenshotSettings.slot(occupying: oldValue) == nil, "cleared shortcut no longer reserves a combination: \(slot)")
            defaults.synchronize()
            let fresh = Process(); fresh.executableURL = Bundle.main.executableURL
            fresh.arguments = ["read-cleared", slot.rawValue]; try fresh.run(); fresh.waitUntilExit()
            try require(fresh.terminationStatus == 0, "fresh-process unset shortcut persists: \(slot)")
            BlinkClipScreenshotSettings.requestHotKeyReload()
            try require(!GlobalHotKey.events.contains(where: { $0.hasPrefix("register:\(identifier):") }), "reload leaves cleared shortcut disabled: \(slot)")
            GlobalHotKey.events.removeAll()
            BlinkClipScreenshotSettings.setShortcut(oldValue, for: slot)
            try require(BlinkClipScreenshotSettings.effectiveShortcut(for: slot) == oldValue && GlobalHotKey.events.contains(where: { $0.hasPrefix("register:\(identifier):") }), "assigning same legacy combination re-enables cleared slot: \(slot)")
        }
        for slot in BlinkClipScreenshotHotKeySlot.allCases { BlinkClipScreenshotSettings.clearShortcut(for: slot) }
        BlinkClipScreenshotSettings.restoreAllShortcutDefaults()
        try require(BlinkClipScreenshotSettings.effectiveShortcut(for: .region) == BlinkClipScreenshotSettings.regionDefault && BlinkClipScreenshotSettings.effectiveShortcut(for: .fullScreen) == BlinkClipScreenshotSettings.fullScreenDefault, "restore all re-enables both cleared screenshot defaults")
        // Preserve this suite's existing custom-pair assertions below.
        BlinkClipScreenshotSettings.regionShortcut = custom
        BlinkClipScreenshotSettings.fullScreenShortcut = .init(keyCode: 41, modifierRawValue: custom.modifierRawValue)

        coordinator.startRegionCapture()
        GlobalHotKey.events.removeAll()
        BlinkClipScreenshotSettings.requestHotKeyReload()
        try require(GlobalHotKey.events.isEmpty, "reload deferred while presentation is queued")
        drain()
        let activeCount = CaptureProbe.activations
        coordinator.startRegionCapture(); drain()
        try require(CaptureProbe.activations == activeCount, "active overlay rejects repeated capture")
        BlinkClipScreenshotSettings.requestHotKeyReload()
        try require(GlobalHotKey.events.isEmpty, "reload deferred while overlay is active")
        let emptyCount = store.items.count
        CaptureProbe.complete(nil)
        try require(store.items.count == emptyCount && pb.pasteboardItems?.isEmpty != false, "cancel callback leaves Store and private pasteboard empty")
        try require(GlobalHotKey.events.count == 4, "cancel exit applies pending reload")

        BlinkClipScreenshotSettings.postCaptureAction = .edit
        coordinator.startRegionCapture(); drain()
        GlobalHotKey.events.removeAll(); BlinkClipScreenshotSettings.requestHotKeyReload()
        CaptureProbe.suspend()
        try require(GlobalHotKey.events.count == 4, "suspend exit applies pending reload")
        BlinkClipScreenshotSettings.postCaptureAction = .textRecognition
        coordinator.startRegionCapture()
        try require(CaptureProbe.resumedToken != nil && CaptureProbe.resumedToken == CaptureProbe.suspendedToken,
                    "real resume entry forwards original draft unchanged despite preference change")
        CaptureProbe.complete(nil)

        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let image = NSImage(size: NSSize(width: 3, height: 2)); image.addRepresentation(bitmap)
        coordinator.startRegionCapture(); drain(); CaptureProbe.complete(image)
        let saved = store.items.first!
        try require(saved.kind == .image && saved.plainText == nil && Set(saved.payloads.keys) == ["public.png"], "completion creates PNG image record in real Store")
        try require(pb.data(forType: .png) == saved.payloads["public.png"], "completion writes same PNG via real Store to private pasteboard")
        let bridge = ScreenshotHistoryBridge(store: store)
        try require(bridge.blinkclipImageEntries().count == 1 && bridge.blinkclipImage(forLocator: bridge.blinkclipImageEntries()[0].locator) != nil,
                    "history bridge reads real image locator and decodes payload")
        func diagnosticSHA(_ data: Data?) -> String {
            guard let data else { return "nil" }
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        func diagnosticItems(_ phase: String) {
            fputs("DUPLICATE_DIAG phase=\(phase) mainThread=\(Thread.isMainThread) count=\(store.items.count)\n", stderr)
            for item in store.items {
                fputs("DUPLICATE_DIAG id=\(item.id) kind=\(item.kind) pngLength=\(item.payloads["public.png"]?.count ?? -1) pngSHA=\(diagnosticSHA(item.payloads["public.png"])) updatedAt=\(item.updatedAt.timeIntervalSince1970)\n", stderr)
            }
        }
        diagnosticItems("before-historyImage")
        CaptureProbe.historyImage(image)
        diagnosticItems("after-historyImage")
        let repeatedImage = store.items.first { $0.kind == .image }!
        try require(repeatedImage.id == saved.id && store.items.count == 1,
                    "duplicate PNG updates original identity without creating a second item")
        let repeatedReopened = try ClipboardStore(directoryURL: root)
        try require(repeatedReopened.items.first { $0.id == saved.id }?.updatedAt == repeatedImage.updatedAt,
                    "duplicate PNG publishes exact persisted updatedAt after willSave")
        CaptureProbe.historyText("capture OCR 接入")
        CaptureProbe.historyColor("#A1B2C3")
        try require(store.items.contains { $0.kind == .text && $0.plainText == "capture OCR 接入" && $0.payloads["public.utf8-plain-text"] == Data("capture OCR 接入".utf8) }, "real HistoryManager and Bridge forward text data shape")
        try require(store.items.contains { $0.kind == .color && $0.plainText == "#A1B2C3" && $0.payloads["public.utf8-plain-text"] == Data("#A1B2C3".utf8) }, "real HistoryManager and Bridge forward color data shape")
        let reopened = try ClipboardStore(directoryURL: root)
        var reopenDifferences: [String] = []
        for item in store.items {
            guard let reloaded = reopened.items.first(where: { $0.id == item.id }) else {
                throw Failure.assertion("missing persisted item \(item.id)")
            }
            let before = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
            let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reloaded)) as! [String: Any]
            for key in Set(before.keys).union(after.keys) {
                if String(describing: before[key]) != String(describing: after[key]) {
                    reopenDifferences.append("\(item.kind):\(key): \(String(describing: before[key])) -> \(String(describing: after[key]))")
                }
            }
            try require(reloaded.kind == item.kind && reloaded.plainText == item.plainText && reloaded.payloads == item.payloads,
                        "reopened persistent Store retains data shape: \(item.kind)")
            try require(reloaded.updatedAt == item.updatedAt, "reopened Store retains exact updatedAt: \(item.kind)")
        }
        try require(reopenDifferences.isEmpty, "all serialized PNG/text/color fields match after reopen")
        try require(reopened.items.count == store.items.count, "reopened Store preserves item count")
        guard let context = savedContext else { throw Failure.assertion("missing private Store context") }
        let stateRequest = NSFetchRequest<NSManagedObject>(entityName: "State")
        let beforeNoOpRevision = try context.fetch(stateRequest).first?.value(forKey: "revision") as? UUID
        let beforeNoOp = store.items
        let beforeNoOpSaves = saveCount
        var publishedItems = 0
        let publication = store.$items.dropFirst().sink { _ in publishedItems += 1 }
        defer { publication.cancel() }
        try store.save()
        let afterNoOpRevision = try context.fetch(stateRequest).first?.value(forKey: "revision") as? UUID
        try require(saveCount == beforeNoOpSaves && beforeNoOpRevision != nil && afterNoOpRevision == beforeNoOpRevision
                    && store.items == beforeNoOp && publishedItems == 0,
                    "unchanged save does not save, advance dates or publish items")

        let beforeRollback = store.items
        let beforeRollbackPublications = publishedItems
        var injectedFailure = false
        let failSave = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave,
            object: context, queue: nil) { _ in
                guard let target = context.updatedObjects.first(where: { $0.entity.name == "Item" }) else { return }
                // The production model requires Item.data. Trigger actual Core Data
                // validation failure so the production rollback path must run.
                target.setValue(nil, forKey: "data"); injectedFailure = true
            }
        var saveFailed = false
        do { try store.add(repeatedImage) } catch { saveFailed = true }
        NotificationCenter.default.removeObserver(failSave)
        try require(injectedFailure && saveFailed, "required Item.data failure reaches production save rollback")
        try require(store.items == beforeRollback && publishedItems == beforeRollbackPublications && !context.hasChanges,
                    "failed save rolls back managed changes and does not publish speculative items")
        let afterRollback = try ClipboardStore(directoryURL: root)
        // Compare read-time snapshots with read-time snapshots: ClipboardItem's
        // Equatable also includes non-archived native application projection flags.
        try require(afterRollback.items == reopened.items, "failed save leaves reopened persisted items unchanged")

        let syncDate = Date(timeIntervalSince1970: 4_000_000_000)
        var syncItem = repeatedImage; syncItem.updatedAt = syncDate
        let oldAuthor = context.transactionAuthor
        context.transactionAuthor = "syncApply"
        do { try store.add(syncItem) }
        catch { context.transactionAuthor = oldAuthor; throw error }
        context.transactionAuthor = oldAuthor
        let afterSync = try ClipboardStore(directoryURL: root)
        try require(store.items.first { $0.id == syncItem.id }?.updatedAt == syncDate
                    && afterSync.items.first { $0.id == syncItem.id }?.updatedAt == syncDate,
                    "syncApply preserves explicit incoming date in published and persisted items")
        try require(bridge.blinkclipImage(forLocator: URL(string: "https://example.invalid/not-a-history-item")!) == nil, "history bridge rejects foreign locator")

        CaptureProbe.failFullScreen = true
        let beforeFailure = store.items.count
        coordinator.startFullScreenCapture()
        GlobalHotKey.events.removeAll(); BlinkClipScreenshotSettings.requestHotKeyReload(); drain()
        try require(GlobalHotKey.events.count == 4 && store.items.count == beforeFailure,
                    "capture failure exit applies pending reload and creates no record")
        CaptureProbe.failFullScreen = false

        let activationsBeforeStop = CaptureProbe.activations
        coordinator.startRegionCapture()
        coordinator.stop(); drain()
        try require(BlinkClipScreenshotSettings.lastRegistration.isEmpty && CaptureProbe.activations == activationsBeforeStop,
                    "stop clears registrations and cancels queued presentation")
        let stoppedCount = GlobalHotKey.events.count
        BlinkClipScreenshotSettings.requestHotKeyReload()
        try require(GlobalHotKey.events.count == stoppedCount, "stop removes settings observers")
        let report: [String: Any] = ["passed": true, "checks": checks, "count": checks.count,
            "reopen_field_differences": reopenDifferences,
            "duplicate_png_updated_at": ["first": saved.updatedAt.timeIntervalSince1970,
                "memory": repeatedImage.updatedAt.timeIntervalSince1970,
                "reopened": repeatedReopened.items.first { $0.id == saved.id }!.updatedAt.timeIntervalSince1970],
            "no_op_revision_unchanged": beforeNoOpRevision == afterNoOpRevision,
            "sync_apply_explicit_date": syncDate.timeIntervalSince1970,
            "real": ["ScreenshotSettings", "CaptureEntry", "HistoryManagerBridge", "ScreenshotCoordinator", "ScreenshotHistoryBridge", "ClipboardStore", "UserDefaults fresh-process reads", "private NSPasteboard"],
            "doubles": ["capcap OverlayWindowController/ScreenCapturer/ImageEditLauncher", "GlobalHotKey Carbon registration", "ScreenshotFocusRestorer", "ReplicaBrand constant"],
            "not_run": ["screen capture/editor internals", "real global Carbon delivery", "UI confirm-versus-save dispatch", "actual overlay draft internals", "window hide/focus restoration"]]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
    }
}
#endif
