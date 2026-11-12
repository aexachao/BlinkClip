import AppIntents

/// One automatic shortcut with the seven recovered phrases; bundle metadata is still required.
struct BlinkClipShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: BlinkClipCreateItemIntent(),
            phrases: [
                "Create \(.applicationName) item",
                "Save \(.applicationName) item",
                "Add \(.applicationName) item",
                "Create text item with \(.applicationName)",
                "New text item in \(.applicationName)",
                "Save to \(.applicationName)",
                "Add to \(.applicationName)"
            ],
            shortTitle: "Create BlinkClip Item",
            systemImageName: "square.and.pencil"
        )
    }
}
