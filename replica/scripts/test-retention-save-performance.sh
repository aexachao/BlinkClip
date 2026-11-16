#!/bin/bash
set -euo pipefail
: "${ARTIFACT_TASK_DIR:?Run through storage-guard}"
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
shipping_root="$replica_root"
dataset_selector="${BLINKCLIP_RETENTION_PERF_DATASET:-all}"
case "$dataset_selector" in all|1024-8mib) ;; *) exit 64 ;; esac
export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
export BLINKCLIP_TEST_CONFIGURATION=release
mkdir -p "$TMPDIR" "$CLANG_MODULE_CACHE_PATH" "$ARTIFACT_TASK_DIR/out"
shasum -a 256 "$shipping_root/Sources/BlinkClipCore/CloudKitGraph.swift" "$shipping_root/Sources/BlinkClipCore/ClipboardStore.swift" "$shipping_root/Sources/BlinkClipCore/ClipboardPersistence.swift" "$shipping_root/Sources/BlinkClipCore/PinboardAttributes.swift" "$shipping_root/Sources/BlinkClip/UI/HistoryRetentionSaving.swift" "$shipping_root/Sources/BlinkClip/UI/AuxiliaryViews.swift" "$shipping_root/Tests/Native/RetentionSavePerformanceHarness.swift" "$shipping_root/scripts/test-retention-save-performance.sh" > "$ARTIFACT_TASK_DIR/out/source-sha256.txt"
python3 - "$shipping_root" "$ARTIFACT_TASK_DIR" <<'PY'
import difflib,hashlib,json,pathlib,re,shutil,sys
root,task=map(pathlib.Path,sys.argv[1:])
current=(root/'Sources/BlinkClipCore/CloudKitGraph.swift').read_text()

# 基线 = 当前源码做「身份索引」的逆操作，只用语义锚点定位（块首注释 + for 头 + 收尾大括号、
# 身份查找那一行），不写行号。原实现把还原结果钉死成一个 sha256：那条哈希同时钉住了整份
# 文件，产品在本文件里做与「身份索引」无关的正常改动（例如 5d45260 的级联所有权修正）
# 之后就无法满足，属于测试腐化。这里改成自动计算的精确差异断言：还原前后的文本差异必须
# 恰好是「删掉一次身份索引块」+「把索引查找还原成线性查找」，强度不变且不再硬编码。
index_block=re.compile(
    r'(?ms)^( *)// Resolve each existing local identity once\..*?^ *for document in existing \{\n.*?^ *\}\n')
indexed_lookup=re.compile(r'(?m)^( *)if let value = identities\[type\]\?\[local\] \{ return value \}\n')
block_matches=list(index_block.finditer(current))
lookup_matches=list(indexed_lookup.finditer(current))
assert len(block_matches)==1,'identity index block must appear exactly once'
assert len(lookup_matches)==1,'indexed identity lookup must appear exactly once'
block=block_matches[0].group(0)
indent=lookup_matches[0].group(1)
linear_lookup=('%sif let value = existing.first(where: { $0.type == type && localID($0) == local })'
               ' { return (value.id, value.scope) }\n') % indent
old=current[:block_matches[0].start()]+current[block_matches[0].end():]
old=old.replace(lookup_matches[0].group(0),linear_lookup,1)

def assert_only_edit(source,target,removed,added,label):
    source_lines=source.splitlines(keepends=True); target_lines=target.splitlines(keepends=True)
    matcher=difflib.SequenceMatcher(None,source_lines,target_lines,autojunk=False)
    ops=[op for op in matcher.get_opcodes() if op[0]!='equal']
    assert ops,label+': inverse surgery changed nothing'
    removed_text=''.join(''.join(source_lines[i1:i2]) for _,i1,i2,_,_ in ops)
    added_text=''.join(''.join(target_lines[j1:j2]) for _,_,_,j1,j2 in ops)
    assert removed_text==removed,label+': unexpected shipping-source difference %r' % removed_text
    assert added_text==added,label+': unexpected baseline difference %r' % added_text
    assert target.count(added)==1,label+': restored statement is not unique in the baseline'

assert_only_edit(current,old,block+lookup_matches[0].group(0),linear_lookup,'identity index inverse surgery')
baseline=task/'build/baseline-package'; (baseline/'Sources').mkdir(parents=True)
for name in ['BlinkClipCore','BlinkClipObjC']: shutil.copytree(root/'Sources'/name,baseline/'Sources'/name)
(baseline/'Sources/BlinkClipCore/CloudKitGraph.swift').write_text(old)
(baseline/'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "BlinkClip", defaultLocalization: "en", platforms: [.macOS(.v14)], targets: [
 .target(name: "BlinkClipObjC", publicHeadersPath: "include"),
 .target(name: "BlinkClipCore", dependencies: ["BlinkClipObjC"], resources: [.process("BlinkClipResources")])])
''')
capture=old[:old.index('    public struct Projection {')]+'}\n'
capture=capture.replace('public enum CloudKitGraph {','enum BaselineCloudKitGraph {',1)
attributes=(root/'Sources/BlinkClipCore/PinboardAttributes.swift').read_text().replace('public enum PinboardAttributes {','enum BaselinePinboardAttributes {',1)
capture=capture.replace('PinboardAttributes.', 'BaselinePinboardAttributes.')
capture='import BlinkClipCore\nprivate let originalItemDataPayloadKey = "com.chrisli.blinkclip.internal.rawPasteboardItems"\n'+capture
(task/'build/BaselineCapture.swift').write_text(capture+'\n'+attributes)
(task/'out/baseline-CloudKitGraph.swift').write_text(old)
(task/'out/source-comparison.json').write_text(json.dumps({'baselineDerivation':'inverse surgery located by semantic anchors; the only text difference from the shipping source is the identity-index block and its lookup statement; no pinned hash','identityBlockRemovedExactlyOnce':True,'linearLookupRestoredExactlyOnce':True,'indexedOnlyIdentityChange':True,'buildMode':'release (-O)','syntheticOnly':True,'baselineGraphSHA256':hashlib.sha256(old.encode()).hexdigest(),'indexedGraphSHA256':hashlib.sha256(current.encode()).hexdigest(),'baselinePackage':'Same Core/ObjC sources and resources with original graph; minimal manifest avoids unrelated UI targets','captureClone':'Exact original capture/localID prefix and pinboard attribute helper; enum names renamed, import and internal key literal added'},indent=2))
PY
source "$shipping_root/Tests/Native/build-support.sh"
for variant in baseline indexed; do
 if [[ "$variant" == baseline ]]; then replica_root="$ARTIFACT_TASK_DIR/build/baseline-package"; else replica_root="$shipping_root"; fi
 export BLINKCLIP_TEST_SCRATCH_PATH="$ARTIFACT_TASK_DIR/build/swiftpm-$variant"
 test_root="$ARTIFACT_TASK_DIR/build/harness-$variant"
 prepare_native_test_core > "$ARTIFACT_TASK_DIR/out/core-build-$variant.log" 2>&1
 compile_native_test_harness "retention-save-$variant" "$shipping_root/Tests/Native/RetentionSavePerformanceHarness.swift" "$ARTIFACT_TASK_DIR/build/BaselineCapture.swift" > "$ARTIFACT_TASK_DIR/out/compile-$variant.log" 2>&1
 if [[ "${BLINKCLIP_RETENTION_GRAPH_DIAGNOSTIC:-0}" == 1 ]]; then
  BLINKCLIP_RETENTION_PERF_VARIANT="$variant" "$test_harness" > "$ARTIFACT_TASK_DIR/out/diagnostic.log" 2>&1
  exit 0
 fi
 datasets=(256:8388608 1024:8388608 256:33554432)
 if [[ "$dataset_selector" == 1024-8mib ]]; then datasets=(1024:8388608); fi
 for dataset in "${datasets[@]}"; do
  count="${dataset%:*}"; bytes="${dataset#*:}"
  BLINKCLIP_RETENTION_PERF_VARIANT="$variant" BLINKCLIP_RETENTION_PERF_ITEMS="$count" BLINKCLIP_RETENTION_PERF_BYTES="$bytes" "$test_harness" > "$ARTIFACT_TASK_DIR/out/$variant-$count-$bytes.log" 2>&1
  python3 - "$ARTIFACT_TASK_DIR" "$variant" "$count" "$bytes" <<'PY'
import pathlib,shutil,sys
task=pathlib.Path(sys.argv[1]).resolve(); variant,count,size=sys.argv[2:]
assert variant in ['baseline','indexed'] and count in ['256','1024'] and size in ['8388608','33554432']
for prefix in ['fixture','behavior']:
 p=task/'build'/f'{prefix}-{variant}-{count}-{size}'
 assert p.parent==task/'build' and not p.is_symlink()
 shutil.rmtree(p)
PY
 done
done
python3 - "$ARTIFACT_TASK_DIR/out" "$dataset_selector" <<'PY'
import pathlib,json,statistics,sys
out=pathlib.Path(sys.argv[1]); results=[]
datasets=[(1024,8388608)] if sys.argv[2]=='1024-8mib' else [(256,8388608),(1024,8388608),(256,33554432)]
for count,size in datasets:
 pair={v:json.loads((out/f'{v}-{count}-{size}.json').read_text()) for v in ['baseline','indexed']}
 for cloud in [False,True]:
  values={v:[x['saveSeconds'] for x in pair[v]['measurements'] if x['cloudKitJournal']==cloud] for v in pair}
  results.append({'items':count,'payloadBytes':size,'cloudKitJournal':cloud,'baselineMedianSeconds':statistics.median(values['baseline']),'indexedMedianSeconds':statistics.median(values['indexed']),'samplesPerVariant':len(values['baseline'])})
(out/'comparison.json').write_text(json.dumps({'passed':True,'buildMode':'release (-O)','syntheticOnly':True,'results':results,'checksByDataset':{f'{c}-{b}':{v:json.loads((out/f'{v}-{c}-{b}.json').read_text())['checks'] for v in ['baseline','indexed']} for c,b in datasets}},indent=2))
print((out/'comparison.json').read_text())
PY
