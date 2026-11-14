#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run via storage-guard run --repo blinkclip --task settings-localization -- ...}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
test_build="$ARTIFACT_TASK_DIR/build"
test_out="$ARTIFACT_TASK_DIR/out"
mkdir -p "$test_build/tmp" "$test_build/module-cache" "$test_out"
export TMPDIR="$test_build/tmp/"
export CLANG_MODULE_CACHE_PATH="$test_build/module-cache"
export SWIFT_MODULECACHE_PATH="$test_build/module-cache"
sources=("$replica_root/Sources/BlinkClip/UI/ScreenshotSettingsCopy.swift" "$replica_root/Tests/Native/SettingsLocalizationHarness.swift")
shasum -a 256 "${sources[@]}" > "$test_out/production-inputs.sha256"
xcrun swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
  -module-cache-path "$test_build/module-cache" "${sources[@]}" \
  -o "$test_build/settings-localization" > "$test_out/compile.log" 2>&1
languages=(en zh-Hans zh-Hant)
for language in "${languages[@]}"; do
  "$test_build/settings-localization" "$language" "$test_out/$language.json" \
    -AppleLanguages "($language)" > "$test_out/$language.log" 2>&1
  cat "$test_out/$language.log"
done
python3 - "$replica_root" "$test_out" <<'PY'
import json, pathlib, sys
root, out = map(pathlib.Path, sys.argv[1:])
checks = {
    'settings-window-title-provider': 'makeWindow(title: ScreenshotSettingsCopy.text(.settingsWindowTitle)' in (root / 'Sources/BlinkClip/UI/ReplicaUIController.swift').read_text(),
    'recorder-accessibility-provider': '.accessibilityLabel(ScreenshotSettingsCopy.shortcutAccessibilityLabel(for: label))' in (root / 'Sources/BlinkClip/UI/ShortcutRecorder.swift').read_text(),
    'disabled-run-status-provider': 'if arguments.contains("--no-global-hotkey") {\n            ui.hotKeyStatusMessage = ScreenshotSettingsCopy.text(.hotKeysDisabledForRun)' in (root / 'Sources/BlinkClip/AppMain.swift').read_text(),
    'settings-help-consumes-status': '.help(state.hotKeyStatusMessage)' in (root / 'Sources/BlinkClip/UI/AuxiliaryViews.swift').read_text(),
}
(out / 'source-wiring.json').write_text(json.dumps({'passed': all(checks.values()), 'checks': checks}, indent=2) + '\n')
assert all(checks.values()), checks
print(f'Production wiring: {len(checks)} checks passed')
PY

python3 - "$replica_root" "$test_out" <<'PY'
import json, pathlib, sys
root, out = map(pathlib.Path, sys.argv[1:])
languages = ['en', 'zh-Hans', 'zh-Hant']
runs = {language: json.loads((out / f'{language}.json').read_text()) for language in languages}
assert all(run['passed'] for run in runs.values()), {k: v['passed'] for k, v in runs.items()}

def resolved(run):
    return {case['case']: case['value'] for case in run['cases'] if str(case['case']).startswith('resolved.')}

keys = {language: set(run['keys']) for language, run in runs.items()}
assert keys['en'] == keys['zh-Hans'] == keys['zh-Hant'], 'key set differs per language'
resolved_cases = {language: set(resolved(run)) for language, run in runs.items()}
assert resolved_cases['en'] == resolved_cases['zh-Hans'] == resolved_cases['zh-Hant'], 'resolved case set differs per language'
# 每个键在每种语言下都必须解析出真实文案，不能回落成 key 本身。
for language in languages:
    values = resolved(runs[language])
    assert values and len(set(values.values())) > 1, f'{language}: copy collapsed'
    for name, value in values.items():
        assert value and not value.startswith('screenshot.') and not value.startswith('shortcuts.'), f'{language}: {name} fell back to its raw key'
# zh-Hant 的运行必须真的读到了繁体环境（-AppleLanguages），否则三语断言没有意义。
assert runs['zh-Hant']['cases'][0]['value'].lower().startswith('zh-hant'), runs['zh-Hant']['cases'][0]
# 已知差距的看门狗：ScreenshotSettingsCopy 只有一张中文表，zh-Hant 因此与 zh-Hans
# 文案相同。provider 将来补了繁体表，这条会失败，提示把期望值一起更新。
assert runs['zh-Hant']['copyTable'] == 'zh-Hans'
assert resolved(runs['zh-Hant']) == resolved(runs['zh-Hans']), 'zh-Hant settings copy diverged from zh-Hans without updating this test'
assert runs['zh-Hant']['knownGaps'], 'the shared-Chinese-table gap must stay documented'
report = {
    'passed': True,
    'languages': languages,
    'keyCount': len(keys['en']),
    'keySetsIdentical': True,
    'zhHantCopyTable': runs['zh-Hant']['copyTable'],
    'knownGaps': runs['zh-Hant']['knownGaps'],
}
(out / 'three-language-keys.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
print(f"Three-language key parity: {len(keys['en'])} keys resolve in en / zh-Hans / zh-Hant")
PY
