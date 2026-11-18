# 闪贴设置设计规范

更新：2026-11-18

## 方向
- 设置按用户任务分组，一个设置只有一个管理归属。（用户确认）
- 六组按顺序为通用、剪贴板与历史、截图、快捷键、隐私与权限、AI 工具。（用户确认）
- 沿用当前 macOS 原生字体、颜色、卡片和控件，不重塑品牌或视觉风格。（用户确认）

## 品牌资产
- 保留闪贴 / BlinkClip 名称、应用图标、菜单栏标志。（用户已选品牌）
- **App 图标：1024 画布，824 主体，圆角 185.4，含投影。** 主体居中于 (100,100)-(924,924)，四边留白各 100；圆角按 macOS 圆角矩形近似取 185.4（45° 处与 Apple 现行图标一致）；投影向下 10、模糊 24、不透明度 0.35，使图标在浅色 Dock/Finder 上立体。源图为 `replica/Assets/BlinkClipIcon.png`（1024 单图），`BlinkClipAppIcon.icns` 由它经 `replica/scripts/build-icon.swift` 生成 16/32/64/128/256/512/1024 全套；改图只做缩放与遮罩，不重绘。验收：`sips` 导出 1024 后实测实体 alpha≥250 为 824×824、留白 100/100/100/100；Dock 46pt 图标框内实体 74/92 px = 80.5%。（2026-11-15 用户反馈「比其他启动图标大一圈」；重制前实体 896×896，占 87.5%，无投影；实测图见 `evidence/patches/s3-renders/`）

## 内容归属
- 通用：登录启动、后台运行、主题、语言、提示音、iCloud 同步、自动检查更新。（用户确认）
- 通用页按职责分组：**启动与运行**（登录时启动、保持后台服务运行）/ **外观与语言**（主题、语言）/ **同步与更新**（iCloud 同步、自动检查更新）/ **声音**（播放操作提示音）；单张卡不超过 2 项时合并，超过则分组，组内保留分隔线、组间只留 20pt 间距不加 Divider。验收：四个 `settingsSectionTitle` + 四张卡、「外观与语言」夹在「启动与运行」与「同步与更新」之间、`Divider()` 只出现在组内、三语键齐全。（2026-11-15 用户反馈；源码 `AuxiliaryViews.swift` 的 `general`、`SettingsCopy.swift`；断言 `SettingsArchitectureHarness.swift`、`test-settings-architecture.sh` 的通用页分组门）
- 外观与语言组：**主题**（跟随系统 / 浅色 / 深色）写既有 `preferences.appearance`，**语言**（跟随系统 / 简体中文 / 繁體中文 / English）写 `appLanguage` 键（跟随系统 = 删除该键）；两行都是菜单 `Picker` + 标题/说明两行文字，行内控件与文字块同一条中线（≤0.5pt）。切换即时生效并持久化：主题写完偏好立刻跑同一份 `ReplicaUIController.applyAppearance()`，设置窗、底部面板、编辑器与预览窗同时换外观；语言发 `blinkclip.languageDidChange`，已打开的设置页重算文案（分区标题、侧栏、工具栏标题、窗口标题一起改），语言名按语言自称显示不翻译，说明写清「界面语言；部分系统弹窗仍跟随系统语言」。重启后两行回显仍与存储一致。（2026-11-15 用户要求；源码 `AuxiliaryViews.swift` 的 `appearanceThemeRow` / `appearanceLanguageRow`、`SettingsAppearanceLanguage.swift`、`ReplicaUIController.applyAppearance()` / `refreshSettingsWindowTitle()`；断言 `SettingsArchitectureHarness.verifyAppearanceLanguageRows`、`test-settings-architecture.sh`、`test-settings-localization.sh`；实测见 `evidence/patches/z3b-report.md`）
- 剪贴板与历史：粘贴方式、纯文本粘贴、历史保留时间、清空历史。（用户确认）
- 截图：截图后的操作、框选覆盖层（显示十字辅助线）、翻译。（用户确认）
- 快捷键：全部功能快捷键集中管理。（用户确认）
- 隐私与权限：系统权限、排除应用、内容过滤、屏幕共享时显示、链接预览。（用户确认）
- AI 工具：本机 MCP 服务状态及连接配置。（用户确认）

## 文案与状态
- 同一对象、动作和状态在各页使用同一名称，中英文同步。（用户确认）
- 正常界面先写用途、当前状态和操作，技术排障信息按需展开。（用户确认）
- 权限未知、检查失败、尚未生效与已开启待重启分别表达；颜色旁保留文字。（用户确认）
- 敏感内容过滤依据应用标记，不承诺全面识别密码；本机服务可用不等于客户端已连接。（用户确认）
- 标签写对象，按钮写可执行的动作，说明只补充后果、限制和恢复方法。（Agent 推断）

## 组件与交互
- 优先复用 ReplicaSettingsView 的 settingsCard、settingsSectionTitle 及原生控件。（Agent 推断）
- 面板卡片交互矩阵（一次性定死，不另起第二套）：**单击**一张卡片 = 只选中该条，面板保持打开（不复制、不收起，可以继续右键、多选、拖拽）；**双击** = 把该条粘贴到当前应用并收起面板，同时把该条移到其所在分组/列表的第一位；**⌘/⇧ 单击** = 多选（不复制、不收起）；**拖动超过 3pt** = 原生拖拽排序（不复制）；**右键 / ⌃ 单击** = 卡片菜单（「拷贝」仍在），面板不收起；**数字键 1–9** = 快捷粘贴该序号并收起，并把该条移到其所在分组的第一位（历史列表按恢复时间戳自然置顶，与双击一致）。双击判定沿用 AppKit 的 `NSEvent.doubleClickInterval`（第二次按下带 `clickCount == 2`），单击不再挂起任何待决复制，所以选中在 mouseDown/mouseUp 即时生效，多选里的单击仍把选区收拢到被点的那一张。粘贴与收起走与面板 ⌘V/⌘C 相同的既有粘贴路径（`AppMain.paste`）；**所有粘贴路径统一置顶**：双击、⌘1–9、右键「粘贴」、回车、⌘V 与 Stack 菜单都汇入 `ReplicaUIController.paste`，由同一条成功分支调用 `state.movePastedItemsToFront(ids)`，不再由各入口各自补排序，也不依赖剪贴板自捕获副作用。分组条目有手工排序字段 `pinboardOrder`，复用拖拽重排的 `store.reorderItems(ids:in:toOffset:)` 持久化（已带 `pinboardOrder` 的条目按该字段重排，不引入新字段）；历史列表按捕获时间倒序、没有手工顺序字段，恢复写回会刷新该条的 `createdAt`，条目按现有排序语义自然排到首位；搜索与回收站视图不改顺序。粘贴写回带 `com.chrisli.blinkclip.generated` 标记，剪贴板监控跳过自写，因此**粘贴不产生新的历史条目、不产生重复项**。重排在粘贴返回后、面板收起动画（0.2s）结束前同步完成，不另起第二条 hide 路径，也不与 resign-key 的 250ms 复查冲突。（2026-11-18 用户决定 / 原生 harness 实测；取代 2026-11-16 的「单击复制并收起 + 双击判定窗口挂起」）
- 权限状态组件在设置中只出现一次；其他位置如需提示，提供指向唯一管理位置的入口。（用户确认）
- 保留原设置值、保存与清理保护；移动分组不改变数据语义。（Agent 推断）
- 切页、展开帮助沿用原生行为，不新增装饰动效。（Agent 推断）
- 卡片层级随外观同向：浅色卡片纯白（255，页面 236）、深色卡片页面 +12 级（62，页面 50），并加 1pt 内描边维持边界；卡片说明文字（11/12pt）用 58% 前/背景色，两套外观对卡片 ≥4.5:1（实测 5.32:1 / 4.80:1）。（2026-11-14 用户反馈 / 像素验证）
- 六页首元素（无小标题页为卡片，有小标题页为小标题）**顶部对齐**，固定距内容区顶 16pt，六页同一个值；内容超出一屏时从 16pt 起可滚动到底，不再有「装得下则垂直居中」的页面级规则。小标题作为追加层固定在卡片上方 8pt。详见「设置页几何与节奏」。（2026-11-14 用户反馈 / 原生 AX 验证；2026-11-15 订正：撤销上一轮的 `frame(minHeight:alignment: .center)` 页面居中，用户指出他要的是行内选项居中，不是整块内容居中）
- 历史保留期限固定 4 列网格：第一行 1/3/7/15 天，第二行 30/60/永久，第二行末格留空；行、列间距统一 10pt，七块等宽，选中态仍只靠强调边框/底色/字重与辅助功能状态。（2026-11-14 用户反馈 / 原生 AX 验证）
- AI 工具页的“查看连接配置…”放在状态卡底部（分隔线 + 右对齐），卡外不留动作；状态说明与状态标题文字左对齐。（2026-11-14 用户反馈 / 原生 AX 验证）
- 通用页 iCloud 行标题下方为 11pt 状态说明（“上次同步 时间”），开关独占行右端且与文字至少 12pt。（2026-11-14 用户反馈 / 原生 AX 验证）
- 状态语义只用一种图标语言：7pt 实心圆点（绿=正常/可用，红=异常/未授权，灰=未知/检查中），圆点旁必须有文字；权限状态与“本机服务可用”共用同一个圆点组件。（2026-11-14 用户反馈；替换 AI 页灰勾）
- 六页统一 52pt 不透明标题区，内容裁切在标题以下，窗口不使用透明标题栏；中英文与浅深色同步。（Agent 推断；原生离屏验证。2026-11-14 实测：窗口 600pt、内容区 548pt、原生 `.unified` NSToolbar 标题区 52pt，标题项与内容区顶完全对齐。改 `.expanded` 可得到 44pt，但那会放弃六页一致的原生统一工具栏外观，且只多 8pt 可视高度；隐私页 548pt 视口内的内容延伸至 1011pt（下溢约 258pt），8pt 不足以露出折叠内容，故把规范改为实测值。）
- 快捷键页页尾唯一“恢复全部快捷键…”（链接样式，与内容区右上角解耦）管理四项应用、两项截图组合及两类粘贴修饰键；取消零写，保存失败保留原值并就地报错，成功统一刷新六个录制器。（用户确认 / Agent 推断；2026-11-14 管理动作从页首移到页尾并降权）
- 截图只隐藏历史 NSPanel，设置（含其中的关于页）、普通编辑器与附属确认框保持显示。（用户反馈 / Agent 推断；关于不再是独立窗口，2026-11-15 补）
- 系统警告确认框使用普通系统按钮文字颜色，移除 destructive 标记以改善灰底红字可读性；Return、数字 Enter、Esc 安全取消，仅明确确认按钮执行。不宣称完整 HIG 合规。（用户反馈 / Agent 推断）
- 退出二次确认弹窗（快捷菜单「退出 闪贴」）不动结构、只改按钮配色：**「退出」= 系统强调色实心填充 + 纯白文字**，圆角/尺寸/按钮顺序仍是系统那一套（`bezelColor` 只换填充）；「取消」保持系统默认灰白样式。不再用 `hasDestructiveAction`——`.warning` 会把它画成「浅色底 + 红字」，实测浅色 3.55:1、深色 1.23:1。强调色本身（浅色 `#007AFF`）与白字只有 4.02:1、AppKit 渲染的渐变按钮约 4.4:1，所以填充色按「白字 ≥4.5:1」从强调色逐步压深（目标 4.8:1），色相仍是用户选的强调色；压深后实测 **5.18:1（浅）/ 4.97:1（深）**。Return/Esc 仍落在「取消」上。（用户反馈 / 实机截屏验证，见 `evidence/patches/two-fixes-report.md`）
- 历史保留时间使用直接选项块，只提供 1、3、7、15、30、60 天和永久；不提供自定义输入、锁或会员选项。（用户确认）
- 保留期限选中态不显示对勾；使用强调边框、底色、字重及辅助功能选中状态。（用户确认，替代此前勾选标记）
- 说明文字按实际行高布局；正常状态不为隐藏错误预留空白，说明与分隔线间距约 15pt。（用户确认）
- 缩短保留期限可能立即删除过期历史时，使用系统 NSAlert 的布局与按钮；取消不得保存，窗口关闭后恢复父页交互。（Agent 推断；隔离原生与父页离屏验证通过，物理操作未验）
- 保留期旧非预设值只读展示，打开不自动改写；选项仅有上述七项，缩短保护保留。（Agent 推断，保护既有设置）
- 历史卡片来源应用图标完整适配原启动图标的比例与轮廓，不放大后裁切，不重绘图标资产。（用户确认）

## 面板卡片配色
- 卡片前景、说明与脚注颜色一律在渲染时由当前 `effectiveAppearance` 与卡片实际底色推导，不在创建时固定 appearance；底色本身是动态色时，先在调用方的有效外观里读一次，再解析成静态色下发。反例：旧的脚注视图覆盖 appearance、在创建时取色，切浅/深后脚注带与文字停在旧外观（ΔRGB = 0）。（2026-11-15 源码核对：`CompactTextFooter.swift`）
- 来源内容自带深色底（网页、富文本卡片）的卡片保留还原语义：正文与脚注按卡片底色所在的一侧取色，不跟随窗口外观；只有纯文本卡片的底色本身是动态色（浅 255 / 深 20），才随外观走。验收：深底卡片切到浅色外观后仍是亮字压深底，脚注仍比带底亮。（2026-11-15 源码核对：`CompactTextFooter.swift` 的 `isLightBackground` / `resolved`、`PreviewTextColors.swift`）
- 卡片正文对卡片底色 ≥4.5:1；设置页说明文字实测 5.32:1（浅）/ 4.80:1（深），断言取 `SettingsSurfaceStyle.contrastRatio`，不看截图。（2026-11-15 数值核对）
- 面板卡片脚注（「N 个字符」、渐隐带）对卡片底色 ≥4.5:1，两套外观都已达标：脚注不再共用工具栏的 50% 黑，改由独立的 `FooterAppearance.secondaryForeground()` 提供——浅色 58% 黑、深色 55% 白；来源自带底色（网页、富文本）把脚注压到 5:1 以下时，`contrastSafe` 只沿黑/白一侧加不透明度兜底，不换色相、不降不透明度。（2026-11-15 订正：P5 已改实现，旧稿「浅色 3.98:1 未达标、待改口径」与当前实现相反）
- footer 对比度口径（5.32 / 5.33 是同一颜色的两种量法）：浅色 58% 黑压白卡记 **5.33:1**（像素采样：8-bit 合成级 107 = `#6B6B6B`，复算 5.3292）与 **5.32:1**（按 alpha 0.58 直接做 WCAG 复算，5.3213）；**验收值取像素采样的 5.33:1**，因为回归闸门就是渲染后逐像素测量，5.32 只作独立交叉核对，两者都过 4.5:1。深色 55% 白保持原值：文本卡（20 底）实测 6.15:1／复算 6.17:1，链接卡 5.08:1。修复前浅色 50% 黑只有 4.00:1（U5 实测）／3.95:1（复算）。来源浅灰底（`#D1D1D1`）按 5:1 兜底到 5.28:1。断言阈值由 2.5:1 提到 4.5:1。（2026-11-15 源码：`FooterAppearance.swift:21` `targetContrast = 5.0`、`:24-25` 浅 58% 黑／深 55% 白、`:69-88` `contrastSafe`；`CompactTextFooter.swift:58-68`；`TextCardAppearanceHarness.swift:81` 低于 4.5 即记违规、`:305-310` 文本卡 footer 采样、`:402-408` 链接卡 footer 采样；实测值见 `CHANGELOG.md:9`）
- 卡片与页面的层级方向、数值与描边沿用「组件与交互」的卡片层级条，不另立第二套；本节的验收口径是：两套外观下卡片亮度恒高于页面（浅 255 > 236、深 62 > 50），差值 ≥8 级，1pt 内描边对卡片 ≥1.05:1。（2026-11-15 断言核对：`SettingsArchitectureHarness.swift`）

## 卡片内容区与截断
- 卡片是正方形，**标题条固定高度**（`ReplicaClipboardCard.headerHeight`：卡片 280pt+ 为 56、240–279 为 52、200–239 为 48、200 以下为 36/34），标题条永不参与正文的尺寸协商：正文高度 = 卡片高 − 标题条高 − 脚注带高，标题条先拿满自己的高度，正文只用剩下的。反例（已修）：正文放在 `.padding(.top, bodyTop)` 的 VStack 里，长文本的自然高度把 ZStack 撑到比卡片更高，外层 `frame(sideLength, sideLength)` 再把它居中，标题条被顶出卡片上边界——2000 字符的 shell 单行卡片完全没有标题条，正文从卡片顶端开始画。
- 纯文本/富文本卡的正文区高度 = 卡片高 − 标题条高 − 脚注带（50pt；小卡 32pt）。正文超出行数上限时**尾部省略号截断**：行数上限 = floor(正文区高度 ÷ 实测行高)，实现用真实排版高度二分找「最长前缀 + `…` 仍放得下」的切点，`…` 落在最后一行末尾；无空格长串（长 URL、长 token）在词中间断开（Core Text 对超长词本来就会退到字符级断行），所以不插零宽空格——那会改动用户可见的文本，而这里只需要截断预览。SwiftUI 文字分支用 `lineLimit(上限)` + `truncationMode(.tail)` 表达同一条规则。
- 正文永远不越过卡片边界：正文容器定高并 `clipped()`，图片/色块/文件/链接卡共用同一条几何；`sizeClass` 3 的满幅卡片（图片、色块、链接预览）正文起点仍是 0（铺满卡片、标题条透明浮在其上），这是既有设计，不因本条改变。
- 验收：原生 harness（`test-ui-interaction.sh` 的 `assertCardContentOverflow`）用 2000 字符单行、无空格长 token、40 行多行文本、长 URL 链接卡与图片卡各一张，在面板高 332/420（卡片 240/328）下断言：标题条矩形 [0, headerHeight] 与正文矩形不相交、正文不出卡片、文本渲染行数 ≤ 上限且以 `…` 结尾、label 不出正文区、脚注带不与正文重叠。回归探针（旧布局）在该断言上的失败原文：`标题条越出卡片顶部区间：title=(top: -48.5, bottom: -29.5, height: 19.0) headerHeight=52.0`。（2026-11-17 用户反馈 / 窗口级 2x 截屏 + 原生断言；证据 `evidence/patches/card-overflow-report.md`）

## 设置页几何与节奏
- 六页内容区统一左右 20pt、顶 16pt、底 20pt（`SettingsPageMetrics.horizontalInset = 20` / `topInset = 16` / `bottomInset = 20`）。内容**顶部对齐**：第一个内容块固定距内容区顶 16pt，六页一致；底部 20pt 只在内容收尾/滚到底时成立。（2026-11-15 源码：`AuxiliaryViews.swift` 的 `SettingsPageMetrics`）
- 垂直节奏只有一条：`ScrollView { content.padding(.top, 16).padding(.bottom, 20) }`，内容超出一屏才滚动。六个分区都不按「装得下/装不下」改首元素位置，也**没有** `frame(minHeight: proxy.size.height, alignment: .center)`。反例（已撤销）：把带内边距的内容块放进最小高度等于可视高度的 frame 求居中，短页会整体浮在内容区中间，用户看到的是「内容区上下居中了」而不是「设置项在行内居中」。（2026-11-15 源码：`AuxiliaryViews.swift` 的 `SettingsPageScroll`；用户反馈原文：「为什么内容区域上下居中了？我说的是其中的选项」）
- `GeometryReader` 只有关于页用了一个（`AuxiliaryViews.swift` 的 `about`）：它把内容块的最小高度设成「内容区高 − 上下页边距」，好让页脚贴到内容区底部；六个分区与 `SettingsPageScroll` 都不用，页面级居中仍然没有回来。空间不足时关于页退化成普通滚动页，页脚随页面滚到底。（2026-11-15 源码核对：旧稿「没有 GeometryReader」已与实现不符，按事实订正）
- 断言口径：六页首元素距内容区顶一律 16pt（±0.5pt）；装得下的页一格都不滚且底部留白 ≥19pt；装不下的页从 origin 0 起滚，滚到底后最后一个内容块距内容区底 20pt（±1.5/4pt）。出货 648×600 下通用、截图、剪贴板、快捷键、AI 五页装得下不滚，隐私页超出一屏可滚——**位置规则相同，只差是否滚动**。（2026-11-15 断言：`SettingsArchitectureHarness.swift` 的 `checkPageSurface` 与 `topGap` 汇总）
- 小标题作为追加层固定在卡片上方 8pt，见「组件与交互」；本条目只管内容块上下的节奏与左右 20pt 边距。
- 卡片圆角 12pt、1pt 内描边、左右内边距 10pt；小标题左缩进 10pt，与卡片内文左缘对齐。
- **每行在自己的可见区域内垂直居中**：行的上下边界由卡片外边缘或相邻分隔线确定。留白由每行各自提供，卡片不在首行和末行外额外加上下留白；单行上下各 9pt，带说明的行各 8pt。内容折行时行随内容长高，文字和控件继续共用中线。剪贴板与截图页的单选圆点也对齐标题和说明的整体中线，读屏仍使用原生单选组语义。验收以行和控件的框为准，字形升部与降部的像素差不作为布局误差。
- 选项组固定 4 列网格：七块等宽、块高 44pt、行与列间距统一 10pt、第二行末格留空，列数不随窗口宽度变化。验收：七块宽度集合只有一个值、列间与行间差 ≤0.01pt、第二行只有三块且末列无块。（2026-11-15 断言核对：`HistoryCapacityControl.swift`、`SettingsArchitectureHarness.swift`）
- 行内控件与文字块**垂直居中（误差 ≤0.5pt）**：每一行（标题 + 可选说明 + 右侧控件）里，右侧开关/下拉/按钮的外框中心必须与该行文字块中心同一条中线——**单行对文字中心，多行对整块中心**（如「iCloud 同步」标题 +「上次同步 10:00」说明，开关对两行整块的中心，不是只对标题）。对齐只用布局：`HStack(alignment: .center)` + 文字块与控件同处一个行高，禁止用上下 padding/offset 把控件「看起来挪正」。（2026-11-15 用户反馈 / 像素与 AX 实测：通用页 5 行 + 截图页 1 行 + 隐私页 2 行、AI 页状态圆点，全部 ≤0.5pt；源码 `AuxiliaryViews.swift` 的 `settingsRow` / `settingsRowSwitch`、`CloudKitSyncController.swift` 的 `ICloudSyncGeneralRow`；断言 `SettingsArchitectureHarness.swift` 的 `checkRowAlignment` / `checkAIStatusDotAlignment`）
- 行内开关独占行右端、与文字间距 ≥12pt（`Spacer(minLength: 12)`），不贴行底、不挤标题。验收：开关左边减行文字右边 ≥11.5pt。
- 标题区沿用 52pt 不透明条，新增页面不靠额外内边距补高度；52pt 的实测值与取舍见「组件与交互」，此处不重复论证。（沿用「组件与交互」实测值）

## 关于页几何
- 关于沿用设置窗口右侧的第七页，所有现有入口都落到同一页。按任务分三层：顶部依次展示闪贴图标、名称、已装版本和说明。软件更新卡片左侧显示状态，右侧放「检查更新」。关于页页脚贴齐内容区底部，空间不足时随页面滚动。版权在上，下一行居中并排四个链接，按「离读者多远」排序：官方网站 → 更新日志 → AGPL-3.0 许可证 → 源代码（官网是 GitHub Pages 上的产品站 `https://aexachao.github.io/BlinkClip/`，源代码仍指仓库根）。
- 顶部沿用 16pt 页边距；图标按布局框量，资产透明边缘不参与测量。更新操作始终只有一个主按钮；检查中禁用，检查状态继续由同一份模型提供。
- 状态文案必须带时间戳或具体事实：「上次检查 HH:mm」用 24 小时制、语言无关，完成过检查才出现；未检查前只写「尚未检查更新」，不得断言“已是最新”——Sparkle 自己的弹窗已经说过，内联不再重复。（2026-11-15 核对：`BlinkClipUpdateChecker.swift`、`AppUpdateHarness.swift`）

## 危险动作
- 清空、重置类动作放在所属区域底部（内容区页尾、与卡片右缘对齐），不进卡片正文、不占页首；危险性质只用系统红（`NSColor.systemRed`）做文字强调，不新增按钮样式。（2026-11-15 断言核对：`AuxiliaryViews.swift` 的 `settingsFooterAction`、`SettingsArchitectureHarness.swift`）
- 确认弹窗必须写明影响面：条数 + 不可撤销 + 会保留什么（“已钉到分组的项目会保留”）；弹窗里的条数必须与真正删除/重置的条件逐字一致，不另算一遍近似值。（2026-11-15 源码核对：`SettingsDangerAction.swift`）
- 条数可算的动作把条数写进确认键（「清空 N 条」）；固定集合的动作（恢复全部快捷键）确认键写「恢复默认设置」，并在正文点名 6 条。（2026-11-15 源码核对：`SettingsCopy.swift`）
- 取消必须零副作用：取消是第一按钮并占 Return，危险按钮不绑快捷键，`apply(confirmed: false)` 直接返回、不写偏好。反例：把危险按钮设成默认键，误按 Return 就等于清空。（2026-11-15 源码核对：`SettingsDangerAction.swift`、`SettingsShortcutReset.swift`）

## 状态与反馈
- 可重复执行的刷新类操作必须有可见的三段反馈：进行中（按钮禁用 + 「正在刷新…」）→ 完成（「已刷新 · HH:mm」）→ 停留 3 秒后 0.25s 淡出回「刷新状态」。反例：点下去毫无变化，或停在完成态不再复位，用户无法判断刷过没有。（2026-11-15 源码核对：`PermissionStatusView.swift` 的 `PermissionRefreshControl`）
- 刷新入口的作用范围要能被读出来：与卡片标题同一行、右对齐、压在卡片上方，明确刷新整张卡片，不缩进卡片底部假装只刷新某一行。验收：与标题中位差 ≤3pt、与卡片右缘差 ≤2pt。（2026-11-15 断言核对：`SettingsArchitectureHarness.swift`）
- 冲突与错误提示落在触发行正下方 ≤8pt（现为 4pt），文案指名对象（「此快捷键已被“历史面板”占用」）；被拒的组合不写进偏好、不结束录制态，不另设整页共享错误条。（2026-11-15 源码核对：`AuxiliaryViews.swift` 的行错误与冲突判定）
- 状态图标只有一种语义：7pt 实心圆点，圆点与文字间距 5pt，圆点对读屏隐藏、语义由文字承担；沿用「组件与交互」的图标条目，这里只补间距与读屏口径。（2026-11-15 源码核对：`PermissionStatusView.swift` 的 `SettingsStatusDot`）
- **toast 规范（四条轻提示共用一套）**：复制 / 暂停（含定时）/ 继续 / 截图已复制都由同一个组件 `ReplicaToast` 弹出——**固定 128×128pt 的深色 HUD 盘**（`material = .hudWindow`，appearance 固定 `vibrantDark`，所以浅色系统外观下也是深底；圆角 16pt、**底盘不加描边**）。**底盘不加描边，边界靠 HUD 材质与 16pt 圆角自身区分**：1.0.24 的`borderWidth = 1` + `NSColor.separatorColor` 那条边——盘面外观固定 `vibrantDark`，而 `separatorColor` 是动态色，`.cgColor` 在这个上下文里解析成**不透明 #232323（35/255）**，两套系统外观下都是同一条深灰边（2x 实机：盘面最外 2px = 35/35/35，盘内材质 = 148/155/159，差 ~120/255），浅色壁纸上看过去就是一圈黑框。**也不加投影**：盘面就是窗口内容，128×128pt 的窗口会把图层投影整条裁掉，而为了投影把 `masksToBounds` 关掉又会让 16pt 圆角变回直角；系统窗口投影不可调、实机是包在圆角盘面外的**方框**，紧贴外沿 2px 被压到比壁纸深~52/255（远超「外沿环带与壁纸差 ≤ 8/255」）。所以描边与投影两者都不要，圆角只靠 `masksToBounds` 收口。（2026-11-16 用户反馈「toast 有黑边」；逐像素见 `evidence/patches/tb-report.md`）。盘内**上图下字**并整块居中（上下留白差 ≤0.5pt、水平居中 ≤0.5pt）：图标在上（SF Symbol **42pt**、weight .medium），**图标与文案间距 16pt**，文案在下（**14pt semibold**、居中、行距 2pt、最多 2 行）。**图标与文案一律白色**（不跟随强调色/accent），语义只靠符号区分（checkmark / pause / arrow.clockwise）；白字压深底在浅色与深色两套系统外观下的对比度都要 ≥ 4.5:1（实测值见 `t2-report.md`）。盘面尺寸**不随文案变化**。位置固定在**屏幕底部居中**：底边压在 `NSScreen.visibleFrame.minY + 120pt`（即 Dock 上沿 / 屏幕底上方 120pt），水平按 `visibleFrame` 居中，所以 Dock 在底部、在左/右或自动隐藏都不会压住它。时长统一 **1.3s 停留 + 0.2s 淡出**（验收区间 1.2–1.5s），连续触发复用同一实例、只重置计时，不叠加第二个 toast。**不抢焦点**（`.nonactivatingPanel` + 无动作时 `ignoresMouseEvents`，`canBecomeKey/Main = false`，`orderFrontRegardless` 不激活 App），窗口级别取 `.screenSaver + 5`，比 capcap 截图编辑器的浮层（`.screenSaver + 3/+4`）更高。**不入图**：`sharingType = .none` 必须**实际生效**（窗口服务器实测 `CGWindowSharingState == 0`）——注意 `WindowSharingPolicy` 会在 `didExpose/didUpdate` 上把每个窗口写回 `.readOnly`，所以 toast 面板把 `sharingType` 的读写都钉在 `.none`；截图开始前仍先 `hide()` 兜时序。文案只写一次、只占一处：**不允许第二行小字复述同一句话**，暂停有定时时把时间并进同一句（「已暂停采集 · 至 14:30」）；复制 toast 的可点击动作（启用直接粘贴）靠**整块可点 + 手型光标**表达，不额外加副标题。四种 toast 的文案只有一个三语来源 `ReplicaToastCopy`（en / zh-Hans / zh-Hant 同键集：`Copied`/`已复制`/`已複製`、`Capture paused`/`已暂停采集`/`已暫停擷取`、`Capture resumed`/`已恢复采集`/`已恢復擷取`、`Screenshot copied`/`已复制截图`/`截圖已複製`），术语与设置页/状态栏的「暂停采集 / 继续采集」一致，繁体用「擷取」；繁体不再回落到英文。与「播放操作提示音」无关：声音偏好照旧生效；截图失败分支仍只 beep，不弹「已复制截图」。（2026-11-15 T2 统一；源码 `ReplicaToast.swift` / `ReplicaToastCopy.swift` / `ReplicaCopiedOSD.swift`，调用点 `ScreenshotCoordinator.complete` / `present`；断言 `CaptureIntegrationHarness.swift`（同一窗口类、128×128 固定盘面、盘内居中 ≤0.5pt、图标 40–44pt（取 42）、14pt/2 行/2pt 行距、图标与文案白色、底板恒为深色、底部几何、`CGWindowSharingState`、无第二行小字）、`SettingsLocalizationHarness.swift`；实测见 `evidence/patches/t2-report.md`）

## 截图框选覆盖层
- 主色只有一个：选框边框、8 个手柄、尺寸标签底色、空闲态窗口悬停边框统一用 `selectionTint`（`NSColor.controlAccentColor` 解析成 sRGB，失败才回落 `systemBlue`；本机实测 `#007AFF` / rgb(0,122,255)）。滚动截图的红色边框是防渗色标记，语义不同，保持 `systemRed`，不跟蓝。（2026-11-16 用户要求；源码 `replica/Vendor/capcap/Capture/SelectionView.swift` 的 `selectionTint` / `drawHandles` / `drawSizeLabel`）
- 边框一律实线、且**四态同一视觉重量 1pt**（2x 屏上正好 2 设备像素、1x 屏上 1 像素）：空闲悬停、拖动中、已选中、滚动截图四条边框都用 `borderWidth = 1`，描边路径按 `insetBy(-borderWidth/2)` 贴选区外侧，正好压在外沿一圈、不侵入选区内像素。改前实测（2x，同一条上边逐像素扫描）悬停 3pt / 6px、拖动 2pt / 4px、选中 2pt / 4px、滚动红框 3pt / 6px，用户报的「悬停比框选粗」就是 3pt 对 2pt；现在四态全为 1pt / 2px。（2026-11-16 用户反馈「两种模式边框粗细不一致」；实测见 `evidence/patches/pol-report.md`）
- 手柄不用圆点，改用 macOS 截图工具那套**短横条 + L 形角标**（颜色仍是 `selectionTint`）：上下边中点是 **20×4pt 水平横条（圆角 2pt）**，左右边中点是 **4×20pt 竖直横条**，横条以边线为中心上下各占一半；四个角是 **L 形角标**——两段 **12pt 长、2pt 厚**的直角线段沿角的**内侧**绘制，与 1pt 边框连成一体。绘制几何按屏幕像素网格对齐（2x 下 20×4pt = 40×8px，不出现 41×9 的模糊边）。抓取范围 **22×22pt（≥20×20）**，八个手柄 ±10pt 内都能命中；改前是 `handleSize 8` 的圆点、命中 12×12pt。（2026-11-16 用户要求「不要圆点，用之前截图里的小横条手柄，拐角也要相应改」）
- 尺寸标签：蓝底（`selectionTint`）+ 白字 13pt semibold、等宽数字，内边距 10×6，圆角 6pt，向下 1pt / 模糊 4pt 的黑色 35% 投影；文案用乘号而非小写 x（`500 × 260`，滚动截图缩放时追加 `(67%)`，与 App 内其他尺寸角标同一写法）；贴选框左上角上方 **8pt**，**不压进选区内部**（选区内像素要入图），也不压住左上角角标（间距 6pt 时胶囊会贴到手柄上）。（2026-11-16 用户要求）
- **尺寸标签必须在屏幕 `visibleFrame` 内：优先左上外侧，顶部不足翻到下方，左右越界平移。** 取该视图所在屏幕的 `visibleFrame`（避开菜单栏/Dock；多屏用 `window?.screen`，回退 `NSScreen.main`），默认仍是「上方 8pt、左边对齐」；上方放不下时翻到选区**下方外侧 8pt**；左右越界时平移回屏内（各留 4pt 边距）；下方也放不下（极端小屏/超大选区）才允许压在选区内部，但矩形必须完整落在 `visibleFrame` 内。任何情况下胶囊的 minX/maxX/minY/maxY 都在屏内，除该极端例外外与选区内部重叠面积为 0；尺寸/字号/圆角/颜色/文案不变，覆盖层与编辑器共用 `SelectionView.sizeLabelRect(for:in:text:)` 这一份几何。（2026-11-16 用户反馈「贴顶时标签被裁掉」）
- **框选辅助线（1.0.25 形态，REV 恢复）**：**贯穿全屏**的横竖两条**实线**，**随指针实时更新**——水平线跨满整屏宽、竖线跨满整屏高，交点就是指针位置。样式为 **1.5pt `systemGray` 50% 实线**；只在 `.idle` / `.drawing` 显示，`.selected` / 滚动截图 / 编辑器接管时隐藏。**独立图层 + 同步更新**：辅线不在 `draw(_:)` 里，而是每条轴各一个 `CrosshairBandView`（独立 `CAShapeLayer`）；`mouseMoved` / `mouseDragged` / `mouseEntered` 只改这两条图层的 `frame` 与 line path，在 `CATransaction.setDisableActions(true)` 事务里提交，随后对图层 `displayIfNeeded()` 同步显示——位置属于本次鼠标事件，不等下一轮 runloop，鼠标移动期间 `draw(_:)` 调用数 = 0。多屏：控制器把同一个屏幕坐标**跨屏广播**给各屏遮罩，每屏只写自己需要的那一轴——指针所在屏两条线都动，其它屏只更新水平线（竖线落在 bounds 外自然隐藏），于是水平线跨屏连续、竖线只出现在指针所在屏。**做**：辅线默认开，**可通过设置关闭**——设置 →「截图」→「框选覆盖层」→「显示十字辅助线」（键 `blinkclip.screenshot.showCrosshairGuides`，缺键 = 开；关闭后只是不画这两条贯穿辅线，选框本体、尺寸标签、暗化、窗口 hover 高亮、放大镜与系统十字光标一律不变）。**不做窗口吸附、不做拖拽吸边**：不描窗口四边、没有「显示中线」设置、拖拽时选区边缘不吸附到窗口边（1.0.26–1.0.29 的 SG/SNAP2 行为已撤销（见文末 REV））。**窗口 hover 高亮独立存在**：空闲态悬停窗口的暗化挖孔、1pt 强调色边框与尺寸标签是另一套图层（`HoverHighlightView`），与辅线互不影响；指针仍是系统十字光标（见下一条）。**选框本体保持原样**：蓝色 1pt 实线边框、边中点 20×4pt 横条、四角 12×2pt L 角标、蓝底白字尺寸标签。
- **覆盖层分层与 Space 行为**：选区外观（暗化挖孔、1pt 定义框、八个手柄、尺寸标签、滚动截图红框）全部在 `SelectionChromeView` 子图层里，`draw(_:)` 只画冻结快照；拖拽的每次事件只做 `CATransaction.setDisableActions(true)` 内的几何/path 写入 + `displayIfNeeded()`，几何未变提前返回——`draw(_:)` 在整段拖拽里 0 次调用（源码门 + harness 实测）。覆盖层窗口 `collectionBehavior` 含 `.stationary`，切 Space 时覆盖层保持原位、快照不随 Space 滑动。（2026-11-17 REV：保留 SNAP2 的分层与 `.stationary` 成果，删除其拖拽吸附本身。）
- 框选期使用**系统十字光标**（`NSCursor.crosshair`，硬件合成、零延迟）：覆盖层视图在 `resetCursorRects()` 里 `addCursorRect(bounds, cursor: .crosshair)`，覆盖层激活时再 `NSCursor.crosshair.set()`。**不再自绘、不再隐藏系统光标**——全仓库没有 cursor hide/unhide 调用、没有 CG 光标隐藏调用、没有隐藏/恢复状态机，也就不存在 1.0.23 那种「AppKit 在非激活时吞掉 unhide、光标一直隐藏」的失败模式：退出/失活不需要任何恢复，因为系统光标从未被隐藏。自绘光标视图、pointer-drawn 状态回调与系统光标隐藏器全部删除（源码门禁止这些符号再次出现）；harness 在五轮开关里拦截 cursor-hide 入口并断言 0 调用。辅助线与指针都不入图（成图取自遮罩出现前的预抓屏裁剪，遮罩窗口本身在抓屏排除集合里）。
- 边框、标签、辅线都画在 `SelectionView`（遮罩窗口）的图层里（快照仍由 `draw(_:)` 画，其余全是子图层），**均不入图**：成图取自遮罩出现前的预抓屏裁剪（`ScreenCapturer.crop(from: preSnapshot…)`），遮罩窗口本身也在会话抓屏排除集合中。验收：框选区域的成图与遮罩撤掉后同区域 `screencapture` 逐像素比对 ΔRGB 全 0，成图里 `#007AFF` 像素数为 0。（2026-11-16 像素验证，见 `evidence/patches/sel-report.md`）

## 浅深一致性验收
- 同一元素在两套外观下的间距、字号、控件尺寸像素一致（≤1px）：切外观只换颜色，不换布局。验收：同一页分别按浅、深渲染，对同名 AX 元素帧逐项比对，差值 ≤1pt；现有逐页契约（首元素顶边距 ≥16pt／短页居中、录制器 120×24、保留期 44pt 块）在两套外观下各跑一遍。（2026-11-15 断言核对：`SettingsArchitectureHarness.swift`）
- 颜色层级方向一致：卡片恒比页面亮（浅 255 > 236、深 62 > 50，差 ≥8 级），说明文字恒比正文暗但 ≥4.5:1；不接受任一外观下“卡片比页面暗”的例外。（2026-11-15 断言核对：`SettingsArchitectureHarness.swift`）
- 以上是组件级证据：离屏渲染通过只证明颜色数学与 AX 几何，实际可见窗口的浅/深切换仍单独验收，不拿离屏结果替代。（沿用「样板与验收」的离屏口径）

## 样板与验收
- 用户完整截图确认旧自定义确认框存在，问题为大面积留白与比例失衡。本轮已移除对勾、收紧说明间距并使用系统 NSAlert；隔离 UI 与父页中英验证通过，实际物理操作、真实历史清理及 TCC 未验。重复同值不触发布局失效，保留期不再重设无关窗口外观；保存仍同步，不承诺零卡顿。（用户反馈 / Agent 推断）
- 七项保留期限选项块与完整来源图标的隔离原生自验、主控三轮及 15 图盲审通过；父设置页 640pt 中英文布局通过；浅 / 深色只按组件证据范围验收，实际可见窗口仍未验。本机包替换与独立部署审计通过。（Agent 推断）
- ReplicaSettingsView 六页作为信息分组与文案样板；最后文案三轮中英隔离原生验证及两轮不打分视觉审查通过，证据见 replica/TESTING.md，实际可见窗口仍未验。（Agent 推断）
- 检查中英文最小窗口宽度、长文案、状态失败及截图设置深链。（Agent 推断）
- 离屏截图不替代可见界面验收，隔离数据测试不代表真实历史清理或系统授权通过。（Agent 推断）

## 编辑器选框与放大镜
- **编辑器 live 选框与框选覆盖层共用同一套选框 chrome（1pt 实线 + 边中点横条 + 四角 L 角标 + 22×22pt 命中区），不得各自绘制**：编辑器那一层（`SelectionChromeOverlay`）只负责命中与绘制时机，形态一律调用覆盖层的 `SelectionView.drawSelectionChrome(in:rect:showsHandles:sizeLabel:)`——边框、8 个手柄、尺寸标签、抓取范围都只有一份实现。改前编辑器自己画 `2pt / [6,4]` 虚线边框 + `8pt` 圆点手柄、命中 12×12pt，与覆盖层的 1pt 实线 + 横条 + L 角标同时上屏，松手进编辑器就能看到「虚线圈着 + 圆点 + 横条 + L 角标」叠在一起。验收：编辑器 live 选框渲染出的强调色实心像素集合与覆盖层逐像素相同（`EditorChromeParityHarness`、`replica/scripts/test-editor-chrome-parity.sh`），实机 2x 截图同一选框处圆点数 0、虚线段数 0、边框 2px（1pt），角内 9pt 按下可缩放、12pt 按下不可。（2026-11-16 用户要求「两套 chrome 并存是真问题，统一掉」；源码 `replica/Vendor/capcap/Capture/SelectionView.swift` 的 `drawSelectionChrome` / `drawHandles`、`replica/Vendor/capcap/Editor/EditWindowController.swift` 的 `SelectionChromeOverlay.draw`；实测见 `evidence/patches/ec-report.md`）
- **编辑器选框、8 个手柄、长截图裁剪边线、放大镜十字与框选覆盖层同色（跟随系统强调色）**：统一取共享常量 `selectionAccent`（`replica/Vendor/capcap/UI/SelectionAccent.swift`；`NSColor.controlAccentColor` 解析成 sRGB，失败才回落 `systemBlue`，本机实测 `#007AFF` / rgb(0,122,255)）。**全产品只有这一份选区色定义**：覆盖层的 `SelectionView.selectionTint` 已改为引用这个常量（不再自带表达式），编辑器与放大镜里也不重写第二份字面色值——改色只改这一个常量。（2026-11-16 用户要求；源码 `EditCanvasView.swift` 的 `selectionOutlineColor` / `drawSelectionHandles`、`EditWindowController.swift` 的 `SelectionChromeOverlay.draw`、`ScrollCropView.swift` 的裁剪边线与手柄、`UI/MagnifierLensPanelWindow.swift` 的 `drawMagnifiedArea`；实测见 `evidence/patches/ed-report.md`）
- 「选区语义」与「工具语义」两条色不混：选框/手柄/裁剪边线/放大镜十字走 `selectionAccent`（跟随系统强调色）；工具栏选中态、工具组下拉对勾、美化预设与色板选中环、粗细滑块充填、填充样式分段控件、二维码悬浮光圈仍用 `accentGreen`（0,212,106），因为它们表达「当前启用哪个工具/选项」，不是「选区在哪」。要整体换品牌强调色时改 `accentGreen` 一处即可，两条色互不影响。（2026-11-16 取舍说明）
- 编辑器 live 选框**不再自带形态**：1pt 实线边框、边中点横条、四角 L 角标、尺寸标签都由覆盖层的同一个绘制函数画出（编辑器只决定「什么时候画」和「命中谁」），因此不存在「编辑器版选框」与「框选版选框」两套观感；命中区同样走 `SelectionView.handleHitSize`（22×22pt），编辑器不再有自己的 12×12pt。虚线语义作废：全产品选框一律实线。（2026-11-16 EC 统一；改前那条「编辑器选区框仍是虚线、与实线取景框区分语义」的规定已撤销）

## 编辑器浮动工具栏
- **工具栏按 macOS 标准工具栏尺寸：16pt 图标 / 36pt 行高 / 46pt 条高**。几何只有一处来源：`ToolbarChrome.rowHeight = 36`、`symbolPointSize = 16`（weight 仍是 `.medium`）、`surfacePadding = 5`、`surfaceCornerRadius = 7`、`highlightCornerRadius = 5`、`highlightInset = 2`；条高 = 行高 + 上下各 5pt 的 cross padding（`ToolbarView.crossPadding = 5`），即 36 + 10 = **46pt**，改前为 40 + 12 = 52pt。分组按钮宽度按比例取 52pt（36pt 工具区 + 16pt 下拉箭头区），按钮间距 6pt、两端 15pt 不变。图标观感：16pt 字形在 36pt 行里占 44%，与系统工具栏一致；按钮命中区仍是完整的 36×36pt（≥32pt 可点性下限）。改前 18pt 图标压在 40pt 行里，行高偏松、整条 52pt 比系统工具栏厚。
- **工具条与下拉菜单共用同一批常量，不得各走一套**：`ToolbarGroupMenuRow` 的图标取自 `ToolbarChrome.symbolPointSize`，行高/内边距取自 `ToolbarChrome.rowHeight` / `surfacePadding`，面板高度 = `surfacePadding × 2 + rowHeight × 行数`（三行时 5×2 + 36×3 = 118pt）。验收口径：同一份常量同时驱动条与菜单，出现「工具条 36 / 下拉 40」即判失败（`ToolbarUploadRemovalHarness` 的 `hoverChecks` / `dropdownChecks` / `glyphChecks`，`replica/scripts/test-toolbar-upload-removal.sh`）。
- 口径与实测：2x 离屏渲染下量单个图标的字形墨迹高度（alpha≥25% 的纵向范围），18pt 时 27–42px（常见 33–38px），16pt 后 24–38px（常见 29–34px），且每个字形都按 16/18 等比缩小（±2px 内）；条高 52 → 46pt、面板高 132 → 118pt。（2026-11-17 用户要求「图标改成 macOS 标准工具栏尺寸」；源码 `ToolbarChrome.swift`、`EditWindowController.swift` 的 `ToolbarView`、`ToolbarGroupMenu.swift`；数据见 `evidence/patches/toolbar16-report.md` 与 `evidence/patches/toolbar16-renders/`）

## 2026-11-11 自有素材接入

A1 设置四态、A2 类别四种和 A5 通用权限插图由基本几何独立绘制；中英文重新撰写，其他语言明确回退英文。源稿审查与源码接入完成，本机 arm64 包 / 安装已验，新的 Universal 正式发布与商店专项仍分别验收，不把候选图审查当作实际安装验收。主 mark 保留现选取景框与折角卡片；源证据、提取研究材料边界和第三方许可见 `branding/BlinkClipAssets/PROVENANCE.md`、`NOTICE.md` 与 `docs/BRAND_ASSET_REPLACEMENTS.md`。

## 变更记录
- 2026-11-17 CO：面板卡片标题条固定高度、正文区固定为「卡片高 − 标题条 − 脚注带」，超长内容尾部省略号截断（长文本/长 URL/多行/图片在正文区内的几何由原生 harness 断言）。规范见「卡片内容区与截断」。
- 2026-11-18 QP：面板内所有粘贴路径统一置顶：双击、⌘1–9、右键「粘贴」、回车、⌘V 与 Stack 菜单都经 `ReplicaUIController.paste` 的同一成功分支调用 `movePastedItemsToFront`，分组用 `pinboardOrder` 持久化；历史列表由恢复写回刷新 `createdAt` 自然置顶。粘贴写回带自写标记，监控不捕获，因此不新增历史条目、不产生重复项；数字键不再依赖捕获副作用。规范见「组件与交互」的卡片交互矩阵。
- 2026-11-18 CLK：面板卡片单击改回「只选中、面板不收起」，双击改为「粘贴 + 收起 + 移到所在分组首位（`pinboardOrder` 持久化）」，右键 / ⌃ 单击菜单在面板打开时照常弹出；去掉单击挂起的 `doubleClickInterval` 待决复制（双击仍按系统判定窗口，不再有「复制 + 粘贴」双动作风险）。历史列表没有手工顺序字段，不参与重排；数字键快捷粘贴行为不变。规范见「组件与交互」的卡片交互矩阵。
- 2026-11-16 CK：面板卡片单击从「只选中」改为「复制该条目并收起面板」，双击粘贴 / ⌘⇧ 多选 / 拖动排序 / 右键菜单保持不变；用双击判定窗口把单击挂起，双击只粘贴一次。规范见「组件与交互」的卡片交互矩阵。
- 2026-11-15 补充面板卡片、设置节奏、关于页几何、危险动作与状态反馈规范。（本轮评审后落地）
- 2026-11-15 对齐 footer 对比度、设置页居中规则与关于页单按钮。
- 2026-11-15 X1a：撤销页面级垂直居中（六页顶对齐 16pt、可滚动），补「行内控件与文字块垂直居中 ≤0.5pt」与「通用页按职责分三组」两条规范。
- 2026-11-15 Z1：卡片内容垂直居中（上下留白差 ≤0.5pt）。行高改成「内容 + 上下对称内边距」（`SettingsRowMetrics`），卡片里的复选框/页脚说明/按钮行/保留期网格自带留白（当时的 `SettingsCardBlock`，该结构已被 2026-11-15 的「行自带留白」重构取代并删除）；补 `assertCardCentring` 逐卡断言与源码门。
- 2026-11-15 Z3a：关于改为设置页内容区的第七页，独立关于窗口与其展示路径删除；「状态行 + 检查更新」整体移到链接/许可之上，页面只剩一个主按钮；`.blinkClipOpenAbout` 补上生产观察者，三个入口落到同一页。「关于页几何」按新形态改写，并记下「图标墨迹不能当布局证据」这条工程约束。
- 2026-11-15 Z3b：通用页新增「外观与语言」组（主题、语言）；主题写 `preferences.appearance` 并立刻应用，语言写 `appLanguage` 并发同名通知让整页重算。通用页分组由三组变四组，逐卡居中断言按卡片身份重新点名（原三张仍在严格名单），另加说明文字卡 1.5pt 降部上限与行内选择器对齐 ≤0.5pt。
- 2026-11-15 W2：截图成功后新增「已复制截图」toast（屏幕上方居中、1.2–1.5s、不抢焦点、不入图、连续截图不叠加）；三语文案进 `ScreenshotSettingsCopy` 的 33 键表，补 `CaptureIntegrationHarness` 的 15 条 toast 断言与三语本地化断言。
- 2026-11-15 T2：四条轻提示统一成 `ReplicaToast`（上图下字、固定 128×128pt 深色 HUD 盘、圆角 16pt、图标 42pt + 间距 16pt + 14pt 白色文案（最多 2 行、行距 2pt）、屏幕底部居中 120pt、1.3s + 0.2s、不抢焦点、不入图、不叠加）。暂停/继续 toast 删掉复述同一句话的副标题，定时并进同一句；截图 toast 从屏幕顶部移到同一底部位置；复制 toast 的「启用直接粘贴」改成整块可点（手型光标），不再加小字。文案收敛成三语同键集的 `ReplicaToastCopy`（截图那条从 `ScreenshotSettingsCopy` 移出，设置表 33 → 32 键），繁体不再回落英文。修掉 `sharingType = .none` 没生效的真实缺陷（`WindowSharingPolicy` 在 didExpose 上把窗口写回 `.readOnly`），出货件 `CGWindowSharingState` 由 1 变 0；`CaptureIntegrationHarness` 的 toast 断言由 15 条扩到 40 余条（含 `CGWindowSharingState`、随内容收缩尺寸、图文几何）。
- 2026-11-15 T1：行自带上下留白后恢复逐卡覆盖。留白常量收进 `SettingsSurfaceStyle.swift` 的 `SettingsRowMetrics`（单行 9 / 带说明 8 / 成段内容 12），权限页与同步控制器共用这一份；`assertCardCentring` 按新结构重写为「首行上留白、末行下留白必须等于该行自己的常量，卡片不加上下内边距」＋「每行上下留白相等 ≤0.5pt」，覆盖面由 `cardCentringCoverage` 点名五页十二张卡（通用四组、剪贴板两张、截图两张、隐私三张、AI 一张），逐行表扩到开关、菜单选择器与复选框 13 行；关于页补「身份 → 更新卡 20pt 节奏、更新卡 → 页脚 ≥20pt」三层间距断言。字形墨迹带继续落盘（`cardCentringGeometry` 的 `inkTopGap` / `inkBottomGap` / `inkDelta`）作为证据，但按上面「以行和控件的框为准」的口径不再承担判定。
- 2026-11-16 SEL：框选覆盖层颜色与形态改造——蓝色实线边框（绿虚线移除）、蓝底白字 13pt 尺寸标签、全屏十字辅线（多屏连续、`.selected` 隐藏），三者都画在遮罩上、不入图；滚动截图的红色边框语义保持不变。证据见 `evidence/patches/sel-report.md` 与 `evidence/patches/sel-renders/`。落地后补两处：尺寸标签文案改乘号（`500 × 260`，含滚动截图与编辑器两条覆盖文案），标签与选区顶边间距 6pt → 8pt，不再贴住左上角手柄。
- 2026-11-16 POL：覆盖层三处细节——①十字辅线从 `draw(_:)` 搬进独立 layer（每屏两条，`mouseMoved` 只改 layer frame、关隐式动画），指针移动不再触发整屏重绘，实测 600pt/s 下偏差 ≤1 个合成帧、停针 ≤0.25pt；②四态边框线宽统一成 1pt（2x 下 2px）：悬停 3pt / 拖动 2pt / 选中 2pt / 滚动红框 3pt → 全 1pt，滚动红框保留外扩防渗色；③8 个圆点手柄改为边中点横条（20×4pt、圆角 2pt）+ 四角 L 形角标（12pt×2pt 两段沿角内侧），命中区 12×12 → 22×22pt，八个手柄 ±10pt 内全命中。证据：`evidence/patches/pol-report.md`、`evidence/patches/pol-renders/`。
- 2026-11-16 CUR：框选期自绘十字光标——隐藏系统光标，光标与辅线同一图层、同一次 `CATransaction` 更新（相对位移恒为 0），结束/取消/失去激活/`deinit` 幂等恢复系统光标；无法确认隐藏时退化为「系统光标 + 只画辅线」并写日志；两者均不入图。实测 300/1200pt/s、浅底深底偏离 0px，证据 `evidence/patches/cur-report.md`、`evidence/patches/cur-renders/`。
- 2026-11-16 CUR2：1.0.23 真机回归发现「覆盖层首帧未出现就拖动 → 松手失去激活 → Esc 关闭后光标约 96 秒不可见」。根因是 `restore()` 在 App 非激活时发出的光标恢复被 AppKit 丢弃，而 0/1 标志已置回「已恢复」，之后没有任何路径重试。补三层兜底：`hideDepth` 计数守恒（重复 hide 禁止、每次成功 hide 恰好一次 unhide）、非激活恢复延后到下一条 `didBecomeActive`、关闭后 0.5s 看门狗读回光标可见性并补一次恢复写日志；`NSApp.terminate` / 遮罩窗口关闭 / `deinit` 同样兜底。harness 覆盖非激活延后、看门狗补一次、首帧未出现就拖动（先失去激活再 tearDown）、连续 5 次开关后 `hideDepth == 0`；真机 10 次「立即拖动 + Esc」关闭后光标全部 visible。证据 `evidence/patches/cur2-report.md`。
- 2026-11-16 CUR4：回到系统十字光标。CUR/CUR2 的「自绘指针 + 隐藏系统光标」在真机上仍会在「首帧未上屏就拖动 → 关闭」的时序里出现光标持续隐藏，且硬件光标与 App 图层天然差一帧。做法：删除自绘光标视图与系统光标隐藏器（全仓库不再有 cursor hide/unhide、CG 光标隐藏/显示调用），框选期直接使用 `NSCursor.crosshair`（cursor rect + 激活时 set）；贯穿辅线仍在独立图层，改为 `CATransaction.setDisableActions(true)` 内更新并同步 `displayIfNeeded()`，样式降为 `systemGray` 50%、1.5pt、实线（1.0.25 发布前按用户要求从虚线改为实线）；选框本体（蓝色 1pt 实线 + 20×4pt 横条 + 12×2pt L 角标 + 蓝底尺寸标签）不变。真机 10 次「10ms 内拖动 → 松手 → Esc」关闭后 0.2s/1s/3s 光标 10/10 visible；证据 `evidence/patches/cur4-report.md`。
- 2026-11-17 SNAP2：拖拽期补吸附——选区四条边在 8pt 内吸到同轴窗口边并高亮那条边（2pt `systemGray`），松手清除；选框外观与拖拽高亮改为独立图层，拖拽期 `draw(_:)` 0 次（不重绘整屏快照）；覆盖层加 `.stationary` 不随 Space 滑动；吸附默认开（`showsDragSnap`，本次未加设置行：该页在 648×600 内已无空余高度）。见 `evidence/patches/snap2-report.md`。（REV 提交已撤销。）
- 2026-11-17 REV：撤销 SG/SNAP2 的窗口吸附式辅助线，恢复 1.0.25 的贯穿全屏跟随辅线（1.5pt `systemGray` 50% 实线、独立 `CrosshairBandView` 图层、同一事务 + `displayIfNeeded()`、跨屏广播、`.selected` 隐藏）；删除窗口四边描线、拖拽吸边与高亮、「显示中线」设置与三语键；保留选区 chrome 子图层、`.stationary`、hover 高亮图层、放大镜 20Hz、事件路径零请求与 MEAS 埋点。证据见 `evidence/patches/rev-report.md`。
- 2026-11-17 SG：框选辅助线改「吸附式」——不再画贯穿光标的横竖线，改为光标下窗口的四条边（1.5pt `systemGray` 50% 虚线 6/4，可选窗口中线，设置页可开）；同一窗口内移动零更新、换窗直接跳变、空白桌面隐藏；窗口列表 8Hz 缓存并排除本产品浮层（后续 OPT 改为 2Hz + 静止暂停 + 未命中补采）；每屏各自吸附、跨屏不串位。系统十字光标、选框本体（蓝色 1pt 实线 + 横条 + L 角标 + 蓝底尺寸标签）不变。证据见 `evidence/patches/sg-report.md`。（REV 提交已撤销；窗口列表 2Hz 缓存、产品浮层排除与 hover 高亮保留。）
- 2026-11-16 EC：编辑器 live 选框不再自画 chrome。`SelectionChromeOverlay` 删掉 2pt/`[6,4]` 虚线边框、8pt 圆点手柄与自己的 12×12pt 命中区，改为调用覆盖层的共享绘制 `SelectionView.drawSelectionChrome(in:rect:showsHandles:sizeLabel:)`、命中区读 `SelectionView.handleHitSize`（22×22pt）；覆盖层 `draw(_:)` 也改走同一个函数，两侧只有一份手柄/边框几何。新增 `EditorChromeParityHarness`（离屏渲染逐像素比对两侧强调色像素集合、边框实线、横条 20×4pt、L 角标 12×2pt、角内 2.5pt 无像素、命中 9pt 命中 / 12pt 不命中）与 `replica/scripts/test-editor-chrome-parity.sh`。实机验证：同一 400×300 选框在编辑器里只有一套手柄，圆点 0、虚线 0、边框 2px（1pt），角内 9pt 拖动可缩放（改前 12pt 命中区在 9pt 处无反应）。证据：`evidence/patches/ec-report.md`、`evidence/patches/ec-renders/`。
- 2026-11-17 TB16：编辑器浮动工具栏改成 macOS 标准工具栏尺寸——图标 18 → 16pt（weight .medium 不变）、行高 40 → 36pt、条高 52 → 46pt（`crossPadding` 6 → 5）、`surfacePadding` 6 → 5、`surfaceCornerRadius` 8 → 7、`highlightCornerRadius` 6 → 5、分组按钮 56 → 52pt。下拉菜单与工具条走同一批常量（行高 36、三行面板 118pt），命中区保持 36×36pt。见「编辑器浮动工具栏」与 `evidence/patches/toolbar16-report.md`。
- 2026-11-16 TB：toast 底盘删掉 1pt 描边（`borderWidth = 1` + `separatorColor` 解析成不透明 #232323），那圈比盘内材质深 ~120/255 的边就是用户说的「黑边」；边界改由 HUD 材质与 16pt 圆角自身区分，不加投影（图层投影被 128×128pt 窗口裁掉，系统窗口投影实测是方框、外沿深 ~52/255）。其余规范（尺寸/文案/位置/时长/材质）不变；`CaptureIntegrationHarness` 补 3 条「无描边/圆角/无投影」断言（7 处盘面检查各一份），`test-capture-integration.sh` 补 2 条源码门；逐像素证据见 `evidence/patches/tb-report.md`。
- 2026-11-17 PERF：覆盖层移动 CPU 口径与实现约定。**口径**：覆盖层打开且指针持续移动时，覆盖层自身新增的 CPU 增量（同机同构建的「零处理下限」之上）目标 **<3%**；绝对 CPU 含平台的事件投递成本，单列给参照。**约定**：①鼠标事件路径只做轻量状态更新（hover 命中、光标、待刷新状态），不做截图/整屏重绘；②放大镜面板的内容刷新（像素采样 + 面板重绘 + 跟随定位）**限频 20Hz**，由控制器自己的 20Hz 定时器驱动，**事件路径零请求**（不再有每事件的 `lens-request`），末尾补一次尾随刷新（末位置不丢）；③放大镜像素采样改为**每个快照解码一次的缓存位图**、按坐标索引，不再把整张快照栅格化进 1×1 上下文；面板的调色板、圆角路径与文字属性同样只解析一次；④窗口悬停高亮（挖洞遮罩 + 边框 + 尺寸标签）从 `draw(_:)` 搬进独立图层 `HoverHighlightView`，**换窗不再重绘冻结快照**；⑤`NSApp.activate` 每会话一次（覆盖层呈现时已领前台，`mouseMoved` 不再逐事件激活，仅在会话内补一次重试）；⑥光标 chip 的跟随定位合并到 60Hz。证据：`evidence/patches/perf-report.md`。
- 2026-11-17 OPT：覆盖层三项成本下调（120Hz 指针流实测）。①窗口枚举 **8Hz → 2Hz**，指针静止 2 秒后**暂停**枚举（下一次指针事件立即恢复），hover 由命中转为未命中时**未命中补采**一次（0.25s 下限，同一空区域不重复补采），浮动层窗口的 bundle-id 查询**按 pid 缓存**；②放大镜面板 **30Hz → 20Hz**，静态部分（圆角背景 + 三条提示行）离线渲染成位图后复用，每帧只重绘放大区与数值行（坐标 / 色值）；③删除每事件的 `lens-request`：面板由控制器 20Hz 定时器按固定频率读指针，**事件路径零请求**。MEAS 埋点保留（`BLINKCLIP_OVERLAY_PERF=1` 才输出），前后对照见 `evidence/patches/opt-report.md`。
- 2026-11-16 CL：尺寸标签加**屏幕边界钳制**。改前标签固定画在选区左上外侧（上方 8pt），选区贴屏幕顶部时胶囊会被屏幕边缘裁掉。现在 `SelectionView.sizeLabelRect(for:in:text:)` 先取该视图所在屏幕的 `visibleFrame`（`window?.screen`，回退 `NSScreen.main`），默认仍是上方 8pt / 左边对齐；上方放不下就翻到选区下方外侧 8pt；左右越界平移回屏内（各留 4pt）；上下都放不下时才允许压进选区内部，但始终完整落在 `visibleFrame` 内。尺寸/字号/圆角/颜色/文案（含 `×`）不变，覆盖层与编辑器共用同一函数，因此编辑器 live 选框的标签同样不会被裁。`CaptureChromeExclusionHarness` 用与 `visibleFrame` 等大的离屏视图实测贴顶/贴底/贴左/贴右四边（全部边在屏内、与选区重叠面积 0）与全高选区兜底（可重叠但仍完整在屏内），并逐像素证明编辑器与覆盖层的强调色像素集合完全相同；证据见 `evidence/patches/cl-label-clamp-report.md`、`evidence/patches/cl-label-clamp-renders/`。
- 2026-11-17 TFA：截图分区新增「框选覆盖层」组与「显示十字辅助线」开关（`blinkclip.screenshot.showCrosshairGuides`，缺键 = 开，三语键进 `ScreenshotSettingsCopy`，设置页多一张单行卡，截图分区两张卡变三张——`SettingsArchitectureHarness.cardCentringCoverage` 与逐行对齐点名同步 +1，`CaptureChromeExclusionHarness` 实测「关 → 两条辅线不可见且 chrome/hover/band 全在、开 → 复现」；截图页仍一屏装得下：en 532pt / zh 506pt ≤ 548pt 视口）。证据见 `evidence/patches/two-fixes-report.md` 与同目录的截屏。
- 2026-11-17 TFB：退出二次确认弹窗「退出」改为强调色实心 + 白字（压深到白字 ≥4.5:1），取消不变，`PanelShortcutMenuHarness` 断言填充色/白字/非 destructive；浅深外观实机截屏量得 5.18:1 / 4.97:1。证据见 `evidence/patches/two-fixes-report.md` 与同目录的截屏。
- 2026-11-17 WEBLINK：设置页的帮助与关于链接改指新官网。关于页链接行由三个变四个，顺序为官方网站（`aboutWebsiteURL` = `https://aexachao.github.io/BlinkClip/`）→ 更新日志 → AGPL-3.0 许可证 → 源代码（原「GitHub 项目」，仍指仓库根）；侧栏页脚的「帮助与指南」也从仓库 README 锚点改为同一个官网地址。四个标签一并收进 `SettingsCopy` 三语表（官方网站 / 官方網站 / Website、更新日志 / 更新日誌 / Release Notes、AGPL-3.0 许可证 / AGPL-3.0 許可證 / AGPL-3.0 License、源代码 / 原始碼 / Source Code），Core 资源表的 `updates.link-project` 同步改名 `updates.link-source`（值 源代码 / Source Code）。断言：`SettingsArchitectureHarness` 与 `AppUpdateHarness` 的页脚断言由「三链接同排」改为「四链接同排 + 官网第一 + 源代码最后」，`test-settings-localization.sh` 键数 52 → 56（总键 91 → 95），并补四条繁中定点断言。证据见 `evidence/patches/about-link-report.md`。
