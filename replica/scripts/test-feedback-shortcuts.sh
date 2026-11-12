#!/bin/bash
set -euo pipefail
if [[ -z "${ARTIFACT_TASK_DIR:-}" ]]; then
  exec "$HOME/dev-artifacts/bin/storage-guard" run --repo blinkclip --task feedback-sound-shortcut -- bash "$0" "$@"
fi
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp/"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
mkdir -p "$TMPDIR" "$ARTIFACT_TASK_DIR/out"
exec > >(tee "$ARTIFACT_TASK_DIR/out/run.log") 2>&1
xcrun swiftc -parse-as-library -swift-version 5 \
  -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  "$replica_root/Tests/Native/FeedbackShortcutHarness.swift" \
  "$replica_root/Vendor/capcap/Adapters/HotkeyManagerStub.swift" \
  "$replica_root/Vendor/capcap/Editor/EditorShortcutRegistry.swift" \
  "$replica_root/Vendor/capcap/Editor/EditorCommandDoubleTap.swift" \
  -o "$ARTIFACT_TASK_DIR/build/feedback-shortcuts"
"$ARTIFACT_TASK_DIR/build/feedback-shortcuts" | tee "$ARTIFACT_TASK_DIR/out/result.json"

xcrun swiftc -parse-as-library -swift-version 5 \
  -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  "$replica_root/Tests/Native/FeedbackSoundHarness.swift" \
  "$replica_root/Sources/BlinkClipCore/SoundEffects.swift" \
  -o "$ARTIFACT_TASK_DIR/build/feedback-sound"
"$ARTIFACT_TASK_DIR/build/feedback-sound" | tee "$ARTIFACT_TASK_DIR/out/sound-result.json"
