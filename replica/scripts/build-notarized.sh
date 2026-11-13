#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?请通过 storage-guard run --kind release 启动}"
: "${BLINKCLIP_SIGNING_IDENTITY:?需要 Developer ID Application 签名身份}"
: "${BLINKCLIP_NOTARY_PROFILE:?需要 notarytool 钥匙串 profile 名称}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
export PYTHONDONTWRITEBYTECODE=1
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ARTIFACT_TASK_DIR/build/swift-module-cache"
mkdir -p "$TMPDIR"
# Fail before compiling if the certificate or notarization credentials are unavailable.
python3 - <<'PY'
import os, re, subprocess
identity = os.environ['BLINKCLIP_SIGNING_IDENTITY']
identities = subprocess.check_output(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True)
valid = False
for fingerprint, name in re.findall(r'\) ([A-F0-9]{40}) "([^"]+)"', identities):
    if identity in (fingerprint, name) and name.startswith('Developer ID Application:'):
        valid = True
if not valid:
    raise SystemExit('没有找到匹配且有效的 Developer ID Application 证书与私钥')
subprocess.run(['xcrun', 'notarytool', 'history', '--keychain-profile',
                os.environ['BLINKCLIP_NOTARY_PROFILE'], '--output-format', 'json'],
               check=True, stdout=subprocess.DEVNULL)
PY
bash replica/scripts/build-app.sh release universal
python3 replica/scripts/notarize-distribution.py
# These signatures cover the final stapled DMG, so they must be generated last.
if [[ -n "${BLINKCLIP_UPDATE_PRIVATE_KEY:-}" ]]; then
  version="$(python3 -c 'import json; print(json.load(open("package.json"))["version"])')"
  python3 replica/scripts/create-update-feed.py \
    --archive "$ARTIFACT_TASK_DIR/out/release/BlinkClip-$version-macos-universal.dmg" --version "$version"
  python3 - <<'PY'
import json, os
from pathlib import Path
manifest = Path(os.environ['ARTIFACT_TASK_DIR']) / 'out/release/signing-manifest.json'
data = json.loads(manifest.read_text())
data['sparkle_feed_generated'] = True
manifest.write_text(json.dumps(data, indent=2) + '\n')
PY
fi
