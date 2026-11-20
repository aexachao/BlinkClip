import Foundation
import BlinkClipCore

/// 菜单栏网速的纯函数口径：接口选择、基线/回绕、速率分母与两种格式。
///
/// 这些测试不读真实网卡，注入 `NetworkSpeedInterfaceSnapshot` 与采样时间，
/// 因此 VPN 口径、计数器重置、999.x 进位边界与末档降级都能稳定复现。
///
/// 单位只有四档：B、KB、MB、GB（bps 模式 bps、kbps、Mbps、Gbps）。
/// 小数位是 macOS 风格自适应：B 档 0 位；KB/MB/GB 里 < 100 一位、≥ 100 无位。
struct NetworkSpeedTests {
    // MARK: - 格式

    func testByteFormatting() {
        // ① B 档（< 1024 B）没有小数位。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 0, unit: .bytesPerSecond),
                    "0 B/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 4.2, unit: .bytesPerSecond),
                    "4 B/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 512, unit: .bytesPerSecond),
                    "512 B/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 999, unit: .bytesPerSecond),
                    "999 B/s")
        // ② KB/MB/GB 里数值 < 100 保留一位小数。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 33_178, unit: .bytesPerSecond),
                    "32.4 KB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_468_006, unit: .bytesPerSecond),
                    "1.4 MB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 99.94 * 1_048_576,
                                                     unit: .bytesPerSecond),
                    "99.9 MB/s")
        // ③ 数值 ≥ 100 不显示小数。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 831_795, unit: .bytesPerSecond),
                    "812 KB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 340 * 1_048_576,
                                                     unit: .bytesPerSecond),
                    "340 MB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_073_741_824, unit: .bytesPerSecond),
                    "1.0 GB/s")
        // ④ 进位边界：显示值到 999.x 就进下一档（0 位小数时即「四舍五入到 ≥ 999.5」）。
        //    999.6 B 进 KB、999.4 KB 还在 KB、999.6 KB 进 MB；除数仍是 1024。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 999.6, unit: .bytesPerSecond),
                    "1.0 KB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_023_385, unit: .bytesPerSecond),
                    "999 KB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_023_590, unit: .bytesPerSecond),
                    "1.0 MB/s")
        // 99.96 M 的「一位小数」会进位成 100.0，于是改按整数显示，不会出现 `100.0M`。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 99.96 * 1_048_576,
                                                     unit: .bytesPerSecond),
                    "100 MB/s")
        // 1024 进制 + 进位：1023 B 与 1024 B 都显示 1.0 KB/s（不会出现 1023 B/s 的四位数）。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_023, unit: .bytesPerSecond),
                    "1.0 KB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_024, unit: .bytesPerSecond),
                    "1.0 KB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_024 * 1_024, unit: .bytesPerSecond),
                    "1.0 MB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_023_897, unit: .bytesPerSecond),
                    "1.0 MB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_023_959, unit: .bytesPerSecond),
                    "1.0 MB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 999 * 1_073_741_824,
                                                     unit: .bytesPerSecond),
                    "999 GB/s")
        // ⑤ 末档（GB）无档可进：显示值到 999.x 落成降级串，而不是 TB 或四位整数。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_024 * 1_073_741_824,
                                                     unit: .bytesPerSecond),
                    ">999 GB/s")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 20_480 * 1_073_741_824,
                                                     unit: .bytesPerSecond),
                    ">999 GB/s")
    }

    func testBitsFormatting() {
        // bps 先 ×8、1000 进制，小数位同样自适应。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_400_000, unit: .bitsPerSecond),
                    "11.2 Mbps")
        // 259.2 kbps ≥ 100 → 无小数。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 32_400, unit: .bitsPerSecond),
                    "259 kbps")
        // 32 bps 是第一档 → 0 位。
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 4, unit: .bitsPerSecond),
                    "32 bps")
        expectEqual(NetworkSpeedFormatter.fullString(bytesPerSecond: 0, unit: .bitsPerSecond),
                    "0 bps")
    }

    func testCompactMenuBarTitle() {
        // 紧凑写法 = 完整写法去掉空格与 `/s`：同样自适应小数，四档单位字母 B/K/M/G。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_468_006,
                                                        uploadBytesPerSecond: 33_178, unit: .bytesPerSecond),
                    "↓1.4M ↑32.4K")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 831_795,
                                                        uploadBytesPerSecond: 4.2, unit: .bytesPerSecond),
                    "↓812K ↑4B")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_073_741_824,
                                                        uploadBytesPerSecond: 1_024 * 1_024,
                                                        unit: .bytesPerSecond),
                    "↓1.0G ↑1.0M")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_400_000,
                                                        uploadBytesPerSecond: 32_400, unit: .bitsPerSecond),
                    "↓11.2M ↑259K")
        // B 档没有小数位，空闲也是 `0B`（宽度稳定、不隐藏）。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 0,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓0B ↑0B")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 0,
                                                        uploadBytesPerSecond: 0, unit: .bitsPerSecond),
                    "↓0b ↑0b")
        // 首采样只有基线：占位符而不是数字。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: nil,
                                                        uploadBytesPerSecond: nil, unit: .bytesPerSecond),
                    "↓— ↑—")
        // 进位边界（显示值到 999.x 进下一档）：999.4 KB 原样是 `999K`，
        // 999.6 KB 进档成 `1.0M`，不会出现 `1000K`。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_023_385,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓999K ↑0B")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_023_590,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓1.0M ↑0B")
        // 99.96 M 的「一位小数」会变成 100.0，所以直接按 `100M` 显示。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 99.94 * 1_048_576,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓99.9M ↑0B")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 99.96 * 1_048_576,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓100M ↑0B")
        // 末档（G）无档可进：显示值到 999.x 显示降级串 `>999G`（它现在是整条里最宽的串）。
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_024 * 1_073_741_824,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓>999G ↑0B")
        expectEqual(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 20_480 * 1_073_741_824,
                                                        uploadBytesPerSecond: 0, unit: .bytesPerSecond),
                    "↓>999G ↑0B")
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
