import Foundation
import UniformTypeIdentifiers

/// The native path uses FileManager's temporary directory; tests can inject an isolated root.
public final class PasteboardImageRestore: @unchecked Sendable {
    private let temporaryRoot: URL?
    private let diagnostics = NamedDiagnostic.makeNamedDiagnostic(name: "PasteboardItemProcessor")

    public init(temporaryRoot: URL? = nil) {
        self.temporaryRoot = temporaryRoot
    }

    public func prepare(_ items: [PasteboardItem], sourceName: String?, timestamp: Date?) -> [PasteboardItem] {
        prepare(sourceName: sourceName, timestamp: timestamp) { items }
    }

    public func prepare(sourceName: String?, timestamp: Date?,
                        loadItems: () throws -> [PasteboardItem]) rethrows -> [PasteboardItem] {
        if let temporaryRoot {
            do {
                try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            } catch {
                diagnostics.diagnosticSink().emitFault("Error while creating temporary images directory: \(error.localizedDescription)")
            }
        }
        return try restoreImageItems(sourceName: sourceName, timestamp: timestamp, loadItems: loadItems)
    }

    // 383df4 reads entity metadata only after directory preparation and ItemData decoding.
    func prepareNative(sourceName: @autoclosure () -> String?, timestamp: @autoclosure () -> Date?,
                       loadItems: () throws -> [PasteboardItem]) rethrows -> [PasteboardItem] {
        if let temporaryRoot {
            do {
                try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
            } catch {
                diagnostics.diagnosticSink().emitFault("Error while creating temporary images directory: \(error.localizedDescription)")
            }
        }
        let directory = temporaryDirectoryURL()
        let items = try loadItems()
        guard let directory else { return items }
        return restoreImageItems(items, sourceName: sourceName(), timestamp: timestamp(), directory: directory)
    }

    public func temporaryDirectoryURL() -> URL? {
        // Calls the one-String URL append, then hasDirectoryPath,
        // not fileExists and not the isDirectory: overload. Preserve that distinction.
        let directory = (temporaryRoot ?? FileManager.default.temporaryDirectory).appendingPathComponent("images")
        if !directory.hasDirectoryPath {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            } catch {
                diagnostics.diagnosticSink().emitFault("Error while creating temporary images directory: \(error.localizedDescription)")
            }
        }
        return directory
    }

    /// Value projection of the original entity-based image preparation branch.
    public func restoreImageItems(_ items: [PasteboardItem], sourceName: String?, timestamp: Date?) -> [PasteboardItem] {
        restoreImageItems(sourceName: sourceName, timestamp: timestamp) { items }
    }

    public func restoreImageItems(sourceName: String?, timestamp: Date?,
                            loadItems: () throws -> [PasteboardItem]) rethrows -> [PasteboardItem] {
        let directory = temporaryDirectoryURL()
        let items = try loadItems()
        guard let directory else { return items }
        return restoreImageItems(items, sourceName: sourceName, timestamp: timestamp, directory: directory)
    }

    private func restoreImageItems(_ items: [PasteboardItem], sourceName: @autoclosure () -> String?,
                             timestamp: @autoclosure () -> Date?, directory: URL) -> [PasteboardItem] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = (sourceName() ?? "BlinkClip") + " " + formatter.string(from: timestamp() ?? Date.now)
        // Original uses one shared base name: equal-format items can target the same file.
        for item in items {
            for type in [UTType.png, .jpeg, .heic, .tiff] {
                guard let data = item.dataForType(forType: type.identifier) else { continue }
                let file = directory.appendingPathComponent(name, conformingTo: type)
                do {
                    try data.write(to: file, options: [])
                    item.setString(file.absoluteString, forType: UTType.fileURL.identifier)
                } catch {
                    diagnostics.diagnosticSink().emitFault("Error while writing temporary image copy to file: \(error.localizedDescription)")
                }
                // Failure exits this item's type search as well; the next item is still processed.
                break
            }
        }
        scheduleTemporaryCleanup()
        return items
    }

    public func scheduleTemporaryCleanup() {
        guard let directory = temporaryDirectoryURL() else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            Self.removeExpiredFiles(directory: directory) { self?.diagnostics }
        }
    }

    public static func removeExpiredFiles(directory: URL, diagnostics: () -> NamedDiagnostic?) {
        let cutoff = Date().addingTimeInterval(-86400)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])
            for file in files {
                guard let values = try? file.resourceValues(forKeys: [.creationDateKey]) else { continue }
                if let created = values.creationDate, created < cutoff {
                    try FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            diagnostics()?.diagnosticSink().emitFault("Error while remove old temporary image file: \(error.localizedDescription)")
        }
    }
}
