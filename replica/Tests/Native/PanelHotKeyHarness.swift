import AppKit
import Carbon
import Foundation
import BlinkClipCore

// 面板（底部快捷菜单）可见期间的全局热键回归。
//
// 覆盖的是**注册生命周期**而不是某个组合：
// - `GlobalHotKey` 是生产实现（真实 Carbon `RegisterEventHotKey` + 真实 dispatcher 投递）；
// - 面板是真实的 `NSPanel(.nonactivatingPanel)`，identifier 与 `ReplicaUIController.loadPanel`
//   一致（`blinkclip-panel`），`ScreenshotWindowHider` 也因此按生产规则识别它；
// - 面板内的 ⇧⌘C 语义用生产函数 `StackHotKeyRouting.route` 判断，不复刻一份。
//
// 旧行为（`AppMain.panelVisibilityChanged`）会在面板可见时 `unregister` Stack 热键，
// 于是这里第 5 项（面板可见时投递 Stack 事件仍能触发动作）会失败。

@MainActor
private final class PanelFixture {
    let panel: NSPanel
    /// `NSApp.isActive` 的替身：harness 以 `.prohibited` 运行，读真实值永远是 false。
    var isAppActive = false
    var isDefaultStackShortcut = true
    var toggleCount = 0
    var stackRoute: StackHotKeyRouting?
    var copied = 0
    var shown = 0

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("blinkclip-panel")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .mainMenu
        panel.hidesOnDeactivate = false
    }

    /// `NSApp` 以 `.prohibited` 运行时无法激活，`makeKey()` 不会真的把窗口变成 key。
    /// key window 是路由输入而不是被测实现，这里允许注入；真实输入路径由 `route` 的矩阵覆盖。
    var keyWindowOverride: Bool?
    var isKeyWindow: Bool { keyWindowOverride ?? panel.isKeyWindow }

    func togglePanel() {
        toggleCount += 1
        if panel.isVisible { panel.orderOut(nil) } else { panel.orderFront(nil) }
    }

    /// 与 `AppMain` 里的 Stack 热键动作同构：路由由生产函数决定。
    func performStackHotKey() {
        let route = StackHotKeyRouting.route(isAppActive: isAppActive,
                                            isPanelKeyWindow: isKeyWindow,
                                            isDefaultStackShortcut: isDefaultStackShortcut)
        stackRoute = route
        switch route {
        case .copySelection: copied += 1
        case .showStack: shown += 1
        }
    }
}

@main
struct PanelHotKeyHarness {
    struct Failure: Error, CustomStringConvertible { let description: String }

    @MainActor static func main() {
        do { try run() }
        catch {
            print(String(data: try! JSONSerialization.data(withJSONObject:
                ["status": "failed", "reason": String(describing: error)], options: [.sortedKeys]),
                encoding: .utf8)!)
            exit(1)
        }
    }

    @MainActor static func run() throws {
        _ = NSApplication.shared
        var checks: [String] = []
        func require(_ condition: Bool, _ message: @autoclosure () -> String) throws {
            guard condition else { throw Failure(description: message()) }
            checks.append(message())
        }
        func pump() { RunLoop.main.run(until: Date().addingTimeInterval(0.06)) }

        // 真实 Carbon 投递：把 kEventHotKeyPressed 送进本进程的 dispatcher。
        var diagnostics: [ShortcutDiagnostic] = []
        let overrides = DependencyOverrides()
        overrides.registerFactory(\DependencyValues.shortcutDiagnostic) { { diagnostics.append($0) } }
        var delivered: [String: Int] = [:]

        try Dependencies.withOverrides(overrides) {
            func actualID() throws -> UInt32 {
                guard let message = diagnostics.last(where: { $0.message.hasPrefix("registered carbonID=") })?.message,
                      let token = message.split(separator: " ").first(where: { $0.hasPrefix("carbonID=") }),
                      let id = UInt32(token.dropFirst("carbonID=".count)) else {
                    throw Failure(description: "registration did not report its Carbon ID")
                }
                return id
            }
            func deliver(_ id: UInt32) -> OSStatus {
                var event: EventRef?
                let status = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                         GetCurrentEventTime(), EventAttributes(kEventAttributeUserEvent), &event)
                guard status == noErr, let event else { return status }
                defer { ReleaseEvent(event) }
                var key = EventHotKeyID(signature: 1, id: id)
                guard SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID),
                                        MemoryLayout<EventHotKeyID>.size, &key) == noErr else {
                    return OSStatus(-1)
                }
                return SendEventToEventTarget(event, GetEventDispatcherTarget())
            }

            let fixture = PanelFixture()
            let hider = ScreenshotWindowHider()
            let candidates = [kVK_F18, kVK_F19, kVK_F20, kVK_F17, kVK_F16, kVK_F15].map(UInt32.init)
            var usedCodes = Set<UInt32>()
            // 每个热键必须占一个不同的组合：`GlobalShortcutMonitor` 按 `ShortcutValue`
            // （键码+修饰键）索引注册，同组合会被后者顶掉。
            @MainActor func register(_ hotKey: GlobalHotKey, _ identifier: UInt32,
                                     _ action: @escaping () -> Void) throws -> (code: UInt32, carbonID: UInt32) {
                hotKey.action = action
                for code in candidates where !usedCodes.contains(code) {
                    guard hotKey.register(keyCode: code, identifier: identifier) == noErr else { continue }
                    usedCodes.insert(code)
                    return (code, try actualID())
                }
                throw Failure(description: "no unused function key for identifier \(identifier)")
            }

            let history = GlobalHotKey(), stack = GlobalHotKey(), screenshot = GlobalHotKey()
            var screenshotCount = 0
            var panelHiddenWhenCaptureStarted: Bool?
            var captureSawPanelHidden = false
            var panelRestored = false
            let historyRegistration = try register(history, 71) {
                delivered["history", default: 0] += 1
                fixture.togglePanel()
            }
            let stackRegistration = try register(stack, 72) {
                delivered["stack", default: 0] += 1
                fixture.performStackHotKey()
            }
            let screenshotRegistration = try register(screenshot, 73) {
                delivered["screenshot", default: 0] += 1
                screenshotCount += 1
                // 生产顺序：先收起 BlinkClip 自己的窗口，再创建抓屏/遮罩。
                hider.hideVisibleBlinkClipWindows()
                panelHiddenWhenCaptureStarted = !fixture.panel.isVisible
                captureSawPanelHidden = !fixture.panel.isVisible
                // 模拟编辑器保存/取消出口：恢复了窗口才算一轮结束。
                hider.restore()
                panelRestored = fixture.panel.isVisible
            }
            defer { history.unregister(); stack.unregister(); screenshot.unregister() }
            let historyID = historyRegistration.carbonID
            let stackID = stackRegistration.carbonID
            let screenshotID = screenshotRegistration.carbonID
            pump()

            // 1. 面板可见 → 面板热键仍然触发，并且是 toggle 语义（关掉）。
            fixture.panel.orderFront(nil); pump()
            try require(fixture.panel.isVisible, "fixture panel is visible before the history hot key")
            try require(deliver(historyID) == noErr, "panel-visible history delivery is consumed")
            pump()
            try require(delivered["history"] == 1 && fixture.toggleCount == 1,
                        "panel-visible history hot key fires and toggles")
            try require(!fixture.panel.isVisible, "toggle closes the already visible panel (no recursion)")

            // 2. 面板隐藏 → 同一个组合再触发一次，重新打开（对照）。
            try require(deliver(historyID) == noErr, "panel-hidden history delivery is consumed")
            pump()
            try require(delivered["history"] == 2 && fixture.panel.isVisible,
                        "panel-hidden history hot key reopens the panel")

            // 3. 面板可见 → 区域截图热键仍然触发；抓屏开始前面板必须已经离屏。
            try require(deliver(screenshotID) == noErr, "panel-visible screenshot delivery is consumed")
            pump()
            try require(screenshotCount == 1, "panel-visible screenshot hot key fires")
            try require(panelHiddenWhenCaptureStarted == true && captureSawPanelHidden,
                        "screenshot hides the visible panel before the capture entry starts")
            try require(panelRestored, "screenshot exit restores the panel that was hidden")

            // 4. 面板可见 → Stack 热键仍然触发（旧实现在这里把它注销了）。
            fixture.isDefaultStackShortcut = false
            try require(deliver(stackID) == noErr, "panel-visible stack delivery is consumed")
            pump()
            try require(delivered["stack"] == 1 && fixture.stackRoute == .showStack,
                        "panel-visible stack hot key fires with the global semantic (custom combination)")

            // 5. 注册生命周期不随面板可见性变化：可见性切换后再投递，仍然只有同一个注册生效。
            fixture.panel.orderOut(nil); pump()
            fixture.panel.orderFront(nil); pump()
            try require(deliver(historyID) == noErr && deliver(screenshotID) == noErr,
                        "visibility cycles keep the original registrations alive")
            pump()
            try require(delivered["history"] == 3 && screenshotCount == 2,
                        "same Carbon registrations still fire after panel show/hide cycles")

            // 6. ⇧⌘C 的两种语义：生产路由函数本身。
            let matrix: [(Bool, Bool, Bool, StackHotKeyRouting)] = [
                (true, true, true, .copySelection),
                (true, true, false, .showStack),
                (true, false, true, .showStack),
                (false, true, true, .showStack),
            ]
            for (active, key, isDefault, expected) in matrix {
                let route = StackHotKeyRouting.route(isAppActive: active, isPanelKeyWindow: key,
                                                     isDefaultStackShortcut: isDefault)
                try require(route == expected,
                            "stack routing(active: \(active), key: \(key), default: \(isDefault)) == \(expected)")
            }
            // 面板 key window 且默认组合时，走面板内的「复制为纯文本」。
            fixture.isAppActive = true
            fixture.isDefaultStackShortcut = true
            fixture.keyWindowOverride = true
            fixture.copied = 0
            fixture.shown = 0
            pump()
            try require(deliver(stackID) == noErr, "panel-key stack delivery is consumed")
            pump()
            try require(fixture.stackRoute == .copySelection && fixture.copied == 1 && fixture.shown == 0,
                        "panel key window routes the stack hot key to copy-as-plain-text")

            let report: [String: Any] = [
                "passed": true,
                "checks": checks,
                "count": checks.count,
                "callbacks": delivered,
                "combinations": ["history": historyRegistration.code, "stack": stackRegistration.code,
                                 "screenshot": screenshotRegistration.code],
                "carbon_ids": ["history": historyID, "stack": stackID, "screenshot": screenshotID],
                "real": ["GlobalHotKey/GlobalShortcutMonitor (Carbon RegisterEventHotKey + dispatcher delivery)",
                         "NSPanel(.nonactivatingPanel) with the blinkclip-panel identifier",
                         "ScreenshotWindowHider hide/restore", "StackHotKeyRouting"],
                "doubles": ["panel show/hide (fixture window instead of ReplicaUIController)",
                            "PanelHotKeyHarness bench: synthetic kEventHotKeyPressed to this process"],
                "scope": "Isolated app ID, temporary function-key registrations and a real offscreen-created panel. "
                    + "No system keyboard posting, no screenshot of the desktop, no clipboard access.",
            ]
            print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]),
                         encoding: .utf8)!)
        }
    }
}
