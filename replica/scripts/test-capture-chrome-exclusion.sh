#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ARTIFACT_TASK_DIR/build/tmp" "$ARTIFACT_TASK_DIR/build/module-cache" "$ARTIFACT_TASK_DIR/out"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp/"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --package-path "$replica_root" --scratch-path "$ARTIFACT_TASK_DIR/build/swiftpm" --target BlinkClipCapture -c debug --jobs 2 > "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
binary_root="$(swift build --package-path "$replica_root" --scratch-path "$ARTIFACT_TASK_DIR/build/swiftpm" -c debug --show-bin-path)"
mapfile_compat=()
while IFS= read -r object; do mapfile_compat+=("$object"); done < <(find "$binary_root/BlinkClipCapture.build" -name '*.o' -type f | sort)
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$CLANG_MODULE_CACHE_PATH" -I "$binary_root/Modules" \
  "$replica_root/Tests/Native/CaptureChromeExclusionHarness.swift" "${mapfile_compat[@]}" -o "$binary_root/chrome-exclusion-harness" > "$ARTIFACT_TASK_DIR/out/harness-build.log" 2>&1
"$binary_root/chrome-exclusion-harness" > "$ARTIFACT_TASK_DIR/out/result.json"
cat "$ARTIFACT_TASK_DIR/out/result.json"

# --- SEL 源码门：尺寸标签的文案与位置 -------------------------------------------
python3 - "$replica_root" "$ARTIFACT_TASK_DIR/out" <<'PY'
import json, pathlib, sys
root, out = map(pathlib.Path, sys.argv[1:])
capture = root / 'Vendor/capcap/Capture'
selection = (capture / 'SelectionView.swift').read_text()
overlay = (capture / 'OverlayWindowController.swift').read_text()
editor = (root / 'Vendor/capcap/Editor/EditWindowController.swift').read_text()


def code(text):
    """去掉行注释：注释里可以举例子，那不是文案。"""
    return '\n'.join(line.split('//', 1)[0] for line in text.splitlines())


# 乘号，不是小写 x：`500 × 260`，与 App 内其他尺寸角标（图片预览、面板、卡片）
# 同一写法。覆盖层自己的三条文案（框选、滚动截图缩放、编辑器裁剪/旋转）都要跟着，
# 否则同一条标签会按入口不同显示两种写法。
default_multiply = r'"\(Int(rect.width)) × \(Int(rect.height))"'
default_lower_x = r'"\(Int(rect.width)) x \(Int(rect.height))"'
overlay_multiply = r'"\(width) × \(height)"'
overlay_scaled_multiply = r'"\(width) × \(height) (\(percent)%)"'
editor_crop_multiply = r'"\(max(1, Int(round(size.width)))) × \(max(1, Int(round(size.height))))"'
editor_size_multiply = r'"\(Int(size.width.rounded())) × \(Int(size.height.rounded()))"'

checks = {
    'size-label-uses-multiplication-sign': default_multiply in code(selection)
                                            and default_lower_x not in code(selection),
    'override-labels-use-multiplication-sign': all(fragment in code(overlay)
                                                   for fragment in (overlay_multiply, overlay_scaled_multiply))
                                                and all(fragment in code(editor)
                                                        for fragment in (editor_crop_multiply, editor_size_multiply)),
    # 标签与选区顶边的间距 8pt：6pt 时胶囊会压到左上角 8pt 手柄上。
    'size-label-gap-clears-handle': 'sizeLabelGap: CGFloat = 8' in code(selection)
                                    and 'rect.origin.y + rect.height + SelectionView.sizeLabelGap' in code(selection),
}
(out / 'sel-label-source-gate.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print(f'SEL label source gate: {len(checks)} checks passed')
PY
