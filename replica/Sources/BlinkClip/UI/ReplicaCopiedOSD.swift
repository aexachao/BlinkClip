import AppKit
import BlinkClipCore

/// 轻提示（toast）的调用入口：复制 / 暂停 / 继续 / 截图已复制。
///
/// 四种 toast 现在都是**同一个组件**（`ReplicaToast`）的同一套样式：
/// 128×128pt 深色 HUD 小盘、上图下字、屏幕底部居中、停留 1.3s + 淡出 0.2s、
/// 不抢焦点、不入图、不叠加。图标与文案一律**白色**，语义只靠符号区分。
/// 本文件只负责把各自的图标与文案拼成 `ReplicaToast.Content`，不再自己建窗口。
///
/// 文案一律来自 `ReplicaToastCopy`（三语齐全）；暂停 toast 不再有第二行小字：
/// 定时信息直接并进正文（「已暂停记录剪贴板 · 至 14:30」）。
@MainActor
enum ReplicaCopiedOSD {
    /// 旧版用来决定暂停 toast 副标题的暂停态探针。
    ///
    /// 单行 toast 不再需要副标题，所以这里已经没人读；`AppMain` 仍会写入（那条
    /// 写入点不在本单范围内，暂不改动）。保留声明只为不打断那个调用点。
    static var pauseStatus: (() -> Bool?)?

    static func showCopied(enableDirectPaste: (() -> Void)? = nil) {
        // 有动作时整块可点（手型光标就是提示），不再额外加一行「点击启用直接粘贴」的小字。
        ReplicaToast.shared.present(.init(
            symbolName: "checkmark",
            text: ReplicaToastCopy.text(.copied),
            action: enableDirectPaste))
    }

    static func showPaused(resumeDate: Date?) {
        let text: String
        if let resumeDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            // 定时信息并进同一行，避免「暂停」这句话在第二行再说一遍。
            text = ReplicaToastCopy.pastePaused(until: formatter.string(from: resumeDate))
        } else {
            text = ReplicaToastCopy.text(.pastePaused)
        }
        ReplicaToast.shared.present(.init(symbolName: "pause", text: text))
    }

    static func showResumed() {
        ReplicaToast.shared.present(.init(symbolName: "arrow.clockwise",
                                          text: ReplicaToastCopy.text(.pasteResumed)))
    }

    /// 截图成功（已落库并写进剪贴板）后的可见反馈；文案取 `ReplicaToastCopy`。
    static func showScreenshotCopied() {
        // 与「已复制」同一个裸对勾：四条 toast 都用无底衬的线条符号。
        ReplicaToast.shared.present(.init(symbolName: "checkmark",
                                          text: ReplicaToastCopy.text(.screenshotCopied)))
    }

    /// 收起当前 toast：新的截图开始前必须调用，否则它会进底图（兜底，真正的
    /// 保证是 `ReplicaToastPanel.sharingType` 恒为 `.none`）。
    static func hideToast() {
        ReplicaToast.shared.hide()
    }
}
