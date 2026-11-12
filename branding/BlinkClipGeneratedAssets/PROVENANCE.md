# 闪贴 / BlinkClip 新生成素材

2026-11-11。用户明确要求生成并替换素材，并确认允许使用当前内置图像模型。本轮使用 `image_gen.imagegen`，工具没有暴露或允许选择模型 ID，**不声称使用了 gpt-image-2.5**。提示词组见 `prompts.json`，完整执行提示词保留于本次对话的工具调用；文件映射与 SHA256 见 `asset-manifest.json`。

## 来源与制作

- `sources/icon.origin.png`：从纯文字简报新生成的主图标概念；蓝色取景框、白色折角卡片、橙色轻闪，未向模型提供旧图标或上游 Paste 素材。
- `sources/icon-foreground.origin.png`：仅引用本轮新概念，由同一内置工具移除背景。五个语义部件用 app-icon-gen 的 `prepare-foreground-layer` 分区最大连通组件清理离散边缘噪点；不描摹或嵌入旧资源。
- `Icon/`：app-icon-gen `author-icon` 制作的六层 source-package：自写蓝色渐变 SVG + 四个取景角 PNG + 卡片/闪光 PNG。保留生成位图细节，**不是全矢量，也不交付或声称分层 Icon Composer 包**。`Icon/tmp/work/spec.json` 使用相对图层路径，可复用生成；目标平台元数据为 macOS。
- `sources/direct-paste.origin.png`、`copy-to-clipboard.origin.png`、`permissions.origin.png`：三个独立纯文字新生成的透明插图，无真实应用 Logo、文字、锁或上游图像输入。RGBA 缩放得到 `Resources/` 的两张 384×256 和一张 480×288 PNG；同一透明图已分别在浅深背景上检查，无须制造另一个深色造型。
- 20pt 类别模板仍由已有独立几何代码绘制；不把小尺寸类别图强行换成模糊生成位图。

传统 macOS ICNS 适配采用 `Icon/icon.preview.png`，缩至 896×896 后置于 1024×1024 的64px透明外边距中，保持原安装图标的画布占比；导出16/32/128/256/512及各2x位图，经 `iconutil` 打包。ICNS1024图回读与主PNG逐像素相等。网站使用同一主PNG。

## 验证与范围

受管证据：`~/dev-artifacts/blinkclip/generated-brand-assets-32017-20261111-205455/out/`，包括 app-icon-gen 验证报告、主图32/64/128px对照、插图浅深对照及打包验证。`author-icon` / `verify` 已通过，warnings为空；实际查看了完整主图、128/64/32px以及插图浅深背景。源PNG真实alpha，没有棋盘背景。所有原生编译、图像转换、ICNS与证据均在此受管任务目录；仓库只保存产品源与可复用资产。

新来源记录描述实际制作过程，不承诺独占权、商标可用性、法律零风险或商店必过。旧研究文件、旧版权与兼容标识由项目原NOTICE继续如实保留，不改写为本轮原创。实际安装验收由主控独立记录。

## 本轮产品接入自验

新图已接入实际 `BlinkClipAssetRenderer`：首次从 Core bundle 解码并缓存，设置图维持192×128pt、权限图240×144pt；原几何fallback与20pt类别图逐字保留。主启动图替换实际 `replica/Assets/BlinkClipAppIcon.icns`、`BlinkClipIcon.png` 与网站同PNG。Core `GeneratedIllustrations/` 的三文件通过打包精确白名单，缺失、重复、损坏和重新混入旧图均拒绝。

受管原生资源验证：`~/dev-artifacts/blinkclip/generated-resources-native-34365-20261111-210858/out/`，fr/ja/zh-Hans/zh-Hant各394、en422，总1998项；白名单/资源字节/原几何fallback保留等29项通过。实际NSImage bitmap类型、logical size、缓存身份、PNG尺寸/alpha均验；实际绘制native-sizes也已视检。该自验不是最终安装、实体按键、真实权限变化或法律审查。旧研究材料仍未被改写或删除。
