import AppKit
import Foundation
import CoreData
import CryptoKit
import BlinkClipCore

@main struct BlinkClipLegacyMigration {
    static func hash(_ d: Data) -> String { SHA256.hash(data:d).map { String(format:"%02x",$0) }.joined() }
    static func json<T: Encodable>(_ x:T) throws -> Data { let e=JSONEncoder(); e.outputFormatting=[.prettyPrinted,.sortedKeys]; return try e.encode(x) }
    static func value(_ x:Any?) -> Any {
        guard let x else { return NSNull() }
        if let x=x as? Data { return ["bytes":x.count,"sha256":hash(x),"base64":x.base64EncodedString()] }
        if let x=x as? Date { return ["date":x.timeIntervalSince1970] }
        if let x=x as? UUID { return x.uuidString }
        if let x=x as? URL { return x.absoluteString }
        if let x=x as? NSManagedObject { return x.objectID.uriRepresentation().absoluteString }
        if let x=x as? NSSet { return x.allObjects.map { String(describing:value($0)) }.sorted() }
        if let x=x as? NSOrderedSet { return x.array.map(value) }
        if let x=x as? String { return x }
        if let x=x as? NSNumber { return x }
        return String(describing:x)
    }
    static func context(_ store:ClipboardStore) throws -> NSManagedObjectContext {
        guard let p=Mirror(reflecting:store).children.first(where:{$0.label=="persistence"})?.value,
          let c=Mirror(reflecting:p).children.first(where:{$0.label=="context"})?.value as? NSManagedObjectContext else { throw NSError(domain:"fixture-reflection",code:1) }
        return c
    }

    static func sameJSON(_ a: Data,_ b: Data) throws -> Bool {
        let x=try JSONSerialization.jsonObject(with:a), y=try JSONSerialization.jsonObject(with:b)
        return (x as AnyObject).isEqual(y)
    }
    static func require(_ ok: Bool,_ label: String) throws { if !ok { throw NSError(domain:label,code:1) } }
    @MainActor static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let out=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
        let dir=root.appendingPathComponent("legacy-store",isDirectory:true)
        let manifest=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("manifest.json"))) as! [String:Any]
        var checks:[String]=[]
        func check<T:Encodable>(_ value:T,_ filename:String) throws {
            try require(try sameJSON(json(value),Data(contentsOf:root.appendingPathComponent(filename))),filename)
            checks.append(filename)
        }
        var store=try ClipboardStore(directoryURL:dir)
        try check(store.items,"reopened-items.json")
        try check(store.pinboards,"reopened-pinboards.json")
        try check(store.preferences,"reopened-preferences.json")
        try check(store.sourceApplications,"applications.json")
        let ctx=try context(store)
        let model=ctx.persistentStoreCoordinator!.managedObjectModel
        var schema:[[String:Any]]=[];var objects:[[String:Any]]=[]
        for e in model.entities.sorted(by:{$0.name!<$1.name!}) {
            schema.append(["name":e.name!,"managedObjectClassName":e.managedObjectClassName ?? "","versionHash":e.versionHash.base64EncodedString(),"attributes":e.attributesByName.mapValues { ["type":$0.attributeType.rawValue,"optional":$0.isOptional] },"relationships":e.relationshipsByName.mapValues { ["destination":$0.destinationEntity?.name ?? "","toMany":$0.isToMany,"optional":$0.isOptional,"inverse":$0.inverseRelationship?.name ?? ""] }])
            for obj in try ctx.fetch(NSFetchRequest<NSManagedObject>(entityName:e.name!)) {
                var fields:[String:Any]=[:]
                for key in e.attributesByName.keys.sorted() { fields[key]=value(obj.value(forKey:key)) }
                for key in e.relationshipsByName.keys.sorted() { fields[key]=value(obj.value(forKey:key)) }
                objects.append(["entity":e.name!,"objectID":obj.objectID.uriRepresentation().absoluteString,"runtimeClass":NSStringFromClass(type(of:obj)),"fields":fields])
            }
        }
        let rows=objects.sorted { String(describing:$0["objectID"]!)<String(describing:$1["objectID"]!) }
        for (label,actual) in [("schema",schema),("objects",rows)] {
            try require(try sameJSON(JSONSerialization.data(withJSONObject:actual),JSONSerialization.data(withJSONObject:manifest[label]!)),label)
            checks.append(label)
        }
        let oldArchive=try Data(contentsOf:root.appendingPathComponent("original-items.nskeyedarchive"))
        try require(hash(oldArchive)==manifest["archiveSHA256"] as! String,"original-archive-sha256")
        let decoded=try PasteboardArchive.decodeItems(oldArchive)
        try require(decoded.count==1,"archive-count")
        try require(NSStringFromClass(PasteboardItem.self)==manifest["archiveRuntimeClass"] as! String,"archive-runtime")
        let encoded=try PasteboardArchive.encodeItems(decoded)
        let roundtrip=try PasteboardArchive.decodeItems(encoded)
        try require(roundtrip[0].dataForType(forType:"public.rtf")==decoded[0].dataForType(forType:"public.rtf"),"archive-roundtrip-payload")
        // Rewrite only class metadata in copied archive; all four historical aliases must decode.
        let aliases=["PasteCore.PasteboardItem","_TtC9PasteCore14PasteboardItem","BlinkClipCore.PasteboardItem","_TtC9BlinkClipCore22PasteboardItem"]
        for alias in aliases {
            var plist=try PropertyListSerialization.propertyList(from:oldArchive,options:[],format:nil) as! [String:Any]
            var values=plist["$objects"] as! [Any]
            for index in values.indices {
                if var value=values[index] as? [String:Any],value["$classname"] as? String=="_TtC9PasteCore14PasteboardItem" {
                    value["$classname"]=alias
                    if var classes=value["$classes"] as? [String] { classes[0]=alias;value["$classes"]=classes }
                    values[index]=value
                }
            }
            plist["$objects"]=values
            let data=try PropertyListSerialization.data(fromPropertyList:plist,format:.binary,options:0)
            let result=try PasteboardArchive.decodeItems(data)
            try require(result.count==1 && result[0].dataForType(forType:"public.rtf")==decoded[0].dataForType(forType:"public.rtf"),"archive-alias-"+alias)
        }
        checks.append("archive runtime + old decode + 4 aliases + new encode/decode payload")
        try store.save()
        for s in ctx.persistentStoreCoordinator!.persistentStores { try ctx.persistentStoreCoordinator!.remove(s) }
        store=try ClipboardStore(directoryURL:dir)
        try check(store.items,"reopened-items.json")
        try check(store.pinboards,"reopened-pinboards.json")
        try check(store.preferences,"reopened-preferences.json")
        let ctx2=try context(store)
        let model2=ctx2.persistentStoreCoordinator!.managedObjectModel
        var schema2:[[String:Any]]=[];var objects2:[[String:Any]]=[]
        for e in model2.entities.sorted(by:{$0.name!<$1.name!}) {
            schema2.append(["name":e.name!,"managedObjectClassName":e.managedObjectClassName ?? "","versionHash":e.versionHash.base64EncodedString(),"attributes":e.attributesByName.mapValues { ["type":$0.attributeType.rawValue,"optional":$0.isOptional] },"relationships":e.relationshipsByName.mapValues { ["destination":$0.destinationEntity?.name ?? "","toMany":$0.isToMany,"optional":$0.isOptional,"inverse":$0.inverseRelationship?.name ?? ""] }])
            for obj in try ctx2.fetch(NSFetchRequest<NSManagedObject>(entityName:e.name!)) {
                var fields:[String:Any]=[:]
                for key in e.attributesByName.keys.sorted() { fields[key]=value(obj.value(forKey:key)) }
                for key in e.relationshipsByName.keys.sorted() { fields[key]=value(obj.value(forKey:key)) }
                objects2.append(["entity":e.name!,"objectID":obj.objectID.uriRepresentation().absoluteString,"runtimeClass":NSStringFromClass(type(of:obj)),"fields":fields])
            }
        }
        let rows2=objects2.sorted { String(describing:$0["objectID"]!)<String(describing:$1["objectID"]!) }
        for (label,actual) in [("schema",schema2),("objects",rows2)] {
            try require(try sameJSON(JSONSerialization.data(withJSONObject:actual),JSONSerialization.data(withJSONObject:manifest[label]!)),label)
            checks.append(label)
        }
        let oldMetadata=try PropertyListSerialization.propertyList(from:Data(contentsOf:root.appendingPathComponent("store-metadata.plist")),options:[],format:nil) as! NSDictionary
        let newMetadata=ctx2.persistentStoreCoordinator!.metadata(for:ctx2.persistentStoreCoordinator!.persistentStores[0]) as NSDictionary
        try require(oldMetadata.isEqual(newMetadata),"post-save-store-model-metadata")
        let payloadHashes=store.items.map { ["id":$0.id.uuidString,"payloads":$0.payloads.mapValues { ["sha256":hash($0),"bytes":$0.count] }] }
        try require(try sameJSON(JSONSerialization.data(withJSONObject:payloadHashes),JSONSerialization.data(withJSONObject:manifest["payloadHashes"]!)),"post-save-all-payload-byteshash")
        try require(hash(Data(contentsOf:root.appendingPathComponent("original-items.nskeyedarchive")))==manifest["archiveSHA256"] as! String,"post-save-original-archive-byteshash")
        checks.append("post-save all native objects/schema/runtime/relationships/model metadata/payload/archive byteshash")
        for s in ctx2.persistentStoreCoordinator!.persistentStores { try ctx2.persistentStoreCoordinator!.remove(s) }
        try JSONSerialization.data(withJSONObject:["status":"pass","module":"BlinkClipCore","checks":checks,"objects":objects.count,"entities":schema.count,"limitations":["No user store/TCC/pasteboard/cloud access","Saved AppIntent shortcuts and SMAppService runtime not tested"]],options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("legacy-migration.json"))
        print("BLINKCLIP_OLD_STORE_SAVE_REOPEN_PASS objects=\(objects.count) entities=\(schema.count)")
    }
}
