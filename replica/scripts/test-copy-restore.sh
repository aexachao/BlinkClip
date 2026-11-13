#!/bin/bash
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/blinkclip-copy-restore.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
export BLINKCLIP_TEST_CONFIGURATION=release
export BLINKCLIP_TEST_SCRATCH_PATH="${BLINKCLIP_TEST_SCRATCH_PATH:-$replica_root/.build/copy-restore-regression}"
source "$replica_root/Tests/Native/build-support.sh"
# UI/*.swift 会 import BlinkClipCapture；必须走 prepare_native_test_ui 才会构建该模块。
prepare_native_test_ui
compile_native_test_harness copy-restore \
  "$replica_root/Sources/BlinkClip/UI/"*.swift \
  "$replica_root/Sources/BlinkClip/ICloudDriveSyncController.swift" \
  "$replica_root/Sources/BlinkClip/SourceAppColor.swift" \
  "$replica_root/Sources/BlinkClip/WindowSharingPolicy.swift" \
  "$replica_root/Sources/BlinkClip/BackgroundService.swift" \
  "$replica_root/Tests/Native/CopyRestoreHarness.swift"
run_native_test_harness "$@"
