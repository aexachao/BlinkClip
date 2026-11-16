# 测试编排指南（按改动范围选测试）

> 本文件管**怎么选测试**；**怎么跑单项测试**（环境变量、离屏夹具、`--live` 探针）见
> [replica/TESTING.md](../replica/TESTING.md)。两者冲突时以本文件的流程为准。

## 为什么要选

全量（56 个测试入口）包含整包构建、真实 App 启动、性能数据集，一轮十几分钟到几十分钟。
日常每轮都跑全量，既拖慢节奏，也让人习惯性忽略失败。所以：

- **日常**：只跑「本次改动会编译到 / 断言到」的测试；
- **发版前**：必跑全量。

选择由 `replica/scripts/test-affected.py` 依据内置的**映射规则表**（文件 glob → 测试项）算出，
规则表就在脚本里（`RULES`，当前 106 条规则 / 56 个测试项），改规则必须走 code review。

## 日常流程

```bash
# 1) 先看选了什么（不执行，随时可跑）
python3 replica/scripts/test-affected.py --worktree --dry-run

# 2) 确认选择合理后，直接跑选中的测试
python3 replica/scripts/test-affected.py --worktree

# 3) 提交前按提交范围再跑一次（对比基线分支）
python3 replica/scripts/test-affected.py --base origin/main
```

输出包含四部分：改动文件 → 选中测试（每条带**命中规则**与理由）→ 跳过测试 → 预估耗时
（有历史耗时才有数字，否则显示 `—`）。

退出码：`0` 全部通过；`1` 有测试失败；`2` 有测试因缺环境变量**未执行**（不算通过）。
默认首个失败即停；想一次看完全部失败加 `--keep-going`。

两种取改动的方式：

| 参数 | 取什么 | 典型用途 |
| --- | --- | --- |
| `--worktree`（默认） | `git status`，含未跟踪文件 | 边改边跑 |
| `--base <commit>` | `git diff --name-only <base>...HEAD` | 提交/分支收尾 |
| `--files <path>...` | 直接给文件列表 | 演练、验证规则表 |
| `--audit` | 体检规则表：列出没有规则覆盖的源码文件 | 新增目录后必跑 |

## 发版流程

```bash
python3 replica/scripts/test-affected.py --full --dry-run   # 确认 56 项都在
python3 replica/scripts/test-affected.py --full             # 必跑，全绿才能发
```

`--full` 忽略改动、选中全部测试项。发版前不允许用「改动不大」作为跳过理由；
需要真机/自有签名的项（`cloudkit-live`、`blinkclip-legacy-migration` 等）缺环境变量时会报
**未执行**并以退出码 2 结束——这时要么补齐环境跑，要么在发布记录里写明未覆盖的原因。

## 映射表维护规则

1. **新增源码目录必须补规则**，否则改到该目录的文件会命中「未覆盖路径」→ 本次**回退全量**并在
   输出里点名路径。这是有意的失败方向：宁可多跑，不可漏跑。
2. 每条规则要能回答两个问题，并把答案写进 `why`：
   - 这个 glob 下的文件被哪些测试**编译/读取**（编译门）；
   - 这些测试**断言**了什么（行为门）。
3. 具体文件规则排在目录规则前面。引擎按顺序**首个命中即停**，所以「改一个文件」不会被宽泛的
   目录规则放大成全量，但每条具体规则里至少要留一个会编译该文件的测试。
4. 改 `replica/Tests/Native/*.swift` 时引擎会去 `test-*.sh` 里找引用它的脚本，自动把对应测试
   加进清单；没有脚本引用（孤儿 harness）则回退全量。改 `replica/scripts/test-*.sh|py` 时把
   **该测试自身**加进清单。
5. 纯文档（`docs/**`、根目录 `*.md`）有显式的「无测试项」规则，会打印「无测试项，跳过」而不是
   回退全量；例外是 `DESIGN.md`（框选 chrome 源码门会读它）、`README.md`/`README.en.md`
   （发布下载同步会重写它们）、`CHANGELOG.md`（发布测试解析它）、`NOTICE.md`/`LICENSE`
   （自有资源测试断言它们被打包）。
6. 新增测试入口时，同时往脚本的 `ITEMS` 表登记（命令、覆盖范围、断言内容、所需环境变量），
   并在相关规则里引用；没被任何规则引用的测试项 `--audit` 会提示。
7. 每次改完规则表，跑一遍：

   ```bash
   python3 replica/scripts/test-affected.py --audit
   python3 replica/scripts/test-affected.py --files <受影响的代表文件> --dry-run
   ```

   `--audit` 只允许列**已知缺口**（脚本里的 `KNOWN_UNCOVERED`，当前仅
   `replica/Tests/Native/ShortcutRecorderLifecycleHarness.swift` —— 没有任何脚本编译它）。
   出现新的未覆盖文件就要么补规则，要么明确写进 `KNOWN_UNCOVERED` 并说明原因。

## 规则表覆盖速览

| 改动区域 | 选中面（要点） |
| --- | --- |
| `replica/Sources/BlinkClip/UI/**` | UI 编译面（capture-integration、copy-restore、settings-*、ui-interaction、panel-* 等）；ReplicaToast/PanelViews/权限页等有更细的单文件规则 |
| `replica/Sources/BlinkClip/Screenshot/**` | capture-integration + screenshot-window-hider（WindowHider 另加 panel-hotkey） |
| `replica/Sources/BlinkClip/AppMain.swift`、`GlobalHotKey*.swift` | sound-effects/panel-menu/权限-设置面、hotkey/panel-hotkey/app-updates |
| 应用层其它文件（`BackgroundService`、`PanelShortcutMenu`、`WindowSharingPolicy`、`AppIntents/` 等） | 各自的编译/断言面；**新增到这些目录之外的文件 → 回退全量** |
| `replica/Sources/BlinkClipCore/**` | core-tests + 链接 core 的保守面；SoundEffects 有专门的窄规则 |
| `replica/Vendor/capcap/Capture/**` | capture-chrome-exclusion + editor-chrome-parity + capture-integration |
| `replica/Vendor/capcap/Editor/**` | editor-chrome-parity + feedback-shortcuts + toolbar-upload-removal |
| `replica/Vendor/capcap/Utilities/**` | identifier-namespace-migration + 模块编译面 |
| `replica/Tests/Native/**` | 引用该 harness 的 `test-*.sh`；`build-support.sh` 命中全部原生脚本 |
| `replica/scripts/**` | 该脚本自身（`test-*`）、发布/打包链路、suite 入口（validate.sh / regress-local.sh） |
| `replica/Assets/**`、`Resources/**`、`BlinkClipResources/**` | packaged-resources / blinkclip-owned-resources（+ 图标相关） |
| `docs/**`、`*.md` | 无测试项，跳过（`DESIGN.md` 等例外见上） |
| 未收录路径 | **回退全量**并点名路径 |

## 全量最近一次通过记录

每次 `--full` 全绿后，更新下表（只记通过的那次，失败不要写）：

| 日期（本地） | 提交 | 结果 | 备注 |
| --- | --- | --- | --- |
| 2026-11-16 | `3c613aa`（1.0.25 集成前） | 未执行 `--full` | 本工具落地（基线 `ba7591e`）后首轮集成只跑受影响测试（`test-affected.py --worktree` 选中项），全量待发版前补 |

## 与既有入口的关系

- `replica/scripts/validate.sh`、`replica/scripts/regress-local.sh` 保持原样，它们仍是
  「固定子集 + 全量回归」的执行者；本工具只负责**选**，不替换它们。
- 本工具不改任何既有测试脚本的行为；它只是决定跑哪些。
