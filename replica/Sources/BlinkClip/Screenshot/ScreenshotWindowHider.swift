import AppKit
import os

/// 截图底图创建前临时收起剪贴板历史面板及其浮层，不关闭窗口。
/// 设置、关于、普通编辑窗口及其 native sheet 仍须可供截图。
///
/// 主历史面板由 ReplicaUIController.loadPanel 明确设置的 identifier 识别；
/// Stack 是 showStack 创建的独立私有 ReplicaStackPanel，没有 identifier，按精确类型名识别。
/// 搜索建议通过 addChildWindow 挂在主面板上，由父窗口收起，不单独恢复过期子窗口。
@MainActor
final class ScreenshotWindowHider {
    /// 一次收起留下的现场，`restore()` 时按记录逐条还回去。
    private struct HiddenWindow {
        let window: NSWindow
        /// 收起前是否是 key window。用于把键盘焦点也还回去（见 `restore()`）。
        let wasKey: Bool
        /// 原 delegate。`ReplicaPanel` 把 delegate 设成自己，而它的 `windowDidResignKey`
        /// 会调用 `ReplicaUIController.hidePanel()`（0.2s 动画 + `close()`）——
        /// 若不管，`orderOut` 引起的 resign key 会把「临时移出屏幕」变成「永久关闭」，
        /// 那就再也放不回来了。因此收起期间先摘掉 delegate，窗口真正离屏后再装回。
        let delegate: NSWindowDelegate?
    }

    private static let logger = Logger(subsystem: "com.chrisli.blinkclip",
                                       category: "screenshot")

    private var hiddenWindows: [HiddenWindow] = []

    // MARK: - 收起

    /// 只收起可见的剪贴板面板并记录现场。
    ///
    /// 可重复调用：已经收起过时保留第一次的记录。万一某次结束回调丢了，记录还在，
    /// 下一次截图结束时仍然能把窗口还回去（不会把面板永久留在屏幕外）。
    func hideVisibleBlinkClipWindows() {
        guard hiddenWindows.isEmpty else { return }
        for window in NSApp.windows {
            guard window.isVisible,
                  window.parent == nil,
                  Self.isClipboardPanel(window)
            else { continue }
            let entry = HiddenWindow(window: window,
                                     wasKey: window.isKeyWindow,
                                     delegate: window.delegate)
            // 先摘 delegate 再 orderOut：见 `HiddenWindow.delegate` 的注释。
            window.delegate = nil
            hiddenWindows.append(entry)
            window.orderOut(nil)
        }
        if !hiddenWindows.isEmpty {
            let names = hiddenWindows
                .map { String(describing: type(of: $0.window)) }
                .joined(separator: ", ")
            Self.logger.debug("截图前收起窗口: \(names, privacy: .public)")
        }
    }

    /// 把收起时摘掉的 delegate 装回去。窗口已经离屏，此时它的 delegate 回调不会再
    /// 因为「离开屏幕」而触发关窗。由调用方在收起之后的下一轮主线程调用。
    func reattachDelegates() {
        reattachDelegates(hiddenWindows)
    }

    // MARK: - 放回

    /// 只恢复「原本可见」的那些窗口（记录里就是全部），重复调用是安全的。
    func restore() {
        guard !hiddenWindows.isEmpty else { return }
        let entries = hiddenWindows
        hiddenWindows.removeAll()
        reattachDelegates(entries)
        for entry in entries {
            guard !entry.window.isVisible else { continue }
            entry.window.orderFront(nil)
            // 原来就是 key window 的话把键盘焦点也还回去；但只在 App 仍然是当前 App 时做，
            // 避免把焦点从用户正在用的其他 App 那里抢回来（焦点归还由
            // `ScreenshotFocusRestorer` 负责）。
            if entry.wasKey, NSApp.isActive, !entry.window.isKeyWindow {
                entry.window.makeKey()
            }
        }
        Self.logger.debug("截图结束，恢复窗口 \(entries.count) 个")
    }

    private func reattachDelegates(_ entries: [HiddenWindow]) {
        for entry in entries where entry.window.delegate == nil {
            entry.window.delegate = entry.delegate
        }
    }

    // MARK: - 识别

    private static func isClipboardPanel(_ window: NSWindow) -> Bool {
        guard window is NSPanel else { return false }
        return window.identifier == NSUserInterfaceItemIdentifier("blinkclip-panel")
            || String(describing: type(of: window)) == "ReplicaStackPanel"
    }
}
