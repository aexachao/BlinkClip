import AppKit
import SwiftUI

/// Selects the card before AppKit dispatches the event that opens its context menu.
/// The view remains passive so existing clicks, editing and dragging keep their targets.
@MainActor
struct ReplicaCardContextSelection: NSViewRepresentable {
    let onContextMenu: () -> Void

    func makeNSView(context: Context) -> EventView {
        let view = EventView()
        view.onContextMenu = onContextMenu
        view.installMonitor()
        return view
    }

    func updateNSView(_ view: EventView, context: Context) {
        view.onContextMenu = onContextMenu
    }

    static func dismantleNSView(_ view: EventView, coordinator: ()) {
        view.removeMonitor()
        view.onContextMenu = nil
    }

    final class EventView: NSView {
        var onContextMenu: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// 右键是否落在**这张卡自己的 bounds** 内。
        ///
        /// 不能用 `visibleRect`：卡片背景挂在 `NSHostingView` 里，SwiftUI 的宿主层级没有
        /// 裁剪视图，`visibleRect` 会返回“整条卡片行在卡片坐标系里的投影”（实测 1680×272，
        /// 远大于卡片自己的 240×240），于是同一行每张卡的后台监视器都会命中同一个点。
        /// 多个监视器依次执行时，最后一张卡决定选区——右键目标因此不确定（U25：
        /// 右键一张未选中的空文本卡，菜单「拷贝」复制出的是另一条 `OTHER 222`；
        /// 另一次右键选区跳到第三张卡）。这里只认自己的 bounds，一张卡最多命中一次。
        func ownsContextEvent(_ event: NSEvent) -> Bool {
            guard !isHiddenOrHasHiddenAncestor, let window, event.window === window,
                  event.type == .rightMouseDown || event.modifierFlags.contains(.control) else {
                return false
            }
            return bounds.contains(convert(event.locationInWindow, from: nil))
        }

        /// 命中本卡时先把光标下的条目设为选中，再由 AppKit 弹出菜单。
        /// 返回 true 表示这次右键属于本卡（同一行其它卡不会重复处理）。
        @discardableResult
        func handleContextEvent(_ event: NSEvent) -> Bool {
            guard ownsContextEvent(event) else { return false }
            onContextMenu?()
            return true
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    _ = self?.handleContextEvent(event)
                    return event
                }
            }
        }

        func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { MainActor.assumeIsolated { removeMonitor() } }
    }
}
