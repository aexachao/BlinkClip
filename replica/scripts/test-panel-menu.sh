#!/bin/bash
# 快捷菜单的结构回归：状态栏图标右键（.statusItem）与面板工具栏 ⋯（.panelOverflow）
# 两个变体都经由同一台模型 / 构建器出菜单，检查 4 组 + 分隔线、每项左侧 SF Symbol、
# 检查更新 / 帮助与关于、面板变体的暂停子菜单（15/30/60/180/480 分钟）、
# 退出二次确认（取消不退出），外加两个变体展开菜单的离屏截图。
#
# 用法：
#   bash replica/scripts/test-panel-menu.sh                 # 只跑断言
#   bash replica/scripts/test-panel-menu.sh --render[=目录]  # 额外渲染展开菜单截图
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/blinkclip-panel-menu.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

render_dir=''
case "${1:-}" in
  '') ;;
  --render) render_dir="${BLINKCLIP_PANEL_MENU_RENDER_DIR:-${TMPDIR:-/tmp}/blinkclip-panel-menu-renders}" ;;
  --render=*) render_dir="${1#*=}" ;;
  *) printf '未知参数：%s\n' "$1" >&2; exit 2 ;;
esac

# --- 源码接线门：菜单数据可测，但真正的接线在 AppMain / PanelViews 里，必须一起核对 ---
python3 - "$replica_root" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
app_main = (root / "Sources/BlinkClip/AppMain.swift").read_text()
menu = (root / "Sources/BlinkClip/PanelShortcutMenu.swift").read_text()
panel_views = (root / "Sources/BlinkClip/UI/PanelViews.swift").read_text()

# 1) 状态栏右键菜单由模型构建，不再手搓 NSMenuItem。
status_block = app_main.split("private func statusClicked(", 1)[1].split("@objc private func", 1)[0]
assert "PanelShortcutMenuBuilder.makeMenu(" in status_block, "statusClicked 没有走菜单构建器"
assert "NSMenuItem(title:" not in status_block, "statusClicked 里还有手搓菜单项"
assert "menuItem(" not in status_block, "statusClicked 里还在用菜单项工厂"
assert "addItem(.separator())" not in status_block, "分隔线应由模型分组统一补"

# 2) 面板工具栏 ⋯ 用同一台模型 / 构建器，只是换成 .panelOverflow 变体。
assert "private struct PanelMoreMenu" in panel_views, "找不到面板 ⋯ 菜单"
more = panel_views.split("private struct PanelMoreMenu", 1)[1]
assert "PanelShortcutMenuBuilder.makeMenu(" in more, "面板 ⋯ 没有走同一台菜单构建器"
assert "PanelShortcutMenuContext(" in more, "面板 ⋯ 没有用共用菜单上下文"
assert "variant: .panelOverflow" in more, "面板 ⋯ 必须显式使用 .panelOverflow 变体"
assert "NSMenuItem(title:" not in more, "面板 ⋯ 里还有手搓菜单项"
assert "NSApp.terminate(nil)" not in more, "面板退出不能直连 NSApp.terminate"
assert 'NSApp.sendAction(NSSelectorFromString("about:")' not in more, "面板「帮助与关于」不能再开独立关于窗口"
assert "aboutController" not in more, "面板「帮助与关于」不能直接打开关于窗口"

# 3) 两个变体都在同一台模型里，且面板变体明确不出现「打开剪贴板」。
assert "enum PanelShortcutMenuVariant" in menu, "缺少变体枚举"
assert "case statusItem" in menu and "case panelOverflow" in menu, "变体枚举缺分支"
assert "static let pauseWindowMinutes = [15, 30, 60, 180, 480]" in menu, "暂停档位不是 15/30/60/180/480"
assert 'if context.variant == .statusItem {' in menu, "「打开剪贴板」必须只在状态栏变体出现"

# 4) 四组分组、图标、检查更新 / 帮助与关于 / 退出都在模型里。
for needle in ['PanelShortcutMenuGroup(title: "动作"', 'PanelShortcutMenuGroup(title: "应用"',
               'PanelShortcutMenuGroup(title: "维护"', 'PanelShortcutMenuGroup(title: "退出"']:
    assert needle in menu, f"缺少分组：{needle}"
assert "rectangle.on.rectangle" in menu and "square.and.pencil" in menu
assert "gearshape" in menu and "arrow.triangle.2.circlepath" in menu
assert "info.circle" in menu and "stethoscope" in menu
assert "pause.circle" in menu and "play.circle" in menu and '"power"' in menu

# 5) 图标走 SF Symbol 且统一成模板图。
assert "NSImage(systemSymbolName:" in menu, "图标必须用 SF Symbol"
assert "isTemplate = true" in menu, "图标必须是模板图"
assert "iconSide" in menu, "图标尺寸必须统一"

# 6) 检查更新复用关于页的同一条路径，不另写一套。
check_updates = app_main.split("@objc private func checkForUpdates(", 1)[1].split("@objc private func", 1)[0]
assert "try inAppUpdater.checkForUpdates()" in check_updates, "检查更新必须复用 BlinkClipInAppUpdater"
assert "SPUStandardUpdaterController" not in app_main, "菜单里不能自己起 Sparkle 控制器"

# 7) 帮助与关于只发通知，不直接开关于窗口。
open_about = app_main.split("@objc private func openAbout(", 1)[1].split("@objc private func", 1)[0]
assert "NotificationCenter.default.post(name: .blinkClipOpenAbout" in open_about, "帮助与关于必须发通知"
assert "aboutController" not in open_about, "帮助与关于不能直接打开关于窗口"
assert "static let blinkClipOpenAbout" in menu, "通知名要在 BlinkClip 模块里定义"
assert "由设置窗口观察后打开关于页" in menu, "通知名旁边要写明由设置窗口观察后打开关于页"

# 8) 模型里每个动作名都要在 AppMain 里真的存在对应 @objc 方法，
#    否则菜单点了就是静默无操作。
actions = re.findall(r'case \w+ = "(\w+):"', menu)
assert len(actions) >= 11, f"动作清单太少：{actions}"
for required in ["newText", "settings", "checkForUpdates", "openAbout",
                 "pause", "pauseIndefinitely", "pauseForMinutes", "resumeMonitoring", "confirmQuit"]:
    assert required in actions, f"缺少动作：{required}"
declared = set(re.findall(r'@objc (?:private )?func (\w+)\(', app_main)) | \
           set(re.findall(r'@objc (?:private )?func (\w+)\(', menu))
missing = [name for name in actions if name not in declared]
assert not missing, f"菜单动作没有对应的 @objc 方法：{missing}"

# 9) 退出必须过二次确认，未确认不 terminate；两个变体共用 confirmQuit:。
confirm_quit = app_main.split("@objc private func confirmQuit(", 1)[1].split("@objc private func", 1)[0]
assert "PanelShortcutMenuQuitConfirmation.confirm(" in confirm_quit, "退出项必须走确认弹窗"
assert "terminate(" not in confirm_quit, "确认前不能直接 terminate"
assert "guard shouldTerminate(response) else { return false }" in menu, "取消必须直接返回、不终止进程"
assert "alertSecondButtonReturn" in menu, "只有确认按钮放行"
assert "hasDestructiveAction = true" in menu, "只有退出按钮带破坏性配色"
assert "cancel.keyEquivalent = " in menu, "取消必须是默认按钮（Esc 也落在取消上）"
assert '"\\u{1b}"' in menu, "Esc 必须映射到取消"
assert menu.count('case confirmQuit = "confirmQuit:"') == 1, "退出动作只能有一条"

# 10) 面板暂停子菜单的分钟数经 representedObject 传给 AppMain。
pause_minutes = app_main.split("@objc private func pauseForMinutes(", 1)[1].split("@objc private func", 1)[0]
assert "representedObject as? Int" in pause_minutes, "定时暂停必须从 representedObject 取分钟数"
assert "pauseMonitoring(minutes: minutes)" in pause_minutes, "定时暂停必须走 pauseMonitoring(minutes:)"
PY

# --- 离屏 harness：真实 NSMenu + 真实 SF Symbol + 注入的确认响应 ----------------
source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_core
compile_native_test_harness panel-shortcut-menu \
  "$replica_root/Sources/BlinkClip/PanelShortcutMenu.swift" \
  "$replica_root/Tests/Native/PanelShortcutMenuSurfaceView.swift" \
  "$replica_root/Tests/Native/PanelShortcutMenuHarness.swift"

if [[ -n "$render_dir" ]]; then
  mkdir -p "$render_dir"
  rm -f "$render_dir"/panel-menu-*.png "$render_dir"/panel-overflow-menu-*.png \
        "$render_dir"/panel-overflow-pause-*.png
  "$test_harness" --render "$render_dir" > "$test_root/result.json"
else
  "$test_harness" > "$test_root/result.json"
fi
cat "$test_root/result.json"

python3 - "$test_root/result.json" <<'PY'
import json
import pathlib
import sys
report = json.loads(pathlib.Path(sys.argv[1]).read_text())
if report.get("passed") is not True:
    raise SystemExit("panel shortcut menu harness did not pass")
for label, key in [("状态栏", "menu"), ("面板 ⋯", "panelMenu")]:
    groups = report.get(key) or []
    if len(groups) != 4:
        raise SystemExit(f"{label} 菜单不是 4 组：{len(groups)}")
    for group in groups:
        print(f'  [{label}] {group["group"]}: ' + ", ".join(item["title"] for item in group["items"]))
        for item in group["items"]:
            if "submenu" in item:
                print(f'    ↳ {item["title"]}: ' +
                      ", ".join(sub["title"] for sub in item["submenu"]))
print(f'panel-menu: {report["count"]} checks passed')
for path in report.get("renders", []):
    print(f"  截图：{path}")
PY

if [[ -n "$render_dir" ]]; then
  ls -1 "$render_dir"/panel-overflow-menu-*.png >/dev/null 2>&1 || {
    printf '没有生成面板 ⋯ 菜单截图：%s\n' "$render_dir" >&2
    exit 1
  }
  ls -1 "$render_dir"/panel-overflow-pause-*.png >/dev/null 2>&1 || {
    printf '没有生成面板暂停子菜单截图：%s\n' "$render_dir" >&2
    exit 1
  }
  printf '展开菜单截图：%s\n' "$render_dir"
fi
