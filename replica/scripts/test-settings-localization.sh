#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run via storage-guard run --repo blinkclip --task settings-localization -- ...}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build="$ARTIFACT_TASK_DIR/build"
test_out="$ARTIFACT_TASK_DIR/out"
mkdir -p "$test_build/tmp" "$test_build/module-cache" "$test_out"
export TMPDIR="$test_build/tmp/"
export CLANG_MODULE_CACHE_PATH="$test_build/module-cache"
export SWIFT_MODULECACHE_PATH="$test_build/module-cache"
sources=("$replica_root/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift" "$replica_root/Tests/Native/SettingsLocalizationHarness.swift")
shasum -a 256 "${sources[@]}" > "$test_out/production-inputs.sha256"
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$test_build/module-cache" "${sources[@]}" \
  -o "$test_build/settings-localization" > "$test_out/compile.log" 2>&1
for language in en zh-Hans; do
  "$test_build/settings-localization" "$language" "$test_out/$language.json" \
    -AppleLanguages "($language)" > "$test_out/$language.log" 2>&1
  cat "$test_out/$language.log"
done
python3 - "$replica_root" "$test_out" <<'PY'
import json, pathlib, sys
root, out = map(pathlib.Path, sys.argv[1:])
checks = {
    'settings-window-title-provider': 'makeWindow(title: ScreenshotSettingsCopy.text(.settingsWindowTitle)' in (root / 'Sources/BlinkClip/UI/ReplicaUIController.swift').read_text(),
    'recorder-accessibility-provider': '.accessibilityLabel(ScreenshotSettingsCopy.shortcutAccessibilityLabel(for: label))' in (root / 'Sources/BlinkClip/UI/ShortcutRecorder.swift').read_text(),
    'disabled-run-status-provider': 'if arguments.contains("--no-global-hotkey") {\n            ui.hotKeyStatusMessage = ScreenshotSettingsCopy.text(.hotKeysDisabledForRun)' in (root / 'Sources/BlinkClip/AppMain.swift').read_text(),
    'settings-help-consumes-status': '.help(state.hotKeyStatusMessage)' in (root / 'Sources/BlinkClip/UI/AuxiliaryViews.swift').read_text(),
}
(out / 'source-wiring.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print(f'Production wiring: {len(checks)} checks passed')
PY
