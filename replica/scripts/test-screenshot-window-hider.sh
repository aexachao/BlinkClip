#!/bin/bash
set -euo pipefail
if [[ -z "${ARTIFACT_TASK_DIR:-}" ]]; then
  exec "$HOME/dev-artifacts/bin/storage-guard" run --repo blinkclip --task capture-settings-visible -- bash "$0" "$@"
fi
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp/"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$ARTIFACT_TASK_DIR/out"
exec > >(tee "$ARTIFACT_TASK_DIR/out/run.log") 2>&1
xcrun swiftc -parse-as-library -swift-version 5 \
  -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  "$replica_root/Sources/BlinkClip/Screenshot/ScreenshotWindowHider.swift" \
  "$replica_root/Tests/Native/ScreenshotWindowHiderHarness.swift" \
  -o "$ARTIFACT_TASK_DIR/build/window-hider-harness"
"$ARTIFACT_TASK_DIR/build/window-hider-harness" > "$ARTIFACT_TASK_DIR/out/result.json"
cat "$ARTIFACT_TASK_DIR/out/result.json"
du -sh "$ARTIFACT_TASK_DIR"
df -h /System/Volumes/Data
