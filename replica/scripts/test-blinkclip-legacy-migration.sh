#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run using storage-guard}"
: "${BLINKCLIP_LEGACY_FIXTURE:?Provide the audited read-only fixture directory}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$ARTIFACT_TASK_DIR/build/harness"
mkdir -p "$test_root" "$ARTIFACT_TASK_DIR/out"
# Record source hashes before/after; chmod applies to the new copy only.
python3 - "$BLINKCLIP_LEGACY_FIXTURE" "$ARTIFACT_TASK_DIR/out/fixture-before.json" <<'PY'
import sys,json,hashlib
from pathlib import Path
root=Path(sys.argv[1]);Path(sys.argv[2]).write_text(json.dumps({str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()},sort_keys=True))
PY
ditto "$BLINKCLIP_LEGACY_FIXTURE" "$ARTIFACT_TASK_DIR/build/legacy-fixture-copy"
chmod -R u+w "$ARTIFACT_TASK_DIR/build/legacy-fixture-copy"
source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_core
compile_native_test_harness blinkclip-legacy-migration "$replica_root/Tests/Native/BlinkClipLegacyMigrationHarness.swift"
"$test_harness" "$ARTIFACT_TASK_DIR/build/legacy-fixture-copy" "$ARTIFACT_TASK_DIR/out"
python3 - "$BLINKCLIP_LEGACY_FIXTURE" "$ARTIFACT_TASK_DIR/out/fixture-before.json" <<'PY'
import sys,json,hashlib
from pathlib import Path
root=Path(sys.argv[1]);actual={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()};assert actual==json.loads(Path(sys.argv[2]).read_text());print('READ_ONLY_FIXTURE_UNCHANGED_PASS',len(actual))
PY
