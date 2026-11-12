// Local translations only; no network requests or external translation service.
(() => {
  const messages = {
  "zh-CN": {
    "brand.name": "闪贴",
    "meta.title": "闪贴 — 复制过的，都值得留住。",
    "meta.description": "闪贴，免费开源的 Mac 剪贴板工具。保存复制记录，用搜索、收藏分组与 Stack 找回和整理常用内容。支持 Intel 与 Apple 芯片。",
    "meta.socialDescription": "免费的 Mac 剪贴板工具。历史、搜索、分组与 OCR，都留在自己的 Mac。",
    "a11y.skip": "跳到正文",
    "a11y.navigation": "主导航",
    "a11y.home": "闪贴 首页",
    "nav.features": "功能",
    "nav.compare": "与 Paste 对比",
    "nav.faq": "常见问题",
    "nav.download": "发布状态",
    "hero.title": "复制过的，\n都值得留住。",
    "hero.description.one": "一句灵感、一张图片、一段常用文字。",
    "hero.description.two": "让复制记录留在手边，下一次需要，轻松找回。",
    "download.mac": "查看发布状态",
    "hero.try": "看看怎么用",
    "compat.chips": "Intel 与 Apple 芯片",
    "common.openSource": "免费开源",
    "a11y.panel": "闪贴 实际面板，窄屏可左右滚动查看",
    "image.panel": "闪贴 实际剪贴板面板：横向浏览文本、图片和收藏分组，内容为演示数据",
    "image.caption": "实际软件界面，内容为演示数据",
    "hero.shortcut": "打开剪贴板",
    "hero.local": "内容保存在本地",
    "hero.source": "源码公开",
    "hero.account": "没有订阅，也无需账号",
    "features.title.one": "你的剪贴板，",
    "features.title.two": "可以多做一点。",
    "features.description": "把每天重复的小动作，变得更顺手。",
    "history.title": "复制记录，不用再找一遍",
    "history.description": "文字、图片、文件和链接，自动收进历史。需要时打开面板，再次使用。",
    "type.text": "文字",
    "type.image": "图片",
    "type.file": "文件",
    "type.link": "链接",
    "collections.title": "常用内容，放在一起",
    "collections.description": "用分组收藏常用片段，用 Stack 整理待粘贴的顺序。让重复工作少一点。",
    "collections.work": "工作常用",
    "collections.ideas": "灵感收藏",
    "ocr.title": "图片里的字，也能复制",
    "ocr.description": "本地识别图片文字，搜索已有识别结果。把截图里的内容，变成可用的文字。",
    "ocr.sample": "好想法，值得留下。",
    "search.title.one": "刚刚复制的，",
    "search.title.two": "和上次收藏的。",
    "search.description.one": "记不清放在哪里，记得一点内容就好。",
    "search.description.two": "搜索、切换类型，让需要的片段浮到眼前。",
    "search.more": "了解全部功能",
    "demo.heading": "试着找一条内容",
    "demo.disclaimer": "网页交互示意 · 演示数据",
    "demo.placeholder": "搜索复制记录…",
    "a11y.search": "搜索演示记录",
    "a11y.reset": "清空搜索和筛选",
    "demo.reset": "重置",
    "a11y.filters": "演示内容类型",
    "demo.all": "全部",
    "demo.note": "灵感备忘",
    "demo.now": "刚刚",
    "demo.sample.one": "少一次寻找，",
    "demo.sample.two": "多一点心流。",
    "demo.links": "实用链接",
    "demo.twoMinutes": "2 分钟前",
    "demo.design": "设计收藏",
    "demo.fiveMinutes": "5 分钟前",
    "image.demoIcon": "演示记录中的 闪贴 图标",
    "demo.empty": "没有找到这条记录，换个关键词试试。",
    "demo.initial": "3 条演示记录",
    "demo.noScript": "启用 JavaScript 后可试用搜索与筛选；上方是演示记录。",
    "privacy.caption": "保存在你的 Mac",
    "privacy.title.one": "你的内容，",
    "privacy.title.two": "留在自己手里。",
    "privacy.description.one": "闪贴 无需原厂账号，同步默认关闭。",
    "privacy.description.two": "内容保存在本机，可选 iCloud Drive 文件同步。",
    "privacy.description.three": "也可以暂停记录，或排除指定应用。",
    "privacy.note": "本地数据为明文存储，请妥善保管电脑及导出归档。",
    "privacy.source": "查看开源代码",
    "compare.title.one": "专注你在 Mac 上",
    "compare.title.two": "常用的那部分。",
    "compare.description": "参考 Paste 的本地使用体验，闪贴 免费开源。",
    "a11y.comparison": "Paste 与 闪贴 核心功能对比",
    "compare.column": "核心功能",
    "compare.history": "剪贴板历史与搜索",
    "common.supported": "支持",
    "common.implemented": "已有实现",
    "common.unsupported": "不支持",
    "compare.collections": "收藏分组与 Stack",
    "compare.paste": "复制粘贴与自定义快捷键",
    "compare.ocr": "图片文字识别（OCR）",
    "compare.mcp": "AI 工具接入（MCP）",
    "compare.shortcuts": "系统“快捷指令”",
    "common.development": "开发中 / 待验",
    "compare.cloud": "Mac 间 iCloud 同步",
    "compare.mobile": "手机端与共享协作",
    "compare.preview": "联网链接预览",
    "compare.note.one": "✅ 表示已有实现，不代表全部场景已验证。跨应用直接粘贴及完整交互仍待全面回归。",
    "compare.note.two": "闪贴 使用可选的 iCloud Drive 文件同步，跨设备实测仍待完成。",
    "faq.title": "你可能想知道。",
    "faq.free.question": "闪贴 是免费的吗？",
    "faq.free.answer": "是。闪贴 的独立实现按 MIT 许可开源，无需订阅或原厂账号。原版研究材料的权利范围单独说明，详见仓库中的 NOTICE。",
    "faq.mac.question": "我的 Mac 可以使用吗？",
    "faq.search.question": "搜索按钮点不开或响应慢怎么办？",
    "faq.search.answer": "1.0.8 已修复搜索按钮点击被拦截及展开延迟的问题。点击放大镜或在面板内按 ⌘F 即可搜索。macOS 26.2 Apple 芯片 Mac 已完成合成数据及本机点击输入验证，Intel 真机和旧系统待验证。",
    "faq.updates.question": "软件如何检查更新？",
    "faq.updates.answer": "关于闪贴中可检查本项目 GitHub Releases，并通过 Sparkle 验证安装包签名。本仓库尚未发布安装包；上游历史版本与临时签名授权实测不表示本项目已有可用更新。正式发布需要先配置匹配的签名密钥。",
    "faq.mac.answer": "支持 macOS 14 及以上。一个 Universal DMG 同时包含 Intel 与 Apple 芯片架构，无需区分下载。构建通过不代表两个架构的所有功能均已完成回归。",
    "faq.install.question": "怎么安装？为什么需要辅助功能权限？",
    "faq.install.answer": "本仓库尚无公开安装包，请按 README 从源码构建。未来发布 DMG 后，将 BlinkClip.app 拖入 Applications 并从那里启动。跨应用直接粘贴需辅助功能权限；保存历史与复制内容不需要该权限。当前本机开发签名不等于 Developer ID 公证或商店验收。",
    "faq.permissions.question": "设置如何分组，在哪里管理系统权限？",
    "faq.permissions.answer": "当前源码将设置分为六组，标题显示在右侧原生顶部工具栏。系统权限只在“隐私与权限”完整展示，返回应用后自动更新，也可手动刷新；监测不申请权限或自动重启。六个快捷键录制器右侧均有 ×，清空显示“未设置”，截图清空只取消对应快捷键绑定，重启后保持；菜单截图功能保留。每项仅非默认时显示左侧“恢复默认”，也可确认后恢复全部快捷键及粘贴修饰键。取消不写入，失败保留原值并报错。截图时只收起历史面板，设置与其他普通窗口保持显示。正式版 1.0.8 尚未包含这些调整；真实全局按键与系统授权变化仍待验证。",
    "faq.feedback.question": "复制和截图提示音有调整吗？",
    "faq.feedback.answer": "当前 1.0.9 源码按用户选择使用 macOS 自带 Purr 成功提示音，运行时加载，不复制系统音频、不使用原音频或系统 Pop，也不做时间节流。原 Pop 的单次多声段可能形成重复听感，但没有证实重复播放调用。隔离测试中截图成功一次声、连续两次不同复制各一次、失败无声；真实听感仍待确认，正式版 1.0.8 尚未包含。",
    "faq.artwork.question": "新图标和说明插图来自哪里？",
    "faq.artwork.answer": "新启动图标、直接粘贴、复制到剪贴板和权限说明图按用户确认使用当前内置图像工具生成，提示词、源图和包装记录保存在仓库 branding/BlinkClipGeneratedAssets。工具未公开模型 ID，不声称由 gpt-image-2.5 生成。小尺寸类别图继续独立代码绘制；旧提取素材不随当前源码包发行，来源与商店权利审查仍分别判断。",
    "faq.retention.question": "历史保留时间如何设置和计算？",
    "faq.retention.answer": "当前源码在“设置 → 剪贴板与历史”提供 1、3、7、15、30、60 天或永久七个选项，选中无对勾；已有非预设值只读显示，打开不改写。按每条记录进入历史的时间计算，只清理过期且未加入分组的内容。缩短期限使用系统警告确认框，按钮采用普通系统文字颜色；Return、数字 Enter 和 Esc 均取消，只有点击确认按钮才立即清理，且无法撤销。取消不保存，保存失败恢复原设置并显示错误。尚未包含在正式版 1.0.8；真实用户历史清理仍待验证。",
    "faq.source-icons.question": "历史卡片如何显示来源应用图标？",
    "faq.source-icons.answer": "历史卡片的来源应用图标已改为完整适配，保留已有启动图标的比例和轮廓，避免放大裁切；不会重绘应用图标资源。完整适配的隔离像素与布局验证已通过，本机版本已完成替换；正式版 1.0.8 尚未包含此调整。",
    "faq.cloud.question": "会把我的剪贴板上传到云端吗？",
    "faq.cloud.answer": "默认保存在本机。在设置 → 通用开启 iCloud 同步后，历史和分组会通过你的 iCloud Drive 文件合并，需要同一 Apple ID 并开启 iCloud Drive。真实多设备同步仍待完整验收。MCP 是可选的本地接口，第三方 AI 客户端如何使用所读取的内容取决于它自己的设置。",
    "faq.parity.question": "和 Paste 完全一样吗？",
    "faq.parity.answer": "不是。闪贴是独立开发的 Mac 剪贴板与截图工具，与 Paste 原厂无关联；完整交互验收仍在进行。提供可选 iCloud Drive 文件同步；手机端、共享协作和联网预览尚未提供。开发源码已有 App Intents 入口；系统发现、真实快捷指令运行及既有快捷指令迁移未验，正式版 1.0.8 未提供。直接粘贴等交互的完整兼容性仍在完善。",
    "image.appIcon": "闪贴 图标",
    "download.title.one": "给复制，",
    "download.title.two": "多一点记忆。",
    "download.start": "从下一次",
    "download.end": "开始。",
    "download.meta": "源码构建 · macOS 14+",
    "download.releases": "更新日志与所有版本",
    "footer.tagline": "免费的本地 Mac 剪贴板工具。",
    "footer.feedback": "反馈问题",
    "footer.license": "许可说明",
    "footer.legal": "© 2026 闪贴 · 独立开源项目，与 Paste 原厂无关联。",
    "language.label": "显示语言",
    "language.system": "跟随系统",
    "demo.result.one": "{count} 条演示记录",
    "demo.result.other": "{count} 条演示记录",
    "demo.keywords.text": "文字 灵感 少一次寻找 多一点心流",
    "demo.keywords.link": "链接 github blinkclip 开源 软件",
    "demo.keywords.image": "图片 blinkclip 图标 设计",
    "hero.release": "安装包尚未发布 · 查看源码",
    "release.note": "当前提供源码：精简设置说明，移除未经配置的图床上传入口，帮助跳转至本项目 GitHub。安装包尚未发布。",
    "hero.title.one": "复制过的，",
    "hero.title.two": "都值得",
    "hero.title.mark": "留住。",
    "a11y.stage": "闪贴 在 Mac 上的界面示意",
    "stage.idea": "刚才的灵感，还在。",
    "stage.local": "只在你的 Mac 上。",
    "stage.file": "文件",
    "stage.edit": "编辑",
    "stage.date": "周四 10:28",
    "stage.eyebrow": "给下一个灵感",
    "stage.description.one": "常用的文字、收藏的链接、",
    "stage.description.two": "还没来得及整理的好想法。",
    "stage.shortcut": "复制记录，随叫随到。",
    "features.eyebrow": "从复制，到再次使用",
    "search.eyebrow": "找回，只需要一个关键词",
    "privacy.eyebrow": "本地优先，简单就好",
    "compare.eyebrow": "熟悉的用法，更轻的选择",
    "faq.eyebrow": "开始之前",
    "language.trigger": "切换语言：{language}"
  },
  "en": {
    "brand.name": "BlinkClip",
    "meta.title": "BlinkClip | Copy once. Keep it close.",
    "meta.description": "BlinkClip is a free, open-source clipboard manager for Mac. Save your copy history, search, organize collections, and queue items with Stack. For Intel and Apple silicon.",
    "meta.socialDescription": "A free clipboard manager for Mac. History, search, collections, and OCR stay on your Mac.",
    "a11y.skip": "Skip to content",
    "a11y.navigation": "Main navigation",
    "a11y.home": "BlinkClip home",
    "nav.features": "Features",
    "nav.compare": "Compare with Paste",
    "nav.faq": "FAQ",
    "nav.download": "Free download",
    "hero.title": "Copy once.\nKeep it close.",
    "hero.description.one": "An idea, an image, a snippet you use every day.",
    "hero.description.two": "Keep what you copy handy, ready for next time.",
    "download.mac": "View release status",
    "hero.try": "See how it works",
    "compat.chips": "Intel and Apple silicon",
    "common.openSource": "Free and open source",
    "a11y.panel": "Actual BlinkClip panel. Scroll horizontally on smaller screens.",
    "image.panel": "Actual BlinkClip clipboard panel in Chinese, showing sample text, images, and collections.",
    "image.caption": "Actual app interface in Chinese, with sample data",
    "hero.shortcut": "Open clipboard",
    "hero.local": "Stored on your Mac",
    "hero.source": "Source available",
    "hero.account": "No subscription or account",
    "features.title.one": "Your clipboard,",
    "features.title.two": "with more to offer.",
    "features.description": "Make everyday copy and paste a little easier.",
    "history.title": "Find what you copied",
    "history.description": "Automatically save text, images, files, and links to your history. Open the panel to use them again.",
    "type.text": "Text",
    "type.image": "Images",
    "type.file": "Files",
    "type.link": "Links",
    "collections.title": "Keep the useful things together",
    "collections.description": "Save your favorite snippets in collections. Queue items with Stack to paste them in order.",
    "collections.work": "Work essentials",
    "collections.ideas": "Saved ideas",
    "ocr.title": "Copy text from images",
    "ocr.description": "Recognize text in images locally and search the results. Turn the words in a screenshot into usable text.",
    "ocr.sample": "Good ideas are worth keeping.",
    "search.title.one": "Just copied.",
    "search.title.two": "Or saved for later.",
    "search.description.one": "Remember a few words, even if you forget where.",
    "search.description.two": "Search and filter by type to find the right snippet.",
    "search.more": "Explore all features",
    "demo.heading": "Try finding an item",
    "demo.disclaimer": "Interactive example · Sample data",
    "demo.placeholder": "Search clipboard history…",
    "a11y.search": "Search sample items",
    "a11y.reset": "Clear search and filters",
    "demo.reset": "Reset",
    "a11y.filters": "Sample content types",
    "demo.all": "All",
    "demo.note": "Idea note",
    "demo.now": "Just now",
    "demo.sample.one": "Less searching.",
    "demo.sample.two": "More doing.",
    "demo.links": "Useful link",
    "demo.twoMinutes": "2 minutes ago",
    "demo.design": "Design pick",
    "demo.fiveMinutes": "5 minutes ago",
    "image.demoIcon": "BlinkClip icon in a sample item",
    "demo.empty": "No matching items. Try a different keyword.",
    "demo.initial": "3 sample items",
    "demo.noScript": "Enable JavaScript to try search and filters. The items above are samples.",
    "privacy.caption": "Stored on your Mac",
    "privacy.title.one": "Your content.",
    "privacy.title.two": "In your hands.",
    "privacy.description.one": "BlinkClip needs no vendor account. Sync is off by default.",
    "privacy.description.two": "Content stays on your Mac, with optional iCloud Drive file sync.",
    "privacy.description.three": "Pause recording or exclude specific apps whenever you need.",
    "privacy.note": "Local data is stored as plain text. Keep your Mac and exported archives secure.",
    "privacy.source": "View the source",
    "compare.title.one": "Focused on what you",
    "compare.title.two": "use on your Mac.",
    "compare.description": "Inspired by the local Paste experience. Free and open source.",
    "a11y.comparison": "Paste and BlinkClip core feature comparison",
    "compare.column": "Core features",
    "compare.history": "Clipboard history and search",
    "common.supported": "Supported",
    "common.implemented": "Implemented",
    "common.unsupported": "Not supported",
    "compare.collections": "Collections and Stack",
    "compare.paste": "Copy, paste, and custom shortcuts",
    "compare.ocr": "Text recognition (OCR)",
    "compare.mcp": "AI tool integration (MCP)",
    "compare.shortcuts": "Apple Shortcuts",
    "common.development": "In development / unverified",
    "compare.cloud": "iCloud sync between Macs",
    "compare.mobile": "Mobile apps and shared collaboration",
    "compare.preview": "Online link previews",
    "compare.note.one": "✅ means implemented, not tested in every scenario. Cross-app direct paste and full interactions still need comprehensive regression testing.",
    "compare.note.two": "BlinkClip offers optional iCloud Drive file sync. Cross-device validation is still pending.",
    "faq.title": "A few things to know.",
    "faq.free.question": "Is BlinkClip free?",
    "faq.free.answer": "Yes. The independent BlinkClip implementation is open source under the MIT license, with no subscription or original vendor account required. Rights to the original research materials are described separately in the repository NOTICE.",
    "faq.mac.question": "Will it work on my Mac?",
    "faq.search.question": "What if the search button is unresponsive or slow?",
    "faq.search.answer": "Version 1.0.8 fixes blocked clicks and delayed activation of the search icon. Click the icon or press ⌘F inside the panel to search. Synthetic-data checks and installed-app clicks passed on Apple silicon and macOS 26.2. Native Intel hardware and older macOS versions remain untested.",
    "faq.updates.question": "How do I check for updates?",
    "faq.updates.answer": "About BlinkClip checks this project's GitHub Releases and uses Sparkle to verify update signatures. This repository has no published installer yet. Upstream release history and ad-hoc signing tests do not establish an available update here; matching signing keys must be configured before publication.",
    "faq.mac.answer": "BlinkClip supports macOS 14 and later. One Universal DMG includes both Intel and Apple silicon builds. A successful build does not mean every feature has been regression-tested on both architectures.",
    "faq.install.question": "How do I install it, and why Accessibility access?",
    "faq.install.answer": "There is no public installer in this repository yet; build from source using the README. For a future published DMG, drag BlinkClip.app into Applications and launch it there. Direct paste needs Accessibility access; saving history and copying content do not. Local development signing is not Developer ID notarization or App Store validation.",
    "faq.permissions.question": "How are settings grouped, and where are permissions managed?",
    "faq.permissions.answer": "Current source groups Settings into six pages, with titles in the native toolbar on the right. Permissions live in Privacy & Permissions and refresh on return, with manual refresh available; monitoring never requests access or restarts the app. All six shortcut recorders have a right-side × and show Not Set when cleared. Clearing a screenshot shortcut disables only its binding, survives restart, and preserves menu capture. A left-side Restore Default appears only for a modified option; Restore All Shortcuts also restores the paste modifiers after confirmation. Cancelling writes nothing; failures preserve the previous values and show an error. Capture hides only the history panel, keeping Settings and ordinary windows visible. These changes are not in stable 1.0.8; real global-key interaction and system permission changes remain unverified.",
    "faq.feedback.question": "Which success sound does BlinkClip use?",
    "faq.feedback.answer": "Current 1.0.9 source uses the built-in macOS Purr sound for success feedback, loaded at runtime without copying system audio, original audio, system Pop, or time throttling. Several segments within one Pop playback may explain a doubled sound, but duplicate playback calls were not established. Isolated tests confirm one tone for screenshot success, one per distinct copy, and silence on failure. Actual listening remains unverified; stable 1.0.8 does not include this change.",
    "faq.artwork.question": "Where do the new icon and illustrations come from?",
    "faq.artwork.answer": "The new app icon, direct-paste, clipboard-copy, and permission illustrations were generated with the built-in image tool with the user’s approval. Prompts, sources, and packaging records live in branding/BlinkClipGeneratedAssets. The tool does not expose its model ID, so these are not attributed to gpt-image-2.5. Small category icons retain independent code drawing. Extracted research assets remain excluded from the app; source-rights and store review are separate checks.",
    "faq.retention.question": "How is history retention set and calculated?",
    "faq.retention.answer": "Current source offers 1, 3, 7, 15, 30, or 60 days, and Forever in Settings → Clipboard & History, with no selection checkmark. Existing non-preset values remain read-only and unchanged on opening. Age starts when each entry enters history; only expired entries outside groups are removed. Shortening uses a system warning alert with ordinary system button labels. Return, keypad Enter, and Esc cancel; clicking confirmation immediately cleans up entries and cannot be undone. Cancelling does not save; a failed save restores the previous setting and shows an error. This is not in stable version 1.0.8; real user-history cleanup remains unverified.",
    "faq.source-icons.question": "How are source-app icons shown in history cards?",
    "faq.source-icons.answer": "Source-app icons in history cards are fitted in full, preserving the existing launcher icon’s proportions and outline rather than enlarging and cropping it. App-icon assets are not being redesigned. Isolated pixel and layout verification have passed. The local app has been replaced; this adjustment is not in stable version 1.0.8.",
    "faq.cloud.question": "Is my clipboard uploaded to the cloud?",
    "faq.cloud.answer": "Content is stored locally by default. Turn on iCloud sync in Settings → General to merge history and collections through your iCloud Drive files. Macs need the same Apple ID and iCloud Drive enabled. End-to-end sync across real devices still needs full validation. MCP is an optional local interface, and third-party AI clients use the content they read according to their own settings.",
    "faq.parity.question": "Is it exactly the same as Paste?",
    "faq.parity.answer": "BlinkClip is independently developed for Mac and is not affiliated with Paste. Full interaction verification is ongoing. Optional iCloud Drive file sync is available; mobile apps, shared collaboration, and online previews are unavailable. The development source has App Intents entry points. System discovery, real shortcut execution, and migration of saved shortcuts remain unverified; stable 1.0.8 does not provide them. Direct-paste compatibility is still being improved.",
    "image.appIcon": "BlinkClip icon",
    "download.title.one": "Give your clipboard",
    "download.title.two": "a memory.",
    "download.start": "Starting with your next",
    "download.end": ".",
    "download.meta": "Build from source · macOS 14+",
    "download.releases": "Release notes and all versions",
    "footer.tagline": "A free, local clipboard manager for Mac.",
    "footer.feedback": "Report an issue",
    "footer.license": "License notes",
    "footer.legal": "© 2026 BlinkClip · An independent open-source project, not affiliated with Paste.",
    "language.label": "Display language",
    "language.system": "System language",
    "demo.result.one": "{count} sample item",
    "demo.result.other": "{count} sample items",
    "demo.keywords.text": "text idea note inspiration less searching more doing",
    "demo.keywords.link": "link github blinkclip open source software",
    "demo.keywords.image": "image blinkclip icon design",
    "hero.release": "No installer published yet · View source",
    "release.note": "Source update: shorter settings copy, no unconfigured image-host upload, and help links to this project on GitHub. No installer has been published yet.",
    "hero.title.one": "Copy once.",
    "hero.title.two": "Keep it ",
    "hero.title.mark": "close.",
    "a11y.stage": "Illustration of BlinkClip on Mac, with an actual Chinese interface and sample data",
    "stage.idea": "That idea is still here.",
    "stage.local": "On your Mac.",
    "stage.file": "File",
    "stage.edit": "Edit",
    "stage.date": "Thu 10:28",
    "stage.eyebrow": "For your next idea",
    "stage.description.one": "Useful snippets, saved links,",
    "stage.description.two": "and ideas to come back to.",
    "stage.shortcut": "Your clipboard, on call.",
    "features.eyebrow": "From copy to reuse",
    "search.eyebrow": "One keyword away",
    "privacy.eyebrow": "Local first. Keep it simple.",
    "compare.eyebrow": "Familiar tools. A lighter choice.",
    "faq.eyebrow": "Before you start",
    "language.trigger": "Change language: {language}"
  }
};

  const storageKey = 'blinkclip.website.language';
  const isSupported = value => Object.prototype.hasOwnProperty.call(messages, value);
  let preference = 'system';
  try {
    const saved = localStorage.getItem(storageKey);
    if (isSupported(saved)) preference = saved;
  } catch { /* Language selection still works when browser storage is unavailable. */ }

  function systemLanguage() {
    const languages = navigator.languages?.length ? navigator.languages : [navigator.language];
    for (const requested of languages) {
      const base = String(requested).toLowerCase().split(/[-_]/)[0];
      if (base === 'zh') return 'zh-CN';
      if (base === 'en') return 'en';
    }
    return 'en';
  }

  let language = preference === 'system' ? systemLanguage() : preference;
  function t(key, values = {}) {
    const text = messages[language][key] ?? messages['zh-CN'][key] ?? key;
    return text.replace(/\{(\w+)\}/g, (match, name) => values[name] === undefined ? match : String(values[name]));
  }

  function applyLanguage() {
    language = preference === 'system' ? systemLanguage() : preference;
    document.documentElement.lang = language;
    for (const element of document.querySelectorAll('[data-i18n]')) {
      element.textContent = t(element.dataset.i18n);
    }
    for (const attribute of ['alt', 'aria-label', 'placeholder', 'content']) {
      const marker = `data-i18n-${attribute}`;
      for (const element of document.querySelectorAll(`[${marker}]`)) {
        element.setAttribute(attribute, t(element.getAttribute(marker)));
      }
    }
    for (const card of document.querySelectorAll('[data-i18n-search]')) {
      const key = card.dataset.i18nSearch;
      card.dataset.search = `${messages['zh-CN'][key]} ${messages.en[key]}`;
    }
    document.querySelector('meta[property="og:locale"]').content = language === 'en' ? 'en_US' : 'zh_CN';
    const label = t('language.trigger', { language: language === 'en' ? 'English' : '简体中文' });
    const trigger = document.querySelector('#language-trigger');
    trigger.setAttribute('aria-label', label);
    trigger.setAttribute('title', label);
    for (const option of document.querySelectorAll('[data-language]')) {
      option.setAttribute('aria-pressed', String(option.dataset.language === preference));
    }
    document.dispatchEvent(new CustomEvent('blinkclip:languagechange', { detail: { language } }));
  }

  function setPreference(value) {
    preference = isSupported(value) ? value : 'system';
    try {
      if (preference === 'system') localStorage.removeItem(storageKey);
      else localStorage.setItem(storageKey, preference);
    } catch { /* Keep the choice for this visit without requiring persistent storage. */ }
    applyLanguage();
  }

  window.BlinkClipI18n = { t, get language() { return language; } };
  const switcher = document.querySelector('.language-switch');
  const trigger = document.querySelector('#language-trigger');
  for (const option of document.querySelectorAll('[data-language]')) {
    option.addEventListener('click', () => {
      setPreference(option.dataset.language);
      switcher.open = false;
      trigger.focus();
    });
  }
  document.addEventListener('click', event => {
    if (!switcher.contains(event.target)) switcher.open = false;
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && switcher.open) {
      switcher.open = false;
      trigger.focus();
    }
  });
  window.addEventListener('languagechange', () => { if (preference === 'system') applyLanguage(); });
  applyLanguage();
})();
