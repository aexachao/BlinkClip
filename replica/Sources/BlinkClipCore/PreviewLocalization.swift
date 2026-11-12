import Foundation

/// Stable accessors resolve independently authored Chinese or English resources.
public enum PreviewLocalization {
    private static let resourceBundle = ResourceBundle.bundle

    private static func resource(_ key: String) -> LocalizedStringResource {
        LocalizedStringResource(String.LocalizationValue(stringLiteral: key),
                                table: "Localizable", locale: ResourceBundle.selectedLocale(),
                                bundle: .atURL(resourceBundle.bundleURL))
    }

    public static func generalUntitled() -> LocalizedStringResource { resource("general.untitled") }

    public static func generalPaused() -> LocalizedStringResource { resource("general.paused") }
    public static func generalActionPausePaste() -> LocalizedStringResource { resource("general.action.pause-paste") }

    public static func generalPastePaused() -> LocalizedStringResource { resource("general.paste-paused") }
    public static func generalPasteResumed() -> LocalizedStringResource { resource("general.paste-resumed") }

    public static func untilTime(_ time: String) -> LocalizedStringResource {
        LocalizedStringResource("general.until", defaultValue: "\(time)", table: "Localizable",
                                locale: ResourceBundle.selectedLocale(), bundle: .atURL(resourceBundle.bundleURL))
    }

    public static func generalCopied() -> LocalizedStringResource {
        resource("general.copied")
    }

    public static func generalEnableDirectPaste() -> LocalizedStringResource {
        resource("general.enable-direct-paste")
    }

    public static func editItemToolbarTextBold() -> LocalizedStringResource {
        resource("edit-item.toolbar.text.bold")
    }

    public static func editItemToolbarTextItalic() -> LocalizedStringResource {
        resource("edit-item.toolbar.text.italic")
    }

    public static func editItemToolbarTextStrikethrough() -> LocalizedStringResource {
        resource("edit-item.toolbar.text.strikethrough")
    }

    public static func editItemToolbarTextUnderline() -> LocalizedStringResource {
        resource("edit-item.toolbar.text.underline")
    }

    public static func editItemToolbarSaveChanges() -> LocalizedStringResource {
        resource("edit-item.toolbar.save-changes")
    }

    public static func generalActionSave() -> LocalizedStringResource {
        resource("general.action.save")
    }

    public static func generalActionCancel() -> LocalizedStringResource {
        resource("general.action.cancel")
    }

    public static func editItemToolbarDiscardChanges() -> LocalizedStringResource {
        resource("edit-item.toolbar.discard-changes")
    }

    public static func generalActionEdit() -> LocalizedStringResource {
        resource("general.action.edit")
    }

    public static func generalActionRestartPaste() -> LocalizedStringResource {
        resource("general.action.restart-paste")
    }

    public static func diagnosticsStartTitle() -> LocalizedStringResource {
        resource("diagnostics.start.title")
    }

    public static func diagnosticsStartMessage() -> LocalizedStringResource {
        resource("diagnostics.start.message")
    }

    public static func diagnosticsStopTitle() -> LocalizedStringResource {
        resource("diagnostics.stop.title")
    }

    public static func diagnosticsStopMessage() -> LocalizedStringResource {
        resource("diagnostics.stop.message")
    }

    public static func diagnosticsActionStopAndCopyLogs() -> LocalizedStringResource {
        resource("diagnostics.action.stop-and-copy-logs")
    }

    public static func generalActionPin() -> LocalizedStringResource {
        resource("general.action.pin")
    }

    public static func generalActionShare() -> LocalizedStringResource {
        resource("general.action.share")
    }

    public static func generalActionCreatePinboard() -> LocalizedStringResource {
        resource("general.action.create-pinboard")
    }

    public static func generalActionUnpin() -> LocalizedStringResource {
        resource("general.action.unpin")
    }

    public static func editItemToolbarImageRotateLeft() -> LocalizedStringResource {
        resource("edit-item.toolbar.image.rotate-left")
    }

    public static func editItemToolbarImageRotateRight() -> LocalizedStringResource {
        resource("edit-item.toolbar.image.rotate-right")
    }

    public static func generalBrowser() -> LocalizedStringResource {
        resource("general.browser")
    }

    public static func itemTypeMultipleFiles() -> LocalizedStringResource {
        resource("item-type.multiple-files")
    }

    public static func itemTypeColor() -> LocalizedStringResource { resource("item-type.color") }
    public static func itemTypeImage() -> LocalizedStringResource { resource("item-type.image") }
    public static func itemTypeLink() -> LocalizedStringResource { resource("item-type.link") }
    public static func itemTypeText() -> LocalizedStringResource { resource("item-type.text") }
    public static func itemTypeUnknown() -> LocalizedStringResource { resource("item-type.unknown") }

    public static func fileCount(_ count: Int32) -> LocalizedStringResource {
        countResource(count, key: "item-type.file-count")
    }

    public static func previewRevealInFinderTitle() -> LocalizedStringResource {
        resource("preview.reveal-in-finder.title")
    }

    public static func openInApplication(_ applicationName: String) -> LocalizedStringResource {
        LocalizedStringResource("general.action.open-in", defaultValue: "\(applicationName)",
                                table: "Localizable", locale: ResourceBundle.selectedLocale(),
                                bundle: .atURL(resourceBundle.bundleURL))
    }

    private static func countResource(_ count: Int32, key: StaticString) -> LocalizedStringResource {
        LocalizedStringResource(key, defaultValue: "\(count)", table: "Localizable",
                                locale: ResourceBundle.selectedLocale(), bundle: .atURL(resourceBundle.bundleURL))
    }

    public static func characterCount(_ count: Int32) -> LocalizedStringResource {
        countResource(count, key: "editor.character-count")
    }

    public static func wordCount(_ count: Int32) -> LocalizedStringResource {
        countResource(count, key: "editor.word-count")
    }

    public static func lineCount(_ count: Int32) -> LocalizedStringResource {
        countResource(count, key: "editor.line-count")
    }

}
