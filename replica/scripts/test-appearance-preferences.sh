#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
repeat_count="${BLINKCLIP_APPEARANCE_REPEAT_COUNT:-1}"
case "$repeat_count" in 1|3) ;; *) exit 64 ;; esac
mkdir -p "$ARTIFACT_TASK_DIR/build/module-cache" "$ARTIFACT_TASK_DIR/build/tmp" "$ARTIFACT_TASK_DIR/out"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
sources=("$replica_root/Sources/BlinkClip/UI/WindowAppearancePreferenceObservation.swift" "$replica_root/Tests/Native/AppearancePreferenceHarness.swift")
shasum -a 256 "${sources[@]}" "$replica_root/Sources/BlinkClip/UI/ReplicaUIController.swift" "$0" > "$ARTIFACT_TASK_DIR/out/source-sha256.txt"
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$ARTIFACT_TASK_DIR/build/module-cache" "${sources[@]}" -o "$ARTIFACT_TASK_DIR/build/appearance-preference-harness" > "$ARTIFACT_TASK_DIR/out/compile.log" 2>&1
for ((run=1;run<=repeat_count;run++)); do
 out="$ARTIFACT_TASK_DIR/out/run-$run"; mkdir -p "$out"
 "$ARTIFACT_TASK_DIR/build/appearance-preference-harness" "$out" | tee "$out/test.log"
done
xcrun swiftc -frontend -parse "$replica_root/Sources/BlinkClip/UI/ReplicaUIController.swift" > "$ARTIFACT_TASK_DIR/out/controller-parse.log" 2>&1
