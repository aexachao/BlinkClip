# BlinkClip / 闪贴本地化源稿

日期：2026-11-11。范围：新制 `en.lproj`、`zh-Hans.lproj` 普通表和复数表；尚未接入应用或发行包。其余语言由后续访问层明确回退英文，本目录没有声称提供其他语言译文。

## 创作来源与保留合同

本目录用户可见文案由本次实施独立撰写，英文和简体中文依据真实功能与调用场景分别编辑。旧表仅用于核对稳定键、参数、图标标记与复数格式接口；不是整表品牌替换或将提取文字重新标记授权。已有来源声明、原表及其权利边界保持原状。本文件不授予其他目录内容新的许可，也不作商标、法律或上架保证。

短菜单词与技术术语（例如 Cancel、OK、Bold、Color）及自然计数单位可能与既有表相同；这不是零字面重复承诺。较长说明重新组织为操作和后果，例如权限设置路径、来源应用标记的机密/临时内容、AI 连接配置及更新失败原因。没有加入“自动识别所有密码”“自动连接 AI”或“一次授权永久有效”等承诺。标准粘贴动作仍是 Paste / 粘贴；BlinkClip / 闪贴仅用于应用品牌。

- 每种语言：123 个普通键及 4 个复数键，无键改名。`blinkclip.*`、`restart-paste` 等保留为兼容标识，其显示值使用当前品牌或“分组”。
- 普通 `%@` 的类型、数量和顺序保持：`general.action.open-in`（应用名）、`general.until`（时间）、`accessibility-access.paste-to-other-apps.title`（应用名）、`shortcut-recorder.error.used-in-menu`（菜单名）。不新增位置修饰符。
- `general.enable-direct-paste` 保留 `{icon:chevron.right}`。该 token 不是文字商标。
- 4 个复数条目均保留 `%#@value@` → `value` → `NSStringPluralRuleType` → `d`。英文 one/other，中文 other；消费者 `countResource` 传入 Int32。
- 英文 `item-type.file-count.one` 按既有分支合同显示 `File`，不消费 `%d`；其 other 及其他英文计数分支消费一个 `%d`，中文四个 other 均消费一个 `%d`。不以格式差异意外更改 ABI。

## 调用场景核对

`keys-map.json` 逐键列出格式合同、源码直接字面量位置和状态，不把源码出现次数等同运行覆盖。

实际检查入口：

- `replica/Sources/BlinkClipCore/SettingsLocalization.swift` / `SearchLocalization.swift`：通用 `text(key)`；须在集成时换到自有资源并明确语言回退。
- `PreviewLocalization.swift`：编辑工具、暂停状态、诊断、内容类型、时间/应用名插值、四个计数。
- `UnavailablePreviewLocalization.swift`：无预览时仍可粘贴的说明。
- `ShortcutMessages.swift`、`ShortcutRecorder.swift`、`ShortcutValidation.swift`：动态 value(key)、录制状态、系统/菜单冲突和旧系统 Option 警告。
- `replica/Sources/BlinkClip/UI/AccessibilityModals.swift`：真实 `%@` 应用名、请求前/后按钮、直接粘贴权限。
- `SettingsCopy.swift`、`AuxiliaryViews.swift`、`FilterBrowser.swift`、`AppMain.swift`、`BlinkClipAboutWindowController.swift`、`ReplicaPreviewAdapter.swift` 及 `BlinkClipUpdateChecker.swift`：设置、分组、搜索、更新结果。

## 覆盖与集成待办

普通键缺漏：0；复数键缺漏：0。123 键中 112 个在 Swift 中有直接字符串字面量。下列 11 键未找到直接字面量消费者，已完整撰写以保合同；没有凭空认定它们是动态运行入口：

`search.filters.section.pinboard`、`settings.history.forever`、`settings.shortcuts.title`、`settings.shortcuts.next-pinboard.title`、`settings.shortcuts.previous-pinboard.title`、`settings.shortcuts.action.reset`、`settings.shortcuts.action.reset.confirmation`、`settings.paste-items.accessibility-access-request`、`settings.privacy.link-preview.title`、`settings.privacy.link-preview.subtitle`、`settings.mcp.title`。

后续集成必须处理：

1. 旧 `ResourceBundle` 及全部 accessor 仍可能读取原表；本源稿不会自行阻止旧资源进入包内。`SettingsCopy.text` 未命中仍回退旧 accessor。
2. 六个设置分组（通用、剪贴板与历史、截图、快捷键、隐私与权限、AI 工具）来自 `SettingsSection` 源码，不属于原 123 键。`ScreenshotSettingsCopy`、Vendor/capcap、硬编码中英、MCP/Intents 等有独立文本来源，不能将本目录验收当成全应用原创文字验收。
3. 尚未新增其他语言文件。非简体中文回退英文需由集成层明确落实并验证；仅创建这些目录不能覆盖旧 17 语言 Bundle 的择语行为。繁体中文此次未作独立翻译。
4. 部分键保留旧未实际使用的功能语义（诊断、获取网络预览等）；翻译覆盖不证明当前 UI 暴露或功能已运行。网络预览主动访问风险文案保留，但不能据此声称网络抓取已启用。
5. 尚未执行应用构建、运行、布局、真实格式渲染、权限、网络、安装或发行验收。长文本在当前 UI 中的换行与可访问性须由集成检查。

## 本次检查

通过 storage-guard 执行独立资源契约检查：`plutil -lint` 四文件通过；UTF-8、重复键、123+4 覆盖、四个 `%@`、图标 token、复数嵌套图/类别/每分支参数均通过。普通表中 14 个英文值与旧英文表相同，均为常规菜单/类型词；其余 109 个英文值不同。复数自然单位不为追求差异改成不准确说法。

证据：`/Users/chrisli/dev-artifacts/blinkclip/blinkclip-original-localization-9106-20261111-185334/out/localization-contract-check.json`。源码哈希保存在该证据中。未创建模拟器或 AVD。
