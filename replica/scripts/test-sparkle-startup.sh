#!/bin/bash
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/blinkclip-sparkle-startup.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT
architecture="${BLINKCLIP_TEST_ARCHITECTURE:-$(uname -m)}"
app="$test_root/Startup.app"
# 2026-11 清理说明：旧版固定从仓库内 .build/native-regression 取 Sparkle.framework，
# 该目录只有在别处先跑过原生构建时才存在（干净克隆/带 ARTIFACT_TASK_DIR 的回归里必然缺失，
# 脚本 0 秒即失败）。改为在本次隔离 scratch（尊重 ARTIFACT_TASK_DIR / BLINKCLIP_TEST_SCRATCH_PATH）
# 中解析依赖，并直接从 SPM 解包出的 xcframework 取框架。
scratch_root="${BLINKCLIP_TEST_SCRATCH_PATH:-${ARTIFACT_TASK_DIR:+$ARTIFACT_TASK_DIR/build/swiftpm}}"
scratch_root="${scratch_root:-$replica_root/.build/native-regression}"
swift build --package-path "$replica_root" --scratch-path "$scratch_root" \
  -c debug --arch "$architecture" --target BlinkClipCore -j 4 >&2
sparkle_root="$scratch_root/artifacts/replica/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
if [[ ! -d "$sparkle_root/Sparkle.framework" ]]; then
  printf '未找到 Sparkle.framework：%s\n' "$sparkle_root" >&2
  exit 1
fi
binary_root="$(swift build --package-path "$replica_root" --scratch-path "$scratch_root" -c debug --arch "$architecture" --show-bin-path)"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
ditto "$sparkle_root/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
python3 - "$app" "$replica_root" <<'PY'
from pathlib import Path
import plistlib
import sys
import uuid
app, replica = map(Path, sys.argv[1:])
info = {
    'CFBundleIdentifier': 'local.blinkclip.sparkle-startup.' + str(uuid.uuid4()),
    'CFBundleExecutable': 'harness', 'CFBundleName': 'BlinkClip Update Startup Test',
    'CFBundleVersion': '1.0.5', 'CFBundleShortVersionString': '1.0.5',
    'CFBundlePackageType': 'APPL', 'LSUIElement': True,
    'SUFeedURL': 'https://github.com/aexachao/BlinkClip/releases/latest/download/appcast.xml',
    'SUPublicEDKey': (replica / 'Assets/UpdatePublicKey.txt').read_text().strip(),
    'SURequireSignedFeed': True, 'SUVerifyUpdateBeforeExtraction': True,
    'SUEnableAutomaticChecks': False, 'SUAutomaticallyUpdate': False, 'SUSendProfileInfo': False}
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
xcrun swiftc -parse-as-library -swift-version 5 -target "$architecture-apple-macosx14.0" \
  -F "$sparkle_root" -framework Sparkle -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
  "$replica_root/Sources/BlinkClip/UI/BlinkClipInAppUpdater.swift" \
  "$replica_root/Tests/Native/SparkleStartupHarness.swift" -o "$app/Contents/MacOS/harness"
codesign --force --sign - "$app" >&2
"$app/Contents/MacOS/harness"
