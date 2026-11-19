import AppKit
import BlinkClipCore
import Combine
import Darwin
import Foundation

/// 菜单栏网速的采集、聚合与 1 秒刷新。
///
/// 采样口径（DESIGN.md「菜单栏网速」一节是同一份说明）：
/// - `sysctl(NET_RT_IFLIST2)` 遍历 `if_msghdr2`，只保留 up + running 的真实链路；
/// - 有活动 VPN 隧道（utun + 非链路本地地址）时只累加隧道，避免物理网卡与隧道重复计数；
/// - 第一次采样只建立基线；计数回绕/重置时重新取基线并跳过本次；
/// - 唤醒后重置基线；开关关闭时取消定时器（0 开销）。
enum NetworkSpeedInterfaceReader {
    static func readInterfaces() -> [NetworkSpeedInterfaceSnapshot] {
        let routable = routableAddressInterfaceNames()
        return routeInterfaceList().map { entry in
            NetworkSpeedInterfaceSnapshot(
                name: entry.name,
                isUp: entry.flags & 0x1 != 0,
                isRunning: entry.flags & 0x40 != 0,
                isLoopback: entry.flags & 0x8 != 0,
                hasLinkType: entry.linkType != 0,
                hasRoutableAddress: routable.contains(entry.name),
                counters: entry.counters)
        }
    }

    private struct RouteEntry {
        let name: String
        let flags: Int32
        let linkType: UInt8
        let counters: NetworkSpeedCounters
    }

    private static func routeInterfaceList() -> [RouteEntry] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard mib.withUnsafeMutableBufferPointer({ sysctl($0.baseAddress!, 6, nil, &length, nil, 0) }) == 0,
              length > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard mib.withUnsafeMutableBufferPointer({ sysctl($0.baseAddress!, 6, &buffer, &length, nil, 0) }) == 0,
              length > 0 else { return [] }

        // RTM_IFINFO2 是 0x12；Darwin 模块在 Swift 里没有导出这个常量。
        let rtmIfInfo2: UInt8 = 0x12
        var entries: [RouteEntry] = []
        buffer.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let pointer = base.advanced(by: offset)
                let header = pointer.assumingMemoryBound(to: if_msghdr.self).pointee
                let messageLength = Int(header.ifm_msglen)
                // 损坏的长度会让游标原地打转；遇到就停止本次解析，保留已读条目。
                guard messageLength > 0, offset + messageLength <= length else { return }
                if header.ifm_type == rtmIfInfo2,
                   offset + MemoryLayout<if_msghdr2>.size <= length {
                    let interface = pointer.assumingMemoryBound(to: if_msghdr2.self).pointee
                    var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ) + 1)
                    if if_indextoname(UInt32(interface.ifm_index), &nameBuffer) != nil {
                        let name = String(cString: nameBuffer)
                        let data = interface.ifm_data
                        entries.append(RouteEntry(
                            name: name,
                            flags: interface.ifm_flags,
                            linkType: data.ifi_type,
                            counters: NetworkSpeedCounters(receivedBytes: data.ifi_ibytes,
                                                           sentBytes: data.ifi_obytes)))
                    }
                }
                offset += messageLength
            }
        }
        return entries
    }

    /// 拿到非链路本地地址的接口名（IPv4 任意地址，或非 `fe80::/10` 的 IPv6）。
    private static func routableAddressInterfaceNames() -> Set<String> {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
        defer { freeifaddrs(addresses) }
        var names: Set<String> = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            let interface = entry.pointee
            cursor = interface.ifa_next
            guard let address = interface.ifa_addr else { continue }
            let name = String(cString: interface.ifa_name)
            switch Int32(address.pointee.sa_family) {
            case AF_INET:
                names.insert(name)
            case AF_INET6:
                let socketAddress = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee }
                var addressBytes = socketAddress.sin6_addr
                let isLinkLocal = withUnsafeBytes(of: &addressBytes) { raw -> Bool in
                    guard raw.count >= 2 else { return true }
                    let bytes = raw.bindMemory(to: UInt8.self)
                    // fe80::/10
                    return bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80
                }
                if !isLinkLocal { names.insert(name) }
            default:
                break
            }
        }
        return names
    }
}

/// 菜单栏网速的偏好键与应用内唯一实例。
///
/// 偏好是应用级 UserDefaults（和 `appLanguage` 同一层），不进剪贴板 store：
/// 它不属于历史数据，也不参与 iCloud 合并。
@MainActor
final class NetworkSpeedMonitor: ObservableObject {
    struct Snapshot: Equatable {
        var isEnabled: Bool
        var unit: NetworkSpeedUnit
        var rates: NetworkSpeedRates?
        /// 定时器采样次数（含基线），用于回归里证明「关掉后真的停了」。
        var sampleCount: Int
        /// 唤醒 / 计数重置导致重新取基线的次数。
        var baselineResetCount: Int
    }

    static let enabledKey = "blinkclip.networkSpeed.enabled"
    static let unitKey = "blinkclip.networkSpeed.unit"

    static let shared = NetworkSpeedMonitor()

    @Published private(set) var snapshot: Snapshot
    @Published private(set) var isRunning = false

    private let defaults: UserDefaults
    private let provider: () -> [NetworkSpeedInterfaceSnapshot]
    private let now: () -> Date
    private let interval: TimeInterval
    private let observesWake: Bool
    private var timer: DispatchSourceTimer?
    private var previous: NetworkSpeedSample?
    private var wakeObserver: NSObjectProtocol?
    private var providerCallCount = 0

    init(defaults: UserDefaults = .standard,
         provider: @escaping () -> [NetworkSpeedInterfaceSnapshot] = NetworkSpeedInterfaceReader.readInterfaces,
         now: @escaping () -> Date = Date.init,
         interval: TimeInterval = 1.0,
         observeWake: Bool = true) {
        self.defaults = defaults
        self.provider = provider
        self.now = now
        self.interval = interval
        self.observesWake = observeWake
        let enabled = defaults.bool(forKey: Self.enabledKey)
        let unit = NetworkSpeedUnit(rawValue: defaults.string(forKey: Self.unitKey) ?? "") ?? .bytesPerSecond
        snapshot = Snapshot(isEnabled: enabled, unit: unit, rates: nil, sampleCount: 0, baselineResetCount: 0)
    }

    deinit {
        timer?.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    /// 当前界面语言的单位回显；设置页直接用它做分段控件绑定。
    var unit: NetworkSpeedUnit { snapshot.unit }

    func setEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled {
            snapshot.isEnabled = true
            start()
        } else {
            stop()
            snapshot.isEnabled = false
        }
    }

    func setUnit(_ unit: NetworkSpeedUnit) {
        guard snapshot.unit != unit else { return }
        defaults.set(unit.rawValue, forKey: Self.unitKey)
        snapshot.unit = unit
    }

    /// 打开开关：立刻取一次基线，之后每 `interval` 秒采样一次。
    func start() {
        guard timer == nil else { return }
        previous = nil
        sampleNow()
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + interval, repeating: interval,
                        leeway: .milliseconds(200))
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.sampleNow() }
        }
        source.resume()
        timer = source
        isRunning = true
        installWakeObserverIfNeeded()
    }

    /// 唤醒监听只在开关打开期间存在：关闭后不保留任何观察者或定时器。
    private func installWakeObserverIfNeeded() {
        guard observesWake, wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        }
    }

    private func removeWakeObserver() {
        guard let wakeObserver else { return }
        NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        self.wakeObserver = nil
    }

    /// 关闭开关：取消定时器，不保留任何后台唤醒源。
    func stop() {
        timer?.cancel()
        timer = nil
        isRunning = false
        previous = nil
        snapshot.rates = nil
        removeWakeObserver()
    }

    /// 唤醒后重置基线：下一拍重新取基线，不会用睡眠前的累计值算出一个巨大的瞬时速率。
    func handleWake() {
        guard snapshot.isEnabled else { return }
        previous = nil
        snapshot.rates = nil
        snapshot.baselineResetCount += 1
        sampleNow()
    }

    /// 单次采样。测试注入假 provider 后直接驱动它，验证基线 / 回绕 / 时间差口径。
    func sampleNow() {
        providerCallCount += 1
        let counters = NetworkSpeedAggregator.counters(in: provider())
        let current = NetworkSpeedSample(counters: counters, timestamp: now())
        switch NetworkSpeedRateCalculator.evaluate(previous: previous, current: current) {
        case .baseline, .reset:
            previous = current
            snapshot.rates = nil
        case .rates(let rates):
            previous = current
            snapshot.rates = rates
        }
        snapshot.sampleCount += 1
    }

    /// 测试与诊断用：断言关掉开关后 provider 不再被调用。
    var providerInvocations: Int { providerCallCount }
}
