import AppKit

@MainActor
public enum FilePreviewActions {
    public static func revealItemsInFinder(_ items: [PasteboardItem]) {
        let urls = items.compactMap { $0.fileURL() }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        NSApp.deactivate()
    }
}
