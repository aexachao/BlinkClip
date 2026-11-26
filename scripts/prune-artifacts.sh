#!/bin/bash
# 清理 storage-guard 的产物目录，防止 ~/dev-artifacts 无限膨胀。
#
# 默认 dry-run：只列出将删除的目录和可释放空间，不动任何文件。
# 加 --apply 才真正删除。规则见 docs/DISK.md。
#
# 保留策略：最近 N 天（默认 7）与最近 K 个（默认 5）的并集，其余删除。
# 安全护栏：只删名字形如 <task>-<pid>-<YYYYMMDD>-<HHMMSS> 的任务目录，
#           其余条目（secrets/、bin/、shared/、符号链接、普通文件、隐藏项）
#           一律跳过并打印原因，绝不递归删上级目录。
set -euo pipefail

usage() {
  cat <<'EOF'
用法：bash scripts/prune-artifacts.sh [选项]

  默认 dry-run，只打印将删除的目录与可释放空间；加 --apply 才真删。

  --apply              真正删除（不加只是试跑）
  --keep-days N        保留最近 N 天的任务目录（默认 7）
  --keep-latest N      无论如何保留最新的 N 个任务目录（默认 5）
  --root DIR           产物根（默认 ~/dev-artifacts/BlinkClip）
  --verbose            连保留项也逐条打印
  --quiet              只打印结论与 JSON 摘要（发布脚本里用，输出不刷屏）
  -h, --help           显示本帮助

只删除名字匹配 ^[a-z0-9-]+-[0-9]+-[0-9]{8}-[0-9]{6}$ 的目录；其它条目跳过。
结束时打印一行 JSON 摘要（mode / deleted_count / freed_bytes / kept_count）。

示例：
  bash scripts/prune-artifacts.sh                 # 看一眼
  bash scripts/prune-artifacts.sh --apply         # 真正清理
  bash scripts/prune-artifacts.sh --apply --keep-days 3   # 发版后更激进
EOF
}

apply=0
verbose=0
quiet=0
keep_days=7
keep_latest=5
root="${BLINKCLIP_ARTIFACT_ROOT:-$HOME/dev-artifacts/BlinkClip}"

while (( $# )); do
  case "$1" in
    --apply) apply=1; shift ;;
    --verbose|-v) verbose=1; shift ;;
    --quiet|-q) quiet=1; shift ;;
    --keep-days) keep_days="${2:?--keep-days 需要参数}"; shift 2 ;;
    --keep-days=*) keep_days="${1#*=}"; shift ;;
    --keep-latest) keep_latest="${2:?--keep-latest 需要参数}"; shift 2 ;;
    --keep-latest=*) keep_latest="${1#*=}"; shift ;;
    --root) root="${2:?--root 需要参数}"; shift 2 ;;
    --root=*) root="${1#*=}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf '未知参数：%s\n\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

for value in "$keep_days" "$keep_latest"; do
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    printf '保留天数/个数必须是非负整数，实际：%s\n' "$value" >&2
    exit 2
  fi
done

exec python3 - "$root" "$keep_days" "$keep_latest" "$apply" "$verbose" "$quiet" <<'PY'
import json
import os
import re
import shutil
import sys
import time
from datetime import datetime

# 与 storage-guard 一致的任务目录命名：<task>-<pid>-<YYYYMMDD>-<HHMMSS>
TASK_DIR = re.compile(r'^[a-z0-9-]+-[0-9]+-[0-9]{8}-[0-9]{6}$')


def die(message):
    sys.stderr.write(message + '\n')
    raise SystemExit(2)


def human(nbytes):
    value = float(nbytes)
    for unit in ('B', 'KiB', 'MiB', 'GiB', 'TiB'):
        if value < 1024 or unit == 'TiB':
            return f'{value:.1f} {unit}' if unit != 'B' else f'{int(value)} B'
        value /= 1024


def iso(mtime):
    return datetime.fromtimestamp(mtime).astimezone().strftime('%Y-%m-%dT%H:%M:%S')


def measure(path):
    """占用字节（按已分配块，和 du 口径一致）与最近活动时间。

    最近活动时间取目录自身 mtime 与直接子项 mtime 的最大值：任务目录是一次
    写入的，这样即使只在末尾改了文件也会被算成「刚用过」，不会被误删。
    """
    allocated = 0
    newest = os.lstat(path).st_mtime
    for dirpath, dirnames, filenames in os.walk(path, onerror=lambda err: None):
        for name in dirnames:
            try:
                newest = max(newest, os.lstat(os.path.join(dirpath, name)).st_mtime)
            except OSError:
                continue
        for name in filenames:
            try:
                st = os.lstat(os.path.join(dirpath, name))
            except OSError:
                continue
            newest = max(newest, st.st_mtime)
            allocated += st.st_blocks * 512
    return allocated, newest


root_arg, keep_days, keep_latest, apply_flag, verbose, quiet = (
    sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4] == '1', sys.argv[5] == '1',
    sys.argv[6] == '1')
root = os.path.realpath(os.path.expanduser(root_arg))

if not os.path.isdir(root):
    die(f'产物根不存在或不是目录：{root}')
home = os.path.realpath(os.path.expanduser('~'))
for forbidden in {'/', home, os.path.join(home, 'dev-artifacts')}:
    if root == os.path.realpath(forbidden):
        die(f'拒绝在过宽的目录上运行：{root}（本脚本只清理某个仓库的任务产物根）')

cutoff = time.time() - keep_days * 86400
scanned, skipped = [], []
for name in sorted(os.listdir(root)):
    path = os.path.join(root, name)
    if name.startswith('.'):
        skipped.append({'name': name, 'reason': '隐藏项'})
    elif os.path.islink(path):
        skipped.append({'name': name, 'reason': '符号链接'})
    elif not os.path.isdir(path):
        skipped.append({'name': name, 'reason': '不是目录'})
    elif not TASK_DIR.match(name):
        skipped.append({'name': name, 'reason': '非任务目录命名'})
    else:
        allocated, mtime = measure(path)
        scanned.append({'name': name, 'bytes': allocated, 'mtime': mtime})

scanned.sort(key=lambda item: item['mtime'], reverse=True)
newest = {item['name'] for item in scanned[:keep_latest]}
kept, to_delete = [], []
for item in scanned:
    if item['mtime'] >= cutoff or item['name'] in newest:
        kept.append(item)
    else:
        to_delete.append(item)
to_delete.sort(key=lambda item: item['mtime'])

print(f'# BlinkClip 产物清理')
print(f'根目录: {root}')
print(f'模式: {"apply（真删）" if apply_flag else "dry-run（不删，加 --apply 执行）"}')
print(f'保留: 最近 {keep_days} 天（>= {iso(cutoff)}） 或 最新 {keep_latest} 个，取并集')
if to_delete and kept:
    print(f'边界: 最旧的保留项 {iso(kept[-1]["mtime"])}；最年轻的删除项 {iso(to_delete[-1]["mtime"])}')
print(f'任务目录 {len(scanned)} 个，跳过 {len(skipped)} 个非任务项')
print()

planned_bytes = sum(item['bytes'] for item in to_delete)
if to_delete:
    verb = '删除' if apply_flag else '将删除'
    print(f'{verb} {len(to_delete)} 个（{human(planned_bytes)}），旧的在前：')
    if not quiet:
        for item in to_delete:
            print(f'DEL\t{item["bytes"]}\t{iso(item["mtime"])}\t{item["name"]}')
else:
    print('没有需要删除的任务目录。')
print()

kept_bytes = sum(item['bytes'] for item in kept)
print(f'保留 {len(kept)} 个（{human(kept_bytes)}）')
if verbose and not quiet:
    for item in kept:
        print(f'KEEP\t{item["bytes"]}\t{iso(item["mtime"])}\t{item["name"]}')
elif kept:
    print(f'  最新 {min(keep_latest, len(kept))} 个: ' +
          ', '.join(item['name'] for item in kept[:max(keep_latest, 1)]))
    if not quiet:
        print('  （--verbose 可看全部保留项）')
# 预算告警：单任务目录超过 1 GiB 通常意味着构建产物写到了错误的位置（例如把
# 依赖或 dist 拷进了 out），值得人看一眼，而不是默默留着。
oversized = [item for item in kept if item['bytes'] > 1 << 30]
if oversized:
    print(f'注意: {len(oversized)} 个保留的任务目录超过 1 GiB 预算——'
          f'{oversized[0]["name"]}（{human(oversized[0]["bytes"])}），检查它是不是把缓存写进了 out/')
print()

if skipped:
    print(f'跳过 {len(skipped)} 个：')
    for item in skipped:
        print(f'SKIP\t0\t-\t{item["name"]}\t{item["reason"]}')
    print()

deleted, errors = [], []
if apply_flag:
    for item in to_delete:
        path = os.path.join(root, item['name'])
        try:
            shutil.rmtree(path)
        except OSError as err:
            errors.append({'name': item['name'], 'error': str(err)})
            print(f'ERROR\t{item["name"]}\t{err}', file=sys.stderr)
            continue
        if os.path.exists(path):
            errors.append({'name': item['name'], 'error': '删除后仍存在'})
            print(f'ERROR\t{item["name"]}\t删除后仍存在', file=sys.stderr)
            continue
        deleted.append(item)
    freed = sum(item['bytes'] for item in deleted)
    print(f'已删除 {len(deleted)} 个，释放 {human(freed)}')
    if errors:
        print(f'失败 {len(errors)} 个（见 stderr）')
else:
    freed = 0
    print(f'dry-run：未删除任何文件；可释放 {human(planned_bytes)}')

summary = {
    'root': root,
    'mode': 'apply' if apply_flag else 'dry-run',
    'keep_days': keep_days,
    'keep_latest': keep_latest,
    'cutoff': iso(cutoff),
    'scanned_count': len(scanned),
    'kept_count': len(kept),
    'kept_bytes': sum(item['bytes'] for item in kept),
    'planned_delete_count': len(to_delete),
    'deleted_count': len(deleted),
    'freed_bytes': freed,
    'reclaimable_bytes': planned_bytes,
    'skipped_count': len(skipped),
    'skipped': skipped,
    'errors': errors,
}
print()
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
raise SystemExit(1 if errors else 0)
PY
