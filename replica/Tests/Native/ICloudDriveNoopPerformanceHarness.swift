import AppKit
import Darwin
import Foundation
import BlinkClipCore

@main
struct ICloudDriveNoopPerformanceHarness {
    struct Failure: Error { let message: String }
    static var checks = 0

    static func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message: message) }
        checks += 1
    }

    static func processCPU() -> Double {
        var value = timespec()
        precondition(clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &value) == 0)
        return Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000
    }

    static func measure(_ operation: () async throws -> Void) async rethrows -> [String: Double] {
        let wall = Date()
        let cpu = processCPU()
        try await operation()
        return ["wallSeconds": Date().timeIntervalSince(wall), "processCPUSeconds": processCPU() - cpu]
    }

    @MainActor static func main() async {
        do { try await run() }
        catch {
            let data = try! JSONSerialization.data(withJSONObject: ["passed": false, "error": String(describing: error)])
            print(String(decoding: data, as: UTF8.self))
            exit(1)
        }
    }

    @MainActor static func run() async throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"]!)
        let scratch = root.appendingPathComponent("build/noop-performance", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let store = try ClipboardStore(directoryURL: scratch.appendingPathComponent("store"))
        store.preferences.historyRetentionDays = 0
        let payloadBytes = 16 * 1024 * 1024
        _ = try store.add(ClipboardItem(title: "Synthetic transport benchmark", plainText: "Synthetic transport benchmark",
                                       payloads: ["local.synthetic.binary": Data(repeating: 0x5A, count: payloadBytes)]))
        let snapshot = try store.prepareICloudSync()
        let transport = ICloudDriveSyncTransport()
        let shippingFolder = scratch.appendingPathComponent("shipping", isDirectory: true)
        try FileManager.default.createDirectory(at: shippingFolder, withIntermediateDirectories: true)
        let file = shippingFolder.appendingPathComponent("BlinkClipSync-v1/\(snapshot.deviceID.uuidString).json")
        try await transport.write(snapshot, to: shippingFolder)
        let original = try Data(contentsOf: file)
        let sentinel = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: sentinel], ofItemAtPath: file.path)
        var shippingTimes: [[String: Double]] = []
        for _ in 0..<3 { shippingTimes.append(try await measure { try await transport.write(snapshot, to: shippingFolder) }) }
        try check(try Data(contentsOf: file) == original, "No-op altered document bytes")
        try check(try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == sentinel,
                  "No-op altered the document modification date")

        var changed = snapshot
        let itemIndex = changed.records.firstIndex { $0.entity?.item != nil }!
        changed.records[itemIndex].entity!.item!.title = "Changed synthetic item"
        try await transport.write(changed, to: shippingFolder)
        try check(try JSONDecoder().decode(ICloudSyncSnapshot.self, from: Data(contentsOf: file)) == changed,
                  "Changed outgoing snapshot was not written")
        try original.write(to: file, options: .atomic)
        try await transport.write(changed, to: shippingFolder)
        try check(try JSONDecoder().decode(ICloudSyncSnapshot.self, from: Data(contentsOf: file)) == changed,
                  "External valid document replacement was not repaired")
        try Data("{broken".utf8).write(to: file, options: .atomic)
        try await transport.write(changed, to: shippingFolder)
        try check(try JSONDecoder().decode(ICloudSyncSnapshot.self, from: Data(contentsOf: file)) == changed,
                  "Corrupt existing document was not repaired")
        try check((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600,
                  "Cloud document permissions changed")

        let linkedFolder = scratch.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: linkedFolder, withIntermediateDirectories: true)
        let linkedData = linkedFolder.appendingPathComponent("BlinkClipSync-v1", isDirectory: true)
        try FileManager.default.createDirectory(at: linkedData, withIntermediateDirectories: true)
        let victim = scratch.appendingPathComponent("link-victim.txt")
        let victimData = Data("untouched synthetic victim".utf8)
        try victimData.write(to: victim)
        try FileManager.default.createSymbolicLink(at: linkedData.appendingPathComponent("\(snapshot.deviceID.uuidString).json"),
                                                   withDestinationURL: victim)
        do { try await transport.write(snapshot, to: linkedFolder); throw Failure(message: "Accepted linked destination") }
        catch is ICloudDriveSyncError { checks += 1 }
        try check(try Data(contentsOf: victim) == victimData, "Linked destination target was modified")

        let cancelFolder = scratch.appendingPathComponent("cancelled", isDirectory: true)
        try FileManager.default.createDirectory(at: cancelFolder, withIntermediateDirectories: true)
        let cancelled = Task { try await transport.write(snapshot, to: cancelFolder) }
        cancelled.cancel()
        do { try await cancelled.value; throw Failure(message: "Cancelled write continued") }
        catch is CancellationError { checks += 1 }
        try check(!FileManager.default.fileExists(atPath: cancelFolder.appendingPathComponent("BlinkClipSync-v1").path),
                  "Cancelled write created a data directory")

        let eager = EagerMeasuredICloudTransport()
        let deferred = DeferredMeasuredICloudTransport()
        let eagerFolder = scratch.appendingPathComponent("eager", isDirectory: true)
        let deferredFolder = scratch.appendingPathComponent("deferred", isDirectory: true)
        for folder in [eagerFolder, deferredFolder] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try await eager.write(snapshot, to: eagerFolder)
        try await deferred.write(snapshot, to: deferredFolder)
        var eagerTimes: [[String: Double]] = []
        var deferredTimes: [[String: Double]] = []
        // Alternate order to avoid giving one variant all warm-cache runs.
        for round in 0..<3 {
            if round.isMultiple(of: 2) {
                eagerTimes.append(try await measure { try await eager.write(snapshot, to: eagerFolder) })
                deferredTimes.append(try await measure { try await deferred.write(snapshot, to: deferredFolder) })
            } else {
                deferredTimes.append(try await measure { try await deferred.write(snapshot, to: deferredFolder) })
                eagerTimes.append(try await measure { try await eager.write(snapshot, to: eagerFolder) })
            }
        }
        let eagerCount = await eager.encodeCalls
        let deferredCount = await deferred.encodeCalls
        try check(eagerCount == 4, "Baseline did not encode initial write plus all three no-ops")
        try check(deferredCount == 1, "Deferred branch encoded an unchanged document")
        func average(_ values: [[String: Double]], _ key: String) -> Double { values.reduce(0) { $0 + $1[key]! } / Double(values.count) }
        let result: [String: Any] = [
            "passed": true, "checks": checks, "payloadBytes": payloadBytes, "documentBytes": original.count,
            "shippingNoop": shippingTimes, "baselineNoop": eagerTimes, "deferredNoop": deferredTimes,
            "baselineMeanCPUSeconds": average(eagerTimes, "processCPUSeconds"),
            "deferredMeanCPUSeconds": average(deferredTimes, "processCPUSeconds"),
            "baselineMeanWallSeconds": average(eagerTimes, "wallSeconds"),
            "deferredMeanWallSeconds": average(deferredTimes, "wallSeconds"),
            "baselineEncodeCalls": eagerCount, "deferredEncodeCalls": deferredCount,
            "limits": ["Synthetic 16 MiB payload and local directories; no real history or iCloud accessed",
                       "Shipping transport runs behavior regression and three no-op timings",
                       "Branch counters and before/after timings use exact actor extracts with counter instrumentation; baseline is reconstructed by reversing only this encoding move",
                       "No-op still reads and decodes the existing document; this does not prove all UI lag is fixed"]
        ]
        let resultData = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try resultData.write(to: root.appendingPathComponent("out/noop-performance.json"))
        print(String(decoding: resultData, as: UTF8.self))
    }
}
