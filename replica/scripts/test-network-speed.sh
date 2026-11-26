#!/bin/bash
# 菜单栏网速的运行时回归：注入假计数器，验证 1 秒采样、关闭后停表、唤醒重置基线、
# utun 优先口径，以及唯一呈现（上下两行、上↑下↓、固定宽度、左对齐、无补位无字距）、
# macOS 风格自适应小数（B 档 0 位、KB/MB/GB < 100 一位、≥ 100 无位）与四档进位、
# 末档降级串 `>999G`、关闭回 24pt、tooltip / VoiceOver 的完整写法。
# 纯函数格式口径在 `blinkclip-core-tests` 的 network-speed-* 用例里。
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
# 菜单栏图标是包内矢量 PDF：测试 app 的 Resources 里放同一份文件，让
# `ReplicaBrand.menuBarImage()` 走生产的 `Bundle.main` 查找路径（找不到就会是空图标，
# harness 立刻断言失败，不会静默测一张空白图）。
cp "$replica_root/Assets/BlinkClipMenuBarMark.pdf" \
  "$test_root/network-speed.app/Contents/Resources/BlinkClipMenuBarMark.pdf"
"$test_harness" "$@" | tee "$ARTIFACT_TASK_DIR/out/test.log"

# 源码门：单一呈现意味着渲染器里不该再有单行路径、补位字符或字距补偿。
python3 - "$replica_root" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
source = (root / 'Sources/BlinkClip/UI/NetworkSpeedStatusItem.swift').read_text()
code = '\n'.join(line.split('//', 1)[0] for line in source.splitlines())
checks = {
    'only-two-line-renderer': code.count('attributedTitle') == 1
                              and 'attributedTitle = NSAttributedString(string: "")' in code
                              and 'imageLeading' not in code and 'imageOnly' in code,
    'no-figure-space-padding': '\\u{2007}' not in code and '2007' not in code,
    'no-kerning': '.kern' not in code and 'digitKerning' not in code,
    'no-single-line-layout': 'NetworkSpeedLayout' not in code and 'singleLine' not in code,
    'no-width-strategy': 'NetworkSpeedWidth' not in code and 'variableLength' not in code,
    'no-overflow-degradation': '>999' not in code.replace('>999G', ''),
    'left-aligned-two-rows': code.count('TwoLines.textX') >= 1
                              and 'textX: CGFloat' in code,
    'fixed-width-constant': 'static let textWidth: CGFloat = 38' in code,
    'icon-gap-is-6': 'static let iconGap: CGFloat = 6' in code
                     and 'textX: CGFloat { iconWidth + iconGap }' in code,
}
assert all(checks.values()), checks
print(f'Renderer source gate: {len(checks)} checks passed')
PY

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

# --- 固定宽度：唯一长度、唯一图宽 -------------------------------------------
length = report['enabledLength']
image = report['imageWidth']
text = report['textWidth']
assert abs(length - (image + 6)) < 0.01, f'状态项长度 {length} 不是图宽 {image} + 6pt 内边距'
assert abs(image - (18 + 6 + text)) < 0.01, f'图宽 {image} 不是 18pt 图标 + 6pt 间距 + {text}pt 文字区'
# 自适应小数之后最宽串从 6 个字符（`999.9M`）缩到 5 个（`99.9M`），状态项 74 → 68pt。
assert abs(text - 38) < 0.01, f'文字区常量 {text}pt 不是 38pt'
assert abs(image - 62) < 0.01, f'图宽 {image}pt 不是 62pt'
assert abs(length - 68) < 0.01, f'状态项长度 {length}pt 不是 68pt'
assert 64 <= length <= 70, f'固定长度 {length}pt 不在预计的 64–70pt 内'
# 图标（18pt）与文字区之间的间距：图宽减掉图标与文字区，必须正好 6pt。
gap = image - 18 - text
assert abs(gap - 6) < 0.01, f'图标与文字间距 {gap}pt 不是 6pt'
assert report['imageHeight'] <= 22.01, f"两行图高 {report['imageHeight']} 超过 22pt"

# ①② 两行顺序与内容：第一行 ↑（上传）、第二行 ↓（下载）。
assert report['lines'] == {'upload': '↑32.4K', 'download': '↓1.4M'}, report['lines']
bands = report['bands']
assert bands, 'harness 没有给出两行墨迹证据'
assert abs(bands['topMinColumn'] - bands['bottomMinColumn']) <= 2, \
    f"两行左边缘不齐：{bands['topMinColumn']} vs {bands['bottomMinColumn']}"
# 图标与文字的像素间距：图内 18pt 图标占 0–36px、文字排版原点在 18+6=24pt=48px（@2x），
# 即两段之间留 12px（6pt）空白。harness 只从 20pt=40px 起扫墨迹，这里断言最左墨迹
# 落在 48–52px（48px 是文字左边缘，多出的 ≤2px 是 ↑/↓ 字形自带的 bearing），
# 于是 36–47px 必为空白——图标右边缘到文字左边缘正好 12px。
ink_left = min(bands['topMinColumn'], bands['bottomMinColumn'])
assert 48 <= ink_left <= 52, \
    f"文字墨迹左边缘 {ink_left}px 不在 48–52px（图标右边缘 36px + 6pt 间距 12px）"
offsets = bands['leftOffsets']
assert len(offsets) == 3 and len(set(offsets)) == 1, \
    f"两行左边缘之差随读数变化（不是同一个排版原点）：{offsets}"
assert bands['topWidth'] > bands['bottomWidth'] + 8, \
    f"第一行（↑ 上传）不比第二行（↓ 下载）宽：{bands['topWidth']} vs {bands['bottomWidth']}"

# ③ 连续 10 帧不同数值：宽度恒定（新常量 68pt，逐帧不变）。
widths = report['frameButtonWidths']
assert len(widths) == 10, f'只采样了 {len(widths)} 帧'
assert len(set(widths)) == 1, f'10 帧宽度在变：{widths}'
assert abs(widths[0] - length) < 0.01, f'逐帧按钮宽 {widths[0]} 不是固定长度 {length}'
assert report['overflowLogs'] == 0, '正常读数触发了超宽日志'

# ④ 左对齐要求见 bands；⑤ 无补位无字距由 harness 的字符串/属性断言 + 源码门覆盖。

# ⑥ 关闭后 24pt。
assert report['disabledLength'] == -2, f"关闭态长度不是 squareLength：{report['disabledLength']}"
assert abs(report['disabledButtonWidth'] - 24) < 0.01, \
    f"关闭态宽度 {report['disabledButtonWidth']} 不是 24pt"

# --- 宽度预算：最宽正常串与降级串都落在固定文字区内 --------------------------
assert report['widestLine'] == '↑99.9M', report['widestLine']
assert report['widestLineWidth'] <= text, \
    f"最宽正常串 {report['widestLineWidth']}pt 超过 {text}pt 文字区"
# 自适应小数之后降级串 `>999G` 反而成了最宽的一种，文字区必须同时容下它。
assert report['degradeLineWidth'] > report['widestLineWidth'], \
    f"降级串 {report['degradeLineWidth']}pt 应宽于最宽正常串 {report['widestLineWidth']}pt"
assert report['degradeLineWidth'] <= text, '降级串超过固定文字区'

# --- 自适应小数（方案 C）：B 档 0 位、KB/MB/GB < 100 一位、≥ 100 无位 ----------
fulls = [s['full'] for s in report['formatSamples']]
compacts = [s['compact'] for s in report['formatSamples']]
# ① B 档（< 1024 B）没有小数位；② < 100 保留一位小数；③ ≥ 100 不显示小数。
assert fulls == ['0 B/s', '4 B/s', '512 B/s', '999 B/s', '1.0 KB/s', '1.0 KB/s',
                 '32.4 KB/s', '99.9 MB/s', '1.4 MB/s', '812 KB/s', '340 MB/s',
                 '1.0 GB/s', '999 GB/s'], fulls
assert compacts == ['0B', '4B', '512B', '999B', '1.0K', '1.0K', '32.4K', '99.9M',
                    '1.4M', '812K', '340M', '1.0G', '999G'], compacts
samples = {s['bytes']: (s['full'], s['compact']) for s in report['formatSamples']}
assert samples[0] == ('0 B/s', '0B'), samples[0]
assert samples[4.2] == ('4 B/s', '4B'), samples[4.2]
assert samples[512] == ('512 B/s', '512B'), samples[512]
assert samples[999] == ('999 B/s', '999B'), samples[999]
assert samples[33178] == ('32.4 KB/s', '32.4K'), samples[33178]
assert samples[831795] == ('812 KB/s', '812K'), samples[831795]
assert samples[1468006] == ('1.4 MB/s', '1.4M'), samples[1468006]
assert samples[1073741824] == ('1.0 GB/s', '1.0G'), samples[1073741824]

# ④ 进位边界：显示值到 999.x 就进下一档（0 位小数时即 ≥ 999.5），
#    99.96M 的「一位小数」会变成 100.0，于是直接按整数显示 `100M`。
boundary_fulls = [s['full'] for s in report['boundarySamples']]
boundary_compacts = [s['compact'] for s in report['boundarySamples']]
assert boundary_fulls == ['999 B/s', '1.0 KB/s', '999 KB/s', '1.0 MB/s',
                          '99.9 MB/s', '100 MB/s', '999 GB/s'], boundary_fulls
assert boundary_compacts == ['999B', '1.0K', '999K', '1.0M', '99.9M', '100M', '999G'], boundary_compacts

# ⑤ 末档（GB）无处可进 → 降级串。
assert report['degradeFull'] == '>999 GB/s', report['degradeFull']
assert report['degradeCompact'] == '↓>999G ↑>999G', report['degradeCompact']

# ⑥ tooltip / 设置页读数 / VoiceOver：完整写法（`下载 812 KB/s · 上传 32.4 KB/s`）。
tooltip = report['tooltip']
assert '812 KB/s' in tooltip and '32.4 KB/s' in tooltip, tooltip
assert tooltip.count(' · ') == 1, f'tooltip 不是「下载 · 上传」两段：{tooltip}'
# VoiceOver 用的是同一份完整写法（harness 里已与 toolTip(rates:) 逐字比较），
# 这里再按读数核对一次：两行图那次渲染的读数是 1.4 MB/s / 32.4 KB/s。
description = report['accessibilityDescription']
assert '1.4 MB/s' in description and '32.4 KB/s' in description, description
assert description.count(' · ') == 1, f'VoiceOver 描述不是「下载 · 上传」两段：{description}'

print(f"Presentation: two lines (↑ upload on top, ↓ download below), fixed {length}pt "
      f"(image {image}×{report['imageHeight']}pt = 18pt icon + {gap}pt gap + {text}pt text box), "
      f"text ink starts at {ink_left}px @2x (icon edge 36px, gap 12px), "
      f"10/10 frames width {widths[0]}pt, disabled {report['disabledButtonWidth']}pt, "
      f"{report['checks']} checks")
print(f"Format: adaptive decimals (B 0dp, <100 1dp, >=100 0dp) -> {report['lines']}; "
      f"tooltip {tooltip}")
print(f"Budget: widest normal {report['widestLine']} = {report['widestLineWidth']}pt, "
      f"degraded {report['degradeLine']} = {report['degradeLineWidth']}pt, "
      f"left edges {bands['topMinColumn']}px / {bands['bottomMinColumn']}px")
PY
