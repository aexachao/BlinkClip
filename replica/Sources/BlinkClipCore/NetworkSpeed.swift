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
/// 完整格式（tooltip / 设置预览）：1024 进制、一位小数，`1.4 MB/s` / `4.2 B/s`；
/// bps 模式先 ×8，再按 1000 进制、一位小数，`11.2 Mbps` / `259.2 kbps`。
/// 菜单栏紧凑写法：B/s 模式 `↓1.4M ↑32.4K`，bps 模式 `↓11.2M ↑259K`；
/// 不足 1 个单位时保留单位后缀，空闲显示 `↓0B/s ↑0B/s`（宽度稳定，不隐藏）。
public enum NetworkSpeedFormatter {
    private struct Scale {
        let base: Double
        let units: [String]
        let compactUnits: [String]
    }

    private static let byteScale = Scale(base: 1024,
                                         units: ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"],
                                         compactUnits: ["B/s", "K", "M", "G", "T"])
    private static let bitScale = Scale(base: 1000,
                                        units: ["bps", "kbps", "Mbps", "Gbps", "Tbps"],
                                        compactUnits: ["bps", "K", "M", "G", "T"])

    /// 空读数（还没取到基线，或刚从重置里恢复）的菜单栏占位。
    public static let unavailableCompact = "↓— ↑—"

    public static func fullString(bytesPerSecond: Double, unit: NetworkSpeedUnit) -> String {
        let value = unit.isBits ? max(0, bytesPerSecond) * 8 : max(0, bytesPerSecond)
        let scale = unit.isBits ? bitScale : byteScale
        var scaled = scaleRaw(value, in: scale.base, units: scale.units)
        // 一位小数的边界是 999.9K：999.9 KB 不再显示，直接进档成 1.0 MB/s
        // （999.96 KB 同理）。除数仍是 1024，只是不在最后一档显示 999.9。
        if scaled.index < scale.units.count - 1,
           rounded(scaled.value, decimals: 1) >= 999.9 {
            scaled = (scaled.value / scale.base, scaled.index + 1)
        }
        return "\(number(scaled.value, decimals: 1)) \(scale.units[scaled.index])"
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
        let value = unit.isBits ? max(0, bytesPerSecond) * 8 : max(0, bytesPerSecond)
        let scale = unit.isBits ? bitScale : byteScale
        var scaled = scaleRaw(value, in: scale.base, units: scale.compactUnits)
        if scaled.value == 0 { return "0\(scale.compactUnits[scaled.index])" }
        // 三位有效数字的紧凑写法：<100 保留一位小数（1.4M / 32.4K），
        // ≥100 取整（259K / 812K）。
        var decimals = scaled.value < 100 ? 1 : 0
        if scaled.index < scale.compactUnits.count - 1,
           rounded(scaled.value, decimals: decimals) >= 1000 {
            // 999.6K 取整是 1000K；先提升到 MB 再格式化，得到 1.0M。
            scaled = (scaled.value / scale.base, scaled.index + 1)
            decimals = scaled.value < 100 ? 1 : 0
        }
        let number = self.number(scaled.value, decimals: decimals)
        return "\(number)\(scale.compactUnits[scaled.index])"
    }

    /// 按 1024 / 1000 逐级缩放。进档判定留给调用方（完整格式一位小数、
    /// 紧凑格式按有效数字取整），避免出现 `1000.0 KB/s` 这类四位整数。
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
