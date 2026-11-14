# CloudKit 配置与验收

闪贴使用自有 `iCloud.com.chrisli.blinkclip` 容器，团队 `4NJM425J3B`，显式 App ID `com.chrisli.blinkclip`。Developer ID 分发，不走 Mac App Store，不启用 App Sandbox。

## 当前状态（2026-11-14）

- App ID 的 iCloud / CloudKit 能力及容器关联已在 Apple 后台完成。
- 已签发 `BlinkClip CloudKit Development 20261114` 和 `BlinkClip CloudKit Developer ID 20261114` 两份描述文件。开发版匹配 Apple Development 证书；分发版匹配现用 Developer ID Application 证书，并授权 Production。
- 开发环境真实服务验证通过：同一 Mac 的两个隔离客户端完成新增、附件字节回验、修改、并发标题冲突、停止客户端后重启补传、内容及分组删除。六类记录及全部声明字段已通过真实写入验证。
- Production 再次验证了从磁盘重新打开 Store 后的附件字节。多 Store 测试中仍出现 Core Data 的模型重名与临时外部数据引用日志，保留原始日志；本轮的内存和磁盘重开字节断言均通过，不宣称已消除这些系统日志。
- 合成记录只写入随机 `BlinkClip-Verification-*` zone，完成后删除 zone 与订阅；首次崩溃遗留区域也已按名称单独清理。未开启或上传用户真实历史。
- 完整 schema 已部署到 Production；Developer ID + Production 探针也通过上述真实服务测试。1.0.15 Universal 本地候选应用与 DMG 均已公证 Accepted、装订票据并通过 Gatekeeper。尚未替换 `/Applications/BlinkClip.app` 或发布到 GitHub。
- 第二台物理 Mac、物理网络断开后重连、Intel 真机与 macOS 26 实机仍未测。停止客户端后补传不等于物理断网验收。

## 凭据与存储

证书及私钥留在登录钥匙串，公证使用 `BlinkClip-notary` profile。描述文件是 Apple 签发的授权允许列表，不能手工修改。不要把密码、私钥、描述文件或用户历史提交到 Git。

本机下载文件为：

- `~/Downloads/BlinkClip_CloudKit_Development_20261114.provisionprofile`
- `~/Downloads/BlinkClip_CloudKit_Developer_ID_20261114.provisionprofile`

后续使用前可安装到 `~/Library/Developer/Xcode/UserData/Provisioning Profiles/<UUID>.provisionprofile`。重新生成时需要选择当前实际签名证书；脚本会验证其指纹在 `DeveloperCertificates` 中。

所有构建、测试、公证经 `~/dev-artifacts/bin/storage-guard run` 启动；中间文件在 `$ARTIFACT_TASK_DIR/build`，安装包和原始证据在 `out`。不要把示例中的描述文件下载到仓库。

## 构建

正式候选包（需能访问 Apple 时间戳与公证服务）：

```bash
BLINKCLIP_SIGNING_IDENTITY='Developer ID Application: Chao Li (4NJM425J3B)' \
BLINKCLIP_NOTARY_PROFILE=BlinkClip-notary \
BLINKCLIP_CLOUDKIT_PROFILE="$HOME/Downloads/BlinkClip_CloudKit_Developer_ID_20261114.provisionprofile" \
BLINKCLIP_CLOUDKIT_CONTAINER=iCloud.com.chrisli.blinkclip \
BLINKCLIP_CLOUDKIT_ENVIRONMENT=Production \
~/dev-artifacts/bin/storage-guard run --repo BlinkClip --task cloudkit-release \
  --kind release --release-id com.chrisli.blinkclip@1.0.15+1.0.15 -- \
  bash replica/scripts/build-notarized.sh
```

开发构建将身份换为 `Apple Development: Chao Li (7Q4W57L7ZM)`、描述文件换为 Development、环境换为 Development，并在 storage-guard 内执行 `bash replica/scripts/build-app.sh debug native`。

`configure-cloudkit-signing.py` 校验有效期、团队、显式 App ID、容器、服务、环境和证书允许列表，随后嵌入描述文件及容器配置。Apple 实际允许 `icloud-services = "*"`，应用签名收窄为 `["CloudKit"]`；KV 的 `4NJM425J3B.*` 展开成具体 App ID，已有具体 KV 标识保留。签名不能携带字面通配符。参见 [Apple TN2415](https://developer.apple.com/library/archive/technotes/tn2415/)。

CloudKit 授权与基础 Apple Events 授权合并，重复键失败；不加入 App Sandbox，不保留 `get-task-allow`。`sign-app.py` 由内向外签名，开启 Hardened Runtime 和时间戳。最终票据和 Gatekeeper 结果以 `out/release/signing-manifest.json` 为准。

## 设置入口

“通用 → iCloud 同步”在当前进程具有有效 CloudKit 授权且使用正式数据目录时，优先调用 CloudKit 的现有确认框。取消确认不会静默改开 iCloud Drive。确认开启后关闭独立 Drive 后端；关闭同步保留本地内容与云端数据。已有 Drive 同步保持原有状态，先关闭再开启才能主动切换到 CloudKit。

未授权构建继续使用原有 Drive 路径。状态提示跟随实际启用的后端；均未启用时优先展示可用 CloudKit 的状态。不需要手工写 defaults 绕过 UI。

## 合成数据验证

离线合同：`test-cloudkit-sync.sh`（真实 CKRecord / CKAsset 编解码，内存服务端，不代表联网）；签名：`python3 replica/Tests/Native/test_cloudkit_signing.py`；界面：`test-ui-interaction.sh`。上述命令均在 storage-guard 内执行。

真实服务：设置下列环境变量后，在 storage-guard 内运行 `bash replica/scripts/test-cloudkit-live.sh --synthetic-only`：

| 变量 | Development | Production |
| --- | --- | --- |
| `BLINKCLIP_CLOUDKIT_PROFILE` | 开发描述文件路径 | Developer ID 描述文件路径 |
| `BLINKCLIP_SIGNING_IDENTITY` | Apple Development 身份 | Developer ID Application 身份 |
| `BLINKCLIP_CLOUDKIT_CONTAINER` | `iCloud.com.chrisli.blinkclip` | 同左 |
| `BLINKCLIP_CLOUDKIT_TEST_BUNDLE_ID` | `com.chrisli.blinkclip` | 同左 |
| `BLINKCLIP_CLOUDKIT_TEST_ENVIRONMENT` | `Development`（默认） | `Production`（必须显式） |

探针先验证全部 schema 字段，再以两个独立 Store 运行真实引擎；报告包含实际环境、客户端数量、物理 Mac 数、冲突/补传/删除验证与清理结果。生产环境先部署 schema，探针不能自动增加生产字段。

只有某次崩溃遗留的确切开发合成区域已核对后，才可设置 `BLINKCLIP_CLOUDKIT_CLEANUP_ZONE=<确切名称>`。脚本只接受已列出、以 `BlinkClip-Verification-` 开头且后缀为 UUID 的 Development zone；不能用它清理业务区域或其他人的数据。

## 真实服务发现并修复的问题

1. `Task {}` 继承 SDK delegate 的 task-local 上下文，错误处理中的 `cancelOperations()` 会触发 SDK 重入崩溃。改用 `Task.detached` 离开回调上下文后再取消。
2. `deleteSelf` 是子记录指向所有者：附件指向内容、元数据指向列表。旧的反向引用与 parent 关系形成删除约束冲突；已修正并以真实内容/分组删除验证。关联修改按 zone 原子提交。
3. Apple 下发的服务/KV 通配授权与手写测试夹具不同；已补真实形态测试和明确的证书匹配校验。

## 后续验收边界

- 两台已登录同一 iCloud 的物理 Mac：确认同一 Production 构建、开启后的双向变更/删除、冲突与重复项收敛。
- 物理断网与恢复：不能靠暂停客户端宣称完成。
- 账户切换、服务端限流、推送唤醒、共享协作 CKShare、全部附件冲突组合仍需专项验证；未完成的冲突保留本机修改并暂停，不能假定服务器胜出。
- GitHub 发布、Sparkle appcast 生成和安装覆盖分别验收；本地带公证票据的候选包不等于已线上发布。
- 本轮跨应用直接粘贴自动化未完成：系统事件权限为 true，但自动化期间目标焦点落到 ChatGPT，TextEdit 目标未收到文本；没有据此修改粘贴逻辑或宣布验收通过。
