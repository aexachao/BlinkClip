#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ARTIFACT_TASK_DIR/build/module-cache" "$ARTIFACT_TASK_DIR/out" "$ARTIFACT_TASK_DIR/out/renders"
python3 - "$replica_root" "$ARTIFACT_TASK_DIR" <<'PY'
from pathlib import Path
import re,sys,hashlib,json
r,t=map(Path,sys.argv[1:]); layout=r/'Vendor/capcap/Editor/ToolbarLayout.swift'
names=sorted(set(re.findall(r'L10n\.(\w+)',layout.read_text())))
controller=(r/'Vendor/capcap/Editor/EditWindowController.swift').read_text()
# The offscreen bar render must use the production geometry, not a copy, so
# these numbers are parsed out of ToolbarView and baked into the harness.
toolbar_source=controller.split('class ToolbarView: NSView',1)[1]
metrics={}
for metric in ['buttonSpacing','endPadding','crossPadding','groupButtonWidth','dividerSlotWidth']:
    found=re.search(r'static let '+metric+r': CGFloat = ([0-9.]+)',toolbar_source)
    assert found, f'ToolbarView.{metric} is no longer a numeric literal'
    metrics[metric]=found.group(1)
stubs='''import AppKit
enum EditTool { case rectangle,ellipse,arrow,line,pen,marker,spotlight,mosaic,eraser,magnifier,numbered,text,emoji }
enum Defaults { }
enum EditorShortcutAction { case toolbar(ToolbarItemID) }
enum EditorShortcutRegistry { static func displayString(for: EditorShortcutAction) -> String? { nil } }
extension ToolbarItemID { var supportsEditorShortcut: Bool { true } }
enum ToolTipWindow {
    static func show(text: String, anchor: NSRect, delay: TimeInterval = 0.35) { }
    static func hide() { }
}
// Parsed from ToolbarView by scripts/test-toolbar-upload-removal.sh, so the
// harness bar render uses the production geometry instead of a second copy.
enum HarnessBarMetrics {
'''+''.join('static let '+k+': CGFloat = '+v+'\n' for k,v in metrics.items())+'''}

/// Loads the app\'s own `Localizable.strings`, exactly where `Localizer` looks
/// (an `<lang>.lproj` inside Contents/Resources), so renders show the copy the
/// shipped app shows instead of raw keys. Records misses so a missing key shows
/// up as a failure rather than as a silent fallback.
enum HarnessStrings {
    static var language = "zh-Hans"
    private static var tables: [String: [String: String]] = [:]
    private(set) static var missingKeys: Set<String> = []
    private(set) static var loaded: Set<String> = []

    static var resourceRoot: URL? {
        guard let path = ProcessInfo.processInfo.environment["TOOLBAR_STRINGS_DIR"], !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func table(for language: String) -> [String: String]? {
        if let cached = tables[language] { return cached }
        guard let root = resourceRoot else { return nil }
        let file = root
            .appendingPathComponent("\(language).lproj")
            .appendingPathComponent("Localizable.strings")
        guard FileManager.default.fileExists(atPath: file.path),
              let dictionary = NSDictionary(contentsOf: file) as? [String: String]
        else { return nil }
        tables[language] = dictionary
        loaded.insert(language)
        return dictionary
    }

    /// Is `key` present in that language's table (no fallback applied)?
    static func has(_ key: String, in language: String) -> Bool {
        table(for: language)?[key] != nil
    }

    /// Mirrors `Localizer.string`: current language, then English, then the key.
    static func value(_ key: String) -> String {
        if let value = table(for: language)?[key] { return value }
        if language != "en", let english = table(for: "en")?[key] { return english }
        missingKeys.insert(key)
        return key
    }
}
/// Every string the toolbar reads, so the harness can require it in each
/// shipped language instead of settling for `Localizer`'s English fallback.
enum HarnessToolbarStrings {
'''+'static let keys = ['+','.join('"'+n+'"' for n in names)+']\n'+'''}

enum L10n {
'''+''.join('static var '+n+': String { HarnessStrings.value("'+n+'") }\n' for n in names)+'}\n'
# accentGreen now lives in the production ToolbarChrome.swift, not in a stub.
(t/'build/PresentationDependencyStubs.swift').write_text(stubs)
dispatch=controller.split('private func performToolbarItem(',1)[1].split('case .upload:',1)[1].split('case .pin:',1)[0]
assert 'return false' in dispatch and 'upload()' not in dispatch
toolbarView=controller.split('class ToolbarView: NSView',1)[1]
assert 'Orientation' not in toolbarView, 'single horizontal bar has no vertical orientation'
assert 'class ToolbarGroupButton' in controller, 'grouped tools render as dropdown buttons'
assert 'func setVisible(' in toolbarView, 'scenario-unavailable items hide instead of greying out'
assert 'func setEnabled(' in toolbarView, 'undo keeps the grey-out mechanism'
layout_text=layout.read_text()
assert 'filter { $0 != .upload }' in layout_text, 'slot building filters unsupported upload before geometry'
assert 'case divider' in layout_text and '[.divider]' in layout_text, 'single bar carries a divider slot between the two runs'
registry=(r/'Vendor/capcap/Editor/EditorShortcutRegistry.swift').read_text()
assert 'ToolbarLayout.canonicalOrder' in registry

# --- Requirement gates for the toolbar rework -------------------------------
# 1. Hover: tracking area + shared adaptive fill, never on a disabled control.
chrome=(r/'Vendor/capcap/Editor/ToolbarChrome.swift').read_text()
buttons=(r/'Vendor/capcap/Editor/ToolbarButtons.swift').read_text()
assert 'NSTrackingArea(' in chrome and '.mouseEnteredAndExited' in chrome, 'hover uses a tracking area with enter/exit'
assert '.activeInKeyWindow' in chrome, 'hover tracking is scoped to the key window'
assert 'hoverRequiresKeyWindow' in chrome and '.activeAlways' in chrome, 'never-key controls (dropdown rows) can opt into always-on tracking'
assert 'resyncHoverWithPointer' in chrome and 'refreshHoverTrackingArea' in chrome, 'hover state is re-derived instead of trusting the last event'
assert 'AdaptiveChrome.subtleFill' in chrome, 'hover fill uses the adaptive chrome token, not a literal RGB'
assert 'guard hovered, enabled else { return }' in chrome, 'disabled controls draw no hover fill'
assert 'drawHoverBackground' in buttons, 'tool buttons paint the hover fill'
assert 'drawSelectedBackground' in buttons, 'selected state keeps its own, stronger fill'
assert 'class ToolbarChevronButton' in buttons, 'the group chevron is a hoverable control too'
assert 'ToolbarChrome.drawSurface(in: bounds)' in toolbarView, 'the bar surface comes from the shared chrome helper'
assert 'keyboardOnlyItems' in toolbarView and '[.redo]' in toolbarView, 'redo is hidden through the runtime hide mechanism'
assert 'guard !Self.keyboardOnlyItems.contains(id) else { return }' in toolbarView, 'redo cannot be shown again by a scenario'
assert 'ToolbarGroupMenuPanel.present(' in controller, 'the chevron opens the self-drawn panel'
group_button=controller.split('final class ToolbarGroupButton',1)[1].split('final class MoveSelectionDragHandle',1)[0]
assert 'NSMenu()' not in group_button, 'the group dropdown no longer uses a system menu'
panel=(r/'Vendor/capcap/Editor/ToolbarGroupMenu.swift').read_text()
assert 'ToolbarChrome.drawSurface(in: bounds, bordered: true)' in panel, 'the panel reuses the bar surface helper'
assert 'NSColor(red:' not in panel, 'panel colours come from the shared chrome tokens, not literals'
assert 'ToolbarChrome.drawHoverBackground(' in panel, 'row hover uses the same fill helper as a toolbar button'
# 1b. Dropdown rows live in a never-key panel: their tracking must not be
# scoped to the key window, and a panel move must rebuild it.
assert 'var hoverRequiresKeyWindow: Bool { false }' in panel, 'dropdown rows opt out of the key-window hover rule'
assert 'NSWindow.didMoveNotification' in panel and 'refreshRowHover()' in panel, 'moving the panel re-derives row hover'
assert 'func refreshHoverTracking()' in panel, 'rows can reinstall their tracking area on demand'
assert 'isSelected' in panel and 'drawSelectedBackground' in panel, 'the selected row keeps its own stronger fill'
assert 'canBecomeKey: Bool { false }' in panel, 'the panel still never becomes key (the editor keeps focus)'
assert 'setAccessibilityRole(.menuItem)' in panel and 'setAccessibilityLabel(title)' in panel and 'setAccessibilitySelected(isSelected)' in panel, 'each row exposes its name and selected state to VoiceOver'
assert 'ToolbarGroupMenuKeyCommand' in panel and 'addLocalMonitorForEvents' in panel, 'the panel handles its own keys'
assert 'didResignKeyNotification' in panel and 'willCloseNotification' in panel, 'the panel closes when the editor window resigns key or is torn down'
assert 'ToolbarGroupMenuPanel.presentedPanel?.handleKeyDown(event)' in controller, 'the dropdown claims arrow/Return/Esc before the capture overlay treats Esc as cancel'
# 2/3. Group inventory: arrow default, brush group.
assert 'defaultMember: .arrow' in layout_text, 'lines default to the arrow tool'
assert 'ToolbarGroup(id: "lines", members: [.arrow, .line], defaultMember: .arrow)' in layout_text, 'the lines dropdown lists the arrow first'
assert 'ToolbarGroup(id: "brush", members: [.pen, .marker, .spotlight], defaultMember: .pen)' in layout_text, 'pen/highlighter/spotlight are one brush group'
assert 'static let all: [ToolbarGroup] = [.shapes, .lines, .brush]' in layout_text, 'all three groups are registered'
# 6. One-time group-selection migration: its own schema marker, `lines=line`
# rewritten once, and a later explicit pick written with the current schema.
# The migration stays for old maps, but a new editor never reads the stored
# map: session start overwrites it with the defaults (J1-f).
assert 'static let schemaDefaultsKey = "editor.toolbarGroupSelection.schema"' in layout_text, 'the schema marker uses its own key'
assert 'static let schemaVersion = 2' in layout_text, 'the migration is versioned'
assert 'static func migrating(dictionary: [String: String], storedSchema: Int?) -> Migration' in layout_text, 'the migration is a pure, testable function'
assert 'if persisted[ToolbarGroup.lines.id] == ToolbarItemID.line.rawValue' in layout_text, 'only the stale lines default is rewritten'
assert 'if migration.needsSchemaWrite' in layout_text, 'the schema is stamped once'
assert 'ToolbarGroupSelection.schemaDefaultsKey' in layout_text and 'ToolbarGroupSelection.defaultsKey' in layout_text, 'read and write go through the shared keys'
assert 'defaults.set(ToolbarGroupSelection.schemaVersion, forKey: ToolbarGroupSelection.schemaDefaultsKey)' in layout_text, 'an explicit pick marks the state as migrated'
# 7. Per-session group reset (J1-f): every new editor starts on rectangle /
# arrow / pen and writes those defaults back, so storage cannot resurface the
# previous session's pick.
assert 'static var sessionDefaults: ToolbarGroupSelection' in layout_text, 'the session default selection is an explicit value'
assert 'static func resetToolbarGroupSelectionForNewSession(in defaults: UserDefaults = .standard)' in layout_text, 'session start has an explicit reset-and-persist entry point'
assert 'setToolbarGroupSelection(selection, in: defaults)' in layout_text, 'the reset writes the defaults back'
assert 'Defaults.resetToolbarGroupSelectionForNewSession()' in controller, 'the editor builds its bar from the session defaults'
show_toolbar=controller.split('private func showToolbar()',1)[1].split('private func resetActiveToolForNewSession',1)[0]
assert 'Defaults.toolbarGroupSelection' not in show_toolbar, 'a new session never reads the stored group selection'
# 8. A new editor session has no active annotation tool (J1-d).
assert 'private var activeTool: EditTool = .none' in controller, 'the editor field starts with no active tool'
assert 'resetActiveToolForNewSession()' in controller, 'the session start resets the active tool explicitly'
reset_block=controller.split('private func resetActiveToolForNewSession()',1)[1].split('/// Injects the controller',1)[0]
assert 'activeTool = .none' in reset_block and 'canvasView?.activeTool = .none' in reset_block, 'both the controller and the canvas start with no tool'
assert 'toolbarView?.updateSelection(tool: .none)' in reset_block, 'the reset clears any toolbar highlight'
assert 'subToolbarView?.removeFromSuperview()' in reset_block, 'the reset drops a stale sub-toolbar'
# 4. Redo shortcut is ⇧⌘Z.
redo_block=registry.split('case .toolbar(.redo):',1)[1].split('case .toolbar(.pin):',1)[0]
assert 'UInt32(cmdKey) | UInt32(shiftKey)' in redo_block, 'redo keeps its registration with the ⇧⌘Z chord'
assert 'modifiers = 0' not in redo_block, 'the old bare-Z redo binding is gone'
# 5. Confirm tooltip.
for lang,value in [('zh-Hans','完成'),('en','Done')]:
    strings=(r/f'Vendor/capcap/Resources/{lang}.lproj/Localizable.strings').read_text()
    assert f'"tipConfirm" = "{value}";' in strings, f'tipConfirm is "{value}" in {lang}'
    assert '复制到剪贴板' not in re.findall(r'"tipConfirm" = "([^"]*)"', strings)[0], 'old Chinese tooltip is gone'
    assert 'Copy to Clipboard' not in re.findall(r'"tipConfirm" = "([^"]*)"', strings)[0], 'old English tooltip is gone'

(t/'out/entrypoint-review.json').write_text(json.dumps({'passed':True,'checks':[
  'legacy upload dispatch rejects without invoking upload',
  'single horizontal toolbar filters unsupported upload before geometry',
  'shortcut action inventory uses the filtered canonical order',
  'hover: tracking area, key-window scoping, adaptive fill, disabled suppressed, chevron included',
  'dropdown row hover: always-on tracking in the never-key panel, refresh on panel move, same fill as the bar, selected fill intact',
  'grouping: lines default arrow, brush group registered, document order preserved',
  'lines dropdown: arrow is the first menu row, then line',
  'group selection: one-time schema-2 migration kept for old maps; every editor session resets shapes/lines/brush to rectangle/arrow/pen and writes the defaults back',
  'editor session: no annotation tool is active when a new editor opens (no highlight, no sub-toolbar)',
  'redo: runtime-hidden from the bar, ⇧⌘Z binding kept in the registry',
  'dropdown: self-drawn panel reuses the bar surface, no NSMenu, keyboard + VoiceOver + resign-key dismissal',
  'confirm tooltip: 完成 / Done in both localizations',
],'boundary':'Source entrypoint review plus the native harness render/sampling below; the harness drives the per-session group reset through a scratch UserDefaults suite, the lines dropdown order through the real menu content view, and row hover through synthetic mouse events inside a real non-key NSPanel, not a click-driven editor session'},indent=2))
paths=[layout,r/'Vendor/capcap/Editor/EditWindowController.swift',r/'Vendor/capcap/Editor/EditorShortcutRegistry.swift',
       r/'Vendor/capcap/Editor/ToolbarChrome.swift',r/'Vendor/capcap/Editor/ToolbarButtons.swift',
       r/'Vendor/capcap/Editor/ToolbarGroupMenu.swift',
       r/'Tests/Native/ToolbarUploadRemovalHarness.swift',r/'scripts/test-toolbar-upload-removal.sh']
(t/'out/source-sha256.json').write_text(json.dumps({str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2))
PY
# Prefer the installed app's resources (what ships); fall back to the source
# .lproj when the app has not been built in this checkout.
strings_root="$replica_root/dist/BlinkClip.app/Contents/Resources"
if [[ ! -d "$strings_root/zh-Hans.lproj" ]]; then
  strings_root="$replica_root/Vendor/capcap/Resources"
fi
printf '%s\n' "$strings_root" > "$ARTIFACT_TASK_DIR/out/strings-root.txt"
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$ARTIFACT_TASK_DIR/build/module-cache" \
  "$ARTIFACT_TASK_DIR/build/PresentationDependencyStubs.swift" \
  "$replica_root/Vendor/capcap/UI/AdaptiveChrome.swift" \
  "$replica_root/Vendor/capcap/Editor/ToolbarChrome.swift" \
  "$replica_root/Vendor/capcap/Editor/ToolbarLayout.swift" \
  "$replica_root/Vendor/capcap/Editor/ToolbarButtons.swift" \
  "$replica_root/Vendor/capcap/Editor/ToolbarGroupMenu.swift" \
  "$replica_root/Tests/Native/ToolbarUploadRemovalHarness.swift" \
  -o "$ARTIFACT_TASK_DIR/build/toolbar-upload-harness" > "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
# Fresh evidence every run: stale PNGs from an older renderer would otherwise
# keep sitting next to the current ones.
rm -f "$ARTIFACT_TASK_DIR/out/renders"/*.png
TOOLBAR_RENDER_DIR="$ARTIFACT_TASK_DIR/out/renders" TOOLBAR_STRINGS_DIR="$strings_root" \
  "$ARTIFACT_TASK_DIR/build/toolbar-upload-harness" > "$ARTIFACT_TASK_DIR/out/result.json"
cat "$ARTIFACT_TASK_DIR/out/result.json"
