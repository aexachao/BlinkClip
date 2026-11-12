#!/usr/bin/env python3
"""Check the public static site without accessing any clipboard or app data."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import json
import re

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "website"


class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.targets = []
        self.downloads = set()
        self.release_version = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "html":
            self.release_version = attrs.get("data-release-version")
        if "id" in attrs:
            assert attrs["id"] not in self.ids, f"Duplicate id: {attrs['id']}"
            self.ids.add(attrs["id"])
        if tag == "img":
            assert "alt" in attrs, f"Image has no alt text: {attrs.get('src')}"
        for key in ("href", "src"):
            if key in attrs:
                self.targets.append(attrs[key])
                if attrs[key].endswith(".dmg"):
                    self.downloads.add(attrs[key])


def main():
    parser = SiteParser()
    parser.feed((SITE / "index.html").read_text())
    for target in parser.targets:
        url = urlsplit(target)
        if url.scheme or url.netloc:
            assert url.scheme == "https", f"Non-HTTPS external resource: {target}"
            continue
        if url.path:
            path = (SITE / unquote(url.path)).resolve()
            assert path.is_relative_to(SITE.resolve()), f"Resource outside website: {target}"
            assert path.is_file(), f"Missing resource: {target}"
        elif url.fragment:
            assert unquote(url.fragment) in parser.ids, f"Missing anchor: {target}"
    # No installer has been published in a new repository: never link an upstream DMG as our own.
    version = parser.release_version
    if version == "":
        assert not parser.downloads, "Unreleased repositories must not advertise installer downloads"
        assert "https://github.com/aexachao/BlinkClip/releases" in parser.targets
    else:
        assert version and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version), "Invalid public release version"
        prefix = f"https://github.com/aexachao/BlinkClip/releases/download/v{version}/"
        allowed_downloads = {prefix + f"BlinkClip-{version}-macos-universal.dmg", prefix + f"BlinkClip-{version}-macos-universal.dmg"}
        assert len(parser.downloads) == 1 and parser.downloads <= allowed_downloads, "Download does not match the validated repository release"
    allowed = {".html", ".css", ".js", ".png"}
    for path in SITE.rglob("*"):
        assert not path.is_symlink(), f"Unexpected symlink: {path}"
        if path.is_file():
            assert path.name == ".nojekyll" or path.suffix in allowed, f"Unexpected public file: {path}"
    print(json.dumps({"passed": True, "checked_links": len(parser.targets), "universal_download": version}, ensure_ascii=False))


if __name__ == "__main__":
    main()
