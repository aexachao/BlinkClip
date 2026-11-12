#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ARTIFACT_TASK_DIR/build/module-cache" "$ARTIFACT_TASK_DIR/out"
python3 - "$replica_root" "$ARTIFACT_TASK_DIR" <<'PY'
from pathlib import Path
import re,sys,hashlib,json
r,t=map(Path,sys.argv[1:]); layout=r/'Vendor/capcap/Editor/ToolbarLayout.swift'
names=sorted(set(re.findall(r'L10n\.(\w+)',layout.read_text())))
stubs='''import AppKit
enum EditTool { case rectangle,ellipse,arrow,line,pen,marker,spotlight,mosaic,eraser,magnifier,numbered,text,emoji }
enum Defaults { }
enum EditorShortcutAction { case toolbar(ToolbarItemID) }
enum EditorShortcutRegistry { static func displayString(for: EditorShortcutAction) -> String? { nil } }
extension ToolbarItemID { var supportsEditorShortcut: Bool { true } }
let accentGreen = NSColor.green
enum L10n {
'''+''.join('static let '+n+' = "'+n+'"\n' for n in names)+'}\n'
(t/'build/PresentationDependencyStubs.swift').write_text(stubs)
controller=(r/'Vendor/capcap/Editor/EditWindowController.swift').read_text()
dispatch=controller.split('private func performToolbarItem(',1)[1].split('case .upload:',1)[1].split('case .pin:',1)[0]
assert 'return false' in dispatch and 'upload()' not in dispatch
toolbarView=controller.split('class ToolbarView: NSView',1)[1]
assert 'Orientation' not in toolbarView, 'single horizontal bar has no vertical orientation'
assert 'class ToolbarGroupButton' in controller, 'grouped tools render as dropdown buttons'
assert 'func setVisible(' in toolbarView, 'scenario-unavailable items hide instead of greying out'
assert 'func setEnabled(' in toolbarView, 'undo/redo keep the grey-out mechanism'
layout_text=layout.read_text()
assert 'filter { $0 != .upload }' in layout_text, 'slot building filters unsupported upload before geometry'
assert 'case divider' in layout_text and '[.divider]' in layout_text, 'single bar carries a divider slot between the two runs'
registry=(r/'Vendor/capcap/Editor/EditorShortcutRegistry.swift').read_text()
assert 'ToolbarLayout.canonicalOrder' in registry
(t/'out/entrypoint-review.json').write_text(json.dumps({'passed':True,'checks':['legacy upload dispatch rejects without invoking upload','single horizontal toolbar filters unsupported upload before geometry','shortcut action inventory uses the filtered canonical order'],'boundary':'Source entrypoint review; not a native editor click or upload test'},indent=2))
paths=[layout,r/'Vendor/capcap/Editor/EditWindowController.swift',r/'Tests/Native/ToolbarUploadRemovalHarness.swift',r/'scripts/test-toolbar-upload-removal.sh']
(t/'out/source-sha256.json').write_text(json.dumps({str(p.relative_to(r)):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths},indent=2))
PY
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$ARTIFACT_TASK_DIR/build/module-cache" \
  "$ARTIFACT_TASK_DIR/build/PresentationDependencyStubs.swift" \
  "$replica_root/Vendor/capcap/Editor/ToolbarLayout.swift" \
  "$replica_root/Tests/Native/ToolbarUploadRemovalHarness.swift" \
  -o "$ARTIFACT_TASK_DIR/build/toolbar-upload-harness" > "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
"$ARTIFACT_TASK_DIR/build/toolbar-upload-harness" > "$ARTIFACT_TASK_DIR/out/result.json"
cat "$ARTIFACT_TASK_DIR/out/result.json"
