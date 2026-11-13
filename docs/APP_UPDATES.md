# 应用内更新

1.0.6 起入口位于“关于闪贴”。检查更新读取 GitHub 最新正式 Release，确认后使用 Sparkle 2.10.1 的原生界面下载、安装和重启。更新包使用完整 Universal DMG，兼容 Intel 和 Apple 芯片。

已发布的 1.0.5 及更早版本没有此功能，需要先手动安装 1.0.6。应用内更新代码、打包和签名测试与真实线上版本升级验收分别记录。

## 更新源与签名

- 更新源地址固定为 `https://github.com/aexachao/BlinkClip/releases/latest/download/appcast.xml`，跟随最新正式 Release，预发布不会改变此地址的目标。
- 发布时使用 Sparkle 官方 `sign_update`，对 DMG 和 appcast 分别进行 Ed25519 签名。公钥固定在 `replica/Assets/UpdatePublicKey.txt`，写入应用的 `SUPublicEDKey`。
- `SURequireSignedFeed` 和 `SUVerifyUpdateBeforeExtraction` 开启，更新源及安装包验证成功后才能解包和安装。发布脚本也会使用嵌入公钥验证归档签名，阻止错误私钥发布。
- 私钥通过 `BLINKCLIP_UPDATE_PRIVATE_KEY` Actions Secret 提供，是 Base64 编码的 32 字节 Ed25519 seed。签名工具从标准输入接收私钥，私钥不放入命令行、应用或仓库。
- Sparkle 二进制框架及签名工具固定版本和 SHA-256。框架中的符号链接、更新辅助程序及原始许可随应用打包。

应用启动时不会自动安装更新。打开“关于闪贴”会异步读取版本摘要，六小时内复用结果。用户点击“下载并安装”后由 Sparkle 显示更新过程。安装前的正常退出会经过已有 `applicationShouldTerminate` 数据保存逻辑，保存失败时取消退出。

## 发布

正式发布需要配置与嵌入公钥匹配的更新签名 Secret。main 或版本标签推送只做契约检查；配置私钥后，手动运行工作流并选择 publish=true 才会发布。本地公证安装包与 GitHub 发布、更新源生成分别验收，不能在缺少私钥时生成替代公钥或假签名。

正式版 Actions 在原有 Universal DMG、SHA256SUMS.txt 和 release-manifest.json 之外上传 appcast.xml。所有附件上传后下载核对，再公开 Release。缺失私钥或私钥与嵌入公钥不匹配时，正式版构建失败，阻止发布不可信更新源。

本地验证签名时，从项目外的安全存储将私钥传入进程环境，不在终端输出私钥。可以通过 `create-update-feed.py --archive <DMG路径> --version <正式版本>` 生成更新源。更新密钥必须持久备份，重新生成公钥会导致已经安装的客户端无法信任后续更新，轮换需遵循 Sparkle 的密钥迁移流程。

### Developer ID 签名与 Apple 公证

站外分发使用 `Developer ID Application` 证书及其配对私钥；`Apple Development`、`Apple Distribution` 与临时签名均不能替代它。证书放登录钥匙串，不在仓库保存私钥。公证凭据先在本机终端交互式存入钥匙串（密码不放命令行或聊天）：

```bash
xcrun notarytool store-credentials BlinkClip-notary \
  --apple-id '<Apple 开发者账号>' --team-id 4NJM425J3B
```

按提示输入 Apple 账号的 App 专用密码。已配置其他 profile 时，直接使用其名称。正式构建通过 storage-guard 启动：

```bash
BLINKCLIP_SIGNING_IDENTITY='Developer ID Application: Chao Li (4NJM425J3B)' \
BLINKCLIP_NOTARY_PROFILE='BlinkClip-notary' \
~/dev-artifacts/bin/storage-guard run --repo BlinkClip --task notarized-release \
  --kind release --release-id com.chrisli.blinkclip@1.0.10+1.0.10 -- \
  bash replica/scripts/build-notarized.sh
```

脚本先验证证书与公证 profile，再构建 Universal 应用。从嵌套 Mach-O、Sparkle 辅助程序及 XPC 服务到主应用依次签名，开启 Hardened Runtime 和可信时间戳，保留现有必要 entitlements 并移除调试授权。随后提交应用 ZIP、装订应用票据，创建并签署 DMG，再提交 DMG 公证并装订票据。每步以 Apple 的 `Accepted`、`stapler validate`、Gatekeeper 与镜像内容核验为准；不会启动应用或发布到 GitHub。

最终安装包、SHA-256、`signing-manifest.json` 和 Apple 返回的公证日志位于任务的 `out/release/`。等待超时会在 `evidence` 保留原始上传 ZIP 与提交 ID；续查时新建 storage-guard 发布任务，将旧任务的 `out/` 完整复制到新任务 `out/`，保留原签名及时间戳，直接运行 `python3 replica/scripts/notarize-distribution.py --profile BlinkClip-notary`（仍需设置签名身份，以便尚未生成的 DMG 签名）。不要重新构建或换签后复用旧提交。只可对同一归档继续等待，禁止将其他字节套用旧结果。`signing-manifest.json` 与原发布工作流的 `release-manifest.json` 分开，不能直接作为 `release-ci.py publish` 的输入。

若提供 `BLINKCLIP_UPDATE_PRIVATE_KEY`，最后才对已装订的最终 DMG 和 appcast 做 Sparkle 签名；未提供时交付公证安装包，不生成应用内更新源。Apple 公证与 Sparkle Ed25519 签名是两套凭据，不能互相替代。

## 辅助功能授权

更新包的 Ed25519 签名用于证明下载来源。macOS 通过应用的代码签名身份判断辅助功能权限归属。历史临时签名更新实测需要重新授权；2026-11-13 本机已完成 1.0.10 Universal 应用的 Developer ID 签名，主应用及嵌套代码的团队、Hardened Runtime 和可信时间戳检查通过。应用与最终 DMG 均获得 Apple 公证 `Accepted`（无警告或问题），已装订并验证票据，Gatekeeper 均通过。尚未证明真实跨版本更新后授权连续；授权连续性需保持相容的 Developer ID 签名身份和 Bundle ID，并经过真实跨版本更新验证。

### 为什么重建后可能还要再授权一次

TCC 不记录“哪个路径被勾选”，而是记录被勾选那一刻那个构建的 **designated requirement**。两种构建写进 TCC 的要求完全不同：

| 构建方式 | `codesign -d -r-` 的 designated requirement | 重建后是否仍然匹配 |
| --- | --- | --- |
| Developer ID（`sign-app.py`，`--options runtime --timestamp`） | `identifier "com.chrisli.blinkclip" and anchor apple generic and certificate … and certificate leaf[subject.OU] = "4NJM425J3B"` | 是。只绑定 Bundle ID + 团队，与 cdhash 无关 |
| 临时签名 `codesign --sign -`（`build-app.sh` 未设置 `BLINKCLIP_SIGNING_IDENTITY` 时的回退） | `cdhash H"…" or cdhash H"…"` | 否。每次构建二进制的 cdhash 都变，要求随之失效 |
| `Apple Development` / `Apple Distribution` | 绑定该证书与团队 | 否。证书与 Developer ID 的团队身份不同，TCC 里新旧要求对不上 |

本机 2026-11-13 的实例就是这样：`/Applications/BlinkClip.app` 已是 Developer ID 签名（Team `4NJM425J3B`），但 TCC 里那条授权存的仍是旧临时签名构建的两个 cdhash，系统设置里的勾选一直保留，API 却一直返回 false，`log show` 里每次检查都打印：

```
tccd  Failed to match existing code requirement for subject com.chrisli.blinkclip and service kTCCServiceAccessibility
      cdhash H"811ea047…" or cdhash H"59fde0e4…"                                     ← TCC 里存的要求（旧临时签名）
      identifier "com.chrisli.blinkclip" and anchor apple generic and … OU="4NJM425J3B"  ← 当前二进制的要求（Developer ID）
```

### 一次性修好，之后不再需要重新授权

1. 只做一次目录清理：系统设置 → 隐私与安全性 → 辅助功能（跨应用发送事件、屏幕录制同理），选中闪贴/BlinkClip 点“−”移除；或执行 `tccutil reset Accessibility com.chrisli.blinkclip`（同时会清掉该 Bundle ID 的上述三条授权记录）。
2. 用当前 Developer ID 构建的 `/Applications/BlinkClip.app` 重新点“+”，勾选新增的条目。设置窗口的“系统权限”分区检测到“已勾选但仍被拒绝”时会直接给出这两步。
3. 以后每次构建都带上 Developer ID 身份，保持同一个 Bundle ID 与同一个 Team 证书：

```bash
BLINKCLIP_SIGNING_IDENTITY='Developer ID Application: Chao Li (4NJM425J3B)' \
  bash replica/scripts/build-app.sh release universal
```

不要用临时签名或 Apple Development 构建覆盖安装正式版：那样 TCC 里的要求又被换成 cdhash，下一次勾选白做。`build-app.sh` 在没有 Developer ID 身份时会打印提示，说明这次构建的授权不会随重建保留；签名脚本的安全语义（必须真实身份、Hardened Runtime、可信时间戳、逐层签名）不变。

比较自维护时，可用 `codesign -d -r- /Applications/BlinkClip.app` 确认仍是 `identifier … OU = "4NJM425J3B"` 形式，而不是 `cdhash H"…"`。


参考 [Sparkle 更新发布文档](https://sparkle-project.org/documentation/publishing/) 和 [Apple 代码签名身份说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

## 本机实测

2026-11-04 的隔离应用实测完成了 Sparkle 下载、安装及重启。更新前系统授权返回 true，更新后的新进程返回 false，当前临时签名构建未通过“更新后无需重新授权”验收。详情见 [测试记录](../reports/replica/in-app-update-accessibility-test-2026-11-04.md)。
