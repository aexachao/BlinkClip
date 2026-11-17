#!/usr/bin/env python3
"""Check the public static site without accessing any clipboard or app data."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit
import json
import re

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / "website"
ASSETS = SITE / "assets"

ALLOWED_SUFFIXES = {".html", ".css", ".js", ".png", ".jpg", ".jpeg", ".svg", ".webp", ".ico"}
ALLOWED_IMAGES = {
    "blinkclip-icon.png",
    "screenshot-clipboard-panel.png",
    "screenshot-capture-overlay.jpg",
    "screenshot-editor-toolbar.png",
    "screenshot-settings-capture.png",
    "screenshot-settings-permissions.png",
}
REQUIRED_FILES = {"index.html", "style.css", "main.js", "i18n.js", "site.js", "assets/icons.svg"}
ICON_REFERENCE = re.compile(r"assets/icons\.svg#([\w-]+)$")


class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = set()
        self.targets = []
        self.images = []
        self.downloads = set()
        self.release_version = None
        self.use_fragments = []
        self.i18n_keys = set()

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "html":
            self.release_version = attrs.get("data-release-version")
        if "id" in attrs:
            assert attrs["id"] not in self.ids, f"Duplicate id: {attrs['id']}"
            self.ids.add(attrs["id"])
        if tag == "img":
            assert "alt" in attrs, f"Image has no alt text: {attrs.get('src')}"
            self.images.append(attrs.get("src", ""))
        if tag == "use" and attrs.get("href"):
            self.use_fragments.append(attrs["href"])
        for key in ("href", "src"):
            if key in attrs:
                self.targets.append(attrs[key])
                if attrs[key].endswith(".dmg"):
                    self.downloads.add(attrs[key])
        for key, value in attrs.items():
            if key.startswith("data-i18n"):
                self.i18n_keys.add(value)


def parse_catalogs():
    source = (SITE / "i18n.js").read_text()
    match = re.search(r"const messages = (\{[\s\S]*?\n  \});", source)
    assert match, "Could not locate the translation catalog"
    messages = json.loads(match.group(1))
    assert set(messages) == {"zh-Hans", "en"}, f"Unexpected catalogs: {sorted(messages)}"
    for language, catalog in messages.items():
        assert catalog, f"Empty catalog: {language}"
        for key, value in catalog.items():
            assert isinstance(value, str) and value.strip(), f"Empty translation: {language}/{key}"
    assert set(messages["zh-Hans"]) == set(messages["en"]), "Catalogs have different keys"
    for key in messages["zh-Hans"]:
        left = re.findall(r"\{\w+\}", messages["zh-Hans"][key])
        right = re.findall(r"\{\w+\}", messages["en"][key])
        assert left == right, f"Placeholders differ for {key}"
    return messages


def parse_symbols():
    source = (ASSETS / "icons.svg").read_text()
    return set(re.findall(r'<symbol id="([\w-]+)"', source))


def main():
    parser = SiteParser()
    parser.feed((SITE / "index.html").read_text())

    for required in REQUIRED_FILES:
        assert (SITE / required).is_file(), f"Missing required site file: {required}"

    for target in parser.targets:
        url = urlsplit(target)
        if url.scheme or url.netloc:
            assert url.scheme == "https", f"Non-HTTPS external resource: {target}"
            continue
        assert not target.startswith("/"), f"Absolute root path breaks GitHub Pages subpath deployment: {target}"
        if url.path:
            path = (SITE / unquote(url.path)).resolve()
            assert path.is_relative_to(SITE.resolve()), f"Resource outside website: {target}"
            assert path.is_file(), f"Missing resource: {target}"
        elif url.fragment:
            assert unquote(url.fragment) in parser.ids, f"Missing anchor: {target}"

    symbols = parse_symbols()
    for reference in parser.use_fragments:
        match = ICON_REFERENCE.search(reference)
        assert match, f"Unexpected sprite reference: {reference}"
        assert match.group(1) in symbols, f"Missing icon symbol: {reference}"

    for image in parser.images:
        name = Path(unquote(urlsplit(image).path)).name
        assert name in ALLOWED_IMAGES, f"Image is not on the reviewed, privacy-safe allowlist: {image}"

    messages = parse_catalogs()
    for key in parser.i18n_keys:
        assert key in messages["zh-Hans"] and key in messages["en"], f"Missing translation key: {key}"

    version = parser.release_version
    if version == "":
        assert not parser.downloads, "Unreleased repositories must not advertise installer downloads"
        assert any("github.com/aexachao/BlinkClip/releases" in target for target in parser.targets), "Missing release link"
        assert not re.search(r"BlinkClip-\d+\.\d+\.\d+-macos-universal\.dmg", (SITE / "index.html").read_text()), "Versioned DMG is hard-coded"
    else:
        assert version and re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version), "Invalid public release version"
        prefix = f"https://github.com/aexachao/BlinkClip/releases/download/v{version}/"
        allowed_downloads = {prefix + f"BlinkClip-{version}-macos-universal.dmg"}
        assert len(parser.downloads) == 1 and parser.downloads <= allowed_downloads, "Download does not match the validated repository release"

    for path in SITE.rglob("*"):
        assert not path.is_symlink(), f"Unexpected symlink: {path}"
        if path.is_file():
            assert path.name == ".nojekyll" or path.suffix.lower() in ALLOWED_SUFFIXES, f"Unexpected public file: {path}"
            if path.parent == ASSETS and path.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp", ".ico"}:
                assert path.name in ALLOWED_IMAGES, f"Unreviewed image in assets: {path.name}"

    css = (SITE / "style.css").read_text()
    lower = css.lower()
    assert "#ffffff" not in lower and "#6366f1" not in lower, "Forbidden pure white or indigo design token"
    # The landing page keeps one calm, upright product frame: no tilted colour blocks,
    # no decorative section clip-paths and no warm wash textures.
    assert "clip-path:" not in lower, "Decorative clip-path section edges must not return"
    assert "texture-seoul" not in lower, "Decorative wash textures must not return"
    assert not re.search(r"rotate\(-", lower), "Product screenshots must stay upright (no negative rotation)"
    frame = re.search(r"\.shot,\s*\n\.hero-shot\s*\{([^}]*)\}", css)
    assert frame, "Reviewed screenshots must share one frame rule"
    for token in ("border: 1px solid", "border-radius: 14px", "box-shadow: 0 24px 60px rgba(25, 25, 23, 0.1)"):
        assert token in frame.group(1), f"Screenshot frame is missing {token!r}"
    assert re.search(r"\.hero-shot\s*\{\s*width:\s*min\(1180px, 100%\)", css), \
        "The hero product shot must stay centred at min(1180px, 100%)"

    html = (SITE / "index.html").read_text()
    assert not re.search(r"data-count=|class=\"stat-row", html), "The filled-out statistic rows must not return"

    print(json.dumps({
        "passed": True,
        "checked_links": len(parser.targets),
        "translation_keys": len(messages["en"]),
        "reviewed_images": len(set(parser.images)),
        "universal_download": version,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
