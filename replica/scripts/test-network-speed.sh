#!/bin/bash
# 菜单栏网速的运行时回归：注入假计数器，验证 1 秒采样、关闭后停表、唤醒重置基线、
# utun 优先口径，以及状态栏文字 / tooltip / 图标宽度。纯函数口径在
# `blinkclip-core-tests` 的 network-speed-* 用例里。
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
export SWIFT_MODULECACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$ARTIFACT_TASK_DIR/out"
test_root="$ARTIFACT_TASK_DIR/build/harness"
mkdir -p "$test_root"
source "$replica_root/Tests/Native/build-support.sh"
shasum -a 256 \
  "$replica_root/Sources/BlinkClipCore/NetworkSpeed.swift" \
  "$replica_root/Sources/BlinkClip/UI/NetworkSpeedMonitor.swift" \
  "$replica_root/Sources/BlinkClip/UI/NetworkSpeedStatusItem.swift" \
  "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" \
  "$replica_root/Sources/BlinkClip/UI/ReplicaBrand.swift" \
  "$replica_root/Tests/Native/NetworkSpeedHarness.swift" \
  "$replica_root/scripts/test-network-speed.sh" > "$ARTIFACT_TASK_DIR/out/source-sha256.txt"
prepare_native_test_core > "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
compile_native_test_harness network-speed \
  "$replica_root/Sources/BlinkClip/UI/NetworkSpeedMonitor.swift" \
  "$replica_root/Sources/BlinkClip/UI/NetworkSpeedStatusItem.swift" \
  "$replica_root/Sources/BlinkClip/UI/SettingsCopy.swift" \
  "$replica_root/Sources/BlinkClip/UI/ReplicaBrand.swift" \
  "$replica_root/Tests/Native/NetworkSpeedHarness.swift" \
  > "$ARTIFACT_TASK_DIR/out/compile.log" 2>&1
"$test_harness" "$@" | tee "$ARTIFACT_TASK_DIR/out/test.log"
