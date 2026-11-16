#!/usr/bin/env python3
"""把「源码 → 二进制」钉在一起：源码指纹、缓存失效、产物校验。

背景：SwiftPM 的增量编译只看文件 mtime。只要源文件的 mtime 不再前进（`cp -p`、
`git checkout` 还原旧时间、把 scratch 指到共享目录、从旧归档里解出源码），
`swift build` 就会复用过期 .o，产出一个「版本号是新的、代码是旧的」二进制，
而打包脚本对此毫无察觉。

也不要靠「二进制里有没有新符号」来判断：release 优化会内联小函数，1.0.21 的
`SelectionView.barPath` / `cornerBracketRects` 在二进制里根本没有独立符号，所以
符号探测既不能证明新代码在，也不能证明旧代码不在。

做法：
  * digest —— 对决定二进制的源码集算内容指纹；与 scratch 里记录的指纹不一致就
              作废架构缓存，强制重新编译（见 build-app.sh）；
  * seal   —— 构建落地后校验「可执行文件比所有源码新」，并把指纹、git 提交、
              各可执行文件 sha256 写成 <app 同级>/BlinkClip.build-manifest.json；
  * verify —— 发布打包前复核指纹、清单、可执行文件哈希与时间顺序，任一不符即中止。
"""
import argparse
import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

REPOSITORY = Path(__file__).resolve().parents[2]
REPLICA = REPOSITORY / "replica"

# 只有这些输入会改变二进制内容：Swift 源码、随包资源、包清单与版本号。
SOURCE_DIRECTORIES = ("Sources", "Vendor", "Assets")
EXTRA_FILES = (REPLICA / "Package.swift", REPOSITORY / "package.json")
SKIP_DIRECTORY_NAMES = {"__pycache__", ".build", ".swiftpm", ".git"}
SKIP_FILE_NAMES = {".DS_Store"}
SKIP_SUFFIXES = {".o", ".swiftmodule", ".swiftdoc", ".pyc"}


def iter_inputs():
    """Yield every file whose content decides the binary, in a stable order."""
    for name in SOURCE_DIRECTORIES:
        root = REPLICA / name
        if not root.is_dir():
            raise SystemExit(f"缺少源码目录：{root}")
        for path in sorted(root.rglob("*")):
            if path.is_symlink() or not path.is_file():
                continue
            if SKIP_DIRECTORY_NAMES & set(path.parts):
                continue
            if path.name in SKIP_FILE_NAMES or path.suffix in SKIP_SUFFIXES:
                continue
            yield path
    for path in EXTRA_FILES:
        if not path.is_file():
            raise SystemExit(f"缺少构建输入：{path}")
        yield path


def digest_files(paths):
    """sha256 over path + content, independent of mtimes and of the checkout path."""
    checksum = hashlib.sha256()
    count = 0
    for path in paths:
        checksum.update(str(path.relative_to(REPOSITORY)).encode("utf-8"))
        checksum.update(b"\0")
        checksum.update(hashlib.sha256(path.read_bytes()).digest())
        count += 1
    return checksum.hexdigest(), count


def source_digest():
    return digest_files(iter_inputs())


def newest_input_mtime():
    newest = 0.0
    newest_path = None
    for path in iter_inputs():
        stamp = path.stat().st_mtime
        if stamp > newest:
            newest, newest_path = stamp, path
    return newest, newest_path


def executables(app):
    """Every Mach-O the build installs into the bundle, as app-relative paths."""
    roots = [app / "Contents/MacOS"]
    roots.extend(sorted(app.glob("Contents/Library/LoginItems/*/Contents/MacOS")))
    found = []
    for root in roots:
        if not root.is_dir():
            continue
        for path in sorted(root.iterdir()):
            if path.is_file() and not path.is_symlink():
                found.append(path)
    if not found:
        raise SystemExit(f"包里没有任何可执行文件：{app}")
    return found


def sha256_file(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def git_commit():
    try:
        result = subprocess.run(["git", "-C", str(REPOSITORY), "rev-parse", "--short=12", "HEAD"],
                                capture_output=True, text=True)
    except OSError:
        return None
    if result.returncode:
        return None
    commit = result.stdout.strip()
    status = subprocess.run(["git", "-C", str(REPOSITORY), "status", "--porcelain", "--untracked-files=no"],
                            capture_output=True, text=True)
    if status.returncode == 0 and status.stdout.strip():
        commit += "-dirty"
    return commit or None


def version():
    return json.loads((REPOSITORY / "package.json").read_text())["version"]


def manifest_path(app):
    stem = app.name[:-4] if app.name.endswith(".app") else app.name
    return app.parent / f"{stem}.build-manifest.json"


def assert_fresh(app, digest, count):
    """The executables must be newer than every input: proves they were linked now."""
    newest, newest_path = newest_input_mtime()
    stale = [path for path in executables(app) if path.stat().st_mtime < newest]
    if stale:
        raise SystemExit(
            "产物比源码旧，可能复用了过期编译缓存：\n  "
            + "\n  ".join(f"{p}（{time.strftime('%F %T', time.localtime(p.stat().st_mtime))}）" for p in stale)
            + f"\n最新的源码输入：{newest_path}（{time.strftime('%F %T', time.localtime(newest))}）"
            + f"\n源码指纹 {digest}（{count} 个文件）")
    return newest


def command_digest(arguments):
    digest, count = source_digest()
    if arguments.quiet:
        print(digest)
    else:
        print(f"{digest}  {count} 个源码输入文件")
    return 0


def command_seal(arguments):
    app = Path(arguments.app).resolve()
    if not app.is_dir():
        raise SystemExit(f"找不到构建产物：{app}")
    digest, count = source_digest()
    assert_fresh(app, digest, count)
    manifest = {
        "schema": 1,
        "application": app.name,
        "version": version(),
        "source_commit": git_commit(),
        "source_digest": digest,
        "source_input_count": count,
        "configuration": arguments.configuration,
        "architecture": arguments.architecture,
        "built_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "executables": {
            str(path.relative_to(app)): sha256_file(path) for path in executables(app)
        },
    }
    destination = manifest_path(app)
    destination.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(f"构建指纹已封存：{destination}")
    print(f"  source_digest {digest}（{count} 个文件，{manifest['source_commit']}）")
    return 0


def command_verify(arguments):
    app = Path(arguments.app).resolve()
    if not app.is_dir():
        raise SystemExit(f"找不到待发布产物：{app}")
    destination = Path(arguments.manifest).resolve() if arguments.manifest else manifest_path(app)
    if not destination.is_file():
        raise SystemExit(f"缺少构建指纹清单，拒绝发布：{destination}\n"
                         "  该产物不是由 replica/scripts/build-app.sh 生成的，"
                         "请在干净环境重新构建。")
    manifest = json.loads(destination.read_text())
    failures = []

    digest, count = source_digest()
    if manifest.get("source_digest") != digest:
        failures.append(
            f"源码指纹与产物不符：清单 {manifest.get('source_digest')}（{manifest.get('source_input_count')} 个文件）"
            f" / 当前 {digest}（{count} 个文件）——产物不是这批源码构建出来的")

    expected_version = version()
    if manifest.get("version") != expected_version:
        failures.append(f"清单版本 {manifest.get('version')} 与 package.json {expected_version} 不符")

    for relative, expected in sorted(manifest.get("executables", {}).items()):
        path = app / relative
        if not path.is_file():
            failures.append(f"清单里的可执行文件缺失：{relative}")
        elif sha256_file(path) != expected:
            failures.append(f"可执行文件已被替换：{relative}")

    try:
        assert_fresh(app, digest, count)
    except SystemExit as error:
        failures.append(str(error))

    if failures:
        raise SystemExit("产物与源码一致性校验失败，已中止发布：\n" + "\n".join(f"  - {item}" for item in failures))
    print(f"产物与源码一致：{app}")
    print(f"  source_digest {digest}（{count} 个文件，{manifest.get('source_commit')}）")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    subcommands = parser.add_subparsers(dest="command", required=True)

    digest = subcommands.add_parser("digest", help="打印源码内容指纹")
    digest.add_argument("--quiet", action="store_true", help="只打印指纹，便于脚本比较")
    digest.set_defaults(handler=command_digest)

    seal = subcommands.add_parser("seal", help="构建后封存指纹清单")
    seal.add_argument("--app", required=True)
    seal.add_argument("--configuration", default="release")
    seal.add_argument("--architecture", default="universal")
    seal.set_defaults(handler=command_seal)

    verify = subcommands.add_parser("verify", help="打包前复核产物与源码一致")
    verify.add_argument("--app", required=True)
    verify.add_argument("--manifest")
    verify.set_defaults(handler=command_verify)

    arguments = parser.parse_args()
    sys.exit(arguments.handler(arguments))


if __name__ == "__main__":
    main()
