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

# Project license and third-party/scope notice are packaged next to the vendored notices,
# and the copy is byte-checked with cmp at build time (fail closed on drift).
build_text=(r/'scripts/build-app.sh').read_text()
checks['project-license-packaged']='cp "$replica_root/../LICENSE" "$bundle/Contents/Resources/LICENSE.txt"' in build_text
checks['project-notice-packaged']='cp "$replica_root/../NOTICE.md" "$bundle/Contents/Resources/NOTICE.txt"' in build_text
checks['packaged-license-compared']=build_text.count('cmp "$replica_root/../LICENSE"')==1 and build_text.count('cmp "$replica_root/../NOTICE.md"')==1
checks['agpl-license-at-repository-root']=(r.parent/'LICENSE').read_text().startswith('                    GNU AFFERO GENERAL PUBLIC LICENSE')
checks['notice-describes-agpl']='GNU Affero General Public License v3.0' in (r.parent/'NOTICE.md').read_text()

# Execute the packaged-resources whitelist (fail closed: any undeclared entry fails).
checks['packaged-resource-guard']="<<'PACKAGED_RESOURCES'" in build_text and 'Unexpected packaged resource:' in build_text
packaged_guard=build_text.split("<<'PACKAGED_RESOURCES'\n",1)[1].split('\nPACKAGED_RESOURCES',1)[0]
def packaged_layout(name):
 fixture=o.parent/'build'/name
 (fixture/'BlinkClip_BlinkClipCore.bundle').mkdir(parents=True)
 (fixture/'BlinkClip_BlinkClipCore.bundle'/'Info.plist').write_text('guard fixture')
 for entry in ['BlinkClipAppIcon.icns','Sparkle-LICENSE.txt','capcap-LICENSE.txt','LICENSE.txt','NOTICE.txt']:
  (fixture/entry).write_text('guard fixture')
 for language,members in {'en.lproj':['InfoPlist.strings','Localizable.strings'],
                          'zh-Hans.lproj':['InfoPlist.strings','Localizable.strings'],
                          'zh-Hant.lproj':['InfoPlist.strings']}.items():
  (fixture/language).mkdir()
  for member in members:
   (fixture/language/member).write_text('guard fixture')
 return fixture
def packaged_guard_result(fixture):
 return subprocess.run([sys.executable,'-c',packaged_guard,str(fixture)],capture_output=True,text=True)
packaged=packaged_layout('packaged-resources-fixture')
accepted=packaged_guard_result(packaged)
checks['packaging-accepts-declared-resources']=accepted.returncode==0
for relative,marker in [('Assets.car','Unexpected packaged resource'),
                        ('fr.lproj/Localizable.strings','Unexpected packaged resource'),
                        ('zh-Hant.lproj/Assets.car','Unexpected packaged resource')]:
 stale=packaged/relative
 stale.parent.mkdir(parents=True,exist_ok=True);stale.write_text('stale')
 result=packaged_guard_result(packaged)
 checks['packaging-resources-reject-'+relative]=result.returncode!=0 and marker in result.stderr
 stale.unlink()
 for directory in ['fr.lproj']:
  leftover=packaged/directory
  if leftover.is_dir() and not any(leftover.iterdir()): leftover.rmdir()
for name in ['LICENSE.txt','NOTICE.txt','capcap-LICENSE.txt','Sparkle-LICENSE.txt']:
 contents=(packaged/name).read_bytes();(packaged/name).unlink()
 result=packaged_guard_result(packaged)
 checks['packaging-resources-reject-missing-'+name]=result.returncode!=0 and 'Missing packaged resource' in result.stderr
 (packaged/name).write_bytes(contents)
shutil.rmtree(packaged/'zh-Hant.lproj')
result=packaged_guard_result(packaged)
checks['packaging-resources-reject-missing-language']=result.returncode!=0 and 'Missing packaged resource' in result.stderr
(o/'source-wiring.json').write_text(json.dumps({'passed':all(checks.values()),'checks':checks},indent=2)+'\n')
assert all(checks.values()),checks
print(f'Source wiring: {len(checks)} checks passed')
PY
