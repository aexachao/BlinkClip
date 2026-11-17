(() => {
  const messages = {
    "zh-Hans": {
      "brand.name": "闪贴",
      "meta.title": "闪贴 BlinkClip — 复制过的都找得回来，截完图直接标注",
      "meta.description": "闪贴（BlinkClip）是本地优先的 macOS 剪贴板历史与截图标注工具：文本、图片、文件、链接和颜色收进一个可搜索面板，⌘⇧A 框选后直接标注，无需账号。",
      "meta.socialDescription": "本地优先的 macOS 剪贴板历史与截图标注工具。历史只存在本机，同步默认关闭，无需账号。",
      "a11y.skip": "跳到正文",
      "a11y.navigation": "主导航",
      "a11y.home": "闪贴首页",
      "a11y.download": "下载闪贴（GitHub Releases）",
      "language.label": "显示语言",
      "language.system": "跟随系统",
      "language.short": "中文",
      "language.trigger": "切换语言：{language}",
      "nav.capture": "截图",
      "nav.history": "剪贴板",
      "nav.integrations": "AI 与同步",
      "nav.shortcuts": "快捷键",
      "nav.permissions": "权限",
      "nav.faq": "常见问题",
      "nav.download": "下载",
      "hero.title.one": "复制过的，",
      "hero.title.two": "都找得回来。",
      "hero.lede": "文本、图片、文件、链接和颜色收进一个可搜索面板，⌘⇧A 框选后直接标注。",
      "hero.meta": "macOS 14+ · Universal · 本地优先 · 无需账号",
      "hero.secondary": "查看功能",
      "hero.release": "当前正式安装包：BlinkClip 1.0.33",
      "download.mac": "免费下载 Mac 版",
      "download.meta": "v1.0.33 · macOS 14+ · Intel / Apple 芯片",
      "image.clipboard": "闪贴剪贴板面板：横向卡片浏览文本、图片与链接，卡片标明类型与来源应用",
      "image.overlay": "框选覆盖层：贯穿全屏的十字辅助线、蓝色选区与放大镜读数（坐标 / 色值 / 比例）",
      "image.toolbar": "截图后的标注编辑器浮动工具栏",
      "image.permissions": "设置 → 隐私与权限：辅助功能与屏幕录制状态，以及内容过滤开关",
      "capture.eyebrow": "截图与标注",
      "capture.title": "⌘⇧A 框选，松手就标注",
      "capture.point.one": "十字辅助线贯穿全屏，放大镜实时读坐标、色值与比例",
      "capture.point.two": "矩形、箭头、马赛克、聚光灯、文字等 16 种标注工具",
      "capture.point.three": "长截图自动拼接，钉图浮窗，本地 Vision OCR 与 Apple 翻译（macOS 15+）",
      "history.eyebrow": "剪贴板历史",
      "history.title": "复制过的，按 ⇧⌘V 回来",
      "history.point.one": "文本、图片、文件、链接和颜色自动入库，保留原始格式",
      "history.point.two": "关键字搜索，按类型、来源应用和日期筛选",
      "history.point.three": "保留 1–60 天或永久；Pinboard 收藏与 ⇧⌘C Stack 顺序粘贴",
      "integrations.eyebrow": "AI 与同步",
      "integrations.title": "接得上 AI，也接得上 iCloud",
      "ai.name": "把剪贴板交给 AI 当上下文",
      "ai.desc": "blinkclip-mcp 是标准 stdio JSON-RPC 服务，Claude、Codex、Cursor 都能接；「设置 → AI 工具」可复制配置。",
      "sync.name": "iCloud 同步，默认关闭",
      "sync.desc": "开启后经 CloudKit 在 Mac 之间同步历史与分组；快捷键、权限与保留期限不同步。",
      "shortcuts.eyebrow": "快捷键",
      "shortcuts.title": "四个快捷键",
      "shortcuts.lede": "默认值如下，全部可以在「设置 → 快捷键」里改。",
      "shortcuts.open": "打开历史面板",
      "shortcuts.stack": "Stack 顺序粘贴",
      "shortcuts.region": "区域截图",
      "shortcuts.full": "全屏截图",
      "privacy.eyebrow": "权限与隐私",
      "privacy.title": "要什么权限，数据在哪",
      "privacy.lede": "闪贴需要系统级能力才能读界面、投按键和截图；不授予也能用，滚动截图可改用手动。",
      "perm.head": "需要哪些权限",
      "perm.access.name": "辅助功能",
      "perm.access.desc": "读取其他应用界面（滚动截图），并向其他应用发送按键（直接粘贴）。",
      "perm.screen.name": "屏幕录制",
      "perm.screen.desc": "截取区域、窗口或整个屏幕。",
      "perm.events.name": "发送事件",
      "perm.events.desc": "与辅助功能同源，系统设置不单独列出。",
      "privacy.head": "数据在哪",
      "privacy.local.name": "本机数据库",
      "privacy.local.desc": "历史、截图与设置只在本机：~/Library/Application Support/BlinkClip/（0700 / 0600 权限）。",
      "privacy.sync.name": "同步默认关闭",
      "privacy.sync.desc": "开启后内容进入你自己的 iCloud（CloudKit 或 iCloud Drive），不经过我们的服务器，也不上报使用数据。",
      "privacy.sensitive.name": "敏感内容不记录",
      "privacy.sensitive.desc": "来源应用标记为机密或临时的内容会被跳过，也可指定不记录的应用。",
      "faq.eyebrow": "上手前",
      "faq.title": "常见问题",
      "faq.q1": "需要哪些权限？",
      "faq.a1": "辅助功能用于读界面和发送按键（直接粘贴、滚动截图），屏幕录制用于截图。都在「系统设置 → 隐私与安全性」授权，应用内「设置 → 隐私与权限」有直达按钮；不授予也能用。",
      "faq.q2": "数据会上传吗？",
      "faq.a2": "默认不会。历史、截图和设置只存在本机；同步默认关闭，开启后内容进入你自己 Apple ID 下的 iCloud，不经过本项目的服务器。",
      "faq.q3": "支持 Intel Mac 吗？",
      "faq.a3": "支持。同一个 Universal DMG 同时支持 Intel 与 Apple 芯片，系统要求 macOS 14 或更新。",
      "faq.q4": "怎么更新或卸载？",
      "faq.a4": "「关于闪贴 → 检查更新」在应用内下载 Universal DMG 并校验签名后安装，更新后系统可能要求重新授予辅助功能。卸载时把 BlinkClip.app 移到废纸篓，再删除 ~/Library/Application Support/BlinkClip/ 即可。",
      "cta.title.one": "把下一个灵感，",
      "cta.title.two": "留在手边。",
      "cta.lede": "拖进「应用程序」就能用。免费、开源、无需账号。",
      "cta.note": "Universal 通用包 · Developer ID 签名，Apple 公证 · AGPL-3.0",
      "footer.license": "AGPL-3.0 许可",
      "footer.credits": "第三方致谢：capcap（MIT）· Sparkle（应用内更新）",
      "footer.repo": "GitHub 仓库"
    },
    "en": {
      "brand.name": "BlinkClip",
      "meta.title": "BlinkClip — Everything you copy stays findable, every screenshot ready to annotate",
      "meta.description": "BlinkClip is a local-first clipboard history and screenshot tool for macOS: text, images, files, links and colours in one searchable panel, and ⌘⇧A opens annotation right after a region capture. No account required.",
      "meta.socialDescription": "A local-first clipboard history and screenshot annotation tool for macOS. History stays on your Mac, sync is off by default, no account required.",
      "a11y.skip": "Skip to content",
      "a11y.navigation": "Main navigation",
      "a11y.home": "BlinkClip home",
      "a11y.download": "Download BlinkClip (GitHub Releases)",
      "language.label": "Display language",
      "language.system": "System language",
      "language.short": "EN",
      "language.trigger": "Change language: {language}",
      "nav.capture": "Capture",
      "nav.history": "Clipboard",
      "nav.integrations": "AI & sync",
      "nav.shortcuts": "Shortcuts",
      "nav.permissions": "Permissions",
      "nav.faq": "FAQ",
      "nav.download": "Download",
      "hero.title.one": "Everything you copy",
      "hero.title.two": "stays findable.",
      "hero.lede": "Text, images, files, links, colours in one searchable panel. ⌘⇧A captures and annotates.",
      "hero.meta": "macOS 14+ · Universal · Local first · No account",
      "hero.secondary": "See features",
      "hero.release": "Current stable installer: BlinkClip 1.0.33",
      "download.mac": "Download for Mac",
      "download.meta": "v1.0.33 · macOS 14+ · Intel / Apple silicon",
      "image.clipboard": "BlinkClip clipboard panel: horizontal cards for text, images and links, each labelled with type and source app",
      "image.overlay": "Selection overlay: full-screen crosshair guides, the blue selection and live magnifier readouts (coordinates / colour / ratio)",
      "image.toolbar": "Floating toolbar of the annotation editor, opened right after a capture",
      "image.permissions": "Settings → Privacy & Permissions: Accessibility and Screen Recording status, plus the content filters",
      "capture.eyebrow": "Capture and annotate",
      "capture.title": "⌘⇧A to select, annotate on release",
      "capture.point.one": "Crosshair guides across the screen; the magnifier reads coordinates, colour and ratio",
      "capture.point.two": "Rectangle, arrow, mosaic, spotlight, text and 16 annotation tools in all",
      "capture.point.three": "Scrolling capture stitched automatically, pin to screen, on-device Vision OCR and Apple Translation (macOS 15+)",
      "history.eyebrow": "Clipboard history",
      "history.title": "Everything you copied, back on ⇧⌘V",
      "history.point.one": "Text, images, files, links and colours captured automatically, original formats kept",
      "history.point.two": "Keyword search, filter by type, source app and date",
      "history.point.three": "Keep 1–60 days or forever; Pinboards and ⇧⌘C Stack paste in order",
      "integrations.eyebrow": "AI and sync",
      "integrations.title": "Works with your AI, syncs with your iCloud",
      "ai.name": "Hand your clipboard to an AI as context",
      "ai.desc": "blinkclip-mcp is a standard stdio JSON-RPC service for Claude, Codex, Cursor and similar tools; Settings → AI tools copies the configuration.",
      "sync.name": "iCloud sync, off by default",
      "sync.desc": "When on, CloudKit syncs history and collections between your Macs; shortcuts, permissions and retention stay local.",
      "shortcuts.eyebrow": "Shortcuts",
      "shortcuts.title": "Four shortcuts",
      "shortcuts.lede": "These are the defaults; all can be changed in Settings → Shortcuts.",
      "shortcuts.open": "Open history panel",
      "shortcuts.stack": "Stack sequential paste",
      "shortcuts.region": "Region capture",
      "shortcuts.full": "Full-screen capture",
      "privacy.eyebrow": "Permissions and privacy",
      "privacy.title": "What it needs, where data lives",
      "privacy.lede": "BlinkClip needs system access to read interfaces, deliver keystrokes and capture the screen. Without it the app still works; scrolling capture can be done by hand.",
      "perm.head": "Permissions it needs",
      "perm.access.name": "Accessibility",
      "perm.access.desc": "Reads other apps' interface for scrolling capture, and sends keystrokes to other apps for direct paste.",
      "perm.screen.name": "Screen Recording",
      "perm.screen.desc": "Captures a region, a window or the whole screen.",
      "perm.events.name": "Send events",
      "perm.events.desc": "Comes from the Accessibility grant; System Settings never lists it separately.",
      "privacy.head": "Where the data lives",
      "privacy.local.name": "Local database",
      "privacy.local.desc": "History, screenshots and settings stay on this Mac: ~/Library/Application Support/BlinkClip/ (0700 / 0600 permissions).",
      "privacy.sync.name": "Sync is off by default",
      "privacy.sync.desc": "When you turn it on, content goes to your own iCloud (CloudKit or iCloud Drive) — never to a server of ours, and no usage data is reported.",
      "privacy.sensitive.name": "Sensitive content skipped",
      "privacy.sensitive.desc": "Items the source app marks as confidential or transient are skipped, and you can exclude specific apps.",
      "faq.eyebrow": "Before you start",
      "faq.title": "Questions",
      "faq.q1": "Which permissions does it need?",
      "faq.a1": "Accessibility reads interfaces and sends keystrokes (direct paste, scrolling capture), and Screen Recording captures the screen. Grant both in System Settings → Privacy & Security, or jump there from the app's Settings → Privacy & Permissions. Nothing is blocked without them.",
      "faq.q2": "Is my data uploaded?",
      "faq.a2": "Not by default. History, screenshots and settings stay on your Mac; sync is off by default, and when you turn it on content goes to iCloud under your own Apple ID, never to a server of ours.",
      "faq.q3": "Does it run on Intel Macs?",
      "faq.a3": "Yes. One Universal DMG covers Intel and Apple silicon, and the app requires macOS 14 or newer.",
      "faq.q4": "How do I update or uninstall?",
      "faq.a4": "About BlinkClip → Check for Updates downloads the Universal DMG inside the app and verifies its signature before installing; macOS may ask you to grant Accessibility again afterwards. To remove it, move BlinkClip.app to the Trash and delete ~/Library/Application Support/BlinkClip/.",
      "cta.title.one": "Keep the next idea",
      "cta.title.two": "within reach.",
      "cta.lede": "Drag it into Applications and go. Free, open source, no account.",
      "cta.note": "Universal installer · Developer ID signed and notarized by Apple · AGPL-3.0",
      "footer.license": "AGPL-3.0 licensed",
      "footer.credits": "Third-party credits: capcap (MIT) · Sparkle (in-app updates)",
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
