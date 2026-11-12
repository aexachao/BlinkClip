# 闪贴 / BlinkClip 开发说明

当前源码应用名称：**闪贴 / BlinkClip**，Bundle ID `com.chrisli.blinkclip`。全部快捷键统一在「设置 → 快捷键」的应用唤起、分组切换、粘贴操作和截图卡片中；「截图」页管理截图后行为和翻译。完整应用与交互的最新验收状态见 [变更日志](../CHANGELOG.md) 与 [TESTING](TESTING.md)。

## 品牌与标识

| 项 | 当前值 |
| --- | --- |
| 产品名 | 闪贴 / BlinkClip |
| Bundle ID | `com.chrisli.blinkclip`（Helper：`com.chrisli.blinkclip.helper`） |
| 主应用 / 可执行文件 | `BlinkClip.app` / `BlinkClip` |
| 登录项 Helper | `BlinkClip Helper.app` / `BlinkClipHelper` |
| MCP 服务 | `blinkclip-mcp` |
| 测试可执行文件 | `blinkclip-core-tests` |
| SwiftPM Package / 模块 | `BlinkClip`；`BlinkClipCore`、`BlinkClipObjC`、`BlinkClipCapture`、`BlinkClipMCP`、`BlinkClipHelper`；测试 `BlinkClipCoreTests`，源码目录 `Sources/BlinkClip*` |
| 核心资源 | `BlinkClip_BlinkClipCore.bundle`（自写中英表与 3 张生成插图） |
| 环境变量 | `BLINKCLIP_*`，兼容 `BLINKCLIP_*`，两者并存时新名优先 |

主 App target / 模块暂保留 `BlinkClip` 与 AppIntent 类型，作为兼容桥，不代表旧快捷指令迁移已经通过。数据目录、归档格式与 CloudKit 标识见下文。

## 数据与同步

最新源码使用 `~/Library/Application Support/BlinkClip/clipboard.sqlite`（Core Data / SQLite）。首次启动迁移旧 `clipboard.json`，成功保存后以数据库为准，原 JSON 保留不覆盖；升级前应退出仍写 JSON 的旧版应用和工具。数据目录权限 0700、数据库文件 0600；图片、RTF、HTML、文件 URL 等保留原始 representation，数据为本地明文。

### iCloud Drive 文件同步

当前首选文件同步，**设置 → 通用**只提供**iCloud 同步**开关及简短状态，没有设置弹窗。两台 Mac 均需使用含此功能的构建、登录同一 Apple ID 并打开开关；自动使用 `iCloud Drive/BlinkClip`，同步文件夹为 `BlinkClipSync-v1`，格式标记为 `blinkclip-icloud-drive`。已有自定义同步目录配置继续保留。开启时合并历史和分组，后续每 30 秒尝试同步；关闭后保留本地与云目录内容。

同步包含已保存的项目内容、原始格式、图片、来源应用信息及分组名称、颜色、顺序和成员关系。快捷键、权限、来源排除、暂停、保留期限和 Stack 队列不在设备之间同步。文件路径会保留，但对应的原始文件不会被自动复制。不要把不同保留期限视为独立删除策略：某台设备实际清理的内容也会通过删除标记传播。

每台设备维护自己的同步文档，使用确定性的版本顺序合并同一记录；同一条记录同时修改时采用版本较新的整条记录，不按字段合并。永久删除有持久标记，缺失文件不当作删除，避免离线设备或尚未下载的文档使内容丢失。大图片会增加本地处理、传输和 iCloud 存储开销。

详见[同步说明与验证范围](../docs/ICLOUD_SYNC.md)。专项隔离测试脚本为 `replica/scripts/test-icloud-sync.sh`；只有显式添加 `--live-icloud` 才会向真实 iCloud Drive 写入独立合成测试文件。测试和演示数据目录不会启动应用自动同步。

另有面向已签名构建的 CloudKit 高级选项：需要自有签名与容器配置，真实 CloudKit 云端传输尚未完成验证，不能称已完成同步。详见 [CloudKit 迁移与测试](../docs/CLOUDKIT_MIGRATION.md)。

## 构建运行

支持 macOS 14+ 的 Intel（x86_64）和 Apple 芯片（arm64）Mac。需要 Swift 工具链和 Python 3；为使用 macOS 26 的原生控件外观，构建时使用 Xcode 26 或更新版本。以下命令从仓库根目录执行。

默认构建 Universal 应用，产物为 `out/BlinkClip.app`：

```sh
bash replica/scripts/build-app.sh release universal
```

将末行改为 `bash replica/scripts/build-app.sh debug native` 可只构建当前 Mac。正式打包运行 `npm run build:dmg`，完整命令见[根目录构建说明](../README.md#从源码构建)。稳定版本需要项目外的更新签名私钥，此命令不会发布。

本仓库尚无正式安装包；未来发布附件使用 `BlinkClip-<版本号>-macos-universal.dmg`，下载同步只接受本仓库实际发布并验证完整的附件。未指定签名身份时构建采用临时签名；当前本机验收使用稳定开发签名，尚未经过 Apple 公证；包签名不保证 macOS 辅助功能授权连续，更新后仍可能需要重新开启。构建、签名、安装和功能验收分别记录。

菜单栏使用单色取景框与折角卡片标志，点击打开历史。默认全局快捷键为 ⇧⌘V（打开面板），Stack 为 ⇧⌘C，区域截图为 ⇧⌘A，全屏截图为 ⌘⇧E。所有快捷键集中在「设置 → 快捷键」四组卡片；六个录制器右侧均有 ×，清空显示“未设置”，截图槽真正注销对应快捷键，重启后不自动恢复；菜单截图入口保留。旧配置未设 enabled 标志时默认启用，保留既有组合值。每个选项仅非默认时在快捷键左侧显示“恢复默认”；单项或确认后的“恢复全部快捷键…”都会重新启用对应默认截图绑定。取消录制保留原值。新旧应用名或用户改名不影响 Helper 按包含应用的 Bundle ID 定位。真实 Carbon 全局事件、SMAppService 注册及安装升级不由模型或路径测试替代。

复制 / 截图成功音使用 macOS 自带 Purr，通过 `NSSound(named:)` 运行时加载，不复制系统音频；没有时间节流，连续不同操作均保留反馈。真实听感仍待确认。新启动图标、直接粘贴 / 复制到剪贴板 / 权限图来自内置图像工具，提示词和源图见 `branding/BlinkClipGeneratedAssets/`；模型 ID 未公开，20pt 类别模板继续使用独立代码绘制。

## MCP

将构建后的可执行路径用于 MCP 客户端；应用设置中的“MCP 与 AI 工具”页面可复制当前路径的配置。

```json
{
  "mcpServers": {
    "blinkclip": {
      "command": "/绝对路径/BlinkClip.app/Contents/MacOS/blinkclip-mcp",
      "args": ["--data-dir", "/绝对路径/独立数据目录"]
    }
  }
}
```

支持 `search`、`read_item`、`create_item`、`update_item`、`delete_item`、`list_pinboards`、`create_pinboard`、`rename_pinboard`、`delete_pinboard`、`add_item_to_pinboard`、`remove_item_from_pinboard`。`create_item(list_id)` 建立仅分组项目且不修改系统剪贴板，删除需要先查看确认预览。传输使用本地 stdio JSON-RPC。

## 验证与差异

完整 Core suite 在旧 / 新工程均因 SQLite `RAISE ABORT` 触发 CoreData fatal（exit 133），未通过，不能以定向测试代替全组结果。MCP 定向 fixture 自验 13/13 的结果仅覆盖其边界，不代表整个 Core suite 通过；最新证据见 [TESTING](TESTING.md)。

当前没有实现 iCloud 账号 / 订阅服务，也未验证所有菜单、拖放目标和系统权限组合。跨应用直接粘贴、CloudKit 真实同步、录屏入口与多显示器长截图仍需独立验收；不能标记为全功能或逐像素一比一通过。核心测试使用独立原生可执行 runner，不依赖 XCTest，仍执行真实持久化、AppKit 具名剪贴板和多个操作系统进程。详细覆盖见 [TESTING.md](TESTING.md)。

统一快捷键的生产模型 / 会话回归与实际页面验收分别记账。`validate.sh` / `regress-local.sh` 的默认路径及迁移前置条件不作为本轮受管验收示例；运行前必须按各组脚本实际支持的参数配置外部 scratch、应用和证据目录。专项验证只代表其实际覆盖的行为，不表示全量迁移或全部 UI 通过。
