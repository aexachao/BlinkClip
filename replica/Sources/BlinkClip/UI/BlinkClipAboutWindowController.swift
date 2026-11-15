import AppKit
import Combine
import BlinkClipCore
import os

/// 「关于闪贴」页的状态模型。
///
/// 独立关于窗口已经移除：关于现在是设置窗口右侧内容区里的**一个页面**
/// （`ReplicaSettingsView.about`），页面只负责排版，而「尚未检查更新 / 正在
/// 检查更新… / 上次检查 HH:mm / 有新版本 X 可用」这四种状态与按下「检查更新」
/// 之后的既有路径仍然只在这一份模型里，两条入口（应用菜单「关于 闪贴」与
/// `.blinkClipOpenAbout` 通知）都打开同一个设置窗口的同一页，因此不存在第二份
/// 状态、也不会各起一个 updater。
///
/// 状态行属于动作块：它与唯一的主按钮同处一段，状态行在按钮上方、两者同一条
/// 中轴，间距 ≤12pt。它永远用次要色，检查失败也不会把布局顶开、更不会把网络
/// 细节漏到界面上——温和文案来自 `BlinkClipUpdateChecker`。状态行只报告时间戳
/// （「上次检查 21:04」）或具体的等待/有新版本/失败事实，从不断言「已是最新」：
/// Sparkle 自己的弹窗已经说过，而 Sparkle 2.10.1 没有公开钩子能压掉那个弹窗
/// （`SPUStandardUserDriverDelegate` 只观察模态弹窗）。
///
/// 文件名保留历史名 `BlinkClipAboutWindowController.swift`：回归脚本按这个名字
/// 取关于页的源码门禁，窗口类本身已经删掉。
@MainActor
final class BlinkClipAboutModel: ObservableObject {
    private static let log = Logger(subsystem: "com.chrisli.blinkclip", category: "updates")

    let checker: BlinkClipUpdateChecker
    /// Sparkle 自己的检查（`BlinkClipInAppUpdater` / `SPUUpdater`）。注入是为了
    /// 让页面/harness 不依赖 Sparkle。
    private let sparkleCheck: () throws -> Void
    private var observation: AnyCancellable?

    /// 状态行文案。与旧窗口逐字相同：首帧就是「尚未检查更新」或持久化的
    /// 「上次检查 HH:mm」，不会先空一帧。
    @Published private(set) var statusText: String = ""
    /// 检查请求在飞：按钮置灰（唯一的主按钮，检查中不可重复点）。
    @Published private(set) var isChecking = false

    init(checker: BlinkClipUpdateChecker, sparkleCheck: @escaping () throws -> Void) {
        self.checker = checker
        self.sparkleCheck = sparkleCheck
        refresh(checker.state)
        observation = checker.$state.sink { [weak self] state in
            MainActor.assumeIsolated { self?.refresh(state) }
        }
    }

    /// 「版本 %@」，与窗口版同一句文案、同一个格式串。
    var versionText: String {
        String(format: text("updates.current-version"), checker.currentVersion)
    }

    private func text(_ key: String) -> String { SettingsLocalization.text(key) }

    private func refresh(_ state: BlinkClipUpdateChecker.State) {
        isChecking = state == .checking
        switch state {
        case .idle:
            // 一次检查都没跑过时显示「尚未检查更新」，跑过就是持久化的检查时间，
            // 从不报告「新鲜度」。
            statusText = checker.lastCheckSummary
        case .checking:
            statusText = text("updates.checking")
        case .upToDate:
            // Sparkle 的主动检查自己会弹「已是最新」。内联再写一遍就是两处说同一
            // 件事，这里只留验证时间。
            statusText = checker.lastCheckSummary
        case let .available(update):
            statusText = String(format: text("updates.available-format"),
                                update.version, checker.lastCheckTime)
        case let .failed(message):
            statusText = message
        }
    }

    /// 刷新 appcast 摘要并把安装交给 Sparkle。按钮是更新器的入口，不是页面刷新。
    func check() {
        Task { await checker.check(force: true) }
        do {
            try sparkleCheck()
        } catch {
            Self.log.error("sparkle check failed: \(String(describing: error), privacy: .public)")
            statusText = text("updates.unreachable")
        }
    }
}
