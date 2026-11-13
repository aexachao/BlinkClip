#!/bin/bash
set -euo pipefail
replica_root="$(cd "$(dirname "$0")/.." && pwd)"
repository_root="$(cd "$replica_root/.." && pwd)"
report_root="${1:-$repository_root/.local/replica-validation}"
# 2026-11 清理说明：此处原有三条历史调用已随资产删除而失去意义，故移除，不另造替代实现：
#   1) scripts/function_ledger.py --require-migration-complete / --record-contracts
#      —— 用于核对"从 Paste 迁移函数"的台账；BlinkClip 已转为独立发布（见 RENAME_LOG.md），
#      不再维护迁移台账，仓库中也不存在该脚本。
#   2) replica/scripts/test-original-functions.py
#      —— 需要原版 Paste 二进制做逐函数对比；TESTING.md 已声明测试不访问原版运行时，
#      该契约已废弃，脚本亦不存在。
#   3) scripts/verify.py
#      —— 旧的研究报告校验入口，清理时删除；现行静态检查由 scripts/tests 承担（下方 unittest）。
mkdir -p "$report_root"
bash "$replica_root/scripts/build-app.sh" > "$report_root/build.log" 2>&1
# build-app.sh 默认以 universal 构建，二进制落在 .build/architectures/<arch>/release，
# 而不是历史硬编码的 .build/release（那是 native 构建的布局）。这里按同一规则定位。
build_root="${BLINKCLIP_BUILD_ROOT:-$replica_root/.build}"
core_tests="$build_root/architectures/$(uname -m)/release/blinkclip-core-tests"
if [[ ! -x "$core_tests" ]]; then
  core_tests="$build_root/release/blinkclip-core-tests"
fi
if [[ ! -x "$core_tests" ]]; then
  printf '找不到核心测试二进制（已尝试 .build/architectures/%s/release 与 .build/release）：%s\n'     "$(uname -m)" "$core_tests" >&2
  exit 1
fi
"$core_tests" > "$report_root/core.json"
python3 -m unittest discover -s "$repository_root/scripts/tests" > "$report_root/python-static-tests.log" 2>&1
bash "$replica_root/scripts/test-hotkey.sh" "$report_root/hotkey.json"
bash "$replica_root/scripts/test-shortcut-model.sh" "$report_root/shortcut-model.json"
bash "$replica_root/scripts/test-window-policy.sh" > "$report_root/window-policy.json"
bash "$replica_root/scripts/test-ui-interaction.sh" > "$report_root/ui-interaction.json"
python3 "$replica_root/scripts/test-helper-lifecycle.py" --report "$report_root/helper-lifecycle.json"
python3 "$replica_root/scripts/test-app-monitor.py" --report "$report_root/app-monitor.json"
printf '验证报告：%s\n' "$report_root"
