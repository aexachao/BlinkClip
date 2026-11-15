import AppKit
import BlinkClipCore
import BlinkClipObjC

@main
struct PackagedResourcesHarness {
    @MainActor static func main() {
        _ = NSApplication.shared
        let background = PRPanelGlassBackground(frame: NSRect(x: 0, y: 0, width: 80, height: 60))
        background.cornerRadius = 26
        guard let effect = background.subviews.first, background.hitTest(.zero) == nil else {
            fputs("Invalid panel background hierarchy\n", stderr)
            exit(1)
        }
        if #available(macOS 26, *) {
            guard NSStringFromClass(type(of: effect)) == "NSGlassEffectView" else {
                fputs("Missing native glass effect\n", stderr)
                exit(1)
            }
        } else {
            guard let effect = effect as? NSVisualEffectView, effect.material == .menu,
                  effect.blendingMode == .behindWindow, effect.state == .active else {
                fputs("Invalid older-system visual effect fallback\n", stderr)
                exit(1)
            }
        }
        let query = SearchQuery.predicateString([.text("fixture")])
        let usesDescription = ProcessInfo.processInfo.isOperatingSystemAtLeast(
            .init(majorVersion: 26, minorVersion: 4, patchVersion: 0))
        guard query.contains("contentDescription") == usesDescription else {
            fputs("Spotlight query uses fields unavailable on this system\n", stderr)
            exit(1)
        }
        for directPaste in [false, true] {
            for dark in [false, true] {
                guard let image = SettingsIllustrations.image(directPaste: directPaste, dark: dark),
                      image.size.width > 0, image.size.height > 0 else {
                    fputs("Missing packaged settings illustration\n", stderr)
                    exit(1)
                }
            }
        }
        let settingsKey = "settings.general.title"
        guard SettingsLocalization.text(settingsKey) != settingsKey,
              String(localized: PreviewLocalization.generalUntitled()) != "general.untitled",
              String(localized: UnavailablePreviewLocalization.previewUnavailableTitle()) != "preview.unavailable.title" else {
            fputs("Missing packaged localization\n", stderr)
            exit(1)
        }
        // Per-action feedback audio ships with the Core bundle; a missing file would
        // silently degrade to no tone, so packaging asserts both resolve from it.
        for feedback in [SoundEffects.Feedback.copy, .cut, .paste] {
            guard let url = SoundEffects.bundledURL(for: feedback),
                  url.deletingLastPathComponent().lastPathComponent == "BlinkClip_BlinkClipCore.bundle",
                  let player = NSSound(contentsOf: url, byReference: true),
                  player.duration > 0.3, !player.isPlaying else {
                fputs("Missing packaged feedback audio: \(feedback)\n", stderr)
                exit(1)
            }
        }
        guard SoundEffects.bundledURL(for: .copy) == SoundEffects.bundledURL(for: .cut),
              SoundEffects.bundledURL(for: .copy)?.lastPathComponent == SoundEffects.copySoundFileName,
              SoundEffects.bundledURL(for: .paste)?.lastPathComponent == SoundEffects.pasteSoundFileName else {
            fputs("Packaged feedback audio mapping is wrong\n", stderr)
            exit(1)
        }
        for kind in [PasteboardContentKind.files, .color, .text, .link, .unknown, .image] {
            let image = StackCategoryIcons.image(for: kind)
            let bitmaps = image.representations.compactMap { $0 as? NSBitmapImageRep }
            guard image.isTemplate, image.size == NSSize(width: 20, height: 20),
                  Set(bitmaps.map(\.pixelsWide)) == [20, 40] else {
                fputs("Missing Stack image scale or template metadata\n", stderr)
                exit(1)
            }
            var coverage: [Int: Int] = [:]
            for bitmap in bitmaps {
                var visiblePixels = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in 0..<bitmap.pixelsWide {
                        if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
                            visiblePixels += 1
                        }
                    }
                }
                guard visiblePixels > 0 else {
                    fputs("Blank Stack image\n", stderr)
                    exit(1)
                }
                coverage[bitmap.pixelsWide] = visiblePixels
            }
            guard coverage[40]! > coverage[20]! * 3 else {
                fputs("Stack retina image was not rendered at double resolution\n", stderr)
                exit(1)
            }
        }
        print("{\"passed\":true,\"settings_illustrations\":4,\"stack_kinds\":6,\"stack_scales\":[1,2],\"localization\":true,\"background\":true,\"spotlight_version_gate\":true,\"build_directory_available\":false}")
    }
}
