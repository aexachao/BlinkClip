# 产物与磁盘预算

本仓库的构建、测试和打包产物**不落在仓库里**，而是落在 `~/dev-artifacts/BlinkClip` 下的任务目录。
这里写清楚它们怎么生成、怎么清理、超出预算是谁的问题。

## 产物落在哪

所有构建、测试、打包都通过 storage-guard 启动（见 [AGENTS.md](../AGENTS.md)），每次运行生成一个任务目录：

```
~/dev-artifacts/BlinkClip/<task>-<pid>-<YYYYMMDD>-<HHMMSS>/
├── out/      交付物与证据（BlinkClip.app、DMG、报告、日志）
└── build/    中间文件（TMPDIR、clang/SwiftPM 模块缓存；多数测试跑完自己删）
```

例如 `netspeed-build-37351-20261119-170420/`。名字格式固定为 `<task>-<pid>-<8 位日期>-<6 位时间>`，
清理脚本就是靠这个格式认出「哪些是我们的任务目录」。

仓库内不保存构建缓存：`replica/.build/`（SwiftPM）与 `replica/dist/` 都在 `.gitignore` 里。

## 预算

| 项目 | 上限 | 超了说明什么 |
| --- | --- | --- |
| `~/dev-artifacts` 总量 | **8 GiB** | 跑测/发版太多没清理，或其它仓库的产物在长 |
| 单个任务目录 | **1 GiB** | 构建产物异常：多半是把依赖、`dist/` 或整份 `.app` 重复拷进了 `out/` |

`scripts/prune-artifacts.sh` 会在保留项里发现超过 1 GiB 的目录时打印一行 `注意: …`，
提醒去 `.storage-guard.json` 和 `out/` 里看看到底写进了什么，而不是默默留着。

> 8 GiB 是 `~/dev-artifacts` 的**总量**预算。这个目录是多个本地项目共用的，本仓库的脚本只管
> `~/dev-artifacts/BlinkClip` 这一个子目录；别的仓库的产物不在它的处理范围内。
> 截至 2026-11-26 清理后：本仓库 1.26 GiB / 144 个任务目录，`~/dev-artifacts` 合计 13.7 GiB
> （差额来自 `fnos_music_ext`、`iReader`、`qingjian-music` 等其它仓库）。

## 清理

```bash
bash scripts/prune-artifacts.sh                 # 默认 dry-run：只列清单，不动文件
bash scripts/prune-artifacts.sh --apply         # 真删（保留最近 7 天 + 最新 5 个）
bash scripts/prune-artifacts.sh --apply --keep-days 3   # 发版后更激进
bash scripts/prune-artifacts.sh --root /path/to/root --keep-latest 2 --verbose
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `--apply` | 关 | 不加就是试跑，只打印 |
| `--keep-days N` | 7 | 保留最近 N 天内有活动的任务目录 |
| `--keep-latest N` | 5 | 无论多旧，最新的 N 个一定保留 |
| `--root DIR` | `~/dev-artifacts/BlinkClip` | 产物根（也可用 `BLINKCLIP_ARTIFACT_ROOT`） |
| `--verbose` | 关 | 连保留项也逐条打印 |
| `--quiet` | 关 | 只打结论与 JSON（发布脚本里用） |

保留策略是**并集**：最近 7 天内的目录 **或** 最新的 5 个目录，两者满足一个就留下。

### 安全护栏

脚本故意只能干一件很窄的事，出错时宁可不删：

- 只删名字匹配 `^[a-z0-9-]+-[0-9]+-[0-9]{8}-[0-9]{6}$` 的**直接子目录**；
- `secrets/`、`bin/`、`shared/`、`sparkle-tools-2.10.1/` 这类非任务目录、符号链接、普通文件、
  隐藏项一律跳过，并逐条打印跳过原因；
- 拒绝在 `/`、`$HOME`、`$HOME/dev-artifacts` 这类过宽的根上运行（退出码 2）；
- 从不递归删除上级目录，也不跟随符号链接。

「有活动」= 目录自身或直接子项的 mtime 最大值，所以一个目录里最后改过文件的，会被算成刚用过。

### 输出

人读部分逐条列出将删项（`DEL <字节> <时间> <名字>`）与跳过项（`SKIP …`），最后打印一行 JSON 摘要：

```json
{"mode": "apply", "scanned_count": 395, "kept_count": 144, "planned_delete_count": 251,
 "deleted_count": 251, "freed_bytes": 1815883776, "reclaimable_bytes": 1815883776,
 "skipped_count": 3, "root": "…", "keep_days": 7, "keep_latest": 5, "cutoff": "…", "errors": []}
```

有删除失败时退出码为 1（`errors` 里有明细），参数或根目录不合法时退出码为 2。

## `replica/.build` 可以随时删

它是 SwiftPM 的构建缓存（清理前约 2.4 GiB），`gitignored`，**不属于证据**，删掉不影响任何提交内容：

```bash
rm -rf replica/.build     # 下次 bash replica/scripts/build-app.sh 自动重建
```

唯一代价是下次构建要重新编译一遍。它不在 `prune-artifacts.sh` 的处理范围里（那个脚本只管
`~/dev-artifacts` 的产物根），所以磁盘紧张时自己删。

## 发版后自动清理

`replica/scripts/build-notarized.sh` **结束时**会自动跑一次：

```bash
bash "$root/scripts/prune-artifacts.sh" --apply --keep-days 3 --quiet
```

选择放在脚本里而不是只写进 checklist，是因为「发版后记得手工清理」这种事一定会漏；
接在公证、staple、签名清单和 Sparkle feed 全部写完之后，回收的是**上一次及更早**的产物目录，
本次发布的 `out/` 是最新的一个，永远在保留集合里。

清理失败**不影响发布结果**：产物此时已经签名、公证、stapled 完成，脚本用 `|| true` 的等价写法
兜住退出码并打印一行提示，发布照常成功。要复核就自己再跑一次 dry-run。

## 记录

每次清理都要留痕。本次（2026-11-26）的清理清单在
[evidence/cleanup/2026-11-26-artifacts-cleaned.txt](../evidence/cleanup/2026-11-26-artifacts-cleaned.txt)，
里面有被删目录的逐个名称与体积、保留策略、以及明确没碰的路径。
