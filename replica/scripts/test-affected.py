#!/usr/bin/env python3
"""按改动范围选择测试：日常每轮只跑受影响的测试，全量留给发版前。

用法：
  python3 replica/scripts/test-affected.py --worktree --dry-run   # 看工作区改动会选哪些
  python3 replica/scripts/test-affected.py --worktree             # 选中的直接跑
  python3 replica/scripts/test-affected.py --base origin/main --dry-run
  python3 replica/scripts/test-affected.py --full                 # 发版前全量
  python3 replica/scripts/test-affected.py --audit                # 映射表体检：哪些源码文件没有规则

选择规则（RULE_TABLE）：每个改动文件只命中**第一条**匹配的规则（规则从具体到宽泛排列），
命中即停。这样「改一个 core 文件」不会被宽泛的目录规则放大成全量，同时每条具体规则都
含至少一个会编译该文件的测试（编译门），避免漏掉编译级回归。

保守兜底：任何文件若一条规则都不命中，本次直接回退全量，并在输出里点名这些路径。
文档类路径（docs/**、根目录 *.md）有显式的「无测试项」规则，因此不会误触发全量。
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TIMINGS_PATH = os.path.join(REPO_ROOT, ".local", "test-affected", "timings.json")


# --------------------------------------------------------------------------------------
# 测试项清单（现网全部测试入口）
#   cmd      : 运行命令（相对仓库根目录）
#   group    : 归属（core / native / python / static / site）
#   covers   : 它编译或读取哪些源码（来自脚本头注释与 compile_native_test_harness 参数）
#   checks   : 它断言什么
#   requires : 运行前必须存在的环境变量（缺失时记为「未执行」，不当通过）
# --------------------------------------------------------------------------------------
ITEMS = {}


def _item(key, cmd, group, covers, checks, requires=(), note="", manual="", prep=(), env=None):
    # manual: 非自动化项的原因（缺环境变量时记为「手工」而不是「未执行」，见 run_selection）
    # prep : 运行前必须先在同一个隔离目录里跑完的前置命令（列表 of argv）
    # cmd  : 其中出现的 {artifact_task_dir} 会替换成该项自己的隔离目录
    # env  : 只对这一项生效的环境变量（值里的 {artifact_task_dir} 同样替换），
    #        用来把「读哪个构建产物」显式传给脚本，而不是让脚本猜 dist/ 里有没有包
    ITEMS[key] = {
        "id": key,
        "cmd": cmd,
        "group": group,
        "covers": covers,
        "checks": checks,
        "requires": list(requires),
        "note": note,
        "manual": manual,
        "prep": [list(step) for step in prep],
        "env": dict(env or {}),
    }


_item("core-tests",
      ["swift", "run", "--package-path", "replica", "blinkclip-core-tests"],
      "core",
      "Tests/BlinkClipCoreTests/**（编译整个 BlinkClipCore 目标）",
      "剪贴板 Store/持久化/集合/搜索等核心单元断言")

_item("python-static",
      [sys.executable, "-m", "unittest", "discover", "-s", "scripts/tests"],
      "static",
      "scripts/tests/*.py；读 Sources/BlinkClipCore/PasteboardItem.swift、"
      "Sources/BlinkClip/AppMain.swift、Sources/BlinkClip/UI/ReplicaUIController.swift、"
      "scripts/sync-release-downloads.py、README.md、README.en.md、website/index.html、website/i18n.js、"
      ".github/workflows/*.yml",
      "P0 修复源码门（粘贴归档键、焦点回落）、发布下载链接同步与站点渲染、工作流顺序")

# --- 原生 harness 脚本（replica/scripts/test-*.sh） -------------------------------------
_SHELL_ITEMS = [
    ("accessibility-modal", "权限引导弹窗",
     "UI/AccessibilityModals.swift、UI/AccessibilityRequestAction.swift、UI/ReplicaBrand.swift",
     "弹窗文案与动作绑定"),
    ("app-updates", "应用内更新与关于页",
     "UI/ 全量、BackgroundService.swift、GlobalHotKey.swift、ICloudDriveSyncController.swift、"
     "PanelShortcutMenu.swift、SourceAppColor.swift、WindowSharingPolicy.swift、BlinkClipCore",
     "版本比较、appcast 解析、关于页几何/文案、限流"),
    ("appearance-preferences", "外观偏好观察",
     "UI/WindowAppearancePreferenceObservation.swift、UI/ReplicaUIController.swift（语法解析）",
     "浅深外观切换的通知与映射"),
    ("blinkclip-legacy-migration", "旧版数据迁移",
     "Tests/Native/BlinkClipLegacyMigrationHarness.swift",
     "旧版 fixture 迁移后的键与文件", ("BLINKCLIP_LEGACY_FIXTURE",)),
    ("blinkclip-owned-resources", "自有资源白名单",
     "BlinkClipCore 资源与本地化表、Core/AppBrand、SettingsStrings、ResourceBundle、SettingsLocalization、"
     "SearchLocalization、PreviewLocalization、UnavailablePreviewLocalization、ShortcutMessages、"
     "BlinkClipAssetRenderer、SettingsIllustrations、Package.swift、scripts/build-app.sh、"
     "Assets/capcap-LICENSE.txt、LICENSE、NOTICE.md",
     "五语本地化表、生成插图、图标、打包资源白名单"),
    ("capture-chrome-exclusion", "截图框选 chrome 源码门",
     "Vendor/capcap/Capture/SelectionView.swift、Capture/OverlayWindowController.swift、"
     "Capture/（整目录编译 BlinkClipCapture）、Editor/EditWindowController.swift、DESIGN.md",
     "尺寸标签乘号/间距、十字辅线图层化、边框 1pt、手柄形态、自绘十字光标"),
    ("capture-integration", "截图入口胶水 + toast",
     "Screenshot/ScreenshotCoordinator.swift、Screenshot/ScreenshotWindowHider.swift、"
     "Screenshot/ScreenshotHistoryBridge.swift、UI/ReplicaToast.swift、UI/ReplicaToastCopy.swift、"
     "UI/ReplicaCopiedOSD.swift、UI/ScreenshotSettingsCopy.swift、"
     "Vendor/capcap/Adapters/{ScreenshotSettings,CaptureEntry,HistoryManagerBridge}.swift",
     "遮罩/编辑器入口、历史桥、四条 toast 同一组件、暂停/复制文案、独立 Store"),
    ("card-source-icon", "卡片来源图标",
     "UI/ 全量、UI/CardSourceIconPresentation.swift、UI/PanelViews.swift",
     "来源图标与配色、离屏截图"),
    ("cloudkit-live", "真实 CloudKit 探针",
     "Tests/Native/LiveCloudKitSyncHarness.swift",
     "真实容器读写（非离屏），默认不出现在日常选择里",
     ("BLINKCLIP_CLOUDKIT_PROFILE", "BLINKCLIP_CLOUDKIT_CONTAINER",
      "BLINKCLIP_SIGNING_IDENTITY", "BLINKCLIP_CLOUDKIT_TEST_BUNDLE_ID")),
    ("cloudkit-sync", "CloudKit 契约",
     "Tests/Native/CloudKitSyncHarness.swift、Tests/Native/LiveCloudKitSyncHarness.swift（编译门）、BlinkClipCore",
     "记录/作用域映射、journal 重放契约"),
    ("copy-restore", "复制/粘贴还原",
     "UI/ 全量、PanelShortcutMenu.swift、ICloudDriveSyncController.swift、SourceAppColor.swift、"
     "WindowSharingPolicy.swift、BackgroundService.swift、BlinkClipCore（含 SoundEffects）",
     "面板/聚合复制、栈粘贴、声音分类、暂停期不写剪贴板"),
    ("editor-chrome-parity", "编辑器与框选 chrome 一致",
     "整个 BlinkClipCapture 模块（Vendor/capcap/**）",
     "位图强调色集合一致、1pt 边框、角标几何、22×22 命中区"),
    ("feedback-shortcuts", "快捷键反馈",
     "BlinkClipCore/SoundEffects.swift、Vendor/capcap/Editor/EditorShortcutRegistry.swift、"
     "Editor/EditorCommandDoubleTap.swift、Vendor/capcap/Adapters/HotkeyManagerStub.swift",
     "反馈声音分类与编辑器快捷键注册/双击命令"),
    ("history-retention", "历史保留期限",
     "UI/HistoryRetentionSaving.swift、UI/HistoryRetentionCopy.swift、UI/HistoryCapacityControl.swift、"
     "UI/AuxiliaryViews.swift、BlinkClipCore/SettingsStrings.swift、Assets/BlinkClipAppIcon.icns",
     "期限/容量设置生效与文案"),
    ("hotkey", "全局热键",
     "Sources/BlinkClip/GlobalHotKey.swift、Tests/HotKey/HotKeyHarness.swift",
     "注册/注销与触发（进程内合成事件）"),
    ("icloud-drive-controller", "iCloud Drive 控制器",
     "ICloudDriveSyncController.swift、UI/ReplicaBrand.swift",
     "状态机与错误文案"),
    ("icloud-noop-performance", "iCloud 空转性能",
     "BlinkClipCore（release 全量构建）、BlinkClipCore/ICloudDriveSync.swift",
     "无操作路径不产生多余写入/唤醒"),
    ("icloud-sync", "iCloud 同步",
     "Tests/Native/ICloudDriveSyncHarness.swift、BlinkClipCore",
     "同步状态与写入路径（--live-icloud 走真实目录）"),
    ("identifier-namespace-migration", "标识符命名空间迁移",
     "Vendor/capcap/Capture/ClipboardHistorySkipMarker.swift、"
     "Vendor/capcap/Utilities/BlinkClipIdentifierMigration.swift",
     "pasteboard skip marker 与 UserDefaults 键迁移"),
    ("overlay-opt", "覆盖层开销三项下调",
     "Vendor/capcap/Capture/OverlayWindowController.swift、Capture/SelectionView.swift、"
     "Capture/WindowDetector.swift、Vendor/capcap/UI/MagnifierLensPanelWindow.swift、"
     "Tests/Native/OverlayOptHarness.swift、DESIGN.md",
     "2Hz 枚举 + 静止暂停 + 未命中补采、20Hz 放大镜由自己的时钟驱动、事件路径零请求、pid 缓存，"
     "以及放大镜坐标/色值/缓存 chrome 的实测断言"),
    ("packaged-resources", "打包资源布局",
     "BlinkClipCore bundle（app Contents/Resources 布局）、Tests/Native/PackagedResourcesHarness.swift",
     "从打包位置解析本地化与音频资源"),
    ("panel-hotkey", "面板期热键",
     "GlobalHotKey.swift、GlobalHotKeyRouting.swift、Screenshot/ScreenshotWindowHider.swift",
     "面板可见期间热键路由与窗口隐藏"),
    ("panel-menu", "快捷菜单结构",
     "PanelShortcutMenu.swift、UI/PanelViews.swift、AppMain.swift",
     "状态栏/面板两变体菜单结构、暂停子菜单、退出二次确认"),
    ("panel-permission-interaction", "权限面板交互",
     "Sources/、Vendor/、Assets/ 全量（build-app.sh 全量构建）、AppMain.swift、BackgroundService.swift、"
     "ICloudDriveSyncController.swift、PanelShortcutMenu.swift、SourceAppColor.swift、WindowSharingPolicy.swift",
     "构建前后输入集不变、Bundle ID/版本/架构/签名、权限面板交互"),
    ("panel-scroll", "面板滚动",
     "UI/ 全量、PanelShortcutMenu.swift、BackgroundService.swift、WindowSharingPolicy.swift",
     "滚动位置与选中项跟随"),
    ("panel-top-corners", "面板顶角玻璃背景",
     "UI/PanelViews.swift、UI/ReplicaPanelGlassBackground.swift、"
     "Sources/BlinkClipObjC/PRPanelGlassBackground.m、include/",
     "圆角/边框像素与 PanelViews 语法门"),
    ("pasteboard-write-feedback", "写剪贴板反馈",
     "BlinkClipCore（含 SoundEffects）、Tests/Native/PasteboardWriteFeedbackHarness.swift",
     "写剪贴板时的反馈分类与剪贴板内容"),
    ("permission-status", "权限状态",
     "BlinkClipCore/AccessibilityService.swift、PermissionPromptPolicy.swift、"
     "PermissionStatusSnapshot.swift、SettingsStrings.swift、UI/PermissionStatusView.swift、"
     "UI/PermissionStatusProbe.swift、UI/AccessibilityRequestAction.swift、UI/SettingsSurfaceStyle.swift、"
     "UI/SettingsWindowFocusRestore.swift、AppMain.swift",
     "权限快照、提示策略、三语文案、返回焦点"),
    ("quick-paste", "快捷粘贴置顶",
     "UI/ 全量、PanelShortcutMenu.swift、BackgroundService.swift、GlobalHotKey.swift、"
     "ICloudDriveSyncController.swift、SourceAppColor.swift、WindowSharingPolicy.swift、"
     "BlinkClipCore（含 Pasteboard 生成标记）、Tests/Native/QuickPasteHarness.swift",
     "四条粘贴路径置顶一致（双击/⌘1–9/右键/Stack）、粘贴不新增历史条目"),
    ("retention-save-performance", "保留期限保存性能",
     "BlinkClipCore/CloudKitGraph.swift、ClipboardStore.swift、ClipboardPersistence.swift、"
     "PinboardAttributes.swift、UI/HistoryRetentionSaving.swift、UI/AuxiliaryViews.swift",
     "1024 条 8MiB 数据集下的保存耗时与源码结构门"),
    ("screenshot-window-hider", "截图时隐藏窗口",
     "Screenshot/ScreenshotWindowHider.swift",
     "截图期间本窗口隐藏与恢复"),
    ("search-button", "搜索按钮",
     "UI/ 全量、PanelShortcutMenu.swift、BackgroundService.swift",
     "搜索入口状态与离屏渲染"),
    ("settings-architecture", "设置页架构",
     "UI/ 全量、SettingsSplitView.swift、SettingsCopy.swift、SettingsSurfaceStyle.swift、"
     "ReplicaUIController.swift、AuxiliaryViews.swift、各设置页控制器、快捷行恢复",
     "七个设置页结构、控件与焦点、快捷行恢复"),
    ("settings-localization", "设置文案本地化",
     "BlinkClipCore/SettingsStrings.swift、SettingsLocalization.swift、ResourceBundle.swift、AppBrand.swift、"
     "Pasteboard.swift、UI/ 文案提供者（ReplicaUIController、SettingsCopy、ScreenshotSettingsCopy、"
     "ReplicaToastCopy、ShortcutRecorder、AuxiliaryViews）、AppMain.swift",
     "三语解析一致性与设置文案表"),
    ("settings-shortcut-reset", "快捷键重置",
     "UI/SettingsShortcutReset.swift、UI/SettingsCopy.swift",
     "重置恢复到默认快捷键并刷新文案"),
    ("settings-window-focus", "设置窗口焦点恢复",
     "UI/SettingsWindowFocusRestore.swift、UI/ReplicaUIController.swift、UI/PermissionStatusView.swift、"
     "UI/AccessibilityRequestAction.swift",
     "关闭设置后焦点回到原 App；权限动作前记录返回目标"),
    ("shortcut-model", "快捷键模型",
     "Tests/HotKey/ShortcutModelHarness.swift、BlinkClipCore 快捷键类型",
     "键码/修饰键编解码与显示"),
    ("shortcut-row-restore", "快捷键行恢复",
     "UI/SettingsShortcutRowRestore.swift、UI/SettingsCopy.swift、UI/ScreenshotSettingsCopy.swift",
     "快捷键行在重建后恢复录制/展示状态"),
    ("sound-effects", "声音反馈",
     "BlinkClipCore/SoundEffects.swift、AppMain.swift（调用点源码门）",
     "反馈分类映射（copy/paste/capture）与 Stack 粘贴包装"),
    ("sparkle-startup", "Sparkle 启动",
     "UI/BlinkClipInAppUpdater.swift、Assets/UpdatePublicKey.txt",
     "启动时 updater 配置与公钥"),
    ("text-card-appearance", "文本卡外观对比度",
     "UI/ 全量、BackgroundService.swift",
     "四态外观对比度 ≥ 4.5:1、footer 配色"),
    ("toolbar-upload-removal", "工具栏上传项移除",
     "Vendor/capcap/Editor/ToolbarLayout.swift、ToolbarButtons.swift、ToolbarChrome.swift、"
     "ToolbarGroupMenu.swift、EditWindowController.swift、EditorShortcutRegistry.swift、"
     "Vendor/capcap/UI/AdaptiveChrome.swift、Vendor/capcap/Resources/*.lproj/Localizable.strings",
     "工具栏不含上传、几何来自生产代码、文案键齐全"),
    ("translation-integration", "翻译/OCR 桥",
     "Vendor/capcap/Translation/**、Vendor/capcap/Resources/en.lproj、zh-Hans.lproj",
     "翻译方向解析与 OCR 服务接线"),
    ("ui-interaction", "面板交互",
     "UI/ 全量、PanelShortcutMenu.swift、BackgroundService.swift、GlobalHotKey.swift、"
     "ICloudDriveSyncController.swift、SourceAppColor.swift、WindowSharingPolicy.swift",
     "选中/拖动/堆叠/删除列表后的选中夹取等交互"),
    ("window-policy", "窗口共享策略",
     "Sources/BlinkClip/WindowSharingPolicy.swift",
     "截图/录屏时窗口不参与共享"),
]

for key, label, covers, checks, *rest in _SHELL_ITEMS:
    _item(key, ["bash", "replica/scripts/test-%s.sh" % key], "native", covers, checks,
          rest[0] if rest else ())

# 两项「随包产物门」要读真实 app bundle：sound-effects 断言两份音效落在 Core bundle 里，
# toolbar-upload-removal 用随包 .lproj 渲染工具栏。和 app-monitor 一样，先构建，再把
# BLINKCLIP_APP_PATH 指向本次产物；不再读 replica/dist 里的旧包（那份包可能是上一版的，
# 也可能只剩一个目录名）。
for _key in ("sound-effects", "toolbar-upload-removal"):
    ITEMS[_key]["prep"] = [["bash", "replica/scripts/build-app.sh", "release", "native"]]
    ITEMS[_key]["env"]["BLINKCLIP_APP_PATH"] = "{artifact_task_dir}/out/BlinkClip.app"
    ITEMS[_key]["note"] = "前置命令先构建 app；BLINKCLIP_APP_PATH 指向本次构建产物，不再读 replica/dist 里的旧包"

# 真实 CloudKit 探针也必须显式声明「只写合成数据」，否则脚本按用法错误退出 2。
ITEMS["cloudkit-live"]["cmd"] += ["--synthetic-only"]

# 旧版迁移需要一份审计过的真实旧版数据目录，仓库里没有可提交的等价夹具：
# 显式降级为手工项（docs/TESTING.md「手工项」一节写了怎么跑），缺变量时不算失败。
ITEMS["blinkclip-legacy-migration"]["manual"] = (
    "需要真实旧版数据目录（BLINKCLIP_LEGACY_FIXTURE）；仓库不提交该夹具，故不在自动门禁里")

# 真实 CloudKit 探针要自有容器 + 本机 Apple 签名身份（docs/CLOUDKIT_SETUP.md）。没有一整套
# 凭据时按手工项处理；配齐环境变量后照常执行（--synthetic-only 只写合成内容）。
ITEMS["cloudkit-live"]["manual"] = (
    "需要 BLINKCLIP_CLOUDKIT_* + 本机签名身份（docs/CLOUDKIT_SETUP.md）；未配置时按手工项")

# 权限面板交互的 QA 进程按设计不自己退出：它轮询 `finish` 文件，由协调者（CUA）点完再收尾。
# 没有协调者时脚本会一直 wait（曾把 --full 卡住 9 分钟），因此默认按手工项处理；
# 设 BLINKCLIP_QA_COORDINATOR=1 时照常执行。
ITEMS["panel-permission-interaction"]["requires"] = ["BLINKCLIP_QA_COORDINATOR"]
ITEMS["panel-permission-interaction"]["manual"] = (
    "需要 GUI 协调（真实点击/权限面板；协作者写 finish 收尾，CUA 证据单独记录）")

# --- Python 测试 ----------------------------------------------------------------
_item("app-monitor",
      [sys.executable, "replica/scripts/test-app-monitor.py",
       "--app", "{artifact_task_dir}/out/BlinkClip.app"],
      "python",
      "本项刚构建的 BlinkClip.app（build-app.sh release native）、scripts/build-store-reader.sh、"
      "Tests/Native/StoreReadHarness.swift",
      "定时监控在私有 pasteboard 上写入",
      note="前置命令先构建 app；--app 指向本次构建产物，不再读 replica/dist 里的旧包",
      prep=[["bash", "replica/scripts/build-app.sh", "release", "native"]])
_item("distribution-signing", [sys.executable, "replica/scripts/test-distribution-signing.py"], "python",
      "replica/scripts/sign-app.py、replica/scripts/notarize-distribution.py",
      "嵌套签名顺序、公证失败关闭")
_item("helper-lifecycle", [sys.executable, "replica/scripts/test-helper-lifecycle.py"], "python",
      "Sources/BlinkClipHelper/HelperMain.swift（真实 helper 二进制以一次性身份启动）",
      "工作区创建、重启与退出")
_MCP_PREP = r"""set -euo pipefail
replica_root="$PWD/replica"
source "$replica_root/Tests/Native/build-support.sh"
export BLINKCLIP_TEST_CONFIGURATION=debug
prepare_native_test_core
test_root="$ARTIFACT_TASK_DIR/build/fixture"
compile_native_test_harness mcp-store-fixture "$replica_root/scripts/MCPStoreFixture.swift"
bin="$(swift build --package-path "$replica_root" --scratch-path "$ARTIFACT_TASK_DIR/build/swiftpm" \
  -c debug --show-bin-path)"
swift build --package-path "$replica_root" --scratch-path "$ARTIFACT_TASK_DIR/build/swiftpm" \
  -c debug --product blinkclip-mcp >/dev/null
printf '%s\n' "$bin" > "$ARTIFACT_TASK_DIR/build/mcp-bin-path"
"""

_item("mcp",
      ["bash", "-c",
       'set -euo pipefail\n'
       'bin="$(cat "$ARTIFACT_TASK_DIR/build/mcp-bin-path")"\n'
       'exec python3 replica/scripts/test-mcp.py --binary "$bin/blinkclip-mcp" '
       '--fixture "$ARTIFACT_TASK_DIR/build/fixture/mcp-store-fixture.app/Contents/MacOS/harness"'],
      "python",
      "Sources/BlinkClipMCP/**、replica/scripts/MCPStoreFixture.swift（链接 BlinkClipCore）",
      "MCP stdio 初始化、工具调用、私有 pasteboard 读写",
      note="前置：编译 blinkclip-mcp 与 MCPStoreFixture（均隔离目录内），再显式传 --binary/--fixture",
      prep=[["bash", "-c", _MCP_PREP]])
_item("cloudkit-signing", [sys.executable, "replica/Tests/Native/test_cloudkit_signing.py"],
      "python",
      "replica/scripts/configure-cloudkit-signing.py",
      "描述文件→签名授权的收窄规则、通配符拒绝、过期/团队校验",
      note="脚本位于 Tests/Native/，按 docs/CLOUDKIT_SETUP.md 手工执行")

_item("release-changelog", [sys.executable, "replica/scripts/test-release-changelog.py"], "python",
      "replica/scripts/release-ci.py、CHANGELOG.md 解析",
      "标题分隔符兼容、版本段落边界")
_item("release-packaging", [sys.executable, "replica/scripts/test-release-packaging.py"], "python",
      "replica/scripts/release-ci.py、replica/scripts/build-app.sh、"
      "replica/Assets/UpdatePublicKey.txt、package.json",
      "一 DMG 两架构、产物命名与资源布局")
_item("release-plan", [sys.executable, "replica/scripts/test-release-plan.py"], "python",
      "replica/scripts/release-plan.py、package.json、.github/workflows/**",
      "版本差量、强制推送兜底、发布门")
_item("update-feed", [sys.executable, "replica/scripts/test-update-feed.py"], "python",
      "replica/scripts/create-update-feed.py、replica/scripts/prepare-sparkle-tools.sh",
      "签名 appcast 契约（不联网）")
_item("check-website", [sys.executable, "scripts/check-website.py"], "site",
      "website/**（HTML/CSS/JS、下载链接、i18n 资源）",
      "静态站点结构、锚点、下载链接与版本属性",
      note="不在 validate.sh / regress-local.sh 登记，独立存在")
_item("website-i18n", ["node", "scripts/test-website-i18n.cjs"], "site",
      "website/index.html、website/i18n.js、website/site.js",
      "站点双语切换与 DOM 夹具断言",
      note="需要 node；不在 validate.sh / regress-local.sh 登记")

ALL_IDS = tuple(ITEMS)


# --------------------------------------------------------------------------------------
# 分组常量：让规则表短而可读
# --------------------------------------------------------------------------------------
NATIVE_ALL = tuple(k for k, v in ITEMS.items() if v["group"] == "native")

# 会编译 Sources/BlinkClip/UI/**.swift（或其中大部分）的测试
UI_COMPILE = ("app-updates", "appearance-preferences", "capture-integration", "card-source-icon",
              "copy-restore", "panel-permission-interaction", "panel-scroll", "panel-top-corners",
              "quick-paste", "search-button", "settings-architecture", "settings-localization",
              "settings-shortcut-reset", "settings-window-focus", "shortcut-row-restore",
              "text-card-appearance", "ui-interaction")

# 会链接/编译 BlinkClipCore 的测试（core 层改动的保守面）
CORE_LINKED = ("core-tests", "app-monitor", "app-updates", "capture-integration", "cloudkit-sync",
               "copy-restore", "history-retention", "icloud-drive-controller",
               "icloud-noop-performance", "icloud-sync", "mcp", "packaged-resources",
               "pasteboard-write-feedback", "permission-status", "retention-save-performance",
               "settings-localization", "settings-window-focus", "sound-effects",
               "shortcut-model", "ui-interaction", "window-policy", "blinkclip-owned-resources")

# Vendor/capcap（BlinkClipCapture 模块）改动的保守面
VENDOR_CAPTURE = ("capture-chrome-exclusion", "capture-integration", "editor-chrome-parity",
                  "feedback-shortcuts", "toolbar-upload-removal", "translation-integration")

# 会跑 build-app.sh（整包构建）的测试
BUILD_APP = ("packaged-resources", "panel-permission-interaction", "blinkclip-owned-resources",
             "release-packaging", "app-monitor", "helper-lifecycle")


# --------------------------------------------------------------------------------------
# 规则表：文件 glob → 测试项
#   id      : 规则名（输出里会显示，也是维护锚点）
#   globs   : 路径模式（`*` 不跨目录，`**` 跨目录）
#   tests   : 选中的测试项；kind="docs" 时为空表示「无测试项」
#   why     : 为什么这些测试受影响（映射维护时按这句复核）
#   kind    : tests（默认）/ docs（纯文档，不算漏覆盖）/ ignore（不触发任何事）
#   dynamic : harness / test-script / builder —— 由脚本内容现算
# 顺序即优先级：具体文件在前，目录在后，兜底最后。
# --------------------------------------------------------------------------------------
RULES = [
    # ============ 0. 忽略：不参与选择 ============
    dict(id="ignore-local", globs=[".gitignore", "**/.DS_Store", ".local/**", "**/.build/**",
                                   "replica/dist/**", "**/*.log", "**/__pycache__/**"],
         tests=(), why="本地/构建产物，不进选择", kind="ignore"),

    # ============ 1. 测试自身 ============
    dict(id="native-build-support", globs=["replica/Tests/Native/build-support.sh"],
         tests=NATIVE_ALL,
         why="所有原生 harness 的编译/运行辅助被全部 test-*.sh 引用；改它必须跑全部原生脚本"),
    dict(id="native-harness", globs=["replica/Tests/Native/*.swift"], dynamic="harness",
         tests=(),
         why="改某个 harness 时，选中引用它的 test-*.sh（引用不到则回退全量）"),
    dict(id="hotkey-harness", globs=["replica/Tests/HotKey/HotKeyHarness.swift"], tests=("hotkey",),
         why="test-hotkey.sh 只编译 GlobalHotKey.swift + 该 harness"),
    dict(id="shortcut-model-harness", globs=["replica/Tests/HotKey/ShortcutModelHarness.swift"],
         tests=("shortcut-model",), why="test-shortcut-model.sh 只编译该 harness"),
    dict(id="core-unit-tests", globs=["replica/Tests/BlinkClipCoreTests/**"], tests=("core-tests",),
         why="core 单测自身改动只影响 blinkclip-core-tests"),
    dict(id="selector-self", globs=["replica/scripts/test-affected.py"], tests=(),
         why="选择器自身改动用「五场景 --dry-run」冒烟验收，不进入测试选择",
         kind="docs"),
    dict(id="test-script-self", globs=["replica/scripts/test-*.sh", "replica/scripts/test-*.py"],
         dynamic="test-script", tests=(),
         why="改测试脚本时把该测试自身加进选择清单"),
    dict(id="store-reader", globs=["replica/scripts/build-store-reader.sh",
                                   "replica/scripts/MCPStoreFixture.swift"],
         tests=("app-monitor", "mcp"),
         why="两者分别是 app-monitor 与 test-mcp.py 的辅助可执行"),
    dict(id="prepare-sparkle-tools", globs=["replica/scripts/prepare-sparkle-tools.sh"],
         tests=("update-feed",), why="test-update-feed.py 通过它取 Sparkle 工具链"),
    dict(id="build-app", globs=["replica/scripts/build-app.sh"], tests=BUILD_APP,
         why="整包构建脚本被这些测试实际调用；产物布局/架构/资源由它们断言"),
    dict(id="release-ci", globs=["replica/scripts/release-ci.py"],
         tests=("release-changelog", "release-packaging"),
         why="两个发布测试都 import release-ci.py"),
    dict(id="release-plan-script", globs=["replica/scripts/release-plan.py"], tests=("release-plan",),
         why="test-release-plan.py 直接 import 它"),
    dict(id="release-python-other",
         globs=["replica/scripts/create-update-feed.py", "replica/scripts/sign-app.py",
                "replica/scripts/notarize-distribution.py",
                "replica/scripts/configure-cloudkit-signing.py"],
         tests=("update-feed", "distribution-signing", "cloudkit-live"),
         why="发布/签名/公证脚本的测试与云签名探针"),
    dict(id="release-shell-other",
         globs=["replica/scripts/build-dmg.sh", "replica/scripts/build-notarized.sh",
                "replica/scripts/release-plan.py", "replica/scripts/build-icon.swift",
                "replica/scripts/prepare-appintents-constants.py",
                "replica/scripts/compare-empty-state.swift", "replica/scripts/build-store-reader.sh"],
         tests=("release-packaging", "distribution-signing", "packaged-resources"),
         why="发布/打包链路脚本，由发布契约测试覆盖"),
    dict(id="release-python-tests",
         globs=["replica/scripts/test-release-*.py", "replica/scripts/test-update-feed.py",
                "replica/scripts/test-distribution-signing.py"],
         dynamic="test-script", tests=(), why="发布测试脚本自身改动"),
    dict(id="validate-suite", globs=["replica/scripts/validate.sh"],
         tests=("core-tests", "python-static", "hotkey", "shortcut-model", "window-policy",
                "ui-interaction", "panel-menu", "helper-lifecycle", "app-monitor"),
         why="validate.sh 就按这个顺序跑这些项（外加 build-app + source-fingerprint）"),
    dict(id="regress-suite", globs=["replica/scripts/regress-local.sh"],
         tests=("core-tests", "hotkey", "panel-hotkey", "panel-menu", "shortcut-model",
                "window-policy", "ui-interaction", "copy-restore", "accessibility-modal",
                "packaged-resources", "app-updates", "sparkle-startup", "icloud-sync",
                "icloud-drive-controller", "cloudkit-sync", "app-monitor", "helper-lifecycle"),
         why="regress-local.sh 正是跑这 17 个 suite，改它就要重跑同一批"),
    dict(id="verify-update-signature",
         globs=["replica/scripts/verify-update-signature.swift"],
         tests=("update-feed",),
         why="create-update-feed.py 调用它签名，test-update-feed.py 断言该调用"),
    dict(id="cloudkit-signing-config",
         globs=["replica/scripts/configure-cloudkit-signing.py"],
         tests=("cloudkit-signing", "cloudkit-live"),
         why="该脚本是 cloudkit-signing 的被测对象，真实探针也走同一入口"),
    dict(id="cloudkit-signing-test",
         globs=["replica/Tests/Native/test_cloudkit_signing.py"], tests=("cloudkit-signing",),
         why="签名测试脚本自身"),
    dict(id="store-read-harness", globs=["replica/Tests/Native/StoreReadHarness.swift"],
         tests=("app-monitor",),
         why="build-store-reader.sh 编译该 harness，app-monitor 用它读 Store"),
    dict(id="source-fingerprint", globs=["replica/scripts/source-fingerprint.py"],
         tests=("packaged-resources", "release-packaging", "panel-permission-interaction"),
         why="validate.sh/构建用它核对产物出自当前源码"),
    dict(id="scripts-tests", globs=["scripts/tests/**"], tests=("python-static",),
         why="python3 -m unittest discover -s scripts/tests"),
    dict(id="scripts-static", globs=["scripts/sync-release-downloads.py"], tests=("python-static",),
         why="test_sync_release_downloads.py import 它并渲染 README/website"),
    dict(id="scripts-website", globs=["scripts/check-website.py"], tests=("check-website",),
         why="站点检查脚本自身"),
    dict(id="scripts-website-i18n", globs=["scripts/test-website-i18n.cjs"], tests=("website-i18n",),
         why="站点 i18n 测试自身"),

    # ============ 2. 文档 / 元数据 ============
    dict(id="design-doc", globs=["DESIGN.md"],
         tests=("capture-chrome-exclusion", "overlay-opt"),
         why="test-capture-chrome-exclusion.sh 的 SEL 源码门直接读 DESIGN.md 的设计口径；"
             "test-overlay-opt.sh 的口径门读 DESIGN.md 的 OPT 三条改法"),
    dict(id="notice-license", globs=["NOTICE.md", "LICENSE", "replica/Vendor/capcap/LICENSE"],
         tests=("blinkclip-owned-resources",),
         why="自有资源测试断言 NOTICE/LICENSE 被打进 app 且与仓库一致"),
    dict(id="changelog", globs=["CHANGELOG.md"], tests=("release-changelog",),
         why="release-ci.py 从 CHANGELOG.md 取版本段落，发布测试守着解析规则"),
    dict(id="readme-roots", globs=["README.md", "README.en.md"],
         tests=("python-static", "check-website"),
         why="发布下载同步要重写这两个 README，站点检查读其中的下载链接"),
    dict(id="docs-only", globs=["docs/**", "*.md", "replica/*.md", "branding/**/*.md",
                                "website/**/*.md"],
         tests=(), why="纯文档改动没有测试覆盖，明确跳过而不是回退全量", kind="docs"),
    dict(id="meta-only", globs=[".github/**/*.md", ".gitattributes", ".editorconfig"],
         tests=(), why="仓库元数据，无行为影响", kind="docs"),

    # ============ 3. BlinkClip 应用层（Sources/BlinkClip） ============
    dict(id="appmain", globs=["replica/Sources/BlinkClip/AppMain.swift"],
         tests=("sound-effects", "panel-menu", "panel-permission-interaction",
                "permission-status", "settings-architecture", "settings-localization"),
         why="这些测试直接编译 AppMain.swift 或对其调用点做源码门（Stack 粘贴的 SoundEffects 包装）"),
    dict(id="global-hotkey", globs=["replica/Sources/BlinkClip/GlobalHotKey.swift"],
         tests=("hotkey", "panel-hotkey", "app-updates", "ui-interaction", "quick-paste"),
         why="热键注册/路由的直接测试，且这几个测试显式编译 GlobalHotKey.swift"),
    dict(id="global-hotkey-routing", globs=["replica/Sources/BlinkClip/GlobalHotKeyRouting.swift"],
         tests=("panel-hotkey", "hotkey", "ui-interaction"),
         why="test-panel-hotkey.sh 编译它，热键路由变化影响面板期行为"),
    dict(id="screenshot-window-hider", globs=["replica/Sources/BlinkClip/Screenshot/ScreenshotWindowHider.swift"],
         tests=("screenshot-window-hider", "panel-hotkey", "capture-integration"),
         why="专门的窗口隐藏测试 + 面板热键与截图胶水都编译该文件"),
    dict(id="screenshot-coordinator",
         globs=["replica/Sources/BlinkClip/Screenshot/ScreenshotCoordinator.swift",
                "replica/Sources/BlinkClip/Screenshot/ScreenshotHistoryBridge.swift"],
         tests=("capture-integration",),
         why="截图入口/历史桥的端到端胶水测试逐条断言接线"),
    dict(id="screenshot-focus",
         globs=["replica/Sources/BlinkClip/Screenshot/ScreenshotFocusRestorer.swift"],
         tests=("capture-integration", "screenshot-window-hider"),
         why="截图后焦点恢复属于截图会话，两个测试都覆盖截图生命周期"),
    dict(id="screenshot-generic", globs=["replica/Sources/BlinkClip/Screenshot/**"],
         tests=("capture-integration", "screenshot-window-hider"),
         why="Screenshot/ 其余文件均参与截图会话，由胶水与窗口隐藏测试覆盖"),
    dict(id="icloud-drive-controller",
         globs=["replica/Sources/BlinkClip/ICloudDriveSyncController.swift"],
         tests=("icloud-drive-controller", "icloud-sync", "app-updates", "copy-restore",
                "panel-permission-interaction", "panel-scroll", "quick-paste", "search-button",
                "settings-architecture", "text-card-appearance", "ui-interaction",
                "card-source-icon"),
         why="专属控制器测试 + 所有把该文件编进 harness 的 UI 测试"),
    dict(id="background-service", globs=["replica/Sources/BlinkClip/BackgroundService.swift"],
         tests=("app-updates", "app-monitor", "copy-restore", "panel-scroll", "quick-paste",
                "search-button", "settings-architecture", "text-card-appearance", "ui-interaction",
                "card-source-icon", "panel-permission-interaction"),
         why="后台服务被这些 harness 编译，app-monitor 直接跑真实进程"),
    dict(id="panel-shortcut-menu", globs=["replica/Sources/BlinkClip/PanelShortcutMenu.swift"],
         tests=("panel-menu", "app-updates", "copy-restore", "panel-scroll", "quick-paste",
                "search-button", "settings-architecture", "text-card-appearance", "ui-interaction",
                "card-source-icon", "panel-permission-interaction"),
         why="快捷菜单模型自身 + 全部编译该文件的 UI 测试"),
    dict(id="source-app-color", globs=["replica/Sources/BlinkClip/SourceAppColor.swift"],
         tests=("card-source-icon", "app-updates", "copy-restore", "panel-scroll", "quick-paste",
                "search-button", "settings-architecture", "text-card-appearance", "ui-interaction",
                "panel-permission-interaction"),
         why="来源配色被卡片图标测试断言，且被这些 UI harness 编译"),
    dict(id="window-sharing-policy", globs=["replica/Sources/BlinkClip/WindowSharingPolicy.swift"],
         tests=("window-policy", "app-updates", "copy-restore", "panel-scroll", "quick-paste",
                "search-button", "settings-architecture", "text-card-appearance", "ui-interaction",
                "card-source-icon", "panel-permission-interaction"),
         why="专门策略测试 + 编译该文件的 UI harness"),
    dict(id="app-intents", globs=["replica/Sources/BlinkClip/AppIntents/**"],
         tests=("packaged-resources", "release-packaging", "panel-permission-interaction"),
         why="AppIntents 影响整包构建产物与 Info.plist/常量，由打包类测试覆盖"),

    # --- UI/ 精确文件规则（先于 UI/** 兜底） ---
    dict(id="ui-toast", globs=["replica/Sources/BlinkClip/UI/ReplicaToast.swift",
                               "replica/Sources/BlinkClip/UI/ReplicaCopiedOSD.swift"],
         tests=("capture-integration", "ui-interaction"),
         why="test-capture-integration.sh 直接编译并逐条断言 toast（窗口类唯一、文案、时长、"
             "不参与共享）；ui-interaction 编译 UI/ 全量作编译门"),
    dict(id="ui-toast-copy", globs=["replica/Sources/BlinkClip/UI/ReplicaToastCopy.swift"],
         tests=("capture-integration", "settings-localization", "ui-interaction"),
         why="toast 文案表被 capture-integration 与设置本地化测试分别断言"),
    dict(id="ui-panelviews", globs=["replica/Sources/BlinkClip/UI/PanelViews.swift"],
         tests=("panel-menu", "card-source-icon", "panel-top-corners", "quick-paste",
                "ui-interaction"),
         why="面板视图被菜单结构、卡片图标、顶角几何与交互测试分别编译/断言；"
             "quick-paste 按 UI/ 全量编译并断言双击/右键粘贴入口"),
    dict(id="ui-panel-glass", globs=["replica/Sources/BlinkClip/UI/ReplicaPanelGlassBackground.swift"],
         tests=("panel-top-corners", "ui-interaction"),
         why="顶角玻璃绘制与面板 :: 由 panel-top-corners 专门断言"),
    dict(id="ui-card-source-icon", globs=["replica/Sources/BlinkClip/UI/CardSourceIconPresentation.swift"],
         tests=("card-source-icon", "ui-interaction"),
         why="来源图标呈现是 card-source-icon 的断言对象"),
    dict(id="ui-permission", globs=["replica/Sources/BlinkClip/UI/PermissionStatusView.swift",
                                    "replica/Sources/BlinkClip/UI/PermissionStatusProbe.swift"],
         tests=("permission-status", "settings-architecture", "settings-window-focus",
                "panel-permission-interaction", "ui-interaction"),
         why="权限状态视图被权限测试断言，且被设置架构/焦点/面板交互测试编译"),
    dict(id="ui-accessibility", globs=["replica/Sources/BlinkClip/UI/AccessibilityRequestAction.swift",
                                       "replica/Sources/BlinkClip/UI/AccessibilityModals.swift"],
         tests=("accessibility-modal", "permission-status", "settings-window-focus",
                "panel-permission-interaction"),
         why="权限引导弹窗与请求动作的直接断言方"),
    dict(id="ui-settings-focus", globs=["replica/Sources/BlinkClip/UI/SettingsWindowFocusRestore.swift"],
         tests=("settings-window-focus", "permission-status"),
         why="焦点恢复的唯一断言方，permission-status 编译该文件"),
    dict(id="ui-appearance-observation",
         globs=["replica/Sources/BlinkClip/UI/WindowAppearancePreferenceObservation.swift"],
         tests=("appearance-preferences",),
         why="外观偏好观察是 appearance-preferences 的断言对象"),
    dict(id="ui-brand", globs=["replica/Sources/BlinkClip/UI/ReplicaBrand.swift"],
         tests=("accessibility-modal", "icloud-drive-controller"),
         why="两个测试显式编译 ReplicaBrand.swift 并断言品牌文案"),
    dict(id="ui-shortcut-recorder", globs=["replica/Sources/BlinkClip/UI/ShortcutRecorder.swift"],
         tests=("settings-localization", "ui-interaction"),
         why="录制器文案由设置本地化测试覆盖，交互由 ui-interaction 覆盖"),
    dict(id="ui-settings-shortcut-reset",
         globs=["replica/Sources/BlinkClip/UI/SettingsShortcutReset.swift"],
         tests=("settings-shortcut-reset", "settings-architecture"),
         why="重置逻辑的专属测试；设置架构测试也编译 UI/ 全量"),
    dict(id="ui-settings-row-restore",
         globs=["replica/Sources/BlinkClip/UI/SettingsShortcutRowRestore.swift"],
         tests=("shortcut-row-restore", "settings-architecture"),
         why="行恢复的专属测试；设置架构测试内含行恢复段落"),
    dict(id="ui-settings-copy", globs=["replica/Sources/BlinkClip/UI/SettingsCopy.swift"],
         tests=("settings-architecture", "settings-localization", "settings-shortcut-reset",
                "shortcut-row-restore"),
         why="设置文案提供者被这四个测试编译并断言文案键"),
    dict(id="ui-screenshot-settings-copy",
         globs=["replica/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift"],
         tests=("settings-architecture", "settings-localization", "shortcut-row-restore",
                "capture-integration"),
         why="截图设置文案被设置/行恢复/截图胶水三侧共用"),
    dict(id="ui-history-retention",
         globs=["replica/Sources/BlinkClip/UI/HistoryRetentionSaving.swift",
                "replica/Sources/BlinkClip/UI/HistoryRetentionCopy.swift",
                "replica/Sources/BlinkClip/UI/HistoryCapacityControl.swift"],
         tests=("history-retention", "retention-save-performance", "settings-architecture"),
         why="保留期限的专属测试 + 保存性能 + 设置架构"),
    dict(id="ui-auxiliary-views", globs=["replica/Sources/BlinkClip/UI/AuxiliaryViews.swift"],
         tests=("history-retention", "retention-save-performance", "settings-architecture",
                "settings-localization"),
         why="保留期限与设置页共用的视图，三个测试都编译或断言"),
    dict(id="ui-updater", globs=["replica/Sources/BlinkClip/UI/BlinkClipInAppUpdater.swift",
                                 "replica/Sources/BlinkClip/UI/BlinkClipAboutWindowController.swift"],
         tests=("app-updates", "sparkle-startup", "settings-architecture"),
         why="更新器与关于页被更新测试断言，Sparkle 启动测试编译更新器"),
    dict(id="ui-cloudkit-controller",
         globs=["replica/Sources/BlinkClip/UI/CloudKitSyncController.swift"],
         tests=("settings-architecture", "cloudkit-sync", "icloud-sync"),
         why="设置页里的云同步控制器，被设置架构与云同步契约测试编译"),
    dict(id="ui-settings-split",
         globs=["replica/Sources/BlinkClip/UI/SettingsSplitView.swift",
                "replica/Sources/BlinkClip/UI/SettingsSurfaceStyle.swift"],
         tests=("settings-architecture", "settings-localization", "permission-status"),
         why="设置外壳/表面样式被设置架构与权限页共用"),
    dict(id="ui-replica-uicontroller",
         globs=["replica/Sources/BlinkClip/UI/ReplicaUIController.swift"],
         tests=("ui-interaction", "settings-architecture", "settings-localization",
                "settings-window-focus", "appearance-preferences", "copy-restore",
                "panel-scroll", "quick-paste", "search-button", "text-card-appearance"),
         why="面板 UI 控制器是这些测试的主被测对象（含语法门与外观观察）；"
             "quick-paste 断言其统一粘贴入口的置顶成功分支"),
    dict(id="ui-generic", globs=["replica/Sources/BlinkClip/UI/**"], tests=UI_COMPILE,
         why="UI/ 其余文件均被这批测试编译（多数按 UI/ 全量 glob 编译）"),

    # ============ 4. BlinkClipCore ============
    dict(id="core-sound-effects", globs=["replica/Sources/BlinkClipCore/SoundEffects.swift"],
         tests=("sound-effects", "copy-restore", "feedback-shortcuts"),
         why="三个测试都编译 SoundEffects.swift：sound-effects 断言分类映射，copy-restore 断言"
             "复制/粘贴/栈粘贴的声音序列，feedback-shortcuts 断言快捷键反馈"),
    dict(id="core-pasteboard-item", globs=["replica/Sources/BlinkClipCore/PasteboardItem.swift"],
         tests=("core-tests", "python-static"),
         why="core 单测覆盖它；scripts/tests/test_p0_repair_archive_keys.py 对其做源码门"),
    dict(id="core-pasteboard", globs=["replica/Sources/BlinkClipCore/Pasteboard.swift",
                                      "replica/Sources/BlinkClipCore/PasteboardArchive.swift",
                                      "replica/Sources/BlinkClipCore/PasteboardRestore.swift",
                                      "replica/Sources/BlinkClipCore/PasteboardDataCodec.swift",
                                      "replica/Sources/BlinkClipCore/PasteboardPolicies.swift",
                                      "replica/Sources/BlinkClipCore/PasteboardChecksums.swift",
                                      "replica/Sources/BlinkClipCore/PasteboardClassification.swift",
                                      "replica/Sources/BlinkClipCore/PasteboardImageEncoding.swift",
                                      "replica/Sources/BlinkClipCore/PasteboardImageRestore.swift",
                                      "replica/Sources/BlinkClipCore/PasteboardCaptureState.swift"],
         tests=("core-tests", "settings-localization", "copy-restore", "pasteboard-write-feedback",
                "quick-paste"),
         why="剪贴板数据层：core 单测 + 设置本地化（Pasteboard.swift）+ 复制还原 + 写入反馈；"
             "quick-paste 断言写回带的生成标记不会被自身监听捕获"),
    dict(id="core-permission",
         globs=["replica/Sources/BlinkClipCore/AccessibilityService.swift",
                "replica/Sources/BlinkClipCore/PermissionPromptPolicy.swift",
                "replica/Sources/BlinkClipCore/PermissionStatusSnapshot.swift"],
         tests=("permission-status", "core-tests"),
         why="permission-status 显式编译这三个文件并断言快照/提示策略"),
    dict(id="core-localization",
         globs=["replica/Sources/BlinkClipCore/SettingsStrings.swift",
                "replica/Sources/BlinkClipCore/SettingsLocalization.swift",
                "replica/Sources/BlinkClipCore/SearchLocalization.swift",
                "replica/Sources/BlinkClipCore/PreviewLocalization.swift",
                "replica/Sources/BlinkClipCore/UnavailablePreviewLocalization.swift",
                "replica/Sources/BlinkClipCore/ShortcutMessages.swift",
                "replica/Sources/BlinkClipCore/ResourceBundle.swift",
                "replica/Sources/BlinkClipCore/AppBrand.swift",
                "replica/Sources/BlinkClipCore/SettingsIllustrations.swift",
                "replica/Sources/BlinkClipCore/BlinkClipAssetRenderer.swift"],
         tests=("blinkclip-owned-resources", "settings-localization", "permission-status",
                "history-retention"),
         why="本地化解析器与自有资源渲染器：自有资源测试逐个编译它们，设置本地化逐语断言"),
    dict(id="core-icloud", globs=["replica/Sources/BlinkClipCore/ICloudDriveSync.swift"],
         tests=("icloud-sync", "icloud-noop-performance", "icloud-drive-controller"),
         why="三个 iCloud 测试分别覆盖契约、空转性能与控制器"),
    dict(id="core-cloudkit-config",
         globs=["replica/Sources/BlinkClipCore/BlinkClipCloudKitConfiguration.swift"],
         tests=("cloudkit-sync", "icloud-sync"),
         why="CloudKit 配置被契约测试与同步测试编译"),
    dict(id="core-cloudkit-graph", globs=["replica/Sources/BlinkClipCore/CloudKitGraph.swift"],
         tests=("retention-save-performance", "cloudkit-sync", "core-tests"),
         why="保存性能测试对该文件做结构门并编译；CloudKit 契约测试覆盖图构建"),
    dict(id="core-cloudkit-sync-engine",
         globs=["replica/Sources/BlinkClipCore/CloudKitSyncEngine.swift",
                "replica/Sources/BlinkClipCore/CloudKitJournal.swift",
                "replica/Sources/BlinkClipCore/CloudKitContracts.swift"],
         tests=("cloudkit-sync", "icloud-sync", "core-tests"),
         why="云同步引擎/journal 契约由 cloudkit-sync 断言"),
    dict(id="core-update-checker", globs=["replica/Sources/BlinkClipCore/BlinkClipUpdateChecker.swift"],
         tests=("app-updates", "sparkle-startup"),
         why="版本比较与 appcast 解析的断言对象"),
    dict(id="core-store",
         globs=["replica/Sources/BlinkClipCore/ClipboardStore.swift",
                "replica/Sources/BlinkClipCore/ClipboardPersistence.swift",
                "replica/Sources/BlinkClipCore/ClipboardListPersistence.swift",
                "replica/Sources/BlinkClipCore/PinboardAttributes.swift",
                "replica/Sources/BlinkClipCore/Models.swift"],
         tests=("core-tests", "retention-save-performance", "copy-restore",
                "pasteboard-write-feedback", "history-retention", "mcp"),
         why="存储核心：core 单测 + 保存性能 + 复制还原 + 写入反馈 + 保留期限 + MCP fixture 链接"),
    dict(id="core-resources", globs=["replica/Sources/BlinkClipCore/BlinkClipResources/**"],
         tests=("blinkclip-owned-resources", "packaged-resources"),
         why="本地化表/音频/插图是这两条资源测试的断言对象"),
    dict(id="core-generic", globs=["replica/Sources/BlinkClipCore/**"], tests=CORE_LINKED,
         why="core 层其余文件由所有链接 BlinkClipCore 的测试覆盖（保守面）"),

    # ============ 5. Vendor/capcap（BlinkClipCapture 模块） ============
    dict(id="vendor-identifier-migration",
         globs=["replica/Vendor/capcap/Utilities/BlinkClipIdentifierMigration.swift",
                "replica/Vendor/capcap/Capture/ClipboardHistorySkipMarker.swift"],
         tests=("identifier-namespace-migration",),
         why="标识符迁移测试只编译这两个文件的 harness"),
    dict(id="vendor-selection-view",
         globs=["replica/Vendor/capcap/Capture/SelectionView.swift"],
         tests=("capture-chrome-exclusion", "overlay-opt", "editor-chrome-parity",
                "capture-integration"),
         why="chrome-exclusion 直接读 SelectionView 断言标签/辅线/边框/手柄/光标；"
             "overlay-opt 的源码门读 mouseMoved 断言事件路径零请求；"
             "editor-chrome-parity 比对它与编辑器 chrome；capture-integration 编译整个 Capture 模块"),
    dict(id="vendor-capture-gate",
         globs=["replica/Vendor/capcap/Capture/OverlayWindowController.swift"],
         tests=("overlay-opt", "capture-chrome-exclusion", "editor-chrome-parity",
                "capture-integration"),
         why="源码门读 OverlayWindowController 断言光标与选框生命周期；"
             "overlay-opt 的源码门断言 2Hz 枚举 + 静止暂停 + 未命中补采 + 事件路径零请求"),
    dict(id="vendor-capture-generic", globs=["replica/Vendor/capcap/Capture/**"],
         tests=("overlay-opt", "capture-chrome-exclusion", "editor-chrome-parity",
                "capture-integration"),
         why="框选/截图引擎其余文件由 chrome 源码门 + chrome 一致性 + 截图胶水覆盖；"
             "overlay-opt 另读 WindowDetector 断言 pid 缓存"),
    dict(id="vendor-editor-window",
         globs=["replica/Vendor/capcap/Editor/EditWindowController.swift"],
         tests=("editor-chrome-parity", "capture-chrome-exclusion", "toolbar-upload-removal"),
         why="三者都编译/读取 EditWindowController（chrome 一致性、尺寸标签文案、工具栏几何）"),
    dict(id="vendor-editor-shortcuts",
         globs=["replica/Vendor/capcap/Editor/EditorShortcutRegistry.swift",
                "replica/Vendor/capcap/Editor/EditorCommandDoubleTap.swift"],
         tests=("feedback-shortcuts", "toolbar-upload-removal", "editor-chrome-parity"),
         why="快捷键注册/双击命令由 feedback-shortcuts 断言，其余两者编译该模块"),
    dict(id="vendor-editor-toolbar",
         globs=["replica/Vendor/capcap/Editor/Toolbar*.swift"],
         tests=("toolbar-upload-removal", "editor-chrome-parity"),
         why="工具栏布局/按钮/分组是 toolbar-upload-removal 的断言对象"),
    dict(id="vendor-editor-generic", globs=["replica/Vendor/capcap/Editor/**"],
         tests=("editor-chrome-parity", "feedback-shortcuts", "toolbar-upload-removal",
                "capture-chrome-exclusion"),
         why="编辑器其余文件（标注/美化/裁剪/Mosaic/QR）由 chrome 一致性与工具栏测试编译覆盖"),
    dict(id="vendor-adapters", globs=["replica/Vendor/capcap/Adapters/**"],
         tests=("capture-integration", "feedback-shortcuts"),
         why="截图入口/ScreenshotSettings/HistoryManagerBridge 被 capture-integration 编译并断言；"
             "HotkeyManagerStub 被 feedback-shortcuts 编译"),
    dict(id="vendor-adapters-hotkey-stub",
         globs=["replica/Vendor/capcap/Adapters/HotkeyManagerStub.swift"],
         tests=("feedback-shortcuts", "capture-integration", "panel-hotkey"),
         why="热键桩被快捷键反馈与面板热键测试编译"),
    dict(id="vendor-utilities-generic", globs=["replica/Vendor/capcap/Utilities/**"],
         tests=("identifier-namespace-migration", "editor-chrome-parity", "capture-integration"),
         why="工具层随模块编译；迁移工具由 identifier 测试断言"),
    dict(id="vendor-translation", globs=["replica/Vendor/capcap/Translation/**"],
         tests=("translation-integration",), why="翻译/OCR 桥的唯一断言方"),
    dict(id="vendor-resources", globs=["replica/Vendor/capcap/Resources/**"],
         tests=("translation-integration", "toolbar-upload-removal",
                "blinkclip-owned-resources", "packaged-resources"),
         why="capcap 本地化表被翻译、工具栏与资源白名单测试三方断言"),
    dict(id="vendor-ui", globs=["replica/Vendor/capcap/UI/**"],
         tests=("overlay-opt", "toolbar-upload-removal", "editor-chrome-parity",
                "capture-chrome-exclusion"),
         why="自适应 chrome/光标/放大镜等与编辑器 chrome 一致性直接相关；"
             "overlay-opt 的源码门读 MagnifierLensPanelWindow 断言 20Hz 与静态 chrome 缓存"),
    dict(id="vendor-generic", globs=["replica/Vendor/capcap/**"], tests=VENDOR_CAPTURE,
         why="BlinkClipCapture 其余目录（ImageMerge/Upload/ImageOutputEncoder 等）随模块编译，"
             "由捕获/编辑器/工具栏面保守覆盖"),

    # ============ 6. 其它目标 / 构建输入 ============
    dict(id="objc", globs=["replica/Sources/BlinkClipObjC/**"],
         tests=("panel-top-corners", "ui-interaction", "core-tests", "packaged-resources"),
         why="ObjC 模块被所有 harness 链接；PRPanelGlassBackground 由 panel-top-corners 断言"),
    dict(id="helper", globs=["replica/Sources/BlinkClipHelper/**"],
         tests=("helper-lifecycle", "packaged-resources"),
         why="helper 主程序是 helper-lifecycle 的被测对象"),
    dict(id="mcp-target", globs=["replica/Sources/BlinkClipMCP/**"], tests=("mcp",),
         why="MCP stdio 端到端测试的被测对象"),
    dict(id="package-swift", globs=["replica/Package.swift"],
         tests=("core-tests", "packaged-resources", "blinkclip-owned-resources",
                "capture-chrome-exclusion", "editor-chrome-parity", "icloud-noop-performance",
                "sparkle-startup", "retention-save-performance", "capture-integration"),
         why="SwiftPM 清单变化影响所有构建路径，选一组代表性构建/资源测试并回退全量更稳妥——"
             "因此本规则故意放宽到 9 项"),
    dict(id="assets", globs=["replica/Assets/**"],
         tests=("packaged-resources", "blinkclip-owned-resources", "history-retention",
                "sparkle-startup", "release-packaging"),
         why="图标/公钥/entitlements 被打包、资源、保留期限与发布测试断言"),
    dict(id="resources-root", globs=["Resources/**", "replica/Resources/**"],
         tests=("packaged-resources", "blinkclip-owned-resources"),
         why="仓库级资源目录（若新增）由资源类测试覆盖"),
    dict(id="website", globs=["website/**"], tests=("check-website", "website-i18n"),
         why="站点检查与 i18n 测试的被测对象"),
    dict(id="workflows", globs=[".github/workflows/**"],
         tests=("release-plan", "release-packaging", "python-static"),
         why="发布计划/打包契约与站点顺序断言直接读工作流文件"),
    dict(id="package-json", globs=["package.json"],
         tests=("release-plan", "release-packaging", "panel-permission-interaction"),
         why="版本号与脚本入口被发布测试、打包断言（panel-permission-interaction 校验 CFBundleShortVersionString）"),
    dict(id="branding", globs=["branding/**"],
         tests=("blinkclip-owned-resources", "packaged-resources"),
         why="品牌资产与自有资源/打包资源测试相关"),
]


# --------------------------------------------------------------------------------------
# glob → regex（`*` 不跨目录，`**` 跨目录）
# --------------------------------------------------------------------------------------
def glob_to_regex(pattern):
    out = []
    i = 0
    while i < len(pattern):
        if pattern[i:i + 3] == "**/":
            out.append("(?:.*/)?")
            i += 3
        elif pattern[i:i + 2] == "**":
            out.append(".*")
            i += 2
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("^" + "".join(out) + "$")


for _rule in RULES:
    _rule["regexes"] = [glob_to_regex(g) for g in _rule["globs"]]


class Item:
    """一个测试项。"""
    __slots__ = ("id", "group", "cmd", "reasons", "files")

    def __init__(self, key):
        meta = ITEMS[key]
        self.id = key
        self.group = meta["group"]
        self.cmd = list(meta["cmd"])
        self.reasons = []   # [(rule_id, why)]
        self.files = []     # 命中的改动文件


class Selection:
    def __init__(self):
        self.items = {}       # id -> Item
        self.docs = []        # [(path, rule_id)]
        self.ignored = []     # [path]
        self.uncovered = []   # [path]
        self.fell_back = False
        self.changed = []

    def add(self, test_id, rule_id, why, path):
        item = self.items.get(test_id)
        if item is None:
            item = Item(test_id)
            self.items[test_id] = item
        if (rule_id, why) not in item.reasons:
            item.reasons.append((rule_id, why))
        if path and path not in item.files:
            item.files.append(path)


# --------------------------------------------------------------------------------------
# 改动文件来源
# --------------------------------------------------------------------------------------
def _git(*args):
    proc = subprocess.run(["git"] + list(args), cwd=REPO_ROOT, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        raise SystemExit("git %s 失败：%s" % (" ".join(args), proc.stderr.strip()))
    return proc.stdout


def changed_from_base(base):
    for spec in ("%s...HEAD" % base, "%s" % base):
        proc = subprocess.run(["git", "diff", "--name-only", spec], cwd=REPO_ROOT,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if proc.returncode == 0:
            return [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    raise SystemExit("git diff --name-only %s...HEAD 失败（基线上不存在？）" % base)


def _unquote(path):
    if path.startswith('"') and path.endswith('"'):
        try:
            return path[1:-1].encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")
        except Exception:
            return path[1:-1]
    return path


def changed_from_worktree():
    out = _git("status", "--porcelain=v1", "--untracked-files=all", "--no-renames")
    paths = []
    for line in out.splitlines():
        if len(line) < 4:
            continue
        body = line[3:]
        if " -> " in body:
            body = body.split(" -> ", 1)[1]
        paths.append(_unquote(body.strip()))
    return [p for p in paths if p]


# --------------------------------------------------------------------------------------
# 选择引擎
# --------------------------------------------------------------------------------------
def resolve_dynamic(rule, path):
    """返回 (test_ids, why) 或 (None, why) 表示未覆盖。"""
    kind = rule.get("dynamic")
    if kind == "harness":
        name = os.path.basename(path)
        hits = []
        for test_id in NATIVE_ALL:
            script = os.path.join(REPO_ROOT, "replica", "scripts", "test-%s.sh" % test_id)
            try:
                with open(script, "r", encoding="utf-8", errors="replace") as handle:
                    if name in handle.read():
                        hits.append(test_id)
            except OSError:
                continue
        if not hits:
            return None, "没有任何 test-*.sh 引用 %s" % name
        return hits, "以下 test-*.sh 编译/引用该 harness：%s" % ", ".join(hits)
    if kind == "test-script":
        base = os.path.basename(path)
        stem = base[len("test-"):].rsplit(".", 1)[0]
        if stem in ITEMS:
            return [stem], "测试脚本自身改动：把 %s 加进选择清单" % stem
        return None, "%s 不是已登记的测试入口" % base
    return None, "未知动态规则 %r" % kind


def resolve_rule(path):
    """按规则表顺序解析一个路径：(rule, tests, why)；解析不了返回 (None, None, None)。

    动态规则（harness/test-script）解析失败时继续往下试下一条规则——这样「只为某个
    python 测试服务的 harness」可以由后面的显式规则接住，而不是直接算漏覆盖。
    """
    for rule in RULES:
        if not any(regex.match(path) for regex in rule["regexes"]):
            continue
        if rule.get("dynamic"):
            tests, why = resolve_dynamic(rule, path)
            if tests is None:
                continue
            return rule, tests, why
        return rule, tuple(rule["tests"]), rule.get("why", "")
    return None, None, None


def select(paths):
    sel = Selection()
    sel.changed = sorted(set(p for p in paths if p))
    for path in sel.changed:
        rule, tests, why = resolve_rule(path)
        if rule is None:
            sel.uncovered.append(path)
            continue
        kind = rule.get("kind", "tests")
        if kind == "ignore":
            sel.ignored.append(path)
            continue
        if kind == "docs":
            sel.docs.append((path, rule["id"]))
            continue
        for test_id in tests:
            sel.add(test_id, rule["id"], why, path)

    if sel.uncovered:
        # 保守兜底：未收录路径 → 全量
        sel.fell_back = True
        sel.items = {}
        for test_id in ALL_IDS:
            sel.add(test_id, "fallback-full",
                     "改动触及未收录路径，回退全量（规则表需要补规则）", "")
    return sel


# --------------------------------------------------------------------------------------
# 耗时估计：优先本工具的 timings.json，其次 regress-local 的历史 summary.json
# --------------------------------------------------------------------------------------
_REGRESS_NAME_MAP = {
    "core": "core-tests", "hotkey": "hotkey", "panel-hotkey": "panel-hotkey",
    "panel-menu": "panel-menu", "quick-paste": "quick-paste",
    "shortcut": "shortcut-model", "window": "window-policy",
    "ui": "ui-interaction", "copy-restore": "copy-restore",
    "accessibility-modal": "accessibility-modal", "packaged-resources": "packaged-resources",
    "app-updates": "app-updates", "sparkle-startup": "sparkle-startup",
    "icloud-sync": "icloud-sync", "icloud-drive-controller": "icloud-drive-controller",
    "cloudkit-contract": "cloudkit-sync", "monitor": "app-monitor",
    "helper": "helper-lifecycle",
}


def load_timings():
    timings = {}
    for summary in sorted(_glob_recent(os.path.join(REPO_ROOT, ".local"), "local-regression-*",
                                       "summary.json")):
        try:
            data = json.load(open(summary, "r", encoding="utf-8"))
        except (OSError, ValueError):
            continue
        for suite in data.get("suites", []):
            test_id = _REGRESS_NAME_MAP.get(suite.get("name", ""))
            seconds = suite.get("duration_seconds")
            if test_id and isinstance(seconds, (int, float)):
                timings.setdefault(test_id, float(seconds))
    try:
        data = json.load(open(TIMINGS_PATH, "r", encoding="utf-8"))
        for key, seconds in data.items():
            if key in ITEMS and isinstance(seconds, (int, float)):
                timings[key] = float(seconds)
    except (OSError, ValueError):
        pass
    return timings


def _glob_recent(root, pattern, leaf):
    paths = []
    try:
        for name in os.listdir(root):
            if fnmatch.fnmatchcase(name, pattern):
                candidate = os.path.join(root, name, leaf)
                if os.path.isfile(candidate):
                    paths.append(candidate)
    except OSError:
        return []
    return paths


def write_timings(durations):
    if not durations:
        return
    try:
        existing = json.load(open(TIMINGS_PATH, "r", encoding="utf-8"))
        if not isinstance(existing, dict):
            existing = {}
    except (OSError, ValueError):
        existing = {}
    existing.update({k: round(v, 3) for k, v in durations.items()})
    os.makedirs(os.path.dirname(TIMINGS_PATH), exist_ok=True)
    with open(TIMINGS_PATH, "w", encoding="utf-8") as handle:
        json.dump(existing, handle, indent=2, sort_keys=True)
        handle.write("\n")


# --------------------------------------------------------------------------------------
# 输出
# --------------------------------------------------------------------------------------
def _fmt_seconds(seconds):
    if seconds is None:
        return "—"
    if seconds < 60:
        return "~%ds" % round(seconds)
    return "~%.1fmin" % (seconds / 60.0)


def render(sel, args, timings):
    lines = []
    if args.files:
        scope = "--files（直接给定文件列表）"
    elif args.base:
        scope = "--base %s（提交对比）" % args.base
    elif args.worktree:
        scope = "工作区改动（git status）"
    else:
        scope = "--full（全量）"
    lines.append("影响面测试选择器 · 范围：%s" % scope)
    lines.append("改动文件：%d 个" % len(sel.changed))
    for path in sel.changed:
        lines.append("  · %s" % path)
    if not sel.changed:
        lines.append("  （无改动）")
    if sel.fell_back:
        lines.append("")
        lines.append("⚠ 未覆盖的路径，回退全量：")
        for path in sel.uncovered:
            lines.append("  ✗ %s" % path)
        lines.append("  → 请在 replica/scripts/test-affected.py 的 RULE_TABLE 里补规则，"
                     "或确认该路径确实不影响测试。")

    selected = [sel.items[key] for key in ALL_IDS if key in sel.items]
    total = 0.0
    all_known = bool(selected)
    for item in selected:
        seconds = timings.get(item.id)
        if seconds is None:
            all_known = False
        else:
            total += seconds
    lines.append("")
    if sel.fell_back:
        # 回退全量时不逐条重复同一句理由，只把清单摊开
        lines.append("选中测试：全量 %d / %d 项（未覆盖路径触发回退）" % (len(selected), len(ALL_IDS)))
        lines.append("  " + ", ".join(item.id for item in selected))
    else:
        lines.append("选中测试：%d / %d 项" % (len(selected), len(ALL_IDS)))
        for item in selected:
            seconds = timings.get(item.id)
            rule_ids = ", ".join(sorted(set(r for r, _ in item.reasons)))
            lines.append("  ✓ %-32s [%s] 预估 %-8s 命中规则：%s"
                         % (item.id, item.group, _fmt_seconds(seconds), rule_ids))
            for rule_id, why in item.reasons[:2]:
                lines.append("      · %s" % why)
            extra = item.reasons[2:]
            if extra:
                lines.append("      · 另有 %d 条规则命中同一测试" % len(extra))
    if selected:
        lines.append("预估耗时合计：%s" % (_fmt_seconds(total) if all_known else "未知（缺历史耗时）"))
    else:
        lines.append("预估耗时合计：0s")

    skipped = [key for key in ALL_IDS if key not in sel.items]
    lines.append("")
    lines.append("跳过测试：%d 项" % len(skipped))
    for key in skipped:
        lines.append("  - %-32s [%s]" % (key, ITEMS[key]["group"]))

    if sel.docs:
        lines.append("")
        lines.append("无需测试的改动（文档/元数据/工具自身）：")
        for path, rule_id in sel.docs:
            lines.append("  · %s（规则 %s）" % (path, rule_id))
    if sel.ignored:
        lines.append("")
        lines.append("忽略路径（不触发选择）：")
        for path in sel.ignored:
            lines.append("  · %s" % path)
    if sel.docs and not selected:
        lines.append("")
        lines.append("结论：本次改动只涉及文档/元数据，无测试项，跳过。")

    manual_items = [item.id for item in selected if ITEMS[item.id]["manual"]]
    if manual_items:
        lines.append("")
        lines.append("手工项（缺环境变量时记为「手工」而不是失败；执行方式见 docs/TESTING.md）：")
        for test_id in manual_items:
            lines.append("  · %-30s %s" % (test_id, ITEMS[test_id]["manual"]))

    required_env = sorted({var for item in selected if not ITEMS[item.id]["manual"]
                           for var in ITEMS[item.id]["requires"]})
    if required_env:
        missing = [var for var in required_env if not os.environ.get(var)]
        lines.append("")
        if missing:
            lines.append("⚠ 选中的测试需要环境变量（缺失项按「未执行」处理，不算通过）：%s"
                         % ", ".join(missing))
        else:
            lines.append("环境变量齐备：%s" % ", ".join(required_env))
    return "\n".join(lines)


def as_json(sel, timings):
    selected = [sel.items[key] for key in ALL_IDS if key in sel.items]
    return json.dumps({
        "changed": sel.changed,
        "fell_back": sel.fell_back,
        "uncovered": sel.uncovered,
        "docs": [p for p, _ in sel.docs],
        "ignored": sel.ignored,
        "selected": [{"id": item.id, "group": item.group, "cmd": item.cmd,
                      "manual": ITEMS[item.id]["manual"],
                      "rules": [r for r, _ in item.reasons],
                      "files": item.files,
                      "estimated_seconds": timings.get(item.id)} for item in selected],
        "skipped": [key for key in ALL_IDS if key not in sel.items],
    }, ensure_ascii=False, indent=2)


# --------------------------------------------------------------------------------------
# 执行
# --------------------------------------------------------------------------------------
def artifact_root():
    """本次执行的产物根目录（永远在仓库之外）。

    在 storage-guard 里跑时嵌到 `$ARTIFACT_TASK_DIR/items`，让受管预算照旧统计；
    独立运行时用 `BLINKCLIP_TEST_ARTIFACT_ROOT`，否则在系统临时目录建一个。
    """
    guard_task = os.environ.get("ARTIFACT_TASK_DIR")
    if guard_task:
        root = os.path.join(guard_task, "items")
    else:
        root = os.environ.get("BLINKCLIP_TEST_ARTIFACT_ROOT") or tempfile.mkdtemp(
            prefix="blinkclip-test-affected-")
    os.makedirs(root, exist_ok=True)
    return os.path.abspath(root)


def expand(argv, task_dir):
    return [str(arg).replace("{artifact_task_dir}", task_dir) for arg in argv]


def run_selection(selected, timings, keep_going, root=None, keep_artifacts=False):
    """逐项跑。

    **每一项一个隔离目录**：所有 `test-*.sh` 都把中间文件写在 `$ARTIFACT_TASK_DIR/build`
    下，共用同一个目录时 `build/harness` 这类路径会在不同测试之间既当文件又当目录
    （`capture-integration` 的假失败就是这么来的）。这里给每项分配
    `$root/<id>` 并把它作为该项的 `ARTIFACT_TASK_DIR`，跑完删掉该项 `build/`，只留 `out/`。
    """
    root = root or artifact_root()
    durations = {}
    failures = []
    blocked = []
    manual = []
    ran = 0
    print("隔离产物目录：%s（每项一个子目录，跑完删除该项 build/）" % root, flush=True)
    for item in selected:
        meta = ITEMS[item.id]
        missing = [var for var in meta["requires"] if not os.environ.get(var)]
        if item.id == "website-i18n" and shutil.which("node") is None:
            missing.append("node")
        if missing and meta["manual"]:
            print("\n===== %s：手工项（%s） =====" % (item.id, meta["manual"]), flush=True)
            manual.append((item.id, meta["manual"]))
            continue
        if missing:
            print("\n===== %s：未执行（缺少 %s） =====" % (item.id, ", ".join(missing)), flush=True)
            blocked.append((item.id, "缺少 " + ", ".join(missing)))
            continue
        task_dir = os.path.join(root, item.id)
        os.makedirs(task_dir, exist_ok=True)
        env = os.environ.copy()
        env["ARTIFACT_TASK_DIR"] = task_dir
        for name, value in meta["env"].items():
            env[name] = expand([value], task_dir)[0]
        prepared = True
        for step in meta["prep"]:
            step_cmd = expand(step, task_dir)
            print("\n===== %s：前置 %s =====" % (item.id, " ".join(step_cmd[:2]) + (" …" if len(step_cmd) > 2 else "")),
                  flush=True)
            if subprocess.call(step_cmd, cwd=REPO_ROOT, env=env) != 0:
                print("----- %s：FAIL（前置命令失败）" % item.id, flush=True)
                failures.append((item.id, "prep"))
                prepared = False
                break
        if not prepared:
            if not keep_going:
                break
            continue
        cmd = expand(meta["cmd"], task_dir)
        print("\n===== %s：%s =====" % (item.id, " ".join(cmd)), flush=True)
        started = time.monotonic()
        code = subprocess.call(cmd, cwd=REPO_ROOT, env=env)
        elapsed = time.monotonic() - started
        durations[item.id] = elapsed
        ran += 1
        if code == 0:
            print("----- %s：PASS（%.1fs）" % (item.id, elapsed), flush=True)
        else:
            print("----- %s：FAIL（exit %d，%.1fs）" % (item.id, code, elapsed), flush=True)
            failures.append((item.id, code))
        if not keep_artifacts:
            shutil.rmtree(os.path.join(task_dir, "build"), ignore_errors=True)
        if code != 0 and not keep_going:
            break
    write_timings(durations)

    print("\n===== 汇总 =====")
    print("执行 %d 项，失败 %d 项，未执行 %d 项，手工项 %d 项"
          % (ran, len(failures), len(blocked), len(manual)))
    for test_id, code in failures:
        print("  FAIL %s（exit %s）" % (test_id, code))
    for test_id, reason in blocked:
        print("  未执行 %s：%s" % (test_id, reason))
    for test_id, reason in manual:
        print("  手工项 %s：%s（需按 docs/TESTING.md 手工执行，不计入自动门禁）"
              % (test_id, reason))
    print("产物目录：%s" % root)
    if failures:
        return 1
    if blocked:
        print("注意：存在未执行项，不能视为全部通过。")
        return 2
    if manual:
        print("全部自动测试通过；另有 %d 个手工项未在本次执行。" % len(manual))
    else:
        print("全部选中测试通过。")
    return 0


# 已知缺口：仓库里存在但没有任何测试引用的文件。audit 会单列，不算失败；
# 一旦它们被某个测试接入，请从本表删掉，让 audit 重新把关。
KNOWN_UNCOVERED = {
    "replica/Tests/Native/ShortcutRecorderLifecycleHarness.swift":
        "孤儿 harness：没有任何 test-*.sh 编译它（改了只能回退全量）",
}


# --------------------------------------------------------------------------------------
# 映射表体检
# --------------------------------------------------------------------------------------
def audit():
    """列出规则表没覆盖到的源码文件，以及没人引用的规则/测试项。"""
    known = set()
    for dirpath, dirnames, filenames in os.walk(REPO_ROOT):
        dirnames[:] = [d for d in dirnames if d not in (".git", ".build", "node_modules", ".local")]
        for name in filenames:
            rel = os.path.relpath(os.path.join(dirpath, name), REPO_ROOT)
            if rel.startswith("replica/dist/"):
                continue
            known.add(rel)
    interesting = sorted(p for p in known
                         if p.startswith(("replica/Sources", "replica/Vendor", "replica/Tests",
                                          "replica/scripts", "scripts/", "website/", "branding/",
                                          "docs/", ".github/"))
                         or "/" not in p)
    uncovered = [path for path in interesting if resolve_rule(path)[0] is None]
    referenced = set()
    for rule in RULES:
        referenced.update(rule["tests"])
    print("规则 %d 条，测试项 %d 个" % (len(RULES), len(ITEMS)))
    print("未被任何测试项引用的规则：%s" %
          (", ".join(r["id"] for r in RULES if r["tests"] and not set(r["tests"]) & referenced)
           or "无"))
    known = [p for p in uncovered if p in KNOWN_UNCOVERED]
    unknown = [p for p in uncovered if p not in KNOWN_UNCOVERED]
    print("没有规则/动态解析覆盖的源码文件：%d 个（其中已知缺口 %d 个）"
          % (len(uncovered), len(known)))
    for path in unknown:
        print("  ✗ %s（需要补规则，否则改动会回退全量）" % path)
    for path in known:
        print("  · %s（已知缺口：%s）" % (path, KNOWN_UNCOVERED[path]))
    return 0 if not unknown else 1


# --------------------------------------------------------------------------------------
def main(argv=None):
    parser = argparse.ArgumentParser(
        description="按改动范围选择测试（日常只跑受影响测试，全量留给发版前）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="示例：\n"
               "  python3 replica/scripts/test-affected.py --worktree --dry-run\n"
               "  python3 replica/scripts/test-affected.py --base origin/main\n"
               "  python3 replica/scripts/test-affected.py --full --dry-run\n")
    scope = parser.add_mutually_exclusive_group()
    scope.add_argument("--base", metavar="COMMIT",
                       help="用 git diff --name-only <base>...HEAD 对比提交范围")
    scope.add_argument("--worktree", action="store_true",
                       help="用 git status 取工作区/未跟踪改动（默认）")
    scope.add_argument("--full", action="store_true", help="全量：跑所有测试（发版前用）")
    scope.add_argument("--files", nargs="+", metavar="PATH",
                       help="直接给改动文件列表（不经 git，调试/演练用）")
    parser.add_argument("--dry-run", action="store_true", help="只打印选择结果，不执行")
    parser.add_argument("--json", action="store_true", help="以 JSON 输出选择结果")
    parser.add_argument("--audit", action="store_true", help="映射表体检：列出未覆盖源码文件")
    parser.add_argument("--keep-going", action="store_true",
                        help="有测试失败时继续跑剩余测试（默认首个失败即停）")
    parser.add_argument("--keep-artifacts", action="store_true",
                        help="保留每项隔离目录里的 build/（默认跑完即删，只留 out/ 证据）")
    args = parser.parse_args(argv)

    if args.audit:
        return audit()

    timings = load_timings()
    if args.files:
        paths = args.files
    elif args.base:
        paths = changed_from_base(args.base)
    elif args.full:
        paths = []
    else:
        args.worktree = True
        paths = changed_from_worktree()

    if args.full:
        sel = Selection()
        sel.changed = []
        for test_id in ALL_IDS:
            sel.add(test_id, "full", "--full：发版前全量", "")
    else:
        sel = select(paths)

    if args.json:
        print(as_json(sel, timings))
    else:
        print(render(sel, args, timings))

    selected = [sel.items[key] for key in ALL_IDS if key in sel.items]
    if args.dry_run:
        return 0
    if not selected:
        return 0
    return run_selection(selected, timings, args.keep_going,
                         keep_artifacts=args.keep_artifacts)


if __name__ == "__main__":
    sys.exit(main())
