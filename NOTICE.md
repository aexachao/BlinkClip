# 许可范围说明

当前维护仓库：[aexachao/BlinkClip](https://github.com/aexachao/BlinkClip)。BlinkClip（闪贴）是独立开发的 macOS 应用，与 Paste 原厂无关联，也不授予对原版应用的修改、付费解锁或再分发许可。原应用的版权与商标归 Paste Team ApS 及相关权利人所有。

## 独立实现

本项目的 [GNU AGPL-3.0](LICENSE) 仅适用于有权许可的独立实现源码、独立工具、独立撰写的文档和有来源记录的自制品牌图形与新绘功能插图（见 `branding/BlinkClipAssets/PROVENANCE.md` 与 `branding/BlinkClipGeneratedAssets/PROVENANCE.md`）。它不表示仓库内所有文件都属于本项目作者，也不替代任何第三方材料的权利或许可条件。

## 已移除的材料

在 1.0.10 清理中，以下原版资源已从公开仓库移除：

- `replica/Sources/BlinkClipCore/BlinkClipResources/` 中的原版本地化文字与设置插图，以及 `OriginalStackIcons.bundle` 中的原版类别图标。

仅从当前分支删除文件并不能清除 git 历史中的旧内容。本仓库将以单一初始提交重建为独立仓库（见发布说明），不再共享上游 fork 的历史；在此之前，请勿将旧提交历史视为已清理。

现源码中的函数名均为按实际行为命名的描述性名称。

## 引入的第三方源码

- `replica/Vendor/capcap/`：capcap（<https://github.com/realskyrin/capcap>）的截图与编辑器模块，以 MIT 许可引入。原始许可证与版权声明保留在同目录的 `LICENSE` 文件中（Copyright (c) 2026 realskyrin）。这些文件不属于本项目的独立实现部分，其权利与许可条件以上游 MIT 条款为准。
- Sparkle 更新框架：保留框架及其依赖的许可告知；不因品牌迁移改变更新验证公钥或提交私钥。

## 自有替代资源与发行边界

小尺寸类别模板和插图失图回退由 `branding/BlinkClipAssets/BlinkClipAssetRenderer.swift` 的独立基本几何绘制。当前设置说明、通用权限图及主启动图标，按用户确认使用当前内置图像工具从纯文字简报生成；源图、提示词、图层包装和实际工具来源见 `branding/BlinkClipGeneratedAssets/PROVENANCE.md`。未向模型提供原版资源；工具不公开模型 ID，不声称由 gpt-image-2.5 生成，也不将生成过程当作独占权、商标可用性或法律结论。

自写中英文及四项复数文案见 `branding/BlinkClipLocalization/`，其他语言回退英文。当前 `BlinkClipCore` 仅处理新自有 `BlinkClipResources`：中英表与明确的新生成 PNG。成功提示音按用户选择使用 macOS 系统自带 Purr，由 `NSSound(named:)` 运行时加载；不将苹果系统音频复制进仓库或应用，不使用系统 Pop。Purr 是本项目所选的反馈音，不声称 Apple 规定其统一代表成功。源稿审查、音频事件验证与最终包安装分别验收，结果见[替换清单](docs/BRAND_ASSET_REPLACEMENTS.md)和 [TESTING](replica/TESTING.md)。

capcap 的完整 MIT 许可与版权应随发行物提供，Sparkle 及其依赖告知继续保留。BlinkClip contributors 的版权行保留在本文件「版权」段；新品牌不转移原作者、原厂或第三方权利。本项目不在 Mac App Store 上架，通过 GitHub Releases 免费分发，并使用 Sparkle 提供应用内更新。

## 数据与验证

BlinkClip 运行时会处理并在本机保存用户剪贴板内容，这是独立应用的功能。贡献或报告问题时不要提交真实历史、账号、密钥或个人文件。

当前实现尚未完成全面验收，跨应用直接粘贴仍未完成验证。AGPL-3.0 的许可及免责条款不构成任何功能等价性、兼容性或适用性的保证。

## 许可证

本项目以 [GNU Affero General Public License v3.0](LICENSE)（AGPL-3.0）发布。第三方组件（capcap 截图与编辑器模块、Sparkle 更新框架及其依赖）保持各自的许可证，彼此独立，不因本项目采用 AGPL-3.0 而改变；相应全文与版权声明见上文「引入的第三方源码」及 `replica/Vendor/capcap/LICENSE`、`replica/Assets/Sparkle-LICENSE.txt`。

AGPL-3.0 第 13 条要求：若你修改本程序并通过网络向用户提供其功能，须向这些用户提供对应源码。本项目自身即以源码形式分发，构建步骤见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 版权

Copyright (c) 2026 BlinkClip contributors
