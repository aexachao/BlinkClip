import AppKit

/// Stable identifier for every button that can appear in the editor's
/// toolbars. Raw values are persisted in `UserDefaults`, so existing cases
/// must never be renamed — only added or deprecated.
enum ToolbarItemID: String, Codable, CaseIterable {
    // Annotation tools (toggle an `EditTool`)
    case rectangle
    case ellipse
    case arrow
    case line
    case pen
    case marker
    case spotlight
    case mosaic
    case eraser
    case magnifier
    case numbered
    case text
    case qrCode
    case emoji
    case insertImage
    // Stateful actions
    case colorPicker
    case undo
    case redo
    case moveSelection
    case scrollCapture
    case rotate
    case beautify
    case ocr
    case screenshotTranslate
    // Output actions
    case save
    case upload
    case pin
    case record
    case close
    case confirm
}

extension ToolbarItemID {
    /// How the button behaves — drives which `on*` callback it fires and
    /// whether it carries a persistent selected/active state.
    enum Kind {
        /// Annotation tool — selecting it toggles an `EditTool`.
        case toggleTool
        /// Has an on/off state but is not an `EditTool` (scroll capture, beautify).
        case toggleAction
        /// Fires once on click, no persistent state.
        case momentary
        /// Press-and-drag handle (move selection) — not a tappable button.
        case dragHandle
    }

    var kind: Kind {
        switch self {
        case .rectangle, .ellipse, .arrow, .line, .pen, .marker, .spotlight, .mosaic, .eraser, .magnifier, .numbered, .text, .emoji:
            return .toggleTool
        case .scrollCapture, .rotate, .beautify, .qrCode:
            return .toggleAction
        case .moveSelection:
            return .dragHandle
        case .insertImage, .colorPicker, .undo, .redo, .ocr, .screenshotTranslate, .save, .upload, .pin, .record, .close, .confirm:
            return .momentary
        }
    }

    /// The annotation tool a `toggleTool` item maps to; `nil` for all others.
    var editTool: EditTool? {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse:   return .ellipse
        case .arrow:     return .arrow
        case .line:      return .line
        case .pen:       return .pen
        case .marker:    return .marker
        case .spotlight: return .spotlight
        case .mosaic:    return .mosaic
        case .eraser:    return .eraser
        case .magnifier: return .magnifier
        case .numbered:  return .numbered
        case .text:      return .text
        case .emoji:     return .emoji
        default:         return nil
        }
    }

    var symbolName: String {
        switch self {
        case .rectangle:     return "rectangle"
        case .ellipse:       return "circle"
        case .arrow:         return "arrow.up.right"
        case .line:          return "line.diagonal"
        case .pen:           return "pencil.tip"
        case .marker:        return "highlighter"
        case .spotlight:     return "rectangle.inset.filled"
        case .mosaic:        return "square.grid.3x3"
        case .eraser:        return "eraser"
        case .magnifier:     return "plus.magnifyingglass"
        case .numbered:      return "1.circle"
        case .text:          return "textformat"
        case .qrCode:        return "qrcode.viewfinder"
        case .emoji:         return "face.smiling"
        case .insertImage:   return "photo"
        case .colorPicker:   return "eyedropper"
        case .undo:          return "arrow.uturn.backward"
        case .redo:          return "arrow.uturn.forward"
        case .moveSelection: return "arrow.up.and.down.and.arrow.left.and.right"
        case .scrollCapture: return "arrow.up.and.down.text.horizontal"
        case .rotate:        return "rotate.left"
        case .beautify:      return "sparkles"
        case .ocr:           return "character.bubble"
        case .screenshotTranslate: return "translate"
        case .save:          return "square.and.arrow.down"
        case .upload:        return "icloud.and.arrow.up"
        case .pin:           return "pin"
        case .record:        return "record.circle"
        case .close:         return "xmark"
        case .confirm:       return "checkmark"
        }
    }

    /// Keep the OCR symbol's Chinese glyph fixed regardless of the system locale.
    func iconImage(pointSize: CGFloat) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return nil
        }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        let locale: Locale? = switch self {
        case .ocr: Locale(identifier: "zh-Hans")
        case .text: Locale(identifier: "en")
        default: nil
        }
        return (locale.map { base.withLocale($0) } ?? base).withSymbolConfiguration(config)
    }

    var localizedTitle: String {
        switch self {
        case .rectangle:     return L10n.tipRectangle
        case .ellipse:       return L10n.tipEllipse
        case .arrow:         return L10n.tipArrow
        case .line:          return L10n.tipLine
        case .pen:           return L10n.tipPen
        case .marker:        return L10n.tipMarker
        case .spotlight:     return L10n.tipSpotlight
        case .mosaic:        return L10n.tipMosaic
        case .eraser:        return L10n.tipEraser
        case .magnifier:     return L10n.tipMagnifier
        case .numbered:      return L10n.tipNumbered
        case .text:          return L10n.tipText
        case .qrCode:        return L10n.tipQRCode
        case .emoji:         return L10n.tipEmoji
        case .insertImage:   return L10n.tipInsertImage
        case .colorPicker:   return L10n.tipColorPicker
        case .undo:          return L10n.tipUndo
        case .redo:          return L10n.tipRedo
        case .moveSelection: return L10n.tipMoveSelection
        case .scrollCapture: return L10n.tipScrollCapture
        case .rotate:        return L10n.tipRotate
        case .beautify:      return L10n.tipBeautify
        case .ocr:           return L10n.tipOCR
        case .screenshotTranslate: return L10n.tipScreenshotTranslate
        case .save:          return L10n.tipSave
        case .upload:        return L10n.tipUpload
        case .pin:           return L10n.tipPin
        case .record:        return L10n.tipRecord
        case .close:         return L10n.tipCancel
        case .confirm:       return L10n.tipConfirm
        }
    }

    /// Localized hover-tooltip text with the current configured shortcut.
    var tooltip: String {
        guard let shortcut = editorShortcutDisplay else { return localizedTitle }
        return "\(localizedTitle) (\(shortcut))"
    }

    var editorShortcutDisplay: String? {
        guard supportsEditorShortcut else { return nil }
        return EditorShortcutRegistry.displayString(for: .toolbar(self))
    }

    /// Icon tint in the resting state.
    var normalColor: NSColor {
        switch self {
        case .close:   return toolbarDangerRed
        case .confirm: return accentGreen
        default:       return .labelColor
        }
    }

    /// Icon tint while selected/active. For `momentary` items this equals
    /// `normalColor` — they never enter a selected state.
    var selectedColor: NSColor {
        switch kind {
        case .toggleTool, .toggleAction:
            return accentGreen
        case .momentary, .dragHandle:
            return normalColor
        }
    }
}

/// Red used for the cancel button's icon. Mirrors the literal previously
/// inlined in `ToolbarView.setupButtons()`.
let toolbarDangerRed = NSColor(red: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)

/// A set of related annotation tools collapsed into one toolbar button with
/// a dropdown menu. The button shows the currently selected member's icon
/// plus a chevron; the last-used member per group is persisted (see
/// `ToolbarGroupSelection`) and restored on launch. Raw `ToolbarItemID`
/// values are never renamed, so grouping never changes persistence.
struct ToolbarGroup: Equatable {
    /// Stable key used in the persisted group-selection dictionary.
    let id: String
    let members: [ToolbarItemID]
    let defaultMember: ToolbarItemID

    /// Shapes: rectangle (default) and ellipse.
    static let shapes = ToolbarGroup(id: "shapes", members: [.rectangle, .ellipse], defaultMember: .rectangle)
    /// Lines: line and arrow. Arrow is the default because it is the tool the
    /// user reaches for first. A persisted choice still wins
    /// (`ToolbarGroupSelection.member(for:)`), except for the one v1 map where
    /// `line` was the shipped default rather than a pick — that is rewritten
    /// once by `ToolbarGroupSelection.migrating(dictionary:storedSchema:)`.
    static let lines = ToolbarGroup(id: "lines", members: [.line, .arrow], defaultMember: .arrow)
    /// Brush: pen (default), highlighter and spotlight. One button with a
    /// dropdown instead of three separate buttons.
    static let brush = ToolbarGroup(id: "brush", members: [.pen, .marker, .spotlight], defaultMember: .pen)

    static let all: [ToolbarGroup] = [.shapes, .lines, .brush]

    static func group(containing item: ToolbarItemID) -> ToolbarGroup? {
        all.first { $0.members.contains(item) }
    }
}

/// Last-used tool per toolbar group, persisted in UserDefaults under
/// `editor.toolbarGroupSelection` as `[groupID: memberRawValue]`. Pure value
/// type so the resolution rules are unit-testable without UserDefaults.
struct ToolbarGroupSelection: Equatable {
    var selected: [String: ToolbarItemID]

    static let empty = ToolbarGroupSelection(dictionary: [:])

    /// The member the group's button currently shows. Falls back to the
    /// group's default when nothing was persisted, or when the persisted
    /// value is no longer a member of the group.
    func member(for group: ToolbarGroup) -> ToolbarItemID {
        if let saved = selected[group.id], group.members.contains(saved) {
            return saved
        }
        return group.defaultMember
    }

    /// Returns a copy with `member` recorded as the group's selected tool.
    /// No-op when `member` is not in the group.
    func selecting(_ member: ToolbarItemID, in group: ToolbarGroup) -> ToolbarGroupSelection {
        guard group.members.contains(member) else { return self }
        var copy = self
        copy.selected[group.id] = member
        return copy
    }

    /// Builds a selection from a persisted `[groupID: rawValue]` dictionary,
    /// silently skipping unknown groups, unknown raw values, and values that
    /// are not members of their group.
    init(dictionary: [String: String]) {
        var selected: [String: ToolbarItemID] = [:]
        for group in ToolbarGroup.all {
            if let raw = dictionary[group.id],
               let member = ToolbarItemID(rawValue: raw),
               group.members.contains(member) {
                selected[group.id] = member
            }
        }
        self.selected = selected
    }

    /// Plain `[String: String]` form suitable for `UserDefaults`.
    var dictionary: [String: String] {
        selected.mapValues(\.rawValue)
    }
}

// MARK: - Schema migration

extension ToolbarGroupSelection {
    /// `UserDefaults` key holding the persisted `[groupID: memberRawValue]`
    /// map. Its shape never changed when grouping shipped, so it stays exactly
    /// as it was: no version, no wrapper object.
    static let defaultsKey = "editor.toolbarGroupSelection"
    /// Meaning-version of `defaultsKey`, in its own key so the persisted map
    /// keeps its existing structure.
    static let schemaDefaultsKey = "editor.toolbarGroupSelection.schema"
    /// Current meaning. Version 1 shipped with `line` as the lines group's
    /// default, and the bar persisted that default as if it were a user pick;
    /// version 2 made `arrow` the default, so v1 state needs a one-time fix.
    static let schemaVersion = 2

    /// Outcome of reading a persisted map through the schema migration.
    struct Migration: Equatable {
        /// Selection to resolve against the current groups.
        let selection: ToolbarGroupSelection
        /// Map to write back. Equal to the input when nothing needs
        /// rewriting; unknown groups/values are preserved so the migration
        /// never drops data it does not understand.
        let dictionary: [String: String]
        let storedSchema: Int?
        /// The stored `lines` member was the old default, not a real choice.
        let didMigrate: Bool

        /// Schema the caller should persist (never lowers a newer one).
        var schema: Int { max(storedSchema ?? 0, ToolbarGroupSelection.schemaVersion) }

        /// A missing marker is `nil`, which counts as version 1.
        var needsSchemaWrite: Bool {
            (storedSchema ?? 0) < ToolbarGroupSelection.schemaVersion
        }
    }

    /// One-time fix-up of a v1 map: `lines = line` was the old default that
    /// v1 persisted without the user ever choosing it, so it is rewritten to
    /// `arrow`. The rewrite only happens while the stored schema predates
    /// `schemaVersion`; once the marker is stamped, a stored `line` is a real
    /// user choice and is left alone forever. Purely functional and
    /// idempotent: running it on its own output changes nothing. Only the
    /// `lines` group is ever touched — shapes and brush keep their members.
    static func migrating(dictionary: [String: String], storedSchema: Int?) -> Migration {
        guard (storedSchema ?? 0) < schemaVersion else {
            return Migration(
                selection: ToolbarGroupSelection(dictionary: dictionary),
                dictionary: dictionary,
                storedSchema: storedSchema,
                didMigrate: false
            )
        }
        var persisted = dictionary
        var didMigrate = false
        if persisted[ToolbarGroup.lines.id] == ToolbarItemID.line.rawValue {
            persisted[ToolbarGroup.lines.id] = ToolbarItemID.arrow.rawValue
            didMigrate = true
        }
        return Migration(
            selection: ToolbarGroupSelection(dictionary: persisted),
            dictionary: persisted,
            storedSchema: storedSchema,
            didMigrate: didMigrate
        )
    }
}

extension Defaults {
    /// Persisted last-used tool per toolbar group. Reads run the one-time
    /// schema migration, so a v1 `lines = line` left over from the old default
    /// resolves to the arrow tool; writes always stamp the current schema,
    /// which is what lets a later explicit `line` pick survive every launch.
    /// Always returned resolved against the current groups, so a stale or
    /// unknown value can never surface a tool that is not in its group.
    static var toolbarGroupSelection: ToolbarGroupSelection {
        get { toolbarGroupSelection(in: .standard) }
        set { setToolbarGroupSelection(newValue, in: .standard) }
    }

    /// `UserDefaults`-injected form of the accessor above, so the native
    /// harness can run the migration against a scratch suite instead of the
    /// user's real preferences.
    static func toolbarGroupSelection(in defaults: UserDefaults) -> ToolbarGroupSelection {
        let stored = (defaults.dictionary(forKey: ToolbarGroupSelection.defaultsKey) as? [String: String]) ?? [:]
        let storedSchema = (defaults.object(forKey: ToolbarGroupSelection.schemaDefaultsKey) as? NSNumber)?.intValue
        let migration = ToolbarGroupSelection.migrating(dictionary: stored, storedSchema: storedSchema)
        // Persist the migration outcome once. Subsequent launches read the
        // stamped schema and never rewrite the value again.
        if migration.dictionary != stored {
            defaults.set(migration.dictionary, forKey: ToolbarGroupSelection.defaultsKey)
        }
        if migration.needsSchemaWrite {
            defaults.set(migration.schema, forKey: ToolbarGroupSelection.schemaDefaultsKey)
        }
        return migration.selection
    }

    static func setToolbarGroupSelection(_ selection: ToolbarGroupSelection, in defaults: UserDefaults) {
        defaults.set(selection.dictionary, forKey: ToolbarGroupSelection.defaultsKey)
        defaults.set(ToolbarGroupSelection.schemaVersion, forKey: ToolbarGroupSelection.schemaDefaultsKey)
    }
}

/// User-customizable assignment of every toolbar item to the primary
/// (horizontal) toolbar, the side (vertical) toolbar, or hidden.
struct ToolbarLayout: Equatable {
    var primary: [ToolbarItemID]
    var side: [ToolbarItemID]
    var hidden: [ToolbarItemID]

    /// The single horizontal bar's left-to-right order: `primary` items
    /// first, then a vertical divider, then the former `side` items. The
    /// `primary`/`side` buckets still persist separately so an existing
    /// layout keeps its order and the divider stays between the two runs;
    /// they are no longer two separate bars.
    var visibleItems: [ToolbarItemID] { primary + side }

    /// Index in `visibleItems` after which the divider is drawn — i.e. the
    /// number of items in the first run.
    var dividerIndex: Int { primary.count }

    /// Canonical left-to-right order. Used for the default layout and to
    /// place any newly-introduced tool that an older persisted layout never
    /// recorded.
    static let canonicalOrder: [ToolbarItemID] = [
        .rectangle, .ellipse, .line, .arrow, .pen, .marker, .spotlight, .mosaic, .eraser, .numbered, .text, .emoji, .insertImage,
        .colorPicker, .magnifier, .undo, .redo, .moveSelection, .scrollCapture, .rotate, .beautify, .qrCode, .ocr,
        .screenshotTranslate,
        .save, .pin, .record, .close, .confirm,
    ]

    /// Default layout: annotation tools + edit actions in the first run of
    /// the single horizontal bar; capture/output actions in the second run
    /// (after the divider).
    static var `default`: ToolbarLayout {
        ToolbarLayout(
            primary: [
                .rectangle, .ellipse, .line, .arrow, .pen, .marker, .spotlight, .mosaic, .eraser, .numbered, .text, .emoji, .insertImage,
                .colorPicker, .magnifier, .rotate, .beautify, .qrCode, .ocr, .screenshotTranslate, .undo, .redo, .moveSelection,
            ],
            side: [.scrollCapture, .save, .pin, .record, .close, .confirm],
            hidden: []
        )
    }

    /// A slot in the single horizontal bar: one plain button, one grouped
    /// dropdown button, or the vertical divider between the two runs.
    enum Slot: Equatable {
        case item(ToolbarItemID)
        case group(ToolbarGroup)
        case divider
    }

    /// Builds the bar's slots from a layout. Related tools collapse into one
    /// dropdown button when two or more members of the group are visible; a
    /// group with a single visible member renders as that member's plain
    /// button. The divider sits between the primary run and the side run. A
    /// group whose members straddle the divider renders once, at its first
    /// member's position. Upload is filtered here as well as in
    /// `normalized()`, so it can never reach the bar's geometry even from a
    /// hand-edited layout. Which member a group button shows comes from
    /// `ToolbarGroupSelection` at button-build time, not from the slots.
    static func slots(for layout: ToolbarLayout) -> [Slot] {
        let visible = layout.visibleItems.filter { $0 != .upload }
        var emittedGroups = Set<String>()
        func slots(for run: [ToolbarItemID]) -> [Slot] {
            var out: [Slot] = []
            for item in run where item != .upload {
                if let group = ToolbarGroup.group(containing: item) {
                    guard !emittedGroups.contains(group.id) else { continue }
                    emittedGroups.insert(group.id)
                    let visibleMembers = group.members.filter { visible.contains($0) }
                    if visibleMembers.count >= 2 {
                        out.append(.group(group))
                    } else if let only = visibleMembers.first {
                        out.append(.item(only))
                    }
                } else {
                    out.append(.item(item))
                }
            }
            return out
        }
        let primarySlots = slots(for: layout.primary)
        let sideSlots = slots(for: layout.side)
        if primarySlots.isEmpty { return sideSlots }
        if sideSlots.isEmpty { return primarySlots }
        return primarySlots + [.divider] + sideSlots
    }

    /// The layout with `items` treated as unavailable, keeping every other
    /// tool exactly where it was. Used for items hidden for the current
    /// scenario and for keyboard-only actions (redo), so hiding never rewrites
    /// the persisted layout — the item simply stops contributing a slot.
    func excluding(_ items: Set<ToolbarItemID>) -> ToolbarLayout {
        guard !items.isEmpty else { return self }
        return ToolbarLayout(
            primary: primary.filter { !items.contains($0) },
            side: side.filter { !items.contains($0) },
            hidden: hidden.filter { !items.contains($0) }
        )
    }

    /// Drops duplicate / unknown ids and slots any tool missing from all
    /// three buckets next to its canonical neighbour, so the result always
    /// covers every supported toolbar item exactly once regardless of app-version
    /// drift. A newly-introduced tool lands beside its siblings (e.g. `line`
    /// after `ellipse`) instead of being dumped at the end of the bar.
    /// Old persisted layouts (primary/side/hidden buckets) are accepted as
    /// is: the single bar's merged order is `primary` followed by `side`,
    /// so migration needs no rewrite — `normalized()` keeps the buckets and
    /// the bar renders them as one row with the divider between them.
    func normalized() -> ToolbarLayout {
        var seen = Set<ToolbarItemID>()
        func dedup(_ ids: [ToolbarItemID]) -> [ToolbarItemID] {
            // Retain the persisted raw value for compatibility, but never
            // restore the unsupported image-host upload into any toolbar.
            ids.filter { $0 != .upload && seen.insert($0).inserted }
        }
        var p = dedup(primary)
        var s = dedup(side)
        var h = dedup(hidden)

        let missing = Self.canonicalOrder.filter { !seen.contains($0) }
        for item in missing {
            // Existing layouts put scroll capture on the side bar. Anchor the
            // new rotation action to Beautify so upgrading preserves its place.
            if item == .rotate {
                if let index = p.firstIndex(of: .beautify) {
                    p.insert(item, at: index)
                } else if let index = s.firstIndex(of: .beautify) {
                    s.insert(item, at: index)
                } else if let index = h.firstIndex(of: .beautify) {
                    h.insert(item, at: index)
                } else {
                    p.append(item)
                }
                seen.insert(item)
                continue
            }
            guard let canonicalIdx = Self.canonicalOrder.firstIndex(of: item) else { continue }
            // Walk back through the canonical order to the nearest sibling
            // that's already placed, then drop the new tool right after it
            // in whichever bucket that sibling lives in.
            var placed = false
            for prevIdx in stride(from: canonicalIdx - 1, through: 0, by: -1) {
                let prev = Self.canonicalOrder[prevIdx]
                if let i = p.firstIndex(of: prev) { p.insert(item, at: i + 1); placed = true; break }
                if let i = s.firstIndex(of: prev) { s.insert(item, at: i + 1); placed = true; break }
                if let i = h.firstIndex(of: prev) { h.insert(item, at: i + 1); placed = true; break }
            }
            if !placed { p.insert(item, at: 0) }
            seen.insert(item)
        }
        return ToolbarLayout(primary: p, side: s, hidden: h)
    }
}

extension ToolbarLayout {
    /// Builds a layout from a persisted `[bucket: [rawValue]]` dictionary,
    /// silently skipping any raw value no longer backed by a `ToolbarItemID`.
    init(dictionary: [String: [String]]) {
        func parse(_ key: String) -> [ToolbarItemID] {
            (dictionary[key] ?? []).compactMap(ToolbarItemID.init(rawValue:))
        }
        self.init(
            primary: parse("primary"),
            side: parse("side"),
            hidden: parse("hidden")
        )
    }

    /// Plain `[String: [String]]` form suitable for `UserDefaults`.
    var dictionary: [String: [String]] {
        [
            "primary": primary.map(\.rawValue),
            "side": side.map(\.rawValue),
            "hidden": hidden.map(\.rawValue),
        ]
    }
}

extension Defaults {
    /// Persisted editor toolbar layout. Always returned normalized, so
    /// callers can rely on every tool being present exactly once.
    static var toolbarLayout: ToolbarLayout {
        get {
            guard let dict = UserDefaults.standard
                .dictionary(forKey: "editor.toolbarLayout") as? [String: [String]]
            else {
                return .default
            }
            return ToolbarLayout(dictionary: dict).normalized()
        }
        set {
            UserDefaults.standard.set(
                newValue.normalized().dictionary,
                forKey: "editor.toolbarLayout"
            )
        }
    }
}
