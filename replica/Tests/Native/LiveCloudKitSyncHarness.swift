import CloudKit
import Foundation
import BlinkClipCore

/// Explicitly signed test process, separate temporary stores and an allowlisted random zone.
/// No system pasteboard, installed application's store, or existing cloud record zone is opened.
@main
struct LiveCloudKitSyncHarness {
    struct Failure: Error { let message: String }
    @MainActor static func main() async {
        guard ProcessInfo.processInfo.environment["BLINKCLIP_CLOUDKIT_ALLOW_LIVE_TEST"] == "1" else {
            print("BLOCKED: 必须显式启用合成数据 CloudKit 测试。 "); exit(2)
        }
        do { try await run() }
        catch { print("FAIL: \(error)"); exit(1) }
    }
    @MainActor static func verifyCompleteSchema(database: CKDatabase, zoneName: String, root: URL) async throws {
        let zoneID = CKRecordZone.ID(zoneName: zoneName)
        _ = try await database.save(CKRecordZone(zoneID: zoneID))
        let ids = Dictionary(uniqueKeysWithValues: CloudKitSchema.recordTypes.map {
            ($0, CloudRecordID(name: "schema-\($0)", zone: zoneName))
        })
        let relationships = ["data": "ItemDataEntity", "device": "DeviceEntity", "list": "ListEntity",
                             "sourceApplication": "ApplicationEntity", "metadata": "ListMetadataEntity", "item": "ItemEntity"]
        let integers: Set<String> = ["rawType", "rawColor", "displayOrderInPinboard", "index"]
        let dates: Set<String> = ["createdAt", "updatedAt", "timestamp"]
        let binary: Set<String> = ["rawIcon", "rawPreview", "rawShareRecord", "rawAttributes"]
        let records = try CloudKitSchema.recordTypes.sorted().map { type -> CKRecord in
            var fields: [String: CloudField] = [:]
            for field in CloudKitSchema.fields[type, default: []] {
                if let target = relationships[field] { fields[field] = .reference(ids[target]!, deleteSelf: false) }
                else if field == "items" { fields[field] = .array([.reference(ids["ItemEntity"]!, deleteSelf: false)]) }
                else if field == "rawPasteboardItems" { fields[field] = .asset(Data("schema synthetic asset".utf8)) }
                else if integers.contains(field) { fields[field] = .integer(1) }
                else if dates.contains(field) { fields[field] = .date(Date()) }
                else if binary.contains(field) { fields[field] = .data(Data("synthetic schema field".utf8)) }
                else { fields[field] = .string("synthetic \(field)") }
            }
            return try CloudKitRecordCodec.encode(CloudDocument(id: ids[type]!, type: type, fields: fields),
                                                   assetDirectory: root.appendingPathComponent("schema-assets"))
        }
        let results = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: true)
        for result in results.saveResults.values { _ = try result.get() }
        guard results.saveResults.count == CloudKitSchema.recordTypes.count else { throw Failure(message: "完整 schema 写入未覆盖六类实体") }
        print("SCHEMA: all six record types and every declared field accepted"); fflush(stdout)
    }

    @MainActor static func run() async throws {
        let configuration = try BlinkClipCloudKitConfiguration.current()
        let expectedEnvironment = ProcessInfo.processInfo.environment["BLINKCLIP_CLOUDKIT_TEST_ENVIRONMENT"] ?? "Development"
        guard ["Development", "Production"].contains(expectedEnvironment), configuration.environment == expectedEnvironment else {
            throw Failure(message: "实际 CloudKit 签名环境与显式请求的测试环境不匹配")
        }
        let artifactRoot = ProcessInfo.processInfo.environment["ARTIFACT_TASK_DIR"].map {
            URL(fileURLWithPath: $0).appendingPathComponent("build")
        } ?? FileManager.default.temporaryDirectory
        let root = artifactRoot.appendingPathComponent("BlinkClipCloudKitLive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let zoneName = "BlinkClip-Verification-\(UUID().uuidString)"
        let database = CKContainer(identifier: configuration.containerIdentifier).privateCloudDatabase
        let leftovers = try await database.allRecordZones().map { $0.zoneID.zoneName }.filter { $0.hasPrefix("BlinkClip-Verification-") }
        print("PREEXISTING SYNTHETIC ZONES: \(leftovers.sorted())"); fflush(stdout)
        if let cleanup = ProcessInfo.processInfo.environment["BLINKCLIP_CLOUDKIT_CLEANUP_ZONE"] {
            guard configuration.environment == "Development", leftovers.contains(cleanup),
                  cleanup.hasPrefix("BlinkClip-Verification-"),
                  UUID(uuidString: String(cleanup.dropFirst("BlinkClip-Verification-".count))) != nil else {
                throw Failure(message: "拒绝清理未明确列出的开发环境合成区域")
            }
            _ = try await database.deleteRecordZone(withID: CKRecordZone.ID(zoneName: cleanup))
            do { _ = try await database.deleteSubscription(withID: "\(cleanup).2") }
            catch let error as CKError where error.code == .unknownItem { }
            print("CLEANED PREVIOUS CRASH TEST: \(cleanup)"); fflush(stdout)
        }
        let a = try ClipboardStore(directoryURL: root.appendingPathComponent("a"))
        let b = try ClipboardStore(directoryURL: root.appendingPathComponent("b"))
        a.preferences.historyRetentionDays = 0; b.preferences.historyRetentionDays = 0
        _ = try a.prepareCloudKit(zoneName: zoneName); _ = try b.prepareCloudKit(zoneName: zoneName)
        _ = try a.cloudKitTransaction { $0.deviceName = "BlinkClip synthetic client A" }
        _ = try b.cloudKitTransaction { $0.deviceName = "BlinkClip synthetic client B" }
        let first = CloudKitSyncEngine(store: a, configuration: configuration, zoneName: zoneName)
        let second = CloudKitSyncEngine(store: b, configuration: configuration, zoneName: zoneName)
        first.statusChanged = { print("CLIENT A: \($0)"); fflush(stdout) }
        second.statusChanged = { print("CLIENT B: \($0)"); fflush(stdout) }
        var testError: Error?
        do {
            try await verifyCompleteSchema(database: database, zoneName: zoneName + "-Schema", root: root)
            let board = try a.createPinboard(name: "BlinkClip CloudKit 合成分组", colorHex: "#12AB89")
            let bytes = Data((0..<200_000).map { UInt8($0 % 251) })
            let id = try a.add(ClipboardItem(title: "CloudKit 合成内容", plainText: "BlinkClip cloud verification",
                payloads: ["public.utf8-plain-text": Data("BlinkClip cloud verification".utf8), "local.blinkclip.synthetic": bytes],
                pinboardIDs: [board.id], pinboardOwnerID: board.id))
            print("STAGE: upload synthetic records to \(zoneName)"); fflush(stdout)
            try await first.start(); try await first.synchronize()
            try await second.start(); try await second.synchronize()
            guard let received = b.items.first(where: { $0.id == id }), b.pinboards.contains(where: { $0.id == board.id }),
                  try ClipboardStore.originalPasteboardItems(from: received.payloads).first?.dataForType(forType: "local.blinkclip.synthetic") == bytes else {
                throw Failure(message: "真实服务端传输或附件回验失败")
            }
            do {
                let reopened = try ClipboardStore(directoryURL: b.directoryURL)
                guard let persisted = reopened.items.first(where: { $0.id == id }),
                      try ClipboardStore.originalPasteboardItems(from: persisted.payloads).first?
                        .dataForType(forType: "local.blinkclip.synthetic") == bytes else {
                    throw Failure(message: "重新打开磁盘 Store 后附件字节不一致")
                }
                print("PERSISTENCE: reopened Store attachment bytes verified"); fflush(stdout)
            }
            let index = b.items.firstIndex(where: { $0.id == id })!
            b.items[index].title = "CloudKit 更新验证"; b.items[index].updatedAt = Date(); try b.save()
            try await second.synchronize(); try await first.synchronize()
            guard a.items.first(where: { $0.id == id })?.title == "CloudKit 更新验证" else { throw Failure(message: "真实更新回验失败") }
            print("STAGE: concurrent title conflict"); fflush(stdout)
            let firstIndex = a.items.firstIndex(where: { $0.id == id })!
            let olderEdit = Date()
            a.items[firstIndex].title = "synthetic earlier edit"; a.items[firstIndex].updatedAt = olderEdit; try a.save()
            b.items[index].title = "synthetic later edit"; b.items[index].updatedAt = olderEdit.addingTimeInterval(1); try b.save()
            try await first.synchronize(); try await second.synchronize(); try await first.synchronize()
            guard a.items.first(where: { $0.id == id })?.title == "synthetic later edit",
                  b.items.first(where: { $0.id == id })?.title == "synthetic later edit" else {
                throw Failure(message: "真实并发标题冲突未收敛")
            }
            print("STAGE: stopped client edits and restart catch-up"); fflush(stdout)
            await first.stop()
            a.items[firstIndex].title = "synthetic restart catch-up"; a.items[firstIndex].updatedAt = olderEdit.addingTimeInterval(2); try a.save()
            try await first.start(); try await first.synchronize(); try await second.synchronize()
            guard b.items.first(where: { $0.id == id })?.title == "synthetic restart catch-up" else {
                throw Failure(message: "停机编辑重启后未补传")
            }
            print("STAGE: item and parent group deletion"); fflush(stdout)
            b.items.removeAll { $0.id == id }; try b.save()
            try await second.synchronize(); try await first.synchronize()
            guard !a.items.contains(where: { $0.id == id }) else { throw Failure(message: "真实删除回验失败") }
            try b.removePinboard(id: board.id)
            try await second.synchronize(); try await first.synchronize()
            guard !a.pinboards.contains(where: { $0.id == board.id }) else { throw Failure(message: "真实分组删除回验失败") }
        } catch { testError = error }
        await first.stop(); await second.stop()
        for name in [zoneName, zoneName + "-Schema"] {
            do { _ = try await database.deleteRecordZone(withID: CKRecordZone.ID(zoneName: name)) }
            catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem { }
            catch { throw Failure(message: "测试区域清理失败：\(name)，\(error.localizedDescription)") }
        }
        do { _ = try await database.deleteSubscription(withID: "\(zoneName).2") }
        catch let error as CKError where error.code == .unknownItem { }
        catch { throw Failure(message: "测试订阅清理失败：\(zoneName).2，\(error.localizedDescription)") }
        if let testError { throw testError }
        let report: [String: Any] = ["passed": true, "actualCloudKitService": true, "clients": 2, "physicalMacs": 1,
            "environment": configuration.environment, "syntheticOnly": true, "zoneCleaned": true,
            "allRecordTypesAndFields": true, "attachmentBytesVerified": true, "concurrentTitleConflict": true,
            "stoppedClientCatchUp": true, "itemAndGroupDeletion": true, "physicalNetworkDisconnected": false,
            "reopenedStoreAttachmentBytes": true]
        print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: .sortedKeys), as: UTF8.self))
    }
}
