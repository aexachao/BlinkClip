#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run via storage-guard}"
repeat_count="${BLINKCLIP_RETENTION_REPEAT_COUNT:-1}"
case "$repeat_count" in 1|3) ;; *) exit 64 ;; esac
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPLICA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
mkdir -p "$ARTIFACT_TASK_DIR/build/module-cache" "$ARTIFACT_TASK_DIR/build/tmp" "$ARTIFACT_TASK_DIR/out"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
test_app="$ARTIFACT_TASK_DIR/build/HistoryRetentionHarness.app"
mkdir -p "$test_app/Contents/MacOS" "$test_app/Contents/Resources"
cp "$REPLICA_DIR/Assets/BlinkClipAppIcon.icns" "$test_app/Contents/Resources/BlinkClipAppIcon.icns"
cat > "$test_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.blinkclip.history-retention.$(uuidgen)</string>
<key>CFBundleExecutable</key><string>harness</string>
<key>CFBundleName</key><string>History Retention Test</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>BlinkClipAppIcon.icns</string>
<key>LSUIElement</key><true/>
<key>UIDesignRequiresCompatibility</key><false/>
</dict></plist>
PLIST
# HistoryRetentionCopy resolves its three languages through BlinkClipCore's
# SettingsStrings, so the harness links a scratch Core module built from the
# shipping sources instead of a copy.
core_sources=("$REPLICA_DIR/Sources/BlinkClipCore/SettingsStrings.swift")
shim="$ARTIFACT_TASK_DIR/build/BundleModuleShim.swift"
printf '%s\n' 'import Foundation' 'extension Bundle { static var module: Bundle { Bundle.main } }' > "$shim"
SOURCES=("$REPLICA_DIR/Sources/BlinkClip/UI/HistoryCapacityControl.swift" "$REPLICA_DIR/Sources/BlinkClip/UI/HistoryRetentionCopy.swift" "$REPLICA_DIR/Sources/BlinkClip/UI/HistoryRetentionSaving.swift" "$REPLICA_DIR/Tests/Native/HistoryRetentionHarness.swift")
shasum -a 256 "${SOURCES[@]}" "${core_sources[@]}" "$REPLICA_DIR/Sources/BlinkClip/UI/AuxiliaryViews.swift" "$REPLICA_DIR/Assets/BlinkClipAppIcon.icns" "$0" > "$ARTIFACT_TASK_DIR/out/source-sha256.txt"
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$ARTIFACT_TASK_DIR/build/module-cache" \
  -emit-library -emit-module -module-name BlinkClipCore "${core_sources[@]}" "$shim" \
  -emit-module-path "$ARTIFACT_TASK_DIR/build/BlinkClipCore.swiftmodule" \
  -o "$ARTIFACT_TASK_DIR/build/libBlinkClipCore.dylib" > "$ARTIFACT_TASK_DIR/out/core-compile.log" 2>&1
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$ARTIFACT_TASK_DIR/build/module-cache" -I "$ARTIFACT_TASK_DIR/build" -L "$ARTIFACT_TASK_DIR/build" -lBlinkClipCore -Xlinker -rpath -Xlinker "$ARTIFACT_TASK_DIR/build" "${SOURCES[@]}" -o "$test_app/Contents/MacOS/harness" 2>&1 | tee "$ARTIFACT_TASK_DIR/out/compile.log"
for ((run=1;run<=repeat_count;run++)); do
 out="$ARTIFACT_TASK_DIR/out/run-$run"; mkdir -p "$out"
 skip="${BLINKCLIP_SKIP_SCREENSHOTS:-0}"; if ((run > 1)); then skip=1; fi
 for language in en zh-Hans; do
  BLINKCLIP_RETENTION_RUN_ID="$run" BLINKCLIP_SKIP_SCREENSHOTS="$skip" "$test_app/Contents/MacOS/harness" "$out" -AppleLanguages "($language)" 2>&1 | tee "$out/test-$language.log"
 done
done
xcrun swiftc -frontend -parse "$REPLICA_DIR/Sources/BlinkClip/UI/AuxiliaryViews.swift" 2>&1 | tee "$ARTIFACT_TASK_DIR/out/auxiliary-parse.log"
