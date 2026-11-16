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
    # 标签与选区顶边的间距 8pt：6pt 时胶囊会压到左上角手柄上。
    'size-label-gap-clears-handle': 'sizeLabelGap: CGFloat = 8' in code(selection)
                                    and 'rect.origin.y + rect.height + SelectionView.sizeLabelGap' in code(selection),

    # POL：十字辅线住在独立图层里（每屏两条），鼠标移动只改 layer frame，不再
    # 让整屏快照重绘；旧的 draw(_:) 版辅线与失效带必须彻底消失，否则延迟会回来。
    'overlay-guides-live-in-layers': 'CrosshairBandView' in code(selection)
                                     and 'crosshairHorizontal = CrosshairBandView(axis: .horizontal)' in code(selection)
                                     and 'crosshairVertical = CrosshairBandView(axis: .vertical)' in code(selection)
                                     and 'CATransaction.setDisableActions(true)' in code(selection)
                                     and 'drawCrosshair' not in code(selection)
                                     and 'invalidateCrosshairBands' not in code(selection),

    # POL：四态边框同一视觉重量 1pt（2x 下 2px）。任何 `borderWidth + 1` 形式的
    # 加粗都会把悬停/滚动红框顶回 3pt，与框选的 1pt 不一致。
    'overlay-border-width-unified': 'private let borderWidth: CGFloat = 1.0' in code(selection)
                                    and 'borderWidth + 1' not in code(selection)
                                    and code(selection).count('insetBy(dx: -borderWidth / 2, dy: -borderWidth / 2)') == 2,

    # POL：手柄是横条 + L 形角标，不是圆点；抓取区 ≥20×20（实测 22×22）。
    'overlay-handles-are-bars-and-corners': 'fillEllipse' not in code(selection)
        and all(fragment in code(selection) for fragment in (
            'handleBarLength: CGFloat = 20', 'handleBarThickness: CGFloat = 4',
            'handleBarCornerRadius: CGFloat = 2', 'handleCornerArmLength: CGFloat = 12',
            'handleCornerArmThickness: CGFloat = 2', 'handleHitSize: CGFloat = 22')),

    # POL：滚动截图的红色防渗色标记保留「整条描边落在选区外」的外扩逻辑。
    'scroll-marker-keeps-outer-offset': 'NSColor.systemRed.cgColor' in code(selection)
                                        and 'let outerInset = -(strokeWidth / 2 + 1)' in code(selection)
                                        and 'let strokeWidth = borderWidth' in code(selection),
}
(out / 'sel-label-source-gate.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print(f'SEL label source gate: {len(checks)} checks passed')
PY

# --- CUR 源码门：框选期自绘十字光标 ---------------------------------------------
python3 - "$replica_root" "$ARTIFACT_TASK_DIR/out" <<'PY'
import json, pathlib, sys
root, out = map(pathlib.Path, sys.argv[1:])
capture = root / 'Vendor/capcap/Capture'
selection = (capture / 'SelectionView.swift').read_text()
overlay = (capture / 'OverlayWindowController.swift').read_text()
design = (root.parent / 'DESIGN.md').read_text()


def code(text):
    """去掉行注释：注释里可以举例子，那不是实现。"""
    return '\n'.join(line.split('//', 1)[0] for line in text.splitlines())


def body(text, signature, next_signature):
    """取出一个函数体，用来断言「同一处更新」这类结构性质。"""
    start = text.index(signature)
    end = text.index(next_signature, start)
    return text[start:end]


update_layers = body(code(selection), 'private func updateCrosshairLayers()', 'private func reportPointerCursorDrawn')
begin_pointer = body(code(overlay), 'private func beginSelfDrawnPointer()', 'private func pointerCursorDrawnStateChanged')
tear_down = body(code(overlay), 'private func tearDown()', 'private func takeWindowCaptureTask')
lock_selection = body(code(overlay), 'private func lockSelectionForCompletion', 'private func resumePendingSelectionIfReady')

checks = {
    # CUR：光标是覆盖层内的一份图层/子视图（18pt 十字、1pt 白线、3pt 深色描边、
    # 中心 2pt 空隙），不是系统光标，也不是 draw(_:) 像素。
    'self-drawn-pointer-lives-in-the-overlay': all(fragment in code(selection) for fragment in (
        'private final class CrosshairCursorView: NSView',
        'crosshairCursor = CrosshairCursorView()',
        'addSubview(crosshairCursor)',
        'strandLength: CGFloat = 18',
        'centerGap: CGFloat = 2',
        'lineWidth: CGFloat = 1',
        'strokeWidth: CGFloat = 3',
        'func hitTest(_ point: NSPoint) -> NSView? { nil }',
        'var drawsPointerCursor = false',
        'onPointerCursorDrawnChanged: ((Bool) -> Void)?',
    )),

    # CUR：光标与两条辅线在同一个函数、同一次 CATransaction 里写 frame；这条
    # 路径不排整窗重绘，否则「同一帧」就无从保证。
    'self-drawn-pointer-shares-the-guide-transaction': all(fragment in update_layers for fragment in (
        'CATransaction.setDisableActions(true)',
        'crosshairHorizontal.place(',
        'crosshairVertical.place(',
        'crosshairCursor.place(',
        'let showsPointer = drawsPointerCursor',
        'crosshairCursor.place(centre: NSPoint(x: x, y: y), visible: showsPointer)',
    )) and 'needsDisplay' not in update_layers,

    # CUR：系统光标成对隐藏/恢复，幂等标志防多减一次；选区提交、会话结束、
    # 失去激活、deinit 都必须恢复。
    # CUR2：计数守恒（0/1 状态机，不能重复 hide）、非激活恢复延后到激活、
    # 关闭后看门狗兜底，任何退出路径都不能让光标长期不可见。
    'system-cursor-hide-is-paired-and-balanced': all(fragment in code(overlay) for fragment in (
        'final class SystemCursorHider',
        'NSCursor.hide()',
        'NSCursor.unhide()',
        'private(set) var hideDepth = 0',
        'var isHidden: Bool { hideDepth > 0 }',
        'guard hideDepth > 0 else { return }',
        'private(set) var isUnavailable = false',
        'func restore()',
        'deinit {',
        'systemCursor.hide()',
        'restoreSystemCursorNow()',
        'NSApplication.willResignActiveNotification',
        'NSApplication.didBecomeActiveNotification',
        'NSApplication.willTerminateNotification',
        'NSWindow.willCloseNotification',
        'func scheduleRestoreWatchdog()',
        'func runRestoreWatchdog()',
        'private func armActivationRestore()',
        'private func performUnhide() -> Bool',
        'if drivers.isAppActive()',
        'forcedUnhides += 1',
    ))
    and 'systemCursor.restore()' in code(overlay)
    and 'restoreSystemCursorNow()' in tear_down
    and 'restoreSystemCursorNow()' in lock_selection
    # 关闭/失去激活/终止三条退出路径都挂看门狗或同步兜底。
    and 'systemCursor.scheduleRestoreWatchdog()' in code(overlay)
    and 'systemCursor.forceRestoreForTermination()' in code(overlay)
    # 先隐藏、确认成功后才开始自绘（失败不出现第二个光标）。
    and begin_pointer.index('systemCursor.hide()') < begin_pointer.index('drawsPointerCursor = true'),

    # CUR：确认不了隐藏就退化，且写日志。
    'system-cursor-fallback-draws-guides-only': 'could not be hidden' in code(overlay)
        and 'drawsPointerCursor = false' in code(overlay)
        and 'suppressesSelfDrawnPointer = true' in code(overlay),

    # CUR：文档写清「自绘光标 + 同一帧 + 必须恢复 + 都不入图」。
    # CUR2：文档写清计数守恒 / 非激活延后 / 看门狗 / 任何路径不得长期不可见。
    'design-doc-self-drawn-pointer': all(fragment in design for fragment in (
        '十字光标本身也画在覆盖层内',
        '同一次 `CATransaction.setDisableActions(true)` 里写 frame',
        '结束必须恢复系统光标',
        '均不入图',
        '系统光标隐藏必须计数守恒',
        '恢复在 App 非激活时延后到下一条 `didBecomeActive`',
        '看门狗',
        '任何退出路径都不得让光标长期不可见',
    )),
}
(out / 'cur-cursor-source-gate.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print(f'CUR cursor source gate: {len(checks)} checks passed')
PY
