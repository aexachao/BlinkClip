#!/bin/bash
set -euo pipefail
if [[ -z "${ARTIFACT_TASK_DIR:-}" ]]; then
  exec "$HOME/dev-artifacts/bin/storage-guard" run --repo blinkclip --task capture-glue -- bash "$0" "$@"
fi
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp/"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
export BLINKCLIP_TEST_CONFIGURATION=release
mkdir -p "$TMPDIR" "$ARTIFACT_TASK_DIR/out"
exec > >(tee "$ARTIFACT_TASK_DIR/out/run.log") 2>&1
source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_core
test_root="$ARTIFACT_TASK_DIR/build/harness"
mkdir -p "$test_root"
source_file="$replica_root/Tests/Native/CaptureIntegrationHarness.swift"
xcrun swiftc -parse-as-library -swift-version 5 -D CAPTURE_BOUNDARY -module-name BlinkClipCapture \
  -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -emit-library -emit-module -emit-module-path "$test_root/BlinkClipCapture.swiftmodule" \
  "$source_file" "$replica_root/Vendor/capcap/Adapters/ScreenshotSettings.swift" \
  "$replica_root/Vendor/capcap/Adapters/CaptureEntry.swift" \
  "$replica_root/Vendor/capcap/Adapters/HistoryManagerBridge.swift" \
  -o "$test_root/libBlinkClipCapture.dylib"
compile_native_test_harness capture-integration \
  -I "$test_root" -L "$test_root" -lBlinkClipCapture -Xlinker -rpath -Xlinker "$test_root" \
  "$source_file" "$replica_root/Sources/BlinkClip/Screenshot/ScreenshotCoordinator.swift" \
  "$replica_root/Sources/BlinkClip/Screenshot/ScreenshotWindowHider.swift" \
  "$replica_root/Sources/BlinkClip/Screenshot/ScreenshotHistoryBridge.swift" \
  "$replica_root/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift" \
  "$replica_root/Sources/BlinkClip/UI/ReplicaCopiedOSD.swift" \
  "$replica_root/Sources/BlinkClip/UI/ReplicaToastCopy.swift" \
  "$replica_root/Sources/BlinkClip/UI/ReplicaToast.swift"
# Each invocation needs an empty Store, including repeats inside one guarded task.
export CAPTURE_STORE_ROOT="$ARTIFACT_TASK_DIR/build/store-$(uuidgen)"
"$test_harness" > "$ARTIFACT_TASK_DIR/out/result.json"
cat "$ARTIFACT_TASK_DIR/out/result.json"
du -sh "$ARTIFACT_TASK_DIR"
df -h /System/Volumes/Data

# --- T2 源码门：四条 toast 必须是同一个组件 -------------------------------------
python3 - "$replica_root" "$ARTIFACT_TASK_DIR/out" <<'PY'
import json, pathlib, re, sys
root, out = map(pathlib.Path, sys.argv[1:])
ui = root / 'Sources/BlinkClip/UI'
toast = (ui / 'ReplicaToast.swift').read_text()
facade = (ui / 'ReplicaCopiedOSD.swift').read_text()
coordinator = (root / 'Sources/BlinkClip/Screenshot/ScreenshotCoordinator.swift').read_text()
copy_table = (ui / 'ReplicaToastCopy.swift').read_text()


def code(text):
    """去掉行注释：注释里可以提到窗口类名，那不是实现。"""
    return '\n'.join(line.split('//', 1)[0] for line in text.splitlines())


# 轻提示只有一个窗口子类：除了主面板/堆叠面板，就只剩 toast 盘面。
panel_subclasses = []
for path in sorted((root / 'Sources/BlinkClip').rglob('*.swift')):
    for name in re.findall(r'^\s*(?:final\s+)?class\s+(\w+)\s*:\s*(?:NS)?Panel', code(path.read_text()), re.M):
        panel_subclasses.append(f'{path.name}:{name}')
checks = {
    # 轻提示只有一个窗口子类：`ReplicaToastPanel`；门面（`ReplicaCopiedOSD`）一个都不建。
    'single-toast-panel-class': [name for name in panel_subclasses if name.startswith('ReplicaToast')]
                                == ['ReplicaToast.swift:ReplicaToastPanel']
                                and not [name for name in panel_subclasses if name.startswith('ReplicaCopiedOSD')],
    # 四条 toast 的入口都走同一个 present，没有任何一条自己建窗口。
    'facade-creates-no-window': 'NSWindow(' not in code(facade) and 'NSPanel(' not in code(facade)
                                and 'NSHostingView' not in code(facade),
    'four-toasts-share-one-presenter':
        re.findall(r'ReplicaToast\.shared\.present', code(facade)) and
        len(re.findall(r'ReplicaToast\.shared\.present', code(facade))) == 4,
    'screenshot-toast-uses-same-entry': 'ReplicaCopiedOSD.showScreenshotCopied()' in coordinator,
    # 停止「同一句话两遍」：暂停 toast 只有一处文案来源，没有副标题参数。
    'pause-toast-has-no-subtitle': 'subtitle' not in code(facade),
    'single-trilingual-copy-table': copy_table.count(': Entry(') == 5 and 'private struct Entry' in copy_table,
    # 图标语义只靠符号：四类 toast 都是无底衬的线条符号，不许出现 .circle 变体。
    'toast-symbols-are-bare': sorted(re.findall(r'symbolName: "([^"]+)"', code(facade)))
                              == ['arrow.clockwise', 'checkmark', 'checkmark', 'pause']
                              and not [name for name in re.findall(r'symbolName: "([^"]+)"', code(facade))
                                       if '.circle' in name or 'fill' in name],
    # 不入图：写入口被钉死，且上屏前后各钉一次。
    'sharing-type-is-pinned': 'override var sharingType' in code(toast)
                              and code(toast).count('toast.sharingType = .none') >= 2,
    # 停留时长不能挂在主线程上：整段「停留 + 淡出」必须是渲染服务器推进的 CA 时间线，
    # 计时锚点是「首帧已提交」的那一刻，收起按墙钟补刀（1.0.19 的 NSAnimationContext
    # 写法在主线程忙时把「已复制截图」拖到 2.72s）。
    'timeline-is-render-server-driven': 'CAKeyframeAnimation' in code(toast)
                                        and code(toast).count('CATransaction.flush()') >= 1
                                        and 'NSAnimationContext' not in code(toast)
                                        and 'animator().alphaValue' not in code(toast),
    'hold-clock-anchored-at-first-frame': 'lastVisibleAt = Date()' in code(toast)
                                          and 'toast.displayIfNeeded()' in code(toast),
    'dismiss-is-wall-clock-decoupled': 'orderOutAfterTimeline' in code(toast)
                                       and 'holdDuration + Self.fadeDuration' in code(toast),
    # 位置/时长是规范里的数字，不是各处随手写。
    'toast-geometry-constants': all(name in code(toast) for name in
                                    ('bottomInset: CGFloat = 120', 'holdDuration: TimeInterval = 1.3',
                                     'fadeDuration: TimeInterval = 0.2', 'panelSize = NSSize(width: 128, height: 128)',
                                     'cornerRadius: CGFloat = 16', 'iconPointSize: CGFloat = 42',
                                     'iconTextSpacing: CGFloat = 16', 'textPointSize: CGFloat = 14',
                                     'textLineSpacing: CGFloat = 2')),
    # 盘面**没有描边**（2026-11-16 用户反馈「toast 有一圈黑边」）：`borderWidth` /
    # `borderColor` 两处赋值都不许再出现。旧代码写的是 `borderWidth = 1` +
    # `NSColor.separatorColor.cgColor`；盘面外观固定 vibrantDark，那个动态色在这个上下文里
    # 解析成不透明 #232323，与系统外观无关——实机 2x 逐像素：盘面最外 2px = (35,35,35)，
    # 盘内材质 = (148,155,159)，一头一尾差 ~120/255，浅色壁纸上看过去就是一圈黑框。
    'toast-plate-has-no-stroke': '.borderWidth' not in code(toast)
                                 and '.borderColor' not in code(toast)
                                 and 'separatorColor' not in code(toast),
    # 圆角仍然只靠 mask 收口（删描边不能顺手把圆角也删了），边界交给 HUD 材质自己。
    # 反方向也钉一次：不许把去掉的描边换成别的「定形」层（阴影、外框、第二层视图）。
    'toast-plate-boundary-is-material-only': code(toast).count('masksToBounds = true') == 1
                                             and 'shadowOpacity' not in code(toast)
                                             and 'shadowRadius' not in code(toast)
                                             and 'hasShadow = true' not in code(toast),
}
(out / 'toast-source-gate.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print(f'Toast source gate: {len(checks)} checks passed (one component for all four toasts)')
PY
