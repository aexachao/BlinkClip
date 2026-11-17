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

## 修复轮（2026-11-17）

- 基线：`8cc1579`，开工时 `git status --short` 为空（工作区干净）。
- 范围：`website/style.css`、`scripts/tests/test_sync_release_downloads.py`、`evidence/website/**`。未改 Swift / 版本 / CHANGELOG，未 push，未启用 Pages。
- 本轮修掉 §10 第 1 条（CI 测试报错）。

### 1) 去掉薰衣草色

| 位置 | 改前 | 改后 | 为什么 |
| --- | --- | --- | --- |
| `website/style.css:636` `.hero-visual-panel` | `linear-gradient(145deg, rgba(61,92,255,.13), rgba(255,107,53,.07) 60%, rgba(250,250,248,.4))` | 单色钴蓝洗色 `rgba(61,92,255,.10) → .03(40%) → 0(64%)` 叠暖中性 `rgba(250,250,248,.34) → rgba(242,240,235,.62)` | 13% 钴蓝 + 7% 橙在暖底上合成 ≈(221,213,225)，HSV 色相 ≈282°（薰衣草）；单色钴蓝后同一区域实测 (225,229,246)，色相 228.6°（蓝）。橙块仍在面板外侧，不再与钴蓝叠色 |
| `website/style.css:890` `--accent-bright` | `#9aabff`（色相 229.9°，饱和度 0.396） | `#8ba3ff`（色相 227.6°，饱和度 0.455） | 旧值同色相但饱和度过低，在 `#191917` 深底上读作灰紫/薰衣草；新值是明确的浅钴蓝。深底对比度 8.08 → **7.36**，仍 ≥4.5 |
| `website/style.css:95` `.texture-seoul` | 钴蓝 0.07 + **橙 0.055** + 钴蓝 0.03 三道径向 | 钴蓝 0.06 + 钴蓝 0.04 两道 | 首屏右上角同时有蓝色 `hero-glow` 与橙色径向（同 85% 15% 角），实测该处 (235,231,240)、色相 266.7°，即淡紫块；去掉橙色后只剩钴蓝 |

全表色值审计（`style.css` 全部 hex + rgba 逐个转 HSV）：改后**没有任何色值落在 260–285° 紫带**；蓝色族只剩 `#3d5cff`（230.4°）、`#2b46d6`（230.5°）、`#8ba3ff`（227.6°），其余为暖中性（`#fafaf8` / `#f2f0eb` / `#191917`）与橙（`#ff6b35` / `#8b4513` / `#f5ede0`）。

### 2) 修既有 CI 测试

`scripts/tests/test_sync_release_downloads.py:113-115`：

- 语言键 `zh-CN` → `zh-Hans`（新站字典键）。
- 提取正则 `r"const messages = (\{[\s\S]*?\n\});"` → `r"const messages = (\{[\s\S]*?\n[ \t]*\});"`：允许闭括号缩进，仍要求 `};` 收尾（顶格写法也兼容）；非贪婪匹配仍停在 messages 对象的收尾行，不会截到内层 `}`。
- 其它断言（版本前缀、`.dmg` 不写死、`1.0.8` 不残留）与 9 个测试项一个没删、没放宽。

回归灵敏度实测（把修好的测试临时改回错误写法跑一遍，证明断言仍然生效）：

```
old_language_key (zh-CN)            → detected=True  | FAILED (errors=1)
dmg_assertion_flipped               → detected=True  | FAILED (failures=1)
hero_release_must_not_pin_version   → detected=True  | FAILED (failures=1)
```

### 3) 移动端首屏观感

根因不是"折叠切屏"：390×844 下首屏 `heroBottom = 844`，卡片并没有被视口切掉。真正的原因是 `@media (max-width:620px)` 里 `.hero-shot img { max-height:120px; object-fit:cover; object-position:left center }` 把 2:1 的产品截图压成 332×120 的**中段横切**（上下都被裁），看起来就是"露半张卡片"。

采用「在 390 下让截图在首屏内完整」方案：

- `.hero-shot img`：`max-height: none; object-fit: contain; object-position: center`（按自然 2:1 渲染）。
- `.hero-shot`：`max-width: min(100%, 460px)`，让 390–620 之间宽度也不会把首屏撑出视口。

实测 390 卡片：截图 332×166（改前 332×120 被裁）、卡片底 721px，在斜切裁线（右缘 743px）之上；首屏仍自成一屏。

未采用"底部渐变遮罩出血"的原因：hero 自身有 `clip-path: polygon(0 0,100% 0,100% 88%,0 100%)` 斜切边，遮罩必须与对角线对齐才不会出现"二次硬切"，改动面比缩图方案大且更难验证。

### 4) 紫像素比例（改前 / 改后）

扫描器：`evidence/website/tools/purple-scan.py`。**strict** = HSV 色相 260–285° 且饱和度 >0.08；**relaxed** = 255–295° 且 >0.03（用来抓低饱和的淡紫洗色——390 改前 strict 就是 0，只有 relaxed 能量化）。

| 截图 | strict 改前 | strict 改后 | relaxed 改前 | relaxed 改后 |
| --- | --- | --- | --- | --- |
| `1440x900.png` | 0.2779% | **0.0%** | 4.1037% | **0.0005%** |
| `1024x768.png` | 0.1699% | **0.0%** | 3.4721% | **0.0003%** |
| `390x844.png` | 0.0% | **0.0%** | 0.161% | **0.0%** |
| `en-1440x900.png` | 0.2487% | **0.0%** | 3.4115% | **0.0%** |
| `en-390x844.png` | 0.0% | **0.0%** | 0.2063% | **0.0%** |
| `1440x900-full.png` | 0.0297% | **0.0005%** | 0.449% | **0.0009%** |
| `1024x768-full.png` | 0.015% | **0.0009%** | 0.2971% | **0.0016%** |
| `390x844-full.png` | 0.0002% | **0.0007%** | 0.0173% | **0.0008%** |

改前热点集中在首屏面板右上（1440 的 x≈1200–1320 / y≈200–280），与实拍一致。改后残留只有 54px（1440 全页）/ 24px（390 全页），全部落在本托钴蓝焦点卡的胶囊描边抗锯齿上（坐标 y≈1600 / y≈1480），不是色块。

### 5) 对比度复测（`--accent-bright` 的 6 处深底用法）

`node evidence/website/tools/contrast-check.cjs … → evidence/website/shots/contrast.json`

| 用法 | 前景 | 背景 | 对比度 |
| --- | --- | --- | --- |
| `.stats .eyebrow` | `rgb(139,163,255)` | `rgb(25,25,23)` | **7.36** |
| `.stat-row.is-focal .stat-value` | 同上 | 同上 | **7.36** |
| `.cta .eyebrow` | 同上 | 同上 | **7.36** |
| `.cta-title .accent` | 同上 | 同上 | **7.36** |
| `.footer-link` | `rgb(250,250,248)` | 同上 | 16.85 |
| `.cta-github` | `rgba(250,250,248,.82)` | 同上 | 11.57 |

（改前 `#9aabff` 为 8.08，改后 7.36，均 ≥4.5。）

### 6) 首屏自成一屏 + 截图完整度

`node evidence/website/tools/hero-metrics.cjs … → evidence/website/shots/hero-metrics.json`

| 视口 | 语言 | 视口高 | heroBottom | 卡片底 | 斜切右缘 | 截图是否被裁 |
| --- | --- | --- | --- | --- | --- | --- |
| 1440×900 | zh-Hans | 900 | 900 | 576 | 792 | 否（2:1） |
| 1440×900 | en | 900 | 900 | 547 | 792 | 否（2:1） |
| 1024×768 | zh-Hans | 768 | 768 | 478 | 676 | 否（2:1） |
| 1024×768 | en | 768 | 768 | 457 | 676 | 否（2.01:1） |
| 390×844 | zh-Hans | 844 | 844 | 721 | 743 | 否（2:1） |
| 390×844 | en | 844 | 844 | 733 | 743 | 否（2:1） |

### 7) 校验命令与结果

```
node scripts/test-website-i18n.cjs
  {"passed":true,"checks":22,"translation_keys":135}

python3 scripts/check-website.py
  {"passed": true, "checked_links": 50, "translation_keys": 135, "reviewed_images": 6, "universal_download": ""}

python3 -m unittest discover -s scripts/tests
  Ran 16 tests in 0.016s — OK
```

浏览器侧（`evidence/website/shots/verify.json`）：`errors: []`；`zh-Hans` / `en` 切换、`system` 回退、FAQ 手风琴、reduced-motion、CDN 降级均与上一轮一致；390 英文 `heroBottom = 844`、无横向溢出、`smallTargets: []`。

> 本轮截图用的是全新 Chrome profile（`--lang=zh-CN`），所以中文快照是 `stored: null` / `pressed: "system"`（系统协商到 `zh-Hans`），比上一轮「profile 里残留 zh-Hans 存值」更干净；`verify.json` 里这两行因此与 P5 版本不同，属预期变化。

### 8) 三档新截图（已覆盖 `evidence/website/shots/`）

- `evidence/website/shots/1440x900.png`（+ `-full`）
- `evidence/website/shots/1024x768.png`（+ `-full`）
- `evidence/website/shots/390x844.png`（+ `-full`）
- 英文：`evidence/website/shots/en-1440x900.png`（+ `en-1440-full`）、`en-390x844.png`
- 深底对比证据：`stats-1440x900.png`、`cta-1440x900.png`
- 新增工具：`evidence/website/tools/purple-scan.py`、`contrast-check.cjs`、`hero-metrics.cjs`；产物 `contrast.json`、`hero-metrics.json`

截图仍用同一 headless Chrome 156 经 CDP `Emulation.setDeviceMetricsOverride` 取得精确视口（理由见 §10 第 2 条）。

### 9) 未通过 / 假设 / 风险

1. **报告路径**：任务单写 `/Users/chrisli/dev/闪贴/evidence/patches/citycraft-report.md`，但该文件实际在仓库内 `BlinkClip/evidence/patches/citycraft-report.md`（仓库外的 `evidence/patches/` 没有此文件）。本节追加到仓库内这份报告。
2. **紫像素阈值是自定的**：strict（260–285°，sat>0.08）对 390 改前的低饱和薰衣草不触发，所以同时给了 relaxed（255–295°，sat>0.03）口径；两种口径都列在表里，不单挑对自己有利的那个。
3. **`--accent-bright` 对比度从 8.08 降到 7.36**：满足 ≥4.5，但比旧值低；若产品侧希望更亮，可换 `#9bb0ff`（会更接近旧的灰紫观感，需重新扫紫像素）。
4. **768×1024 档（不在验收档）**：首屏内容本来就高于视口（`heroBottom` 1082 vs 1024），属 P5 遗留，本轮未改，也未把它算作通过。
5. **621–980px 区间**：`≤620` 的缩图规则不生效，此区间仍按自然比例渲染（P5 起即如此）；本轮只改了 ≤620 的横切问题与 ≤620 的宽度上限。
6. **橙块保留**：`.hero-visual::before` 的橙色强调块仍在，只是不再与钴蓝洗色重叠；若后续把橙色叠回钴蓝区域，薰衣草会重新出现。
7. 本轮未跑 Swift/原生构建与打包（任务范围外，且 AGENTS.md 要求本机构建走 storage-guard），`npm run test:core` 等未验证。

## CI 修复（GitHub Pages 部署在同步后必挂）

### 1) 根因

`.github/workflows/pages.yml` 的顺序是「先 `sync-release-downloads.py` 同步最新正式版，再跑 `node scripts/test-website-i18n.cjs`」。同步脚本会把两处 `class="button"` 的 href 从 `…/releases/latest` 改写成**固定版本 DMG**（`…/releases/download/v1.0.32/BlinkClip-1.0.32-macos-universal.dmg`），而旧断言要求两个按钮**必须**等于 `…/releases/latest`、且整份 HTML 里**不许**出现 DMG 文件名 —— 两者互斥，CI 必挂（run 44090516621）。

本地复现（同步后跑测试，基线 `7977a3e`）：

```
$ python3 scripts/sync-release-downloads.py --release-json /tmp/rel.json
{"release": "v1.0.32", "changed": ["website/index.html", "website/i18n.js"]}
$ node scripts/test-website-i18n.cjs
AssertionError [ERR_ASSERTION]: Expected values to be strictly equal:
+ 'https://github.com/aexachao/BlinkClip/releases/download/v1.0.32/BlinkClip-1.0.32-macos-universal.dmg'
- 'https://github.com/aexachao/BlinkClip/releases/latest'
    at scripts/test-website-i18n.cjs:308:36
```

### 2) 改法（保持意图，不放宽）

**`website/index.html`（+4 行，只有注释）**：`hero-actions` 与 `cta-actions` 里给两个下载按钮各套一对「机器同步区」标记 `<!-- blinkclip-download:start/end -->`。任务单假设 HTML 里已有该标记块，实际只有 `README.md` / `README.en.md` 有；这里是按任务单允许的「最小改动加稳定包裹」补上。同步脚本一个字节没改（它只替换两个按钮 href，与标记共存）。

**`scripts/test-website-i18n.cjs`（1 → 3 项检查，22 → 24）**：

1. `versioned DMG links are pinned only inside the synchronized download markers`
   - Start/End 标记各恰好 2 对；
   - 把两个标记区间从 HTML **切掉**后，剩余的人手写内容里**不许**出现 `BlinkClip-\d+\.\d+\.\d+-macos-universal\.dmg`，也不许出现 `releases/download/`。
2. `hero and CTA download links target the latest release or its synchronized DMG`
   - 仍然要求恰好 2 个 `.button`；
   - 每个 href 必须**要么**是 `https://github.com/aexachao/BlinkClip/releases/latest`，**要么**是标记块里那条 DMG，其它 URL 一律失败；
   - 未发布状态（标记块里没有 DMG）额外要求 `data-release-version` 为空，且按钮只能是 `…/releases/latest` 或 `…/releases`（`--unreleased` 的产物）。
3. `synchronized markers hold exactly one DMG link each, identical and matching the release version`
   - 每个标记块**恰好一条** DMG 链接（防同步产生重复）；
   - 两块必须是**同一个** URL（防版本漂移）；
   - 链接里 `releases/download/vX.Y.Z` 与文件名 `BlinkClip-X.Y.Z` 一致，且等于 `data-release-version`。

没有删除任何既有检查项，也没有任何断言被写成恒真：未发布分支同样要求「版本号为空」，写死版本就会失败。

**与任务单的偏差（已按最接近意图的方式落地）**：任务单设想的是**一个**标记块里恰好一条 DMG 链接；实际同步会同时改写 hero 和 CTA 两个按钮（`scripts/tests/test_sync_release_downloads.py` 也断言了 2 处），所以落地为**两个**标记块、「每块恰好一条 + 两块必须完全相同」。重复/漂移都仍然会失败。

### 3) 验证一：按 CI 顺序模拟（真实 Release v1.0.32）

仓库副本里完整走一遍 workflow 的步骤：

```
$ node scripts/test-website-i18n.cjs                      # 同步前（仓库已提交状态）
{"passed":true,"checks":24,"translation_keys":135}

$ python3 scripts/sync-release-downloads.py --release-json /tmp/rel.json
{"release": "v1.0.32", "changed": ["website/index.html", "website/i18n.js"]}

$ python3 -m unittest discover -s scripts/tests -p 'test_sync_release_downloads.py'
Ran 9 tests in 0.013s — OK

$ python3 scripts/check-website.py
{"passed": true, "checked_links": 50, "translation_keys": 135, "reviewed_images": 6, "universal_download": "1.0.32"}

$ node --check website/i18n.js && node --check website/site.js
ok

$ node scripts/test-website-i18n.cjs                      # 同步后（新断言生效）
{"passed":true,"checks":24,"translation_keys":135}

$ python3 -m unittest discover -s scripts/tests           # 16 tests
Ran 16 tests in 0.016s — OK

$ python3 scripts/sync-release-downloads.py --release-json /tmp/rel.json   # 幂等
{"release": "v1.0.32", "changed": []}
```

补充覆盖：

- 未来版本（用 `test_sync_release_downloads.py` 的 `v9.8.7` 夹具渲染）→ `checks:24 passed`、`check-website.py` 报 `universal_download: "9.8.7"`，说明断言不依赖当前具体版本号。
- `--unreleased` 状态（按钮 → `…/releases`、`data-release-version=""`）→ `checks:24 passed`。

### 4) 验证二：反向灵敏度（改了就必须挂）

在同步后的副本上逐项注入错误，每次只改一处：

| 注入 | 结果 | 触发的断言 |
| --- | --- | --- |
| 标记块里的版本改成 `v9.9.9` | FAILED | `data-release-version must match the synchronized DMG` |
| 人手写区域插一条固定版本 DMG 链接 | FAILED | `hand-written markup must not pin an installer version` |
| 按钮 href 改成 `https://example.com/BlinkClip.dmg` | FAILED | 按钮断言打印该 URL |
| 同一个标记块里塞第二条 DMG 链接 | FAILED | `each synchronized region carries exactly one DMG link` |
| 两块各写一个不同版本（v1.0.32 / v1.0.31） | FAILED | 版本一致性 |
| 删掉 `blinkclip-download` 标记 | FAILED | `0 !== 2`（标记对数） |
| URL 前缀 `v1.0.32` 但文件名写 `BlinkClip-1.0.31-` | FAILED | `'1.0.32' !== '1.0.31'` |
| `data-release-version=""` 但标记块里仍有 DMG | FAILED | `data-release-version must match the synchronized DMG` |

结论：8 项注入全部失败，断言不恒真。

### 5) 未验证 / 假设 / 风险

1. **未在真 CI 上验证**：按任务单禁止 push，本机用 `gh api` 取的真实 Release JSON（`v1.0.32`）在仓库副本里复刻 workflow 顺序；`ubuntu-latest` 的行为、`gh api` 认证、Pages 部署本身未验证。
2. **两个标记块的形状**：如果以后有人把同步标记块挪位置/只留一块，测试会报「标记各 2 对」失败——这是有意的回归网，不是漏配。
3. **未发布分支允许 `…/releases`**：`sync-release-downloads.py --unreleased` 会把按钮写成 `…/releases`（不是 `…/latest`），测试为此显式放行该 URL，但只在「标记块里一条 DMG 都没有且 `data-release-version` 为空」时放行；任何一条不满足都会失败。
4. 未改 Swift、版本号、CHANGELOG、workflows；未 push。
