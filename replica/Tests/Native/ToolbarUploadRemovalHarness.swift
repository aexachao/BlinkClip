import AppKit

/// Native gate for the editor toolbar: persisted-layout inventory, grouping,
/// the interactive hover / dropdown-panel behaviour, and the offscreen renders
/// that prove both. Presentation-only dependencies are stubbed by
/// `scripts/test-toolbar-upload-removal.sh`; everything toolbar-shaped is the
/// production source.
@main struct ToolbarUploadRemovalHarness {
    static var checks = 0
    /// `before` → `after` of the v1 defaults map, quoted in the report.
    static var migrationSnapshot: [String: String] = [:]

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static func main() {
        inventoryChecks()
        migrationChecks()
        sessionResetChecks()
        groupingChecks()
        hoverChecks()
        dropdownHoverChecks()
        dropdownChecks()
        localizationChecks()
        barChecks()
        let renders = RenderEvidence.writeIfRequested()
        let measurements = RenderEvidence.measurements()
        let json = measurements
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\":\"\($0.value)\"" }
            .joined(separator: ",")
        let migration = migrationSnapshot
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\":\"\($0.value)\"" }
            .joined(separator: ",")
        print("{\"passed\":true,\"checks\":\(checks),\"renders\":\(renders),\"samples\":{\(json)},\"migration\":{\(migration)},\"boundary\":\"Actual production ToolbarLayout, ToolbarChrome, ToolbarButtons and ToolbarGroupMenu sources with presentation dependency stubs; group-selection schema migration against a scratch UserDefaults suite, group inventory, hover fills, dropdown row hover driven by synthetic mouse events inside a real never-key NSPanel, dropdown metrics/keyboard/placement, the app's real Localizable.strings for the renders, the whole-bar geometry, and offscreen renders of the real drawing code. No editor UI session or event monitors.\"}")
    }

    // MARK: - Persisted inventory

    static func inventoryChecks() {
        let supported = ToolbarLayout.canonicalOrder
        check(!supported.contains(.upload), "upload is not an offered editor action")
        check(ToolbarItemID(rawValue: "upload") == .upload, "old persisted raw value still decodes")
        check(Set(supported).count == supported.count, "canonical supported actions remain unique")
        check(Set(supported) == Set(ToolbarItemID.allCases.filter { $0 != .upload }), "all other tools remain available")
        // Redo stays in the persisted inventory although it is no longer shown:
        // hiding it is a runtime concern (ToolbarView.keyboardOnlyItems), so a
        // stored layout never loses a raw value.
        check(supported.contains(.redo), "redo keeps its persisted slot so layouts stay compatible")

        func verify(_ layout: ToolbarLayout) {
            let combined = layout.primary + layout.side + layout.hidden
            check(!combined.contains(.upload), "upload is absent from every normalized bucket")
            check(combined.count == supported.count, "no missing or duplicate supported tool")
            check(Set(combined) == Set(supported), "supported tool inventory is preserved")
            check(layout.normalized() == layout, "normalization is stable")
            check(ToolbarLayout(dictionary: layout.dictionary).normalized() == layout, "persisted round trip is stable")
        }
        verify(.default)
        check(ToolbarLayout.default.side == [.scrollCapture, .save, .pin, .record, .close, .confirm], "default output toolbar has no empty upload slot")
        let merged = ToolbarLayout.default.visibleItems
        check(merged == ToolbarLayout.default.primary + ToolbarLayout.default.side, "single bar merges primary then side")
        check(ToolbarLayout.default.dividerIndex == ToolbarLayout.default.primary.count, "divider sits after the primary run")
        for bucket in ["primary", "side", "hidden"] {
            var old = ToolbarLayout.default.dictionary
            old[bucket, default: []].insert("upload", at: 0)
            let normalized = ToolbarLayout(dictionary: old).normalized()
            verify(normalized)
            check(normalized == .default, "old upload placement is removed without rearranging other tools")
        }
        let customized = ToolbarLayout(primary: [.save, .rectangle], side: [.pin, .confirm], hidden: [.text]).normalized()
        var legacy = customized.dictionary
        legacy["primary", default: []].insert(contentsOf: ["upload", "unknown-tool", "upload"], at: 1)
        legacy["side", default: []].insert(contentsOf: ["upload", "save"], at: 0)
        legacy["hidden", default: []].append(contentsOf: ["upload", "text"])
        let migrated = ToolbarLayout(dictionary: legacy).normalized()
        verify(migrated)
        check(migrated == customized, "migration preserves user placement and strips stale upload/unknown/duplicate values")
        verify(ToolbarLayout(primary: [.upload], side: [.upload], hidden: [.upload]).normalized())
        verify(ToolbarLayout(primary: [], side: [], hidden: []).normalized())
    }

    // MARK: - Group-selection schema migration

    /// The shipped v1 build persisted `lines = line` as if the user had picked
    /// it, and the bar "respected the stored preference", so the new arrow
    /// default never showed. The fix is a one-time, schema-marked rewrite:
    /// v1 state migrates once, and a `line` pick made afterwards is the user's
    /// own choice and survives every restart.
    static func migrationChecks() {
        let suiteName = "capcap.harness.toolbar-group-selection"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("could not open the harness defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let key = ToolbarGroupSelection.defaultsKey
        let schemaKey = ToolbarGroupSelection.schemaDefaultsKey

        func storedMap(_ defaults: UserDefaults) -> [String: String] {
            (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        }
        func storedSchema(_ defaults: UserDefaults) -> Int? {
            (defaults.object(forKey: schemaKey) as? NSNumber)?.intValue
        }

        check(ToolbarGroupSelection.defaultsKey == "editor.toolbarGroupSelection",
              "the persisted map keeps its existing key")
        check(ToolbarGroupSelection.schemaDefaultsKey == "editor.toolbarGroupSelection.schema",
              "the schema marker lives in its own key")
        check(ToolbarGroupSelection.schemaVersion == 2, "the migration is schema 2")

        // ① Shipped v1 state: the old default was stored without a marker.
        defaults.set(["lines": "line"], forKey: key)
        migrationSnapshot["before"] = "lines=line schema=(none)"
        let migrated = Defaults.toolbarGroupSelection(in: defaults)
        check(migrated.member(for: .lines) == .arrow,
              "a v1 lines=line default resolves to the arrow tool")
        check(storedMap(defaults) == ["lines": "arrow"],
              "migration rewrites the stored lines member to arrow")
        check(storedSchema(defaults) == ToolbarGroupSelection.schemaVersion,
              "migration stamps the schema marker")
        migrationSnapshot["after"] = "lines=\(storedMap(defaults)["lines"] ?? "?") schema=\(storedSchema(defaults).map(String.init) ?? "none")"

        // Idempotent: a second read (i.e. the next launch) changes nothing.
        let again = Defaults.toolbarGroupSelection(in: defaults)
        check(again == migrated, "the migration is idempotent across reads")
        check(storedMap(defaults) == ["lines": "arrow"], "the migrated map is not rewritten twice")

        // ② A line pick made after the migration is the user's own choice and
        // survives a restart (a fresh defaults handle on the same suite).
        let picked = migrated.selecting(.line, in: .lines)
        check(picked.member(for: .lines) == .line, "the user can pick line after the migration")
        Defaults.setToolbarGroupSelection(picked, in: defaults)
        check(storedMap(defaults) == ["lines": "line"], "an explicit line pick is persisted")
        check(storedSchema(defaults) == ToolbarGroupSelection.schemaVersion, "saving stamps the schema")
        defaults.synchronize()
        guard let restarted = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("could not reopen the harness defaults suite")
        }
        let afterRestart = Defaults.toolbarGroupSelection(in: restarted)
        check(afterRestart.member(for: .lines) == .line,
              "a line pick made after the migration survives a restart")
        check(storedMap(restarted)["lines"] == "line", "the restart does not rewrite the user's line pick")
        migrationSnapshot["afterUserPickedLine"] = "lines=line schema=\(storedSchema(restarted).map(String.init) ?? "none")"

        // ③ A map that already carries schema 2 is never rewritten, whatever
        // it holds: the migration already ran on this device.
        defaults.set(["lines": "line"], forKey: key)
        defaults.set(ToolbarGroupSelection.schemaVersion, forKey: schemaKey)
        let stable = Defaults.toolbarGroupSelection(in: defaults)
        check(stable.member(for: .lines) == .line, "a schema-2 map keeps an explicit line pick")
        check(storedMap(defaults) == ["lines": "line"], "schema-2 state is not rewritten")

        // ④ Only the lines group is migrated; shapes and brush keep whatever
        // the user chose, and unknown groups are preserved rather than dropped.
        defaults.set(["shapes": "ellipse", "brush": "marker", "lines": "line"], forKey: key)
        defaults.removeObject(forKey: schemaKey)
        let mixed = Defaults.toolbarGroupSelection(in: defaults)
        check(mixed.member(for: .lines) == .arrow, "only the lines group migrates")
        check(mixed.member(for: .shapes) == .ellipse, "an explicit shape pick is untouched")
        check(mixed.member(for: .brush) == .marker, "an explicit brush pick is untouched")
        check(storedMap(defaults) == ["shapes": "ellipse", "brush": "marker", "lines": "arrow"],
              "migration rewrites only the lines entry")
        let extra = ToolbarGroupSelection.migrating(
            dictionary: ["lines": "line", "futureGroup": "x"],
            storedSchema: nil
        )
        check(extra.dictionary["futureGroup"] == "x",
              "migration preserves entries for groups it does not know")

        // ⑤ A fresh install is marked migrated before any pick, so the very
        // first `line` choice is never mistaken for the old default later.
        defaults.removePersistentDomain(forName: suiteName)
        let fresh = Defaults.toolbarGroupSelection(in: defaults)
        check(fresh == .empty, "a fresh install starts with no stored group choices")
        check(fresh.member(for: .lines) == .arrow, "a fresh install shows the arrow default")
        check(storedSchema(defaults) == ToolbarGroupSelection.schemaVersion,
              "a fresh install is marked migrated before any pick")
        Defaults.setToolbarGroupSelection(fresh.selecting(.line, in: .lines), in: defaults)
        defaults.synchronize()
        guard let restartedFresh = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("could not reopen the harness defaults suite")
        }
        check(Defaults.toolbarGroupSelection(in: restartedFresh).member(for: .lines) == .line,
              "the first line pick on a fresh install is never mistaken for the old default")

        // ⑥ The pure rule: running the migration on its own output is a no-op.
        let once = ToolbarGroupSelection.migrating(dictionary: ["lines": "line"], storedSchema: nil)
        check(once.didMigrate && once.dictionary["lines"] == "arrow",
              "the pure migration rewrites the v1 default once")
        let twice = ToolbarGroupSelection.migrating(dictionary: once.dictionary, storedSchema: once.storedSchema)
        check(!twice.didMigrate && twice.dictionary == once.dictionary,
              "running the migration on its own output changes nothing")

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Per-session group reset

    /// Requirement change (J1-f): every new editor session resets all three
    /// groups to their defaults and writes them back. The one-time schema
    /// migration above is kept, but it can no longer resurface a stored pick:
    /// `showToolbar()` never reads the stored map, it overwrites it with the
    /// defaults before building the bar. This is stricter than the earlier
    /// "restart keeps the last member" behaviour, not a relaxed assertion.
    static func sessionResetChecks() {
        let suiteName = "capcap.harness.toolbar-session-reset"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("could not open the harness defaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)
        let key = ToolbarGroupSelection.defaultsKey
        let schemaKey = ToolbarGroupSelection.schemaDefaultsKey
        func storedMap() -> [String: String] {
            (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        }
        func storedSchema() -> Int? {
            (defaults.object(forKey: schemaKey) as? NSNumber)?.intValue
        }

        // The session default is exactly rectangle / arrow / pen.
        let sessionDefaults = ToolbarGroupSelection.sessionDefaults
        check(sessionDefaults.member(for: .shapes) == .rectangle, "a session starts on the rectangle shape")
        check(sessionDefaults.member(for: .lines) == .arrow, "a session starts on the arrow line tool")
        check(sessionDefaults.member(for: .brush) == .pen, "a session starts on the pen brush")
        check(ToolbarGroup.lines.members == [.arrow, .line], "the lines group lists the arrow first")
        check(ToolbarGroup.lines.defaultMember == .arrow, "arrow is the lines group default")

        // The previous session picked ellipse / line / marker. Session start
        // must both show and store the defaults.
        defaults.set(["shapes": "ellipse", "lines": "line", "brush": "marker"], forKey: key)
        defaults.set(ToolbarGroupSelection.schemaVersion, forKey: schemaKey)
        let first = Defaults.resetToolbarGroupSelectionForNewSession(in: defaults)
        check(first.member(for: .shapes) == .rectangle, "session start shows rectangle, not the last ellipse")
        check(first.member(for: .lines) == .arrow, "session start shows arrow, not the last line")
        check(first.member(for: .brush) == .pen, "session start shows pen, not the last marker")
        check(storedMap() == ["shapes": "rectangle", "lines": "arrow", "brush": "pen"],
              "session start writes the three defaults back to storage")
        check(storedSchema() == ToolbarGroupSelection.schemaVersion,
              "the session reset stamps the current schema, so the migration stays settled")
        check(Defaults.toolbarGroupSelection(in: defaults).member(for: .shapes) == .rectangle,
              "a later read cannot surface the previous session's shape")
        check(Defaults.toolbarGroupSelection(in: defaults).member(for: .lines) == .arrow,
              "a later read cannot surface the previous session's line tool")

        // Second editor session: a pick made in the first one is not read back.
        defaults.set(["shapes": "ellipse", "lines": "line", "brush": "marker"], forKey: key)
        let second = Defaults.resetToolbarGroupSelectionForNewSession(in: defaults)
        check(second == sessionDefaults, "the second session resets to the same defaults")
        check(storedMap() == sessionDefaults.dictionary, "the second session rewrites the same defaults")

        // Even a v1 map (no schema marker) is replaced at session start: the
        // migration cannot bring the old default back into a new editor.
        defaults.removeObject(forKey: schemaKey)
        defaults.set(["lines": "line"], forKey: key)
        let third = Defaults.resetToolbarGroupSelectionForNewSession(in: defaults)
        check(third.member(for: .lines) == .arrow, "a v1 stored line cannot reach a new editor")
        check(storedMap()["lines"] == "arrow" && storedSchema() == ToolbarGroupSelection.schemaVersion,
              "session start overwrites the v1 map with the current defaults and schema")

        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Grouping

    static func groupingChecks() {
        let slots = ToolbarLayout.slots(for: .default)
        check(slots.filter { $0 == .divider }.count == 1, "exactly one divider slot")
        check(slots.contains(.group(.shapes)), "shapes collapse into one dropdown button")
        check(slots.contains(.group(.lines)), "lines collapse into one dropdown button")
        check(!slots.contains(.item(.rectangle)) && !slots.contains(.item(.ellipse)), "grouped shape members do not render as plain buttons")
        check(!slots.contains(.item(.line)) && !slots.contains(.item(.arrow)), "grouped line members do not render as plain buttons")

        // Brush: pen + marker + spotlight are one dropdown button now.
        check(ToolbarGroup.all.contains(.brush), "brush is a toolbar group")
        check(ToolbarGroup.brush.members == [.pen, .marker, .spotlight], "brush groups pen, highlighter and spotlight")
        check(slots.contains(.group(.brush)), "brush collapses into one dropdown button")
        for member in [ToolbarItemID.pen, .marker, .spotlight] {
            check(!slots.contains(.item(member)), "brush member \(member.rawValue) no longer occupies its own slot")
            check(ToolbarGroup.group(containing: member) == .brush, "\(member.rawValue) resolves to the brush group")
        }
        // Redo is keyboard-only: excluded at slot time, so it contributes no
        // width and the rest of the bar keeps its order.
        check(slots.contains(.item(.redo)), "a layout that still lists redo would otherwise show it")
        let withoutRedo = ToolbarLayout.default.excluding([.redo])
        check(!withoutRedo.visibleItems.contains(.redo), "the hidden redo leaves the visible run")
        let redoSlots = ToolbarLayout.slots(for: withoutRedo)
        check(!redoSlots.contains(.item(.redo)), "the hidden redo gets no slot")
        check(redoSlots.count == slots.count - 1, "hiding redo removes exactly one slot")
        check(withoutRedo.primary.count == ToolbarLayout.default.primary.count - 1, "the persisted layout keeps every other tool")
        check(ToolbarLayout.default.excluding([.redo]).normalized() == withoutRedo.normalized(), "hiding redo does not disturb normalization")

        // The bar is measurably shorter: three separate 40pt buttons became one
        // 56pt group button.
        let plainSlots = slots.filter { $0 != .divider }.count
        check(plainSlots < ToolbarLayout.default.visibleItems.count - 2, "grouping removes slots from the bar")

        var oneHidden = ToolbarLayout.default
        oneHidden.hidden.append(.ellipse)
        oneHidden.primary.removeAll { $0 == .ellipse }
        let oneSlots = ToolbarLayout.slots(for: oneHidden.normalized())
        check(oneSlots.contains(.item(.rectangle)) && !oneSlots.contains(.group(.shapes)), "single visible member renders as a plain button")
        check(ToolbarLayout.slots(for: ToolbarLayout(dictionary: ToolbarLayout.default.dictionary).normalized()) == slots, "old primary/side layout renders identically in the single bar")

        // Group selection: defaults, within-session picks, stale fallback.
        // A pick only lives for the current session (J1-f); the resolver still
        // honours it there, and `sessionResetChecks` covers the reset itself.
        check(ToolbarGroupSelection.empty.member(for: .shapes) == .rectangle, "shapes default to rectangle")
        check(ToolbarGroupSelection.empty.member(for: .lines) == .arrow, "lines default to the arrow tool")
        check(ToolbarGroupSelection.empty.member(for: .brush) == .pen, "brush defaults to the pen tool")
        let pickedShape = ToolbarGroupSelection.empty.selecting(.ellipse, in: .shapes)
        check(pickedShape.member(for: .shapes) == .ellipse, "a pick made in this session resolves to that shape")
        check(ToolbarGroupSelection(dictionary: pickedShape.dictionary) == pickedShape, "group selection round-trips through the stored map")
        check(ToolbarGroupSelection(dictionary: ["shapes": "nope"]).member(for: .shapes) == .rectangle, "unknown persisted value falls back to default")
        check(ToolbarGroupSelection(dictionary: ["shapes": "arrow"]).member(for: .shapes) == .rectangle, "non-member persisted value falls back to default")
        // The resolver itself still honours a stored member; a new session
        // never reads that map, it overwrites it with the defaults first.
        check(ToolbarGroupSelection(dictionary: ["lines": "line"]).member(for: .lines) == .line, "the resolver honours a stored member when a session asks for it")
        let pickedBrush = ToolbarGroupSelection.empty.selecting(.spotlight, in: .brush)
        check(pickedBrush.member(for: .brush) == .spotlight, "a brush pick made in this session resolves to that member")
        check(ToolbarGroupSelection(dictionary: pickedBrush.dictionary).member(for: .brush) == .spotlight, "brush selection round-trips through the stored map")
        check(ToolbarGroupSelection(dictionary: ["brush": "rectangle"]).member(for: .brush) == .pen, "non-member brush value falls back to the pen")
    }

    // MARK: - Hover

    static func hoverChecks() {
        // One shared rule: hover weaker than selected, same radius/inset.
        check(ToolbarChrome.rowHeight == 40, "row height matches a toolbar button")
        check(ToolbarChrome.highlightCornerRadius == 6, "hover/selected highlight radius matches the old button background")
        check(ToolbarChrome.highlightInset == 2, "hover/selected highlight inset matches the old button background")
        check(ToolbarChrome.surfaceCornerRadius == 8, "panel radius matches the bar capsule")

        let button = ToolButton(
            frame: NSRect(x: 0, y: 0, width: 40, height: 40),
            symbolName: "pencil.tip",
            normalColor: .labelColor,
            selectedColor: accentGreen,
            symbolPointSize: 18
        )
        // Resting → hovered: the fill must actually change.
        let rest = RenderEvidence.sample(patch: RenderEvidence.buttonPatch, in: button, appearance: .aqua)
        button.setHovered(true)
        let hovered = RenderEvidence.sample(patch: RenderEvidence.buttonPatch, in: button, appearance: .aqua)
        check(rest != hovered, "hovering a toolbar button changes its background pixels")
        check(hovered.mean < rest.mean, "hover darkens the light-appearance background")

        // Disabled buttons never light up.
        button.isEnabled = false
        button.setHovered(true)
        let disabledHover = RenderEvidence.sample(patch: RenderEvidence.buttonPatch, in: button, appearance: .aqua)
        button.isEnabled = true
        button.setHovered(false)
        let disabledRest = RenderEvidence.sample(patch: RenderEvidence.buttonPatch, in: button, appearance: .aqua)
        check(disabledHover == disabledRest, "a disabled button shows no hover highlight")

        // Selected state is unaffected by hover: its fill is the stronger
        // selected token, and hovering must not replace it.
        button.isSelected = true
        let selected = RenderEvidence.sample(patch: RenderEvidence.buttonPatch, in: button, appearance: .aqua)
        button.setHovered(true)
        let selectedHovered = RenderEvidence.sample(patch: RenderEvidence.buttonPatch, in: button, appearance: .aqua)
        check(selected == selectedHovered, "hover does not disturb the selected highlight")
        check(selected != hovered, "selected and hovered fills are visually distinct")
        button.isSelected = false
        button.setHovered(false)

        // Both appearances must stay readable: the fill must move away from the
        // bar surface in dark appearance too (no single-appearance literals).
        let darkRest = RenderEvidence.sample(patch: RenderEvidence.buttonPatch, in: button, appearance: .darkAqua)
        button.setHovered(true)
        let darkHovered = RenderEvidence.sample(patch: RenderEvidence.buttonPatch, in: button, appearance: .darkAqua)
        check(darkRest != darkHovered, "hover changes the button background in dark appearance")
        check(darkHovered.mean > darkRest.mean, "hover lightens the dark-appearance background")
        button.setHovered(false)

        // The chevron carries the same hover treatment.
        let chevron = ToolbarChevronButton(frame: NSRect(x: 0, y: 0, width: 16, height: 40), symbolPointSize: 9)
        let chevronRest = RenderEvidence.sample(patch: RenderEvidence.chevronPatch, in: chevron, appearance: .aqua)
        chevron.setHovered(true)
        let chevronHovered = RenderEvidence.sample(patch: RenderEvidence.chevronPatch, in: chevron, appearance: .aqua)
        check(chevronRest != chevronHovered, "the group chevron shows a hover background")
    }

    // MARK: - Dropdown hover inside the never-key panel

    /// The group dropdown is a non-activating `NSPanel`
    /// (`canBecomeKey == false`) so the editor keeps focus and text editing
    /// keeps working. That is exactly why its rows cannot use the bar's
    /// `.activeInKeyWindow` rule: for a never-key window AppKit never delivers
    /// `mouseEntered`, which is the reported bug ("dropdown rows do not
    /// hover"). This drives the real rows inside a real non-key panel with
    /// synthetic mouse events and samples the same hover fill as the bar.
    static func dropdownHoverChecks() {
        let members: [ToolbarItemID] = [.pen, .marker, .spotlight]
        let owner = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
        let panel = ToolbarGroupMenuPanel(
            group: .brush,
            members: members,
            selected: .marker,
            owner: owner,
            onPick: { _ in }
        )
        // Park the panel far away from the harness cursor: the assertions
        // below derive hover from the pointer, so a pointer that happened to
        // sit over a row would make them ambiguous.
        panel.setFrameOrigin(NSPoint(x: 40_000, y: 40_000))
        check(panel.canBecomeKey == false, "the dropdown panel is never key")
        check(panel.isKeyWindow == false, "the dropdown panel is not the key window")
        guard let content = panel.contentView as? ToolbarGroupMenuContentView else {
            preconditionFailure("the panel must host the production dropdown content view")
        }
        check(content.rows.count == 3, "the panel builds one row per group member")
        let row = content.rows[0]
        let selectedRow = content.rows[1]

        /// AppKit's `NSEvent` factory only builds real button/move events; a
        /// `.mouseEntered`/`.mouseExited` type is rejected. The row's enter and
        /// exit handlers only switch hover state and ignore the event body, so
        /// a button event at the same location is delivered to those production
        /// entry points.
        func mouseEvent(_ type: NSEvent.EventType = .leftMouseDown, at point: NSPoint) -> NSEvent {
            guard let event = NSEvent.mouseEvent(
                with: type,
                location: point,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: 1
            ) else {
                preconditionFailure("could not synthesize a \(type) event")
            }
            return event
        }

        // Rows attach to the real panel, and their tracking area is the one
        // this window needs: always active, tied to the visible rect.
        row.updateTrackingAreas()
        guard let area = row.hoverTrackingArea else {
            preconditionFailure("the row installed no tracking area")
        }
        check(area.options.contains(.activeAlways), "a dropdown row tracks the pointer even though its window is not key")
        check(area.options.contains(.inVisibleRect), "the row's tracking area follows its visible rect")
        check(!area.options.contains(.activeInKeyWindow), "rows no longer depend on the panel being key")
        check(row.hoverRequiresKeyWindow == false, "rows opt out of the key-window hover rule")
        // The bar keeps its own policy: a toolbar button still only hovers in
        // the key window.
        let buttonInPanel = ToolButton(
            frame: NSRect(x: 0, y: 0, width: 40, height: 40),
            symbolName: "pencil.tip",
            normalColor: .labelColor,
            selectedColor: accentGreen,
            symbolPointSize: ToolbarChrome.symbolPointSize
        )
        content.addSubview(buttonInPanel)
        buttonInPanel.updateTrackingAreas()
        check(buttonInPanel.hoverRequiresKeyWindow, "toolbar buttons keep the key-window hover rule")
        check(buttonInPanel.hoverTrackingArea?.options.contains(.activeInKeyWindow) == true,
              "a toolbar button tracking area stays scoped to the key window")
        // Negative control, documented on purpose: in this never-key window the
        // OLD rule refuses to highlight (and its `.activeInKeyWindow` tracking
        // area never fires), which is precisely the reported bug — while the
        // fixed row does highlight in the same window.
        buttonInPanel.setHovered(true)
        check(!buttonInPanel.isHoverHighlighted, "negative control: the old key-window rule cannot highlight in a never-key panel")
        buttonInPanel.setHovered(false)
        buttonInPanel.removeFromSuperview()

        let rowCentre = NSPoint(x: row.frame.midX, y: row.frame.midY)
        let rowRestBeforeEnter = RenderEvidence.sample(patch: RenderEvidence.rowPatch(in: content),
                                                       in: content,
                                                       appearance: .aqua)
        row.mouseEntered(with: mouseEvent(at: rowCentre))
        check(row.isHovered, "a synthetic mouseEntered highlights a row in a never-key panel")
        check(RenderEvidence.sample(patch: RenderEvidence.rowPatch(in: content),
                                    in: content,
                                    appearance: .aqua) != rowRestBeforeEnter,
              "the entered state is observable in the drawn pixels")
        row.mouseExited(with: mouseEvent(at: rowCentre))
        check(!row.isHovered, "mouseExited clears the row highlight when the pointer leaves")

        // Fast passage / panel move: the row re-derives from the pointer, so a
        // stale highlight cannot stick after the row moved out from under it.
        let pointerInContent = content.convert(panel.mouseLocationOutsideOfEventStream, from: nil)
        check(!content.rows.contains { $0.frame.contains(pointerInContent) },
              "the harness pointer is parked away from the panel's rows")
        row.setHovered(true)
        check(row.isHovered, "the stale highlight is forced on for the refresh check")
        let refreshes = content.hoverRefreshCount
        content.refreshRowHover()
        check(content.hoverRefreshCount == refreshes + 1, "refreshing the rows re-derives their hover")
        check(!row.isHovered, "re-deriving hover from the pointer clears a stale row highlight")
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: panel)
        check(content.hoverRefreshCount == refreshes + 2,
              "moving the panel rebuilds the rows' tracking areas and clears stale hover")
        check(!row.isHovered, "a panel move leaves no row highlighted")

        // A click still reports its pick and never changes the group's choice.
        var picked: ToolbarItemID?
        row.onClick = { picked = row.member }
        row.mouseDown(with: mouseEvent(.leftMouseDown, at: rowCentre))
        row.mouseUp(with: mouseEvent(.leftMouseUp, at: rowCentre))
        check(picked == .pen, "clicking a row reports that member")
        check(!row.isSelected && selectedRow.isSelected,
              "clicking a row does not change which member is selected")
        row.onClick = nil

        // Same hover colour as a toolbar button, in both appearances: both
        // composite `AdaptiveChrome.subtleFill` over the same bar surface.
        let button = ToolButton(
            frame: NSRect(x: 0, y: 0, width: 40, height: 40),
            symbolName: "line.diagonal",
            normalColor: .labelColor,
            selectedColor: accentGreen,
            symbolPointSize: ToolbarChrome.symbolPointSize
        )
        for (label, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            row.setHovered(false)
            let rowRest = RenderEvidence.sample(patch: RenderEvidence.rowPatch(in: content),
                                                in: content,
                                                appearance: appearanceName)
            row.setHovered(true)
            let rowHover = RenderEvidence.sample(patch: RenderEvidence.rowPatch(in: content),
                                                 in: content,
                                                 appearance: appearanceName)
            button.setHovered(false)
            let buttonRest = RenderEvidence.sample(patch: RenderEvidence.buttonHoverPatch,
                                                   in: button,
                                                   appearance: appearanceName)
            button.setHovered(true)
            let buttonHover = RenderEvidence.sample(patch: RenderEvidence.buttonHoverPatch,
                                                    in: button,
                                                    appearance: appearanceName)
            row.setHovered(false)
            button.setHovered(false)
            check(rowRest != rowHover, "a dropdown row shows a hover fill (\(label))")
            check(buttonRest != buttonHover, "a toolbar button shows a hover fill (\(label))")
            check(rowHover.maximumChannelDelta(buttonHover) <= RenderEvidence.hoverColourTolerance,
                  "row hover \(rowHover) matches button hover \(buttonHover) in \(label) appearance")
            let rowDelta = rowHover.mean - rowRest.mean
            let buttonDelta = buttonHover.mean - buttonRest.mean
            check(abs(rowDelta - buttonDelta) <= RenderEvidence.hoverColourTolerance,
                  "row and button hover move the background by the same amount in \(label) appearance")
        }

        // The selected row keeps its stronger fill; hover must not replace it.
        selectedRow.setHovered(false)
        let selectedRest = RenderEvidence.sample(patch: RenderEvidence.rowPatch(in: content, rowIndex: 1),
                                                 in: content,
                                                 appearance: .aqua)
        selectedRow.setHovered(true)
        let selectedHovered = RenderEvidence.sample(patch: RenderEvidence.rowPatch(in: content, rowIndex: 1),
                                                    in: content,
                                                    appearance: .aqua)
        selectedRow.setHovered(false)
        check(selectedRest == selectedHovered, "hovering the selected row leaves its selected fill in place")
    }

    // MARK: - Localization

    /// The renders must show the copy the shipped app shows, not raw keys: the
    /// same `.lproj` tables `Localizer` reads are loaded, and every toolbar
    /// string is required to resolve.
    static func localizationChecks() {
        check(HarnessStrings.resourceRoot != nil, "the harness is given the app's real localization resources")
        let previous = HarnessStrings.language
        var titles: [String: [String]] = [:]
        for language in ["zh-Hans", "en"] {
            HarnessStrings.language = language
            // Reading a title loads the table (same lazily-resolved bundle as
            // `Localizer`), so the load assertion comes after the first read.
            let brush = [ToolbarItemID.pen, .marker, .spotlight].map(\.localizedTitle)
            titles[language] = brush
            check(HarnessStrings.loaded.contains(language), "\(language).lproj/Localizable.strings is loaded")
            for (member, key) in [(ToolbarItemID.pen, "tipPen"), (.marker, "tipMarker"),
                                  (.spotlight, "tipSpotlight"), (.confirm, "tipConfirm")] {
                check(member.localizedTitle != key, "\(language): \(key) resolves to real copy (\(member.localizedTitle))")
            }
            check(!brush.contains { $0.isEmpty }, "\(language): brush rows have visible names")
        }
        // Parity, not just fallback: a key missing from one language would
        // silently render English (Localizer falls back), so require each
        // shipped language to carry every toolbar string itself.
        for key in HarnessToolbarStrings.keys {
            for language in ["zh-Hans", "en"] {
                check(HarnessStrings.has(key, in: language), "\(language).lproj carries \(key)")
            }
        }
        HarnessStrings.language = previous
        check(titles["zh-Hans"] != titles["en"], "the brush rows really are translated (zh != en)")
        check(HarnessStrings.missingKeys.isEmpty,
              "no toolbar key fell back to its raw name: \(HarnessStrings.missingKeys.sorted())")
    }

    // MARK: - Whole toolbar

    /// The bar as the editor lays it out (real slots, real constants): no redo
    /// slot, one 56pt brush button, the lines group showing the arrow tool, and
    /// a greyed undo that is visibly dimmer than the available one.
    static func barChecks() {
        let geometry = RenderEvidence.barGeometry()
        check(!geometry.slots.contains(.item(.redo)), "the rendered bar has no redo slot")
        check(!geometry.slots.contains(.item(.undo)) == false, "undo keeps its slot")
        check(geometry.frame(ofGroup: .brush)?.width == HarnessBarMetrics.groupButtonWidth,
              "the brush group occupies exactly one group button")
        for member in [ToolbarItemID.pen, .marker, .spotlight] {
            check(!geometry.slots.contains(.item(member)), "\(member.rawValue) has no separate button in the bar")
        }
        check(geometry.slots.contains(.group(.shapes)) && geometry.slots.contains(.group(.lines)),
              "shapes and lines still render as their own grouped buttons")
        check(ToolbarGroupSelection.sessionDefaults.member(for: .lines) == .arrow,
              "the lines group shows the arrow tool at session start")
        check(ToolbarGroup.lines.members.first == .arrow,
              "the lines group button shows the arrow, which is its first menu member")
        check(geometry.slotCount == renderBarSlotCount, "the bar renders every visible slot exactly once")
        check(geometry.size.height == ToolbarChrome.rowHeight + HarnessBarMetrics.crossPadding * 2,
              "bar thickness is a button plus the cross padding")

        guard let undoFrame = geometry.frame(of: .undo) else {
            preconditionFailure("undo has no frame")
        }
        let patch = undoFrame.insetBy(dx: 4, dy: 4)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let enabled = RenderEvidence.sampleBar(patch: patch, appearance: name, undoEnabled: true)
            let disabled = RenderEvidence.sampleBar(patch: patch, appearance: name, undoEnabled: false)
            check(enabled != disabled, "disabled undo is drawn dimmer than the available one (\(name.rawValue))")
        }
    }

    /// `ToolbarLayout.slots` is the single source of truth; this is the count
    /// the bar must render for the persisted default minus the hidden redo.
    static var renderBarSlotCount: Int {
        ToolbarLayout.slots(for: ToolbarLayout.default.excluding([.redo])).count
    }

    // MARK: - Dropdown panel

    static func dropdownChecks() {
        let size = ToolbarGroupMenuPanel.preferredSize(members: [.pen, .marker, .spotlight])
        check(size.height == ToolbarChrome.surfacePadding * 2 + ToolbarChrome.rowHeight * 3, "panel height is three 40pt rows plus the bar padding")
        check(size.width >= ToolbarGroupMenuPanel.minimumWidth, "panel keeps a usable minimum width")

        // Keyboard bindings.
        check(ToolbarGroupMenuKeyCommand.command(forKeyCode: 126) == .moveUp, "↑ moves the highlight up")
        check(ToolbarGroupMenuKeyCommand.command(forKeyCode: 125) == .moveDown, "↓ moves the highlight down")
        check(ToolbarGroupMenuKeyCommand.command(forKeyCode: 36) == .commit, "Return commits the highlighted row")
        check(ToolbarGroupMenuKeyCommand.command(forKeyCode: 76) == .commit, "keypad Enter commits the highlighted row")
        check(ToolbarGroupMenuKeyCommand.command(forKeyCode: 53) == .cancel, "Esc closes the panel")
        check(ToolbarGroupMenuKeyCommand.command(forKeyCode: 0) == nil, "other keys stay with the editor")

        // Highlight movement wraps like a menu keyboard.
        var selection = ToolbarGroupMenuSelection(members: [.pen, .marker, .spotlight], selected: .pen)
        check(selection.currentMember == .pen, "the panel starts on the group's current member")
        check(!selection.isHighlighted(0), "no keyboard highlight until an arrow is pressed")
        selection.move(by: -1)
        check(selection.currentMember == .spotlight, "↑ from the first row wraps to the last")
        check(selection.isHighlighted(2), "the keyboard highlight follows the selection")
        selection.move(by: 1)
        check(selection.currentMember == .pen, "↓ from the last row wraps to the first")
        var single = ToolbarGroupMenuSelection(members: [.line], selected: nil)
        single.move(by: 1)
        check(single.currentMember == .line, "a single-member panel cannot move past itself")

        // Placement: below by default, flipped above at the bottom edge, and
        // clamped so the panel never leaves the screen.
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
        let panelSize = NSSize(width: 180, height: 132)
        let middle = ToolbarGroupMenuPanel.placement(
            anchorOnScreen: NSRect(x: 600, y: 500, width: 56, height: 40),
            size: panelSize,
            visibleFrame: visible
        )
        check(middle == NSPoint(x: 600, y: 500 - 132 - ToolbarChrome.dropdownGap), "panel opens below the group button")
        let nearBottom = ToolbarGroupMenuPanel.placement(
            anchorOnScreen: NSRect(x: 600, y: 4, width: 56, height: 40),
            size: panelSize,
            visibleFrame: visible
        )
        check(nearBottom.y == 44 + ToolbarChrome.dropdownGap, "panel flips above the button near the bottom edge")
        let leftEdge = ToolbarGroupMenuPanel.placement(
            anchorOnScreen: NSRect(x: 0, y: 500, width: 56, height: 40),
            size: panelSize,
            visibleFrame: visible
        )
        check(leftEdge.x == ToolbarGroupMenuPanel.edgeInset, "panel is pushed in at the left screen edge")
        let rightEdge = ToolbarGroupMenuPanel.placement(
            anchorOnScreen: NSRect(x: 1420, y: 500, width: 56, height: 40),
            size: panelSize,
            visibleFrame: visible
        )
        check(rightEdge.x == visible.maxX - panelSize.width - ToolbarGroupMenuPanel.edgeInset, "panel is pushed in at the right screen edge")
        let tinyScreen = ToolbarGroupMenuPanel.placement(
            anchorOnScreen: NSRect(x: 10, y: 10, width: 56, height: 40),
            size: panelSize,
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 100)
        )
        check(tinyScreen.y == ToolbarGroupMenuPanel.edgeInset, "panel stays inside a too-short screen instead of going off it")

        // Renders of the real dropdown content view in both appearances.
        let content = ToolbarGroupMenuContentView(frame: NSRect(origin: .zero, size: size))
        content.configure(
            members: [.pen, .marker, .spotlight],
            selected: .marker,
            selection: ToolbarGroupMenuSelection(members: [.pen, .marker, .spotlight], selected: .marker)
        )
        let lightRow = RenderEvidence.sample(patch: RenderEvidence.rowPatch(in: content), in: content, appearance: .aqua)
        content.rows[0].setHovered(true)
        let hoverRow = RenderEvidence.sample(patch: RenderEvidence.rowPatch(in: content), in: content, appearance: .aqua)
        check(lightRow != hoverRow, "a dropdown row shows the same hover fill as a toolbar button")
        content.rows[0].setHovered(false)
        let darkRow = RenderEvidence.sample(patch: RenderEvidence.rowPatch(in: content), in: content, appearance: .darkAqua)
        content.rows[0].setHovered(true)
        let darkHoverRow = RenderEvidence.sample(patch: RenderEvidence.rowPatch(in: content), in: content, appearance: .darkAqua)
        check(darkRow != darkHoverRow, "the dropdown row hover reads in dark appearance too")

        // J1-c: the lines dropdown lists the arrow first and the line second.
        let linesMembers = ToolbarGroup.lines.members
        let linesSize = ToolbarGroupMenuPanel.preferredSize(members: linesMembers)
        let linesContent = ToolbarGroupMenuContentView(frame: NSRect(origin: .zero, size: linesSize))
        linesContent.configure(
            members: linesMembers,
            selected: .arrow,
            selection: ToolbarGroupMenuSelection(members: linesMembers, selected: .arrow)
        )
        check(linesContent.rows.first?.member == .arrow, "the first row of the lines dropdown is the arrow")
        check(linesContent.rows.last?.member == .line, "the line tool follows the arrow in the dropdown")
        check(linesContent.rows.first?.isSelected == true, "the arrow row starts selected")
    }
}

/// Offscreen rendering of the production drawing code. Views are drawn into a
/// bitmap with the requested appearance current, so the samples and PNGs are
/// what the screen would show. Nothing here re-implements the toolbar's look:
/// the bar, the buttons, the divider and the dropdown all come from
/// `ToolbarChrome` / `ToolbarButtons` / `ToolbarGroupMenu`.
///
/// Set `TOOLBAR_RENDER_DIR` to write PNGs, and `TOOLBAR_STRINGS_DIR` to load the
/// app's real `.lproj` resources (see `scripts/test-toolbar-upload-removal.sh`).
enum RenderEvidence {
    struct Sample: Equatable, CustomStringConvertible {
        let r: Double
        let g: Double
        let b: Double
        let a: Double
        var mean: Double { (r + g + b) / 3 }
        var description: String { String(format: "rgba(%.1f, %.1f, %.1f, %.1f)", r, g, b, a) }

        /// Largest per-channel difference, so "same colour scale" can be
        /// asserted instead of eye-balled.
        func maximumChannelDelta(_ other: Sample) -> Double {
            max(abs(r - other.r), abs(g - other.g), abs(b - other.b), abs(a - other.a))
        }
    }

    static let scale: CGFloat = 2
    /// Patch of a 40pt button sampled away from the centred symbol.
    static let buttonPatch = NSRect(x: 4, y: 4, width: 8, height: 8)
    /// Patch of the 16pt chevron zone.
    static let chevronPatch = NSRect(x: 3, y: 4, width: 6, height: 8)
    /// Interior of a 40pt button: inside the hover/selected highlight, clear
    /// of the centred symbol and of the rounded highlight corners, so a hover
    /// fill can be compared with a dropdown row's pixel for pixel.
    static let buttonHoverPatch = NSRect(x: 32, y: 15, width: 5, height: 10)
    /// A row and a button composite the same fill over the same surface; the
    /// tolerance only absorbs rounding between two rasterisations.
    static let hoverColourTolerance: Double = 1.5

    static func rowPatch(in content: ToolbarGroupMenuContentView, rowIndex: Int = 0) -> NSRect {
        // Right-hand side of the row: past the icon and the name.
        let frame = content.rowFrame(at: rowIndex, count: content.rows.count)
        return NSRect(x: frame.maxX - 26, y: frame.minY + 8, width: 14, height: 10)
    }

    // MARK: - Bar geometry (production numbers)

    /// The bar as `ToolbarView` lays it out: same slot list (from
    /// `ToolbarLayout.slots`), same spacing/padding constants (parsed out of
    /// `ToolbarView` by the test script), same row height (from
    /// `ToolbarChrome`).
    struct BarGeometry {
        let slots: [ToolbarLayout.Slot]
        let frames: [NSRect]
        let size: NSSize

        func frame(of item: ToolbarItemID) -> NSRect? {
            if let index = slots.firstIndex(of: .item(item)) { return frames[index] }
            guard let group = ToolbarGroup.group(containing: item),
                  let index = slots.firstIndex(of: .group(group)) else { return nil }
            return frames[index]
        }

        func frame(ofGroup group: ToolbarGroup) -> NSRect? {
            guard let index = slots.firstIndex(of: .group(group)) else { return nil }
            return frames[index]
        }

        var slotCount: Int { slots.count }
    }

    static func slotWidth(_ slot: ToolbarLayout.Slot) -> CGFloat {
        switch slot {
        case .item: return ToolbarChrome.rowHeight
        case .group: return HarnessBarMetrics.groupButtonWidth
        case .divider: return HarnessBarMetrics.dividerSlotWidth
        }
    }

    /// `includingRedo` renders the pre-change bar, used only to point at where
    /// redo used to sit in the annotated image.
    static func barGeometry(includingRedo: Bool = false) -> BarGeometry {
        let layout = includingRedo ? ToolbarLayout.default : ToolbarLayout.default.excluding([.redo])
        let slots = ToolbarLayout.slots(for: layout)
        var run = HarnessBarMetrics.endPadding * 2
        for (index, slot) in slots.enumerated() {
            if index > 0 { run += HarnessBarMetrics.buttonSpacing }
            run += slotWidth(slot)
        }
        let thickness = ToolbarChrome.rowHeight + HarnessBarMetrics.crossPadding * 2
        var x = HarnessBarMetrics.endPadding
        var frames: [NSRect] = []
        for slot in slots {
            let width = slotWidth(slot)
            frames.append(NSRect(
                x: x,
                y: HarnessBarMetrics.crossPadding,
                width: width,
                height: ToolbarChrome.rowHeight
            ))
            x += width + HarnessBarMetrics.buttonSpacing
        }
        return BarGeometry(
            slots: slots,
            frames: frames,
            size: NSSize(width: max(run, thickness), height: thickness)
        )
    }

    // MARK: - Bar drawing

    static func draw(_ view: NSView, at point: NSPoint) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.translateBy(x: point.x, y: point.y)
        view.draw(view.bounds)
        cg.restoreGState()
    }

    static func drawText(
        _ text: String,
        at point: NSPoint,
        font: NSFont = .systemFont(ofSize: 11),
        color: NSColor = .labelColor
    ) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (text as NSString).draw(at: point, withAttributes: attributes)
    }

    static func drawItem(_ id: ToolbarItemID, frame: NSRect, undoEnabled: Bool) {
        let button = ToolButton(
            frame: NSRect(origin: .zero, size: frame.size),
            symbolName: id.symbolName,
            normalColor: id.normalColor,
            selectedColor: id.selectedColor,
            symbolPointSize: ToolbarChrome.symbolPointSize,
            iconImage: id.iconImage(pointSize: ToolbarChrome.symbolPointSize)
        )
        button.itemID = id
        if id == .undo && !undoEnabled {
            // Mirror `ToolbarView.setEnabled(false, for:)`.
            button.isEnabled = false
            button.alphaValue = 0.35
        }
        draw(button, at: frame.origin)
    }

    static func drawBar(_ geometry: BarGeometry, undoEnabled: Bool) {
        ToolbarChrome.drawSurface(in: NSRect(origin: .zero, size: geometry.size))
        for (slot, frame) in zip(geometry.slots, geometry.frames) {
            switch slot {
            case .item(let id):
                // `moveSelection` is a drag handle in the app; it draws the same
                // symbol on the same slot with no background, so the same button
                // drawing is visually identical.
                drawItem(id, frame: frame, undoEnabled: undoEnabled)
            case .group(let group):
                // The editor opens with the session defaults, so the render
                // shows the same member a fresh editor shows.
                let member = ToolbarGroupSelection.sessionDefaults.member(for: group)
                let toolFrame = NSRect(
                    x: frame.minX,
                    y: frame.minY,
                    width: ToolbarChrome.rowHeight,
                    height: frame.height
                )
                drawItem(member, frame: toolFrame, undoEnabled: undoEnabled)
                let chevron = ToolbarChevronButton(
                    frame: NSRect(
                        x: 0,
                        y: 0,
                        width: max(0, frame.width - ToolbarChrome.rowHeight),
                        height: frame.height
                    ),
                    symbolPointSize: 9
                )
                draw(chevron, at: NSPoint(
                    x: frame.minX + ToolbarChrome.rowHeight,
                    y: frame.minY
                ))
            case .divider:
                // `ToolbarView` puts an `NSBox` separator one button-spacing
                // into the divider slot.
                AdaptiveChrome.separator.setFill()
                NSRect(
                    x: frame.minX + HarnessBarMetrics.buttonSpacing,
                    y: frame.minY,
                    width: 1,
                    height: frame.height
                ).fill()
            }
        }
    }

    static func sampleBar(patch: NSRect, appearance name: NSAppearance.Name, undoEnabled: Bool) -> Sample {
        guard let appearance = NSAppearance(named: name) else {
            preconditionFailure("no appearance named \(name.rawValue)")
        }
        let geometry = barGeometry()
        guard let rep = render(size: geometry.size, appearance: appearance, draw: { _ in
            drawBar(geometry, undoEnabled: undoEnabled)
        }) else {
            preconditionFailure("could not render the bar")
        }
        return sample(rep: rep, patch: patch)
    }

    static func renderBar(appearance: NSAppearance, undoEnabled: Bool) -> NSBitmapImageRep? {
        let geometry = barGeometry()
        return render(size: geometry.size, appearance: appearance) { _ in
            drawBar(geometry, undoEnabled: undoEnabled)
        }
    }

    /// The bar plus a legend band that points at the four things the task asks
    /// to see: the arrow default, the single brush button, the missing redo and
    /// the undo button.
    static func renderAnnotatedBar(appearance: NSAppearance) -> NSBitmapImageRep? {
        let geometry = barGeometry()
        let withRedo = barGeometry(includingRedo: true)
        let bandHeight: CGFloat = 96
        let size = NSSize(width: geometry.size.width, height: geometry.size.height + bandHeight)
        return render(size: size, appearance: appearance) { _ in
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            drawBar(geometry, undoEnabled: true)

            let lines = geometry.frame(ofGroup: .lines)
            let brush = geometry.frame(ofGroup: .brush)
            let undo = geometry.frame(of: .undo)
            let redoX = withRedo.frame(of: .redo)?.midX
            let markers: [(String, CGFloat?)] = [
                ("①", lines?.midX),
                ("②", brush?.midX),
                ("③", redoX),
                ("④", undo?.midX),
            ]
            let base = geometry.size.height
            for (label, x) in markers {
                guard let x else { continue }
                NSColor.secondaryLabelColor.setFill()
                NSRect(x: x - 0.5, y: base + 6, width: 1, height: 14).fill()
                drawText(label, at: NSPoint(x: x - 6, y: base + 22),
                         font: .systemFont(ofSize: 14))
            }
            let legend = [
                "① 线条组默认 = 箭头（arrow）",
                "② 笔刷组（画笔/高亮笔/聚光灯）= 1 个按钮位",
                "③ redo 不在可见序列（⇧⌘Z 仍生效）",
                "④ undo 保留；灰显/可用两态见 toolbar-bar-undo-*.png",
            ]
            for (index, line) in legend.enumerated() {
                drawText(line, at: NSPoint(x: 4, y: base + 44 + CGFloat(index) * 13),
                         font: .systemFont(ofSize: 10),
                         color: .secondaryLabelColor)
            }
        }
    }

    // MARK: - Rendering primitives

    static func render(_ view: NSView, appearance: NSAppearance) -> NSBitmapImageRep? {
        render(size: view.bounds.size, appearance: appearance) { bounds in
            // Same surface the bar draws behind its buttons, so a button
            // sample sits on the material it really sits on.
            ToolbarChrome.drawSurface(in: bounds)
            view.draw(view.bounds)
        }
    }

    /// Draws the dropdown content view *and* its row subviews, offset into the
    /// panel's coordinates (a plain `draw(_:)` never paints subviews).
    static func renderMenu(
        _ content: ToolbarGroupMenuContentView,
        appearance: NSAppearance
    ) -> NSBitmapImageRep? {
        render(size: content.bounds.size, appearance: appearance) { _ in
            content.draw(content.bounds)
            for row in content.rows {
                draw(row, at: row.frame.origin)
            }
        }
    }

    static func render(
        size: NSSize,
        appearance: NSAppearance,
        draw: (NSRect) -> Void
    ) -> NSBitmapImageRep? {
        let pixelsWide = Int(size.width * scale)
        let pixelsHigh = Int(size.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: pixelsWide, height: pixelsHigh))
        appearance.performAsCurrentDrawingAppearance {
            draw(NSRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func sample(
        patch: NSRect,
        in content: ToolbarGroupMenuContentView,
        appearance name: NSAppearance.Name
    ) -> Sample {
        guard let appearance = NSAppearance(named: name) else {
            preconditionFailure("no appearance named \(name.rawValue)")
        }
        guard let rep = renderMenu(content, appearance: appearance) else {
            preconditionFailure("could not render the dropdown content")
        }
        return sample(rep: rep, patch: patch)
    }

    static func sample(patch: NSRect, in view: NSView, appearance name: NSAppearance.Name) -> Sample {
        guard let appearance = NSAppearance(named: name) else {
            preconditionFailure("no appearance named \(name.rawValue)")
        }
        guard let rep = render(view, appearance: appearance) else {
            preconditionFailure("could not render \(type(of: view))")
        }
        return sample(rep: rep, patch: patch)
    }

    static func sample(rep: NSBitmapImageRep, patch: NSRect) -> Sample {
        var total = (r: 0.0, g: 0.0, b: 0.0, a: 0.0, count: 0.0)
        let minX = Int(patch.minX * scale)
        let maxX = Int(patch.maxX * scale)
        // AppKit rects are bottom-up; bitmap rows run top-down.
        let height = Double(rep.pixelsHigh)
        let minY = Int(height - patch.maxY * Double(scale))
        let maxY = Int(height - patch.minY * Double(scale))
        for y in minY..<maxY {
            for x in minX..<maxX {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total.r += Double(color.redComponent)
                total.g += Double(color.greenComponent)
                total.b += Double(color.blueComponent)
                total.a += Double(color.alphaComponent)
                total.count += 1
            }
        }
        precondition(total.count > 0, "empty sample patch")
        return Sample(
            r: total.r / total.count * 255,
            g: total.g / total.count * 255,
            b: total.b / total.count * 255,
            a: total.a / total.count * 255
        )
    }

    // MARK: - Measurements quoted in the report

    static func measurements() -> [String: String] {
        var out: [String: String] = [:]
        let button = ToolButton(
            frame: NSRect(x: 0, y: 0, width: 40, height: 40),
            symbolName: "pencil.tip",
            normalColor: .labelColor,
            selectedColor: accentGreen,
            symbolPointSize: 18
        )
        for (label, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            button.setHovered(false)
            out["button.\(label).rest"] = "\(sample(patch: buttonPatch, in: button, appearance: name))"
            button.setHovered(true)
            out["button.\(label).hover"] = "\(sample(patch: buttonPatch, in: button, appearance: name))"
            button.isSelected = true
            out["button.\(label).selected"] = "\(sample(patch: buttonPatch, in: button, appearance: name))"
            button.isSelected = false
            button.isEnabled = false
            out["button.\(label).disabledHover"] = "\(sample(patch: buttonPatch, in: button, appearance: name))"
            button.isEnabled = true
            button.setHovered(false)
        }

        let previousLanguage = HarnessStrings.language
        for language in ["zh-Hans", "en"] {
            HarnessStrings.language = language
            let size = ToolbarGroupMenuPanel.preferredSize(members: [.pen, .marker, .spotlight])
            out["panel.\(language).size"] = String(format: "%.0fx%.0f pt", size.width, size.height)
            let content = ToolbarGroupMenuContentView(frame: NSRect(origin: .zero, size: size))
            content.configure(
                members: [.pen, .marker, .spotlight],
                selected: .marker,
                selection: ToolbarGroupMenuSelection(members: [.pen, .marker, .spotlight], selected: .marker)
            )
            let patch = rowPatch(in: content)
            out["row.\(language).rest"] = "\(sample(patch: patch, in: content, appearance: .aqua))"
            content.rows[0].setHovered(true)
            out["row.\(language).hover"] = "\(sample(patch: patch, in: content, appearance: .aqua))"
            content.rows[0].setHovered(false)
            out["row.\(language).title0"] = content.rows[0].member.localizedTitle
            out["row.\(language).title1"] = content.rows[1].member.localizedTitle
            out["row.\(language).title2"] = content.rows[2].member.localizedTitle
        }
        HarnessStrings.language = previousLanguage

        // Row hover vs toolbar-button hover: same fill, same surface, so the
        // sampled colours must agree. Quoted in the report.
        do {
            let size = ToolbarGroupMenuPanel.preferredSize(members: [.pen, .marker, .spotlight])
            let content = ToolbarGroupMenuContentView(frame: NSRect(origin: .zero, size: size))
            content.configure(
                members: [.pen, .marker, .spotlight],
                selected: .marker,
                selection: ToolbarGroupMenuSelection(members: [.pen, .marker, .spotlight], selected: .marker)
            )
            let reference = ToolButton(
                frame: NSRect(x: 0, y: 0, width: 40, height: 40),
                symbolName: "line.diagonal",
                normalColor: .labelColor,
                selectedColor: accentGreen,
                symbolPointSize: ToolbarChrome.symbolPointSize
            )
            for (label, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                content.rows[0].setHovered(false)
                let rowRest = sample(patch: rowPatch(in: content), in: content, appearance: name)
                content.rows[0].setHovered(true)
                let rowHover = sample(patch: rowPatch(in: content), in: content, appearance: name)
                content.rows[0].setHovered(false)
                reference.setHovered(false)
                let buttonRest = sample(patch: buttonHoverPatch, in: reference, appearance: name)
                reference.setHovered(true)
                let buttonHover = sample(patch: buttonHoverPatch, in: reference, appearance: name)
                reference.setHovered(false)
                out["hover.\(label).rowRest"] = "\(rowRest)"
                out["hover.\(label).rowHover"] = "\(rowHover)"
                out["hover.\(label).buttonRest"] = "\(buttonRest)"
                out["hover.\(label).buttonHover"] = "\(buttonHover)"
                out["hover.\(label).rowVsButtonDelta"] = String(format: "%.2f", rowHover.maximumChannelDelta(buttonHover))
            }
        }

        out["panel.rowHeight"] = "\(ToolbarChrome.rowHeight)"
        out["panel.surfaceRadius"] = "\(ToolbarChrome.surfaceCornerRadius)"
        out["panel.highlightRadius"] = "\(ToolbarChrome.highlightCornerRadius)"
        out["strings.root"] = HarnessStrings.resourceRoot?.path ?? "none"
        out["strings.loaded"] = HarnessStrings.loaded.sorted().joined(separator: ",")
        out["strings.missingKeys"] = HarnessStrings.missingKeys.sorted().joined(separator: ",")

        let geometry = barGeometry()
        out["bar.widthPt"] = String(format: "%.0f", geometry.size.width)
        out["bar.widthPx"] = "\(Int(geometry.size.width * scale))"
        out["bar.heightPt"] = String(format: "%.0f", geometry.size.height)
        out["bar.slotCount"] = "\(geometry.slotCount)"
        func describe(_ label: String, _ frame: NSRect?) {
            guard let frame else { return }
            out["bar.\(label).xPt"] = String(format: "%.0f", frame.minX)
            out["bar.\(label).widthPt"] = String(format: "%.0f", frame.width)
        }
        describe("shapesGroup", geometry.frame(ofGroup: .shapes))
        describe("linesGroup", geometry.frame(ofGroup: .lines))
        describe("brushGroup", geometry.frame(ofGroup: .brush))
        describe("undo", geometry.frame(of: .undo))
        describe("redoWouldBe", barGeometry(includingRedo: true).frame(of: .redo))
        out["bar.containsRedo"] = "\(geometry.slots.contains(.item(.redo)))"
        if let undo = geometry.frame(of: .undo) {
            let patch = undo.insetBy(dx: 4, dy: 4)
            out["bar.undo.light.enabled"] = "\(sampleBar(patch: patch, appearance: .aqua, undoEnabled: true))"
            out["bar.undo.light.disabled"] = "\(sampleBar(patch: patch, appearance: .aqua, undoEnabled: false))"
            out["bar.undo.dark.enabled"] = "\(sampleBar(patch: patch, appearance: .darkAqua, undoEnabled: true))"
            out["bar.undo.dark.disabled"] = "\(sampleBar(patch: patch, appearance: .darkAqua, undoEnabled: false))"
        }
        return out
    }

    // MARK: - PNG output

    /// Writes PNGs of every state when `TOOLBAR_RENDER_DIR` is set. Returns the
    /// number of files written.
    static func writeIfRequested() -> Int {
        guard let directory = ProcessInfo.processInfo.environment["TOOLBAR_RENDER_DIR"] else {
            return 0
        }
        let base = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var written = 0

        func save(_ rep: NSBitmapImageRep?, _ name: String) {
            guard let rep, let data = rep.representation(using: .png, properties: [:]) else { return }
            guard (try? data.write(to: base.appendingPathComponent(name))) != nil else { return }
            written += 1
        }

        let button = ToolButton(
            frame: NSRect(x: 0, y: 0, width: 40, height: 40),
            symbolName: "pencil.tip",
            normalColor: .labelColor,
            selectedColor: accentGreen,
            symbolPointSize: 18
        )
        let previousLanguage = HarnessStrings.language
        for (name, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            guard let resolved = NSAppearance(named: appearanceName) else { continue }
            button.setHovered(false)
            save(render(button, appearance: resolved), "toolbar-button-rest-\(name).png")
            button.setHovered(true)
            save(render(button, appearance: resolved), "toolbar-button-hover-\(name).png")
            button.isSelected = true
            save(render(button, appearance: resolved), "toolbar-button-selected-\(name).png")
            button.isSelected = false
            button.setHovered(false)

            // Grouped button: the 40pt tool half plus the 16pt chevron half,
            // drawn on the bar surface (the two production controls that
            // `ToolbarGroupButton` composes).
            let groupSize = NSSize(width: HarnessBarMetrics.groupButtonWidth, height: ToolbarChrome.rowHeight)
            let groupHalf = ToolButton(
                frame: NSRect(x: 0, y: 0, width: ToolbarChrome.rowHeight, height: ToolbarChrome.rowHeight),
                symbolName: "pencil.tip",
                normalColor: .labelColor,
                selectedColor: accentGreen,
                symbolPointSize: 18
            )
            let groupChevron = ToolbarChevronButton(
                frame: NSRect(
                    x: ToolbarChrome.rowHeight,
                    y: 0,
                    width: groupSize.width - ToolbarChrome.rowHeight,
                    height: ToolbarChrome.rowHeight
                ),
                symbolPointSize: 9
            )
            func renderGroup() -> NSBitmapImageRep? {
                render(size: groupSize, appearance: resolved) { bounds in
                    ToolbarChrome.drawSurface(in: bounds)
                    groupHalf.draw(groupHalf.bounds)
                    guard let cg = NSGraphicsContext.current?.cgContext else { return }
                    cg.saveGState()
                    cg.translateBy(x: groupChevron.frame.minX, y: groupChevron.frame.minY)
                    groupChevron.draw(groupChevron.bounds)
                    cg.restoreGState()
                }
            }
            save(renderGroup(), "toolbar-group-rest-\(name).png")
            groupChevron.setHovered(true)
            save(renderGroup(), "toolbar-group-chevron-hover-\(name).png")
            groupChevron.setHovered(false)

            // Dropdown with the app's real copy, per language.
            for (tag, language) in [("zh", "zh-Hans"), ("en", "en")] {
                HarnessStrings.language = language
                let size = ToolbarGroupMenuPanel.preferredSize(members: [.pen, .marker, .spotlight])
                let content = ToolbarGroupMenuContentView(frame: NSRect(origin: .zero, size: size))
                content.configure(
                    members: [.pen, .marker, .spotlight],
                    selected: .marker,
                    selection: ToolbarGroupMenuSelection(members: [.pen, .marker, .spotlight], selected: .marker)
                )
                save(renderMenu(content, appearance: resolved), "toolbar-dropdown-\(tag)-\(name).png")
                content.rows[0].setHovered(true)
                save(renderMenu(content, appearance: resolved), "toolbar-dropdown-\(tag)-hover-\(name).png")
                content.rows[0].setHovered(false)
            }
            // Lines dropdown (J1-c): arrow first, then line, with the app's
            // real copy in each language.
            for (tag, language) in [("zh", "zh-Hans"), ("en", "en")] {
                HarnessStrings.language = language
                let members = ToolbarGroup.lines.members
                let size = ToolbarGroupMenuPanel.preferredSize(members: members)
                let content = ToolbarGroupMenuContentView(frame: NSRect(origin: .zero, size: size))
                content.configure(
                    members: members,
                    selected: .arrow,
                    selection: ToolbarGroupMenuSelection(members: members, selected: .arrow)
                )
                save(renderMenu(content, appearance: resolved), "toolbar-dropdown-lines-\(tag)-\(name).png")
            }
            HarnessStrings.language = previousLanguage

            // Whole toolbar, once with history (undo available) and once as the
            // editor opens (undo greyed out), plus an annotated copy.
            save(renderBar(appearance: resolved, undoEnabled: true), "toolbar-bar-\(name).png")
            save(renderBar(appearance: resolved, undoEnabled: false), "toolbar-bar-undo-disabled-\(name).png")
            save(renderAnnotatedBar(appearance: resolved), "toolbar-bar-annotated-\(name).png")
        }
        return written
    }
}
