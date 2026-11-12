// BlinkClip-local adapter (not part of upstream capcap). Keep additive: upstream subtree merges must not conflict.
//
// 为什么这个文件存在：vendored capcap 的 Capture / Editor / Upload / ImageMerge 会调用
// `HistoryManager.shared`，而上游 `Capture/HistoryManager.swift`（以及它拖进来的
// HistoryPanelController / HistorySearch / HistoryPreviewLoader / Trigger 整条历史的 UI 栈）
// 不在 vendoring 范围内。
//
// P1-C：这里不再是空桩。`HistoryManager` 保留与上游一致的调用表面，但把读写转发给
// 由 BlinkClip 侧注入的 `BlinkClipHistoryBackend`；真实实现见
// `Sources/BlinkClip/Screenshot/ScreenshotHistoryBridge.swift`，背后是 BlinkClip 的 `ClipboardStore`。
//
// 为什么不在这里 `import BlinkClipCore`：`BlinkClipCapture` 这个 target 目前没有任何依赖
// （Package.swift 里 `.target(name: "BlinkClipCapture", ...)` 没有 dependencies），
// 与其为了一个存储引用改 Package.swift、把整个 BlinkClipCore 塞进采集 target，
// 不如在这里只声明协议，实现留在 BlinkClip 模块（BlinkClip 已经依赖 BlinkClipCore）。
//
// 未配置 backend 时保持 P1-A 的空实现行为（写 no-op / 读恒空），
// 这样没接线到的路径不会因为半配置状态而崩。

import AppKit
import Foundation

/// capcap 历史条目在 BlinkClip 存储里的定位符。
///
/// `HistoryEntry.fileURL` 在 vendored 代码里只当身份键用
/// （`OverlayWindowController.historyEditorDrafts[fileURL]`），从不读文件，
/// 所以这里放一个稳定的虚拟 URL（由 BlinkClip 侧编码 ClipboardItem 的 uuid）。
public struct BlinkClipHistoryImageEntry {
    public let locator: URL
    public let createdAt: Date

    public init(locator: URL, createdAt: Date) {
        self.locator = locator
        self.createdAt = createdAt
    }
}

/// BlinkClip 侧要实现的历史后端。
///
/// 方法统一带 `blinkclip` 前缀，避免与 capcap 既有符号重名；
/// 类型只用 Foundation / AppKit，保证跨 module 可用。
public protocol BlinkClipHistoryBackend: AnyObject {
    func blinkclipAddImagePNG(_ pngData: Data)
    func blinkclipAddColor(hex: String)
    func blinkclipAddText(_ text: String)
    func blinkclipAddFileReferences(_ urls: [URL])
    func blinkclipHasFavoriteEntries() -> Bool
    /// 按时间倒序（最新在前）返回图片条目。capcap 编辑器用 `offset: 1` 表示「上一张」，
    /// 也就是往更旧的条目走，因此顺序必须是倒序。
    func blinkclipImageEntries() -> [BlinkClipHistoryImageEntry]
    func blinkclipImage(forLocator locator: URL) -> NSImage?
}

/// capcap 交付的是 `NSImage`；历史库和剪贴板都需要一份明确的位图表示。
///
/// 单一实现：`ScreenshotCoordinator.complete()` 也用它，避免「往历史里写」和
/// 「写剪贴板」两条路各自编码一次。
public enum BlinkClipImageEncoding {
    public static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// Mirrors `HistoryEntryKind` from the excluded `Capture/HistoryManager.swift`.
/// Declared here only because `HistoryEntry` needs it. No vendored file switches
/// on it.
enum HistoryEntryKind {
    case image
    case video
    case color(hex: String)
    case text(String)
    case files([URL])
}

/// Mirrors `HistoryEntry` from the excluded `Capture/HistoryManager.swift`.
/// Vendored code only reads `fileURL`.
struct HistoryEntry {
    let fileURL: URL
    let createdAt: Date
    let kind: HistoryEntryKind
    let cloudURL: URL?
}

/// 上游 `HistoryManager` 的替身，转发给注入的 `BlinkClipHistoryBackend`。
///
/// 注入方式刻意保持「一次性显式配置」：没有可变全局开关、没有静态 setter 滥用，
/// `configure(backend:)` 由 `ScreenshotCoordinator.start()` 调用一次。
public final class HistoryManager {
    static let shared = HistoryManager()

    private var backend: BlinkClipHistoryBackend?

    private init() {}

    /// 由 `ScreenshotCoordinator` 在启动时调用一次。未调用时全部方法保持空实现。
    public static func configure(backend: BlinkClipHistoryBackend) {
        shared.backend = backend
    }

    /// 仅用于自检/日志；vendored 代码不读它。
    var isConfigured: Bool { backend != nil }

    // MARK: - Writes

    func add(image: NSImage, cloudURL: URL? = nil) {
        // `cloudURL` 没有落点：BlinkClip 的 iCloud 同步是整库级别的，条目上没有 per-item 云端 URL。
        // P1 不覆盖。
        _ = cloudURL
        guard let backend, let data = BlinkClipImageEncoding.pngData(from: image) else { return }
        backend.blinkclipAddImagePNG(data)
    }

    func addColor(hex: String) {
        backend?.blinkclipAddColor(hex: hex)
    }

    func addText(_ text: String) {
        backend?.blinkclipAddText(text)
    }

    func addFileReferences(_ urls: [URL]) {
        backend?.blinkclipAddFileReferences(urls)
    }

    // MARK: - Reads

    /// capcap 的「收藏」在 BlinkClip 里最接近的概念是「放进某个 Pinboard 的条目」，
    /// 语义由后端决定（见 ScreenshotHistoryBridge）。
    func hasFavoriteEntries() -> Bool {
        backend?.blinkclipHasFavoriteEntries() ?? false
    }

    func imageEntries() -> [HistoryEntry] {
        guard let backend else { return [] }
        return backend.blinkclipImageEntries().map { entry in
            HistoryEntry(fileURL: entry.locator, createdAt: entry.createdAt, kind: .image, cloudURL: nil)
        }
    }

    func image(for entry: HistoryEntry) -> NSImage? {
        backend?.blinkclipImage(forLocator: entry.fileURL)
    }
}
