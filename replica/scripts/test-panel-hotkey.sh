#!/bin/bash
# 面板（底部快捷菜单）可见期间的全局热键回归。
# 只在本进程内投递合成的 Carbon 热键事件；不发送系统按键、不抓屏、不读写剪贴板。
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/blinkclip-panel-hotkey.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_core
compile_native_test_harness panel-hotkey \
  "$replica_root/Sources/BlinkClip/GlobalHotKey.swift" \
  "$replica_root/Sources/BlinkClip/GlobalHotKeyRouting.swift" \
  "$replica_root/Sources/BlinkClip/Screenshot/ScreenshotWindowHider.swift" \
  "$replica_root/Tests/Native/PanelHotKeyHarness.swift"
"$test_harness" > "$test_root/result.json"
cat "$test_root/result.json"
python3 - "$test_root/result.json" <<'PY'
import json
import pathlib
import sys
report = json.loads(pathlib.Path(sys.argv[1]).read_text())
if report.get("passed") is not True:
    raise SystemExit("panel hot key harness did not pass")
print(f"panel-hotkey: {report['count']} checks passed")
PY
