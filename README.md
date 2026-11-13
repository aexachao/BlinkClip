# 闪贴 / BlinkClip

**BlinkClip（闪贴）是一款免费、本地优先的 macOS 剪贴板历史与截图工具。** 复制过的内容随时找得回来，截图顺手就能标注、钉在屏幕上。

面向 **macOS 14+，Intel（x86_64）与 Apple 芯片（arm64）通用**，用 Swift、AppKit 与 SwiftUI 编写。数据默认只保存在本机，不需要账号。

[![构建与发布](https://github.com/aexachao/BlinkClip/actions/workflows/release.yml/badge.svg)](https://github.com/aexachao/BlinkClip/actions/workflows/release.yml)

[下载最新版本](https://github.com/aexachao/BlinkClip/releases) · [从源码构建](#从源码构建) · [参与贡献](CONTRIBUTING.md) · [许可范围](NOTICE.md)

<!-- blinkclip-download:start -->
当前正式版 **1.0.10**，一个安装包兼容 Intel 与 Apple 芯片：

[下载 BlinkClip-1.0.10-macos-universal.dmg](https://github.com/aexachao/BlinkClip/releases/download/v1.0.10/BlinkClip-1.0.10-macos-universal.dmg)
<!-- blinkclip-download:end -->

## 功能

### 剪贴板历史

- 保存复制过的内容：文本、图片、文件、链接、颜色。
- 横向卡片面板浏览，多选、预览、本地编辑。
- 搜索与筛选，按类型、来源应用、日期查找。

### 收藏、分组与 Stack

- 收藏分组（Pinboard）整理常用内容。
- BlinkClip Stack 队列：按顺序依次粘贴多个项目，适合填表与重复操作。
- 自有归档导入与导出（JSON）。

### 截图与标注

- ⌘⇧A 区域截图，⌘⇧E 全屏截图，截图后直接进入标注编辑器。
- 标注工具：矩形、箭头、画笔、马赛克、聚光灯、文字、二维码、OCR、钉图。
- 长截图（滚动截图）：自动滚动需要 macOS 辅助功能授权，手动滚动不需要；结束后先裁剪再回到编辑器。
- 截图钉图：把图片以浮窗钉在屏幕上，随时对照查看。
- 本地 Vision OCR：识别图片中的文字；Apple 翻译（macOS 15+）可在「设置 → 截图」开启。

### AI 工具接入

- 独立的 `blinkclip-mcp` stdio 服务，可把剪贴板历史交给 Claude、Codex、Cursor 等 AI 工具作上下文。
- 提供搜索、读取、创建、更新、删除条目，以及分组的创建、改名、删除与成员管理。

### 同步

- iCloud Drive 文件同步为可选项，**默认关闭**，在「设置 → 通用」开启后自动使用 `iCloud Drive/BlinkClip`，同一 Apple ID 的多台 Mac 可同步历史与分组。
- 另有面向已签名构建的 CloudKit 高级选项，真实云端测试尚未完成。

## 下载与安装

1. 从 [GitHub Releases](https://github.com/aexachao/BlinkClip/releases/latest) 下载 `BlinkClip-1.0.10-macos-universal.dmg`。
2. 打开 DMG，把 `BlinkClip.app` 拖入 `Applications`，再从应用程序启动。
3. 首次使用时按引导授予必要的系统权限；跨应用直接粘贴需要 macOS 辅助功能权限。

1.0.10 已通过 GitHub Releases 公开发布：安装包经 Developer ID 签名并通过 Apple 公证，`macos-universal` 包同时支持 Intel 与 Apple 芯片。下载与校验信息见[最新发布页](https://github.com/aexachao/BlinkClip/releases/latest)。

应用内更新由 Sparkle 提供：在「关于 BlinkClip」中检查更新，确认后下载并安装已签名的完整 DMG。详见[自动更新](#自动更新)。

## 系统要求

- macOS 14 或更高版本
- Intel 或 Apple 芯片 Mac（提供 Universal 安装包）
- iCloud Drive 同步需要登录同一 Apple ID

## 快捷键

默认快捷键如下，全部可在「设置 → 快捷键」中修改：

| 操作 | 默认快捷键 |
| --- | --- |
| 打开历史面板 | ⇧⌘V |
| Stack 顺序粘贴 | ⇧⌘C |
| 区域截图 | ⌘⇧A |
| 全屏截图 | ⌘⇧E |

## 隐私

- **本地优先**：剪贴板历史、截图与设置默认只保存在本机，同步默认关闭，不需要账号。
- 截图、日志与归档可能包含个人信息，分享前请检查；报告问题时请用虚构文本和临时文件复现，不要提交真实历史、账号或密钥。

## 从源码构建

需要 macOS 14+、Xcode 26 或更新的 Command Line Tools（Swift 工具链）与 Python 3。首次构建会通过 SwiftPM 下载校验固定版本的 Sparkle 框架。

从仓库根目录构建 Universal 应用：

```sh
bash replica/scripts/build-app.sh release universal
```

产物为 `out/BlinkClip.app`。只构建当前 Mac 的调试版：

```sh
bash replica/scripts/build-app.sh debug native
```

制作正式发布的 Universal DMG：

```sh
npm run build:dmg
```

稳定版本生成签名更新源需要项目外配置的发布私钥；此命令仅本地打包，不发布。详见[应用内更新说明](docs/APP_UPDATES.md)。

已有有效 Apple Development 身份时，可设置环境变量 `BLINKCLIP_SIGNING_IDENTITY` 为身份名称或证书 SHA-1（兼容旧名 `BLINKCLIP_SIGNING_IDENTITY`）；未设置时采用临时签名。签名变化后可能需要重新授予辅助功能权限。

更多开发说明见 [replica/README.md](replica/README.md) 与[测试说明](replica/TESTING.md)。

## 自动更新

在「关于 BlinkClip → 检查更新」中查看最新正式 Release，六小时内复用检查结果，也可手动重新检查。确认更新后，Sparkle 在应用内下载完整的 Universal DMG，验证更新源与安装包的 Ed25519 签名，安装后重启应用；安装前会通过已有退出流程保存本地数据。

检查仅请求公开版本信息，离线或失败时可重试，剪贴板功能可继续使用。更新后辅助功能授权可能需要重新开启。

## 参与贡献

欢迎提交 Issue 与 Pull Request，详见 [CONTRIBUTING.md](CONTRIBUTING.md)。报告问题时请附不含隐私的复现步骤。

## 许可

独立编写的实现源码、工具、文档与自制图形按 [GNU AGPL-3.0](LICENSE) 开源（含第 13 条网络使用条款）。第三方组件（capcap 截图与编辑器模块、Sparkle 更新框架）保留各自的许可与版权声明，范围见 [NOTICE.md](NOTICE.md)。

## 已知限制

- 跨应用直接粘贴尚未完成全面验证，不能保证在所有应用的光标位置正确插入。
- CloudKit 真实云端同步尚未完成测试；iCloud Drive 文件同步的跨设备完整验收仍在进行。
- 录屏入口存在，是否可用尚未验证。
- 暂无 iPhone / iPad 应用。
- 当前源码版本 1.0.10；各安装包的实际功能以对应 Release 说明为准。
