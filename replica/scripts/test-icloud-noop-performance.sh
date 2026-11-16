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
import difflib, hashlib, json, pathlib, re, sys
source = pathlib.Path(sys.argv[1]).read_text()
actor = source[source.index('public actor ICloudDriveSyncTransport {'):]
# 基线 = 把 write() 里的延迟编码搬回 coordinate 之前（优化前的写法）。定位只用语义锚点
# 的正则，不写行号；原实现额外断言「重建结果 == git HEAD 里的 actor」，这在优化被提交
# 之后永远不成立（本仓库唯一提交 6c274da 已经含优化后的写法），属于过期基线，已删除。
# 现在改成自动计算的精确差异断言：actor 与基线的文本差异必须恰好是「删掉延迟编码块」
# + 「在 coordinate 入口前插入等价的提前编码」。
deferred = re.compile(
    r'(?ms)^( *)let encoder = JSONEncoder\(\)\n'
    r' *encoder\.outputFormatting = \[\.sortedKeys\]\n'
    r' *let data = try encoder\.encode\(snapshot\)\n'
    r' *try Task\.checkCancellation\(\)\n')
anchor_pattern = re.compile(
    r'(?m)^( *)try Task\.checkCancellation\(\)\n(?P<coordinate> *try coordinate\(at: file, writing: true\) \{ destination in\n)')
deferred_matches = list(deferred.finditer(actor))
assert len(deferred_matches) == 1, 'deferred encoding block must appear exactly once in the actor'
deferred_text = deferred_matches[0].group(0)
baseline = actor[:deferred_matches[0].start()] + actor[deferred_matches[0].end():]
anchor_matches = list(anchor_pattern.finditer(baseline))
assert len(anchor_matches) == 1, 'write() coordinate anchor must appear exactly once in the actor'
eager = ('        let encoder = JSONEncoder()\n'
         '        encoder.outputFormatting = [.sortedKeys]\n'
         '        let data = try encoder.encode(snapshot)\n')
baseline = baseline[:anchor_matches[0].start()] + eager + baseline[anchor_matches[0].start():]

def assert_only_edit(optimized, restored, removed, added, label):
    optimized_lines = optimized.splitlines(keepends=True)
    restored_lines = restored.splitlines(keepends=True)
    matcher = difflib.SequenceMatcher(None, optimized_lines, restored_lines, autojunk=False)
    ops = [op for op in matcher.get_opcodes() if op[0] != 'equal']
    assert ops, label + ': baseline surgery changed nothing'
    removed_text = ''.join(''.join(optimized_lines[i1:i2]) for _, i1, i2, _, _ in ops)
    added_text = ''.join(''.join(restored_lines[j1:j2]) for _, _, _, j1, j2 in ops)
    assert removed_text == removed, label + ': unexpected optimized-source difference %r' % removed_text
    assert added_text == added, label + ': unexpected baseline difference %r' % added_text
    assert restored.count(added) == 1, label + ': restored statement is not unique in the baseline'

assert_only_edit(actor, baseline, deferred_text, eager, 'eager encoding inverse surgery')
def instrument(text, name):
    text = text.replace('public actor ICloudDriveSyncTransport {', 'actor ' + name + ' {\n    private(set) var encodeCalls = 0', 1)
    assert text.count('let data = try encoder.encode(snapshot)') == 1
    return text.replace('let data = try encoder.encode(snapshot)', 'encodeCalls += 1\n' + ('            ' if name.startswith('Deferred') else '        ') + 'let data = try encoder.encode(snapshot)', 1)
pathlib.Path(sys.argv[2]).write_text('import Foundation\nimport BlinkClipCore\n' + instrument(actor, 'DeferredMeasuredICloudTransport') + '\n' + instrument(baseline, 'EagerMeasuredICloudTransport'))
pathlib.Path(sys.argv[2]).with_name('LegacyICloudTransport.swift').write_text('import Foundation\nimport BlinkClipCore\n' + baseline.replace('public actor ICloudDriveSyncTransport {', 'actor LegacyICloudDriveSyncTransport {', 1))
pathlib.Path(sys.argv[3]).write_text(json.dumps({'productionSourceSHA256': hashlib.sha256(source.encode()).hexdigest(), 'actorSHA256': hashlib.sha256(actor.encode()).hexdigest(), 'baselineActorSHA256': hashlib.sha256(baseline.encode()).hexdigest(), 'baselineDerivation': 'semantic anchors + exact text-difference assertion; no pinned hash and no git HEAD comparison', 'instrumentation': 'only actor rename and encodeCalls counter; baseline reverses encoding move; Legacy actor only renamed without counters', 'productionFile': sys.argv[1]}, indent=2))
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
