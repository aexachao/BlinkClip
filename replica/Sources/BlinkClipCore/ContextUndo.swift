import CoreData
import Foundation

/// Source counterpart of the original synchronous Undo/Redo context-save path.
@MainActor
enum ContextUndo {
    private static let diagnostics = NamedDiagnostic.makeNamedDiagnostic(name: "DB")

    // keep a successful result when there are no changes.
    @discardableResult
    static func saveContext(_ context: NSManagedObjectContext,
                           prepareForSave: (() throws -> Void)? = nil) -> Bool {
        var succeeded = true
        context.performAndWait { performContextSave(context, succeeded: &succeeded, prepareForSave: prepareForSave) }
        return succeeded
    }

    // On save failure, roll back, report failure, and log the error.
    static func performContextSave(_ context: NSManagedObjectContext, succeeded: inout Bool,
                           prepareForSave: (() throws -> Void)? = nil) {
        guard context.hasChanges else { return }
        do {
            try ObjCExceptionBridge.withResult {
                try prepareForSave?()
                try context.save()
            }
        } catch {
            context.rollback()
            succeeded = false
            diagnostics.diagnosticSink().emitFault("Error saving managed object context: \(error)")
        }
    }
}
