import AppKit
import Combine
import Foundation
import ObjectiveC.runtime
import BlinkClipCore

@main
struct PasteboardWriteFeedbackHarness {
    struct Failure: Error { let message: String }
    final class UndoTarget: NSObject { @objc func undoFixture() {} }
    final class Counts { var notification = 0; var subject = 0; var paste = 0; var copy = 0 }

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }

    static func snapshot(_ directory: URL) throws -> [String: Data] {
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])!
        var result: [String: Data] = [:]
        for case let file as URL in files {
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(file.path.dropFirst(directory.path.count))] = try Data(contentsOf: file)
            }
        }
        return result
    }

    // Only this isolated fixture changes class. No method on an existing class is swizzled.
    @MainActor static func withRejectedWrites(_ board: NSPasteboard, operation: () throws -> Void) throws {
        try require(board.name.rawValue.hasPrefix("BlinkClipWriteFeedback-"), "Not a private fixture")
        guard let original = object_getClass(board),
              let subclass = objc_allocateClassPair(original, "BlinkClipRejectedWrite_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))", 0),
              let method = class_getInstanceMethod(original, #selector(NSPasteboard.writeObjects(_:))) else {
            throw Failure(message: "Cannot create isolated write failure")
        }
        let block: @convention(block) (AnyObject, NSArray) -> Bool = { _, _ in false }
        let implementation = imp_implementationWithBlock(block)
        guard class_addMethod(subclass, #selector(NSPasteboard.writeObjects(_:)), implementation,
                              method_getTypeEncoding(method)) else {
            throw Failure(message: "Cannot install isolated override")
        }
        objc_registerClassPair(subclass)
        object_setClass(board, subclass)
        defer { object_setClass(board, original) }
        try operation()
    }

    @MainActor static func main() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let task = environment["ARTIFACT_TASK_DIR"] else { throw Failure(message: "storage-guard required") }
        let undo = UndoManager()
        let overrides = DependencyOverrides()
        overrides.registerFactory(\DependencyValues.pasteboardUndoManager, factory: { undo })
        var results: [[String: Any]] = []
        try Dependencies.withOverrides(overrides) {
            for registered in [false, true] {
                let directory = URL(fileURLWithPath: task).appendingPathComponent("build/store-\(registered)")
                let store = try ClipboardStore(directoryURL: directory)
                store.preferences.playSounds = true
                store.preferences.historyRetentionDays = 0
                let first = ClipboardItem(createdAt: Date(timeIntervalSince1970: 1_700_000_000), plainText: "first private payload")
                let second = ClipboardItem(createdAt: Date(timeIntervalSince1970: 1_700_000_001), plainText: "second private payload")
                store.items = [first, second]
                try store.save()
                let board = NSPasteboard(name: .init("BlinkClipWriteFeedback-\(UUID())"))
                defer { board.releaseGlobally() }
                let suite = "BlinkClipWriteFeedback-\(UUID())"
                let defaults = UserDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                let monitor = registered ? ClipboardMonitor(store: store, pasteboard: board, defaults: defaults) : nil
                let state = PasteboardCaptureState.current(for: board)
                defer { monitor?.stop() }
                let counts = Counts()
                let observer = NotificationCenter.default.addObserver(forName: ClipboardStore.didRestoreItemNotification,
                    object: store, queue: nil) { _ in counts.notification += 1 }
                defer { NotificationCenter.default.removeObserver(observer) }
                let subscription = store.didRestoreItem.sink { counts.subject += 1 }
                defer { subscription.cancel() }
                // Injected callback prevents all AudioServices/NSSound playback.
                let sounds = SoundEffects(store: store, monitor: monitor, playback: { feedback in
                    switch feedback { case .copy: counts.copy += 1; case .paste: counts.paste += 1 }
                })
                defer { sounds.stop() }
                let target = UndoTarget()
                undo.removeAllActions()
                undo.registerUndo(withTarget: target) { $0.undoFixture() }
                let beforeItems = store.items
                let beforeFiles = try snapshot(directory)
                for ids in [[first.id], [first.id, second.id]] {
                    try withRejectedWrites(board) {
                        var rejected = false
                        do { try store.writeToPasteboard(ids: ids, pasteboard: board) }
                        catch { rejected = true; try require(!error.localizedDescription.isEmpty, "Missing error description") }
                        try require(rejected, "Rejected write returned success")
                    }
                    monitor?.poll()
                    try require(counts.notification == 0 && counts.subject == 0 && counts.paste == 0 && counts.copy == 0,
                                "Failure emitted success feedback")
                    try require(store.items == beforeItems, "Failure changed history metadata")
                    let afterFiles = try snapshot(directory)
                    try require(afterFiles == beforeFiles, "Failure changed persisted files")
                    try require(undo.canUndo, "Failure cleared undo actions")
                    if let state { try require(!state.lastWriteSucceeded, "Registered failure result missing") }
                }
                for (index, ids) in [[first.id], [first.id], [first.id, second.id]].enumerated() {
                    try store.writeToPasteboard(ids: ids, pasteboard: board)
                    monitor?.poll()
                    if ids.count == 1 {
                        try require(board.pasteboardItems?.count == 1 && board.data(forType: .string) == Data(first.plainText!.utf8),
                                    "Successful single payload bytes mismatch")
                    } else {
                        guard let data = board.data(forType: .rtf) else { throw Failure(message: "Missing aggregate RTF") }
                        let text = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
                        try require(board.pasteboardItems?.count == 1 && text.string == first.plainText! + "\n" + second.plainText!,
                                    "Successful batch aggregate/order mismatch")
                    }
                    if let state { try require(state.syncTimer == nil, "Poll scheduled a duplicate capture") }
                    try require(counts.notification == index + 1 && counts.subject == index + 1 && counts.paste == index + 1,
                                "Successful write must emit each feedback exactly once")
                    try require(counts.copy == 0, "Restore emitted capture sound")
                    try require(!undo.canUndo, "Success did not clear undo actions")
                    if let state { try require(state.lastWriteSucceeded, "Registered success result missing") }
                }
                results.append(["registered_state": registered, "rejected_writes": 2, "successful_writes": 3,
                    "notifications": counts.notification, "subjects": counts.subject, "silent_paste_feedback": counts.paste, "capture_feedback_after_poll": counts.copy,
                    "monitor_polled": registered])
                if let monitor {
                    // Same public image-add/write sequence as ScreenshotCoordinator.complete.
                    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    let png = bitmap.representation(using: .png, properties: [:])!
                    let screenshot = ClipboardItem(kind: .image, sourceName: "Private screenshot fixture",
                        payloads: ["public.png": png])
                    let imageID = try store.add(screenshot)
                    try store.writeToPasteboard(ids: [imageID], pasteboard: board, plainTextOnly: false)
                    monitor.poll()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                    try require(counts.paste == 4 && counts.copy == 0,
                        "Screenshot path must produce one restore sound and no monitor echo")
                    // Real timer/read/capture pipeline, two independent external clipboard writes.
                    for index in 1...2 {
                        board.clearContents()
                        try require(board.setString("external private copy \(index)", forType: .string), "Private copy failed")
                        monitor.poll()
                        let deadline = Date().addingTimeInterval(1.5)
                        while counts.copy < index && Date() < deadline {
                            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                        }
                        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                        try require(counts.copy == index && counts.paste == 4,
                            "Each distinct external copy must produce exactly one capture sound")
                    }
                    results.append(["screenshot_writes": 1, "screenshot_restore_feedback": 1,
                        "screenshot_capture_echo": 0, "independent_external_copies": 2,
                        "external_copy_feedback": counts.copy, "real_monitor_timer_pipeline": true])
                }
            }
        }
        print(String(data: try JSONSerialization.data(withJSONObject: ["passed": true, "cases": results,
            "scope": "Production public writeToPasteboard calls; private named pasteboards only; per-instance failure override; injected silent sound callback. Closure non-entry supported by source guard order, not directly instrumented."], options: [.sortedKeys]), encoding: .utf8)!)
    }
}
