import AppKit
import BlinkClipCore
import Foundation

/// 菜单栏网速的运行时回归。
///
/// 注入假计数器，验证：
///  - 打开后 1 秒采样，第一次只取基线（`rates == nil`）；
///  - 关闭开关后 provider 不再被调用（定时器真的停了）；
///  - 唤醒通知重置基线；
///  - utun 优先口径（活动隧道只算隧道，不叠加物理网卡）；
///  - 菜单栏渲染宽度、图标宽度、tooltip 与紧凑文字。
@MainActor
@main struct NetworkSpeedHarness {
    static var checks = 0

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        checks += 1
    }

    static func sleep(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// 每次读取都在上一次的基础上增加固定字节数，模拟真实网卡的累计计数器。
    final class FakeProvider {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var calls = 0
        var includesActiveTunnel = false
        var physicalStep: UInt64 = 1_048_576
        var tunnelStep: UInt64 = 102_400

        func next() -> [NetworkSpeedInterfaceSnapshot] {
            calls += 1
            received &+= physicalStep
            sent &+= physicalStep / 4
            if includesActiveTunnel {
                return [
                    NetworkSpeedInterfaceSnapshot(
                        name: "en0", isUp: true, isRunning: true, isLoopback: false,
                        hasLinkType: true, hasRoutableAddress: true,
                        counters: NetworkSpeedCounters(receivedBytes: received, sentBytes: sent)),
                    NetworkSpeedInterfaceSnapshot(
                        name: "utun3", isUp: true, isRunning: true, isLoopback: false,
                        hasLinkType: true, hasRoutableAddress: true,
                        counters: NetworkSpeedCounters(receivedBytes: received / 10,
                                                       sentBytes: sent / 10)),
                ]
            }
            return [
                NetworkSpeedInterfaceSnapshot(
                    name: "en0", isUp: true, isRunning: true, isLoopback: false,
                    hasLinkType: true, hasRoutableAddress: true,
                    counters: NetworkSpeedCounters(receivedBytes: received, sentBytes: sent)),
                NetworkSpeedInterfaceSnapshot(
                    name: "lo0", isUp: true, isRunning: true, isLoopback: true,
                    hasLinkType: true, hasRoutableAddress: true,
                    counters: NetworkSpeedCounters(receivedBytes: received * 3, sentBytes: sent * 3)),
            ]
        }
    }

    /// 真机口径探针：每 1 秒打印生产采集器的聚合结果，用 netstat 对拍时使用。
    static func live(seconds: Int) {
        var previous: NetworkSpeedSample?
        for index in 0..<seconds {
            let interfaces = NetworkSpeedInterfaceReader.readInterfaces()
            let selection = NetworkSpeedAggregator.selection(in: interfaces)
            let current = NetworkSpeedSample(counters: NetworkSpeedAggregator.counters(in: interfaces),
                                             timestamp: Date())
            var rx = 0.0, tx = 0.0
            if let previous,
               case .rates(let rates) = NetworkSpeedRateCalculator.evaluate(previous: previous, current: current) {
                rx = rates.downloadBytesPerSecond
                tx = rates.uploadBytesPerSecond
            }
            let names = interfaces.filter(\.isEligible).map(\.name).sorted()
            print(String(format: "LIVE %d rx=%.0f tx=%.0f selection=%@ eligible=%@",
                         index, rx, tx, String(describing: selection), names.joined(separator: ",")))
            fflush(stdout)
            previous = current
            Thread.sleep(forTimeInterval: 1.0)
        }
    }

    static func main() async {
        if let index = CommandLine.arguments.firstIndex(of: "--live") {
            live(seconds: index + 1 < CommandLine.arguments.count
                 ? (Int(CommandLine.arguments[index + 1]) ?? 6) : 6)
            return
        }
        let suite = "local.blinkclip.netspeed.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            print("FAIL cannot create defaults suite")
            exit(1)
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        // ---- 开关打开：首拍基线，1 秒后出数字 ------------------------------
        let provider = FakeProvider()
        let monitor = NetworkSpeedMonitor(defaults: defaults, provider: { provider.next() },
                                          interval: 1.0, observeWake: true)
        check(!monitor.snapshot.isEnabled, "默认关闭")
        check(monitor.snapshot.rates == nil, "打开前没有读数")
        monitor.setEnabled(true)
        check(monitor.isRunning, "打开后定时器应在运行")
        check(monitor.snapshot.sampleCount == 1, "打开时先取一次基线")
        check(monitor.snapshot.rates == nil, "第一次采样只做基线，不显示数字")
        await sleep(1.45)
        check(monitor.snapshot.sampleCount >= 2, "1 秒后应至少再采样一次")
        guard let firstRates = monitor.snapshot.rates else {
            print("FAIL 1.45s 后仍没有速率")
            exit(1)
        }
        // provider 每次 +1 MiB，1 秒上下浮动；leeway 0.2s 允许 0.85–1.6 MiB/s。
        check(firstRates.downloadBytesPerSecond > 650_000
              && firstRates.downloadBytesPerSecond < 1_400_000,
              "1 秒采样速率不在预期范围：\(firstRates.downloadBytesPerSecond)")

        // ---- 关闭开关：provider 调用数必须停住 -----------------------------
        monitor.setEnabled(false)
        check(!monitor.isRunning, "关闭后定时器应停止")
        check(monitor.snapshot.rates == nil, "关闭后不显示旧读数")
        let callsAtStop = provider.calls
        await sleep(1.35)
        check(provider.calls == callsAtStop, "关闭开关后仍在采样：\(callsAtStop) → \(provider.calls)")

        // ---- 唤醒：重置基线，下一拍仍是基线，再下一拍恢复数字 -------------
        monitor.setEnabled(true)
        await sleep(1.35)
        check(monitor.snapshot.rates != nil, "重新打开后应恢复读数")
        let resetsBeforeWake = monitor.snapshot.baselineResetCount
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        await sleep(0.2)
        check(monitor.snapshot.baselineResetCount == resetsBeforeWake + 1,
              "唤醒没有重置基线：\(resetsBeforeWake) → \(monitor.snapshot.baselineResetCount)")
        check(monitor.snapshot.rates == nil, "唤醒后的第一拍只做基线")
        await sleep(1.35)
        check(monitor.snapshot.rates != nil, "唤醒后第二拍应恢复数字")

        // ---- utun 优先：活动隧道存在时只累加隧道（约为物理的 1/10） --------
        let tunnelProvider = FakeProvider()
        tunnelProvider.includesActiveTunnel = true
        let tunnelMonitor = NetworkSpeedMonitor(defaults: defaults,
                                                provider: { tunnelProvider.next() },
                                                interval: 1.0, observeWake: false)
        tunnelMonitor.setEnabled(true)
        await sleep(1.45)
        guard let tunnelRates = tunnelMonitor.snapshot.rates else {
            print("FAIL utun 口径没有产生速率")
            exit(1)
        }
        check(tunnelRates.downloadBytesPerSecond > 60_000
              && tunnelRates.downloadBytesPerSecond < 160_000,
              "utun 优先口径没有只算隧道：\(tunnelRates.downloadBytesPerSecond)")
        tunnelMonitor.setEnabled(false)
        monitor.setEnabled(false)

        // ---- 菜单栏渲染：宽度增长、图标不被挤掉、tooltip 完整 --------------
        let rates = NetworkSpeedRates(downloadBytesPerSecond: 1_468_006,
                                      uploadBytesPerSecond: 33_178)
        let icon = ReplicaBrand.menuBarImage()
        let enabledWidths = NetworkSpeedStatusItem.measuredWidths(
            enabled: true, rates: rates, unit: .bytesPerSecond, icon: icon)
        let disabledWidths = NetworkSpeedStatusItem.measuredWidths(
            enabled: false, rates: nil, unit: .bytesPerSecond, icon: icon)
        check(enabledWidths.button > disabledWidths.button + 40,
              "开启网速后状态栏没有变宽：\(disabledWidths.button) → \(enabledWidths.button)")
        check(enabledWidths.icon >= 16, "图标被挤掉了：\(enabledWidths.icon)")
        check(disabledWidths.icon >= 16, "关闭状态下图标被挤掉了：\(disabledWidths.icon)")
        let title = NetworkSpeedStatusItem.attributedTitle(rates: rates, unit: .bytesPerSecond).string
        check(title == "↓1.4M ↑32.4K", "菜单栏紧凑文字不对：\(title)")
        let bitRates = NetworkSpeedRates(downloadBytesPerSecond: 1_400_000,
                                         uploadBytesPerSecond: 32_400)
        let bitsTitle = NetworkSpeedStatusItem.attributedTitle(rates: bitRates, unit: .bitsPerSecond).string
        check(bitsTitle == "↓11.2M ↑259K", "bps 菜单栏文字不对：\(bitsTitle)")
        let tooltip = NetworkSpeedStatusItem.toolTip(rates: rates, unit: .bytesPerSecond)
        check(tooltip.contains("1.4 MB/s") && tooltip.contains("32.4 KB/s") && tooltip.contains("·"),
              "tooltip 不完整：\(tooltip)")

        let payload: [String: Any] = [
            "passed": true,
            "checks": checks,
            "menuBarWidth": Double((enabledWidths.button * 100).rounded() / 100),
            "menuBarDisabledWidth": Double((disabledWidths.button * 100).rounded() / 100),
            "iconWidth": Double((enabledWidths.icon * 100).rounded() / 100),
            "sampleCount": monitor.snapshot.sampleCount,
            "baselineResetCount": monitor.snapshot.baselineResetCount,
            "boundary": "生产 NetworkSpeedMonitor / NetworkSpeedInterfaceReader / NetworkSpeedStatusItem + 注入假计数器；真实 NSStatusBarButton 尺寸；不访问用户历史与剪贴板。",
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
