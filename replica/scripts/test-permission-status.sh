#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build="$ARTIFACT_TASK_DIR/build"
test_out="$ARTIFACT_TASK_DIR/out"
mkdir -p "$test_build/module-cache" "$test_out"
export CLANG_MODULE_CACHE_PATH="$test_build/module-cache"
export SWIFT_MODULECACHE_PATH="$test_build/module-cache"
target="$(uname -m)-apple-macosx14.0"
sources=("$replica_root/Sources/BlinkClipCore/AccessibilityService.swift" "$replica_root/Sources/BlinkClipCore/PermissionPromptPolicy.swift" "$replica_root/Sources/BlinkClipCore/PermissionStatusSnapshot.swift")
xcrun swiftc -swift-version 5 -target "$target" -module-cache-path "$test_build/module-cache" \
  -emit-library -emit-module -module-name BlinkClipCore "${sources[@]}" \
  -emit-module-path "$test_build/BlinkClipCore.swiftmodule" -o "$test_build/libBlinkClipCore.dylib" > "$test_out/compile.log" 2>&1
xcrun swiftc -parse-as-library -swift-version 5 -target "$target" -module-cache-path "$test_build/module-cache" \
  -I "$test_build" -L "$test_build" -lBlinkClipCore -Xlinker -rpath -Xlinker "$test_build" \
  "$replica_root/Sources/BlinkClip/UI/AccessibilityRequestAction.swift" \
  "$replica_root/Sources/BlinkClip/UI/PermissionStatusProbe.swift" \
  "$replica_root/Sources/BlinkClip/UI/PermissionStatusView.swift" \
  "$replica_root/Sources/BlinkClip/UI/SettingsWindowFocusRestore.swift" \
  "$replica_root/Tests/Native/PermissionStatusHarness.swift" \
  -o "$test_build/permission-status" >> "$test_out/compile.log" 2>&1
shasum -a 256 "${sources[@]}" "$replica_root/Sources/BlinkClip/UI/PermissionStatusView.swift" \
  "$replica_root/Sources/BlinkClip/UI/AccessibilityRequestAction.swift" \
  "$replica_root/Sources/BlinkClip/UI/PermissionStatusProbe.swift" \
  "$replica_root/Sources/BlinkClip/UI/SettingsWindowFocusRestore.swift" "$replica_root/Sources/BlinkClip/AppMain.swift" > "$test_out/production-inputs.sha256"
for language in en zh-Hans; do
  "$test_build/permission-status" "$test_out" -AppleLanguages "($language)" > "$test_out/$language.log" 2>&1
  cat "$test_out/$language.log"
done
