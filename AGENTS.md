# BlinkClip 项目规则

BlinkClip（闪贴）是一款免费、本地优先的 macOS 剪贴板历史与截图工具，独立开发，与 Paste 原厂无关联。

## 基本信息

- 产品名：BlinkClip（闪贴）
- Bundle ID：`com.chrisli.blinkclip`
- 仓库：`github.com/aexachao/BlinkClip`（独立仓库，单一初始提交，不共享上游 fork 历史）
- 发行：GitHub Releases 免费分发，**不在 Mac App Store 上架**；应用内更新使用 Sparkle
- 目标系统：macOS 14+，Intel 与 Apple 芯片通用

## 构建与测试

```bash
npm run build:app     # bash replica/scripts/build-app.sh
npm run build:icon    # swift replica/scripts/build-icon.swift
npm run build:dmg     # python3 replica/scripts/release-ci.py package
npm run test:core     # swift run --package-path replica blinkclip-core-tests
npm run test:mcp      # python3 replica/scripts/test-mcp.py
```

原生测试脚本在 `replica/scripts/test-*.sh`，测试桩在 `replica/Tests/Native/`，核心测试在 `replica/Tests/BlinkClipCoreTests/`，Python 静态检查在 `scripts/tests/`。详见 `replica/TESTING.md`。构建与测试直接在仓库内运行，不经过 storage-guard，也不使用 `~/dev-artifacts`。

## 不要做的事

- 不要提交到 Mac App Store；不要做 App Sandbox、商店签名或商店专属更新工作。
- 不要推送到 GitHub，不要删除或改名 GitHub 上的任何内容（除非用户明确授权）。
- 不要恢复已删除的研究材料（反编译产物、研究报告、函数对照台账、地址注释）；函数重命名记录见 `RENAME_LOG.md`。
- 不要把真实剪贴板历史、账号、密钥或个人文件提交到仓库或问题报告中。

## 历史记录

本文件在 BlinkClip 清理中重写。旧版 AGENTS.md 中的 240KB 历史修复日志已随清理删除，不再保留；历史测试证据日志同样已从 `replica/TESTING.md` 移除，改为现行测试指南。
