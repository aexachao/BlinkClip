# CloudKit 同步启用 runbook（闪贴 / BlinkClip）

这份文档只做一件事：把 CloudKit 同步从"卡在账号侧"推进到"后台点几下就能启用"。
代码侧的接线已经就绪并验证过（见第 5 节）；剩下的是 Apple 开发者后台的账号操作，
必须由账号持有人本人完成，工具与脚本都不能代劳。

- 本文不含任何凭据、私钥、描述文件内容；所有产物都在本机 `/tmp` 或 `dist/` 下，不进仓库。
- 本文不创建真实 CloudKit 容器。
- 目标 Bundle ID：`com.chrisli.blinkclip`；Team ID：`4NJM425J3B`；
  建议容器：`iCloud.com.chrisli.blinkclip`。
- 相关背景与未完成项见 [CloudKit 迁移与测试](CLOUDKIT_MIGRATION.md)、
  [iCloud 同步说明](ICLOUD_SYNC.md)、[签名与更新](APP_UPDATES.md)。

---

## 1. 一句话结论

CloudKit 能不能用，只取决于**描述文件里是否携带 iCloud/CloudKit 授权**。
代码在没有授权时会优雅降级（不初始化 `CKContainer`、设置里显示"暂不能连接 iCloud"），
在有授权时会自动读取进程的实际授权并连接。

本机 2026-11-14 实测状态：

```sh
security find-identity -v -p codesigning
#   1) "Apple Development: Chao Li (7Q4W57L7ZM)"
#   2) "Apple Distribution: Chao Li (4NJM425J3B)"
#   3) "Developer ID Application: Chao Li (4NJM425J3B)"   3 valid identities found

ls ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/
# 10 个描述文件全部解析后无 com.apple.developer.icloud-*，即没有任何一个能授权 CloudKit。
```

也就是说：**证书齐了，缺描述文件；描述文件要等后台把 iCloud 勾上才能生成。**

---

## 2. 必须由用户在开发者后台完成的最小集合

只有下面 6 步是在后台网页上做的，做完本机就能构建出能连 CloudKit 的包。

| # | 位置 | 动作 |
| --- | --- | --- |
| 1 | Certificates, Identifiers & Profiles → **Identifiers** | 确认存在 `com.chrisli.blinkclip`（Platform: macOS）；不存在则先 Register a new Identifier → App ID（必须用显式 App ID，**不要通配符**） |
| 2 | 同上 → 该 App ID 的 **Capabilities** | 勾选 **iCloud**（CloudKit） |
| 3 | iCloud 的 **Edit** 面板 | **Create Container** → `iCloud.com.chrisli.blinkclip` → Save；记下容器名 |
| 4 | **Profiles** → + | 生成 **Development**（macOS App Development）描述文件，选同一个 App ID，选中 `Apple Development` 证书 |
| 5 | **Profiles** → + | 生成 **Developer ID** 描述文件（Distribution → Developer ID），选同一个 App ID，选中 `Developer ID Application` 证书 |
| 6 | 下载 .provisionprofile | 双击安装，或用第 4 节的验证命令确认已就位 |

若第 5 步后台**没有**提供 Developer ID 类型的描述文件（账号协议未签、或该 App ID 在该界面上
不出现 Developer ID 选项），则 CloudKit 只能用于 Development / App Store 分发路径；
本仓库当前以 Developer ID + Sparkle 分发，这种情况下 CloudKit 只能作为开发环境能力，
必须在发布说明中注明"正式分发版不含 CloudKit 同步"。

第 1–3 步做完，App ID 侧就已经能签发带 iCloud 授权的描述文件；第 4–6 步才让本机构建可用。

---

## 3. 代码侧前置（读代码确认，已逐条核对）

### 3.1 `replica/scripts/configure-cloudkit-signing.py`

参数：

| 参数 | 必填 | 含义 |
| --- | --- | --- |
| `--profile` | 是 | 已安装的 `.provisionprofile` 路径（CMS 签名文件，用 `security cms -D -i` 解出 plist） |
| `--bundle` | 是 | 构建中的 `.app`，脚本会读 `Contents/Info.plist` 的 `CFBundleIdentifier` |
| `--container` | 是 | `iCloud.*` 容器标识，必须被描述文件授权 |
| `--environment` | 否 | `Development`（默认）或 `Production`，必须被描述文件授权 |
| `--output` | 是 | 输出 entitlements plist 的路径 |

校验逻辑（任一不满足直接 `ValueError` 失败，不生成半成品）：

1. `TeamIdentifier` 必须恰好一个，且不是原版厂商团队 `4788TTJ39Y`；
2. 容器必须 `iCloud.` 开头，且不含原版厂商标记 `wiheads`；
3. `Entitlements['com.apple.application-identifier']` 必须等于 `<团队>.<BundleID>`；
4. 容器必须在 `com.apple.developer.icloud-container-identifiers` 里；
5. `com.apple.developer.icloud-services` 必须含 `CloudKit`；
6. `com.apple.developer.icloud-container-environment` 必须含所请求环境（数组或字符串均可）；
7. `ExpirationDate` 未过期。

产出与副作用（三件事同时发生，无需手工改包）：

- 写出 entitlements plist，含 `com.apple.application-identifier`、
  `com.apple.developer.team-identifier`、`com.apple.developer.icloud-container-identifiers`
  （只放这一个容器）、`com.apple.developer.icloud-services = ["CloudKit"]`、
  `com.apple.developer.icloud-container-environment`（**字符串**，App 侧按 String 读取）；
- 描述文件存在 `com.apple.developer.ubiquity-kvstore-identifier` 时**逐字**带进授权
  （Apple 下发的是 `TeamIdentifierPrefix.CFBundleIdentifier`，不要改写）；不存在则不补，
  因为签名里的授权必须是描述文件授权的子集；
- 描述文件存在 `com.apple.developer.aps-environment` / `aps-environment` 时带进授权
  （CloudKit 订阅推送需要它；没有也能用，只是退回 30 秒轮询）；
- `get-task-allow` / `com.apple.security.get-task-allow` **永不写入**：开发描述文件通常带它，
  写进发布签名等于允许调试器挂载，与 `replica/Assets/BlinkClip.entitlements` 的取舍冲突；
- 把容器名写进 App 的 `Info.plist` 键 `BlinkClipCloudKitContainerIdentifier`（App 运行时读它）；
- 把描述文件复制为 `Contents/embedded.provisionprofile`。

### 3.2 `replica/scripts/build-app.sh` 的 CloudKit 分支

触发条件：`BLINKCLIP_CLOUDKIT_PROFILE` 或 `BLINKCLIP_CLOUDKIT_CONTAINER` 任一非空。
三个变量必须齐全（`BLINKCLIP_CLOUDKIT_PROFILE`、`BLINKCLIP_CLOUDKIT_CONTAINER`、
`BLINKCLIP_SIGNING_IDENTITY`），否则 `: "${VAR:?}"` 直接中止。

- `BLINKCLIP_SIGNING_IDENTITY=-` 会被显式拒绝：ad-hoc 签名带不了描述文件授权的 iCloud 能力，
  与其运行时才失败，不如构建时就说明；
- 先用 `configure-cloudkit-signing.py` 产出 CloudKit 授权，再把它与
  `replica/Assets/BlinkClip.entitlements`（`com.apple.security.automation.apple-events`）
  合并：**重复键直接报错**（不猜），合并结果缺 `apple-events` 或缺 `icloud-services` 也报错，
  出现 `com.apple.security.app-sandbox` 也报错；
- 合并后用 `replica/scripts/sign-app.py` 逐层签名（Hardened Runtime + 时间戳），
  主程序的授权就是合并后的那份；
- 未设置这些变量时行为不变：ad-hoc 签名、设置里禁用 CloudKit。

### 3.3 `CloudKitSyncController` 的未配置降级

- 初始化时 `BlinkClipCloudKitConfiguration.current()` 读 `Info.plist` 的
  `BlinkClipCloudKitContainerIdentifier` + 进程真实授权（`SecTask`，不是自造 plist），
  缺任何一项即 `unconfigured`；
- 此时 `canSync = false`，`statusText = "此构建未配置 <品牌名> 自有 CloudKit 容器和开发者签名，暂不能连接 iCloud。"`；
- 设置 → 通用里的 "iCloud 同步" 行开关在 CloudKit 与 iCloud Drive 都不可用时才置灰，
  鼠标悬停显示 `statusText`；
- 未配置时**不会**创建 `CKContainer`、不注册远程通知、不写任何云状态，也不会影响 iCloud Drive 路径。

---

## 4. 本机验证描述文件

安装后先确认它是谁、授权了什么：

```sh
security cms -D -i "$BLINKCLIP_CLOUDKIT_PROFILE" > /tmp/profile.plist
plutil -p /tmp/profile.plist | grep -E "Name|ExpirationDate|TeamIdentifier|\
com.apple.application-identifier|icloud-container-identifiers|icloud-services|\
icloud-container-environment|ubiquity-kvstore-identifier|aps-environment|get-task-allow"
```

期望看到：`com.apple.application-identifier = 4NJM425J3B.com.chrisli.blinkclip`、
`com.apple.developer.icloud-container-identifiers` 含 `iCloud.com.chrisli.blinkclip`、
`com.apple.developer.icloud-services` 含 `CloudKit`、`com.apple.developer.icloud-container-environment`
含你要构建的环境（Development / Production）。

**签名证书必须在描述文件的 `DeveloperCertificates` 里**，否则能签但一启动就被系统拒绝。
脚本不校验这一项，自己核一遍指纹：

```sh
python3 - "$BLINKCLIP_CLOUDKIT_PROFILE" "Developer ID Application: Chao Li (4NJM425J3B)" <<'PY'
import hashlib, plistlib, re, subprocess, sys
profile = plistlib.loads(subprocess.run(['/usr/bin/security', 'cms', '-D', '-i', sys.argv[1]],
                                        capture_output=True, check=True).stdout)
identities = subprocess.run(['/usr/bin/security', 'find-identity', '-v', '-p', 'codesigning'],
                            capture_output=True, text=True).stdout
match = re.search(r'([0-9A-F]{40}) "' + re.escape(sys.argv[2]) + r'"', identities)
assert match, '找不到该签名身份'
print('身份 cert SHA-1 :', match.group(1))
print('描述文件 SHA-1 :', [hashlib.sha1(d).hexdigest().upper() for d in profile['DeveloperCertificates']])
PY
```

两个 SHA-1 必须有一个相同。示例输出取自本机一个真实 macOS 描述文件（macOS 开发描述文件
与 `Apple Development` 证书的对应关系）：

```text
身份 cert SHA-1 : A5C1C85ED2F36901A57F309CCCD31C8FFE80CF74
描述文件 SHA-1   : ['A5C1C85ED2F36901A57F309CCCD31C8FFE80CF74']
```

不匹配的处理：重新生成描述文件并在选证书那一步勾上你实际用来签名的证书
（Development 配 `Apple Development`，分发配 `Developer ID Application`），不要靠换证书去凑。

---

## 5. 构建与产物校验

```sh
# A. 开发环境（Development 描述文件 + Apple Development 身份）
BLINKCLIP_SIGNING_IDENTITY="Apple Development: Chao Li (7Q4W57L7ZM)" \
BLINKCLIP_CLOUDKIT_PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/<uuid>.provisionprofile" \
BLINKCLIP_CLOUDKIT_CONTAINER=iCloud.com.chrisli.blinkclip \
BLINKCLIP_CLOUDKIT_ENVIRONMENT=Development \
./replica/scripts/build-app.sh debug native

# B. 分发（Developer ID 描述文件 + Developer ID Application 身份）
BLINKCLIP_SIGNING_IDENTITY="Developer ID Application: Chao Li (4NJM425J3B)" \
BLINKCLIP_CLOUDKIT_PROFILE="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles/<uuid>.provisionprofile" \
BLINKCLIP_CLOUDKIT_CONTAINER=iCloud.com.chrisli.blinkclip \
BLINKCLIP_CLOUDKIT_ENVIRONMENT=Production \
./replica/scripts/build-app.sh release universal
```

可选：`BLINKCLIP_BUILD_ROOT`（SwiftPM scratch）、`BLINKCLIP_APP_OUTPUT_DIR`（产物目录）。
签名需要 `codesign --timestamp`，**必须联网**；时间戳服务不可用会直接构建失败。

产物校验（`dist/BlinkClip.app` 为默认输出）：

```sh
codesign -d --entitlements :- dist/BlinkClip.app | plutil -p -
```

dev 与 release 两种构建的差异只在身份与环境；`Production` 构建的期望授权：

| 键 | 期望值 |
| --- | --- |
| `com.apple.application-identifier` | `4NJM425J3B.com.chrisli.blinkclip` |
| `com.apple.developer.team-identifier` | `4NJM425J3B` |
| `com.apple.developer.icloud-container-identifiers` | `[iCloud.com.chrisli.blinkclip]` |
| `com.apple.developer.icloud-services` | `[CloudKit]` |
| `com.apple.developer.icloud-container-environment` | `Production`（dev 构建为 `Development`，字符串而非数组） |
| `com.apple.developer.ubiquity-kvstore-identifier` | `4NJM425J3B.com.chrisli.blinkclip`（描述文件带这项时） |
| `com.apple.developer.aps-environment` | dev 描述文件通常为 `development`；Developer ID 描述文件通常没有 |
| `com.apple.security.automation.apple-events` | `true`（Hardened Runtime 下 Finder 选区需要） |
| `com.apple.security.app-sandbox` | **不应出现** |
| `get-task-allow` / `com.apple.security.get-task-allow` | **不应出现** |

同时确认签名与内嵌描述文件：

```sh
codesign -dvv dist/BlinkClip.app 2>&1 | grep -E "Identifier|Authority|TeamIdentifier|flags|Timestamp"
#   flags 期望含 runtime；Authority 必须是本机实际身份
ls -l dist/BlinkClip.app/Contents/embedded.provisionprofile
codesign --verify --deep --strict dist/BlinkClip.app
```

DER 授权由 `codesign` 自动随 `--entitlements` 写入（签名的 `DER_ENTITLEMENTS` blob），
不需要额外步骤；上面的 `codesign -d --entitlements :-` 只打印 XML 那一份。

---

## 6. 功能验证清单

按顺序做，每步都要留证据（截图或日志），不要把单机探针当双机验收。

1. **单机两客户端（真实服务端，合成数据）**——先确认服务端通路：

   ```sh
   bash replica/scripts/test-cloudkit-live.sh --preflight
   BLINKCLIP_CLOUDKIT_PROFILE=... BLINKCLIP_CLOUDKIT_CONTAINER=iCloud.com.chrisli.blinkclip \
   BLINKCLIP_SIGNING_IDENTITY="Apple Development: Chao Li (7Q4W57L7ZM)" \
   BLINKCLIP_CLOUDKIT_TEST_BUNDLE_ID=com.chrisli.blinkclip \
   bash replica/scripts/test-cloudkit-live.sh --synthetic-only
   ```

   探针只写随机 `BlinkClip-Verification-*` zone，验证新增/附件/更新/删除后自清理。
   **`BLINKCLIP_CLOUDKIT_TEST_BUNDLE_ID` 必须等于描述文件的 App ID**（脚本按
   `<团队>.<BundleID>` 精确比对，通配符描述文件用不了）。

2. **两台设备（或两个数据目录）的冲突合并**：两端各改同一条内容的标题，互相同步后确认
   较新字段胜出、另一端的本机编辑没有被静默丢弃（冲突未闭合时会保留本机编辑并暂停）。
3. **离线后重连**：断开网络改内容，再联网，确认补传且不重复、不丢。
4. **删除传播**：一端删除条目/分组，确认另一端删除；再确认本地历史与 iCloud 数据在
   关闭同步后仍保留。
5. **账号侧**：记录一次关闭/开启同步后的状态文案；不要在他人 iCloud 账号上测试，
   也不要把测试数据写进别人的容器。
6. **两台物理 Mac 的验收**是唯一能宣称"设备间同步可用"的证据；单机探针只能证明
   "一台 Mac 的两个客户端经过真实服务端交换"。

---

## 7. 故障排查

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `需要 BlinkClip 自有的 iCloud 容器` | 容器不是 `iCloud.` 开头或含 `wiheads` | 用 `iCloud.com.chrisli.blinkclip` |
| `描述文件的应用标识与当前 Bundle ID 不匹配` | App ID 与 `com.chrisli.blinkclip` 不符，或用了通配符 | 换显式 App ID 重新生成描述文件 |
| `描述文件未授权此 CloudKit 容器` | 后台没把该容器加入 App ID，或描述文件是旧版 | 后台勾选容器后**重新生成**描述文件 |
| `描述文件未启用 CloudKit` | iCloud 勾了但只勾了 Cloud Documents 等 | 勾上 CloudKit 并重新生成 |
| `描述文件未授权此 CloudKit 环境` | 开发描述文件只授权 `Development`，却用 `Production` 构建 | 换匹配的 `BLINKCLIP_CLOUDKIT_ENVIRONMENT` |
| `描述文件已过期` | 描述文件超期 | 重新生成；开发者后台不续期旧文件 |
| `需要本机有效 Apple 签名身份` / ad-hoc 被拒 | 没设 `BLINKCLIP_SIGNING_IDENTITY` 或为 `-` | 用真实身份；ad-hoc 不能带 iCloud 能力 |
| `基础与 CloudKit 授权存在重复键` | 描述文件也带了 `apple-events` 等基础键 | 人工确认后二选一，脚本不替人猜 |
| `The timestamp service is not available` | 签名联网失败 | 重试；离线环境无法出合法分发签名 |
| 设置里一直显示"此构建未配置…" | 构建没带 CloudKit 变量，或授权读不到 | 按第 5 节重新核对 `codesign -d --entitlements` |
| 授权齐全但界面无反 | 见第 8 节：设置开关当前接的是 iCloud Drive | 用第 8 节的临时办法或等待 UI 接线修复 |

---

## 8. 已知未接线点：设置开关目前走的是 iCloud Drive

`replica/Sources/BlinkClip/UI/CloudKitSyncController.swift` 里 `ICloudSyncGeneralRow` 的
开关在打开时调用的是 `drive.setEnabled(true)`（iCloud Drive 文件同步），代码里没有任何
界面路径调用 `CloudKitSyncController.setEnabled(true)`。因此即使授权与构建都齐全，
用户也只能在"通用 → iCloud 同步"里打开 iCloud Drive 那条旧路径。

在 UI 接线修好之前，CloudKit 只能这样启动（**临时绕行，仅用于验证**）：

```sh
# 1. 先关闭 iCloud Drive 同步（两者互斥：drive.isEnabled 为真时 CloudKit 不会启动）
# 2. 写入 CloudKit 启用键（键名含数据目录路径的 SHA-256）
digest=$(printf '%s' "$HOME/Library/Application Support/BlinkClip" | shasum -a 256 | cut -d' ' -f1)
defaults write com.chrisli.blinkclip "blinkclip.cloudkit.$digest.enabled" -bool true
# 3. 退出并重新启动应用（start() 只在启动时读取该键）
```

功能未改动、只缺一个入口：后续修复方向是让该行的绑定在
`sync.canSync` 为真时调用 `sync.setEnabled(true)`（会弹出"开启 iCloud 同步？"确认框），
否则回落到 `drive.setEnabled(true)`。本次改动范围不含 Swift 界面代码，故只记录不改。

---

## 9. 禁止事项

- 不要创建真实 CloudKit 容器用于测试；测试用随机 zone 并自清理。
- 不要把描述文件、私钥、证书导出物、`defaults` 备份提交进仓库。
- 不要在他人 iCloud 账号或他人容器上做验证。
- 不要为了跑通而改签名身份或改团队；证书与描述文件不匹配时重新生成描述文件。
