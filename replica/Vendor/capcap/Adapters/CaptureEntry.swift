// BlinkClip-local adapter (not part of upstream capcap). Keep additive: upstream subtree merges must not conflict.
//
// 为什么需要这个文件：`BlinkClipCapture` 里所有类型都是 internal（`struct ScreenCapturer`、
// `enum ImageEditLauncher`、`class OverlayWindowController`、`CaptureTriggerContext`），
// 而 `BlinkClip` 是另一个 module，跨 module 直接调用会得到
// “cannot find 'ScreenCapturer' in scope”。
//
// 因此这里只加一层薄公共门面：参数全是 Foundation/AppKit 的公开类型
// （NSImage / 闭包 / 不透明草稿盒），不把任何 internal 类型整体 public 化。
// 上游 capcap 文件一个字节都不动。

import AppKit

/// capcap 的挂起编辑草稿（`OverlayWindowController.SuspendedEditDraft`）在这里是不透明盒：
/// `BlinkClip` 模块既构造不了也读不了里面的字段，只能「原样收下、下次触发时原样交回」。
///
/// 对应上游 `AppDelegate.suspendedEditDraft` 的语义（P1-C）。
public final class SuspendedEditDraftBox {
    let draft: OverlayWindowController.SuspendedEditDraft

    init(_ draft: OverlayWindowController.SuspendedEditDraft) {
        self.draft = draft
    }

    /// 草稿所在显示器是否还在。拔掉外接屏后草稿无法复原——调用方据此决定是否丢弃，
    /// 否则会拿到一个「激活了但什么都没显示」的控制器，把热键永久堵住。
    var isRestorable: Bool {
        NSScreen.screens.contains { screen in
            if let displayID = draft.screenDisplayID,
               let screenID = screen.deviceDescription[
                   NSDeviceDescriptionKey("NSScreenNumber")
               ] as? CGDirectDisplayID {
                return screenID == displayID
            }
            return screen.frame == draft.screenFrame
        }
    }
}

public enum CaptureEntry {
    /// 全屏：抓取鼠标所在那一块屏幕，直接进编辑器。
    /// 注意：全屏**不读**「截图后行为」偏好，始终走编辑器（`ImageEditLauncher` 的上游默认）。
    /// 设置面板的脚注也写了这一点，避免用户以为全屏会跟着改。
    /// 返回 nil 表示抓屏失败（缺少「屏幕录制」授权，或 2 秒超时——见 `captureFullScreen`）。
    /// 调用方拿到 nil 会走 `windowHider.restore()` 并把窗口还回去。
    @discardableResult
    public static func presentFullScreenEditor(
        onFocusReturn: @escaping () -> Void,
        onSuspend: @escaping (SuspendedEditDraftBox) -> Void = { _ in },
        onComplete: @escaping (NSImage?) -> Void
    ) -> AnyObject? {
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let image = captureFullScreen(rect: CGDisplayBounds(displayID), screen: screen)
        else { return nil }
        return ImageEditLauncher.launch(
            generatedImage: image,
            source: .fullScreen,
            onRequestFocusReturn: onFocusReturn,
            onSuspend: { draft in onSuspend(SuspendedEditDraftBox(draft)) },
            onComplete: onComplete
        )
    }

    /// 区域：拉起选区遮罩（十字光标 / 窗口吸附），松手后按设置面板里选的
    /// 「截图后行为」执行（默认 `.edit` → 进标注编辑器）。
    /// 返回 nil 表示遮罩没能启动。
    @discardableResult
    public static func presentRegionEditor(
        onFocusReturn: @escaping () -> Void,
        onSuspend: @escaping (SuspendedEditDraftBox) -> Void = { _ in },
        onComplete: @escaping (NSImage?) -> Void
    ) -> AnyObject? {
        let controller = OverlayWindowController(
            postCaptureAction: BlinkClipScreenshotSettings.postCaptureAction.capcapPostCaptureAction,
            triggerContext: CaptureTriggerContext(source: .keyboardShortcut),
            onFirstFramePresented: nil,
            onRecordingSelection: { _, _ in },
            onRequestFocusReturn: onFocusReturn,
            onSuspend: { draft in onSuspend(SuspendedEditDraftBox(draft)) },
            onComplete: onComplete
        )
        controller.activate()
        return controller
    }

    /// 恢复挂起的编辑草稿（对应上游 `AppDelegate.resumeSuspendedEditIfAvailable()`）。
    ///
    /// 走 `OverlayWindowController(suspendedDraft:)` 这条 init：它不再抓屏，
    /// 而是用草稿里冻结的桌面快照 + 编辑器状态重建遮罩和编辑器。
    /// 返回 nil 表示草稿所在显示器已经不在，调用方应丢弃草稿、按新截图继续。
    @discardableResult
    public static func resumeSuspendedEditor(
        draft: SuspendedEditDraftBox,
        onFocusReturn: @escaping () -> Void,
        onSuspend: @escaping (SuspendedEditDraftBox) -> Void = { _ in },
        onComplete: @escaping (NSImage?) -> Void
    ) -> AnyObject? {
        guard draft.isRestorable else { return nil }
        let controller = OverlayWindowController(
            suspendedDraft: draft.draft,
            onRecordingSelection: { _, _ in },
            onRequestFocusReturn: onFocusReturn,
            onSuspend: { next in onSuspend(SuspendedEditDraftBox(next)) },
            onComplete: onComplete
        )
        controller.activate()
        return controller
    }

    // MARK: - 全屏抓取

    /// 全屏抓取的等待上限（秒）。`ScreenCapturer.capture` 内部是 `DispatchSemaphore.wait()`
    /// 在调用线程上同步等 ScreenCaptureKit，而这里就在主线程——SCK 卡住会把整个 UI 挂起。
    /// 超时该调用返回 nil，落到 `presentFullScreenEditor` 的 nil 分支。
    private static let captureTimeout: TimeInterval = 2

    /// 全屏抓取：先用 BlinkClip 自己的可见窗口号做排除（面板已收起，但设置窗/预览窗仍可能挡在前面）。
    /// 排除失败（窗口在抓屏瞬间消失、SCK 列不出该窗口等）时回退到不排除的调用——
    /// 此时面板已不可见，回退结果依然正确，不能让整次截图失败。
    /// 两次调用都必须带 `timeout`，否则回退这一发又可能把主线程挂死。
    private static func captureFullScreen(rect: CGRect, screen: NSScreen) -> NSImage? {
        let excludedWindowNumbers: [CGWindowID] = NSApp.windows.compactMap { window in
            guard window.isVisible else { return nil }
            let number = window.windowNumber
            return number > 0 ? CGWindowID(number) : nil
        }
        if !excludedWindowNumbers.isEmpty,
           let image = ScreenCapturer.capture(rect: rect,
                                              screen: screen,
                                              excludingWindowNumbers: excludedWindowNumbers,
                                              timeout: captureTimeout) {
            return image
        }
        return ScreenCapturer.capture(rect: rect, screen: screen, timeout: captureTimeout)
    }
}
