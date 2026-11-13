# BlinkClip (闪贴)

**BlinkClip is a free, local-first clipboard history and screenshot tool for macOS.** Everything you copy stays findable, and screenshots are ready to annotate or pin to your screen.

It runs on **macOS 14+, Intel (x86_64) and Apple silicon (arm64)**, built with Swift, AppKit, and SwiftUI. Your data stays on your Mac by default, and no account is required.

[![Build and release](https://github.com/aexachao/BlinkClip/actions/workflows/release.yml/badge.svg)](https://github.com/aexachao/BlinkClip/actions/workflows/release.yml)

[Download the latest release](https://github.com/aexachao/BlinkClip/releases) · [Build from source](#build-from-source) · [Contribute](CONTRIBUTING.md) · [License scope](NOTICE.md)

<!-- blinkclip-download:start -->
Current stable version: **1.0.10**. One installer supports Intel and Apple silicon:

[Download BlinkClip-1.0.10-macos-universal.dmg](https://github.com/aexachao/BlinkClip/releases/download/v1.0.10/BlinkClip-1.0.10-macos-universal.dmg)
<!-- blinkclip-download:end -->

## Features

### Clipboard history

- Keeps what you copy: text, images, files, links, and colors.
- A horizontal card panel to browse, multi-select, preview, and edit locally.
- Search and filters by type, source app, and date.

### Collections, groups, and Stack

- Pinboard collections to organize content you reuse.
- BlinkClip Stack: queue items and paste them in order, handy for forms and repetitive work.
- Import and export your own archives (JSON).

### Screenshots and annotation

- ⌘⇧A for a region capture, ⌘⇧E for full-screen capture; both open the annotation editor directly.
- Annotation tools: rectangle, arrow, pen, mosaic, spotlight, text, QR code, OCR, and pin.
- Scrolling capture (long screenshots): automatic scrolling needs macOS Accessibility access; manual scrolling does not. A crop step runs before returning to the editor.
- Pin to screen: keep an image floating on top while you work.
- Local Vision OCR to read text from images; Apple Translation (macOS 15+) is available in **Settings → Screenshots**.

### AI tool integration

- A standalone `blinkclip-mcp` stdio service that lets Claude, Codex, Cursor, and other AI tools use your clipboard history as context.
- Tools to search, read, create, update, and delete items, and to create, rename, delete, and manage collections.

### Sync

- iCloud Drive file sync is optional and **off by default**. Enable it in **Settings → General**; it uses `iCloud Drive/BlinkClip` and syncs history and collections across Macs signed in with the same Apple ID.
- A CloudKit option exists for properly signed builds; live cloud testing is not complete yet.

## Download and install

1. Download `BlinkClip-1.0.10-macos-universal.dmg` from [GitHub Releases](https://github.com/aexachao/BlinkClip/releases/latest).
2. Open the DMG, drag `BlinkClip.app` into `Applications`, and launch it from there.
3. Grant the system permissions it asks for on first use; direct paste into other apps requires macOS Accessibility access.

1.0.10 is publicly available on GitHub Releases: the installer is Developer ID signed and notarized by Apple, and the `macos-universal` package supports both Intel and Apple silicon. See the [latest release](https://github.com/aexachao/BlinkClip/releases/latest) for the download and checksums.

In-app updates are provided by Sparkle: check for updates in **About BlinkClip** and install the signed Universal DMG when prompted. See [Automatic updates](#automatic-updates).

## System requirements

- macOS 14 or later
- Intel or Apple silicon Mac (a Universal installer is provided)
- iCloud Drive sync requires the same Apple ID on each Mac

## Keyboard shortcuts

Default shortcuts, all configurable in **Settings → Shortcuts**:

| Action | Default shortcut |
| --- | --- |
| Open the history panel | ⇧⌘V |
| Stack sequential paste | ⇧⌘C |
| Region screenshot | ⌘⇧A |
| Full-screen screenshot | ⌘⇧E |

## Privacy

- **Local first**: clipboard history, screenshots, and settings stay on your Mac by default. Sync is off by default, and no account is needed.
- Screenshots, logs, and archives may contain personal information; review them before sharing. When reporting an issue, reproduce it with fictional text and temporary files, and never submit real history, accounts, or secrets.

## Build from source

You need macOS 14+, Xcode 26 or newer Command Line Tools (the Swift toolchain), and Python 3. The first build downloads a checksum-pinned Sparkle framework through SwiftPM.

From the repository root, build a Universal app:

```sh
bash replica/scripts/build-app.sh release universal
```

The output is `out/BlinkClip.app`. For a debug build of the current Mac only:

```sh
bash replica/scripts/build-app.sh debug native
```

To package a release-format Universal DMG:

```sh
npm run build:dmg
```

Generating the signed update feed for a stable release requires the release private key configured outside the repository; this command packages locally and does not publish. See the [in-app updates guide](docs/APP_UPDATES.md).

If this Mac has a valid Apple Development identity, set `BLINKCLIP_SIGNING_IDENTITY` to its name or certificate SHA-1 (the legacy `BLINKCLIP_SIGNING_IDENTITY` name still works). Without it, builds use ad-hoc signing. A signing change may require Accessibility access to be granted again.

More development information is in [replica/README.md](replica/README.md) and the [testing notes](replica/TESTING.md).

## Automatic updates

Open **About BlinkClip → Check for Updates** to compare against the latest stable GitHub Release; results are reused for six hours, and you can check again manually. After confirmation, Sparkle downloads the complete Universal DMG inside the app, verifies the Ed25519 signatures on the update feed and archive, installs it, and relaunches BlinkClip. The existing quit flow saves local data before installation.

The check requests only public release information. Offline or failed checks can be retried while clipboard features keep working. Accessibility authorization may need to be enabled again after an update.

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). When reporting a problem, include reproduction steps without private content.

## License

The independently written implementation, tools, documentation, and self-made graphics are open source under the [GNU AGPL-3.0](LICENSE), including its section 13 network-use clause. Third-party components (the capcap screenshot and editor module, the Sparkle update framework) keep their own licenses and copyright notices; see [NOTICE.md](NOTICE.md) for the scope of each part.

## Known limitations

- Cross-app direct paste has not been fully verified; correct insertion at the cursor cannot be guaranteed in every app.
- Live CloudKit sync testing is incomplete, and end-to-end iCloud Drive sync across real devices still needs full validation.
- The screen recording entry exists and is not yet verified as working.
- There are no iPhone or iPad apps yet.
- The current source version is 1.0.10; each installer's actual features are described in its Release notes.
