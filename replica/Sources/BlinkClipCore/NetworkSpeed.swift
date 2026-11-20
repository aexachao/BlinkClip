import Foundation

/// 菜单栏网速的单位口径。
///
/// - `bytesPerSecond`：B/s、KB/s、MB/s、GB/s，1024 进制（用户看到的文件大小单位）。
/// - `bitsPerSecond`：bps、kbps、Mbps、Gbps，1000 进制（运营商与网络工具的口径）。
public enum NetworkSpeedUnit: String, CaseIterable, Codable, Sendable {
    case bytesPerSecond = "bytes"
    case bitsPerSecond = "bits"

    public var isBits: Bool { self == .bitsPerSecond }
}

/// 一个接口（或一组接口）自开机以来累计的收发字节数。
public struct NetworkSpeedCounters: Equatable, Sendable {
    public var receivedBytes: UInt64
    public var sentBytes: UInt64

    public init(receivedBytes: UInt64 = 0, sentBytes: UInt64 = 0) {
        self.receivedBytes = receivedBytes
        self.sentBytes = sentBytes
    }

    public static let zero = NetworkSpeedCounters()

    public static func + (lhs: NetworkSpeedCounters, rhs: NetworkSpeedCounters) -> NetworkSpeedCounters {
        NetworkSpeedCounters(receivedBytes: lhs.receivedBytes &+ rhs.receivedBytes,
                             sentBytes: lhs.sentBytes &+ rhs.sentBytes)
    }

    public var isZero: Bool { receivedBytes == 0 && sentBytes == 0 }
}

/// `NET_RT_IFLIST2` 里一个 `if_msghdr2` 的纯数据投影。
///
/// 采集层（应用目标里的 `NetworkSpeedInterfaceReader`）负责把 Darwin 结构体翻成
/// 这个结构；口径判定与累加放在这里，核心测试不需要真实网卡。
public struct NetworkSpeedInterfaceSnapshot: Equatable, Sendable {
    public var name: String
    public var isUp: Bool
    public var isRunning: Bool
    public var isLoopback: Bool
    /// 有链路类型（`ifi_type != 0`）。`gif0` / `stf0` 这类没有链路层的接口不参与统计。
    public var hasLinkType: Bool
    /// 持有非链路本地地址（IPv4 任意地址，或非 `fe80::/10` 的 IPv6）。
    ///
    /// macOS 常驻的 `utun0…`（iCloud Private Relay、Back to My Mac 等）只有
    /// `fe80::` 链路本地地址；真正的 VPN 隧道在建连后才会拿到 `inet 10.x` 或
    /// 全局 IPv6。这个标记只用于「VPN 口径」的判定，不参与物理网卡累加。
    public var hasRoutableAddress: Bool
    public var counters: NetworkSpeedCounters

    public init(name: String, isUp: Bool, isRunning: Bool, isLoopback: Bool,
                hasLinkType: Bool, hasRoutableAddress: Bool = false,
                counters: NetworkSpeedCounters = .zero) {
        self.name = name
        self.isUp = isUp
        self.isRunning = isRunning
        self.isLoopback = isLoopback
        self.hasLinkType = hasLinkType
        self.hasRoutableAddress = hasRoutableAddress
        self.counters = counters
    }

    public var isUtun: Bool { name.hasPrefix("utun") }

    /// 只统计 up + running 的真实链路（loopback 与无链路层接口都排除）。
    public var isEligible: Bool { isUp && isRunning && !isLoopback && hasLinkType }

    /// VPN 口径里的「隧道在跑」：接口本身可用、是 utun、并且真的拿到了隧道地址。
    public var isActiveTunnel: Bool { isEligible && isUtun && hasRoutableAddress }
}

/// 累加口径：有活动 VPN 隧道时只算隧道（物理网卡与隧道会重复计数），否则算全部物理接口。
public enum NetworkSpeedInterfaceSelection: Equatable, Sendable {
    case tunnel
    case physical
    case none
}

public enum NetworkSpeedAggregator {
    public static func eligibleInterfaces(in interfaces: [NetworkSpeedInterfaceSnapshot])
        -> [NetworkSpeedInterfaceSnapshot] {
        interfaces.filter(\.isEligible)
    }

    /// 选择口径。`utun` 优先级只看**活动隧道**：常驻但只有链路本地地址的 utun
    /// 不接管统计，否则普通上网会被算成 0。
    public static func selection(in interfaces: [NetworkSpeedInterfaceSnapshot])
        -> NetworkSpeedInterfaceSelection {
        let eligible = eligibleInterfaces(in: interfaces)
        guard !eligible.isEmpty else { return .none }
        return eligible.contains(where: \.isActiveTunnel) ? .tunnel : .physical
    }

    public static func counters(in interfaces: [NetworkSpeedInterfaceSnapshot]) -> NetworkSpeedCounters {
        let eligible = eligibleInterfaces(in: interfaces)
        switch selection(in: interfaces) {
        case .tunnel:
            return eligible.filter(\.isActiveTunnel).reduce(.zero) { $0 + $1.counters }
        case .physical:
            return eligible.filter { !$0.isUtun }.reduce(.zero) { $0 + $1.counters }
        case .none:
            return .zero
        }
    }
}

/// 一次采样的累计值 + 实际采样时间。速率分母用两次采样的时间差，不用固定 1 秒。
public struct NetworkSpeedSample: Equatable, Sendable {
    public var counters: NetworkSpeedCounters
    public var timestamp: Date

    public init(counters: NetworkSpeedCounters, timestamp: Date) {
        self.counters = counters
        self.timestamp = timestamp
    }
}

public struct NetworkSpeedRates: Equatable, Sendable {
    public var downloadBytesPerSecond: Double
    public var uploadBytesPerSecond: Double

    public init(downloadBytesPerSecond: Double, uploadBytesPerSecond: Double) {
        self.downloadBytesPerSecond = downloadBytesPerSecond
        self.uploadBytesPerSecond = uploadBytesPerSecond
    }

    public static let zero = NetworkSpeedRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0)
}

/// 两次采样之间的结果：第一次只取基线；计数回绕/重置也要重新取基线并跳过本次。
public enum NetworkSpeedSampleResult: Equatable, Sendable {
    case baseline
    case reset
    case rates(NetworkSpeedRates)
}

public enum NetworkSpeedRateCalculator {
    public static func evaluate(previous: NetworkSpeedSample?,
                                current: NetworkSpeedSample) -> NetworkSpeedSampleResult {
        guard let previous else { return .baseline }
        let elapsed = current.timestamp.timeIntervalSince(previous.timestamp)
        // 时间没有前进（例如唤醒后时钟被校正）时不产生速率，重新取基线。
        guard elapsed > 0 else { return .reset }
        // 累计值变小说明接口计数被重置或回绕；本次不显示数字。
        guard current.counters.receivedBytes >= previous.counters.receivedBytes,
              current.counters.sentBytes >= previous.counters.sentBytes else { return .reset }
        let received = current.counters.receivedBytes - previous.counters.receivedBytes
        let sent = current.counters.sentBytes - previous.counters.sentBytes
        return .rates(NetworkSpeedRates(downloadBytesPerSecond: Double(received) / elapsed,
                                        uploadBytesPerSecond: Double(sent) / elapsed))
    }
}

/// 菜单栏文字与 tooltip 的格式化。
///
/// 单位只有四档：`B`、`KB`、`MB`、`GB`（bps 模式对应 `bps`、`kbps`、`Mbps`、`Gbps`）。
/// 小数位按 **macOS 风格自适应**：B 档固定 **0 位**；KB/MB/GB 里数值 **< 100 用 1 位、
/// ≥ 100 用 0 位**（B/s 走 1024 进制，bps 先 ×8、走 1000 进制）。
///
/// | 读数 | 完整写法（tooltip / 设置页 / VoiceOver） | 菜单栏紧凑写法 |
/// |---|---|---|
/// | 0 B | `0 B/s` | `0B` |
/// | 4 B | `4 B/s` | `4B` |
/// | 512 B | `512 B/s` | `512B` |
/// | 32.4 KB | `32.4 KB/s` | `32.4K` |
/// | 812 KB | `812 KB/s` | `812K` |
/// | 1.4 MB | `1.4 MB/s` | `1.4M` |
/// | 9.8 MB | `9.8 MB/s` | `9.8M` |
/// | 340 MB | `340 MB/s` | `340M` |
/// | 999 GB | `999 GB/s` | `999G` |
///
/// 菜单栏紧凑写法只是把完整写法的空格与 `/s` 去掉；tooltip 的完整读法是
/// `下载 812 KB/s · 上传 32.4 KB/s`。不足 1 个单位时保留单位字母，空闲显示
/// `↓0B ↑0B`（宽度稳定，不隐藏），首拍占位 `↓— ↑—`。
///
/// 进位与降级：显示值到 999.x 就进下一档，所以任一档最多 3 位整数——0 位小数时是
/// `999`、1 位小数时是 `99.9`。0 位小数档按 `≥ 999.5` 进档（`999.6 KB/s` →
/// `1.0 MB/s`，除数仍是 1024），不会出现 `1000KB/s` 这种四位整数；1 位小数只出现在
/// < 100 的区间，99.96 这种「一位小数会进位成 100.0」的读数直接按整数显示（`100K`），
/// 不会出现 `100.0K`。末档 GB 无处可进（显示值到 999.x），降级成 `>999 GB/s`
/// （菜单栏 `>999G`）——它比最宽正常串 `99.9M` 宽 1.85pt，仍在固定文字区内。
public enum NetworkSpeedFormatter {
    private struct Scale {
        let base: Double
        let units: [String]
        let compactUnits: [String]
        /// 末档放不下时的完整写法（tooltip / 设置预览）。
        let degraded: String
        /// 末档放不下时的菜单栏紧凑写法。
        let degradedCompact: String
    }

    private static let byteScale = Scale(base: 1024,
                                         units: ["B/s", "KB/s", "MB/s", "GB/s"],
                                         compactUnits: ["B", "K", "M", "G"],
                                         degraded: ">999 GB/s",
                                         degradedCompact: ">999G")
    private static let bitScale = Scale(base: 1000,
                                        units: ["bps", "kbps", "Mbps", "Gbps"],
                                        compactUnits: ["b", "K", "M", "G"],
                                        degraded: ">999 Gbps",
                                        degradedCompact: ">999G")

    /// 空读数（还没取到基线，或刚从重置里恢复）的菜单栏占位。
    public static let unavailableCompact = "↓— ↑—"

    public static func fullString(bytesPerSecond: Double, unit: NetworkSpeedUnit) -> String {
        let scale = unit.isBits ? bitScale : byteScale
        let shown = presented(bytesPerSecond, unit: unit, scale: scale)
        guard !shown.degraded else { return scale.degraded }
        return "\(shown.number) \(scale.units[shown.index])"
    }

    public static func compactString(downloadBytesPerSecond: Double?, uploadBytesPerSecond: Double?,
                                     unit: NetworkSpeedUnit) -> String {
        guard let download = downloadBytesPerSecond, let upload = uploadBytesPerSecond else {
            return unavailableCompact
        }
        return "↓\(compact(download, unit: unit)) ↑\(compact(upload, unit: unit))"
    }

    /// 菜单栏两段速度（供状态栏渲染复用，保持箭头与空格一致）。
    public static func menuBarTitle(downloadBytesPerSecond: Double?, uploadBytesPerSecond: Double?,
                                    unit: NetworkSpeedUnit) -> String {
        compactString(downloadBytesPerSecond: downloadBytesPerSecond,
                      uploadBytesPerSecond: uploadBytesPerSecond, unit: unit)
    }

    private static func compact(_ bytesPerSecond: Double, unit: NetworkSpeedUnit) -> String {
        let scale = unit.isBits ? bitScale : byteScale
        let shown = presented(bytesPerSecond, unit: unit, scale: scale)
        guard !shown.degraded else { return scale.degradedCompact }
        // 紧凑写法只是把完整写法的空格与 `/s` 去掉：`4 B/s` → `4B`、`812 KB/s` → `812K`、
        // `32.4 KB/s` → `32.4K`。
        return "\(shown.number)\(scale.compactUnits[shown.index])"
    }

    /// 把字节/比特值落到「自适应小数的数字 + 档位」，两种写法共用同一份进位口径。
    ///
    /// - `number`：按小数位格式化后的数字（`4`、`512`、`32.4`、`812`、`999`）；
    /// - `index`：档位下标，配合完整单位表或紧凑单位表取后缀；
    /// - `degraded`：末档（GB / Gbps）显示值到 999.x、无处可进，调用方改用降级串。
    private static func presented(_ bytesPerSecond: Double, unit: NetworkSpeedUnit,
                                  scale: Scale) -> (number: String, index: Int, degraded: Bool) {
        let value = unit.isBits ? max(0, bytesPerSecond) * 8 : max(0, bytesPerSecond)
        var scaled = scaleRaw(value, in: scale.base, units: scale.units)
        // 999.x 是显示层的一档边界：0 位小数时即「四舍五入到 ≥ 999.5」，999.6 KB 不再
        // 显示成 1000 KB，而是 1.0 MB（除数仍是 1024）。末档已经无档可进，交给降级串。
        if rounded(scaled.value, decimals: 0) >= 999.5 {
            guard scaled.index < scale.units.count - 1 else {
                return ("", scaled.index, true)
            }
            scaled = (scaled.value / scale.base, scaled.index + 1)
        }
        return (number(scaled.value, decimals: decimals(scaled)), scaled.index, false)
    }

    /// 自适应小数位：B 档（第一档）固定 **0 位**；KB/MB/GB 数值 **< 100 时 1 位、
    /// ≥ 100 时 0 位**。
    ///
    /// 99.96 这种「一位小数会进位成 100.0」的读数按 100 处理、改按整数显示（`100K`），
    /// 所以 1 位小数的写法最多到 `99.9`（4 个字符），0 位小数最多到 `999`（3 个字符）。
    private static func decimals(_ scaled: (value: Double, index: Int)) -> Int {
        guard scaled.index > 0, scaled.value < 100,
              rounded(scaled.value, decimals: 1) < 100 else { return 0 }
        return 1
    }

    /// 按 1024 / 1000 逐级缩放，最多升到最后一档（GB / Gbps）。
    /// 999.x 的显示进位留给调用方（`presented`），避免出现 `1000 KB/s` 这类四位整数。
    private static func scaleRaw(_ value: Double, in base: Double, units: [String])
        -> (value: Double, index: Int) {
        var scaled = value
        var index = 0
        while scaled >= base, index < units.count - 1 {
            scaled /= base
            index += 1
        }
        return (scaled, index)
    }

    private static func rounded(_ value: Double, decimals: Int) -> Double {
        let factor = pow(10.0, Double(decimals))
        return (value * factor).rounded() / factor
    }

    private static func number(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
