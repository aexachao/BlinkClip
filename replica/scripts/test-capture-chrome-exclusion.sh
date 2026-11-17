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
design = (root.parent / 'DESIGN.md').read_text()


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
                                    and 'y: rect.maxY + sizeLabelGap' in code(selection),

    # CL：尺寸标签必须完整落在屏幕 visibleFrame 内。默认左上外侧；上方空间不足
    # 翻到选区下方；左右越界平移（各留 4pt）；下方也放不下时允许压在选区内部，
    # 但仍在 visibleFrame 内。覆盖层与编辑器都通过带 view 的同一函数取屏幕。
    'size-label-clamped-to-visible-frame': all(fragment in code(selection) for fragment in (
        'window?.screen ?? NSScreen.main',
        'window.convertFromScreen(screen.visibleFrame)',
        'sizeLabelEdgeInset: CGFloat = 4',
        'rect.maxY + sizeLabelGap <= visible.maxY - size.height',
        'rect.minY - sizeLabelGap - size.height >= visible.minY',
        'visible.maxY - size.height',
        'sizeLabelRect(for: rect, in: view, text: text)',
    )) and all(fragment in code(selection) for fragment in (
        'SelectionView.drawSizeLabel(context: context, rect: hoverRect, in: self)',
        'Self.drawSizeLabel(context: context, rect: rect, text: sizeLabel, in: self)',
    )) and 'drawSizeLabel(context: context, rect: rect, text: sizeLabel)' not in code(selection),

    # 文档口径：规范必须写明「visibleFrame 内 / 左上外侧 / 顶部不足翻到下方 /
    # 左右越界平移」，否则下次改绘制时没人知道这条规则存在。
    'design-doc-size-label-visible-frame': all(fragment in design for fragment in (
        'visibleFrame', '左上外侧', '翻到下方', '左右越界平移')),

    # REV：贯穿辅线是两个独立图层（水平 + 垂直），随指针改 layer frame/path，
    # 不让整屏快照重绘；旧的自绘/失效带实现必须彻底消失，否则延迟会回来。
    'overlay-guides-live-in-layers': 'private final class CrosshairBandView: NSView' in code(selection)
                                     and 'private let crosshairHorizontal = CrosshairBandView(axis: .horizontal)' in code(selection)
                                     and 'private let crosshairVertical = CrosshairBandView(axis: .vertical)' in code(selection)
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

# --- REV 源码门：系统十字光标 + 贯穿全屏的跟随辅线 ---------------------------
python3 - "$replica_root" "$ARTIFACT_TASK_DIR/out" <<'PY'
import json, pathlib, sys
root, out = map(pathlib.Path, sys.argv[1:])
capture = root / 'Vendor/capcap/Capture'
selection = (capture / 'SelectionView.swift').read_text()
overlay = (capture / 'OverlayWindowController.swift').read_text()
detector = (capture / 'WindowDetector.swift').read_text()
screenshot_settings = (root / 'Vendor/capcap/Adapters/ScreenshotSettings.swift').read_text()
copy_table = (root / 'Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift').read_text()
aux = (root / 'Sources/BlinkClip/UI/AuxiliaryViews.swift').read_text()
design = (root.parent / 'DESIGN.md').read_text()
harness = (root / 'Tests/Native/CaptureChromeExclusionHarness.swift').read_text()


def code(text):
    """去掉行注释：注释里可以举例子，那不是实现。"""
    return '\n'.join(line.split('//', 1)[0] for line in text.splitlines())


def body(text, signature, next_signature):
    """取出一个函数体，用来断言「同一处更新」这类结构性质。"""
    start = text.index(signature)
    end = text.index(next_signature, start)
    return text[start:end]


selection_code = code(selection)
overlay_code = code(overlay)
detector_code = code(detector)
band = body(selection_code, 'private final class CrosshairBandView: NSView', 'class SelectionView: NSView')
guide = body(selection_code, 'private func updateCrosshairLayers()', 'private func broadcastCrosshair')
cursor_rects = body(selection_code, 'override func resetCursorRects()', 'func refreshCursorRects')
clear_hover = body(selection_code, 'private func clearHover()', 'override func draw(_ dirtyRect: NSRect) {')
# `SelectionView.draw(_:)` 只画快照——选区外观在子图层里。
# 起始锚点用 MEAS 埋点那一行（`let perfDraw = ...`）：三种区域（hover / 选区
# chrome / 快照）各有一处 `override func draw`，只有快照这处带 `perfDraw`。
selection_draw = body(selection_code,
                      '    override func draw(_ dirtyRect: NSRect) {\n        let perfDraw',
                      '    func drawSelectionChrome(')
chrome_view = body(selection_code, 'private final class SelectionChromeView: NSView', 'class SelectionView: NSView')
drag_new = body(selection_code, '        case .drawNew:', '        case .move:')
mouse_up = body(selection_code, 'override func mouseUp(with event: NSEvent)', 'override func mouseMoved(with event: NSEvent)')

# 全仓库的 Swift 源（生产代码 + 测试工具），不是只有覆盖层。
swift_sources = {p: p.read_text() for p in root.rglob('*.swift')}

checks = {
    # CUR4：自绘光标（视图、状态回调和它引出的控制端逻辑）彻底删除。
    'self-drawn-pointer-is-gone': all(fragment not in selection_code for fragment in (
        'CrosshairCursorView',
        'crosshairCursor',
        'drawsPointerCursor',
        'onPointerCursorDrawnChanged',
        'isDrawingPointerCursor',
    )),

    # CUR4：全仓库不再隐藏/恢复系统光标——这是「关掉覆盖层后光标一定可见」
    # 的结构性保证（没有 hide 就没有需要恢复的 unhide，也就不存在被吞的恢复）。
    'system-cursor-is-never-hidden': all(
        token not in text
        for token in (
            'NSCursor.' + 'hide(',
            'NSCursor.' + 'unhide(',
            'CGDisplay' + 'HideCursor',
            'CGDisplay' + 'ShowCursor',
            'System' + 'CursorHider',
            'CG' + 'CursorIsVisible',
        )
        for text in swift_sources.values()
    ),

    # CUR4：指针交还系统 crosshair：覆盖层视图注册 crosshair cursor rect，
    # 并且在覆盖层激活时主动 set 一次。任一时刻只有一个指针——系统光标。
    'pointer-is-the-system-crosshair': 'addCursorRect(bounds, cursor: .crosshair)' in cursor_rects
        and 'resetCursorRects()' in selection_code
        and 'NSCursor.crosshair.set()' in selection_code
        and 'NSCursor.crosshair.set()' in overlay_code,

    # REV：两条贯穿辅线各自一个图层（水平 + 垂直），不是窗口四边描线。
    'crosshair-guides-are-two-layers': all(fragment in selection_code for fragment in (
        'private final class CrosshairBandView: NSView',
        'private let crosshairHorizontal = CrosshairBandView(axis: .horizontal)',
        'private let crosshairVertical = CrosshairBandView(axis: .vertical)',
        'private func installOverlayLayers()',
        'private let lineLayer = CAShapeLayer()',
    )) and 'needsDisplay' not in guide,

    # REV：线型只有一个来源：1.5pt、systemGray 50%、实线（lineDashPattern = nil）。
    'guide-style-is-solid-1-5pt': all(fragment in band for fragment in (
        'static let lineWidth: CGFloat = 1.5',
        'static let alpha: CGFloat = 0.5',
        'NSColor.systemGray',
        'lineLayer.lineDashPattern = nil',
        'lineLayer.lineWidth = Self.lineWidth',
    )),

    # REV：线跟着光标坐标，不是 hover 窗口的四边；水平线跨满屏宽、竖线跨满屏高。
    'guide-follows-the-pointer': all(fragment in guide for fragment in (
        'let point = crosshairLocalPoint',
        'NSRect(x: bounds.minX, y: y - thickness / 2, width: bounds.width, height: thickness)',
        'NSRect(x: x - thickness / 2, y: bounds.minY, width: thickness, height: bounds.height)',
        'crosshairHorizontal.place(',
        'crosshairVertical.place(',
    )) and 'hoverWindowRect' not in guide
        and 'detector.windowAt(cgPoint: cgPoint)' not in guide,

    # REV：可见性只在 .idle / .drawing，且 .selected / 滚动截图 / 编辑器接管都隐藏。
    'guide-visibility-contract': 'let showsGuides = state == .idle || state == .drawing' in guide
        and '!scrollCaptureActive' in guide
        and '!selectionLocked' in guide
        and 'selectionInteractionEnabled' in guide,

    # REV：同一个关闭隐式动画的事务内更新，并对图层同步 display/displayIfNeeded。
    'guide-updates-synchronously': all(fragment in guide for fragment in (
        'CATransaction.begin()',
        'CATransaction.setDisableActions(true)',
        'CATransaction.commit()',
    )) and all(fragment in band for fragment in (
        'lineLayer.setNeedsDisplay()',
        'lineLayer.displayIfNeeded()',
    )),

    # REV：跨屏广播——控制器把同一个屏幕坐标镜像给各屏遮罩，开场先播种一次；
    # 每屏只写自己需要的那一轴（竖线落在 bounds 外自然隐藏）。
    'guides-broadcast-across-displays': all(fragment in overlay_code for fragment in (
        'selectionView.onCrosshairMoved = { [weak self] screenPoint in',
        'view.updateCrosshair(globalPoint: screenPoint)',
        'view.updateCrosshair(globalPoint: pointerAtPresentation)',
    )) and 'var onCrosshairMoved: ((NSPoint) -> Void)?' in selection_code
        and 'private func broadcastCrosshair(at point: NSPoint)' in selection_code
        and 'broadcastCrosshair(at: point)' in body(selection_code, 'override func mouseMoved(with event: NSEvent)', 'override func mouseEntered(with event: NSEvent)')
        and 'broadcastCrosshair(at: point)' in body(selection_code, 'override func mouseDragged(with event: NSEvent)', 'private func clampedForMove'),

    # REV：窗口吸附与拖拽吸边彻底删除——没有窗口描线视图、没有吸附候选、没有
    # 高亮图层、没有开关；拖拽分支只写选区 chrome 图层。
    'window-snap-is-gone': all(token not in selection_code for token in (
        'SnapGuideView',
        'SnapHighlightView',
        'showsGuideCenterLines',
        'showsDragSnap',
        'dragSnapDistance',
        'dragSnapCandidates',
        'dragSnappedEdges',
        'refreshSnapGuide',
        'refreshDragSnapHighlight',
        'snappedDragRect',
    )) and all(token not in overlay_code for token in (
        'showsGuideCenterLines',
        'snapGuidesCenterLinesEnabled',
    )) and 'let snapped = snappedDragRect' not in drag_new
        and 'needsDisplay' not in drag_new,

    # REV：拖拽只改几何 + 写 chrome 图层，松手不残留任何吸附高亮。
    'drag-writes-layers-not-snapshot': all(fragment in drag_new for fragment in (
        'selectionRect = SelectionView.dragRect(',
        'refreshSelectionChrome()',
    )) and 'drawSelectionChrome(' not in drag_new
        and 'refreshDragSnapHighlight' not in mouse_up,

    # REV：设置页不再有「显示中线」：桥接键、三语文案、设置行与开关全部消失。
    'center-lines-setting-is-gone': 'snapGuidesCenterLines' not in code(screenshot_settings)
        and 'centerLinesTitle' not in code(copy_table)
        and 'guidesSectionTitle' not in code(copy_table)
        and 'settings.snap-guides.center-lines.toggle' not in aux
        and 'snapGuidesCenterLines' not in aux,

    # SG/OPT：窗口列表开场枚举一次 + 2Hz 增量刷新（指针静止暂停、hover
    # 未命中补采，见 `test-overlay-opt.sh`）；计时器在 tearDown 里停掉。
    'window-list-refresh-is-capped-at-2hz': all(fragment in overlay_code for fragment in (
        'windowEnumerationInterval: TimeInterval = 1.0 / 2.0',
        'DispatchSource.makeTimerSource(queue: .main)',
        'repeating: Self.windowEnumerationInterval',
        'private func refreshWindowList(generation: Int)',
        'windowEnumerationInFlight',
    )) and overlay_code.count('stopWindowEnumerationRefresh()') >= 2,

    # SG：枚举时排除本产品自身浮层（本进程 HUD + 同 bundle 孪生实例的 floating+），
    # 否则 hover 高亮会圈住自己的光标芯片。
    'hover-excludes-product-chrome': all(fragment in detector_code for fragment in (
        'let isProductChrome: Bool',
        'static func isProductChrome(',
        'layer >= Int(CGWindowLevelForKey(.screenSaverWindow))',
        'layer >= Int(NSWindow.Level.floating.rawValue)',
        '!$0.isProductChrome',
    )) and 'private func currentSessionChromeWindowNumbers()' in overlay_code
        and 'windows.filter { !sessionChrome.contains($0.windowID) }' in overlay_code,

    # harness：不是只靠文本门——辅线位置、逐帧跟随、跨屏广播、.selected 隐藏、
    # 移动期 0 次 draw(_:) 都有实测断言；五轮开关期间拦截 cursor-hide 入口。
    'harness-proves-crosshair-behaviour': 'hideCalls == 0 && unhideCalls == 0' in harness
        and 'NSSelectorFromString("hide")' in harness
        and 'one chrome layer, one hover-highlight layer and exactly two guide bands' in harness
        and 'both lines sit on the pointer every time' in harness
        and '200 pointer moves call draw(_:) 0 times' in harness
        and 'the horizontal line is continuous across displays' in harness
        and 'the vertical line stays off the display the pointer is not on' in harness
        and 'an established selection hides the guides' in harness
        and 'a dragged edge 3pt from a window edge is not snapped' in harness
        and '120 drag samples call draw(_:) 0 times' in harness
        and '120Hz sweep' in harness,

    # 文档写清新口径：贯穿全屏、随指针实时更新、实线、独立图层、跨屏广播、
    # 不做窗口吸附/拖拽吸边，窗口 hover 高亮独立存在。
    'design-doc-crosshair-guides': all(fragment in design for fragment in (
        '系统十字光标',
        '不再自绘、不再隐藏系统光标',
        '贯穿全屏',
        '随指针实时更新',
        '1.5pt',
        '实线',
        '独立图层',
        '跨屏',
        '不做窗口吸附',
        '拖拽吸边',
        '窗口 hover 高亮',
        '选框本体保持',
    )),

    # SNAP2-2：选区外观（暗化挖孔 + 1pt 框 + 手柄 + 标签 + 滚动红框）在子图层，
    # `draw(_:)` 只画快照。这是「拖拽期 0 次重绘」的结构性保证。
    'selection-chrome-is-a-layer': all(fragment in selection_code for fragment in (
        'private final class SelectionChromeView: NSView',
        'private lazy var selectionChrome = SelectionChromeView(',
        'private func refreshSelectionChrome()',
        'selectionView?.drawSelectionChrome(',
        'selectionChrome.place(',
    )) and 'private var placedRect: NSRect = .null' in chrome_view
        and 'displayIfNeeded()' in chrome_view
        and 'withAlphaComponent(dimmingOverlayAlpha)' not in selection_code
        and 'drawSelectionChrome(' not in selection_draw
        and 'NSColor.black' not in selection_draw
        and 'snapshot.draw(in: bounds)' in selection_draw
        and 'needsDisplay = true' not in selection_draw,

    # SNAP2-3：`clearHover()` 在没有 hover 目标且高亮已隐藏时直接返回，不开事务。
    'clear-hover-short-circuits': 'guard hoverWindowRect != nil || !hoverHighlight.isHidden else { return }' in clear_hover,

    # SNAP2-4：覆盖层 `.stationary`，切 Space 时留在原位。
    'overlay-stays-put-across-spaces': '[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]' in overlay_code,
}
(out / 'rev-crosshair-source-gate.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print(f'REV crosshair source gate: {len(checks)} checks passed')
PY
