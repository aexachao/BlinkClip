import AppKit
import BlinkClipCore
import CoreGraphics
import CoreText
import QuartzCore

/// 所有轻提示（复制 / 暂停 / 继续 / 截图已复制）的唯一实现。
///
/// 规范（与 `DESIGN.md`「toast 规范」一致，改这里就同时改那里）：
/// - **样式**：固定 **128×128pt** 的**深色 HUD 毛玻璃盘**（`.hudWindow`，两套系统外观下
///   都是深底，圆角 16pt）；盘内**上图下字**并整块居中——图标 SF Symbol 42pt（weight .medium）、
///   图标与文案间距 **16pt**、文案 **14pt**（weight .semibold）、居中、行距 2pt、最多 2 行；
///   **图标与文案一律白色**（不跟随强调色），语义只靠符号区分（checkmark / pause / arrow.clockwise）；
/// - **位置**：屏幕底部居中，底边压 `visibleFrame.minY`（Dock 上沿 / 屏幕底）上方 120pt，
///   所以 Dock 在底部、在左/右或自动隐藏都不会压住它；
/// - **时长**：停留 1.3s + 淡出 0.2s；
/// - **不抢焦点**：`NSPanel` + `.nonactivatingPanel`，`canBecomeKey/Main` 恒为 false，
///   无点击动作时 `ignoresMouseEvents`，`orderFrontRegardless()` 不激活 App；
/// - **不入图**：`sharingType = .none` 且**实际生效**（见 `ReplicaToastPanel.sharingType`），
///   另外截图开始前仍会先 `hide()` 兜底；
/// - **不叠加**：单实例复用，连续触发只重置计时。
@MainActor
final class ReplicaToast {
    static let shared = ReplicaToast()

    /// 完全显示（不含淡出）的停留时长。
    static let holdDuration: TimeInterval = 1.3
    /// 淡出时长，从 `holdDuration` 末尾开始。
    static let fadeDuration: TimeInterval = 0.2
    /// 底盘底边与可用区域底边（`visibleFrame.minY`）的距离。
    static let bottomInset: CGFloat = 120

    /// 一条 toast 的全部内容：图标 + 文案（没有第二行小字）。
    ///
    /// 没有颜色参数：四条 toast 的图标与文案都是白色，语义只靠符号区分。
    struct Content {
        var symbolName: String
        var text: String
        /// 整块可点时执行的动作；`nil` 表示这条 toast 不可点。
        var action: (() -> Void)?

        init(symbolName: String, text: String, action: (() -> Void)? = nil) {
            self.symbolName = symbolName
            self.text = text
            self.action = action
        }
    }

    /// 面板创建过一次就一直复用（窗口号不变，窗口服务器不会累积残留窗口）。
    private var panel: ReplicaToastPanel?
    /// 「下一次收起」的计时；每次 `present` 都取消旧的重排一个新的。
    private var dismissWorkItem: DispatchWorkItem?
    /// 「淡出开始」的一次性动作（把窗口切成不吃点击）；同样随 `present` / `hide` 重排。
    private var fadeStartWorkItem: DispatchWorkItem?
    /// 停留 + 淡出整段动画在图层上的键；重新 `present` / `hide` 时先摘掉它。
    private static let timelineAnimationKey = "blinkclip.toast.timeline"

    /// 计时锚点：**第一帧真正提交给窗口服务器**（`CATransaction.flush()`）的那一刻。
    /// 不是 `present()` 被调用的那一刻——调用点之前/之后都可能有落库、写剪贴板、
    /// 拆编辑器、还焦点这些主线程重活。
    private(set) var lastVisibleAt: Date?
    /// `orderOut` 的时刻（整段动画走完后的墙钟补刀，见 `orderOutAfterTimeline`）。
    private(set) var lastDismissedAt: Date?
    /// 上屏 → 收起的墙钟时长；harness 用它断言 1.3–1.7s。
    var lastVisibleDuration: TimeInterval? {
        guard let lastVisibleAt, let lastDismissedAt else { return nil }
        return lastDismissedAt.timeIntervalSince(lastVisibleAt)
    }
    /// 连续触发的次数，测试用来确认是「重置」而不是「再开一个」。
    private(set) var presentationCount = 0
    /// 当前文案/图标；测试读它核对文案与图标语义。
    private(set) var currentText: String?
    private(set) var currentSymbolName: String?
    /// 当前是否可点（有动作）。
    var isInteractive: Bool { currentAction != nil }
    private var currentAction: (() -> Void)?
    /// 每次 `present` 递增。收起只在「还是同一代」时才真的 orderOut——
    /// 否则一次还没走完的收起会把紧接着弹出来的新 toast 收掉。
    private var generation = 0

    /// 供 harness 断言窗口属性（类、级别、`sharingType`、`ignoresMouseEvents`、frame）。
    var window: NSPanel? { panel }
    var isVisible: Bool { panel?.isVisible == true }
    /// 整段「停留 + 淡出」是不是挂在图层上的 CA 动画（由渲染服务器按墙钟推进），
    /// 而不是主线程推进的 `NSAnimationContext`。harness 在 `present` 之后立刻断言它。
    var usesRenderServerTimeline: Bool {
        panel?.contentView?.layer?.animation(forKey: Self.timelineAnimationKey) != nil
    }

    /// 展示一次 toast；已可见时复用同一窗口、重置计时。
    ///
    /// - Parameter screen: 目标屏幕；默认选鼠标所在屏幕，没有鼠标信息时退回主屏。
    func present(_ content: Content, on screen: NSScreen? = nil) {
        let toast = panel ?? makePanel()
        panel = toast
        currentText = content.text
        currentSymbolName = content.symbolName
        currentAction = content.action
        toast.toastView.update(content)
        // 无动作时整块不可点（连鼠标事件都不收）；有动作时整块可点。
        toast.ignoresMouseEvents = content.action == nil
        // 盘面固定 200×200pt；内容在盘内自己居中，不随文案伸缩。
        let size = toast.toastView.fittingSize
        toast.setContentSize(size)
        // 窗口改尺寸后立刻排一次版：否则首帧会用到上一条文案的图文位置。
        toast.layoutIfNeeded()
        if let target = screen ?? Self.screenUnderMouse() ?? NSScreen.main {
            toast.setFrameOrigin(Self.origin(for: size, on: target))
        }
        // 上一次淡出留在图层上的透明度和动画必须先清掉，否则新 toast 一上屏就是透明的。
        toast.alphaValue = 1
        if let layer = toast.contentView?.layer {
            layer.removeAnimation(forKey: Self.timelineAnimationKey)
            layer.opacity = 1
        }
        // `orderFrontRegardless` 不激活 App，也不会成为 key window：不抢焦点。
        toast.orderFrontRegardless()
        // 上屏前/后各钉一次：窗口服务器只认真正设置过的那一次，而首次上屏
        // （`didExpose`）会让 `WindowSharingPolicy` 把 sharingType 写回 `.readOnly`。
        toast.sharingType = .none
        // 关键：第一帧在**这一次调用里**就交给窗口服务器。`displayIfNeeded()` 把内容画出来，
        // `CATransaction.flush()` 立刻提交这一帧；否则要等本次 RunLoop 结束才提交，
        // 调用点后面还有落库/写剪贴板/拆编辑器/还焦点等主线程重活时，首帧会被一起拖走
        // （真机 1.0.19：计时早早开始、画面晚到，可见时长被算错）。
        toast.displayIfNeeded()
        // 整段「停留 + 淡出」的图层动画也放进同一次提交：主线程紧接着被重活占住时，
        // 动画已经在渲染服务器手里按墙钟走，不会再等下一次 RunLoop。
        startTimelineAnimation()
        CATransaction.flush()
        lastVisibleAt = Date()
        lastDismissedAt = nil
        presentationCount += 1
        generation += 1
        scheduleDismiss()
    }

    /// 立即收起（新的截图开始前调用，保证 toast 不进底图）。
    func hide() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        fadeStartWorkItem?.cancel()
        fadeStartWorkItem = nil
        panel?.contentView?.layer?.removeAnimation(forKey: Self.timelineAnimationKey)
        panel?.contentView?.layer?.opacity = 1
        panel?.orderOut(nil)
        panel?.alphaValue = 1
        currentAction = nil
        lastDismissedAt = Date()
    }

    /// 盘面左下角的位置：水平在可用区域内居中（Dock 在左/右时也不会压住），
    /// 垂直压在 `visibleFrame.minY + bottomInset`。
    static func origin(for size: NSSize, on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let centered = visible.midX - size.width / 2
        let x = min(max(centered, visible.minX + 8), max(visible.minX + 8, visible.maxX - size.width - 8))
        let bottomY = visible.minY + bottomInset
        // 极矮的可用区域（多屏缩放/竖屏）也不许顶出屏幕。
        let cappedY = min(bottomY, visible.maxY - size.height - 20)
        return NSPoint(x: x, y: max(visible.minY, cappedY))
    }

    // MARK: - 计时

    /// 停留 + 淡出：整段交给渲染服务器的一条图层动画，前 `holdDuration` 保持不透明，
    /// 后 `fadeDuration` 淡到 0；`orderOut` 另按墙钟补一刀。
    ///
    /// 为什么不用 `NSAnimationContext` + `animator().alphaValue`（1.0.19 的写法）：
    /// 那条路径的窗口淡出由**主线程**推进，并且「淡出结束」只由它的 completionHandler
    /// 通知。截图 toast 弹出时 BlinkClip 还是当前 App（截图编辑器刚关、焦点还没还回去），
    /// 恰好在停留到点前后主线程被收尾重活占住（拆遮罩/还原窗口/还焦点），0.2s 的淡出
    /// 就跟着卡：真机实测「已复制截图」停留 **2.72s**（1.3 停留 + 1.2 卡顿 + 0.2 淡出）。
    /// 另外三条 toast 弹出时 App 不在前台，淡出走窗口服务器，所以一直是 1.44–1.59s。
    /// 改成 CA 之后动画时长由渲染服务器按墙钟推进，主线程再忙也只有 `orderOut` 晚一点，
    /// 而那时窗口早已不可见。
    private func scheduleDismiss() {
        dismissWorkItem?.cancel()
        fadeStartWorkItem?.cancel()
        // 停留到点＝淡出开始：此刻起这块窗口不再吃点击（即使 orderOut 被主线程挤晚）。
        let fadeStart = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.panel?.ignoresMouseEvents = true }
        }
        fadeStartWorkItem = fadeStart
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration, execute: fadeStart)
        let scheduledGeneration = generation
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == scheduledGeneration else { return }
                self.orderOutAfterTimeline()
            }
        }
        dismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration + Self.fadeDuration, execute: item)
    }

    /// 在图层上挂「停留 + 淡出」的显式 CA 动画（渲染服务器按墙钟推进，主线程卡住照走）。
    private func startTimelineAnimation() {
        guard let layer = panel?.contentView?.layer else { return }
        let total = Self.holdDuration + Self.fadeDuration
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, NSNumber(value: Self.holdDuration / total), 1]
        fade.duration = total
        fade.timingFunctions = [CAMediaTimingFunction(name: .linear),
                                CAMediaTimingFunction(name: .easeOut)]
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        // 从「第一帧已提交」的那一刻开始计时；与窗口服务器的时间基准对齐。
        fade.beginTime = CACurrentMediaTime()
        layer.add(fade, forKey: Self.timelineAnimationKey)
        // 模型值落到 0：动画被系统摘掉（切后台/重绘）时也不会又亮回去。
        layer.opacity = 0
    }

    /// 计时到点后真正收起。与动画完成解耦：晚到也只是不可见的窗口多留一会儿。
    private func orderOutAfterTimeline() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        // 只摘动画，不把透明度写回 1：万一窗口被系统重新排上屏（面板类窗口会），
        // 它保持透明，不会闪回一块挡住桌面两秒的盘面。下一次 `present` 才恢复成 1。
        panel.contentView?.layer?.removeAnimation(forKey: Self.timelineAnimationKey)
        lastDismissedAt = Date()
    }

    // MARK: - 窗口

    private static func screenUnderMouse() -> NSScreen? {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(location, $0.frame, false) }
    }

    private func makePanel() -> ReplicaToastPanel {
        let toast = ReplicaToastPanel(contentRect: NSRect(origin: .zero, size: ReplicaToastView.panelSize),
                                      styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        toast.backgroundColor = .clear
        toast.isOpaque = false
        // 透明无边框窗口的系统阴影按整块窗口矩形算，会在圆角盘面外面套一个方框；
        // 这里关掉系统阴影，改用盘面自带的 1pt 描边 + 毛玻璃层次定形。
        toast.hasShadow = false
        toast.isFloatingPanel = true
        // 截图编辑器的浮层是 `.screenSaver + 3` / `+ 4`（见 capcap `EditWindowController`），
        // toast 取 `+ 5`，保证即使编辑器此刻还在屏幕上也不会把它盖住。
        // 注意顺序：`isFloatingPanel = true` 会把 level 改回 `.floating`，所以最后再设。
        toast.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 5)
        toast.becomesKeyOnlyIfNeeded = true
        toast.isReleasedWhenClosed = false
        toast.hidesOnDeactivate = false
        toast.animationBehavior = .none
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // 不进别人的截图/录屏：真正的保证是 `ReplicaToastPanel.sharingType` 的读写都钉在 `.none`，
        // 截图流程开始前还会先 `hide()` 兜一次时序。
        toast.sharingType = .none
        toast.contentView = toast.toastView
        toast.layoutIfNeeded()
        return toast
    }
}

/// `NSWindow` 默认会接受点击/键盘；toast 必须两样都不要。
///
/// `sharingType` 被刻意覆写成「写不进、永远 `.none`」：
/// 只写一次在出货件里不成立——`WindowSharingPolicy` 在 `NSWindow.didExpose` /
/// `didUpdate` 上把**每一个**应用窗口改成 `sharingType = .readOnly`（屏幕共享策略，
/// 默认开启），toast 一上屏就触发一次，实测 `CGWindowSharingState` 因此从 0 又变回 1
/// （`= 1` 表示可被截屏捕获）。把写入口钉死之后，策略再写也只落到 `.none`。
final class ReplicaToastPanel: NSPanel {
    let toastView = ReplicaToastView()
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var sharingType: NSWindow.SharingType {
        get { .none }
        set { super.sharingType = .none }
    }
}

/// 128×128pt 的毛玻璃盘：图标居中在上，文案居中在下（最多 2 行），整块在盘内居中。
final class ReplicaToastView: NSVisualEffectView {
    /// 盘面固定尺寸（pt）。
    static let panelSize = NSSize(width: 128, height: 128)
    static let cornerRadius: CGFloat = 16
    static let iconPointSize: CGFloat = 42
    static let iconTextSpacing: CGFloat = 16
    /// 文案可用宽度 = 盘宽 − 左右各 10pt（比图标窄，长文案换行而不是顶到圆角上）。
    static let textInset: CGFloat = 10
    static let textPointSize: CGFloat = 14
    static let textLineSpacing: CGFloat = 2
    static let maximumLines = 2

    var onActivate: (() -> Void)?

    /// 供 harness 量图文几何（图标在上、文案在下、间距恒定、整块居中）。
    var iconFrame: NSRect { iconView.frame }
    var textFrame: NSRect { label.frame }
    var maximumTextLines: Int { Self.maximumLines }
    var textFontSize: CGFloat { Self.textPointSize }
    var textLineSpacing2: CGFloat { Self.textLineSpacing }
    /// 0 = 居中（`NSTextAlignment.center.rawValue`），从真正的段落样式里读。
    var textAlignment: Int { label.paragraphAlignment }
    /// 文案节点永远只有一个：这里是「没有第二行小字」的硬断言入口。
    var copyNodeCount: Int { subviews.filter { $0 is ReplicaToastCopyView }.count }
    var renderedLineCount: Int { label.renderedLineCount }
    var copyText: String { label.text }
    /// 图标与文案的颜色（规范要求两者都是白色）。
    var iconColor: NSColor? { iconView.contentTintColor }
    var copyColor: NSColor? { label.textColor }
    /// 底板外观固定为深色（浅色系统外观下也不提亮）。
    var backingAppearance: NSAppearance.Name? { appearance?.name }

    private let iconView = NSImageView()
    private let label = ReplicaToastCopyView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Self.cornerRadius
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        // 深色 HUD 底：两套系统外观下**都是深玻璃**，白色图标/文案因此始终有对比度。
        // `appearance` 固定成 `vibrantDark`，浅色外观下也不会把衬底提亮成浅灰。
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        iconView.imageScaling = .scaleProportionallyDown
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

    /// 整块可点：子视图不参与命中，点击一律落到盘面本身。
    override func hitTest(_ point: NSPoint) -> NSView? {
        onActivate == nil ? nil : self
    }

    /// 可点时给一个手型光标，不用再写一行「点击启用直接粘贴」的小字。
    override func resetCursorRects() {
        super.resetCursorRects()
        guard onActivate != nil else { return }
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard let onActivate else { return }
        // 与旧的 OSD 一致：先让这次点击走完窗口的追踪，再执行动作，避免在
        // 事件分发过程中改偏好/收起面板。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { onActivate() }
    }

    func update(_ content: ReplicaToast.Content) {
        onActivate = content.action
        let configuration = NSImage.SymbolConfiguration(pointSize: Self.iconPointSize, weight: .medium)
        iconView.image = NSImage(systemSymbolName: content.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        iconView.contentTintColor = .white
        label.update(content.text)
        // 整块 toast 对读屏是一个元素；可点时是一颗按钮。
        setAccessibilityRole(content.action == nil ? .group : .button)
        setAccessibilityLabel(content.text)
        window?.invalidateCursorRects(for: self)
        needsLayout = true
    }

    /// 盘面固定 128×128pt；文案再长也只换行，不改变盘面尺寸。
    override var fittingSize: NSSize { Self.panelSize }

    override func layout() {
        super.layout()
        // 上图下字，整块在盘内水平+垂直居中（上下留白差 ≤0.5pt）。
        let textWidth = max(0, min(bounds.width - Self.textInset * 2, bounds.width))
        let textHeight = label.layoutSize(forWidth: textWidth).height
        let contentHeight = Self.iconPointSize + Self.iconTextSpacing + textHeight
        let contentBottom = (bounds.height - contentHeight) / 2
        label.frame = NSRect(x: (bounds.width - textWidth) / 2, y: contentBottom,
                             width: textWidth, height: textHeight)
        iconView.frame = NSRect(x: (bounds.width - Self.iconPointSize) / 2,
                                y: contentBottom + textHeight + Self.iconTextSpacing,
                                width: Self.iconPointSize, height: Self.iconPointSize)
    }
}

/// 单块文案：居中、行距 2pt、最多 2 行；超出 2 行时先在末尾收成省略号。
///
/// 为什么自绘而不是 `NSTextField`：实测一旦给 `attributedStringValue` 配上
/// `NSParagraphStyle`（行距只能这样给），`NSTextField` 就退回单行、并且丢掉居中，
/// 带定时的暂停文案会被截成「已暂停记录剪贴…」。自绘之后换行、居中、行距与行数
/// 全部由这里决定，harness 也能直接读到「实际画了几行」。
final class ReplicaToastCopyView: NSView {
    private(set) var text = ""
    private(set) var renderedLineCount = 0
    /// 段落对齐（0 = 居中），从实际排版的段落样式里读。
    var paragraphAlignment: Int {
        (attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?
            .alignment.rawValue ?? -1
    }

    /// 文案颜色（规范要求白色）。
    var textColor: NSColor? { attributed.length > 0 ? attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil }
    private var attributed = NSAttributedString()
    private var lastWidth: CGFloat = 0

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    static func font() -> NSFont {
        .systemFont(ofSize: ReplicaToastView.textPointSize, weight: .semibold)
    }

    /// 居中 + 2pt 行距 + 按词换行。
    static func attributed(_ text: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineSpacing = ReplicaToastView.textLineSpacing
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: font(),
            .foregroundColor: NSColor.white,
            .paragraphStyle: style,
        ])
    }

    /// 实际排出的行数（CoreText 说了算，不用估算）。
    static func lineCount(_ attributed: NSAttributedString, width: CGFloat) -> Int {
        guard attributed.length > 0, width > 0 else { return 0 }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 100_000), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        return (CTFrameGetLines(frame) as [AnyObject]).count
    }

    /// 在给定宽度下的排版结果：文本（必要时收成省略号）、行数、尺寸。
    static func layout(_ text: String, width: CGFloat) -> (text: String, attributed: NSAttributedString,
                                                          lines: Int, size: NSSize) {
        let lineHeight = ceil(font().boundingRectForFont.height)
        var base = text
        var needsEllipsis = false
        // 每次循环都**真的少一个字符**（省略号单独加），所以一定收敛；
        // 循环上限只是兜底，正常文案第一次就返回。
        for _ in 0..<2_000 {
            let display = needsEllipsis ? base + "…" : base
            let attributed = Self.attributed(display)
            let lines = lineCount(attributed, width: width)
            if lines <= ReplicaToastView.maximumLines {
                let bounding = attributed.boundingRect(
                    with: NSSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading])
                let height = lines <= 1 ? lineHeight : ceil(bounding.height)
                return (display, attributed, max(lines, 1),
                        NSSize(width: ceil(min(bounding.width, width)), height: height))
            }
            needsEllipsis = true
            if !base.isEmpty { base = String(base.dropLast()) } else { break }
        }
        return (base, Self.attributed(base), 1,
                NSSize(width: width, height: lineHeight))
    }

    static func measure(_ text: String, font: NSFont, width: CGFloat) -> NSSize {
        layout(text, width: width).size
    }

    func update(_ newText: String) {
        text = newText
        setAccessibilityLabel(newText)
        lastWidth = 0
        needsLayout = true
        needsDisplay = true
    }

    /// 按当前宽度排版并缓存（`layout()` 每帧调用，不重复排）。
    @discardableResult
    func layoutSize(forWidth width: CGFloat) -> NSSize {
        guard width != lastWidth || attributed.length == 0 else { return measuredSize }
        let result = Self.layout(text, width: width)
        attributed = result.attributed
        renderedLineCount = result.lines
        lastWidth = width
        needsDisplay = true
        return result.size
    }

    private var measuredSize: NSSize {
        attributed.boundingRect(with: NSSize(width: lastWidth, height: .greatestFiniteMagnitude),
                                options: [.usesLineFragmentOrigin, .usesFontLeading]).size
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard attributed.length > 0 else { return }
        NSBezierPath(rect: bounds).addClip()
        attributed.draw(with: bounds, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}
