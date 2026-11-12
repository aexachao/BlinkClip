import AppKit

@main struct ToolbarUploadRemovalHarness {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let supported = ToolbarLayout.canonicalOrder
        check(!supported.contains(.upload), "upload is not an offered editor action")
        check(ToolbarItemID(rawValue: "upload") == .upload, "old persisted raw value still decodes")
        check(Set(supported).count == supported.count, "canonical supported actions remain unique")
        check(Set(supported) == Set(ToolbarItemID.allCases.filter { $0 != .upload }), "all other tools remain available")

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
        // Single-row bar: the persisted primary run comes first, then one
        // divider, then the former side run. Grouped tools collapse into
        // one dropdown slot; a group with a single visible member renders
        // as that member's plain button.
        let merged = ToolbarLayout.default.visibleItems
        check(merged == ToolbarLayout.default.primary + ToolbarLayout.default.side, "single bar merges primary then side")
        check(ToolbarLayout.default.dividerIndex == ToolbarLayout.default.primary.count, "divider sits after the primary run")
        let slots = ToolbarLayout.slots(for: .default)
        check(slots.filter { $0 == .divider }.count == 1, "exactly one divider slot")
        check(slots.contains(.group(.shapes)), "shapes collapse into one dropdown button")
        check(slots.contains(.group(.lines)), "lines collapse into one dropdown button")
        check(!slots.contains(.item(.rectangle)) && !slots.contains(.item(.ellipse)), "grouped shape members do not render as plain buttons")
        check(!slots.contains(.item(.line)) && !slots.contains(.item(.arrow)), "grouped line members do not render as plain buttons")
        var oneHidden = ToolbarLayout.default
        oneHidden.hidden.append(.ellipse)
        oneHidden.primary.removeAll { $0 == .ellipse }
        let oneSlots = ToolbarLayout.slots(for: oneHidden.normalized())
        check(oneSlots.contains(.item(.rectangle)) && !oneSlots.contains(.group(.shapes)), "single visible member renders as a plain button")
        check(ToolbarLayout.slots(for: ToolbarLayout(dictionary: ToolbarLayout.default.dictionary).normalized()) == slots, "old primary/side layout renders identically in the single bar")
        // Group selection: defaults, last-used persistence, stale fallback.
        check(ToolbarGroupSelection.empty.member(for: .shapes) == .rectangle, "shapes default to rectangle")
        check(ToolbarGroupSelection.empty.member(for: .lines) == .line, "lines default to line")
        let picked = ToolbarGroupSelection.empty.selecting(.ellipse, in: .shapes)
        check(picked.member(for: .shapes) == .ellipse, "last-used shape is remembered")
        check(ToolbarGroupSelection(dictionary: picked.dictionary) == picked, "group selection round-trips through persistence")
        check(ToolbarGroupSelection(dictionary: ["shapes": "nope"]).member(for: .shapes) == .rectangle, "unknown persisted value falls back to default")
        check(ToolbarGroupSelection(dictionary: ["shapes": "arrow"]).member(for: .shapes) == .rectangle, "non-member persisted value falls back to default")
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
        print("{\"passed\":true,\"checks\":\(checks),\"boundary\":\"Actual production ToolbarLayout with presentation dependency stubs; persisted layout migration and supported-action inventory. No network, user defaults, or editor UI interaction.\"}")
    }
}
