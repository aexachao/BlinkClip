(() => {
  const messages = {
    "zh-Hans": {
      "brand.name": "闪贴",
      "meta.title": "闪贴 BlinkClip — 复制过的都找得回来，截完图直接标注",
      "meta.description": "闪贴（BlinkClip）是一款本地优先的 macOS 剪贴板历史与截图工具：文本、图片、文件、链接和颜色收进一个可搜索面板，⌘⇧A 框选后直接标注；无需账号，一个 DMG 同时支持 Intel 与 Apple 芯片。",
      "meta.socialDescription": "本地优先的 macOS 剪贴板历史与截图标注工具。历史只存在本机，同步默认关闭，无需账号。",
      "a11y.skip": "跳到正文",
      "a11y.navigation": "主导航",
      "a11y.home": "闪贴首页",
      "a11y.download": "下载闪贴（GitHub Releases）",
      "a11y.language": "语言",
      "a11y.external": "在新标签页打开 GitHub",
      "language.label": "显示语言",
      "language.system": "跟随系统",
      "language.short": "中文",
      "language.trigger": "切换语言：{language}",
      "nav.features": "功能",
      "nav.capture": "截图",
      "nav.shortcuts": "快捷键",
      "nav.permissions": "权限",
      "nav.faq": "常见问题",
      "nav.download": "下载",
      "hero.eyebrow": "macOS 14+ · 本地优先 · 无需账号",
      "hero.title.one": "复制过的，",
      "hero.title.two": "都找得回来。",
      "hero.lede": "文本、图片、文件、链接和颜色都收进一个可搜索的卡片面板；⌘⇧A 框选后直接进入标注编辑器，需要对照时还能把截图钉在屏幕上。",
      "hero.fact": "一个 DMG 同时支持 Intel 与 Apple 芯片",
      "hero.secondary": "看快捷键",
      "hero.release": "GitHub Releases",
      "hero.local": "只存在这台 Mac",
      "hero.trust.local": "本地优先",
      "hero.trust.account": "无需账号",
      "hero.trust.license": "AGPL-3.0",
      "download.mac": "下载 macOS 版",
      "download.meta": "macOS 14+ · Universal",
      "image.clipboard": "闪贴剪贴板面板：横向卡片浏览文本、图片与链接，卡片标明类型与来源应用",
      "image.overlay": "框选覆盖层：贯穿全屏的十字辅助线、蓝色选区与放大镜读数（坐标 / 色值 / 比例）",
      "image.toolbar": "截图后的标注编辑器浮动工具栏",
      "image.permissions": "设置 → 隐私与权限：辅助功能与屏幕录制状态",
      "image.captureSettings": "设置 → 截图：截图后行为、框选覆盖层与翻译",
      "features.eyebrow": "一次装好，四件事都顺",
      "features.title.one": "剪贴板、截图、",
      "features.title.two": "AI 与同步。",
      "features.lede": "历史、截图与标注、AI 工具接入、iCloud 同步——都在同一个原生应用里，没有账号，也没有订阅。",
      "card.history.tag": "01 · 剪贴板历史",
      "card.history.title": "复制过的，按 ⇧⌘V 就回来",
      "card.history.body": "文本、图片、文件、链接和颜色自动入库，横向卡片浏览，支持关键字搜索，并按类型、来源应用和日期筛选。",
      "card.history.point.one": "保留期限 1 / 3 / 7 / 15 / 30 / 60 天或永久",
      "card.history.point.two": "只清理过期且未加入分组的内容",
      "card.history.point.three": "收藏分组（Pinboard）与 ⇧⌘C Stack 顺序粘贴",
      "type.text": "文本",
      "type.image": "图片",
      "type.file": "文件",
      "type.link": "链接",
      "type.color": "颜色",
      "card.capture.tag": "02 · 截图与标注",
      "card.capture.title": "⌘⇧A 框选，直接进标注",
      "card.capture.body": "框选时十字辅助线贯穿全屏，放大镜实时读坐标、色值与比例；松手即进入标注编辑器。",
      "card.capture.tools": "矩形、椭圆、箭头、直线、画笔、马克笔、聚光灯、马赛克、橡皮、放大镜、序号、文字、二维码、表情、插入图片、取色",
      "card.capture.extra": "长截图自动拼接 · 钉图浮窗 · 本地 Vision OCR · Apple 翻译（macOS 15+）",
      "card.ai.tag": "03 · AI 工具接入",
      "card.ai.title": "把剪贴板交给 AI 当上下文",
      "card.ai.body": "blinkclip-mcp 是标准 stdio JSON-RPC 服务，Claude、Codex、Cursor 都能接；「设置 → AI 工具」里直接复制配置。",
      "card.sync.tag": "04 · iCloud 同步",
      "card.sync.title": "默认关闭，开不开你说了算",
      "card.sync.body": "开启后经 CloudKit 在 Mac 之间同步历史与分组（生产已上线）；未获授权的构建回退到 iCloud Drive。",
      "card.sync.state": "默认关闭",
      "card.sync.note": "快捷键、权限、排除列表、保留期限与 Stack 队列不同步",
      "stats.eyebrow": "真实数字",
      "stats.title.one": "没有包装，",
      "stats.title.two": "只有事实。",
      "stats.account.title": "账号",
      "stats.account.desc": "无需注册、无需登录，打开就能用；同步也只使用你自己的 Apple ID。",
      "stats.installer.title": "个通用安装包",
      "stats.installer.desc": "同一个 DMG 同时支持 Intel 与 Apple 芯片，不用挑版本。",
      "stats.types.title": "类收录内容",
      "stats.types.desc": "文本、图片、文件、链接、颜色，并保留原始格式（富文本、HTML、文件 URL）。",
      "stats.macos.title": "macOS 版本",
      "stats.macos.desc": "系统要求 macOS 14 或更新；截图翻译需要 macOS 15+。",
      "shortcuts.eyebrow": "手指比鼠标快",
      "shortcuts.title.one": "四个快捷键，",
      "shortcuts.title.two": "记住就够用。",
      "shortcuts.lede": "默认值如下，全部可以在「设置 → 快捷键」里改。",
      "shortcuts.open.title": "打开历史面板",
      "shortcuts.open.desc": "任何应用里呼出横向卡片面板",
      "shortcuts.stack.title": "Stack 顺序粘贴",
      "shortcuts.stack.desc": "多条内容按队列依次粘贴，适合填表",
      "shortcuts.region.title": "区域截图",
      "shortcuts.region.desc": "十字辅助线加放大镜读数",
      "shortcuts.full.title": "全屏截图",
      "shortcuts.full.desc": "截完直接进入标注编辑器",
      "permissions.eyebrow": "先说清楚要什么权限",
      "permissions.title.one": "两个开关，",
      "permissions.title.two": "一次授权。",
      "permissions.lede": "闪贴需要系统级能力才能读取界面和投递按键；不授予也能用，只是部分功能会退化为手动操作。",
      "permissions.access.name": "辅助功能",
      "permissions.access.why": "读取其他应用界面（滚动截图、读取内容），并向其他应用发送键盘事件（直接粘贴）。",
      "permissions.access.where": "系统设置 → 隐私与安全性 → 辅助功能；也可从「设置 → 隐私与权限」点「系统设置…」。",
      "permissions.screen.name": "屏幕录制",
      "permissions.screen.why": "截取区域、窗口或整个屏幕。",
      "permissions.screen.where": "系统设置 → 隐私与安全性 → 屏幕录制；同样可以从应用内跳转。",
      "permissions.events.name": "发送事件",
      "permissions.events.why": "直接粘贴时向目标应用投递键盘事件；它与辅助功能同源，系统设置不会单独列出这一项。",
      "permissions.events.where": "随辅助功能一并生效；若提示未就绪，重新勾选辅助功能后重启应用。",
      "permissions.fallback": "不授予也能用：不依赖辅助功能的项目照常工作，滚动截图可改用手动滚动。",
      "privacy.eyebrow": "本地优先，不是口号",
      "privacy.title.one": "数据只存在",
      "privacy.title.two": "这台 Mac 上。",
      "privacy.lede": "剪贴板历史、截图与设置默认只保存在本机；同步默认关闭，不需要账号，也不经过我们的服务器。",
      "privacy.path.label": "数据位置",
      "privacy.path.note": "目录 0700，数据库 0600；首次启动会把旧的 clipboard.json 迁移进 clipboard.sqlite，原文件保留不覆盖。",
      "privacy.sync.title": "开启同步才会上云",
      "privacy.sync.body": "内容进入你自己 Apple ID 下的 iCloud（CloudKit 容器或 iCloud Drive/BlinkClip），不经过本项目的服务器；应用也不上报使用数据。",
      "privacy.sensitive.title": "敏感内容不记录",
      "privacy.sensitive.body": "来源应用标记为机密或临时的剪贴板内容会被跳过；也可以在「设置 → 隐私与权限」里指定不记录的应用。",
      "faq.eyebrow": "上手前",
      "faq.q1": "需要哪些权限？",
      "faq.a1": "辅助功能用于读取界面和发送按键（直接粘贴、滚动截图），屏幕录制用于截图；发送事件随辅助功能一并生效。都在「系统设置 → 隐私与安全性」里授权，应用内「设置 → 隐私与权限」有直达按钮。不授予也能用，滚动截图可以改用手动滚动。",
      "faq.q2": "数据会上传吗？",
      "faq.a2": "默认不会。历史、截图和设置只存在本机；同步默认关闭，开启后内容进入你自己 Apple ID 下的 iCloud，不经过本项目的服务器，应用也不上报使用数据。",
      "faq.q3": "支持 Intel Mac 吗？",
      "faq.a3": "支持。同一个 Universal DMG 同时支持 Intel 与 Apple 芯片，系统要求 macOS 14 或更新。",
      "faq.q4": "怎么卸载干净？",
      "faq.a4": "退出闪贴，把 BlinkClip.app 移到废纸篓；本地数据在 ~/Library/Application Support/BlinkClip/，需要彻底清除时一并删除。若开启过 iCloud 同步，云端数据保存在你自己的 iCloud 账户里；若开启过「登录时打开」，先在设置中关闭。",
      "faq.q5": "为什么不在 Mac App Store？",
      "faq.a5": "闪贴采用 Developer ID 签名并通过 Apple 公证，未启用 App Sandbox，直接通过 GitHub Releases 分发；安装包双击即可运行，应用内更新由 Sparkle 完成。",
      "faq.q6": "怎么更新？",
      "faq.a6": "「关于闪贴 → 检查更新」会对比最新正式 Release，六小时内复用检查结果；确认后应用内下载完整 Universal DMG 并校验 Ed25519 签名，保存数据后安装重启。更新后系统可能要求重新授予辅助功能权限。",
      "cta.eyebrow": "现在就试",
      "cta.title.one": "把下一个灵感，",
      "cta.title.two": "留在手边。",
      "cta.lede": "下载最新正式版，拖进「应用程序」就能用。免费、开源、无需账号。",
      "cta.note": "macOS 14+ · Universal（Intel + Apple 芯片）· AGPL-3.0",
      "cta.github": "查看源码与更新日志",
      "footer.license": "AGPL-3.0 许可",
      "footer.credits": "第三方致谢：capcap（MIT，截图覆盖层与标注编辑器）· Sparkle（应用内更新）",
      "footer.repo": "GitHub 仓库"
    },
    "en": {
      "brand.name": "BlinkClip",
      "meta.title": "BlinkClip — Everything you copy stays findable, every screenshot ready to annotate",
      "meta.description": "BlinkClip is a local-first clipboard history and screenshot tool for macOS: text, images, files, links and colours in one searchable panel, and ⌘⇧A opens annotation right after a region capture. No account needed; one DMG runs on Intel and Apple silicon.",
      "meta.socialDescription": "A local-first clipboard history and screenshot annotation tool for macOS. History stays on your Mac, sync is off by default, no account required.",
      "a11y.skip": "Skip to content",
      "a11y.navigation": "Main navigation",
      "a11y.home": "BlinkClip home",
      "a11y.download": "Download BlinkClip (GitHub Releases)",
      "a11y.language": "Language",
      "a11y.external": "Opens GitHub in a new tab",
      "language.label": "Display language",
      "language.system": "System language",
      "language.short": "EN",
      "language.trigger": "Change language: {language}",
      "nav.features": "Features",
      "nav.capture": "Capture",
      "nav.shortcuts": "Shortcuts",
      "nav.permissions": "Permissions",
      "nav.faq": "FAQ",
      "nav.download": "Download",
      "hero.eyebrow": "macOS 14+ · Local first · No account",
      "hero.title.one": "Everything you copy",
      "hero.title.two": "stays findable.",
      "hero.lede": "Text, images, files, links and colours land in one searchable card panel. ⌘⇧A opens the annotation editor right after a region capture, and any screenshot can be pinned on top of your screen.",
      "hero.fact": "One DMG runs on both Intel and Apple silicon",
      "hero.secondary": "See shortcuts",
      "hero.release": "GitHub Releases",
      "hero.local": "Stays on this Mac",
      "hero.trust.local": "Local first",
      "hero.trust.account": "No account",
      "hero.trust.license": "AGPL-3.0",
      "download.mac": "Download for macOS",
      "download.meta": "macOS 14+ · Universal",
      "image.clipboard": "BlinkClip clipboard panel: horizontal cards for text, images and links, each labelled with type and source app",
      "image.overlay": "Selection overlay: full-screen crosshair guides, the blue selection and live magnifier readouts (coordinates / colour / ratio)",
      "image.toolbar": "Floating toolbar of the annotation editor, opened right after a capture",
      "image.permissions": "Settings → Privacy & Permissions: Accessibility and Screen Recording status",
      "image.captureSettings": "Settings → Screenshots: post-capture behaviour, selection overlay and translation",
      "features.eyebrow": "One install, four things done",
      "features.title.one": "Clipboard, capture,",
      "features.title.two": "AI and sync.",
      "features.lede": "History, capture and annotation, AI tool access and iCloud sync — one native app, no account, no subscription.",
      "card.history.tag": "01 · Clipboard history",
      "card.history.title": "Everything you copied, back on ⇧⌘V",
      "card.history.body": "Text, images, files, links and colours are captured automatically. Browse horizontal cards, search by keyword, and filter by type, source app or date.",
      "card.history.point.one": "Keep for 1 / 3 / 7 / 15 / 30 / 60 days or forever",
      "card.history.point.two": "Only expired items outside collections are purged",
      "card.history.point.three": "Pinboards and ⇧⌘C Stack paste in order",
      "type.text": "Text",
      "type.image": "Images",
      "type.file": "Files",
      "type.link": "Links",
      "type.color": "Colours",
      "card.capture.tag": "02 · Capture and annotate",
      "card.capture.title": "⌘⇧A to select, straight into annotation",
      "card.capture.body": "While you select, crosshair guides run across the screen and the magnifier reads coordinates, colour and ratio; releasing opens the annotation editor.",
      "card.capture.tools": "Rectangle, ellipse, arrow, line, pen, marker, spotlight, mosaic, eraser, magnifier, numbered markers, text, QR code, emoji, insert image, colour picker",
      "card.capture.extra": "Stitched scrolling capture · pin to screen · local Vision OCR · Apple Translation (macOS 15+)",
      "card.ai.tag": "03 · AI tool access",
      "card.ai.title": "Hand your clipboard to an AI as context",
      "card.ai.body": "blinkclip-mcp is a standard stdio JSON-RPC service that works with Claude, Codex, Cursor and similar tools; Settings → AI tools copies the configuration for you.",
      "card.sync.tag": "04 · iCloud sync",
      "card.sync.title": "Off by default. You decide.",
      "card.sync.body": "When enabled, CloudKit syncs history and collections between Macs (live in production); builds without the entitlement fall back to iCloud Drive.",
      "card.sync.state": "Off by default",
      "card.sync.note": "Shortcuts, permissions, exclusion lists, retention and the Stack queue stay local",
      "stats.eyebrow": "Real numbers",
      "stats.title.one": "No wrapping.",
      "stats.title.two": "Just facts.",
      "stats.account.title": "accounts",
      "stats.account.desc": "No sign-up, no login — open it and go. Sync, if you turn it on, uses your own Apple ID.",
      "stats.installer.title": "universal installer",
      "stats.installer.desc": "The same DMG supports Intel and Apple silicon; there is no build to pick.",
      "stats.types.title": "item types",
      "stats.types.desc": "Text, images, files, links and colours, keeping original formats (rich text, HTML, file URLs).",
      "stats.macos.title": "macOS",
      "stats.macos.desc": "Requires macOS 14 or newer; screenshot translation needs macOS 15+.",
      "shortcuts.eyebrow": "Faster than the mouse",
      "shortcuts.title.one": "Four shortcuts,",
      "shortcuts.title.two": "all you need.",
      "shortcuts.lede": "These are the defaults; every one can be changed in Settings → Shortcuts.",
      "shortcuts.open.title": "Open history panel",
      "shortcuts.open.desc": "Summon the card panel from any app",
      "shortcuts.stack.title": "Stack sequential paste",
      "shortcuts.stack.desc": "Paste queued items one after another — handy for forms",
      "shortcuts.region.title": "Region capture",
      "shortcuts.region.desc": "Crosshair guides and magnifier readouts",
      "shortcuts.full.title": "Full-screen capture",
      "shortcuts.full.desc": "Opens the annotation editor immediately",
      "permissions.eyebrow": "Let's be upfront about permissions",
      "permissions.title.one": "Two switches,",
      "permissions.title.two": "one grant.",
      "permissions.lede": "BlinkClip needs system-level access to read interfaces and deliver keystrokes. Without it the app still works; a few features fall back to manual steps.",
      "permissions.access.name": "Accessibility",
      "permissions.access.why": "Reads other apps' interface for scrolling capture and content, and sends keyboard events to other apps for direct paste.",
      "permissions.access.where": "System Settings → Privacy & Security → Accessibility; the app's Settings → Privacy & Permissions pane links straight there.",
      "permissions.screen.name": "Screen Recording",
      "permissions.screen.why": "Captures a region, a window or the whole screen.",
      "permissions.screen.where": "System Settings → Privacy & Security → Screen Recording; also linked from the app.",
      "permissions.events.name": "Send events",
      "permissions.events.why": "Delivers the keyboard events of a direct paste. It comes from the same grant as Accessibility, so System Settings never lists it separately.",
      "permissions.events.where": "Covered by the Accessibility grant; if the app reports it as not ready, re-tick Accessibility and relaunch.",
      "permissions.fallback": "Nothing is blocked without them: features that do not need Accessibility keep working, and scrolling capture can be done with manual scrolling.",
      "privacy.eyebrow": "Local first, not a slogan",
      "privacy.title.one": "Your data lives",
      "privacy.title.two": "on this Mac.",
      "privacy.lede": "Clipboard history, screenshots and settings stay on your Mac by default. Sync is off, no account is required, and nothing passes through our servers.",
      "privacy.path.label": "Where the data lives",
      "privacy.path.note": "Directory 0700, database 0600. On first launch an older clipboard.json is migrated into clipboard.sqlite and the original is kept, never overwritten.",
      "privacy.sync.title": "Only sync goes to the cloud",
      "privacy.sync.body": "Content goes to iCloud under your own Apple ID (the CloudKit container or iCloud Drive/BlinkClip), not to any server of ours. The app reports no usage data.",
      "privacy.sensitive.title": "Sensitive content is skipped",
      "privacy.sensitive.body": "Items the source app marks as confidential or transient are ignored; you can also exclude specific apps in Settings → Privacy & Permissions.",
      "faq.eyebrow": "Before you start",
      "faq.q1": "Which permissions does it need?",
      "faq.a1": "Accessibility reads interfaces and sends keystrokes (direct paste, scrolling capture); Screen Recording is used for screenshots; Send events comes with the Accessibility grant. Grant both in System Settings → Privacy & Security — the app's Settings → Privacy & Permissions pane links there. Nothing is blocked without them, and scrolling capture can be done manually.",
      "faq.q2": "Is my data uploaded?",
      "faq.a2": "Not by default. History, screenshots and settings stay on your Mac; sync is off by default, and when you turn it on content goes to iCloud under your own Apple ID, not to any server of ours. The app reports no usage data.",
      "faq.q3": "Does it run on Intel Macs?",
      "faq.a3": "Yes. The same Universal DMG supports Intel and Apple silicon, and the app requires macOS 14 or newer.",
      "faq.q4": "How do I uninstall it completely?",
      "faq.a4": "Quit BlinkClip and move BlinkClip.app to the Trash. Local data lives in ~/Library/Application Support/BlinkClip/ — delete it too for a full cleanup. If you enabled iCloud sync, cloud data stays in your own iCloud account; if you enabled Launch at login, turn it off in Settings first.",
      "faq.q5": "Why isn't it on the Mac App Store?",
      "faq.a5": "BlinkClip is Developer ID signed and notarized by Apple, runs without App Sandbox, and ships directly through GitHub Releases. The installer opens with a normal double-click, and in-app updates are handled by Sparkle.",
      "faq.q6": "How do updates work?",
      "faq.a6": "About BlinkClip → Check for Updates compares against the latest stable GitHub Release and reuses a result for six hours. After you confirm, Sparkle downloads the complete Universal DMG inside the app and verifies the Ed25519 signatures, saves local data through the normal quit flow, then installs and relaunches. macOS may ask you to grant Accessibility again after an update.",
      "cta.eyebrow": "Try it now",
      "cta.title.one": "Keep the next idea",
      "cta.title.two": "within reach.",
      "cta.lede": "Download the latest stable build, drag it into Applications, and go. Free, open source, no account.",
      "cta.note": "macOS 14+ · Universal (Intel + Apple silicon) · AGPL-3.0",
      "cta.github": "Source and changelog",
      "footer.license": "AGPL-3.0 licensed",
      "footer.credits": "Third-party credits: capcap (MIT, capture overlay and annotation editor) · Sparkle (in-app updates)",
      "footer.repo": "GitHub repository"
    }
  };

  const storageKey = 'blinkclip.website.language';
  const aliases = {
    'zh': 'zh-Hans',
    'zh-cn': 'zh-Hans',
    'zh-hans': 'zh-Hans',
    'zh-sg': 'zh-Hans',
    'en': 'en',
    'en-us': 'en',
    'en-gb': 'en'
  };

  function normalize(value) {
    if (!value) return null;
    return aliases[String(value).toLowerCase()] ?? null;
  }

  let preference = 'system';
  try {
    const saved = localStorage.getItem(storageKey);
    if (saved === 'system') preference = 'system';
    else if (normalize(saved)) preference = normalize(saved);
  } catch { /* Language selection still works without persistent storage. */ }

  function systemLanguage() {
    const languages = navigator.languages?.length ? navigator.languages : [navigator.language];
    for (const requested of languages) {
      const base = String(requested).toLowerCase().split(/[-_]/)[0];
      if (base === 'zh') return 'zh-Hans';
      if (base === 'en') return 'en';
    }
    return 'en';
  }

  let language = preference === 'system' ? systemLanguage() : preference;

  function t(key, values = {}) {
    const text = messages[language]?.[key] ?? messages['zh-Hans'][key] ?? key;
    return text.replace(/\{(\w+)\}/g, (match, name) => values[name] === undefined ? match : String(values[name]));
  }

  function applyLanguage() {
    language = preference === 'system' ? systemLanguage() : preference;
    document.documentElement.lang = language;
    for (const element of document.querySelectorAll('[data-i18n]')) {
      element.textContent = t(element.dataset.i18n);
    }
    for (const attribute of ['alt', 'aria-label', 'placeholder', 'content', 'title']) {
      const marker = `data-i18n-${attribute}`;
      for (const element of document.querySelectorAll(`[${marker}]`)) {
        element.setAttribute(attribute, t(element.getAttribute(marker)));
      }
    }
    const meta = document.querySelector('meta[property="og:locale"]');
    if (meta) meta.content = language === 'en' ? 'en_US' : 'zh_CN';
    const label = t('language.trigger', { language: language === 'en' ? 'English' : '简体中文' });
    const trigger = document.querySelector('#language-trigger');
    if (trigger) {
      trigger.setAttribute('aria-label', label);
      trigger.setAttribute('title', label);
    }
    for (const option of document.querySelectorAll('[data-language]')) {
      option.setAttribute('aria-pressed', String(option.dataset.language === preference));
    }
    document.title = t('meta.title');
    document.dispatchEvent(new CustomEvent('blinkclip:languagechange', { detail: { language } }));
  }

  function setPreference(value) {
    preference = value === 'system' ? 'system' : (normalize(value) ?? 'system');
    try {
      if (preference === 'system') localStorage.removeItem(storageKey);
      else localStorage.setItem(storageKey, preference);
    } catch { /* Keep the choice for this visit without requiring persistent storage. */ }
    applyLanguage();
  }

  window.BlinkClipI18n = { t, get language() { return language; }, setLanguage: setPreference };

  const switcher = document.querySelector('.language-switch');
  const trigger = document.querySelector('#language-trigger');
  for (const option of document.querySelectorAll('[data-language]')) {
    option.addEventListener('click', () => {
      setPreference(option.dataset.language);
      if (switcher) switcher.open = false;
      if (trigger) trigger.focus();
    });
  }
  document.addEventListener('click', event => {
    if (switcher?.open && switcher.contains && !switcher.contains(event.target)) switcher.open = false;
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && switcher?.open) {
      switcher.open = false;
      if (trigger) trigger.focus();
    }
  });
  window.addEventListener('languagechange', () => { if (preference === 'system') applyLanguage(); });
  applyLanguage();
})();
