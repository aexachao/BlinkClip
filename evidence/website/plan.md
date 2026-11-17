# 闪贴官网重做 — 设计计划（citycraft · 首尔）

- 仓库：`/Users/chrisli/dev/闪贴/BlinkClip`，基线 HEAD `e7564e6`（v1.0.32）
- 输出：`website/`（GitHub Pages 只上传该目录）
- 技能：`citycraft`（SKILL.md + references/nav-catalog.md、product-demo-hero.md、preview-workflow.md）
- 事实来源：`README.md` / `README.en.md`（功能、权限、系统要求、同步口径、隐私、更新、许可、致谢）
- 资产：citycraft `assets/`（clip-paths.css、textures.css、gsap-snippets.js、sections/*-variants.html、extract_variant.py、get_city_tokens.py）

## 1. 城市 token（`get_city_tokens.py "首尔"`，Python 3.13）

| token | 值 | 用途 |
| --- | --- | --- |
| `CITY_BG` | `#fafaf8` | 页面近白暖底（禁用 `#ffffff`） |
| `CITY_SURFACE` | `#f2f0eb` | 卡片 / 次级面 |
| `CITY_INK` | `#191917` | 正文与深色带 |
| `CITY_MUTED` | `#6b6b63` | 辅助文字（近白底上对比度 ≥ 4.5:1） |
| `CITY_ACCENT` | `#3d5cff` | 钴蓝主色（按钮、焦点卡、大数字描边） |
| `--accent-2` | `#ff6b35` | 橘子强调，仅装饰（不用于正文） |
| `--line` | `rgba(25,25,23,0.1)` | 分隔线 |

纹理：`get_city_tokens.py "首尔" --texture` 输出（径向钴蓝/橘色 mesh）写入 `website/_staging/_texture.css`，再拼 `clip-paths.css`。
字体：`Plus Jakarta Sans`（display）+ `Outfit`（body），Google Fonts `display=swap`；两种字体均带系统回退。
圆角：卡片 20–32px（`--r-card: 28px`、`--r-lg: 32px`、`--r-sm: 20px`）。
动效：`power2.out` / `back.out(1.4)`，0.6–0.9s（首尔条目）。

## 2. 变体选择

| 段落 | 变体 | 理由 |
| --- | --- | --- |
| Hero | **Hero B 分屏张力** | 左侧价值主张 + 右侧真实剪贴板面板截图；斜切 `clip-path` 面板正是首尔“色块构图”。不选 D（产品演示型）因为 D 需要自绘界面帧，与“必须真实截图、不得伪造产品界面”冲突。 |
| 功能 | **Features D 本托格子** | 4 个能力域是并列模块而非步骤：剪贴板历史（2×2 钴蓝焦点卡）、截图与标注（1×2 高卡，真实框选/工具栏截图）、AI MCP（1×1）、同步（1×1）。视觉焦点：钴蓝大卡 + 高卡截图。 |
| 数字 | **Features A 大数字** | 只用真实数字：0 账号、1 个通用安装包、5 类收录内容、macOS 14+。深墨色带 + 钴蓝描边数字。 |
| FAQ | **FAQ_A 编辑排版型** | 左侧巨大 “FAQ” sticky 锚点 + 右侧手风琴；6 条真实问题。 |
| CTA | **Power CTA** | 自带斜切顶边 + 磁吸式主按钮（下载是唯一转化）；删除模板里的 “10,000+ developers” 等编造背书。 |
| 导航 | **Nav B 底部磁性胶囊** | nav-catalog 明确“首尔、巴黎”适配；惊喜元素 = 光标 120px 内胶囊磁吸位移 + 弹性回位；桌面显示文字，移动端图标 + 44px 触控目标。语言切换独立固定在右上角（按需求）。 |

不使用 testimonials / 客户 logo / 价格 / 用户量。

## 3. 页面顺序、屏数与图片

| # | 段落 | 预计高度（1440×900） | 图片 / 图形 |
| --- | --- | --- | --- |
| 1 | Hero B | 1 屏（100vh，min 720px） | `screenshot-clipboard-panel.png`（真实剪贴板面板）+ 钴蓝偏移色块 + ⇧⌘V 键帽；图标 sprite |
| 2 | Features D 本托 | ~1.2 屏 | `screenshot-capture-overlay.jpg`（框选覆盖层）+ `screenshot-editor-toolbar.png`（标注工具栏，宽条） |
| 3 | Stats A 大数字 | ~0.9 屏 | 无图片，数字排版 + 钴蓝描边 |
| 4 | 快捷键 | ~0.7 屏 | 键帽组件（HTML/CSS），无图片 |
| 5 | 权限 | ~1 屏 | `screenshot-settings-permissions.png`（真实权限设置页） |
| 6 | 隐私 / 同步 | ~0.9 屏 | `screenshot-settings-capture.png`（真实截图设置页）+ 本地路径代码块 |
| 7 | FAQ_A | ~1 屏 | 无图片，编辑排版 |
| 8 | CTA + 页脚 | ~0.7 屏 | 图标 sprite |

图片一律无 caption（技能规则）；致谢只在页脚一行。

## 4. 段落边界（每个边界单独选，至少 2 类）

1. Hero → Features：`clip-diagonal-br`（首屏右下斜切，进入功能）
2. Features → Stats：`clip-parallelogram`（深色数字带斜切压上）
3. Stats → 快捷键：`section-rule`（极细钴蓝分隔线，节奏放缓）
4. 快捷键 → 权限：`clip-round-bottom` + 下一段负 margin 互锁（柔和曲线）
5. 权限 → 隐私：`clip-scallop`（扇贝边，organic soft）
6. 隐私 → FAQ：`section-rule`（编辑排版 hairline）
7. FAQ → CTA：CTA 自带 `clip-path: polygon(0 8vw, 100% 0, 100% 100%, 0 100%)` 斜切
8. CTA → 页脚：平边 + hairline

## 5. 动效（来自 `assets/gsap-snippets.js`）

- `initHeroEntrance('.hero-copy', '.hero-copy > *')`：hero 入场 stagger（blur + y）
- `initLineReveal('.js-line-reveal')`：标题逐行 reveal；`.line-wrap` 加 CJK 修正 `padding-top: 0.15em; margin-top: -0.15em`
- `initParallax`：≥2 层 —— `.hero-visual`（1.15）、`.hero-glow`（0.6）
- `initMagneticPill('.pill-nav')`：导航惊喜
- ScrollTrigger 段落标题 reveal + 数字计数（`animateCount` 用于 0/1/5/14 真实数字）
- `prefers-reduced-motion`：CSS 关闭过渡/动画；JS 在 reduced 下不初始化 GSAP；CDN 失败时 `if (!window.gsap) return`，内容静态可读（CSS 不预设 opacity:0）

## 6. 双语

- `website/i18n.js`：`data-i18n` / `data-i18n-alt` / `data-i18n-aria-label` / `data-i18n-content` + 字典 `zh-Hans` / `en`
- 默认：浏览器语言（`zh*` → 中文，其余 → 英文）；手动选择存 `localStorage['blinkclip.website.language']`
- 兼容旧值：`zh-CN`（旧版存值）映射到 `zh-Hans`；`system` 仍表示跟随系统
- 切换更新：正文、`<title>`、`document.title`、meta description/og、`alt`、`aria-label`、`html.lang`、`aria-pressed`
- `scripts/test-website-i18n.cjs` 重写为覆盖同一组断言（字典键/占位符一致、HTML 绑定齐全、系统语言协商、手动优先与持久化、回到跟随系统、非法存值回退、storage 被拒、系统语言变化、手动不被覆盖、metadata/alt/aria 本地化、语言控件状态与关闭）
- `scripts/check-website.py` 校验：资源存在、无绝对根路径、图片白名单（无隐私图/无未确认截图）、双语键完整、下载链接只指向 releases（无硬编码 DMG/版本）

## 7. 与现有 CI 的兼容

`.github/workflows/pages.yml` 会执行 `node --check website/site.js` 和 `scripts/sync-release-downloads.py`（依赖 `data-release-version`、`class="release-pill"`、恰好 2 个 `class="button"`、i18n 键 `hero.release` / `download.meta` / `download.mac`）。本任务不修改这些脚本，因此页面保留上述最小兼容接口；下载按钮源码仍指向 `releases/latest`（不写死版本）。`website/site.js` 保留为无 GSAP 的渐进增强（FAQ 手风琴、导航 scrollspy、语言菜单关闭）。

## 8. 验收

- `node --check website/i18n.js website/site.js website/main.js`
- `node scripts/test-website-i18n.cjs`
- `python3 scripts/check-website.py`
- `python3 -m unittest discover -s scripts/tests -p 'test_sync_release_downloads.py'`（兼容性回归）
- `python3 -m http.server --directory website` + headless Chrome 1440×900 / 1024×768 / 390×844 截图到 `evidence/website/shots/`
- 自查：首屏自成一屏、左右边距相等、无缺图、无横向滚动、对比度 ≥4.5:1、CJK 标题不裁切、390 下按钮 ≥44pt
