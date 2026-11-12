# 测试指南

> 历史说明：本文件在 BlinkClip 清理（2026-11-12）中重写。此前的 288 行逐轮测试证据日志已删除；本文件只记录现行测试的运行方式，不再记录历史通过数字。历史证据不替代本轮验证。

## 环境要求

- macOS 14+，Xcode Command Line Tools。
- 测试无法在 Linux 上运行（无 macOS SDK / XCTest）；核心验证入口是 `blinkclip-core-tests`，不是 `swift test`。

## 运行方式

```bash
npm run test:core   # swift run --package-path replica blinkclip-core-tests
npm run test:mcp    # python3 replica/scripts/test-mcp.py
```

原生测试脚本（`replica/scripts/test-*.sh`）直接运行；多数脚本要求设置 `ARTIFACT_TASK_DIR`（用作构建与输出的临时目录）：

```bash
ARTIFACT_TASK_DIR=$(mktemp -d) bash replica/scripts/test-cloudkit-sync.sh
ARTIFACT_TASK_DIR=$(mktemp -d) bash replica/scripts/test-copy-restore.sh
```

构建脚本（`replica/scripts/build-app.sh`）在未设置 `ARTIFACT_TASK_DIR` 时使用仓库内默认临时目录。

## 测试组成

- `replica/Tests/BlinkClipCoreTests/`：核心单元测试（`ClipboardStoreTests.swift` 等），由 `blinkclip-core-tests` 运行。
- `replica/Tests/Native/`：原生测试桩（`*Harness.swift`），由 `replica/scripts/test-*.sh` 编译并运行；覆盖面板、截图、快捷键、设置、CloudKit 同步、保留期限、更新、权限提示等。
- `scripts/tests/`：Python 静态检查（`test_p0_repair_archive_keys.py`、`test_p0_repair_focus.py`、`test_sync_release_downloads.py` 及 `appkit_cache_static.py`、`compiled_nib_static.py`），用 `python3` 直接运行。
- `replica/scripts/test-blinkclip-owned-resources.sh`：自有资源校验（本地化表、生成插图、图标与打包资源白名单）。

## 约束

- 测试使用临时 Store、私有剪贴板与离屏窗口，不访问真实 iCloud、原版运行时或用户历史；`--live-icloud` 等探针需显式开启，且只写入合成内容。
- 失败时脚本退出码非零；提前退出不能当作通过。真实像素抓取、实体听感、TCC 权限与第二台物理 Mac 的验证不在自动化覆盖内，需单独验收。
