import AppKit
import BlinkClipCore
import QuartzCore
import SwiftUI

/// Recovered local OSD presentation, including the copy-only enable-direct-paste action.
@MainActor
enum ReplicaCopiedOSD {
    // The original published pause flag is the inverse of the actual monitor's poll timer state.
    static var pauseStatus: (() -> Bool?)?
    static func showCopied(enableDirectPaste: (() -> Void)? = nil) {
        show(symbolName: "checkmark", title: String(localized: PreviewLocalization.generalCopied()),
             subtitle: enableDirectPaste == nil ? nil : String(localized: PreviewLocalization.generalEnableDirectPaste()),
             action: enableDirectPaste)
    }

    static func showPaused(resumeDate: Date?) {
        let subtitle: String?
        if let resumeDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            subtitle = String(localized: PreviewLocalization.untilTime(formatter.string(from: resumeDate)))
        } else if let paused = pauseStatus?() {
            subtitle = ReplicaBrand.replacingName(in: String(localized: paused
                ? PreviewLocalization.generalPaused() : PreviewLocalization.generalActionPausePaste()))
        } else { subtitle = nil }
        show(symbolName: "pause", title: ReplicaBrand.replacingName(in: String(localized: PreviewLocalization.generalPastePaused())),
             subtitle: subtitle)
    }

    static func showResumed() {
        show(symbolName: "arrow.clockwise", title: ReplicaBrand.replacingName(in: String(localized: PreviewLocalization.generalPasteResumed())))
    }

    /// W2：截图成功（已落库并写剪贴板）后的可见反馈。
    /// 文案由调用方传入三语表里的那一条，与设置页共用 `ScreenshotSettingsCopy`。
    static func showScreenshotCopied(_ title: String) {
        ReplicaCaptureToast.shared.present(title: title)
    }

    /// 收起截图成功 toast：新的截图开始前必须调用，否则它会进底图。
    static func hideScreenshotCopied() {
        ReplicaCaptureToast.shared.hide()
    }

    private static func show(symbolName: String, title: String?, subtitle: String? = nil,
                             action: (() -> Void)? = nil) {
        // The original controller enqueues its presenter on MainActor rather than presenting inline.
        Task { @MainActor in
            let content = NSHostingView(rootView: Content(symbolName: symbolName, title: title, subtitle: subtitle, action: action))
            let effect = NSVisualEffectView()
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 20
            effect.material = .init(rawValue: 13)!
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.autoresizingMask = [.width, .height]
            content.translatesAutoresizingMaskIntoConstraints = false
            effect.addSubview(content)
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: effect.topAnchor),
                content.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                content.widthAnchor.constraint(equalToConstant: 200),
                content.heightAnchor.constraint(equalToConstant: 200)
            ])
            let window = NSWindow(contentRect: .zero, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.level = .init(rawValue: 1000)
            window.backgroundColor = .clear
            window.contentView = effect
            window.layoutIfNeeded()
            window.center()
            if let screen = NSScreen.main {
                window.setFrameOrigin(.init(x: window.frame.origin.x, y: screen.frame.minY + 140))
            }
            window.orderFrontRegardless()
            // Each presentation owns its window through both callbacks; an older fade cannot hide a newer OSD.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.5
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    context.allowsImplicitAnimation = true
                    window.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated { window.orderOut(nil) }
                }
            }
        }
    }

    private struct Content: View {
        let symbolName: String
        let title: String?
        let subtitle: String?
        let action: (() -> Void)?

        var body: some View {
            VStack(spacing: 16) {
                Image(systemName: symbolName)
                    .renderingMode(.template)
                    .font(.system(size: 86))
                VStack(spacing: 4) {
                    if let title { Text(title).font(.title) }
                    if let subtitle { Text(subtitle).font(.body) }
                }
            }
            .foregroundStyle(.secondary)
            .onTapGesture {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { action?() }
            }
        }
    }
}

// MARK: - 截图成功 toast（W2）

/// 截图落库并写剪贴板成功后弹的轻提示：屏幕上方居中的一颗小胶囊，
/// 「已复制截图 / Screenshot copied / 截圖已複製」，停留 1.3s 再 0.2s 淡出。
///
/// 与上面 `show(...)` 的 200×200 OSD 同一套视觉语言（毛玻璃 + SF Symbol + 文字），
/// 但有三个不同的硬约束，所以单列一个复用实例：
/// - **不叠加**：连续快速截图复用同一个 window，只重置计时，不新建第二个 toast；
/// - **不抢焦点**：`NSPanel` + `.nonactivatingPanel` + `ignoresMouseEvents`，
///   `orderFrontRegardless()` 不激活 App，`canBecomeKey` / `canBecomeMain` 恒为 false；
/// - **不入自己的截图**：`sharingType = .none`；并且截图流程开始前由
///   `ScreenshotCoordinator.present` 先收起（H1 的排除逻辑只排除会话自有的
///   遮罩/HUD，这个 toast 不属于那次会话，靠「先收起」保证不进底图）。
///
/// 与「播放操作提示音」无关：声音偏好和反馈音映射不在这里判，也不受这里影响。
@MainActor
final class ReplicaCaptureToast {
    static let shared = ReplicaCaptureToast()

    /// 完全显示（不含淡出）的停留时长；任务要求 1.2–1.5s。
    static let holdDuration: TimeInterval = 1.3
    /// 淡出时长，从 `holdDuration` 末尾开始。
    static let fadeDuration: TimeInterval = 0.2
    /// 距屏幕上缘（菜单栏以下）的留白。
    static let topInset: CGFloat = 16

    /// 面板创建过一次就一直复用（窗口号不变，窗口服务器不会累积残留窗口）。
    private var panel: CaptureToastPanel?
    /// 「下一次收起」的计时；每次 `present` 都取消旧的重排一个新的。
    private var dismissWorkItem: DispatchWorkItem?
    /// 连续截图的次数，测试用来确认是「重置」而不是「再开一个」。
    private(set) var presentationCount = 0
    /// 当前文案；测试读它核对三语。
    private(set) var currentTitle: String?
    /// 每次 `present` 递增。淡出动画的 completion 只在「还是同一代」时才真的
    /// orderOut——否则一次还没结束的淡出会把紧接着弹出来的新 toast 收掉。
    private var generation = 0

    /// 供 harness 断言窗口属性（级别、`sharingType`、`ignoresMouseEvents`、frame）。
    var window: NSPanel? { panel }
    var isVisible: Bool { panel?.isVisible == true }

    /// 展示一次 toast；已可见时复用同一窗口、重置计时。
    ///
    /// - Parameter screen: 目标屏幕；默认选鼠标所在屏幕（截图区域就在那块屏上），
    ///   没有鼠标信息时退回主屏。
    func present(title: String, on screen: NSScreen? = nil) {
        let toast = panel ?? makePanel()
        panel = toast
        currentTitle = title
        toast.toastView.update(title: title)
        let size = toast.toastView.fittingSize
        toast.setContentSize(size)
        if let target = screen ?? Self.screenUnderMouse() ?? NSScreen.main {
            // 水平按**屏幕**居中（不是 visibleFrame：Dock 停靠在一侧时两者不同），
            // 纵向压在菜单栏下方——那个位置不受截图编辑器窗口影响。
            toast.setFrameOrigin(NSPoint(x: target.frame.midX - size.width / 2,
                                         y: target.visibleFrame.maxY - size.height - Self.topInset))
        }
        toast.alphaValue = 1
        // `orderFrontRegardless` 不激活 App，也不会成为 key window：不抢焦点。
        toast.orderFrontRegardless()
        presentationCount += 1
        generation += 1
        scheduleDismiss()
    }

    /// 立即收起（新的截图开始前调用，保证 toast 不进底图）。
    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    // MARK: - 计时

    private func scheduleDismiss() {
        dismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration, execute: item)
    }

    private func fadeOut() {
        guard let panel, panel.isVisible else { return }
        let fading = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == fading else { return }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
            }
        }
    }

    // MARK: - 窗口

    private static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    private func makePanel() -> CaptureToastPanel {
        let toast = CaptureToastPanel(contentRect: NSRect(origin: .zero,
                                                          size: CaptureToastView.minimumSize),
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        toast.backgroundColor = .clear
        toast.isOpaque = false
        // 透明无边框窗口的系统阴影按整块窗口矩形算，会在圆角胶囊外面套一个方框；
        // 这里关掉系统阴影，改用胶囊自带的 1pt 描边 + 毛玻璃层次定形。
        toast.hasShadow = false
        toast.isFloatingPanel = true
        // 截图编辑器的浮层是 `.screenSaver + 3` / `+ 4`（见 capcap `EditWindowController`），
        // toast 取 `+ 5`，保证即使编辑器此刻还在屏幕上也不会把它盖住。
        // 注意顺序：`isFloatingPanel = true` 会把 level 改回 `.floating`，所以最后再设。
        toast.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 5)
        toast.becomesKeyOnlyIfNeeded = true
        // 点不到、也不会被拖走：toast 只是看一眼就走，不允许打断用户。
        toast.ignoresMouseEvents = true
        toast.isReleasedWhenClosed = false
        toast.hidesOnDeactivate = false
        toast.animationBehavior = .none
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // 与 H1 的「伪装窗口不入底图」同一个口径；真正的保证是截图前先 `hide()`。
        toast.sharingType = .none
        toast.contentView = toast.toastView
        toast.layoutIfNeeded()
        return toast
    }
}

/// `NSWindow` 默认会接受点击/键盘；toast 必须两样都不要。
private final class CaptureToastPanel: NSPanel {
    let toastView = CaptureToastView()
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 毛玻璃胶囊：左侧 `checkmark.circle.fill`，右侧一行文案；圆角取高度的一半。
private final class CaptureToastView: NSVisualEffectView {
    static let minimumSize = NSSize(width: 132, height: 40)
    private static let iconPointSize: CGFloat = 17
    private static let iconTextSpacing: CGFloat = 8
    private static let horizontalPadding: CGFloat = 15
    private var minimumWidth: CGFloat { Self.minimumSize.width }
    private var toastHeight: CGFloat { Self.minimumSize.height }

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    /// 文案实测宽度（含 cell 内边距），由 `update(title:)` 现算；
    /// 用 `intrinsicContentSize` 会少算几个点，英文长文案会被截成「Screenshot copi…」。
    private var textWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.minimumSize.height / 2
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        // `.popover` 随浅/深外观给不同毛玻璃底，文字用 `labelColor` 自动配对；
        // 与上面 200×200 OSD 的 `.hudWindow` 是同一族材质。
        material = .popover
        blendingMode = .behindWindow
        state = .active
        iconView.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.imageScaling = .scaleProportionallyDown
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityRole(.staticText)
        addSubview(iconView)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// 动态色（`separatorColor`）只在当前外观下解析，切浅/深后要重新取一次。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    func update(title: String) {
        label.stringValue = title
        label.setAccessibilityLabel(title)
        label.sizeToFit()
        textWidth = ceil(label.frame.width)
        needsLayout = true
    }

    override var fittingSize: NSSize {
        let width = max(minimumWidth,
                        Self.horizontalPadding * 2 + Self.iconPointSize + Self.iconTextSpacing + textWidth)
        return NSSize(width: width, height: toastHeight)
    }

    override func layout() {
        super.layout()
        let iconFrame = NSRect(x: Self.horizontalPadding,
                               y: (bounds.height - Self.iconPointSize) / 2,
                               width: Self.iconPointSize,
                               height: Self.iconPointSize)
        iconView.frame = iconFrame
        let labelX = iconFrame.maxX + Self.iconTextSpacing
        let labelHeight = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: labelX,
                             y: (bounds.height - labelHeight) / 2,
                             width: max(0, bounds.width - labelX - Self.horizontalPadding),
                             height: labelHeight)
    }
}
