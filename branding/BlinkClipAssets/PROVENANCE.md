# BlinkClip 自制功能素材与现有品牌证据

日期：2026-11-11。此文件保留此前获授权 worker 的独立几何源稿与旧选定图标溯源事实。几何插图已在 20:28 本机品牌包接入并安装；本轮生成的新主图标、A1 / A5 替代图及其实际来源改见 `../BlinkClipGeneratedAssets/PROVENANCE.md`。A2 小尺寸类别模板与几何失图回退继续使用。旧图标记录不是新生成图标的制作证明。

## 独立新绘 A1 / A2 / A5

`BlinkClipAssetRenderer.swift` 是唯一造型源稿，纯 AppKit 基本几何、路径和自定颜色；没有读取、描摹、变色、嵌入原 Paste 设置插图、Stack PNG、其他 App 拼图，也未下载第三方 SVG、Logo、SF Symbols 或字形作为图形。输入仅为功能含义、当前 UI 显示尺寸及已选 BlinkClip 的蓝色品牌方向。主图标没有重新设计。

| 项 | API / 造型 | 逻辑画布 | 导出像素 |
| --- | --- | --- | --- |
| A1 四态 | `settings(directPaste:dark:)`；卡片进入窗口 / 卡片存入剪贴板 × light/dark | 192×128pt；现消费者可按比例显示96×64pt | 每态192×128、384×256 |
| A2 四类 | `category(_:)`；file折角文档、link双环、text四行、unknown三点卡片 | 20×20pt；`isTemplate=true` | 每类20×20、40×40，共8PNG |
| A5 两态 | `permission(dark:)`；三个通用应用窗口与内容卡片、传递箭头 | 240×144pt | 每态240×144、480×288 |

外部留透明边界；light/dark采用不同窗口、边框、正文对比度；蓝色 `#0E65F6`，青色辅助强调。类别图为单色模板，PNG导出黑色，运行时由宿主按深浅界面着色。窗口无真实App标志。绘制函数只返回NSImage，不访问资源bundle、用户数据或网络。调用方应按使用点缓存，并以应用本地化文案提供具体辅助描述。

本目录中新绘几何和代码是为本项目独立创作，可按项目现有MIT约定使用；此记录不重授原提取素材或第三方依赖的版权，也不构成商标可用性、独占权、法律无风险或商店审核保证。

## 此前选定主图标：历史画面与来源边界

此前产品PNG `replica/Assets/BlinkClipIcon.png` SHA256为 `8eadc9563d0d9e2a71cbbbba5975ca3127ce416f8083e2c6cae63badfbf19b22`，网站PNG逐字节相同。ICNS SHA256为 `07c45c5cb11c1f29a33ad2e217be9007bf6db537ef66c27c34d9752f7abbc71e`。

`ExistingBrandSource/BlinkClipIcon.origin.svg` 是从**本次已有** `build/blinkclip-icon/blinkclip-icon.svg` 原样复制的选定源证据：蓝底、四角取景框、折角白卡、橙色槽。对应既有 `AppIcon.appiconset/icon_512x512@2x.png` 与 `BlinkClipAppIcon.icns` 分别和此前产品PNG / ICNS的SHA完全一致。未修改或删除该历史build目录；其归档/清理由原负责任务处理。

早先外置 `icon-source-archive-20261110-172237/out/original-icon-work/blinkclip-icon/` 确有源稿/spec/分层包，但内容为paperclip+sparkle方案，SHA与现产品不同，**不能用该历史spec或package-verification的ok为当前选定图标作完整来源或验收证明**。现选定SVG的早期生成/选择对话、创作工具及完整制作过程仍未纳入本目录；本次仅能确认已有源文件与现画面对应，不能补写不存在的权利链。

依据app-icon-gen的source-requirements/verification路线，当前仅作已有来源转换核验，不新建完整.icon或替换画面：`VerifyBrand.mjs`重渲染源SVG、生成overlay/diff并与当前PNG比较；`VerifyMenuBar.swift`编译实际`ReplicaBrand.swift`只读副本，检查18pt、template及可访问名称，并渲染浅/深色1x/2x观察表。菜单栏使用相同取景框+折角卡片语汇，省略主图颜色；该时源码注释误拼，后来已修正为 BlinkClip。关于窗/权限取`NSApp.applicationIconImage`的实际安装表现及所有线上入口，不由本源稿验证冒充完成。

## 自验与证据

所有导出/编译经storage-guard运行。仅下列受管目录保留PNG与JSON；没有在仓库写PNG、ICNS、缓存或截图。本任务没有创建模拟器或AVD，storage-guard成功后已删除自身build。

- `~/dev-artifacts/blinkclip/blinkclip-owned-assets-7016-20261111-184812/out/`：20个产品候选PNG、review-sheet、现主图64px透明边界表、asset-validation.json；Swift编译与导出成功。亲自检查light/dark和类别1x/2x，主图64px边界四角透明；图形无残留文字/第三方Logo。sheet上的黑白类别是着色预览，不是另外8个产品源图。
- `~/dev-artifacts/blinkclip/blinkclip-brand-source-verify-7416-20261111-184943/out/`：主SVG重渲染、菜单栏实际源码浅深预览，18pt/template/name断言通过；ICNS解码PNG与源PNG文件编码不同，不能仅凭其SHA作画面差异判断。
- `~/dev-artifacts/blinkclip/blinkclip-brand-pixel-verify-7770-20261111-185035/out/`：可见像素比较与overlay/diff。ICNS内1024图与产品PNG预乘RGBA逐像素相同（差异0）；SVG重渲染均值差0.1987/255、最大39/255，有抗锯齿与渐变细微差异，亲自检查overlay与10倍diff后未见位置/轮廓偏移，仍记录为近似渲染，不冒充逐像素相同。

运行入口：在仓库根目录由storage-guard执行`swiftc -module-cache-path "$ARTIFACT_TASK_DIR/build/module-cache" branding/BlinkClipAssets/BlinkClipAssetRenderer.swift branding/BlinkClipAssets/ExportAssets.swift -o "$ARTIFACT_TASK_DIR/build/export-assets"`，再传`"$ARTIFACT_TASK_DIR/out" "$PWD"`运行。不可直接把缓存写到仓库。`VerifyBrand.mjs`使用已安装app-icon-gen skill中的resvg/pngjs，绝不安装依赖进仓库；其绝对模块路径是本机验证入口，不是产品运行依赖。

历史自验边界：此源稿任务当时未执行应用资源接入 / 完整包清单；后来几何版已完成源码接入、本机包排除旧资源与安装核对。当前 A1 / A5 和主图标再替换为新生成素材，验收见 `../BlinkClipGeneratedAssets/PROVENANCE.md` 及项目 TESTING。来源权利与 Mac App Store 审查仍未完成，不由源稿或打包通过代替。

收尾体积：首组280K，品牌源码核验72K，像素核验548K，合计约900K；Data可用205GiB。共27个PNG输出（包括复核重复主图与证据图），低于30张；三个受管build均已由storage-guard清除，未创建或登记设备。
