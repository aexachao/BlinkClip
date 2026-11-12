#!/bin/bash
set -euo pipefail
if [[ -z "${ARTIFACT_TASK_DIR:-}" ]]; then
  exec "$HOME/dev-artifacts/bin/storage-guard" run --repo blinkclip --task capture-glue -- bash "$0" "$@"
fi
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp/"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
export BLINKCLIP_TEST_CONFIGURATION=release
mkdir -p "$TMPDIR" "$ARTIFACT_TASK_DIR/out"
exec > >(tee "$ARTIFACT_TASK_DIR/out/run.log") 2>&1
source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_core
test_root="$ARTIFACT_TASK_DIR/build/harness"
mkdir -p "$test_root"
source_file="$replica_root/Tests/Native/CaptureIntegrationHarness.swift"
xcrun swiftc -parse-as-library -swift-version 5 -D CAPTURE_BOUNDARY -module-name BlinkClipCapture \
  -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  -emit-library -emit-module -emit-module-path "$test_root/BlinkClipCapture.swiftmodule" \
  "$source_file" "$replica_root/Vendor/capcap/Adapters/ScreenshotSettings.swift" \
  "$replica_root/Vendor/capcap/Adapters/CaptureEntry.swift" \
  "$replica_root/Vendor/capcap/Adapters/HistoryManagerBridge.swift" \
  -o "$test_root/libBlinkClipCapture.dylib"
compile_native_test_harness capture-integration \
  -I "$test_root" -L "$test_root" -lBlinkClipCapture -Xlinker -rpath -Xlinker "$test_root" \
  "$source_file" "$replica_root/Sources/BlinkClip/Screenshot/ScreenshotCoordinator.swift" \
  "$replica_root/Sources/BlinkClip/Screenshot/ScreenshotWindowHider.swift" \
  "$replica_root/Sources/BlinkClip/Screenshot/ScreenshotHistoryBridge.swift" \
  "$replica_root/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift"
# Each invocation needs an empty Store, including repeats inside one guarded task.
export CAPTURE_STORE_ROOT="$ARTIFACT_TASK_DIR/build/store-$(uuidgen)"
"$test_harness" > "$ARTIFACT_TASK_DIR/out/result.json"
cat "$ARTIFACT_TASK_DIR/out/result.json"
du -sh "$ARTIFACT_TASK_DIR"
df -h /System/Volumes/Data
