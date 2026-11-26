#!/bin/bash
set -euo pipefail
# 正式发布路径 fail-closed：没有 CloudKit 三变量的构建会在编译前就退出，
# 不允许再出现「漏设变量 → 无 iCloud 授权的包一路走到 DMG」这种事。
cloudkit_missing=""
for required in BLINKCLIP_CLOUDKIT_PROFILE BLINKCLIP_CLOUDKIT_CONTAINER BLINKCLIP_CLOUDKIT_ENVIRONMENT; do
  if [[ -z "${!required:-}" ]]; then
    cloudkit_missing="${cloudkit_missing:+$cloudkit_missing }$required"
  fi
done
if [[ -n "$cloudkit_missing" ]]; then
  printf 'CloudKit 发布配置缺失：%s\n\n' "$cloudkit_missing" >&2
  cat >&2 <<'MESSAGE'
正式发布必须携带 CloudKit 授权，缺少上面这些变量时不进入编译。三个变量都要设置：

  BLINKCLIP_CLOUDKIT_PROFILE        BlinkClip 自有 Developer ID 描述文件路径（.provisionprofile）
  BLINKCLIP_CLOUDKIT_CONTAINER      iCloud 容器标识，正式值为 iCloud.com.chrisli.blinkclip
  BLINKCLIP_CLOUDKIT_ENVIRONMENT    CloudKit 环境，只能取 Development 或 Production

示例（正式发布用 Production，描述文件路径换成自己本机的）：

  BLINKCLIP_CLOUDKIT_PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile" \
  BLINKCLIP_CLOUDKIT_CONTAINER='iCloud.com.chrisli.blinkclip' \
  BLINKCLIP_CLOUDKIT_ENVIRONMENT='Production' \
  BLINKCLIP_SIGNING_IDENTITY='Developer ID Application: <名字> (<团队 ID>)' \
  BLINKCLIP_NOTARY_PROFILE='BlinkClip-notary' \
  ~/dev-artifacts/bin/storage-guard run --repo BlinkClip --task notarized-release \
    --kind release --release-id com.chrisli.blinkclip@<版本>+<构建号> -- \
    bash replica/scripts/build-notarized.sh

变量来源与描述文件申请见 docs/CLOUDKIT_SETUP.md。
MESSAGE
  exit 2
fi
if [[ ! -f "$BLINKCLIP_CLOUDKIT_PROFILE" || ! -r "$BLINKCLIP_CLOUDKIT_PROFILE" ]]; then
  printf 'BLINKCLIP_CLOUDKIT_PROFILE 指向的描述文件不存在或不可读：%s\n' \
    "$BLINKCLIP_CLOUDKIT_PROFILE" >&2
  exit 2
fi
case "$BLINKCLIP_CLOUDKIT_ENVIRONMENT" in
  Development|Production) ;;
  *)
    printf 'BLINKCLIP_CLOUDKIT_ENVIRONMENT 只能是 Development 或 Production，实际：%s\n' \
      "$BLINKCLIP_CLOUDKIT_ENVIRONMENT" >&2
    exit 2
    ;;
esac
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
# 打包前最后一道：产物必须由当前源码构建。任一不符（指纹、可执行文件 sha256、
# 时间顺序）都会在这里中止，而不是等用户看到「版本号是新的、界面是旧的」。
python3 replica/scripts/source-fingerprint.py verify --app "$ARTIFACT_TASK_DIR/out/BlinkClip.app"
# 公证前再确认一次 CloudKit 授权真的进了产物（描述文件 + 三个 CloudKit 键 + 无调试授权）。
# 编译成功但授权缺失的包在这里中止，不会被公证成「看起来可发布」的成品。
python3 replica/scripts/release-ci.py verify-cloudkit \
  --app "$ARTIFACT_TASK_DIR/out/BlinkClip.app" \
  --container "$BLINKCLIP_CLOUDKIT_CONTAINER" \
  --environment "$BLINKCLIP_CLOUDKIT_ENVIRONMENT"
python3 replica/scripts/notarize-distribution.py
# 把这次发布的源码指纹写进签名清单：事后仅凭 DMG 与清单就能核对它由哪份源码构建，
# 不必再猜「09:16 的包到底是不是 09:05 的源码」。
python3 - <<'PY'
import json, os
from pathlib import Path
task = Path(os.environ['ARTIFACT_TASK_DIR'])
provenance = json.loads((task / 'out/BlinkClip.build-manifest.json').read_text())
signing = task / 'out/release/signing-manifest.json'
data = json.loads(signing.read_text())
data['source_digest'] = provenance['source_digest']
data['source_commit'] = provenance['source_commit']
signing.write_text(json.dumps(data, indent=2) + '\n')
PY
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
# 发版收尾顺手清理旧产物：发版后「记得手工清理」一定会漏，所以放在这里自动做。
# 只保留最近 3 天与最新 5 个任务目录，回收的是上一次及更早的目录——本次发布的
# out/ 是最新的一个，永远在保留集合里，不会删到自己。
# 清理失败不能影响发布退出码：此时产物已经签名、公证、staple 完成，清理只是善后。
if ! bash "$root/scripts/prune-artifacts.sh" --apply --keep-days 3 --quiet; then
  printf '旧产物清理未完成（不影响本次发布）：bash scripts/prune-artifacts.sh --apply --keep-days 3\n' >&2
fi
