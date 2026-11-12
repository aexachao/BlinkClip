#!/bin/bash
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
test_root="$ARTIFACT_TASK_DIR/build/harness"
mkdir -p "$test_root" "$ARTIFACT_TASK_DIR/out"
export BLINKCLIP_TEST_SCRATCH_PATH="$ARTIFACT_TASK_DIR/build/swiftpm"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_core > "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
compile_native_test_harness pasteboard-write-feedback "$replica_root/Tests/Native/PasteboardWriteFeedbackHarness.swift" >> "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
run_native_test_harness "$ARTIFACT_TASK_DIR/out/result.json"
