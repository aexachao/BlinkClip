#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
export BLINKCLIP_TEST_CONFIGURATION=release
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$ARTIFACT_TASK_DIR/out"
source "$replica_root/Tests/Native/build-support.sh"
case "${1:-}" in
  '') run_store_regression=0; store_comparison=0 ;;
  --include-store-regression) run_store_regression=1; store_comparison=0 ;;
  --store-comparison) run_store_regression=0; store_comparison=1 ;;
  *) printf '%s\n' 'Usage: test-icloud-noop-performance.sh [--include-store-regression|--store-comparison]' >&2; exit 2 ;;
esac
test_build_root="$ARTIFACT_TASK_DIR/build/swiftpm"
test_configuration=release
test_architecture="$(uname -m)"
swift build --package-path "$replica_root" --scratch-path "$test_build_root" -c release --arch "$test_architecture" --target BlinkClipCore -j 2 > "$ARTIFACT_TASK_DIR/out/core-build.log" 2>&1
binary_root="$(swift build --package-path "$replica_root" --scratch-path "$test_build_root" -c release --arch "$test_architecture" --show-bin-path)"
test_root="$ARTIFACT_TASK_DIR/build/harnesses"
if [[ "$run_store_regression" == 1 ]]; then
  compile_native_test_harness icloud-sync "$replica_root/Tests/Native/ICloudDriveSyncHarness.swift" > "$ARTIFACT_TASK_DIR/out/regression-compile.log" 2>&1
  "$test_harness" > "$ARTIFACT_TASK_DIR/out/sync-regression.json"
fi
python3 - "$replica_root/Sources/BlinkClipCore/ICloudDriveSync.swift" "$ARTIFACT_TASK_DIR/build/MeasuredICloudTransports.swift" "$ARTIFACT_TASK_DIR/out/actor-extraction.json" <<'PY'
import hashlib, json, pathlib, subprocess, sys
source = pathlib.Path(sys.argv[1]).read_text()
actor = source[source.index('public actor ICloudDriveSyncTransport {'):]
encode = '''            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(snapshot)
            try Task.checkCancellation()
'''
assert actor.count(encode) == 1
baseline = actor.replace(encode, '', 1)
anchor = '''        try Task.checkCancellation()
        try coordinate(at: file, writing: true) { destination in'''
eager = '''        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
'''
assert baseline.count(anchor) == 1
baseline = baseline.replace(anchor, eager + anchor, 1)
repo = pathlib.Path(sys.argv[1]).resolve().parents[3]
head_source = subprocess.check_output(['git', 'show', 'HEAD:replica/Sources/BlinkClipCore/ICloudDriveSync.swift'], cwd=repo, text=True)
head_actor = head_source[head_source.index('public actor ICloudDriveSyncTransport {'):]
assert baseline == head_actor, 'Reconstructed eager actor differs from the original repository actor'
def instrument(text, name):
    text = text.replace('public actor ICloudDriveSyncTransport {', 'actor ' + name + ' {\n    private(set) var encodeCalls = 0', 1)
    assert text.count('let data = try encoder.encode(snapshot)') == 1
    return text.replace('let data = try encoder.encode(snapshot)', 'encodeCalls += 1\n' + ('            ' if name.startswith('Deferred') else '        ') + 'let data = try encoder.encode(snapshot)', 1)
pathlib.Path(sys.argv[2]).write_text('import Foundation\nimport BlinkClipCore\n' + instrument(actor, 'DeferredMeasuredICloudTransport') + '\n' + instrument(baseline, 'EagerMeasuredICloudTransport'))
pathlib.Path(sys.argv[2]).with_name('LegacyICloudTransport.swift').write_text('import Foundation\nimport BlinkClipCore\n' + baseline.replace('public actor ICloudDriveSyncTransport {', 'actor LegacyICloudDriveSyncTransport {', 1))
pathlib.Path(sys.argv[3]).write_text(json.dumps({'productionSourceSHA256': hashlib.sha256(source.encode()).hexdigest(), 'actorSHA256': hashlib.sha256(actor.encode()).hexdigest(), 'baselineActorSHA256': hashlib.sha256(baseline.encode()).hexdigest(), 'baselineActorMatchesHEAD': True, 'instrumentation': 'only actor rename and encodeCalls counter; baseline reverses encoding move; Legacy actor only renamed without counters', 'productionFile': sys.argv[1]}, indent=2))
PY
if [[ "$store_comparison" == 1 ]]; then
  compile_native_test_harness icloud-store-current "$replica_root/Tests/Native/ICloudDriveSyncHarness.swift" > "$ARTIFACT_TASK_DIR/out/current-store-compile.log" 2>&1
  current_exit=0
  "$test_harness" > "$ARTIFACT_TASK_DIR/out/current-store-regression.json" 2> "$ARTIFACT_TASK_DIR/out/current-store-stderr.log" || current_exit=$?
  python3 - "$replica_root/Tests/Native/ICloudDriveSyncHarness.swift" "$ARTIFACT_TASK_DIR/build/LegacyICloudDriveSyncHarness.swift" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
needle = 'let transport = ICloudDriveSyncTransport()'
assert source.count(needle) == 1
pathlib.Path(sys.argv[2]).write_text(source.replace(needle, 'let transport = LegacyICloudDriveSyncTransport()', 1))
PY
  compile_native_test_harness icloud-store-legacy \
    "$ARTIFACT_TASK_DIR/build/LegacyICloudTransport.swift" \
    "$ARTIFACT_TASK_DIR/build/LegacyICloudDriveSyncHarness.swift" > "$ARTIFACT_TASK_DIR/out/legacy-store-compile.log" 2>&1
  legacy_exit=0
  "$test_harness" > "$ARTIFACT_TASK_DIR/out/legacy-store-regression.json" 2> "$ARTIFACT_TASK_DIR/out/legacy-store-stderr.log" || legacy_exit=$?
  python3 - "$ARTIFACT_TASK_DIR/out" "$current_exit" "$legacy_exit" <<'PY'
import json, pathlib, sys
out = pathlib.Path(sys.argv[1])
current = json.loads((out/'current-store-regression.json').read_text())
legacy = json.loads((out/'legacy-store-regression.json').read_text())
result = {'comparisonCompleted': True, 'currentExit': int(sys.argv[2]), 'legacyExit': int(sys.argv[3]), 'currentRegression': current, 'legacyRegression': legacy, 'matchingOutcome': current == legacy, 'limits': ['Same unmodified Store and original harness; legacy harness changes only transport constructor to exact original actor', 'This comparison does not mark a failing regression suite as passing']}
(out/'store-comparison.json').write_text(json.dumps(result, indent=2))
print(json.dumps(result, indent=2))
PY
  du -sh "$ARTIFACT_TASK_DIR"
  df -h /System/Volumes/Data
  exit 0
fi
compile_native_test_harness icloud-noop-performance \
    "$ARTIFACT_TASK_DIR/build/MeasuredICloudTransports.swift" \
    "$replica_root/Tests/Native/ICloudDriveNoopPerformanceHarness.swift" > "$ARTIFACT_TASK_DIR/out/performance-compile.log" 2>&1
"$test_harness" > "$ARTIFACT_TASK_DIR/out/performance.log"
cat "$ARTIFACT_TASK_DIR/out/noop-performance.json"
du -sh "$ARTIFACT_TASK_DIR"
df -h /System/Volumes/Data
