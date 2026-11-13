#!/bin/bash
set -euo pipefail
if [[ -z "${ARTIFACT_TASK_DIR:-}" ]]; then
  exec "$HOME/dev-artifacts/bin/storage-guard" run --repo blinkclip --task settings-window-focus -- bash "$0" "$@"
fi
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp/"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$ARTIFACT_TASK_DIR/out"
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  "$replica_root/Sources/BlinkClip/UI/SettingsWindowFocusRestore.swift" \
  "$replica_root/Tests/Native/SettingsWindowFocusRestoreHarness.swift" \
  -o "$ARTIFACT_TASK_DIR/build/settings-window-focus" > "$ARTIFACT_TASK_DIR/out/compile.log" 2>&1
for language in en zh-Hans; do
  "$ARTIFACT_TASK_DIR/build/settings-window-focus" -AppleLanguages "($language)" \
    | tee "$ARTIFACT_TASK_DIR/out/result-$language.json"
done
# Production wiring: the window is registered by the settings controller and the
# permission model arms the return before the permission action opens System Settings.
python3 - "$replica_root" "$ARTIFACT_TASK_DIR" <<'PY'
import json, pathlib, sys
root, out = (pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))
controller = (root / 'Sources/BlinkClip/UI/ReplicaUIController.swift').read_text()
permission = (root / 'Sources/BlinkClip/UI/PermissionStatusView.swift').read_text()
action = (root / 'Sources/BlinkClip/UI/AccessibilityRequestAction.swift').read_text()
manifest = (root / 'Sources/BlinkClip/UI/SettingsWindowFocusRestore.swift').read_text()
checks = {
    'settings-window-attached': 'SettingsWindowFocusRestore.shared.attach(to: settingsWindow)' in controller,
    'permission-flow-arms-return': 'SettingsWindowFocusRestore.shared.expectReturnFromSystemSettings()' in permission,
    'both-return-paths-armed': permission.count('willOpenSystemSettings()') >= 3,
    'system-settings-return-seam': 'didDeactivateApplicationNotification' in manifest and 'didTerminateApplicationNotification' in manifest,
    'no-always-on-top-level': '.floating' not in manifest and 'window.level =' not in manifest,
    'no-panel-focus-steal': 'showPanel()' not in manifest,
    'signed-action-untouched': 'expectReturnFromSystemSettings' not in action,
}
(out / 'out' / 'wiring.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print(f'Production wiring: {len(checks)} checks passed')
PY
