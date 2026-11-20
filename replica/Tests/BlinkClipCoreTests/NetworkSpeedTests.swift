import Foundation
import BlinkClipCore

/// 菜单栏网速的纯函数口径：接口选择、基线/回绕、速率分母与两种格式。
///
/// 这些测试不读真实网卡，注入 `NetworkSpeedInterfaceSnapshot` 与采样时间，
/// 因此 VPN 口径、计数器重置、999.9K 边界与末档降级都能稳定复现。
///
/// 单位只有四档：B、KB、MB、GB（bps 模式 bps、kbps、Mbps、Gbps）。
struct NetworkSpeedTests {
    // MARK: - 格式

    func testByteFormatting() {
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_468_006, unit: .bytesPerSecond),
                    "1.4 MB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 33_178, unit: .bytesPerSecond),
                    "32.4 KB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 4.2, unit: .bytesPerSecond),
                    "4.2 B/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 831_795, unit: .bytesPerSecond),
                    "812.3 KB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_073_741_824, unit: .bytesPerSecond),
                    "1.0 GB/s")
        // 999.9K 边界：999.9 KB 与 999.96 KB 都进档成 1.0 MB/s。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_023_897, unit: .bytesPerSecond),
                    "1.0 MB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_023_959, unit: .bytesPerSecond),
                    "1.0 MB/s")
        // 1024 进制 + 「一位小数进位到 1000 就进档」：不会出现 1023.0 B/s 这种
        // 四位整数，1023 B/s 与 1024 B/s 都显示 1.0 KB/s（除数仍是 1024）。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_023, unit: .bytesPerSecond),
                    "1.0 KB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_024, unit: .bytesPerSecond),
                    "1.0 KB/s")
        // 四档：B → KB → MB → GB，每档一位小数。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_024 * 1_024, unit: .bytesPerSecond),
                    "1.0 MB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 999 * 1_073_741_824, unit: .bytesPerSecond),
                    "999.0 GB/s")
        // 末档（GB）无档可进：≥ 1024 GB 落成降级串，而不是 TB 或四位整数。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_024 * 1_073_741_824,
                                                     unit: .bytesPerSecond),
                    ">999 GB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 20_480 * 1_073_741_824,
                                                     unit: .bytesPerSecond),
                    ">999 GB/s")
    }

    func testBitsFormatting() {
        // bps 先 ×8、1000 进制，一位小数。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_400_000, unit: .bitsPerSecond),
                    "11.2 Mbps")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 32_400, unit: .bitsPerSecond),
                    "259.2 kbps")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 4, unit: .bitsPerSecond),
                    "32.0 bps")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 0, unit: .bitsPerSecond),
                    "0.0 bps")
    }

    func testCompactMenuBarTitle() {
        // 紧凑写法 = 完整写法去掉空格与 `/s`：一位小数，四档单位字母 B/K/M/G。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_468_006,
                                                        uploadBytesPerSecond: 33_178, unit: .bytesPerSecond),
                    "↓1.4M ↑32.4K")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 831_795,
                                                        uploadBytesPerSecond: 4.2, unit: .bytesPerSecond),
                    "↓812.3K ↑4.2B")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_073_741_824,
                                                        uploadBytesPerSecond: 1_024 * 1_024,
                                                        unit: .bytesPerSecond),
                    "↓1.0G ↑1.0M")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_400_000,
                                                        uploadBytesPerSecond: 32_400, unit: .bitsPerSecond),
                    "↓11.2M ↑259.2K")
        // 空闲不隐藏、宽度稳定。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 0,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓0.0B ↑0.0B")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 0,
                                                        uploadBytesPerSecond: 0, unit: .bitsPerSecond),
                    "↓0.0b ↑0.0b")
        // 首采样只有基线：占位符而不是数字。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: nil,
                                                        uploadBytesPerSecond: nil, unit: .bytesPerSecond),
                    "↓— ↑—")
        // 一位小数的边界是 999.9：999.6 KB 原样显示（`999.6K`），
        // 999.9 KB 再往上一格才进档成 `1.0M`，不会出现 `1000.0K`。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_023_590,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓999.6K ↑0.0B")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_023_897,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓1.0M ↑0.0B")
        // 末档（G）无档可进：≥ 1024 GB 显示降级串 `>999G`（5 个字符，比最宽正常串窄）。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_024 * 1_073_741_824,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓>999G ↑0.0B")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 20_480 * 1_073_741_824,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓>999G ↑0.0B")
    }

    // MARK: - 接口选择与 VPN 口径

    func testInterfaceEligibility() {
        let up = interface("en0", up: true, running: true, received: 100, sent: 200)
        let down = interface("en1", up: false, running: true, received: 1_000, sent: 2_000)
        let notRunning = interface("en2", up: true, running: false, received: 1_000, sent: 2_000)
        let loopback = interface("lo0", up: true, running: true, loopback: true, received: 5_000, sent: 6_000)
        let noLink = interface("gif0", up: true, running: true, linkType: false, received: 7_000, sent: 8_000)
        let selection = NetworkSpeedAggregator.selection(in: [up, down, notRunning, loopback, noLink])
        expectEqual(selection, .physical)
        expectEqual(NetworkSpeedAggregator.counters(in: [up, down, notRunning, loopback, noLink]),
                    NetworkSpeedCounters(receivedBytes: 100, sentBytes: 200))
    }

    func testUtunTakesPriorityOnlyWhenTunnelIsActive() {
        let physical = interface("en0", up: true, running: true, received: 1_000, sent: 2_000)
        let awdl = interface("awdl0", up: true, running: true, received: 10, sent: 20)
        // macOS 常驻的 utun（只有 fe80 链路本地地址）不能接管统计，否则普通上网会是 0。
        let idleTunnel = interface("utun0", up: true, running: true,
                                   routable: false, received: 50, sent: 60)
        expectEqual(NetworkSpeedAggregator.selection(in: [physical, awdl, idleTunnel]), .physical)
        expectEqual(NetworkSpeedAggregator.counters(in: [physical, awdl, idleTunnel]),
                    NetworkSpeedCounters(receivedBytes: 1_010, sentBytes: 2_020))

        let vpn = interface("utun3", up: true, running: true,
                            routable: true, received: 3_000, sent: 4_000)
        expectEqual(NetworkSpeedAggregator.selection(in: [physical, awdl, vpn]), .tunnel)
        expectEqual(NetworkSpeedAggregator.counters(in: [physical, awdl, vpn]),
                    NetworkSpeedCounters(receivedBytes: 3_000, sentBytes: 4_000))
    }

    // MARK: - 基线、回绕与时间差

    func testFirstSampleIsBaselineAndUsesActualElapsed() {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = NetworkSpeedSample(counters: NetworkSpeedCounters(receivedBytes: 1_000, sentBytes: 2_000),
                                       timestamp: start)
        expectEqual(NetworkSpeedRateCalculator.evaluate(previous: nil, current: first), .baseline)

        // 2 秒内收到 1,000,000 B：分母是实际时间差，不是写死的 1 秒。
        let second = NetworkSpeedSample(counters: NetworkSpeedCounters(receivedBytes: 1_001_000, sentBytes: 2_002_000),
                                        timestamp: start.addingTimeInterval(2))
        switch NetworkSpeedRateCalculator.evaluate(previous: first, current: second) {
        case .rates(let rates):
            expectEqual(rates.downloadBytesPerSecond, 500_000)
            expectEqual(rates.uploadBytesPerSecond, 1_000_000)
        case .baseline, .reset:
            expectTrue(false, "2 秒采样没有产生速率")
        }
    }

    func testCounterResetAndNonAdvancingTime() {
        let start = Date(timeIntervalSince1970: 2_000)
        let previous = NetworkSpeedSample(counters: NetworkSpeedCounters(receivedBytes: 10_000, sentBytes: 10_000),
                                          timestamp: start)
        let wrapped = NetworkSpeedSample(counters: NetworkSpeedCounters(receivedBytes: 10, sentBytes: 10_000),
                                         timestamp: start.addingTimeInterval(1))
        expectEqual(NetworkSpeedRateCalculator.evaluate(previous: previous, current: wrapped), .reset)
        let sameTime = NetworkSpeedSample(counters: NetworkSpeedCounters(receivedBytes: 11_000, sentBytes: 10_000),
                                          timestamp: start)
        expectEqual(NetworkSpeedRateCalculator.evaluate(previous: previous, current: sameTime), .reset)
        let backwards = NetworkSpeedSample(counters: NetworkSpeedCounters(receivedBytes: 11_000, sentBytes: 10_000),
                                           timestamp: start.addingTimeInterval(-1))
        expectEqual(NetworkSpeedRateCalculator.evaluate(previous: previous, current: backwards), .reset)
    }

    // MARK: - Fixtures

    private func interface(_ name: String, up: Bool, running: Bool, loopback: Bool = false,
                           linkType: Bool = true, routable: Bool = false,
                           received: UInt64, sent: UInt64) -> NetworkSpeedInterfaceSnapshot {
        NetworkSpeedInterfaceSnapshot(
            name: name,
            isUp: up, isRunning: running, isLoopback: loopback,
            hasLinkType: linkType, hasRoutableAddress: routable,
            counters: NetworkSpeedCounters(receivedBytes: received, sentBytes: sent))
    }
}
