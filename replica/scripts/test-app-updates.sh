#!/bin/bash
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/blinkclip-app-updates.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_core
compile_native_test_harness app-updates \
  "$replica_root/Sources/BlinkClip/UI/ReplicaBrand.swift" \
  "$replica_root/Sources/BlinkClip/UI/BlinkClipAboutWindowController.swift" \
  "$replica_root/Tests/Native/AppUpdateHarness.swift"
test_app="$(dirname "$(dirname "$(dirname "$test_harness")")")"
plutil -insert BlinkClipSourceVersion -string '1.0.5-dev.2' "$test_app/Contents/Info.plist" >/dev/null
plutil -insert CFBundleShortVersionString -string '1.0.5' "$test_app/Contents/Info.plist" >/dev/null
if [[ "${1:-}" == --preview ]]; then
  printf 'PREVIEW_APP=%s\n' "$test_app"
fi
"$test_harness" "$@"
