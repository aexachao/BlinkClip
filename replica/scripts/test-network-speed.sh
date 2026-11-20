#!/bin/bash
# 菜单栏网速的运行时回归：注入假计数器，验证 1 秒采样、关闭后停表、唤醒重置基线、
# utun 优先口径，两种排版（单行 / 上下两行）× 两种宽度策略（固定 / 随内容）的状态栏
# 文字、宽度、即时切换、超预算降级与 tooltip。纯函数口径在 `blinkclip-core-tests`
# 的 network-speed-* 用例里。
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
# 两行（随内容）必须比单行窄、两行宽度落在 40–64pt、关闭态必须回到 24pt；
# 固定宽度必须常量（单行 124/两行 72）、补位后 13 个字符位、降级文本正确。
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

# --- 排版口径（随内容）：两行比单行窄，关闭回 24pt -------------------------
single = report['menuBarWidth']
two = report['twoLineWidth']
disabled = report['menuBarDisabledWidth']
assert two < single, f'two-line layout is not narrower: {two} vs {single}'
assert 40 <= two <= 64, f'two-line width {two} is outside the 40-64pt band'
assert abs(disabled - 24) < 0.01, f'disabled width {disabled} is not the 24pt square length'
assert report['twoLineImageHeight'] <= 22.01, f"two-line image height {report['twoLineImageHeight']} exceeds 22pt"
assert report['layouts'] == ['single', 'twoLines'], f"layout contract changed: {report['layouts']}"

# --- 宽度策略：固定（默认）/ 随内容 -----------------------------------------
assert report['widths'] == ['fixed', 'content'], f"width contract changed: {report['widths']}"
fixed_single = report['fixedSingleLength']
fixed_two = report['fixedTwoLinesLength']
fixed_image = report['fixedTwoLinesImageWidth']
assert abs(fixed_single - 124) < 0.01, f'fixed single-line length is {fixed_single}, expected 124'
assert abs(fixed_two - 72) < 0.01, f'fixed two-line length is {fixed_two}, expected 72'
assert abs(fixed_image - (fixed_two - 6)) < 0.01, \
    f'two-line image {fixed_image} is not the fixed length minus the 6pt button padding'

# ① 固定宽度下多帧长度恒定（0 变化），补位后字符位数恒定。
assert report['fixedWidthStable'] is True, 'fixed width mode changed width across frames'
assert report['fixedTitleSlots'] == 13, f"fixed title has {report['fixedTitleSlots']} slots, expected 13"
sample = report['fixedTitleSample']
assert len(sample) == 13, f'fixed title sample has {len(sample)} chars: {sample!r}'
assert '\u2007' in sample, f'fixed title sample is not figure-space padded: {sample!r}'
assert 'B/s' not in sample and 'bps' not in sample, f'fixed title keeps a 3-char suffix: {sample!r}'
assert sample.startswith('↓') and '↑' in sample, f'fixed title lost its arrows: {sample!r}'
# 最宽标题 + 真实菜单栏的 38pt 固定开销（左右各 9 + 图标 18 + 间距 2）必须落在状态项内。
widest = report['fixedWidestTitleWidth']
assert widest + 38 <= fixed_single, f'widest fixed title {widest}pt does not fit {fixed_single}pt'
assert widest >= 80, f'the widest measured title {widest}pt is suspiciously narrow'
assert report['fixedIdleTitle'] == '↓\u2007\u2007\u20070B ↑\u2007\u2007\u20070B', \
    f"idle fixed title is {report['fixedIdleTitle']!r}"

# ② 随内容模式下宽度确实变化（与 ① 对照）。
assert report['contentWidthCount'] > 1, 'content width mode did not vary across frames'

# ③ 超预算降级：数字位超过 4 位时换成 >999 + 后缀，段仍然 6 位。
assert report['degradeText'] == '↓>999T', f"degrade text is {report['degradeText']!r}"

# ④ 四种组合：单行/两行 × 固定/随内容 各自落定。
combos = report['combinationLengths']
expected = {
    'single-fixed': fixed_single,
    'single-content': -1.0,
    'twoLines-fixed': fixed_two,
    'twoLines-content': -1.0,
}
assert combos == expected, f'four combinations are {combos}, expected {expected}'
if report['fixedRealStatusItem'] != 1:
    print('NOTE 本次运行没有 NSStatusBar，固定宽度的真状态项断言只在离屏按钮上跑过')

print(f"Layouts: single {single}pt, twoLines {two}pt (image {report['twoLineImageWidth']}×"
      f"{report['twoLineImageHeight']}pt), disabled {disabled}pt")
print(f"Width: fixed single {fixed_single}pt / fixed twoLines {fixed_two}pt "
      f"(image {fixed_image}pt), widest fixed title {widest}pt, {report['checks']} checks")
PY
