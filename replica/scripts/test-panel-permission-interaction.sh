#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export BLINKCLIP_BUILD_ROOT="$ARTIFACT_TASK_DIR/build/swiftpm"
export BLINKCLIP_APP_OUTPUT_DIR="$ARTIFACT_TASK_DIR/out"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$ARTIFACT_TASK_DIR/out/qa"
python3 - "$replica_root" "$ARTIFACT_TASK_DIR/out/source-before.json" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
files = [p for folder in ('Sources', 'Vendor', 'Assets') for p in (root/folder).rglob('*') if p.is_file()]
files += [root/'Package.swift', root/'scripts/build-app.sh', root.parent/'package.json']
json.dump({str(p.relative_to(root.parent)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}, open(sys.argv[2], 'w'), indent=2)
PY
bash "$replica_root/scripts/build-app.sh" release native > "$ARTIFACT_TASK_DIR/out/native-build.log" 2>&1
python3 - "$replica_root" "$ARTIFACT_TASK_DIR/out" <<'PY'
import hashlib, json, pathlib, plistlib, subprocess, sys
root, out = map(pathlib.Path, sys.argv[1:])
before = json.load(open(out/'source-before.json'))
files = [p for folder in ('Sources', 'Vendor', 'Assets') for p in (root/folder).rglob('*') if p.is_file()]
files += [root/'Package.swift', root/'scripts/build-app.sh', root.parent/'package.json']
after = {str(p.relative_to(root.parent)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
json.dump(after, open(out/'source-after.json', 'w'), indent=2)
json.dump({'passed': before == after, 'beforeInputs': len(before), 'afterInputs': len(after),
           'added': sorted(after.keys() - before.keys()), 'removed': sorted(before.keys() - after.keys()),
           'changed': sorted(p for p in before.keys() & after.keys() if before[p] != after[p])},
          open(out/'product-input-set-check.json', 'w'), indent=2)
assert before == after, 'Product sources changed during build'
app = out/'BlinkClip.app'
info = plistlib.load(open(app/'Contents/Info.plist', 'rb'))
assert info['CFBundleIdentifier'] == 'com.chrisli.blinkclip'
assert info['CFBundleShortVersionString'] == json.load(open(root.parent/'package.json'))['version']
architectures = {}
for binary in ('Contents/MacOS/BlinkClip', 'Contents/MacOS/blinkclip-mcp', 'Contents/Library/LoginItems/BlinkClip Helper.app/Contents/MacOS/BlinkClipHelper'):
    architectures[binary] = subprocess.check_output(['lipo', '-archs', str(app/binary)], text=True).strip()
    assert architectures[binary] == 'arm64'
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
assert (app/'Contents/Resources/BlinkClipAppIcon.icns').read_bytes() == (root/'Assets/BlinkClipAppIcon.icns').read_bytes()
assert 'ui.panelToggleButton = statusItem.button' in (root/'Sources/BlinkClip/AppMain.swift').read_text()
json.dump({'passed': True, 'sourceInputs': len(before), 'version': info['CFBundleShortVersionString'], 'architectures': architectures, 'strictSignature': True, 'statusButtonWiring': True, 'installed': False, 'launchedProduct': False}, open(out/'bundle-check.json', 'w'), indent=2)
PY
source "$replica_root/Tests/Native/build-support.sh"
test_root="$ARTIFACT_TASK_DIR/out/qa"
test_build_root="$BLINKCLIP_BUILD_ROOT"
test_configuration=release
test_architecture="$(uname -m)"
export BLINKCLIP_TEST_CONFIGURATION=release
binary_root="$(swift build --package-path "$replica_root" --scratch-path "$test_build_root" -c release --show-bin-path)"
test_with_capture=1
compile_native_test_harness panel-permission-qa \
  "$replica_root/Sources/BlinkClip/UI/"*.swift \
  "$replica_root/Sources/BlinkClip/ICloudDriveSyncController.swift" \
  "$replica_root/Sources/BlinkClip/SourceAppColor.swift" \
  "$replica_root/Sources/BlinkClip/WindowSharingPolicy.swift" \
  "$replica_root/Sources/BlinkClip/BackgroundService.swift" \
  "$replica_root/Tests/Native/PanelPermissionInteractionHarness.swift" \
  > "$ARTIFACT_TASK_DIR/out/qa-compile.log" 2>&1
# The executable has safe defaults even if a UI client relaunches it without args.
qa_app="$test_root/panel-permission-qa.app"
qa_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$qa_app/Contents/Info.plist")"
mkdir -p "$qa_app/Contents/Frameworks"
ditto "$binary_root/Sparkle.framework" "$qa_app/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath '@executable_path/../Frameworks' "$test_harness"
codesign --force --sign - "$qa_app" > "$ARTIFACT_TASK_DIR/out/qa-sign.log" 2>&1
printf '%s\n' "$ARTIFACT_TASK_DIR" > "$ARTIFACT_TASK_DIR/out/task-path.txt"
printf '%s\n' "$qa_app" > "$ARTIFACT_TASK_DIR/out/qa-app-path.txt"
qa_pid=""
cleanup_qa() {
  if [[ -n "$qa_pid" ]] && kill -0 "$qa_pid" 2>/dev/null; then
    kill "$qa_pid" 2>/dev/null || true
    wait "$qa_pid" 2>/dev/null || true
  fi
  /usr/bin/defaults delete "$qa_id" >/dev/null 2>&1 || true
}
trap cleanup_qa EXIT
for qa_language in zh-Hans en; do
  "$test_harness" -AppleLanguages "($qa_language)" > "$test_root/run-$qa_language.log" 2>&1 &
  qa_pid=$!
  printf '%s\n' "$qa_pid" > "$test_root/pid.txt"
  printf '%s\n' "$qa_language" > "$test_root/language.txt"
  printf 'QA_READY %s %s\n' "$qa_language" "$qa_app"
  wait "$qa_pid"
  qa_pid=""
  cp "$test_root/qa-state.json" "$test_root/qa-state-$qa_language.json"
  if [[ -e "$test_root/finish" ]]; then break; fi
done
python3 - "$test_root" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
checks = list(root.glob('self-checks-*.json'))
assert checks and all(json.load(open(p))['passed'] for p in checks)
json.dump({'passed': True, 'languages': [p.stem.removeprefix('self-checks-') for p in checks], 'scope': 'Production controller lifecycle checks; CUA evidence separately recorded by coordinator.'}, open(root/'self-check-summary.json', 'w'), indent=2)
PY
du -sh "$ARTIFACT_TASK_DIR"
df -h /System/Volumes/Data
