#!/bin/bash
# EC：编辑器 live 选框与框选覆盖层必须是同一套 chrome。
#   - 位图比对：两侧强调色实心像素集合完全相同（编辑器没有第二套绘制）
#   - 几何：1pt 实线（虚线段 0）、横条 20×4pt、L 角标 12×2pt、无圆点
#   - 命中区 22×22pt：角内 9pt 命中、12pt 不命中，拖动真的改选区
set -euo pipefail
if [[ -z "${ARTIFACT_TASK_DIR:-}" ]] && [[ -x "$HOME/dev-artifacts/bin/storage-guard" ]]; then
  exec "$HOME/dev-artifacts/bin/storage-guard" run --repo blinkclip --task editor-chrome-parity -- bash "$0" "$@"
fi
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/blinkclip-editor-chrome-parity.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
# @testable 需要带 testing 的模块：SwiftPM 只在 debug 配置下加 -enable-testing。
export BLINKCLIP_TEST_CONFIGURATION=debug
export BLINKCLIP_TEST_SCRATCH_PATH="${BLINKCLIP_TEST_SCRATCH_PATH:-$replica_root/.build/editor-chrome-parity}"
source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_ui
compile_native_test_harness editor-chrome-parity "$replica_root/Tests/Native/EditorChromeParityHarness.swift"
run_native_test_harness "$@" | tee "$test_root/result.log"
python3 - "$test_root/result.log" <<'PY'
import json
import pathlib
import sys
reports = []
for line in pathlib.Path(sys.argv[1]).read_text().splitlines():
    try:
        report = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(report, dict):
        reports.append(report)
if not reports or reports[-1].get('passed') is not True:
    raise SystemExit('editor chrome parity harness did not reach its final passing report')
print('EC editor chrome parity: %d checks passed' % reports[-1].get('checks', 0))
PY

# --- 源码门：编辑器不得再自带一套 chrome -----------------------------------------
python3 - "$replica_root" "${ARTIFACT_TASK_DIR:-$test_root}" <<'PY'
import json
import pathlib
import sys
root, out = map(pathlib.Path, sys.argv[1:])
editor = (root / 'Vendor/capcap/Editor/EditWindowController.swift').read_text()


def code(text):
    """去掉行注释：注释里可以解释旧样式，那不是实现。"""
    return '\n'.join(line.split('//', 1)[0] for line in text.splitlines())


start = code(editor).index('final class SelectionChromeOverlay')
overlay = code(editor)[start:]
checks = {
    # 圆点与虚线不再出现：编辑器选框的唯一来源是覆盖层的共享绘制。
    'editor-chrome-has-no-dots': 'fillEllipse' not in overlay and 'handleSize: CGFloat = 8' not in overlay,
    'editor-chrome-has-no-dashes': 'dashPattern' not in overlay and 'setLineDash' not in overlay,
    'editor-chrome-has-no-2pt-frame': 'borderWidth: CGFloat = 2.0' not in overlay,
    # 命中区与覆盖层同一个常量（22×22pt），不再是编辑器自己的 12。
    'editor-hit-target-uses-shared-constant': 'SelectionView.handleHitSize' in overlay
                                              and 'handleHitSize: CGFloat = 12' not in overlay
                                              and overlay.count('hitSize: handleHitSize') == 3,
    # 绘制必须走覆盖层的共享函数。
    'editor-draws-with-overlay-painter': 'drawSelectionChrome(' in overlay,
}
(out / 'editor-chrome-source-gate.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print('EC editor chrome source gate: %d checks passed' % len(checks))
PY
