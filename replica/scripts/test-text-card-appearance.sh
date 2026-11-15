#!/bin/bash
# 防回归：文本卡片外观四态矩阵（P1 白底白字缺陷）。
# {创建时浅,创建时深} × {当前浅,当前深}，断言正文前景/卡片底色对比度 ≥ 4.5:1，
# footer 带色等于当前外观下的卡片底色；缺陷回归时跨外观的两态必然失败。
# P5 追加：两处 footer 小字（文本卡「N 个字符」、链接卡 URL）按 WCAG AA 小字
# 要求浅深两外观都 ≥ 4.5:1（修复前浅色 4.00:1）。
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/blinkclip-text-card-appearance.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
export BLINKCLIP_TEST_CONFIGURATION=release
export BLINKCLIP_TEST_SCRATCH_PATH="${BLINKCLIP_TEST_SCRATCH_PATH:-$replica_root/.build/text-card-appearance-regression}"
source "$replica_root/Tests/Native/build-support.sh"
# UI/*.swift 会 import BlinkClipCapture；必须走 prepare_native_test_ui 才会构建该模块。
prepare_native_test_ui
compile_native_test_harness text-card-appearance \
  "$replica_root/Sources/BlinkClip/UI/"*.swift \
  "$replica_root/Sources/BlinkClip/PanelShortcutMenu.swift" \
  "$replica_root/Sources/BlinkClip/ICloudDriveSyncController.swift" \
  "$replica_root/Sources/BlinkClip/SourceAppColor.swift" \
  "$replica_root/Sources/BlinkClip/WindowSharingPolicy.swift" \
  "$replica_root/Sources/BlinkClip/BackgroundService.swift" \
  "$replica_root/Tests/Native/TextCardAppearanceHarness.swift"
"$test_harness" | tee "$test_root/result.json"
python3 - "$test_root/result.json" <<'PY'
import json, pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()
start = text.find('{')
report = json.loads(text[start:]) if start >= 0 else {}
if report.get('passed') is not True:
    raise SystemExit('text-card-appearance harness did not reach its passing report')
states = report.get('matrix', [])
if len(states) != 4:
    raise SystemExit(f'expected a 4-state matrix, got {len(states)}')
minimum = report.get('footerContrastMinimum', 4.5)
for state in states:
    if state['footerTextContrast'] < minimum:
        raise SystemExit('text-card footer contrast %.2f:1 below %.1f:1 (%s -> %s)'
                         % (state['footerTextContrast'], minimum, state['created'], state['current']))
for footer in report.get('linkCardFooter', []):
    if footer['textContrast'] < minimum:
        raise SystemExit('link-card footer contrast %.2f:1 below %.1f:1 (%s)'
                         % (footer['textContrast'], minimum, footer['side']))
for footer in report.get('sourceToneFooter', []):
    if footer['footerTextContrast'] < minimum:
        raise SystemExit('source-tone text-card footer contrast %.2f:1 below %.1f:1 (%s)'
                         % (footer['footerTextContrast'], minimum, footer['current']))
link_sides = sorted(footer['side'] for footer in report.get('linkCardFooter', []))
if link_sides != ['dark', 'light']:
    raise SystemExit(f'expected link-card footer samples for light and dark, got {link_sides}')
PY
