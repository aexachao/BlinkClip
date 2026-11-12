import Foundation

public enum PreviewTitles {
    public static func itemTypeTitle(rawType: Int, fileCount: Int? = nil) -> String {
        let resource: LocalizedStringResource
        switch rawType {
        case 1: resource = PreviewLocalization.itemTypeImage()
        case 2: resource = PreviewLocalization.itemTypeColor()
        case 3: resource = PreviewLocalization.fileCount(Int32(fileCount ?? 1))
        case 4: resource = PreviewLocalization.itemTypeLink()
        case 5: resource = PreviewLocalization.itemTypeText()
        default: resource = PreviewLocalization.itemTypeUnknown()
        }
        return String(localized: resource)
    }

    // Compare the displayed title first; re-read the optional field only for an empty trimmed input.
    public static func updateTitle(_ title: String, originalTitle: @autoclosure () -> String?,
                                  defaultTitle: @autoclosure () -> String,
                                  update: (String?) throws -> Void) rethrows {
        let displayedTitle = titleOrDefault(originalTitle(), defaultTitle: defaultTitle())
        guard title != displayedTitle else { return }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        try update(normalized.isEmpty && originalTitle() != nil ? nil : normalized)
    }

    public static func titleOrDefault(_ title: String?, defaultTitle: @autoclosure () -> String) -> String {
        if let title, !title.isEmpty { return title }
        return defaultTitle()
    }
}
