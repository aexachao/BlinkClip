#!/bin/bash
set -euo pipefail
# Invoke through storage-guard; never builds in the repo or reuses old scratch.
: "${ARTIFACT_TASK_DIR:?Run via storage-guard run --repo blinkclip --task translation-bridge -- ...}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build="$ARTIFACT_TASK_DIR/build"
test_out="$ARTIFACT_TASK_DIR/out"
mkdir -p "$test_build/tmp" "$test_build/module-cache" "$test_out"
export TMPDIR="$test_build/tmp/"
export CLANG_MODULE_CACHE_PATH="$test_build/module-cache"
export SWIFT_MODULECACHE_PATH="$test_build/module-cache"
app="$test_build/TranslationIntegration.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
bundle_id="local.blinkclip.translation-integration.$(uuidgen | tr '[:upper:]' '[:lower:]')"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>$bundle_id</string><key>CFBundleExecutable</key><string>harness</string><key>CFBundleName</key><string>TranslationIntegration</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/><key>LSMinimumSystemVersion</key><string>15.0</string></dict></plist>
PLIST
cp -R "$replica_root/Vendor/capcap/Resources/en.lproj" "$app/Contents/Resources/"
cp -R "$replica_root/Vendor/capcap/Resources/zh-Hans.lproj" "$app/Contents/Resources/"
sources=()
# 2026-11 清理说明：原用 `rg --files` 枚举源码，但 ripgrep 不是本仓库声明的依赖（CI/本机均可能未安装），
# 脚本因此在枚举阶段就 127 失败。改用 POSIX find：仓库内 Vendor/capcap 无 .gitignore、无隐藏 .swift 文件，
# `find -type f -name '*.swift' | sort` 与之枚举出的集合相同（87 个文件，见 b3-report.md）。
while IFS= read -r path; do sources+=("$path"); done < <(find "$replica_root/Vendor/capcap" -type f -name '*.swift' | sort)
shasum -a 256 "${sources[@]}" > "$test_out/production-inputs-before.sha256"
printf '%s\n' "bundle_id=$bundle_id" "architecture=$(uname -m)" "sdk=$(xcrun --sdk macosx --show-sdk-version)" > "$test_out/environment.txt"
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx15.0" \
  -module-cache-path "$test_build/module-cache" -Onone \
  "${sources[@]}" "$replica_root/Tests/Native/TranslationIntegrationHarness.swift" \
  -o "$app/Contents/MacOS/harness" > "$test_out/compile.log" 2>&1
codesign --force --sign - "$app" > "$test_out/codesign.log" 2>&1
trap '"$app/Contents/MacOS/harness" cleanup "$test_out/cleanup.json" > "$test_out/cleanup.log" 2>&1 || true' EXIT
python3 - "$app/Contents/MacOS/harness" "$test_out" <<'PY'
import pathlib, subprocess, sys
executable, out = sys.argv[1], pathlib.Path(sys.argv[2])
for mode in ('settings-write', 'settings-read', 'integration'):
    with (out / (mode + '.log')).open('w') as log:
        try:
            result = subprocess.run([executable, mode, str(out / (mode + '.json'))],
                                    stdout=log, stderr=subprocess.STDOUT, timeout=105)
        except subprocess.TimeoutExpired:
            print(f'{mode}: process timeout at 105 seconds; child killed, no completion claimed')
            sys.exit(124)
    print((out / (mode + '.log')).read_text())
    if result.returncode:
        sys.exit(result.returncode)
PY
shasum -a 256 "${sources[@]}" > "$test_out/production-inputs-after.sha256"
cmp "$test_out/production-inputs-before.sha256" "$test_out/production-inputs-after.sha256"
printf 'Production inputs unchanged; no simulator or AVD created.\n' > "$test_out/source-check.txt"
