#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build="$ARTIFACT_TASK_DIR/build"
test_out="$ARTIFACT_TASK_DIR/out"
mkdir -p "$test_build/module-cache" "$test_out"
export CLANG_MODULE_CACHE_PATH="$test_build/module-cache"
export SWIFT_MODULECACHE_PATH="$test_build/module-cache"
target="$(uname -m)-apple-macosx14.0"
# SettingsStrings carries the one trilingual language resolver the permission
# page now uses, so it belongs in the scratch Core module.
sources=("$replica_root/Sources/BlinkClipCore/AccessibilityService.swift" "$replica_root/Sources/BlinkClipCore/PermissionPromptPolicy.swift" "$replica_root/Sources/BlinkClipCore/PermissionStatusSnapshot.swift" "$replica_root/Sources/BlinkClipCore/SettingsStrings.swift")
xcrun swiftc -swift-version 5 -target "$target" -module-cache-path "$test_build/module-cache" \
  -emit-library -emit-module -module-name BlinkClipCore "${sources[@]}" \
  -emit-module-path "$test_build/BlinkClipCore.swiftmodule" -o "$test_build/libBlinkClipCore.dylib" > "$test_out/compile.log" 2>&1
xcrun swiftc -parse-as-library -swift-version 5 -target "$target" -module-cache-path "$test_build/module-cache" \
  -I "$test_build" -L "$test_build" -lBlinkClipCore -Xlinker -rpath -Xlinker "$test_build" \
  "$replica_root/Sources/BlinkClip/UI/AccessibilityRequestAction.swift" \
  "$replica_root/Sources/BlinkClip/UI/PermissionStatusProbe.swift" \
  "$replica_root/Sources/BlinkClip/UI/PermissionStatusView.swift" \
  "$replica_root/Sources/BlinkClip/UI/SettingsSurfaceStyle.swift" \
  "$replica_root/Sources/BlinkClip/UI/SettingsWindowFocusRestore.swift" \
  "$replica_root/Tests/Native/PermissionStatusHarness.swift" \
  -o "$test_build/permission-status" >> "$test_out/compile.log" 2>&1
python3 - "$replica_root/Sources/BlinkClip/UI/PermissionStatusView.swift" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
# J1-a: the three captions are gone from the code, not just from the screen.
for text in [
    "返回应用后自动更新权限状态。", "Permission status updates automatically when you return.",
    "未授权也可使用剪贴板历史。", "Clipboard history works without these permissions.",
    "权限已开启，请退出并重新打开应用。", "Access is enabled. Quit and reopen this app to apply it.",
]:
    assert text not in source, f"removed caption is still in the view: {text}"
body = source.split("var body: some View {", 1)[1].split("private var showsRemediation", 1)[0]
# J1-e: one Accessibility row (event posting merged in) + one Screen Recording row.
assert body.count("row(title:") == 2, "only the Accessibility and Screen Recording rows remain"
assert "permission-post-events" not in source, "the separate event-posting row is gone"
assert "跨应用发送事件" not in source, "the removed event-posting capability title is gone"
assert "postEventsHint" in source, "the merged row keeps an inline hint for the AX/post mismatch"
# J1-b: the status line is only 已授权 / 未授权, never "已授权：<capability>".
# The status copy is a trilingual triple: 已授权 / 已授權 / Granted.
assert source.count('PermissionCopy.text("已授权", "已授權", "Granted")') >= 2, "status copy is the bare 已授权 / 已授權 / Granted"
assert source.count('PermissionCopy.text("未授权", "未授權", "Not granted")') >= 2, "status copy is the bare 未授权 / 未授權 / Not granted"
# No blanket "any zh is Simplified" branch may come back to this page.
assert 'hasPrefix("zh")' not in source, "the permission page must resolve three languages through SettingsStrings"
assert 'SettingsStrings.trilingual(zhHans, zhHant, en' in source, "PermissionCopy delegates to the one shared resolver"
assert "已授权：" not in source and "Granted:" not in source, "status lines carry no capability after a colon"
assert "未生效：" not in source and "Not active:" not in source, "denied status is the bare 未授权 / Not granted"
# P4: the refresh action left the card body. It now lives in the card title row, so the
# old "below a divider at the card bottom" contract is gone by design; the card itself
# keeps exactly two permission rows and the refresh control keeps its own copy + id.
assert "permission-refresh-status" in source, "the refresh control keeps its stable accessibility identifier"
assert "permission-refresh-status" not in body, "the refresh control must not sit inside the permission rows"
assert "struct PermissionRefreshControl" in source, "the card-title refresh control is missing"
for marker in ["正在刷新…", "已刷新 · %@", "refreshedLinger"]:
    assert marker in source, f"the refresh control lost its {marker!r} feedback state"
print("permission page gates: ok")
PY
shasum -a 256 "${sources[@]}" "$replica_root/Sources/BlinkClip/UI/PermissionStatusView.swift" \
  "$replica_root/Sources/BlinkClip/UI/AccessibilityRequestAction.swift" \
  "$replica_root/Sources/BlinkClip/UI/SettingsSurfaceStyle.swift" \
  "$replica_root/Sources/BlinkClip/UI/PermissionStatusProbe.swift" \
  "$replica_root/Sources/BlinkClip/UI/SettingsWindowFocusRestore.swift" "$replica_root/Sources/BlinkClip/AppMain.swift" > "$test_out/production-inputs.sha256"
for language in en zh-Hans zh-Hant; do
  "$test_build/permission-status" "$test_out" -AppleLanguages "($language)" > "$test_out/$language.log" 2>&1
  cat "$test_out/$language.log"
done
