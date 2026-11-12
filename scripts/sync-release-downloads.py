#!/usr/bin/env python3
"""Sync public download links from an already published stable GitHub release."""
import argparse
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
REPO = "aexachao/BlinkClip"
BASE = "https://github.com/" + REPO
FILES = ("README.md", "README.en.md", "website/index.html", "website/i18n.js")
START = "<!-- blinkclip-download:start -->"
END = "<!-- blinkclip-download:end -->"


def release_info(release):
    tag = release.get("tag_name", "")
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("Expected a stable vMAJOR.MINOR.PATCH release")
    if release.get("draft") is not False or release.get("prerelease") is not False or not release.get("published_at"):
        raise ValueError("Download links require a published, non-prerelease release")
    version = tag[1:]
    names = {f"BlinkClip-{version}-macos-universal.dmg"}
    assets = [asset for asset in release.get("assets", []) if asset.get("name", "").endswith(".dmg")]
    if len(assets) != 1 or assets[0].get("name") not in names:
        raise ValueError("Expected exactly one versioned Universal DMG")
    asset = assets[0]
    name = asset["name"]
    url = f"{BASE}/releases/download/{tag}/{name}"
    if asset.get("browser_download_url") != url or asset.get("state") != "uploaded" or asset.get("size", 0) <= 0:
        raise ValueError("The Universal DMG is missing, incomplete, or belongs to another repository")
    if release.get("html_url") != f"{BASE}/releases/tag/{tag}":
        raise ValueError("Unexpected release URL")
    return version, url


def replace_one(pattern, replacement, source):
    result, count = re.subn(pattern, replacement, source)
    if count != 1:
        raise ValueError(f"Expected exactly one binding for {pattern!r}; found {count}")
    return result


def render(root, release):
    """Render either a validated published release or the explicit no-release state."""
    version, url = release_info(release) if release is not None else (None, BASE + "/releases")
    originals = {name: (root / name).read_text() for name in FILES}
    updated = dict(originals)
    for name, label in [("README.md", "下载"), ("README.en.md", "Download")]:
        if version:
            lead = (f"当前正式版 **{version}**，一个安装包兼容 Intel 与 Apple 芯片：" if name == "README.md"
                    else f"Current stable version: **{version}**. One installer supports Intel and Apple silicon:")
            body = lead + f"\n\n[{label} {url.rsplit('/', 1)[-1]}]({url})"
        else:
            body = ("本仓库尚未发布安装包。请先按下方说明从源码构建；未来正式包见 "
                    if name == "README.md" else
                    "This repository has no published installer yet. Build from source below; future installers will appear in ")
            body += f"[Releases]({BASE}/releases)。" if name == "README.md" else f"[Releases]({BASE}/releases)."
        block = f"{START}\n{body}\n{END}"
        updated[name] = replace_one(re.escape(START) + r"[\s\S]*?" + re.escape(END), lambda _: block, originals[name])

    html = replace_one(r'data-release-version="[^"]*"', lambda _: f'data-release-version="{version or ""}"', originals["website/index.html"])
    html = replace_one(r'(class="release-pill" href=")[^"]+(")', lambda m: m[1] + (f"{BASE}/releases/tag/v{version}" if version else BASE + "/releases") + m[2], html)
    html, count = re.subn(r'(class="button" href=")[^"]+(")', lambda m: m[1] + url + m[2], html)
    if count != 2:
        raise ValueError("Expected both website installer/release buttons")
    release_zh = f"当前正式安装包：BlinkClip {version}" if version else "安装包尚未发布 · 查看源码"
    release_en = f"Current stable installer: BlinkClip {version}" if version else "No installer published yet · View source"
    meta_zh = f"v{version} · macOS 14+ · Intel / Apple 芯片" if version else "源码构建 · macOS 14+"
    meta_en = f"v{version} · macOS 14+ · Intel / Apple silicon" if version else "Build from source · macOS 14+"
    download_zh = "免费下载 Mac 版" if version else "查看发布状态"
    download_en = "Download for Mac" if version else "View release status"
    for key, value in [("hero.release", release_zh), ("download.meta", meta_zh), ("download.mac", download_zh)]:
        html, count = re.subn(r'(data-i18n="' + re.escape(key) + r'">)[^<]+', lambda m: m[1] + value, html)
        if count != (2 if key == "download.mac" else 1):
            raise ValueError("Unexpected HTML binding count: " + key)
    updated["website/index.html"] = html
    catalog = originals["website/i18n.js"]
    for key, values in [("hero.release", [release_zh, release_en]), ("download.meta", [meta_zh, meta_en]), ("download.mac", [download_zh, download_en])]:
        translations = iter(values)
        catalog, count = re.subn(r'("' + re.escape(key) + r'":\s*)("(?:\\.|[^"\\])*")', lambda m: m[1] + json.dumps(next(translations), ensure_ascii=False), catalog)
        if count != 2:
            raise ValueError("Expected Chinese and English release translations: " + key)
    updated["website/i18n.js"] = catalog
    return {name: text for name, text in updated.items() if text != originals[name]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--release-json", type=Path)
    source.add_argument("--unreleased", action="store_true", help="Explicitly show that this repository has no published installer")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    release = None if args.unreleased else json.loads(args.release_json.read_text())
    changes = render(ROOT, release)  # Validate all bindings before writing any file.
    if args.check and changes:
        raise SystemExit("Stale download bindings: " + ", ".join(changes))
    for name, text in changes.items():
        (ROOT / name).write_text(text)
    print(json.dumps({"release": release["tag_name"] if release else None, "changed": list(changes)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
