#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
core="$replica_root/Sources/BlinkClipCore"
mkdir -p "$ARTIFACT_TASK_DIR/build/module-cache" "$ARTIFACT_TASK_DIR/out"
export TMPDIR="$ARTIFACT_TASK_DIR/build/"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
bundle="$ARTIFACT_TASK_DIR/build/BlinkClip_BlinkClipCore.bundle"
mkdir -p "$bundle"
cp -R "$core/BlinkClipResources/en.lproj" "$core/BlinkClipResources/zh-Hans.lproj" "$bundle/"
cp "$core/BlinkClipResources/GeneratedIllustrations/"*.png "$bundle/"
printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleDevelopmentRegion</key><string>en</string></dict></plist>' > "$bundle/Info.plist"
sources=("$core/AppBrand.swift" "$core/ResourceBundle.swift" "$core/SettingsLocalization.swift" "$core/SearchLocalization.swift" "$core/PreviewLocalization.swift" "$core/UnavailablePreviewLocalization.swift" "$core/ShortcutMessages.swift" "$core/BlinkClipAssetRenderer.swift" "$core/SettingsIllustrations.swift" "$replica_root/Tests/Native/BlinkClipOwnedResourcesHarness.swift")
shasum -a 256 "${sources[@]}" "$core"/BlinkClipResources/*/* "$replica_root/Package.swift" "$replica_root/scripts/build-app.sh" "$replica_root/Assets/capcap-LICENSE.txt" > "$ARTIFACT_TASK_DIR/out/inputs.sha256"
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" -module-cache-path "$CLANG_MODULE_CACHE_PATH" "${sources[@]}" -o "$ARTIFACT_TASK_DIR/build/harness" > "$ARTIFACT_TASK_DIR/out/compile.log" 2>&1
for language in fr ja en zh-Hans zh-Hant; do
 "$ARTIFACT_TASK_DIR/build/harness" "$language" "$ARTIFACT_TASK_DIR/out" -AppleLanguages "($language)" | tee "$ARTIFACT_TASK_DIR/out/$language.log"
done
python3 - "$replica_root" "$ARTIFACT_TASK_DIR/out" <<'PY'
from pathlib import Path
import hashlib,json,sys,subprocess,shutil
r,o=map(Path,sys.argv[1:]);c=r/'Sources/BlinkClipCore'
checks={}
for language in ['en','zh-Hans']:
 for name in ['Localizable.strings','Localizable.stringsdict']:
  checks[f'owned-{language}-{name}']=(c/'BlinkClipResources'/f'{language}.lproj'/name).read_bytes()==(r.parent/'branding/BlinkClipLocalization'/f'{language}.lproj'/name).read_bytes()
renderer=(c/'BlinkClipAssetRenderer.swift').read_text()
start=renderer.index('    // BEGIN_GENERATED_ILLUSTRATIONS:')
end=renderer.index('    // END_GENERATED_ILLUSTRATIONS\n',start)+len('    // END_GENERATED_ILLUSTRATIONS\n')
fallback=renderer[:start]+renderer[end:]
fallback=fallback.replace('        if let image = generatedIllustration(directPaste ? "BlinkClipDirectPaste@2x" : "BlinkClipCopyToClipboard@2x", size: .init(width: 192, height: 128)) { return image }\n','').replace('        if let image = generatedIllustration("BlinkClipPermissions@2x", size: .init(width: 240, height: 144)) { return image }\n','')
fallback=fallback.replace('        return NSImage(size: .init(width: 192, height: 128)', '        NSImage(size: .init(width: 192, height: 128)').replace('        return NSImage(size:.init(width:240,height:144)', '        NSImage(size:.init(width:240,height:144)')
checks['vector-fallback-source-preserved']=fallback==(r.parent/'branding/BlinkClipAssets/BlinkClipAssetRenderer.swift').read_text()
for name in ['BlinkClipDirectPaste@2x.png','BlinkClipCopyToClipboard@2x.png','BlinkClipPermissions@2x.png']:
 checks['generated-source-'+name]=(c/'BlinkClipResources/GeneratedIllustrations'/name).read_bytes()==(r.parent/'branding/BlinkClipGeneratedAssets/Resources'/name).read_bytes()
checks['capcap-license']=(r/'Assets/capcap-LICENSE.txt').read_bytes()==(r/'Vendor/capcap/LICENSE').read_bytes()
package=(r/'Package.swift').read_text()
checks['old-resources-excluded']='resources: [.process("BlinkClipResources")]' in package and 'OriginalStackIcons.bundle' not in package
checks['permission-owned-image']='BlinkClipAssetRenderer.permission(dark: colorScheme == .dark)' in (r/'Sources/BlinkClip/UI/AccessibilityModals.swift').read_text()
checks['old-image-reference-removed']='BlinkClipOtherApps@2x' not in (r/'Sources/BlinkClip/UI/AccessibilityModals.swift').read_text()
checks['build-resource-guard']='Unexpected Core resource:' in (r/'scripts/build-app.sh').read_text()
# Execute the production packaging guard itself against fresh and stale bundles.
guard=(r/'scripts/build-app.sh').read_text().split("<<'OWNED_RESOURCES'\n",1)[1].split('\nOWNED_RESOURCES',1)[0]
fixture=o.parent/'build'/'guard-fixture.bundle'
shutil.copytree(c/'BlinkClipResources',fixture)
checks['packaging-accepts-owned']=subprocess.run([sys.executable,'-c',guard,str(fixture)],capture_output=True).returncode==0
for relative in ['OriginalSettingsCopyToAppLight@2x.png','OriginalStackIcons.bundle/Contents/Resources/icon.file.png','fr.lproj/Localizable.strings','Assets.car','BlinkClipOtherApps@2x.png']:
 stale=fixture/relative
 stale.parent.mkdir(parents=True,exist_ok=True);stale.write_text('stale')
 result=subprocess.run([sys.executable,'-c',guard,str(fixture)],capture_output=True,text=True)
 checks['packaging-rejects-'+relative]=result.returncode!=0 and 'Unexpected Core resource:' in result.stderr
 stale.unlink()

for name in ['BlinkClipDirectPaste@2x.png','BlinkClipCopyToClipboard@2x.png','BlinkClipPermissions@2x.png']:
 owned=fixture/'GeneratedIllustrations'/name
 contents=owned.read_bytes(); owned.unlink()
 checks['packaging-rejects-missing-'+name]=subprocess.run([sys.executable,'-c',guard,str(fixture)],capture_output=True).returncode!=0
 owned.write_bytes(contents)
 duplicate=fixture/name; duplicate.write_bytes(contents)
 checks['packaging-rejects-duplicate-'+name]=subprocess.run([sys.executable,'-c',guard,str(fixture)],capture_output=True).returncode!=0
 duplicate.unlink()
 owned.write_bytes(b'not a png')
 checks['packaging-rejects-corrupt-'+name]=subprocess.run([sys.executable,'-c',guard,str(fixture)],capture_output=True).returncode!=0
 owned.write_bytes(contents)

checks['sparkle-license-retained']='Sparkle-LICENSE.txt' in (r/'scripts/build-app.sh').read_text()
(o/'source-wiring.json').write_text(json.dumps({'passed':all(checks.values()),'checks':checks},indent=2)+'\n')
assert all(checks.values()),checks
print(f'Source wiring: {len(checks)} checks passed')
PY
