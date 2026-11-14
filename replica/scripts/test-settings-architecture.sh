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
shasum -a 256 "$replica_root/Sources/BlinkClip/UI/SettingsSplitView.swift" "$replica_root/Sources/BlinkClip/UI/ReplicaUIController.swift" "$replica_root/Sources/BlinkClip/UI/AuxiliaryViews.swift" "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" "$replica_root/Sources/BlinkClip/UI/PermissionStatusView.swift" "$replica_root/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift" "$replica_root/Sources/BlinkClip/UI/CloudKitSyncController.swift" "$replica_root/Sources/BlinkClip/UI/HistoryCapacityControl.swift" "$replica_root/Tests/Native/SettingsArchitectureHarness.swift" "$replica_root/scripts/test-settings-architecture.sh" "$replica_root/Tests/Native/build-support.sh" > "$ARTIFACT_TASK_DIR/out/source-sha256.txt"
prepare_native_test_ui > "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
compile_native_test_harness shortcut-row-restore "$replica_root/Sources/BlinkClip/UI/SettingsShortcutRowRestore.swift" "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" "$replica_root/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift" "$replica_root/Tests/Native/ShortcutRowRestoreHarness.swift" > "$ARTIFACT_TASK_DIR/out/row-compile.log" 2>&1
"$test_harness" | tee "$ARTIFACT_TASK_DIR/out/row-test.log"
compile_native_test_harness settings-architecture "$replica_root/Sources/BlinkClip/UI/"*.swift "$replica_root/Sources/BlinkClip/ICloudDriveSyncController.swift" "$replica_root/Sources/BlinkClip/SourceAppColor.swift" "$replica_root/Sources/BlinkClip/WindowSharingPolicy.swift" "$replica_root/Sources/BlinkClip/BackgroundService.swift" "$replica_root/Tests/Native/SettingsArchitectureHarness.swift" > "$ARTIFACT_TASK_DIR/out/compile.log" 2>&1
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
surface = (ui / 'SettingsSurfaceStyle.swift').read_text()
retention = (ui / 'HistoryCapacityControl.swift').read_text()
permission = (ui / 'PermissionStatusView.swift').read_text()
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
    # 3) 六页统一 16pt 顶部节奏。
    'six-pages-tighten-to-16': aux.count('.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 20)') == 6,
    'six-pages-no-8pt-top': '.padding(.top, 8).padding(.bottom, 20)' not in aux,
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
    'reset-all-link-style': '.buttonStyle(.link)\n                            .accessibilityIdentifier("settings.reset-all-shortcuts")' in aux,
    'translation-row-centered': 'return HStack {\n            VStack(alignment: .leading, spacing: 3) {\n                Text(ScreenshotSettingsCopy.text(.appleTranslationTitle))' in aux,
    'status-dot-shared': 'SettingsStatusDot(level:' in permission and 'SettingsStatusDot(level: executable ? .normal : .problem)' in aux,
    'ai-no-checkmark-icon': '"checkmark.circle"' not in aux and '"exclamationmark.circle"' not in aux,
}
failures = {name: value for name, value in checks.items() if not value}
assert not failures, failures
print(f'Layout contract: {len(checks)} source checks passed')
PY
