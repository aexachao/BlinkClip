// capcap 历史读写 → BlinkClip `ClipboardStore` 的适配层实现（P1-C）。
//
// capcap 的 `HistoryManager`（`Vendor/capcap/Adapters/HistoryManagerBridge.swift`）只保留上游
// 调用表面，真正的存储读写在这里；因此 `BlinkClipCapture` 不需要依赖 `BlinkClipCore`。
//
// 线程：`ClipboardStore` 是 `@MainActor`。capcap 的写入点（`PinLauncher` / `ImageMerge` /
// `UploadManager` 的完成回调）和读取点（编辑器里的 keyDown 监视器）都在主线程。
// - 万一写入发生在后台线程：异步切回主线程，不阻塞调用方（写是 fire-and-forget）。
// - 万一读取发生在后台线程：退化成空值（与 P1-A 桩行为一致）。同步跨线程取值会和
//   主线程互等，风险大于收益，而且当前不存在这条调用路径。

import AppKit
import os
import BlinkClipCapture
import BlinkClipCore

/// `BlinkClipHistoryBackend` 的 BlinkClip 实现：图片条目就是 `ClipboardStore` 里的 `.image` 条目。
final class ScreenshotHistoryBridge: BlinkClipHistoryBackend {
    /// 条目定位符 scheme。capcap 只把 `HistoryEntry.fileURL` 当身份键
    /// （`historyEditorDrafts[fileURL]`），不读文件，所以这里放虚拟 URL。
    private static let locatorScheme = "blinkclip-history"
    private static let locatorBase = URL(string: "blinkclip-history://image/")!
    /// 「上一张/下一张」翻图时最多回溯多少条。条目只是轻量的定位符，
    /// 图片仍按需解码；上限只为避免几万条历史一次性排序/映射。
    private static let imageEntryLimit = 200
    /// 一张图片可能有多种表示；按这个顺序挑第一个能解码的。
    private static let imagePayloadPreference = ["public.png", "public.tiff", "public.jpeg",
                                                 "public.heic", "com.compuserve.gif", "com.apple.icns"]

    /// P1-C 审计 M1：写入失败必须有痕迹。category 与 BlinkClip 其他诊断日志一致。
    private static let logger = Logger(subsystem: "com.chrisli.blinkclip",
                                       category: "screenshot")

    private let store: ClipboardStore

    init(store: ClipboardStore) {
        self.store = store
    }

    // MARK: - 写入

    func blinkclipAddImagePNG(_ pngData: Data) {
        performOnMain { [store] in
            // 与 `ScreenshotCoordinator.complete()` 保持同一种条目形状：
            // kind = .image，payload 里放一份 PNG。
            let item = ClipboardItem(kind: .image, plainText: nil, sourceName: ReplicaBrand.name,
                                     payloads: ["public.png": pngData])
            Self.add(item, kind: "image", to: store)
        }
    }

    func blinkclipAddColor(hex: String) {
        performOnMain { [store] in
            // 色块预览由 ClipboardStore 从明文 payload 里解析（ColorPreviewMetadataGenerator），
            // 所以这里同时给 plainText 和 `public.utf8-plain-text`。
            let item = ClipboardItem(title: hex, kind: .color, plainText: hex, sourceName: ReplicaBrand.name,
                                     payloads: ["public.utf8-plain-text": Data(hex.utf8)])
            Self.add(item, kind: "color", to: store)
        }
    }

    func blinkclipAddText(_ text: String) {
        performOnMain { [store] in
            let item = ClipboardItem(kind: .text, plainText: text, sourceName: ReplicaBrand.name,
                                     payloads: ["public.utf8-plain-text": Data(text.utf8)])
            Self.add(item, kind: "text", to: store)
        }
    }

    func blinkclipAddFileReferences(_ urls: [URL]) {
        // `ClipboardItem.payloads` 是 `[UTI: Data]`，同一 UTI 只能放一个值，
        // 所以多选文件只能保留第一个引用。capcap 的「多文件历史条目」P1 不覆盖。
        guard let first = urls.first else { return }
        performOnMain { [store] in
            let item = ClipboardItem(kind: .files, plainText: first.path, sourceName: ReplicaBrand.name,
                                     payloads: ["public.file-url": Data(first.absoluteString.utf8)])
            Self.add(item, kind: "file-references", to: store)
        }
    }

    // MARK: - 写辅助

    /// 写一条历史。失败必须留下诊断日志：旧的 `try?` 会把错误静默吞掉，用户只看到
    /// 「截图没进历史」却没有任何线索。`kind` 标明是哪一类写入（image / color / text /
    /// file-references），便于在统一日志里定位。
    @MainActor
    private static func add(_ item: ClipboardItem, kind: String, to store: ClipboardStore) {
        do {
            _ = try store.add(item)
        } catch {
            logger.error("历史写入失败 kind=\(kind, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - 读取

    func blinkclipHasFavoriteEntries() -> Bool {
        // capcap 的「收藏」在 BlinkClip 里最接近的概念是「被放进某个 Pinboard 的条目」。
        // 只用于 `Defaults.isHistoryCacheAvailable`，不驱动任何 UI。
        guard Thread.isMainThread else { return false }
        return MainActor.assumeIsolated {
            store.items.contains { !$0.pinboardIDs.isEmpty && !$0.isDeleted }
        }
    }

    /// `ClipboardStore.search(query:kind:)` 在 `pinboardID == nil`、空查询时
    /// 按 `createdAt` 倒序返回「在历史里且未删除」的条目 —— 正好是 capcap 需要的顺序
    /// （`offset: 1` = 更旧的一张）。
    func blinkclipImageEntries() -> [BlinkClipHistoryImageEntry] {
        guard Thread.isMainThread else { return [] }
        return MainActor.assumeIsolated {
            store.search(query: "", kind: .image)
                .prefix(Self.imageEntryLimit)
                .map { BlinkClipHistoryImageEntry(locator: Self.locator(for: $0.id), createdAt: $0.createdAt) }
        }
    }

    func blinkclipImage(forLocator locator: URL) -> NSImage? {
        guard Thread.isMainThread,
              locator.scheme == Self.locatorScheme,
              let id = UUID(uuidString: locator.lastPathComponent)
        else { return nil }
        return MainActor.assumeIsolated {
            guard let item = store.items.first(where: { $0.id == id }) else { return nil }
            for type in Self.imagePayloadPreference {
                if let data = item.payloads[type], let image = NSImage(data: data) {
                    return image
                }
            }
            return nil
        }
    }

    // MARK: - 辅助

    private static func locator(for id: UUID) -> URL {
        locatorBase.appendingPathComponent(id.uuidString)
    }

    /// 主线程直接执行；后台线程异步切回主线程再执行一次（递归进入时必然在主线）。
    private func performOnMain(_ body: @escaping @MainActor () -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.performOnMain(body) }
            return
        }
        MainActor.assumeIsolated { body() }
    }
}
