#!/bin/bash
# 菜单栏网速的运行时回归：注入假计数器，验证 1 秒采样、关闭后停表、唤醒重置基线、
# utun 优先口径，以及两种排版（单行 / 上下两行）的状态栏文字、宽度、即时切换与
# tooltip。纯函数口径在 `blinkclip-core-tests` 的 network-speed-* 用例里。
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
export SWIFT_MODULECACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$ARTIFACT_TASK_DIR/out"
test_root="$ARTIFACT_TASK_DIR/build/harness"
mkdir -p "$test_root"
source "$replica_root/Tests/Native/build-support.sh"
shasum -a 256 \
  "$replica_root/Sources/BlinkClipCore/NetworkSpeed.swift" \
  "$replica_root/Sources/BlinkClip/UI/NetworkSpeedMonitor.swift" \
  "$replica_root/Sources/BlinkClip/UI/NetworkSpeedStatusItem.swift" \
  "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" \
  "$replica_root/Sources/BlinkClip/UI/ReplicaBrand.swift" \
  "$replica_root/Tests/Native/NetworkSpeedHarness.swift" \
  "$replica_root/scripts/test-network-speed.sh" > "$ARTIFACT_TASK_DIR/out/source-sha256.txt"
prepare_native_test_core > "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
compile_native_test_harness network-speed \
  "$replica_root/Sources/BlinkClip/UI/NetworkSpeedMonitor.swift" \
  "$replica_root/Sources/BlinkClip/UI/NetworkSpeedStatusItem.swift" \
  "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" \
  "$replica_root/Sources/BlinkClip/UI/ReplicaBrand.swift" \
  "$replica_root/Tests/Native/NetworkSpeedHarness.swift" \
  > "$ARTIFACT_TASK_DIR/out/compile.log" 2>&1
"$test_harness" "$@" | tee "$ARTIFACT_TASK_DIR/out/test.log"
# harness 已经用 precondition 逐条断言；这一段再独立核对报告口径：
# 两行必须比单行窄、两行宽度落在 40–64pt、关闭态必须回到 24pt。
python3 - "$ARTIFACT_TASK_DIR/out/test.log" <<'PY'
import json, pathlib, sys
reports = []
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    try:
        report = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(report, dict):
        reports.append(report)
assert reports and reports[-1].get('passed') is True, 'network-speed harness did not report passed'
report = reports[-1]
single = report['menuBarWidth']
two = report['twoLineWidth']
disabled = report['menuBarDisabledWidth']
assert two < single, f'two-line layout is not narrower: {two} vs {single}'
assert 40 <= two <= 64, f'two-line width {two} is outside the 40-64pt band'
assert abs(disabled - 24) < 0.01, f'disabled width {disabled} is not the 24pt square length'
assert report['twoLineImageHeight'] <= 22.01, f"two-line image height {report['twoLineImageHeight']} exceeds 22pt"
assert report['layouts'] == ['single', 'twoLines'], f"layout contract changed: {report['layouts']}"
print(f"Layouts: single {single}pt, twoLines {two}pt (image {report['twoLineImageWidth']}×"
      f"{report['twoLineImageHeight']}pt), disabled {disabled}pt, {report['checks']} checks")
PY
