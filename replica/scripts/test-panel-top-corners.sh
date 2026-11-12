#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
task_build="$ARTIFACT_TASK_DIR/build"
task_out="$ARTIFACT_TASK_DIR/out"
mkdir -p "$task_build/module-cache" "$task_out"
export CLANG_MODULE_CACHE_PATH="$task_build/module-cache"
target="$(uname -m)-apple-macosx14.0"
include="$replica_root/Sources/BlinkClipObjC/include"
xcrun clang -target "$target" -fobjc-arc -fmodules -fmodules-cache-path="$task_build/module-cache" \
  -I "$include" -c "$replica_root/Sources/BlinkClipObjC/PRPanelGlassBackground.m" \
  -o "$task_build/panel-background.o" > "$task_out/compile.log" 2>&1
xcrun swiftc -parse-as-library -swift-version 5 -target "$target" -module-cache-path "$task_build/module-cache" \
  -I "$include" -Xcc "-fmodule-map-file=$include/module.modulemap" \
  "$replica_root/Sources/BlinkClip/UI/ReplicaPanelGlassBackground.swift" \
  "$replica_root/Tests/Native/PanelTopCornersHarness.swift" "$task_build/panel-background.o" \
  -framework AppKit -framework QuartzCore -o "$task_build/panel-top-corners" >> "$task_out/compile.log" 2>&1
xcrun swiftc -parse "$replica_root/Sources/BlinkClip/UI/PanelViews.swift" > "$task_out/parse.log" 2>&1
shasum -a 256 "$replica_root/Sources/BlinkClip/UI/PanelViews.swift" \
  "$replica_root/Sources/BlinkClip/UI/ReplicaPanelGlassBackground.swift" \
  "$replica_root/Sources/BlinkClipObjC/PRPanelGlassBackground.m" "$include/PRPanelGlassBackground.h" \
  > "$task_out/production-inputs.sha256"
"$task_build/panel-top-corners" "$task_out" > "$task_out/run.log" 2>&1
cat "$task_out/run.log"
