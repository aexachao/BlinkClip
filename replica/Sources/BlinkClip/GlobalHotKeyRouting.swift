import Foundation

/// 面板（底部快捷菜单）可见时，Stack 全局热键的语义路由。
///
/// 面板里的 ⇧⌘C 不是「打开 Stack」，而是「复制为纯文本」——语义在
/// `ReplicaUIController.handleKey` 里由 `CollectionShortcutActions.copyOptions` 决定
/// （`command | plainTextModifier` → `.plainText`，见 `CollectionShortcutActions.swift:20-27`）。
///
/// 因此这条热键需要**在面板可见时保持注册**：Carbon 的 `RegisterEventHotKey` 是唯一入口，
/// 一旦注销，按键连 AppKit 的 `keyDown` 都到不了面板，整条链路就断了（旧实现
/// `AppMain.panelVisibilityChanged(_:)` 正是这么做的，同时把 `.copySelection` 分支变成死代码）。
/// 注册不再随面板可见性变化，两套语义的分歧收敛到这个纯函数，便于 harness 直接断言。
enum StackHotKeyRouting: Equatable {
    /// 面板是 key window：把按键让给面板内的「复制为纯文本」。
    case copySelection
    /// 其余情况：走全局语义，打开 Stack。
    case showStack

    /// - Parameters:
    ///   - isAppActive: `NSApp.isActive`。应用不在前台时按键不可能属于面板。
    ///   - isPanelKeyWindow: 面板当前是 key window。面板可见但不是 key（例如刚被别的 App
    ///     抢走焦点）时按全局语义处理。
    ///   - isDefaultStackShortcut: 用户没有改过 Stack 快捷键。默认 ⇧⌘C 才和面板内的
    ///     「复制为纯文本」是同一个组合；自定义组合只承担「打开 Stack」。
    static func route(isAppActive: Bool, isPanelKeyWindow: Bool,
                      isDefaultStackShortcut: Bool) -> StackHotKeyRouting {
        guard isAppActive, isPanelKeyWindow, isDefaultStackShortcut else { return .showStack }
        return .copySelection
    }
}
