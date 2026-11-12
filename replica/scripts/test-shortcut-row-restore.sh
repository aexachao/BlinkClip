#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$ARTIFACT_TASK_DIR/out"
test_root="$ARTIFACT_TASK_DIR/build/harness"
mkdir -p "$test_root"
source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_ui > "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
compile_native_test_harness shortcut-row-restore "$replica_root/Sources/BlinkClip/UI/SettingsShortcutRowRestore.swift" "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" "$replica_root/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift" "$replica_root/Tests/Native/ShortcutRowRestoreHarness.swift" > "$ARTIFACT_TASK_DIR/out/compile.log" 2>&1
"$test_harness" | tee "$ARTIFACT_TASK_DIR/out/test.log"
