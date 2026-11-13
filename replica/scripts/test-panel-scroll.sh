#!/bin/bash
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/blinkclip-panel-scroll.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
export BLINKCLIP_TEST_CONFIGURATION=release
source "$replica_root/Tests/Native/build-support.sh"
# UI/*.swift 会 import BlinkClipCapture；必须走 prepare_native_test_ui 才会构建该模块。
prepare_native_test_ui
compile_native_test_harness panel-scroll \
  "$replica_root/Sources/BlinkClip/UI/"*.swift \
  "$replica_root/Sources/BlinkClip/ICloudDriveSyncController.swift" \
  "$replica_root/Sources/BlinkClip/SourceAppColor.swift" \
  "$replica_root/Sources/BlinkClip/WindowSharingPolicy.swift" \
  "$replica_root/Sources/BlinkClip/BackgroundService.swift" \
  "$replica_root/Tests/Native/PanelScrollHarness.swift"
run_native_test_harness "$@"
