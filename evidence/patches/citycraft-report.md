# citycraft 重做 BlinkClip 官网 — 交付报告

- 仓库：`/Users/chrisli/dev/闪贴/BlinkClip`，基线 HEAD `e7564e6`（v1.0.32）
- 技能：`citycraft`（首尔 / Seoul），使用其 `assets/` 资产（`clip-paths.css`、`textures.css`、`gsap-snippets.js`、`sections/*-variants.html`、`extract_variant.py`、`get_city_tokens.py`）
- 站点目录：`website/`（GitHub Pages 只上传该目录）
- 事实来源：`README.md` / `README.en.md`（功能、权限、系统要求、同步口径、隐私、更新、许可、致谢）

## 1. 阶段提交

| 阶段 | sha | 内容 |
| --- | --- | --- |
| P1 | `26afc49` | 素材组装（`website/_staging/`）、截图与图标复制、`evidence/website/plan.md` |
| P2 | `66eb91b` | `index.html` / `style.css` 骨架、底部磁性胶囊导航、分屏 Hero（真实剪贴板截图）、完整双语字典 |
| P3 | `e1da65a` | 功能本托、真实数字、快捷键、权限、隐私、FAQ、CTA、页脚、图标 sprite；删除 staging |
| P4 | `f54f2e6` | `main.js` GSAP 动效、`scripts/test-website-i18n.cjs` 重写、`scripts/check-website.py` 重写 |
| P5 | 本次提交 | 焦点卡收尾、对比度修正、页脚边距、三档截图、验证证据、本报告 |

> 注：P2 与 P3 之间另有一条不属于本任务的提交 `c15c41c feat(settings): 帮助与关于链接改指新官网`（DESIGN.md + Swift/Strings，未触及 `website/`）。任务开始时工作区已有 7 个此类文件修改，本任务未修改、未暂存它们；该提交由会话外的并行工作产生。

## 2. 选定变体与理由

| 段落 | 变体 | 理由 |
| --- | --- | --- |
| Hero | **Hero B 分屏张力** | 左侧价值主张 + 右侧真实剪贴板面板；斜切色块是首尔“色块构图”。不选 D：D 需要自绘界面帧，与“只用真实截图、不伪造产品界面”冲突。 |
| 功能 | **Features D 本托格子** | 四个能力域并列：剪贴板历史（2×2 钴蓝焦点卡）、截图与标注（2×2 高卡，真实框选覆盖层 + 工具栏）、AI MCP（2×1）、同步（2×1）。 |
| 数字 | **Features A 大数字** | 只用真实数字：0 账号、1 个通用安装包、5 类收录内容、macOS 14+。深墨色带 + 描边数字，钴蓝强调 0。 |
| FAQ | **FAQ_A 编辑排版型** | 左侧巨大 FAQ sticky 锚点，右侧 6 条手风琴；内容全部来自 README。 |
| CTA | **Power CTA** | 斜切顶边 + 钴蓝主按钮；删除模板中的用户量等编造背书。 |
| 导航 | **Nav B 底部磁性胶囊** | nav-catalog 标注“首尔、巴黎”适配；惊喜元素 = 光标 120px 内胶囊磁吸位移、离开后弹性回位；滚动时高亮当前段。移动端图标化，44px 触控目标。 |

不使用 testimonials / 客户 logo / 价格 / 用户量。

## 3. 设计 token（首尔）

`get_city_tokens.py "首尔"`（Python 3.13，系统 python3.9 不支持脚本的 `str | None`）：

| token | 值 |
| --- | --- |
| `--bg` | `#fafaf8` |
| `--bg-surface` | `#f2f0eb` |
| `--ink` | `#191917` |
| `--ink-muted` | `#6b6b63` |
| `--accent` | `#3d5cff` |
| `--accent-2` | `#ff6b35` |
| `--accent-ink` | `#2b46d6`（surface 上的小字） |
| `--accent-bright` | `#9aabff`（墨色带上的强调） |
| `--line` | `rgba(25,25,23,0.1)` |

- 字体：`Plus Jakarta Sans`（display）+ `Outfit`（body），Google Fonts `display=swap`，带系统中文字体回退。
- 圆角 20–32px；按钮 100px 胶囊。
- 纹理：`get_city_tokens.py --texture` 输出的 `texture-seoul` 径向 mesh；clip-path 类全部来自 `assets/clip-paths.css`。
- 禁止项检查：`check-website.py` 断言 CSS 不含 `#ffffff`、`#6366f1`。

## 4. 段落边界（每个边界单独选）

| 边界 | 处理 |
| --- | --- |
| Hero → Features | Hero `clip-diagonal-br`；Features 负 margin 上提，斜切处露出 surface |
| Features → Stats | Stats `clip-parallelogram`（深色斜切压在 surface 上） |
| Stats → 快捷键 | Stats 底部斜切 + 快捷键负 margin，露出近白底 |
| 快捷键 → 权限 | 快捷键 `clip-round-bottom`，权限上提互锁 |
| 权限 → 隐私 | 权限 `clip-scallop`，隐私上提，扇贝边露出隐私底色 |
| 隐私 → FAQ | `section-rule` 钴蓝细线 |
| FAQ → CTA | CTA 自带 `clip-path: polygon(0 8vw, 100% 0, 100% 100%, 0 100%)` |
| CTA → 页脚 | 平边 + 墨色衔接 |

层叠用 `z-index` 交替（hero 6 → features 1 → stats 5 → shortcuts 4 → permissions 3 → privacy 2 → cta 3），让每个被裁掉的区域露出下一段的真实底色，而不是 body 底色。

## 5. 页面与图片

| # | 段落 | 图片 |
| --- | --- | --- |
| 1 | Hero B | `screenshot-clipboard-panel.png`（真实面板） |
| 2 | Features D | `screenshot-capture-overlay.jpg`、`screenshot-editor-toolbar.png` |
| 3 | Stats A | 无图，数字排版 |
| 4 | 快捷键 | 无图，键帽组件 |
| 5 | 权限 | `screenshot-settings-permissions.png` |
| 6 | 隐私 | `screenshot-settings-capture.png` |
| 7 | FAQ_A | 无图 |
| 8 | CTA + 页脚 | 图标 sprite |

图片全部无 caption；页脚一行致谢：`AGPL-3.0 许可 · 第三方致谢：capcap（MIT，截图覆盖层与标注编辑器）· Sparkle（应用内更新）`。图标 `replica/Assets/BlinkClipIcon.png`。旧 `website/assets/blinkclip-panel.png`（未确认干净）已删除；`check-website.py` 用 6 张白名单图约束。

## 6. 动效

`main.js` 复用 `assets/gsap-snippets.js` 的模式：

- `initHeroEntrance('.hero-copy', '.hero-copy > *')`：hero 入场 stagger（y + blur）
- `initLineReveal('.js-line-reveal')`：标题逐行 reveal；`.line-wrap` 带 CJK 修正 `padding-top: .15em; margin-top: -.15em`
- `initParallax`：`.hero-glow`（0.6）与 `.hero-shot`（1.15）两层视差
- `initMagneticPill('.pill-nav', 120, 0.28)`：导航磁吸惊喜
- ScrollTrigger：卡片进入 reveal；`animateCount` 驱动 0/1/5/14+ 计数
- `prefers-reduced-motion`：CSS 关闭过渡；JS 直接 return（浏览器验证 `shotInlineStyle: null`）
- CDN 失败：`if (!window.gsap) return`，且 CSS 不预设 `opacity:0`，内容静态可读；`ScrollTrigger` 缺失时仍执行入场/标题/磁吸。实测屏蔽 `cdnjs.cloudflare.com` 后：`gsap=false`、`scrollTrigger=false`、标题文本完整、`opacity=1`、无 GSAP inline style、正文 2937 字符可读（`verify.json` 的 `cdnFallback`）

## 7. 双语

- 字典 135 键 × 2（`zh-Hans` / `en`），键集合与占位符一致；`data-i18n` / `-alt` / `-aria-label` / `-content` / `-title`。
- 默认按浏览器语言（`zh*` → `zh-Hans`，其余 → `en`）；手动选择存 `localStorage['blinkclip.website.language']`；兼容旧值 `zh-CN`；`system` 仍表示跟随系统并删除存值。
- 切换更新正文、`<title>`/`document.title`、meta description/og、`alt`、`aria-label`、`html.lang`、`aria-pressed`，并派发 `blinkclip:languagechange`。
- 浏览器验证（`evidence/website/shots/verify.json`）：
  - 中文：`htmlLang=zh-Hans`，标题 `闪贴 BlinkClip — 复制过的都找得回来，截完图直接标注`，`ogLocale=zh_CN`，alt/aria 中文
  - 英文：`htmlLang=en`，`ogLocale=en_US`，标题/下载文案/alt/aria 全部英文，`stored=en`，`pressed=en`
  - 跟随系统：`stored=null`，`pressed=system`，回到中文
  - FAQ 展开状态跨语言保留；`aria-expanded=true`，答案高度 147px
  - `errors: []`（无 JS 异常）
  - CDN 降级：`cdnFallback` 为 `{gsap:false, scrollTrigger:false, titleText:"复制过的， 都找得回来。", opacity:"1", inlineStyle:null, textLength:2937}`

## 8. 校验命令与结果

```
node --check website/i18n.js website/site.js website/main.js   → ok
node scripts/test-website-i18n.cjs
  {"passed":true,"checks":22,"translation_keys":135}
python3 scripts/check-website.py
  {"passed":true,"checked_links":50,"translation_keys":135,"reviewed_images":6,"universal_download":""}
python3 -m unittest discover -s scripts/tests -p 'test_sync_release_downloads.py'
  Ran 9 tests — FAILED (errors=1)
```

`test-website-i18n.cjs` 保留了旧脚本的检查类别并扩展到 22 项（旧 17 项）：字典键/占位符、HTML 绑定、6 种系统语言协商、手动优先与持久化、旧 `zh-CN` 迁移、回到 system、非法存值、storage 被拒、系统语言变化、手动不被覆盖、metadata/title/alt/aria 本地化、语言控件状态、FAQ 手风琴（开/关/互斥）、跨语言状态、单复数与量词、下载链接不写死版本。原 demo 搜索/筛选检查已随该 demo 被新设计移除而替换为 FAQ 手风琴与语言切换状态检查（页面结构变更，非放宽断言）。

## 9. 三档截图与自查

截图：`evidence/website/shots/`

| 视口 | 首屏 heroBottom | 内容高度 | 横向溢出 | 缺图 | <44pt 目标 |
| --- | --- | --- | --- | --- | --- |
| 1440×900 | 900 | 8288 | 无（1440/1440） | 无 | 无 |
| 1024×768 | 768 | 9037 | 无（1024/1024） | 无 | 无 |
| 390×844 | 844 | 9046 | 无（390/390） | 无 | 无 |
| 390×844（英文） | 844 | — | 无 | 无 | 无 |

其他自查：

- **左右边距相等**：实测 1440 各段 `left=right=80`；1024 `51/51`；390 `20/20`（页脚已补 `padding-inline: var(--gutter)`）。
- **对比度**：关键文本对 ≥4.5:1 —— 正文 16.85、hero lede 8.54、muted/bg 5.14、muted/surface 4.72、accent-ink/surface 6.25、按钮文字/钴蓝 4.82、钴蓝卡正文 `#fafaf8`/`#3d5cff` 4.82、墨色带正文 7.2–9.2、`--accent-bright`/ink 8.08。钴蓝卡小字统一改为纯 `#fafaf8` 或浅底深字胶囊，避免 3.4–4.1 的低对比。
- **CJK 标题不裁切**：`.line-wrap` 加 `padding-top:.15em; margin-top:-.15em`；1440/1024/390 截图目视无裁切。
- **390 按钮 ≥44pt**：实测所有 `a.button/.pill-link/.pill-cta/.language-trigger/.faq-trigger/.cta-github` 均 ≥44（`smallTargets: []`）；CTA 下载按钮 350×61。
- **reduced motion**：`prefers-reduced-motion: reduce` 下 `.hero-shot` 无 GSAP inline style（`reduced.shotInlineStyle = null`）。
- **首屏自成一屏**：三档 `heroBottom == 视口高度`，英文 390 亦为 844。

## 10. 未通过 / 假设 / 风险

1. **`scripts/tests/test_sync_release_downloads.py` 有 1 个错误（非本次允许路径，未修改）**：
   `test_i18n_release_metadata_matches_the_shipped_html` 硬编码读取 `messages["zh-CN"]`，并用 `const messages = (\{…\n\});`（闭括号顶格）提取字典；新站按任务要求使用 `zh-Hans` 语言键、闭括号缩进两格，因此该测试报 `TypeError: 'NoneType' object is not subscriptable`。其余 8 个测试（含发布版渲染、幂等、缺绑定中止）通过。`sync-release-downloads.py` 本身的 i18n 替换不依赖语言键，仍能处理 2 条 `hero.release` / `download.meta` / `download.mac`；最小修复是在该测试中把 `zh-CN` 改为 `zh-Hans` 并放宽闭括号正则（属于 `scripts/tests/`，超出本任务允许路径，故未改）。
2. **headless Chrome 的 `--window-size` 在 macOS 上不等于布局视口**：实测 `1440×900 → 1440×813`、`1024×768 → 1024×681`、`390×844 → 500×757`（宽度被夹到 500）。因此三档截图用同一 headless Chrome（`--headless=new`）经 DevTools Protocol `Emulation.setDeviceMetricsOverride` 获得精确视口；证据 `evidence/website/shots/headless-probe.txt`。若必须使用字面 `--screenshot --window-size`，390 档会得到 500px 布局，不可作为 390 验收。
3. **页面高度**：1440 全页 8288px（约 9.2 屏），比 plan 的估算略长；主要来自本托高卡与权限/隐私的真实截图。未削减内容。
4. **CloudKit 口径**：按 README 写“生产已上线”，未把“物理双机/断网重连仍验收中”的已知限制包装成已通过；隐私段写“开启同步才会上云”。
5. **语言默认**：截图进程的 Chrome profile 里残留了上一次的 `zh-Hans` 存值，所以截图是中文；默认协商逻辑由 Node 测试（6 种语言）覆盖，而非截图进程。
6. **工作区基线**：任务描述为“工作区干净”，实际开始时已有 7 个 Swift/Strings 文件修改（`branding/…`、`replica/…`）；会话期间并行工作以 `c15c41c` 提交了这些改动（未触及 `website/`）。本任务只提交 `website/`、`scripts/` 中指定的两个校验脚本与 `evidence/`，未改 Swift、版本或 CHANGELOG。
7. **版本号**：页面源码不含版本号；两个下载按钮指向 `releases/latest`，`data-release-version=""` 仅为兼容既有 Pages 发布同步脚本而保留。
