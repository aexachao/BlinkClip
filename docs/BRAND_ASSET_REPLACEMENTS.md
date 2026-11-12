# 闪贴 / BlinkClip 品牌与素材替换清单

产品中文名「闪贴」，英文名「BlinkClip」。源码版本 1.0.10，Bundle ID `com.chrisli.blinkclip`。通过 GitHub Releases 免费分发，使用 Sparkle 提供应用内更新；不在 Mac App Store 上架。本清单记录品牌与素材的当前状态，不提供法律结论。

更新：2026-11-12（BlinkClip 清理）。仓库地址：[aexachao/BlinkClip](https://github.com/aexachao/BlinkClip)。

## 当前状态

- 新主启动图标、直接粘贴 / 复制到剪贴板 / 权限三张插图按用户确认使用当前内置图像工具生成。工具未公开模型 ID，不称为 gpt-image-2.5。源图、提示词、分层 source-package、转换和 SHA 记录见 `branding/BlinkClipGeneratedAssets/`；独立 20pt 类别模板继续保留，中英独立文案与其他语言回退英文保持。
- 新 Core bundle 只允许中英表及指定三张生成 PNG（加 Info.plist 共 8 文件）。
- 1.0.10 清理已从公开仓库移除：反编译产物、研究报告、逆向研究说明，以及旧提取资源（17 套旧本地化、`OriginalSettingsCopyTo*` 四张图、`BlinkClipOtherApps@2x.png`、`OriginalStackIcons.bundle`）。仅从当前分支删除文件并不能清除 git 历史中的旧内容；本仓库将以单一初始提交重建为独立仓库，不再共享上游 fork 的历史。
- 仍保留一份内部函数对照台账（`replica/function-map.json`）与源码中的地址注释，作为实现记录，将在后续重命名工作中清理。

## A · 原研究素材与独立替代

| 项 | 原素材 | 独立替代与当前状态 |
| --- | --- | --- |
| A1 设置插图 | `Resources/OriginalSettingsCopyTo{App,Clipboard}{Light,Dark}@2x.png` 四张原版设置导出，已从仓库删除。 | 新生成 `BlinkClipDirectPaste@2x.png` 与 `BlinkClipCopyToClipboard@2x.png`，384×256 透明图，可用于浅深背景；从纯文字简报生成，源和提示词在 `branding/BlinkClipGeneratedAssets/`。此前独立几何图保留为 fallback。 |
| A2 类别图标 | `OriginalStackIcons.bundle` 八张 PNG，已从仓库删除。 | 同 renderer 的折角文档、双环、四行、三点卡片，20/40px 模板；代码绘制，消费者已改用新绘，最终包不含旧 bundle。 |
| A3 普通本地化 | 17 个 `Resources/*.lproj/Localizable.strings`，各 123 键，已从仓库删除。 | `branding/BlinkClipLocalization/` 独立中英各 123 键，已核动态 key / 占位符。用户明确选择其他界面语言回退英文；不声称已原创翻译全部 17 语言。 |
| A4 复数本地化 | 同上 17 份 `Localizable.stringsdict`，每份四项，已从仓库删除。 | 自写中英各四项，保留格式和复数消费合同。 |
| A5 权限拼图 | `Resources/BlinkClipOtherApps@2x.png`，授权记录不足，已从仓库删除。 | 新生成 `BlinkClipPermissions@2x.png`，480×288 透明通用窗口 / 内容卡片，无真实第三方 Logo、文字或锁。 |
| A6 音效 | 原 `Copy.aiff` / `Paste.aiff` 未随既有包发行。 | 当前按用户最终选择使用 macOS 自带 Purr，运行时按名称加载，不复制苹果音频文件；不读旧音、不用 Pop、无时间节流。实际听感待确认。 |

新生成源、提示词与包装：`branding/BlinkClipGeneratedAssets/PROVENANCE.md`；历史几何与旧图标来源：`branding/BlinkClipAssets/PROVENANCE.md`；语言 key / 占位符：`branding/BlinkClipLocalization/`。

## B · 自有品牌展示

| 项 | 当前状态 |
| --- | --- |
| B1 主图标 | 新生成概念及前景源见 `branding/BlinkClipGeneratedAssets/sources/`；实际 ICNS 文件为 `replica/Assets/BlinkClipAppIcon.icns`。不声称全矢量或 Icon Composer 分层包。 |
| B2 旧自制 BlinkClip 图标 | 原 BlinkClip PNG/ICNS 是项目旧自制图标，不能与 A2 原提取图标混同。当前主入口已改为 BlinkClip。 |
| B3 菜单栏 | `ReplicaBrand` 代码绘制取景框 / 折角卡片；已核 18pt、template、浅深 1x/2x。 |
| B4 显示与语言 | AppBrand、关于、权限、设置、InfoPlist 中英展示使用闪贴 / BlinkClip。原表已由自写 BlinkClipResources 替代。 |
| B5 MCP / Intents | MCP 可见分组描述和错误已修正、来源标记为 `BlinkClip MCP`；协议字段 / 工具名 / schema 不扫词替换。Intent 标题与工程类型兼容分别审计；开发源码已有入口，系统发现、真实快捷指令运行及既有快捷指令迁移未验。 |
| B6 README / 官网 | 中英 README 与官网产品品牌统一为闪贴 / BlinkClip；favicon、OG、正文图标统一 `blinkclip-icon.png`。演示截图未按最终品牌包重新生成，不将旧图称为最新运行证据。 |

## C · 许可与研究隔离

- **capcap**：保留 `replica/Vendor/capcap/LICENSE` 完整 MIT / Copyright (c) 2026 realskyrin；包内完整告知已接入，不能改成 BlinkClip 作者。
- **Sparkle**：保留框架、Sparkle 及其依赖许可告知；不因品牌迁移改变更新验证公钥或提交私钥。
- **项目 MIT**：`LICENSE` 中 Copyright (c) 2026 BlinkClip contributors 保留完整。新品牌与新创作范围由 NOTICE/来源记录说明，本轮不重写既有版权行。
- **研究材料**：反编译产物、研究报告、原符号、恢复代码和旧提取素材已从公开仓库移除（见上文“当前状态”）；内部函数对照台账与源码地址注释已在 BlinkClip 清理中删除（见下文 §D）。
- **系统与其他 App 图标**：历史卡片运行时显示来源标志用于识别，不因此取得将它们用作自身商标或宣传图的权利；相关使用条件仍需复核。

## D · 标识与工程迁移

包名、核心 / helper / MCP 模块、产品和源码目录已实际同步改为 BlinkClip 系列；新 CLI 为 `blinkclip-mcp` / `blinkclip-core-tests`；`BLINKCLIP_*` 环境变量为当前标准，旧 MCP 兼容入口与旧环境变量前缀已在 BlinkClip 清理中移除。核心资源 bundle 为 `BlinkClip_BlinkClipCore.bundle`。主 App 模块现为 `BlinkClip`。

| 标识 | 当前值 |
| --- | --- |
| Bundle ID | `com.chrisli.blinkclip`；Helper `com.chrisli.blinkclip.helper` |
| 数据目录 | `~/Library/Application Support/BlinkClip/` |
| iCloud Drive 同步目录 | `iCloud Drive/BlinkClip`，同步文件夹 `BlinkClipSync-v1`，格式标记 `blinkclip-icloud-drive` |
| 登录项 | `LoginItems/BlinkClip Helper.app` |
| CloudKit | 容器标识由签名 entitlements 决定，不在代码中写死原厂容器；高级选项需自有签名与容器配置 |

以下已在 BlinkClip 清理中完成重命名或删除，不再保留：主 App 模块与 Core Data 实体运行时名已改为 BlinkClip，旧文件名与地址风格的旧函数名已改为描述性名称，源码中的地址注释与函数对照台账已删除（见 `RENAME_LOG.md`）。标准 API（`NSPasteboard`、`paste:`、copy/paste 动词、UTType）与原厂事实性引用不属于清理对象。

## E · 分发与验收

- 分发方式：GitHub Releases 免费下载 Universal DMG，Sparkle 应用内更新（Ed25519 签名更新源）。不在 Mac App Store 上架，不做 App Sandbox、商店签名、隐私清单等商店专项。
- 公开 DMG 仍需 Developer ID 签名与公证，尚未完成；临时签名版本更新后可能需要重新开启辅助功能授权。
- 最终包验收：每次发版构建最终候选 .app，列出包内完整文件清单并与白名单比对，只允许 BlinkClipResources 的中英表与 3 张生成图；包内二进制与字符串扫描应确认无旧厂商标识、旧产品名与地址式函数名残留；与本清单 D 节逐项对账。
