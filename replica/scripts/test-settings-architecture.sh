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
