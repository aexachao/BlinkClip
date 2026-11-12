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
prepare_native_test_ui > "$ARTIFACT_TASK_DIR/out/reset-build.log" 2>&1
compile_native_test_harness settings-shortcut-reset "$replica_root/Sources/BlinkClip/UI/SettingsShortcutReset.swift" "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" "$replica_root/Tests/Native/SettingsShortcutResetHarness.swift" > "$ARTIFACT_TASK_DIR/out/reset-compile.log" 2>&1
for run in 1 2 3; do
  "$test_harness" | tee "$ARTIFACT_TASK_DIR/out/reset-test-$run.log"
done
