#!/bin/bash
# OPT — overlay cost revision gate + lens behaviour harness.
#
# Source gate: the three changes and their invariants (2Hz enumeration + idle
# suspension + hover-miss catch-up, 20Hz lens fed by its own clock, zero
# content requests on the event path, pid-cached bundle lookups) plus the
# DESIGN.md wording that keeps them documented.
#
# Harness: the production lens panel and sampler, offscreen, with a synthetic
# snapshot — coordinates, colour value, cached chrome and live magnified area.
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
  "$replica_root/Tests/Native/OverlayOptHarness.swift" "${mapfile_compat[@]}" -o "$binary_root/overlay-opt-harness" > "$ARTIFACT_TASK_DIR/out/harness-build.log" 2>&1
"$binary_root/overlay-opt-harness" > "$ARTIFACT_TASK_DIR/out/result.json"
cat "$ARTIFACT_TASK_DIR/out/result.json"

# --- OPT source gate ----------------------------------------------------------
python3 - "$replica_root" "$ARTIFACT_TASK_DIR/out" <<'PY'
import json, pathlib, sys
root, out = map(pathlib.Path, sys.argv[1:])
capture = root / 'Vendor/capcap/Capture'
selection = (capture / 'SelectionView.swift').read_text()
overlay = (capture / 'OverlayWindowController.swift').read_text()
detector = (capture / 'WindowDetector.swift').read_text()
lens = (root / 'Vendor/capcap/UI/MagnifierLensPanelWindow.swift').read_text()
design = (root.parent / 'DESIGN.md').read_text()
harness = (root / 'Tests/Native/OverlayOptHarness.swift').read_text()


def code(text):
    """去掉行注释：注释里可以举例，那不是实现。"""
    return '\n'.join(line.split('//', 1)[0] for line in text.splitlines())


def body(text, signature, next_signature):
    start = text.index(signature)
    end = text.index(next_signature, start)
    return text[start:end]


overlay_code = code(overlay)
selection_code = code(selection)
lens_code = code(lens)
refresh_loop = body(overlay_code, 'private func startWindowEnumerationRefresh', 'private func currentSessionChromeWindowNumbers')
refresh_list = body(overlay_code, 'private func refreshWindowList', 'private func handleSnapshotEvent')
move_pointer = body(overlay_code, 'func selectionDidMovePointer()', 'private func noteHoverTargetChange')
mouse_moved = body(selection_code, 'override func mouseMoved(with event: NSEvent)', 'override func mouseEntered')

checks = {
    # OPT-1：枚举降到 2Hz（不再是 8Hz），并且仍然是「一次枚举 + 定时刷新」结构。
    'window-enumeration-is-2hz': all(fragment in overlay_code for fragment in (
        'windowEnumerationInterval: TimeInterval = 1.0 / 2.0',
        'repeating: Self.windowEnumerationInterval',
        'private func refreshWindowList(generation: Int)',
        'windowEnumerationInFlight',
    )) and '1.0 / 8.0' not in overlay_code
        and overlay_code.count('stopWindowEnumerationRefresh()') >= 2,

    # OPT-1a：指针静止 N 秒后停表，下一次指针事件立刻恢复（单次时间戳写入）。
    'enumeration-suspends-while-pointer-rests': all(fragment in refresh_loop for fragment in (
        'Self.windowEnumerationIdleTimeout',
        'enumerationSuspendedForIdle = true',
    )) and 'private static let windowEnumerationIdleTimeout: TimeInterval = 2.0' in overlay_code
        and all(fragment in move_pointer for fragment in (
            'lastPointerActivityTime = CACurrentMediaTime()',
            'guard enumerationSuspendedForIdle else { return }',
            'refreshWindowList(generation: presentationGeneration)',
        ))
        and 'delegate?.selectionDidMovePointer()' in mouse_moved
        and 'func selectionDidMovePointer()' in selection_code
        and 'func selectionDidMovePointer() {}' in selection_code,

    # OPT-1b：hover 命中 → 未命中的那一次补采；同一次空区域不重复补采，
    # 所以空白桌面不会把枚举变成逐事件扫描。
    'hover-miss-triggers-one-catch-up-enumeration': all(fragment in overlay_code for fragment in (
        'private func noteHoverTargetChange(',
        'let hadTarget = hoverTargetPresent',
        'guard window == nil, hadTarget else { return }',
        'windowEnumerationMinimumGap: TimeInterval = 0.25',
        'noteHoverTargetChange(window)',
    )),

    # OPT-1c：浮动层窗口的 bundle-id 查询按 pid 缓存，每轮不再走 launchd。
    'floating-bundle-lookup-cached-per-pid': all(fragment in detector for fragment in (
        'private static var ownerIdentityCache: [pid_t: OwnerIdentity] = [:]',
        'if let cached = ownerIdentityCache[pid], cached.name == ownerName',
        'NSRunningApplication(processIdentifier: pid)?.bundleIdentifier',
        'ownerBundleID(for: pid, ownerName: name)',
    )),

    # OPT-2：放大镜 20Hz（面板侧上限 + 控制器侧唯一的喂给节奏）。
    'lens-runs-at-20hz': all(fragment in lens for fragment in (
        'static let contentRefreshInterval: TimeInterval = 1.0 / 20.0',
    )) and all(fragment in overlay_code for fragment in (
        'magnifierLensRefreshInterval: TimeInterval = 1.0 / 20.0',
        'private func startMagnifierLensRefresh()',
        'private func stopMagnifierLensRefresh()',
        'timer.setEventHandler',
        'self.refreshMagnifierLensPanelContent()',
    )) and overlay_code.count('startMagnifierLensRefresh()') >= 3

        # 生命周期：停止点覆盖每条 dismiss 路径（tearDown + 完成选区）。
        and overlay_code.count('stopMagnifierLensRefresh()') >= 3,

    # OPT-2b：静态部分（背景 + 提示行）缓存复用，每帧只重绘放大区与数值行。
    'lens-caches-static-chrome': all(fragment in lens_code for fragment in (
        'private struct StaticChromeKey: Equatable',
        'private func staticChromeImage() -> NSImage?',
        'private func renderStaticChrome() -> NSImage?',
        'NSBitmapImageRep(',
        'image.addRepresentation(rep)',
        'chrome.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)',
        'drawValueRows()',
        'drawHintRows()',
    )) and 'private func drawInfo()' not in lens_code
        and 'drawMagnifiedArea(in: magnifiedRect)' in lens_code,

    # OPT-3：事件路径零内容请求——两个 mouseMoved monitor 已删除，事件里只留
    # 一个时间戳写入；`lens-request` 只剩 20Hz 定时器 + 快照落地两处调用。
    'event-path-has-no-lens-request': 'mouseMovedLocalMonitor' not in overlay_code
        and 'mouseMovedGlobalMonitor' not in overlay_code
        and 'addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged])' not in overlay_code
        and 'addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged])' not in overlay_code
        and overlay_code.count('refreshMagnifierLensPanelContent()') - 1 <= 3
        and 'OverlayPerfSignpost.begin("lens-request")' in overlay_code
        and 'OverlayPerfSignpost.begin("window-scan")' in overlay_code
        and 'OverlayPerfSignpost.begin("lens-draw")' in lens_code,

    # 文档口径：三项改法都写清楚，否则下一轮没人知道 2Hz 是有意的。
    'design-doc-overlay-cost': all(fragment in design for fragment in (
        '2Hz',
        '未命中补采',
        '20Hz',
        '事件路径零请求',
    )),

    # harness：坐标/色值/缓存/放大区都经过实测断言，不是只靠文本门。
    'harness-proves-lens-values': all(fragment in harness for fragment in (
        'AppKit y-up point maps to the same pixel row from the top',
        'sampling returns the exact pixel colour',
        'the 20Hz path applies the sampled colour',
        'the cached hint rows still paint text',
        'the live value row still paints text',
        'the magnified area follows the pointer without a stale cache',
        'switching to RGB rebuilds the cached chrome',
    )),
}
(out / 'overlay-opt-source-gate.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print(f'OPT source gate: {len(checks)} checks passed')
PY
