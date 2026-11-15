#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
repeat_count="${BLINKCLIP_SETTINGS_REPEAT_COUNT:-1}"
case "$repeat_count" in
  1|3) ;;
  *) echo "BLINKCLIP_SETTINGS_REPEAT_COUNT must be 1 or 3" >&2; exit 64 ;;
esac
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$ARTIFACT_TASK_DIR/out"
test_root="$ARTIFACT_TASK_DIR/build/harness"
mkdir -p "$test_root"
source "$replica_root/Tests/Native/build-support.sh"
shasum -a 256 "$replica_root/Sources/BlinkClip/UI/SettingsSplitView.swift" "$replica_root/Sources/BlinkClip/UI/ReplicaUIController.swift" "$replica_root/Sources/BlinkClip/UI/AuxiliaryViews.swift" "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" "$replica_root/Sources/BlinkClip/UI/PermissionStatusView.swift" "$replica_root/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift" "$replica_root/Sources/BlinkClip/UI/CloudKitSyncController.swift" "$replica_root/Sources/BlinkClip/UI/HistoryCapacityControl.swift" "$replica_root/Sources/BlinkClip/UI/BlinkClipInAppUpdater.swift" "$replica_root/Sources/BlinkClip/UI/BlinkClipAboutWindowController.swift" "$replica_root/Tests/Native/SettingsArchitectureHarness.swift" "$replica_root/scripts/test-settings-architecture.sh" "$replica_root/Tests/Native/build-support.sh" > "$ARTIFACT_TASK_DIR/out/source-sha256.txt"
prepare_native_test_ui > "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
compile_native_test_harness shortcut-row-restore "$replica_root/Sources/BlinkClip/UI/SettingsShortcutRowRestore.swift" "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" "$replica_root/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift" "$replica_root/Tests/Native/ShortcutRowRestoreHarness.swift" > "$ARTIFACT_TASK_DIR/out/row-compile.log" 2>&1
"$test_harness" | tee "$ARTIFACT_TASK_DIR/out/row-test.log"
compile_native_test_harness settings-architecture "$replica_root/Sources/BlinkClip/UI/"*.swift "$replica_root/Sources/BlinkClip/PanelShortcutMenu.swift" "$replica_root/Sources/BlinkClip/ICloudDriveSyncController.swift" "$replica_root/Sources/BlinkClip/SourceAppColor.swift" "$replica_root/Sources/BlinkClip/WindowSharingPolicy.swift" "$replica_root/Sources/BlinkClip/BackgroundService.swift" "$replica_root/Tests/Native/SettingsArchitectureHarness.swift" > "$ARTIFACT_TASK_DIR/out/compile.log" 2>&1
for ((run_id=1; run_id<=repeat_count; run_id++)); do
 run_out="$ARTIFACT_TASK_DIR/out/run-$run_id"
 mkdir -p "$run_out"
 skip_screenshots="${BLINKCLIP_SKIP_SCREENSHOTS:-0}"
 if ((run_id > 1)); then skip_screenshots=1; fi
 for language in en zh-Hans zh-Hant; do
  BLINKCLIP_SETTINGS_RUN_ID="$run_id" BLINKCLIP_SKIP_SCREENSHOTS="$skip_screenshots" \
   "$test_harness" "$run_out" -AppleLanguages "($language)" | tee "$run_out/test-$language.log"
 done
 # zh-Hant offscreen renders (six settings pages, light + dark) are collected
 # next to the managed artifacts so the Traditional layout is reviewable.
 render_dir="${BLINKCLIP_SETTINGS_RENDER_DIR:-/tmp/w3-renders}"
 if [[ "$skip_screenshots" != 1 ]]; then
  mkdir -p "$render_dir"
  for png in "$run_out"/zh-Hant-*.png; do
   [[ -e "$png" ]] || continue
   cp "$png" "$render_dir/"
  done
 fi
done
printf '%s\n' "$(ls -1 "${BLINKCLIP_SETTINGS_RENDER_DIR:-/tmp/w3-renders}"/zh-Hant-*.png 2>/dev/null | wc -l | tr -d ' ')" > "$ARTIFACT_TASK_DIR/out/zh-hant-render-count.txt"
cat "$ARTIFACT_TASK_DIR/out/zh-hant-render-count.txt"
compile_native_test_harness settings-shortcut-reset "$replica_root/Sources/BlinkClip/UI/SettingsShortcutReset.swift" "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" "$replica_root/Tests/Native/SettingsShortcutResetHarness.swift" > "$ARTIFACT_TASK_DIR/out/reset-compile.log" 2>&1
"$test_harness" | tee "$ARTIFACT_TASK_DIR/out/reset-test.log"

# 源码门（新布局）：不得退回浅色卡片比页面暗、两种块宽、卡外按钮和页首管理动作。
python3 - "$replica_root" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
ui = root / 'Sources/BlinkClip/UI'
aux = (ui / 'AuxiliaryViews.swift').read_text()
about_source = (ui / 'BlinkClipAboutWindowController.swift').read_text()
ui_controller = (ui / 'ReplicaUIController.swift').read_text()
app_main = (root / 'Sources/BlinkClip/AppMain.swift').read_text()
surface = (ui / 'SettingsSurfaceStyle.swift').read_text()
retention = (ui / 'HistoryCapacityControl.swift').read_text()
permission = (ui / 'PermissionStatusView.swift').read_text()
harness = (root / 'Tests/Native/SettingsArchitectureHarness.swift').read_text()
checks = {
    # 1) 浅色卡片层级：只允许语义层，不再用 primary.opacity 压暗浅色卡片。
    'card-layer-is-semantic': 'Color.primary.opacity(0.035)' not in aux,
    'card-surface-module': 'static func cardBackground(dark: Bool)' in surface and 'NSColor.white' in surface,
    'card-has-1pt-border': '.strokeBorder(SettingsSurfaceStyle.cardBorderColor(dark: colorScheme == .dark)' in aux
                           and 'borderWidth: CGFloat = 1' in surface,
    'caption-above-4.5': 'secondaryTextOpacity: CGFloat = 0.58' in surface,
    # 2) 固定 4 列网格，行列 10pt，第二行末格留空。
    'retention-four-columns': 'static let gridColumns = 4' in retention
                              and 'static let tileSpacing: CGFloat = 10' in retention,
    'retention-single-width-formula': retention.count('gridColumns - 1) * Self.tileSpacing') == 1,
    'retention-no-count-3-row': 'index < 4 ? 0 : 1' not in retention and 'row == 0 ? 4 : 3' not in retention,
    # 3) 六页统一 16pt 顶部节奏，页面**顶部对齐**（上一轮的「装得下就居中」已撤销）：
    #    内边距只在 `SettingsPageMetrics` 写一次，六个分区共用同一个容器；
    #    容器里不得再出现 GeometryReader / minHeight 等于可视高度的居中 frame。
    # 六个分区 + 关于页：内容区一共七页，共用同一个滚动容器与同一份页边距。
    'seven-pages-share-the-scroll-container': aux.count('SettingsPageScroll {') == 7,
    'page-insets-defined-once': aux.count('horizontalInset: CGFloat = 20') == 1
                                and aux.count('topInset: CGFloat = 16') == 1
                                and aux.count('bottomInset: CGFloat = 20') == 1,
    'pages-start-16pt-from-the-top': '.padding(.top, SettingsPageMetrics.topInset)'
                                     in aux
                                     and '.padding(.bottom, SettingsPageMetrics.bottomInset)' in aux,
    'no-page-level-centring': 'frame(minHeight: proxy.size.height, alignment: .center)' not in aux
                              and 'GeometryReader { proxy in' not in aux,
    'no-page-content-max-height-centring': 'frame(maxHeight: .infinity, alignment: .center)' not in aux
                                           and 'frame(minHeight: 0, alignment: .center)' not in aux,
    'no-hardcoded-page-padding': '.padding(.top, 16).padding(.bottom, 20)' not in aux
                                 and '.padding(.vertical, SettingsPageMetrics.verticalInset)' not in aux
                                 and '.padding(.horizontal, 20)' not in aux,
    'six-pages-no-8pt-top': '.padding(.top, 8).padding(.bottom, 20)' not in aux,
    # P7：「自动检查更新」写在 iCloud 之后、提示音之前，且落到 Sparkle 自己的键上。
    'auto-update-row-between-icloud-and-sound': aux.index('ICloudSyncGeneralRow(')
                                                 < aux.index('settings.automatic-updates.toggle')
                                                 < aux.index('settings.sound-effects.title'),
    'auto-update-writes-sparkle-key': 'BlinkClipInAppUpdater.automaticallyChecksForUpdates' in aux
                                      and 'controller.updater.automaticallyChecksForUpdates' in (ui / 'BlinkClipInAppUpdater.swift').read_text(),
    'auto-update-copy-is-trilingual': 'settings.automatic-updates.title' in (ui / 'SettingsCopy.swift').read_text()
                                      and 'settings.automatic-updates.subtitle' in (ui / 'SettingsCopy.swift').read_text(),
    # Z3a：关于是设置页内的第七页（独立关于窗口已移除）。页面只有「检查更新」一个
    # 动作按钮，状态 + 按钮排在链接/许可之上，检查中置灰，没有关闭按钮。
    'about-is-a-settings-page': 'private var about: some View' in aux
                                and 'SettingsAboutPane.tabIndex' in aux
                                and 'case SettingsAboutPane' not in aux,
    'about-window-is-gone': 'NSWindowController' not in about_source
                            and 'showWindow(' not in about_source
                            and 'windowIdentifier' not in about_source
                            and 'about-close' not in aux,
    'about-has-no-close-button': 'closeButton' not in about_source
                                 and 'updates.close' not in about_source
                                 and 'updates.close' not in aux,
    'about-order-status-before-links': aux.index('aboutIdentity') < aux.index('aboutStatusAndAction')
                                       < aux.index('aboutLinks'),
    'about-one-prominent-button': aux.count('about-check-updates') == 1
                                  and '.buttonStyle(.borderedProminent)' in aux
                                  and '.disabled(aboutModel.isChecking)' in aux,
    # 入口接线：应用菜单走 showSettings(initialTab:)，面板/状态栏菜单只发通知，
    # 生产观察者在 ReplicaUIController 里把两者落到同一页。
    'about-entry-paths': 'showSettings(initialTab: SettingsAboutPane.tabIndex)' in app_main
                         and 'aboutController' not in app_main
                         and 'forName: .blinkClipOpenAbout' in ui_controller
                         and 'showSettings(initialTab: SettingsAboutPane.tabIndex)' in ui_controller,
    # 4) AI 页按钮进卡、说明与状态标题对齐、卡片底部同构分隔线。
    'ai-connect-inside-card': (mcp := aux[aux.index('private var mcp: some View'):aux.index('.sheet(isPresented: $showingMCPConfiguration)')])
                              .count('Divider().padding(.vertical, 8)') == 1
                              and mcp.index('Divider().padding(.vertical, 8)') < mcp.index('settings.mcp.connect'),
    'ai-description-indented-to-title': 'SettingsStatusDot.side + SettingsStatusDot.textSpacing' in aux,
    # 5) iCloud 行：状态在标题下方、开关独占右端。
    'icloud-summary-under-title': aux.count('settings.icloud.summary') == 0  # lives in CloudKitSyncController
                                  and 'settings.icloud.summary' in (ui / 'CloudKitSyncController.swift').read_text(),
    'icloud-switch-gap': 'Spacer(minLength: 12)' in (ui / 'CloudKitSyncController.swift').read_text(),
    # 6) 细节：重置入口在页尾并降权；两处开关对齐；状态圆点统一。
    'reset-all-at-bottom': aux.index('settings.reset-all-shortcuts') > aux.index('ScreenshotSettingsCopy.text(.hotKeySectionTitle)'),
    # P4：两个不可撤销动作共用页尾区域策略；清空历史记录用系统红做语义色，
    # 两个动作都走「影响面写进确认弹窗」的同一层（`settingsFooterAction`）。
    'danger-actions-share-footer': aux.count('settingsFooterAction(') >= 3
                                    and 'settingsFooterAction(SettingsCopy.text("general.action.erase-history") + "…",\n                                     identifier: "settings.clear-history", destructive: true)' in aux
                                    and 'settingsFooterAction(SettingsCopy.text("settings.shortcuts.reset-all"),\n                                         identifier: "settings.reset-all-shortcuts")' in aux,
    'clear-history-uses-system-red': 'Color(nsColor: .systemRed)' in aux,
    'clear-history-leaves-the-card': aux.count('general.action.erase-history') == 1
                                     and aux.index('settings.clear-history') > aux.index('HistoryRetentionPicker(')
                                     and 'settings.card' not in aux[aux.index('HistoryRetentionPicker('):aux.index('settings.clear-history')],
    'reset-all-confirmation-names-six': '復原 6 條快捷鍵為預設' in (ui / 'SettingsCopy.swift').read_text()
                                        and 'Restore 6 shortcuts to their defaults' in (ui / 'SettingsCopy.swift').read_text(),
    'clear-history-confirmation-layer': 'makeClearHistoryAlert(count: count)' in (ui / 'ReplicaUIController.swift').read_text()
                                        and 'historyCount(in: store)' in (ui / 'ReplicaUIController.swift').read_text()
                                        and 'clearHistoryConfirmTitle' in (ui / 'SettingsDangerAction.swift').read_text(),
    # P4：刷新入口在卡片标题行（不再是卡片底部那一行）。
    'refresh-in-card-title-row': 'PermissionRefreshControl(model: permissionProvider.model)' in aux
                                 and 'Spacer(minLength: 8)\n                        PermissionRefreshControl' in aux
                                 and 'Button(PermissionCopy.text("刷新状态", "重新整理狀態", "Refresh Status")) { model.refresh() }' not in permission,
    'refresh-has-three-states': all(marker in permission for marker in
                                    ['case idle, refreshing, refreshed', '正在重新整理…', '已重新整理 · %@', 'refreshedLinger']),
    # P4：冲突提示落在正在编辑的那一行下方，指名占用者，并保持录制态。
    'conflict-hint-owns-its-row': 'shortcutRowError(row)' in aux
                                   and 'screenshotShortcutError' not in aux
                                   and 'shortcutConflictMessage(value, excluding: row)' in aux,
    'conflict-names-the-occupant': '此快捷鍵已被「\\(owner)」占用。' in aux,
    'conflict-keeps-recording': 'rejection.pending != nil, case .assigned = state' in (ui / 'ShortcutRecorder.swift').read_text()
                                 and 'model.beginRecording()' in (ui / 'ShortcutRecorder.swift').read_text(),
    # Z3a：关于行不再有「动作行」语义，选中态就是普通的一页（不需要回退补帧）。
    'about-row-selects-a-page': 'aboutReturnTab' not in aux and 'restoreSidebarAfterAbout' not in aux
                                 and 'BlinkClipAboutWindow.present' not in aux
                                 and '.tag(SettingsAboutPane.tabIndex)' in aux,
    'translation-row-centered': 'return settingsRow(topPadding: SettingsRowMetrics.twoLineTop,'
                                 in aux
                                 and 'identifier: "settings.apple-translation.toggle"' in aux,
    'status-dot-shared': 'SettingsStatusDot(level:' in permission and 'SettingsStatusDot(level: executable ? .normal : .problem)' in aux,
    'ai-no-checkmark-icon': '"checkmark.circle"' not in aux and '"exclamationmark.circle"' not in aux,
    # 7) 行内垂直对齐：所有「标题[+说明] + 右侧开关」的行只经一个 `settingsRow`，
    #    对齐靠 `HStack(alignment: .center)`，不靠上下 padding 挪控件。
    'single-row-layout-helper': 'private func settingsRow<Trailing: View>(' in aux
                                and 'HStack(alignment: .center, spacing: 0) {'
                                in aux[aux.index('private func settingsRow<Trailing: View>('):aux.index('private func settingsToggle(')]
                                and 'Spacer(minLength: spacing)' in aux,
    # 7b) 卡片内容垂直居中：行高由「内容 + 上下各一份对称内边距」决定，不再用
    #     `frame(minHeight:)`（内容长高时余量被吃掉，首末行留白一边多一边少）；
    #     卡片里非行的内容段（复选框、页脚说明、按钮行、保留期网格）自带留白，
    #     数值只在 `SettingsCardBlock` 里写一次。
    'settings-rows-pad-symmetrically': 'topPadding: CGFloat,' in aux
                                       and 'bottomPadding: CGFloat,' in aux
                                       and '.padding(.top, topPadding)' in aux
                                       and '.padding(.bottom, bottomPadding)' in aux
                                       and '.frame(minHeight: minHeight)' not in aux
                                       and 'enum SettingsRowMetrics' in aux,
    'card-block-padding-declared': 'enum SettingsCardBlock' in aux
                                   and aux.count('SettingsCardBlock.') >= 5
                                   and 'SettingsCardBlock.tilesTop' in aux,
    'card-centring-is-asserted': 'cardCentring' in harness
                                 and 'assertCardCentring(appearance: appearance)' in harness
                                 and 'delta <= 0.5' in harness,
    'row-controls-go-through-one-toggle': aux.count('labelsHidden().toggleStyle(.switch).controlSize(.mini)') == 1
                                           and aux.count('settingsRowSwitch(title:') >= 3,
    'no-row-vertical-padding-hack': '.padding(.top, 1).padding(.bottom' not in aux
                                    and '.offset(y:' not in aux,
    # 8) 通用页按职责拆成「启动与运行 / 同步与更新 / 声音」三组小标题卡片。
    'general-splits-into-three-groups': aux.count('settings.general.startup-section.title') == 1
                                        and aux.count('settings.general.sync-section.title') == 1
                                        and aux.count('settings.general.sound-section.title') == 1,
    'general-groups-keep-divider-only-inside-a-card': aux[
        aux.index('private var general: some View'):aux.index('/// 「自动检查更新」')].count('Divider()') == 2,
    'general-groups-are-trilingual': all(
        f'"{key}": (' in (ui / 'SettingsCopy.swift').read_text()
        for key in ('settings.general.startup-section.title',
                    'settings.general.sync-section.title',
                    'settings.general.sound-section.title')),
}
failures = {name: value for name, value in checks.items() if not value}
assert not failures, failures
print(f'Layout contract: {len(checks)} source checks passed')
PY
