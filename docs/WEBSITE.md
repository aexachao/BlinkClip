# 闪贴 / BlinkClip 官网

官网源码位于 `website/`，使用原生 HTML、CSS 和 JavaScript，无需安装依赖。设计参考 Paste 官网的大留白、产品演示与清晰下载入口，使用 闪贴自己的品牌、演示界面和功能说明，不使用原厂宣传图或用户评价。

## 本地预览

在仓库根目录执行：

```sh
python3 -m http.server 4173 --bind 127.0.0.1 --directory website
```

打开 `http://127.0.0.1:4173/`。搜索和类型筛选仅操作网页内的合成演示数据，不访问系统剪贴板。

提交前可执行静态检查：

```sh
~/dev-artifacts/bin/storage-guard run --repo blinkclip --task website-check -- /bin/bash -c '
  export PYTHONDONTWRITEBYTECODE=1
  export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp"
  mkdir -p "$TMPDIR"
  set -e
  python3 scripts/check-website.py > "$ARTIFACT_TASK_DIR/out/website.log"
  node --check website/i18n.js
  node --check website/site.js
  node scripts/test-website-i18n.cjs > "$ARTIFACT_TASK_DIR/out/i18n.log"
'
```

## GitHub Pages

部署工作流为 `.github/workflows/pages.yml`，只上传 `website/`。首次启用时，在仓库 **Settings → Pages → Build and deployment → Source** 中选择 **GitHub Actions**。

Pages 已启用（仓库变量 `BLINKCLIP_PAGES_ENABLED=true`，Source 为 GitHub Actions），main 上 `website/**` 变更或手动 Deploy BlinkClip website 都会部署到 https://aexachao.github.io/BlinkClip/。安装包仅在显式手动 publish=true 时发布。

下载版本由已成功发布的正式 Release 驱动。部署时工作流用 `scripts/sync-release-downloads.py` 把 `website/index.html` 的两处下载按钮、`data-release-version`、页脚正式安装包链接与 `hero.release` / `download.meta` / `download.mac` 三个字典项对齐最新正式版（当前 1.0.33）；真正的 Release 404 进入 `--unreleased` 未发布状态，其他 API 错误仍失败。官网配图只允许使用 `scripts/check-website.py` 白名单里的 `website/assets/` 素材；替换素材前确保不含用户历史或其他隐私。

## 页面结构（2026-11-18 精简版）

首屏加六段正文，再落到一个下载段；1440×900 下总高约 5611px（≈6.2 屏），目标上限 6500px。可见文案约 1398 字符（其中 924 个汉字），中文用途上限 1400 字符。

1. **首屏**：一行大标题 + 一句副标题（≤40 汉字 / ≤90 字符英文）+ 一行元信息（`macOS 14+ · Universal · 本地优先 · 无需账号`）+ 主按钮「免费下载 Mac 版」与次按钮「查看功能」+ 整幅产品图。
2. `#capture` **截图与标注**：真实框选覆盖层 + 标注工具栏，配 3 条要点。
3. `#history` **剪贴板历史**：3 条要点 + 通栏面板截图。
4. `#integrations` **AI 与同步**：两栏图标加短说明，不用大图。
5. `#shortcuts` **快捷键**：一行四个键位，不做表格、不做卡片。
6. `#permissions` **权限与隐私**：两栏（需要哪些权限 / 数据在哪）+ 权限设置截图。
7. `#faq` **常见问题**：4 条手风琴，编辑排版。
8. `#cta` **下载**：一句标题 + 一个按钮 + 一行小字（Universal / Developer ID 与公证 / 版本）。
9. **页脚**：品牌、许可、正式安装包链接、第三方致谢、GitHub。版本行只出现在页脚，不再占据首屏。

已删除：倾斜与旋转的截图、各段 `clip-path` 分段边缘、暖色（粉/紫/薰衣草）大面积 wash、填充式数字段（0 / 1 / 5 / 14+）、独立的隐私段与权限段（合并为一段两栏）。

## 视觉规范（2026-11-18）

- 配色：暖近白 `#fafaf8` 页底、`#f2f0eb` 次级面、墨色 `#191917` 正文与下载段、钴蓝 `#3d5cff` 强调；不使用纯白 `#ffffff`，不使用靛紫 `#6366f1`，不再保留橙色强调。
- 字体：`Plus Jakarta Sans`（标题）+ `Outfit`（正文），均带系统中文字体回退。
- 首屏单列居中：标题 `clamp(2.6rem, 5.2vw, 4.6rem)` 且不超过 2 行；副标题、元信息、按钮依次居中；产品图在下方整幅展开，宽 `min(1180px, 100%)`。
- 产品图统一外框：`1px` 描边 `rgba(25,25,23,.10)`、`border-radius: 14px`、投影 `0 24px 60px rgba(25,25,23,.10)`，全部不旋转、不加 caption。2x 素材按 1:1 显式展示（覆盖层 ≤750px、工具栏 ≤1120px、设置页 ≤540px），首屏面板按设计稿 1180px 宽。
- 节奏：段落纵向留白 `clamp(64px, 7.5vw, 112px)`，每段只有一个视觉重点；`main` 内不再使用负 margin 互锁或斜切过渡。
- 动效：只保留首屏入场（GSAP，标题逐行 + 其余元素淡入）；`prefers-reduced-motion: reduce` 下脚本直接返回、CSS 关闭过渡，内容全部可见；GSAP 加载失败时页面静态可读。
- 响应式：1440 / 1024 / 768 / 390 / 320 无横向滚动，首屏高度等于视口高度（`heroBottom == innerHeight`），390 下按钮 ≥44pt，窄屏导航只保留四个图标入口。

## 官网语言

- 支持简体中文和 English，文案位于 `website/i18n.js`，不依赖翻译服务或额外框架。
- 首次访问按浏览器提供的系统首选语言列表选择：`zh-*` 使用简体中文，`en-*` 使用英文；列表中没有支持的语言时回退到英文。
- 右上角语言图标提供“跟随系统 / 简体中文 / English”。手动选择保存在本站 `localStorage` 的 `blinkclip.website.language`；恢复“跟随系统”时清除此覆盖。浏览器禁用存储时，当前访问仍可切换。
- 切换会更新正文、FAQ、页面标题和描述、图片替代文字、无障碍标签及 `html.lang`，并保留当前 FAQ 展开状态。
- 真实软件截图仍为中文界面的合成数据截图，英文图片替代文字明确标注，不伪造应用的英文界面。
- 无 JavaScript 时保留静态中文内容。新增语言时同步补充字典、菜单选项和语言匹配规则；24 项脚本检查验证首选语言、存储失败、切换恢复、字典完整性、FAQ 数量与文案长度预算。
- GitHub Pages 工作流在部署前运行脚本语法、静态资源和 i18n 检查；这些检查不触发应用构建或安装包发布。

## 设计技能

使用本机 `design-taste-frontend` 与 `impeccable` 的简化、配色和收尾规范。本轮属于现有官网的结构精简，保留品牌、导航、下载地址与真实功能文案。技能来源：[Taste Skill](https://github.com/Leonxlnx/taste-skill)、[Impeccable](https://github.com/pbakaus/impeccable)。GitHub Pages 工作流参考 [GitHub 官方文档](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages)。

## 2026-11-11 品牌接入

页面主品牌为闪贴 / BlinkClip，favicon、OG 与页面图标统一引用 `assets/blinkclip-icon.png`；SVG源证据见 `branding/BlinkClipAssets/ExistingBrandSource/BlinkClipIcon.origin.svg`。GitHub / Pages / Release 地址及 `blinkclip.website.language` 保持兼容。

## 部署与验证

Pages 已启用（仓库变量 `BLINKCLIP_PAGES_ENABLED=true`），main 上 `website/**` 变更会触发 `Deploy BlinkClip website`：先跑 `scripts/sync-release-downloads.py` 把下载按钮与版本对齐最新的正式 Release，再跑静态检查与 i18n 测试，最后上传 `website/` 并部署到 https://aexachao.github.io/BlinkClip/。

回归证据保存在 `evidence/website/shots/`：`after-*.png` 为改版后三档视口截图，`compare-before-after-*.png` 为改版前后上下拼接对比图，`after-audit.json` / `before-audit.json` 记录首屏高度、页面总高、横向溢出与可见字数。测量脚本为 `evidence/website/tools/audit.cjs` 与 `evidence/website/tools/checks.cjs`（需要 `--remote-debugging-port=9222` 的 Chrome）。
