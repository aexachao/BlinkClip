#!/bin/bash
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
test_root="$ARTIFACT_TASK_DIR/build/sound-harness"
mkdir -p "$test_root" "$ARTIFACT_TASK_DIR/out"
export BLINKCLIP_TEST_SCRATCH_PATH="$ARTIFACT_TASK_DIR/build/swiftpm"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
source "$replica_root/Tests/Native/build-support.sh"
prepare_native_test_core > "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
compile_native_test_harness sound-effects "$replica_root/Tests/Native/SoundFeedbackMappingHarness.swift" >> "$ARTIFACT_TASK_DIR/out/build.log" 2>&1
run_native_test_harness "$ARTIFACT_TASK_DIR/out/result.json"
# Stack 粘贴在 AppMain 里直连 `AppMain.paste`，不经过 `ReplicaUIController.paste` 的
# `.paste` 声明；一旦调用点漏掉这层包装，Stack 粘贴会悄悄回落到系统 Purr。harness 覆盖
# 了包装后的分类，这里守住调用点本身。
python3 - "$replica_root/Sources/BlinkClip/AppMain.swift" <<'PY'
import pathlib
import sys
source = pathlib.Path(sys.argv[1]).read_text()
start = source.index("stackPasteHotKey.action")
block = source[start:source.index("configureGlobalHotKeys(force: true)", start)]
if "SoundEffects.withFeedback(.paste)" not in block or "self.paste(ids:" not in block:
    raise SystemExit("AppMain's Stack paste call site does not declare .paste feedback")
print("stack-paste: AppMain declares .paste around its direct paste call")
PY
# The packaged product must carry both tones inside the Core bundle; a path outside the
# bundle (or a stale build without them) fails here instead of at the first copy.
app="${BLINKCLIP_APP_PATH:-$replica_root/dist/BlinkClip.app}"
if [[ -d "$app" ]]; then
  for name in CopySound.mp3 PasteSound.mp3; do
    matches="$(find "$app" -type f -name "$name" -print)"
    count="$(printf '%s\n' "$matches" | grep -c . || true)"
    if [[ "$count" != 1 ]]; then
      printf '%s\n' "expected exactly one packaged $name, found ${count}:" >&2
      printf '%s\n' "$matches" >&2
      exit 1
    fi
    printf '%s\n' "packaged: $matches"
  done
else
  printf '%s\n' "skipped product check: $app is not built" >&2
fi
