#!/bin/bash
# Gate for the capcap → blinkclip identifier rename: the pasteboard skip marker
# and the UserDefaults key migration bridge, both compiled from production source.
set -euo pipefail
if [[ -z "${ARTIFACT_TASK_DIR:-}" ]]; then
  exec "$HOME/dev-artifacts/bin/storage-guard" run --repo blinkclip --task identifier-namespace-migration -- bash "$0" "$@"
fi
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp/"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
mkdir -p "$TMPDIR" "$ARTIFACT_TASK_DIR/out" "$ARTIFACT_TASK_DIR/build"
exec > >(tee "$ARTIFACT_TASK_DIR/out/identifier-namespace.log") 2>&1
xcrun swiftc -parse-as-library -swift-version 5 \
  -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  "$replica_root/Tests/Native/IdentifierNamespaceMigrationHarness.swift" \
  "$replica_root/Vendor/capcap/Capture/ClipboardHistorySkipMarker.swift" \
  "$replica_root/Vendor/capcap/Utilities/BlinkClipIdentifierMigration.swift" \
  -o "$ARTIFACT_TASK_DIR/build/identifier-namespace-migration"
"$ARTIFACT_TASK_DIR/build/identifier-namespace-migration" | tee "$ARTIFACT_TASK_DIR/out/identifier-namespace-result.json"
