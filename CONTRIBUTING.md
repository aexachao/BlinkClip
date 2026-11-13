# 为 BlinkClip 贡献

欢迎提交问题报告、文档改进和范围清晰的修复。开始前请阅读 [AGENTS.md](AGENTS.md)、[NOTICE.md](NOTICE.md) 与 [测试范围](replica/TESTING.md)。

## 报告问题

在 [Issues](https://github.com/aexachao/BlinkClip/issues) 提供：

- macOS 版本、芯片架构、BlinkClip 版本或提交号。
- 最少操作步骤、预期行为和实际行为。
- 是否涉及辅助功能权限、直接粘贴、特定目标应用或自定义快捷键。
- 使用虚构文本、临时图片或文件制作的截图及复现材料。

不要附真实剪贴板历史、个人归档、账号、访问令牌、密钥或未经检查的完整日志。不要上传原版安装包、二进制副本或用户数据库。需要提供配置时，只保留与问题有关的字段并移除个人路径。

## 提交修改

1. 说明修改解决的具体问题，保留用户已有数据及技术兼容键。
2. 在现有实现上做最小改动，不覆盖他人已落盘的修改。
3. 记录验证方法和结果，明确区分静态核对、编译与实际操作测试。
4. 界面和新文案统一使用 **闪贴 / BlinkClip**。原函数地址、系统 `paste` API 和历史证据保持真实。

可先进行静态检查和源码构建。构建、测试与打包必须通过 storage-guard，产物写到仓库外，不使用仓库内缓存：

```sh
~/dev-artifacts/bin/storage-guard run --repo blinkclip --task contributor-compile -- /bin/bash -c '
  export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp/"
  export CLANG_MODULE_CACHE_PATH="$ARTIFACT_TASK_DIR/build/module-cache"
  export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
  mkdir -p "$TMPDIR"
  swift build --package-path replica --scratch-path "$ARTIFACT_TASK_DIR/build/swiftpm" -c release
'
```

该命令编译当前 Mac 的本机架构。BlinkClip 的源码构建目标为 macOS 14+ 的 Intel（x86_64）和 Apple 芯片（arm64）。制作发布格式的 Universal 安装包时，在仓库根目录执行：

```sh
~/dev-artifacts/bin/storage-guard run --repo blinkclip --task contributor-package --kind release -- /bin/bash -c '
  export TMPDIR="$ARTIFACT_TASK_DIR/build/tmp/"
  export BLINKCLIP_BUILD_ROOT="$ARTIFACT_TASK_DIR/build/swiftpm"
  export BLINKCLIP_APP_OUTPUT_DIR="$ARTIFACT_TASK_DIR/out"
  export BLINKCLIP_RELEASE_OUTPUT_DIR="$ARTIFACT_TASK_DIR/out/release"
  mkdir -p "$TMPDIR"
  npm run build:dmg
'
```

该命令调用 `release-ci.py package`，制作 `BlinkClip-<版本号>-macos-universal.dmg`（包含两种架构），以及 `SHA256SUMS.txt`、`release-manifest.json` 和签名 `appcast.xml`。正式打包需要项目外提供与内嵌公钥匹配的更新私钥，见[应用内更新](docs/APP_UPDATES.md)；缺少签名配置时不得伪造更新源。本地打包不等于上传或公开发布，本仓库尚无正式安装包。

GitHub 自动显示的 `Source code (zip)` / `Source code (tar.gz)` 是标签源码链接，不是安装包。未来已发布的 Universal DMG 无须选择芯片：打开后将 `BlinkClip.app` 拖入 Applications，从应用程序启动，再推出磁盘映像。开发签名或临时签名均不等于 Developer ID 公证；不要添加绕过系统安全保护的教程。

涉及架构的修改应说明编译目标、运行机器和是否通过 Rosetta 执行。双架构编译或打包通过不代表两类机器上的功能已验证；不要据此宣称已恢复原版 x86_64 行为。

本项目目前处于迁移和对照阶段，默认不执行全量功能回归或 MCP 测试。定向实机验证应先明确问题、范围和隔离方式，使用合成数据；单项通过不能写成全量验收。跨应用直接粘贴仍有未验证的兼容性边界。

不凭函数命名或静态计数宣布实现完成；实现是否完成以实际编译与实际操作验证为准。

## 贡献许可

独立实现、工具、文档和新图标的贡献应由你有权提交，并接受本项目 [GNU AGPL-3.0](LICENSE) 的约束，提交即表示你同意以 AGPL-3.0 授权你的贡献。不要把第三方代码或原版素材标成自己的原创内容；第三方材料须保留来源及各自的许可和权利说明。
