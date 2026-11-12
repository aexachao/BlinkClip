#!/bin/bash
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "${BLINKCLIP_BUILD_ROOT:-}" ]]; then
  scratch_root="$BLINKCLIP_BUILD_ROOT"
elif [[ -n "${ARTIFACT_TASK_DIR:-}" ]]; then
  scratch_root="$ARTIFACT_TASK_DIR/build/swiftpm"
else
  # Keep the hosted CI cache layout when no managed task is present.
  scratch_root="$replica_root/.build"
fi
mkdir -p "$scratch_root/sparkle-tools"
tools_root="$(cd "$scratch_root/sparkle-tools" && pwd)"
tools="$tools_root/2.10.1"
if [[ ! -x "$tools/bin/sign_update" ]]; then
  temporary="$(mktemp -d "$tools_root/.download.XXXXXX")"
  cleanup() {
    result=$?
    if [[ "$temporary" == "$tools_root"/.download.* && -d "$temporary" && ! -L "$temporary" ]]; then
      rm -rf -- "$temporary"
    fi
    return "$result"
  }
  trap cleanup EXIT
  curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
    'https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz' \
    -o "$temporary/sparkle.tar.xz"
  printf '%s  %s\n' '1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27' \
    "$temporary/sparkle.tar.xz" | shasum -a 256 --check >&2
  tar -xf "$temporary/sparkle.tar.xz" -C "$temporary" bin/sign_update
  mkdir -p "$tools/bin"
  mv "$temporary/bin/sign_update" "$tools/bin/sign_update"
fi
printf '%s\n' "$tools/bin/sign_update"
