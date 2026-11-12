import CoreData
import Foundation

// The original NSManagedObject category supplies nil defaults; concrete entities override them.
@objc(BlinkClipManagedObject)
class BlinkClipManagedObject: NSManagedObject {
    class var entityName: String { String(describing: self) }
    @objc class var defaultSortDescriptors: [NSSortDescriptor]? { nil }
    @objc class var defaultPredicate: NSPredicate? { nil }

    // 3b4984: local edits advance updatedAt; inserted/syncApply/unchanged objects do not.
    override func willSave() {
        let isSyncApply = managedObjectContext?.transactionAuthor == "syncApply"
        if !isInserted && !isSyncApply && !changedValues().isEmpty {
            setPrimitiveValue(Date(), forKey: "updatedAt")
        }
        super.willSave()
    }

}

// a dedicated managed Item type with the original class defaults.
@objc(BlinkClipItemEntity)
class BlinkClipItemEntity: BlinkClipManagedObject {
    // Keep the existing local store's physical entity name for persisted IDs and relationships.
    override class var entityName: String { "Item" }
    override class var defaultSortDescriptors: [NSSortDescriptor]? {
        [NSSortDescriptor(key: "timestamp", ascending: false)]
    }

    // 3b4888: creation time is independent of the history timestamp and later recency changes.
    override func awakeFromInsert() {
        super.awakeFromInsert()
        setPrimitiveValue(Date(), forKey: "createdAt")
    }

    // Item-specific wrapper around the same generic request factory.
    static func defaultFetchRequest() -> NSFetchRequest<BlinkClipItemEntity> {
        ManagedFetchRequest.make(for: BlinkClipItemEntity.self)
    }
}

// 32b0c8/329624: the model's actual List class supplies its own fetch defaults.
@objc(BlinkClipListEntity)
class BlinkClipListEntity: BlinkClipManagedObject {
    override class var entityName: String { "ListEntity" }
    override class var defaultSortDescriptors: [NSSortDescriptor]? {
        [NSSortDescriptor(key: "metadata.index", ascending: true)]
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        setPrimitiveValue(Date(), forKey: "createdAt")
    }

    static func listFetchRequest() -> NSFetchRequest<BlinkClipListEntity> {
        ManagedFetchRequest.make(for: BlinkClipListEntity.self)
    }

    // 329980/329ec0: repair a missing relationship, then propagate the superclass error.
    override func validateForInsert() throws {
        if !isDeleted, value(forKey: "metadata") == nil, let context = managedObjectContext {
            let identifier = "list:" + String._unconditionallyBridgeFromObjectiveC(
                value(forKey: "identifier") as? NSString)
            let request = BlinkClipListMetadataEntity.metadataFetchRequest()
            request.predicate = NSPredicate(format: "identifier == %@", identifier)
            request.fetchLimit = 1
            request.fetchOffset = 0
            var existing: BlinkClipListMetadataEntity?
            context.performAndWait { existing = (try? context.fetch(request))?.first }
            if let existing {
                setValue(existing, forKey: "metadata")
            } else {
                let all = BlinkClipListMetadataEntity.metadataFetchRequest()
                all.fetchOffset = 0
                var values: [BlinkClipListMetadataEntity] = []
                context.performAndWait { values = (try? context.fetch(all)) ?? [] }
                let lastIndex: Int64
                if let last = values.last {
                    lastIndex = (last.value(forKey: "index") as? NSNumber)?.int64Value ?? 0
                } else {
                    lastIndex = -1
                }
                let nextIndex = lastIndex + 1
                let metadata = BlinkClipListMetadataEntity(context: context)
                metadata.setValue(identifier, forKey: "identifier")
                metadata.setValue(self, forKey: "list")
                metadata.setValue(nextIndex, forKey: "index")
                setValue(metadata, forKey: "metadata")
            }
        }
        try super.validateForInsert()
    }
}

// 32b6a8/32b4b4: metadata has a separate class and index ordering.
@objc(BlinkClipListMetadataEntity)
class BlinkClipListMetadataEntity: BlinkClipManagedObject {
    override class var entityName: String { "ListMetadataEntity" }
    override class var defaultSortDescriptors: [NSSortDescriptor]? {
        [NSSortDescriptor(key: "index", ascending: true)]
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        setPrimitiveValue(Date(), forKey: "createdAt")
    }

    static func metadataFetchRequest() -> NSFetchRequest<BlinkClipListMetadataEntity> {
        ManagedFetchRequest.make(for: BlinkClipListMetadataEntity.self)
    }
}

// Source entities share the native local save callback and initialize their own creation date.
@objc(BlinkClipApplicationEntity)
class BlinkClipApplicationEntity: BlinkClipManagedObject {
    override class var entityName: String { "ApplicationEntity" }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        setPrimitiveValue(Date(), forKey: "createdAt")
    }
}

@objc(BlinkClipDeviceEntity)
class BlinkClipDeviceEntity: BlinkClipManagedObject {
    override class var entityName: String { "DeviceEntity" }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        setPrimitiveValue(Date(), forKey: "createdAt")
    }
}

enum ManagedFetchRequest {
    // entity name, class sort/predicate defaults, then batch size.
    static func make<Entity: BlinkClipManagedObject>(for entity: Entity.Type) -> NSFetchRequest<Entity> {
        let request = NSFetchRequest<Entity>(entityName: entity.entityName)
        request.sortDescriptors = entity.defaultSortDescriptors
        request.predicate = entity.defaultPredicate
        request.fetchBatchSize = 20
        return request
    }
}
