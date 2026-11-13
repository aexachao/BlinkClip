#!/bin/bash
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"
architecture="${2:-universal}"
if [[ -n "${ARTIFACT_TASK_DIR:-}" ]]; then
  scratch_root="${BLINKCLIP_BUILD_ROOT:-$ARTIFACT_TASK_DIR/build/swiftpm}"
  output_root="${BLINKCLIP_APP_OUTPUT_DIR:-$ARTIFACT_TASK_DIR/out}"
else
  # Preserve the hosted CI layout when storage-guard is not present.
  scratch_root="${BLINKCLIP_BUILD_ROOT:-$replica_root/.build}"
  output_root="${BLINKCLIP_APP_OUTPUT_DIR:-$replica_root/dist}"
fi
build_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
if (( ${build_sdk_version%%.*} < 26 )); then
  printf '%s\n' "当前 macOS SDK 为 ${build_sdk_version}；要匹配 macOS 26 的原生控件外观，请使用 Xcode 26 或更新版本构建。" >&2
fi
case "$configuration" in release|debug) ;; *) printf '%s\n' '配置必须为 release 或 debug。' >&2; exit 1 ;; esac
case "$architecture" in native|arm64|x86_64|universal) ;; *) printf '%s\n' '架构必须为 native、arm64、x86_64 或 universal。' >&2; exit 1 ;; esac
# Hardened Runtime 下发送 Apple Events（Finder 选区）所需的最小授权；文件头有取舍说明。
base_entitlements="$replica_root/Assets/BlinkClip.entitlements"
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$replica_root/../package.json")"
if [[ ! "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-dev\.([0-9]+))?$ ]]; then
  printf '%s\n' 'package.json version 必须为 major.minor.patch 或 major.minor.patch-dev.N。' >&2
  exit 1
fi
short_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
build_version="$short_version"
if [[ -n "${BASH_REMATCH[5]}" ]]; then
  build_version="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[5]}"
fi
build_architecture() {
  swift build --package-path "$replica_root" -c "$configuration" --jobs 2 \
    --scratch-path "$scratch_root/architectures/$1" --arch "$1"
}
architecture_binary_root() {
  swift build --package-path "$replica_root" -c "$configuration" \
    --scratch-path "$scratch_root/architectures/$1" --arch "$1" --show-bin-path
}
if [[ "$architecture" == native ]]; then
  swift build --package-path "$replica_root" --scratch-path "$scratch_root" -c "$configuration" --jobs 2
  binary_root="$(swift build --package-path "$replica_root" --scratch-path "$scratch_root" -c "$configuration" --show-bin-path)"
elif [[ "$architecture" == universal ]]; then
  build_architecture arm64
  build_architecture x86_64
  binary_root="$(architecture_binary_root arm64)"
  intel_binary_root="$(architecture_binary_root x86_64)"
  diff -rq "$binary_root/BlinkClip_BlinkClipCore.bundle" "$intel_binary_root/BlinkClip_BlinkClipCore.bundle"
else
  build_architecture "$architecture"
  binary_root="$(architecture_binary_root "$architecture")"
fi
install_executable() {
  if [[ "$architecture" == universal ]]; then
    lipo -create "$binary_root/$1" "$intel_binary_root/$1" -output "$2"
    lipo "$2" -verify_arch arm64 x86_64
  else
    cp "$binary_root/$1" "$2"
  fi
  install_name_tool -add_rpath "${3:-@executable_path/../Frameworks}" "$2"
}
mkdir -p "$output_root"
staging="$(mktemp -d "$output_root/.blinkclip-build.XXXXXX")"
# 清理用 EXIT trap 必须保留真实退出码：bash 3.2 下 `set -e` + ${VAR:?} 中止时，
# trap 里读到的 $? 是 0，只有真正走到脚本末尾（build_complete=1）才算成功。
trap 'rc=$?; rm -rf "$staging"; if [[ "$rc" -eq 0 && "${build_complete:-0}" != 1 ]]; then rc=1; fi; exit "$rc"' EXIT
bundle="$staging/BlinkClip.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
mkdir -p "$bundle/Contents/Frameworks"
# Preserve Sparkle's symlinks, signed helpers, and both architecture slices.
ditto "$binary_root/Sparkle.framework" "$bundle/Contents/Frameworks/Sparkle.framework"
install_executable BlinkClip "$bundle/Contents/MacOS/BlinkClip"
install_executable blinkclip-mcp "$bundle/Contents/MacOS/blinkclip-mcp"
codesign --force --sign - "$bundle/Contents/MacOS/blinkclip-mcp"
cp "$replica_root/Assets/Sparkle-LICENSE.txt" "$bundle/Contents/Resources/Sparkle-LICENSE.txt"
cp "$replica_root/Assets/capcap-LICENSE.txt" "$bundle/Contents/Resources/capcap-LICENSE.txt"
cp "$replica_root/Assets/BlinkClipAppIcon.icns" "$bundle/Contents/Resources/BlinkClipAppIcon.icns"
ditto "$binary_root/BlinkClip_BlinkClipCore.bundle" "$bundle/Contents/Resources/BlinkClip_BlinkClipCore.bundle"
# Fail closed if a stale build reintroduces extracted artwork or language tables.
python3 - "$bundle/Contents/Resources/BlinkClip_BlinkClipCore.bundle" <<'OWNED_RESOURCES'
from pathlib import Path
import struct, sys
core = Path(sys.argv[1])
files = [p for p in core.rglob("*") if p.is_file()]
illustrations = {
    "BlinkClipDirectPaste@2x.png": (384, 256),
    "BlinkClipCopyToClipboard@2x.png": (384, 256),
    "BlinkClipPermissions@2x.png": (480, 288),
}
for p in files:
    owned_image = p.name in illustrations and p.relative_to(core).parts in {(p.name,), ("GeneratedIllustrations", p.name)}
    assert p.name == "Info.plist" or owned_image or (p.name in {"Localizable.strings", "Localizable.stringsdict"} and p.parent.name.lower() in {"en.lproj", "zh-hans.lproj"}), f"Unexpected Core resource: {p}"
for name, size in illustrations.items():
    matches = [p for p in files if p.name == name]
    assert len(matches) == 1, f"Missing or duplicate owned illustration: {name}"
    header = matches[0].read_bytes()[:24]
    assert header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR" and struct.unpack(">II", header[16:24]) == size, f"Invalid owned illustration: {name}"
for language in ("en", "zh-hans"):
    for name in ("Localizable.strings", "Localizable.stringsdict"):
        assert (core / (language + ".lproj") / name).is_file(), f"Missing owned resource: {language}/{name}"
OWNED_RESOURCES
ditto "$replica_root/Vendor/capcap/Resources/zh-Hans.lproj" "$bundle/Contents/Resources/zh-Hans.lproj"
ditto "$replica_root/Vendor/capcap/Resources/en.lproj" "$bundle/Contents/Resources/en.lproj"
helper="$bundle/Contents/Library/LoginItems/BlinkClip Helper.app"
mkdir -p "$helper/Contents/MacOS"
install_executable BlinkClipHelper "$helper/Contents/MacOS/BlinkClipHelper" '@executable_path/../../../../../Frameworks'
cat > "$helper/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.chrisli.blinkclip.helper</string>
<key>CFBundleName</key><string>BlinkClip Helper</string>
<key>CFBundleExecutable</key><string>BlinkClipHelper</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$short_version</string>
<key>CFBundleVersion</key><string>$build_version</string>
<key>BlinkClipSourceVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
plutil -lint "$helper/Contents/Info.plist"
codesign --force --sign - "$helper"
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.chrisli.blinkclip</string>
<key>CFBundleName</key><string>BlinkClip</string>
<key>CFBundleDisplayName</key><string>BlinkClip</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>LSHasLocalizedDisplayName</key><true/>
<key>CFBundleIconFile</key><string>BlinkClipAppIcon</string>
<key>CFBundleExecutable</key><string>BlinkClip</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$short_version</string>
<key>CFBundleVersion</key><string>$build_version</string>
<key>BlinkClipSourceVersion</key><string>$version</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>BlinkClip needs screen access to capture a region or display and save it to your history.</string>
<key>NSAppleEventsUsageDescription</key><string>BlinkClip needs to control Finder to read the files you have selected, so it can pin or capture them.</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>UIDesignRequiresCompatibility</key><false/>
</dict></plist>
PLIST
plutil -lint "$bundle/Contents/Info.plist"
cat > "$bundle/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleName" = "闪贴";
"CFBundleDisplayName" = "闪贴";
"NSScreenCaptureUsageDescription" = "闪贴需要读取屏幕内容，用于截取您选择的区域或整个屏幕并保存到历史。";
"NSAppleEventsUsageDescription" = "闪贴需要控制 Finder 以读取您选中的文件，用于固定或截图。";
STRINGS
cat > "$bundle/Contents/Resources/en.lproj/InfoPlist.strings" <<'STRINGS'
"CFBundleName" = "BlinkClip";
"CFBundleDisplayName" = "BlinkClip";
"NSScreenCaptureUsageDescription" = "BlinkClip needs screen access to capture a region or display and save it to your history.";
"NSAppleEventsUsageDescription" = "BlinkClip needs to control Finder to read the files you have selected, so it can pin or capture them.";
STRINGS
mkdir -p "$bundle/Contents/Resources/zh-Hant.lproj"
cp "$bundle/Contents/Resources/zh-Hans.lproj/InfoPlist.strings" "$bundle/Contents/Resources/zh-Hant.lproj/InfoPlist.strings"
# Static App Intents metadata resolves in the main bundle, alongside capture localization.
cat >> "$bundle/Contents/Resources/zh-Hans.lproj/Localizable.strings" <<'STRINGS'

"BlinkClip" = "闪贴";
"Create BlinkClip Item" = "创建闪贴项目";
"Get BlinkClip Item at Index" = "获取指定位置的闪贴项目";
"Get Latest BlinkClip Item" = "获取最新闪贴项目";
"BlinkClip Item Type" = "闪贴项目类型";
"Create BlinkClip" = "创建闪贴分组";
STRINGS
plutil -insert SUFeedURL -string 'https://github.com/aexachao/BlinkClip/releases/latest/download/appcast.xml' "$bundle/Contents/Info.plist"
plutil -insert SUPublicEDKey -string "$(tr -d '\r\n' < "$replica_root/Assets/UpdatePublicKey.txt")" "$bundle/Contents/Info.plist"
plutil -insert SURequireSignedFeed -bool YES "$bundle/Contents/Info.plist"
plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$bundle/Contents/Info.plist"
plutil -insert SUEnableAutomaticChecks -bool NO "$bundle/Contents/Info.plist"
plutil -insert SUAutomaticallyUpdate -bool NO "$bundle/Contents/Info.plist"
plutil -insert SUSendProfileInfo -bool NO "$bundle/Contents/Info.plist"
# Use the selected compiler's back-deployment libraries for all bundled executables.
mkdir -p "$bundle/Contents/Frameworks"
xcrun swift-stdlib-tool --copy --scan-folder "$bundle/Contents" --platform macosx \
  --destination "$bundle/Contents/Frameworks" --sign "${BLINKCLIP_SIGNING_IDENTITY:--}"
if [[ -n "${BLINKCLIP_CLOUDKIT_PROFILE:-}${BLINKCLIP_CLOUDKIT_CONTAINER:-}" ]]; then
  : "${BLINKCLIP_CLOUDKIT_PROFILE:?需要自有描述文件路径}"
  : "${BLINKCLIP_CLOUDKIT_CONTAINER:?需要自有 CloudKit 容器标识}"
  : "${BLINKCLIP_SIGNING_IDENTITY:?需要本机有效 Apple 签名身份}"
  python3 "$replica_root/scripts/configure-cloudkit-signing.py" \
    --profile "$BLINKCLIP_CLOUDKIT_PROFILE" --bundle "$bundle" --container "$BLINKCLIP_CLOUDKIT_CONTAINER" \
    --environment "${BLINKCLIP_CLOUDKIT_ENVIRONMENT:-Development}" --output "$staging/cloudkit-entitlements.plist"
  # 合并基础授权与 CloudKit 授权再签名：CloudKit 键来自描述文件，必须逐字保留，
  # 因此冲突时描述文件优先，基础键（apple-events）作为底层叠加，两边键集不同不会互相覆盖。
  python3 - "$base_entitlements" "$staging/cloudkit-entitlements.plist" "$staging/signed-entitlements.plist" <<'MERGE_ENTITLEMENTS'
import plistlib, sys
from pathlib import Path
base_path, cloudkit_path, output_path = (Path(argument) for argument in sys.argv[1:4])
base = plistlib.loads(base_path.read_bytes())
cloudkit = plistlib.loads(cloudkit_path.read_bytes())
overlap = sorted(set(base) & set(cloudkit))
# 同一个键出现两套取值时不做猜测：先让人确认，避免静默丢掉 Apple Events 或 CloudKit 授权。
if overlap:
    raise SystemExit("基础与 CloudKit 授权存在重复键，需人工确认：" + ", ".join(overlap))
merged = {**base, **cloudkit}
for key in ("com.apple.security.automation.apple-events", "com.apple.developer.icloud-services"):
    if key not in merged:
        raise SystemExit("合并后的授权缺少 " + key)
if "com.apple.security.app-sandbox" in merged:
    raise SystemExit("合并后的授权不应包含 App Sandbox")
output_path.write_bytes(plistlib.dumps(merged))
MERGE_ENTITLEMENTS
  python3 "$replica_root/scripts/sign-app.py" "$bundle" --identity "$BLINKCLIP_SIGNING_IDENTITY" \
    --entitlements "$staging/signed-entitlements.plist"
else
  if [[ -n "${BLINKCLIP_SIGNING_IDENTITY:-}" && "$BLINKCLIP_SIGNING_IDENTITY" != - ]]; then
    case "$BLINKCLIP_SIGNING_IDENTITY" in
      *"Developer ID Application"*) ;;
      *) printf '%s\n' "提示：${BLINKCLIP_SIGNING_IDENTITY} 不是 Developer ID Application 身份。系统权限（辅助功能、跨应用发送事件、屏幕录制）按代码签名要求判定，换证书或重建后可能又要授权一次；正式分发请使用 Developer ID Application 身份。详见 docs/APP_UPDATES.md。" >&2 ;;
    esac
    python3 "$replica_root/scripts/sign-app.py" "$bundle" --identity "$BLINKCLIP_SIGNING_IDENTITY" \
      --entitlements "$base_entitlements"
  else
    # ad-hoc 构建不开 Hardened Runtime，Finder 自动化不需要授权即可用；
    # Info.plist 的用途说明仍然生效，因此本地构建照旧成功、照旧能弹 TCC 提示。
    # ad-hoc 的 designated requirement 是 cdhash，每次重建都会变，TCC 里的旧授权永远对不上。
    printf '%s\n' "提示：未提供 BLINKCLIP_SIGNING_IDENTITY，本次为 ad-hoc 签名。ad-hoc 的代码要求绑定 cdhash，重建后系统权限需重新授权；如需授权可跨更新保留，请设置稳定且固定的 Developer ID Application 身份。详见 docs/APP_UPDATES.md。" >&2
    codesign --force --sign - "$bundle"
  fi
fi
codesign --verify --deep --strict "$bundle"
if [[ -e "$output_root/BlinkClip.app" ]]; then
  backup="$output_root/backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup"
  mv "$output_root/BlinkClip.app" "$backup/BlinkClip.app"
fi
mv "$bundle" "$output_root/BlinkClip.app"
printf '%s\n' "$output_root/BlinkClip.app"
build_complete=1
