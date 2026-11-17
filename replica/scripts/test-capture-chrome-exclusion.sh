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

    # POL/SG：吸附辅助线住在独立图层里（每屏一条，四边 + 可选中线），只在 hover
    # 目标变化时改 layer path，不再让整屏快照重绘；旧的 draw(_:) 版贯穿辅线与
    # 失效带必须彻底消失，否则延迟会回来。
    'overlay-guides-live-in-layers': 'private final class SnapGuideView: NSView' in code(selection)
                                     and 'private let snapGuide = SnapGuideView()' in code(selection)
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

# --- SG 源码门：系统十字光标 + 吸附式辅助线 -----------------------------------
python3 - "$replica_root" "$ARTIFACT_TASK_DIR/out" <<'PY'
import json, pathlib, sys
root, out = map(pathlib.Path, sys.argv[1:])
capture = root / 'Vendor/capcap/Capture'
selection = (capture / 'SelectionView.swift').read_text()
overlay = (capture / 'OverlayWindowController.swift').read_text()
detector = (capture / 'WindowDetector.swift').read_text()
screenshot_settings = (root / 'Vendor/capcap/Adapters/ScreenshotSettings.swift').read_text()
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
band = body(selection_code, 'private final class SnapGuideView: NSView', 'class SelectionView: NSView')
# 只取 refreshSnapGuide 本身：它后面紧跟的是选区 chrome / 拖拽吸附的刷新函数，
# 那些函数本来就要写图层（`needsDisplay` 只在图层视图里）。
refresh = body(selection_code, 'private func refreshSnapGuide()', 'private func refreshSelectionChrome()')
update_hover = body(selection_code, 'func updateHover(screenPoint: NSPoint)', 'private func clearHover')
cursor_rects = body(selection_code, 'override func resetCursorRects()', 'func refreshCursorRects')
clear_hover = body(selection_code, 'private func clearHover()', 'override func draw(_ dirtyRect: NSRect) {')
# `SelectionView.draw(_:)` 只画快照——选区外观在子图层里。
# 起始锚点用 MEAS 埋点那一行（`let perfDraw = ...`）：它的 `defer` 现在在埋点之后，
# 所以旧的 `{\n        defer {` 锚点在这版源码上取不到函数体（这是源码门自身的
# 锚点问题，与绘制内容无关）。三种区域（hover / 选区 chrome / 快照）各有一处
# `override func draw`，只有快照这处带 `perfDraw`，因此锚点唯一。
selection_draw = body(selection_code,
                      '    override func draw(_ dirtyRect: NSRect) {\n        let perfDraw',
                      '    func drawSelectionChrome(')
drag_new = body(selection_code, '        case .drawNew:', '        case .move:')
mouse_up = body(selection_code, 'override func mouseUp(with event: NSEvent)', 'override func mouseMoved(with event: NSEvent)')
chrome_view = body(selection_code, 'private final class SelectionChromeView: NSView', 'private final class SnapHighlightView: NSView')
highlight_view = body(selection_code, 'private final class SnapHighlightView: NSView', 'class SelectionView: NSView')
snap_helpers = body(selection_code, 'private func dragSnapCandidatesForCurrentDrag()', 'func updateSelectionRect')

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
    # 并且在覆盖层激活时主动 set 一次。
    'pointer-is-the-system-crosshair': 'addCursorRect(bounds, cursor: .crosshair)' in cursor_rects
        and 'resetCursorRects()' in selection_code
        and 'NSCursor.crosshair.set()' in selection_code
        and 'NSCursor.crosshair.set()' in overlay_code,

    # SG：辅助线仍是独立图层，但只有一条：四边 + 可选中线都画在同一个
    # CAShapeLayer 里；指针不是这个视图的一部分。
    'snap-guide-is-one-independent-layer': all(fragment in selection_code for fragment in (
        'private final class SnapGuideView: NSView',
        'private let snapGuide = SnapGuideView()',
        'private let lineLayer = CAShapeLayer()',
        'private func installSnapGuide()',
    )) and 'needsDisplay' not in refresh,

    # SG：线的样式只有一个来源（线型常量抽成 `dashPattern`，改回实线只改它）。
    # 规格明确：1.5pt、systemGray 50%、虚线 6/4。SEL 门继续管选框本体（蓝色实线）。
    'guide-style-is-dashed-6-4': all(fragment in band for fragment in (
        'static let lineWidth: CGFloat = 1.5',
        'static let alpha: CGFloat = 0.5',
        'static let dashPattern: [NSNumber]? = [6, 4]',
        'NSColor.systemGray',
        'lineLayer.lineDashPattern = Self.dashPattern',
    )),

    # SG：线描的是 hover 窗口的四条边（+ 可选中线），不是贯穿光标的横竖线。
    'guide-outlines-hover-window': all(fragment in band for fragment in (
        'path.addRect(edge)',
        'path.move(to: CGPoint(x: edge.midX, y: edge.minY))',
        'path.move(to: CGPoint(x: edge.minX, y: edge.midY))',
    )) and 'detector.windowAt(cgPoint: cgPoint)' in update_hover
        and 'let viewRect = Self.viewRect(' in update_hover,

    # SG：更新时机从「每个 mouseMoved」改成「hover 目标变化」。两处提前返回：
    # 目标没变（hover guard）与几何没变（图层 guard），同窗口内零写入。
    'guide-updates-only-on-target-change': 'guard clamped != hoverWindowRect' in update_hover
        and 'hoverWindowID != detected.windowID else' in update_hover
        and 'guard rect != placedTarget || centerLines != showsCenterLines else { return false }' in band
        and 'hoverTargetChangeCount += 1' in update_hover
        and 'snapGuide.place(' in refresh
        and 'mouseMoved' not in refresh,

    # SG：同一关闭隐式动画的事务内更新，并对图层同步 display/displayIfNeeded，
    # 不把位置留给下一轮 runloop。
    'guide-updates-synchronously': all(fragment in refresh for fragment in (
        'CATransaction.begin()',
        'CATransaction.setDisableActions(true)',
        'CATransaction.commit()',
        'snapGuide.place(',
    )) and all(fragment in band for fragment in (
        'lineLayer.setNeedsDisplay()',
        'lineLayer.displayIfNeeded()',
    )),

    # SG：每屏各自吸附——点必须落在本遮罩所在屏幕；不做跨屏广播。
    'guide-is-per-display': 'displayFrame.contains(screenPoint)' in update_hover
        and 'primaryHeight - frame.origin.y - frame.height' in selection_code
        and 'onCrosshairMoved' not in selection_code
        and 'onCrosshairMoved' not in overlay_code
        and 'broadcastCrosshair' not in overlay_code
        and 'updateCrosshair' not in overlay_code,

    # SG/OPT：窗口列表开场枚举一次 + 2Hz 增量刷新（指针静止暂停、hover
    # 未命中补采，见 `test-overlay-opt.sh`）；鼠标移动只扫缓存；计时器在
    # tearDown 里停掉（定义 + 调用至少两处）。
    'window-list-refresh-is-capped-at-2hz': all(fragment in overlay_code for fragment in (
        'windowEnumerationInterval: TimeInterval = 1.0 / 2.0',
        'DispatchSource.makeTimerSource(queue: .main)',
        'repeating: Self.windowEnumerationInterval',
        'private func refreshWindowList(generation: Int)',
        'windowEnumerationInFlight',
    )) and overlay_code.count('stopWindowEnumerationRefresh()') >= 2,

    # SG：枚举时排除本产品自身浮层（本进程 HUD + 同 bundle 孪生实例的 floating+），
    # 否则光标芯片会被吸成目标。
    'hover-excludes-product-chrome': all(fragment in detector_code for fragment in (
        'let isProductChrome: Bool',
        'static func isProductChrome(',
        'layer >= Int(CGWindowLevelForKey(.screenSaverWindow))',
        'layer >= Int(NSWindow.Level.floating.rawValue)',
        '!$0.isProductChrome',
    )) and 'private func currentSessionChromeWindowNumbers()' in overlay_code
        and 'windows.filter { !sessionChrome.contains($0.windowID) }' in overlay_code,

    # SG：中线开关读同一个键，设置页有开关和三语文案。
    'center-lines-setting-wired': 'snapGuidesCenterLinesEnabled' in code(screenshot_settings)
        and 'snapGuidesCenterLinesKey' in code(screenshot_settings)
        and 'selectionView.showsGuideCenterLines = BlinkClipScreenshotSettings.snapGuidesCenterLinesEnabled' in overlay_code
        and 'var showsGuideCenterLines = false' in selection_code
        and 'settings.snap-guides.center-lines.toggle' in aux
        and all(key in aux for key in (
            'ScreenshotSettingsCopy.text(.guidesSectionTitle)',
            'ScreenshotSettingsCopy.text(.centerLinesTitle)',
            'ScreenshotSettingsCopy.text(.centerLinesSubtitle)',
        )),

    # harness：不是只靠文本门——吸附几何、同窗口零更新、120Hz 帧序列、跨屏 Y 翻转、
    # 自身浮层排除都有实测断言；五轮开关期间拦截 cursor-hide 入口并断言 0 调用。
    'harness-proves-snap-behaviour': 'hideCalls == 0 && unhideCalls == 0' in harness
        and 'NSSelectorFromString("hide")' in harness
        and 'the guide is dashed 6/4' in harness
        and '200 moves inside one window write the guide 0 times' in harness
        and '120Hz sweep' in harness
        and 'the Y flip is correct on a display above the primary' in harness
        and 'own/twin floating chrome is skipped' in harness,

    # 文档写清新口径：系统十字光标、吸附四边、2Hz、同窗口零更新、虚线 6/4、跨屏不串位。
    'design-doc-snap-guides': all(fragment in design for fragment in (
        '系统十字光标',
        '不再自绘、不再隐藏系统光标',
        '吸附辅助线',
        '独立图层',
        '同步 `displayIfNeeded()`',
        '1.5pt',
        '虚线（6/4）',
        '2Hz',
        '0 次重绘',
        '跨屏不串位',
        '选框本体保持',
    )),

    # SNAP2-1：拖拽期吸附。四条边各自找最近的**同轴**窗口边，候选来自 8Hz
    # 缓存列表 + 拖拽起点处的 hover 窗口；距离严格 < 8pt 才吸，吸完改几何。
    'drag-snap-is-same-axis-nearest-edge': all(fragment in snap_helpers for fragment in (
        'detector.cachedWindows',
        'where detected.isSelectableCaptureTarget && !detected.isProductChrome',
        'if let hover = hoverWindowRect',
        'candidate.minX, candidate.maxX',
        'candidate.minY, candidate.maxY',
        'let distance = abs(edge - value)',
        'if distance < bestDistance',
        'minX = target',
        'maxX = target',
        'minY = target',
        'maxY = target',
    )) and 'static let dragSnapDistance: CGFloat = 8' in selection_code
        and 'guard showsDragSnap, aspectRatio == nil, !dragSnapCandidates.isEmpty' in snap_helpers
        and 'dragSnapCandidates = dragSnapCandidatesForCurrentDrag()' in selection_code,

    # SNAP2-1：只改几何 + 写图层。拖拽分支里没有任何 needsDisplay；高亮是独立
    # 图层（2pt / 100%），松手清空高亮。
    'drag-snap-writes-layers-not-snapshot': all(fragment in drag_new for fragment in (
        'let snapped = snappedDragRect(dragged)',
        'selectionRect = snapped.rect',
        'refreshSelectionChrome()',
        'refreshDragSnapHighlight()',
    )) and 'needsDisplay' not in drag_new
        and 'drawSelectionChrome(' not in drag_new
        and 'dragSnappedEdges = []' in mouse_up
        and 'refreshDragSnapHighlight()' in mouse_up,

    # SNAP2-1：高亮只有被吸附的那条边，样式常量只有一个来源。
    'drag-snap-highlight-is-its-own-layer': all(fragment in highlight_view for fragment in (
        'private let lineLayer = CAShapeLayer()',
        'static let lineWidth: CGFloat = 2',
        'static let alpha: CGFloat = 1.0',
        'lineLayer.lineDashPattern = nil',
        'func place(_ segments: [Segment]) -> Bool',
        'guard segments != placedSegments else { return wrote }',
        'lineLayer.setNeedsDisplay()',
        'lineLayer.displayIfNeeded()',
    )) and 'snapHighlight.place(segments)' in selection_code
        and 'let segments: [SnapHighlightView.Segment]' in selection_code
        and 'DragSnapEdge.allCases.compactMap' in selection_code,

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

    # SNAP2-3：`clearHover()` 在没有 hover 目标时先看 guide 是否可见，隐藏时不开事务。
    'clear-hover-short-circuits': 'guard !snapGuide.isHidden else { return }' in clear_hover
        and clear_hover.index('guard !snapGuide.isHidden') < clear_hover.index('refreshSnapGuide()'),

    # SNAP2-4：覆盖层 `.stationary`，切 Space 时留在原位。
    'overlay-stays-put-across-spaces': '[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]' in overlay_code,

    # SNAP2-5：开关默认开。设置页「框选辅助」卡片在出货 648×600 窗口里没有
    # 空余高度（`SettingsArchitectureHarness` 要求每张卡都能在视口内从卡顶量到
    # 卡底），故本次不加设置行；`showsDragSnap` 是唯一开关，默认 true。
    'drag-snap-defaults-on': 'var showsDragSnap = true' in selection_code
        and 'showsDragSnap' in snap_helpers,

    # SNAP2-6：harness 实测——3pt 吸附、7.5/8/10pt 门限、同轴、高亮出现/松手清除、
    # 拖拽期 0 次 `draw(_:)`、成图裁剪与吸附位置一致。
    'harness-proves-drag-snap': all(fragment in harness for fragment in (
        'a dragged edge 3pt from a window edge snaps exactly onto it',
        'the snapped edge is highlighted while the drag holds it',
        'the snapped-edge highlight clears on mouse-up',
        '120 drag samples call draw(_:) 0 times',
        'pt from the window edge: ',
        '(expectedSnap ? "snaps onto it" : "does not snap")',
        '(0, 7.5, true), (1, 8, false), (2, 10, false),',
        'a vertical selection edge does not snap to a horizontal window edge',
        'the capture crop starts on the snapped edge',
        'NSEvent.mouseEvent(',
    )),

    # SNAP2-7：文档写明拖拽吸附口径，并写清为什么这次没有设置开关。
    'design-doc-drag-snap': all(fragment in design for fragment in (
        '拖拽吸附',
        '同轴窗口边',
        '< 8pt',
        '松手（`mouseUp`）清除高亮',
        '拖拽期不重绘快照',
        '.stationary',
        'showsDragSnap',
    )),
}
(out / 'cur-cursor-source-gate.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print(f'SG snap-guide source gate: {len(checks)} checks passed')
PY
