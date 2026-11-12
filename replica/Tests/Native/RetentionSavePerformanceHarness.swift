import Foundation
import CloudKit
import CryptoKit
import BlinkClipCore

@main struct RetentionSavePerformanceHarness {
    struct Failure: Error { let message: String }
    static var checks = 0
    static func check(_ value: Bool, _ message: String) throws {
        checks += 1
        if !value { throw Failure(message: message) }
    }
    struct Seed: Encodable {
        let schemaVersion = 1
        var items: [ClipboardItem]
        var pinboards: [Pinboard] = []
        var preferences: AppPreferences
        let sourceApplications: [SourceApplicationRecord] = []
    }
    @MainActor static func main() throws {
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--peer-write" {
            let store = try ClipboardStore(directoryURL: URL(fileURLWithPath: CommandLine.arguments[2]))
            store.preferences.playSounds = false
            try store.save()
            return
        }
        let task = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"]!)
        if ProcessInfo.processInfo.environment["BLINKCLIP_RETENTION_GRAPH_DIAGNOSTIC"] == "1" {
            try graphEquivalence(items: (0..<3).map { ClipboardItem(title: "Synthetic \($0)", plainText: "Synthetic \($0)", payloads: ["public.utf8-plain-text": Data("Synthetic \($0)".utf8)]) })
            print("Diagnostic capture complete; no Store or timing claim")
            return
        }
        let count = Int(ProcessInfo.processInfo.environment["BLINKCLIP_RETENTION_PERF_ITEMS"] ?? "256")!
        precondition([256, 1024].contains(count))
        let payloadBytes = Int(ProcessInfo.processInfo.environment["BLINKCLIP_RETENTION_PERF_BYTES"] ?? "8388608")!
        precondition([8388608, 33554432].contains(payloadBytes))
        let variant = ProcessInfo.processInfo.environment["BLINKCLIP_RETENTION_PERF_VARIANT"] ?? "current"
        precondition(["baseline", "indexed", "current"].contains(variant))
        let directory = task.appendingPathComponent("build/fixture-\(variant)-\(count)-\(payloadBytes)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var preferences = AppPreferences()
        preferences.historyRetentionDays = 0
        let items = (0..<count).map { i in
            ClipboardItem(title: "Synthetic \(i)", plainText: "Synthetic \(i)",
                payloads: ["public.utf8-plain-text": Data("Synthetic \(i)".utf8),
                           "local.synthetic.blob": Data(repeating: UInt8(i % 251), count: payloadBytes / count)])
        }
        try JSONEncoder().encode(Seed(items: items, preferences: preferences))
            .write(to: directory.appendingPathComponent("clipboard.json"))
        let store = try ClipboardStore(directoryURL: directory)
        var results: [[String: Any]] = []
        for cloud in [false, true] {
            if cloud { _ = try store.prepareCloudKit() }
            for round in 1...3 { for days in [7, 30, 3, 60, 0] {
                let start = Date()
                store.preferences.historyRetentionDays = days
                let assigned = Date()
                try store.save()
                results.append(["cloudKitJournal": cloud, "days": days, "round": round,
                    "assignSeconds": assigned.timeIntervalSince(start),
                    "saveSeconds": Date().timeIntervalSince(assigned),
                    "itemCount": store.items.count])
            } }
        }
        try check(store.items.count == count, "unexpired items remain")
        try graphEquivalence(items: Array(store.items.prefix(3)))
        try behavior(task: task, variant: variant, suffix: "\(count)-\(payloadBytes)")
        let output: [String: Any] = ["variant": variant, "items": count, "checks": checks,
            "buildMode": "release (-O)", "syntheticOnly": true,
            "syntheticPayloadBytes": payloadBytes, "measurements": results,
            "scope": "MainActor synchronous shipping Store.save; isolated synthetic store only; no UI/defaults/TCC/monitor/network"]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: task.appendingPathComponent("out/\(variant)-\(count)-\(payloadBytes).json"))
        print(String(decoding: data, as: UTF8.self))
    }

    static func graphEquivalence(items: [ClipboardItem]) throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var journal = CloudKitJournal()
        journal.deviceName = "Synthetic Mac"
        let cases: [(String, CloudKitJournal)] = [("empty", journal)]
        func compare(_ label: String, _ journal: CloudKitJournal,
                     items: [ClipboardItem], boards: [Pinboard] = []) throws {
            let a = try BaselineCloudKitGraph.capture(items: items, pinboards: boards, applications: [], capacity: 15, journal: journal, now: now, previousItems: items)
            let b = try CloudKitGraph.capture(items: items, pinboards: boards, applications: [], capacity: 15, journal: journal, now: now, previousItems: items)
            if ProcessInfo.processInfo.environment["BLINKCLIP_RETENTION_GRAPH_DIAGNOSTIC"] == "1" {
                func diff(_ x: [CloudDocument], _ y: [CloudDocument]) -> [[String: Any]] {
                    var result: [[String: Any]] = []
                    if x.count != y.count { result.append(["countLeft": x.count, "countRight": y.count]) }
                    for (left, right) in zip(x, y) where left != right {
                        var entry: [String: Any] = ["leftID": left.id.key, "rightID": right.id.key, "leftType": left.type, "rightType": right.type, "leftScope": String(describing: left.scope), "rightScope": String(describing: right.scope), "sameParent": left.parent == right.parent, "sameSystemFields": left.systemFields == right.systemFields]
                        var fields: [[String: Any]] = []
                        for key in Set(left.fields.keys).union(right.fields.keys).sorted() where left.fields[key] != right.fields[key] {
                            var field: [String: Any] = ["field": key]
                            if let a = left.fields[key]?.bytes, let b = right.fields[key]?.bytes {
                                field["leftSHA"] = SHA256.hash(data: a).map { String(format: "%02x", $0) }.joined()
                                field["rightSHA"] = SHA256.hash(data: b).map { String(format: "%02x", $0) }.joined()
                                if key == "rawAttributes" {
                                    field["leftUTF8"] = String(data: a, encoding: .utf8)
                                    field["rightUTF8"] = String(data: b, encoding: .utf8)
                                    if let ao = try? JSONSerialization.jsonObject(with: a) as? NSDictionary, let bo = try? JSONSerialization.jsonObject(with: b) as? NSDictionary { field["jsonObjectsEqual"] = ao == bo }
                                }
                            } else {
                                field["left"] = String(describing: left.fields[key])
                                field["right"] = String(describing: right.fields[key])
                            }
                            fields.append(field)
                        }
                        entry["fields"] = fields; result.append(entry)
                    }
                    return result
                }
                var oldOld: [[[String: Any]]] = []
                for _ in 0..<32 {
                    let again = try BaselineCloudKitGraph.capture(items: items, pinboards: boards, applications: [], capacity: 15, journal: journal, now: now, previousItems: items)
                    oldOld.append(diff(a, again))
                }
                let report: [String: Any] = ["diagnosticOnly": true, "case": label, "oldVersusCurrent": diff(a, b), "oldOldRepeats": oldOld, "oldOldMismatches": oldOld.filter { !$0.isEmpty }.count]
                let path = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"]!).appendingPathComponent("out/diagnostic-\(label).json")
                try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path)
                return
            }
            try check(a == b, "complete graph equality: \(label)")
            var old = journal, indexed = journal
            var oldError: String?, indexedError: String?
            do { try old.capture(a) } catch { oldError = String(describing: error) }
            do { try indexed.capture(b) } catch { indexedError = String(describing: error) }
            try check(oldError == indexedError, "journal error parity: \(label)")
            try check(old == indexed, "complete journal equality including errors: \(label)")
        }
        for (name, value) in cases { try compare(name, value, items: items) }
        try journal.capture(try BaselineCloudKitGraph.capture(items: items, pinboards: [], applications: [], capacity: 7, journal: journal, now: now))
        try compare("existing", journal, items: items)
        let peer = CloudDocument(id: CloudRecordID(name: "peer", zone: journal.zoneName), type: "DeviceEntity", fields: ["identifier": .string("peer"), "name": .string("Peer"), "rawType": .integer(1)])
        journal.documents[CloudKitJournal.key(peer.id, scope: peer.scope)] = peer
        if let item = items.first {
            for (zone, owner) in [(journal.zoneName, CKCurrentUserDefaultName), ("OtherZone", "OtherOwner")] {
                let id = CloudRecordID(name: item.id.uuidString.lowercased(), zone: zone, owner: owner)
                journal.documents[CloudKitJournal.key(id, scope: .private)] = CloudDocument(id: id, type: "ItemEntity", fields: [:])
            }
            let bad = CloudRecordID(name: "not-a-uuid", zone: journal.zoneName)
            journal.documents[CloudKitJournal.key(bad, scope: .private)] = CloudDocument(id: bad, type: "ItemEntity", fields: [:])
            let sameID = CloudRecordID(name: item.id.uuidString, zone: journal.zoneName)
            journal.documents["fixture.other-type"] = CloudDocument(id: sameID, type: "ApplicationEntity", fields: ["bundleIdentifier": .string(item.id.uuidString)])
        }
        try compare("duplicates-zone-owner-invalid-type-peer", journal, items: items)
        let sharedList = CloudDocument(id: CloudRecordID(name: "shared-board", zone: "SharedZone", owner: "owner"), type: "ListEntity", scope: .shared, fields: [:])
        let sharedItem = CloudDocument(id: CloudRecordID(name: "shared-item", zone: "SharedZone", owner: "owner"), type: "ItemEntity", scope: .shared, fields: [:])
        let boardID = CloudKitGraph.localID(sharedList)!, itemID = CloudKitGraph.localID(sharedItem)!
        var shared = CloudKitJournal(); shared.deviceName = "Synthetic Mac"
        for value in [sharedList, sharedItem] { shared.documents[CloudKitJournal.key(value.id, scope: value.scope)] = value }
        // Supply the same persisted attribute bytes to both captures. The
        // unchanged encoder can vary JSON key order when attributes are absent;
        // diagnostic mode intentionally retains that input to expose old-old
        // nondeterminism, while normal equivalence remains fully byte-exact.
        let attributes = ProcessInfo.processInfo.environment["BLINKCLIP_RETENTION_GRAPH_DIAGNOSTIC"] == "1"
            ? nil : try BaselinePinboardAttributes.encoded(colorCode: 0xFF9500)
        let board = Pinboard(id: boardID, name: "Shared", rawType: 2, rawAttributes: attributes)
        let value = ClipboardItem(id: itemID, title: "Shared item", plainText: "Shared", payloads: ["public.utf8-plain-text": Data("Shared".utf8)], pinboardIDs: [boardID], pinboardOwnerID: boardID)
        try compare("shared-private", shared, items: items + [value], boards: [board])
    }

    @MainActor static func behavior(task: URL, variant: String, suffix: String) throws {
        let directory = task.appendingPathComponent("build/behavior-\(variant)-\(suffix)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let board = Pinboard(name: "Protected group", rawType: 2)
        let old = Date(timeIntervalSinceNow: -80 * 86400)
        let expired = ClipboardItem(createdAt: old, title: "Expired", plainText: "Expired", payloads: ["public.utf8-plain-text": Data("Expired".utf8)])
        let grouped = ClipboardItem(createdAt: old, title: "Grouped", plainText: "Grouped", payloads: ["public.utf8-plain-text": Data("Grouped".utf8)], pinboardIDs: [board.id], pinboardOwnerID: board.id)
        let recent = ClipboardItem(title: "Recent", plainText: "Recent", payloads: ["public.utf8-plain-text": Data("Recent".utf8)])
        var preferences = AppPreferences(); preferences.historyRetentionDays = 0
        try JSONEncoder().encode(Seed(items: [expired, grouped, recent], pinboards: [board], preferences: preferences)).write(to: directory.appendingPathComponent("clipboard.json"))
        let store = try ClipboardStore(directoryURL: directory)
        _ = try store.prepareCloudKit()
        store.preferences.historyRetentionDays = 7; try store.save()
        try check(!store.items.contains(where: { $0.id == expired.id }), "expired ungrouped removed immediately")
        try check(store.items.contains(where: { $0.id == grouped.id }) && store.items.contains(where: { $0.id == recent.id }), "grouped and recent retained")
        let journal = try store.prepareCloudKit()
        let expiredID = CloudRecordID(name: expired.id.uuidString, zone: journal.zoneName)
        try check(journal.pending[CloudKitJournal.key(expiredID, scope: .private)]?.deletion == true, "expired cloud tombstone retained")
        let child = Process(); child.executableURL = Bundle.main.executableURL!
        child.arguments = ["--peer-write", directory.path]
        child.standardOutput = Pipe(); child.standardError = Pipe()
        try child.run(); child.waitUntilExit()
        try check(child.terminationStatus == 0, "peer process saved")
        store.preferences.historyRetentionDays = 60; try store.save()
        let reopened = try ClipboardStore(directoryURL: directory)
        try check(reopened.preferences.historyRetentionDays == 60 && !reopened.preferences.playSounds, "peer revision and new retention both survive reopen")
        try check(!reopened.items.contains(where: { $0.id == expired.id }), "expiry remains removed after reopen")
    }
}
