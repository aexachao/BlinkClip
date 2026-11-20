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
///  - 菜单栏唯一呈现：两行（上 `↑` 上传 / 下 `↓` 下载）、固定宽度、左对齐、无补位无字距；
///  - macOS 风格自适应小数（B 档 0 位、KB/MB/GB < 100 一位、≥ 100 无位）与四档进位、
///    末档降级串 `>999G`；
///  - tooltip / 无障碍描述的完整写法（`下载 812 KB/s · 上传 32.4 KB/s`）与关闭态 24pt。
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

    /// 把模板图按 2x 画进位图，返回 `(x, y)` 上有墨（alpha ≥ 0.25）的行列信息。
    /// 位图第 0 行是图片顶边（`NSImage` 画进未翻转的位图上下文时内容仍是正立的）。
    static func rasterize(_ image: NSImage, scale: Int = 2) -> NSBitmapImageRep? {
        let width = Int((image.size.width * CGFloat(scale)).rounded())
        let height = Int((image.size.height * CGFloat(scale)).rounded())
        guard width > 0, height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: image.size.width, height: image.size.height)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    struct InkBand: Equatable {
        var minRow: Int
        var maxRow: Int
        var minColumn: Int
        var maxColumn: Int
        var height: Int { maxRow - minRow + 1 }
        var width: Int { maxColumn - minColumn + 1 }
    }

    /// 在给定的列范围内找有墨的连续行带；行带之间空一行以上就算两段。
    static func inkBands(_ rep: NSBitmapImageRep, columns: Range<Int>) -> [InkBand] {
        var bands: [InkBand] = []
        var current: InkBand?
        for row in 0..<rep.pixelsHigh {
            var minColumn: Int?
            var maxColumn: Int?
            for column in columns where (rep.colorAt(x: column, y: row)?.alphaComponent ?? 0) >= 0.25 {
                if minColumn == nil { minColumn = column }
                maxColumn = column
            }
            if let minColumn, let maxColumn {
                if var band = current {
                    band.maxRow = row
                    band.minColumn = min(band.minColumn, minColumn)
                    band.maxColumn = max(band.maxColumn, maxColumn)
                    current = band
                } else {
                    current = InkBand(minRow: row, maxRow: row, minColumn: minColumn, maxColumn: maxColumn)
                }
            } else if let band = current {
                bands.append(band)
                current = nil
            }
        }
        if let band = current { bands.append(band) }
        return bands
    }

    static func hasInk(_ rep: NSBitmapImageRep, columns: Range<Int>) -> Bool {
        columns.contains { column in
            (0..<rep.pixelsHigh).contains { row in
                (rep.colorAt(x: column, y: row)?.alphaComponent ?? 0) >= 0.25
            }
        }
    }

    /// 文字在给定字体下的排版宽度（和 `NetworkSpeedStatusItem` 用同一份几何）。
    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
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

        // ---- 格式：自适应小数（B 档 0 位、< 100 一位、≥ 100 无位）与四档进位 ------
        let carrySamples: [(Double, String, String)] = [
            // ① B 档（< 1024 B）没有小数位。
            (0, "0 B/s", "0B"),
            (4.2, "4 B/s", "4B"),
            (512, "512 B/s", "512B"),
            (999, "999 B/s", "999B"),
            (999.6, "1.0 KB/s", "1.0K"),
            (1_024, "1.0 KB/s", "1.0K"),
            // ② KB/MB/GB 里 < 100 保留一位小数。
            (33_178, "32.4 KB/s", "32.4K"),
            (99.94 * 1_048_576, "99.9 MB/s", "99.9M"),
            (1_468_006, "1.4 MB/s", "1.4M"),
            // ③ ≥ 100 不显示小数。
            (831_795, "812 KB/s", "812K"),
            (340 * 1_048_576.0, "340 MB/s", "340M"),
            (1_073_741_824, "1.0 GB/s", "1.0G"),
            (999 * 1_073_741_824.0, "999 GB/s", "999G"),
        ]
        for (bytes, full, compact) in carrySamples {
            check(NetworkSpeedFormatter.fullString(bytesPerSecond: bytes, unit: .bytesPerSecond) == full,
                  "完整格式 \(bytes) B/s 不对：\(NetworkSpeedFormatter.fullString(bytesPerSecond: bytes, unit: .bytesPerSecond))")
            let compactTitle = NetworkSpeedFormatter.compactString(downloadBytesPerSecond: bytes,
                                                                   uploadBytesPerSecond: 0,
                                                                   unit: .bytesPerSecond)
            check(compactTitle == "↓\(compact) ↑0B",
                  "紧凑格式 \(bytes) B/s 不对：\(compactTitle)")
        }
        // ④ 进位边界：显示值到 999.x 就进下一档，0 位小数时即「四舍五入到 ≥ 999.5」。
        //    999 B 还在 B 档、999.6 B 进 KB；999.4 KB 还在 KB、999.6 KB 进 MB；
        //    99.96 M 的「一位小数」会变成 100.0，于是直接按整数显示 `100M`。
        let boundaries: [(Double, String, String)] = [
            (999, "999 B/s", "999B"),
            (999.6, "1.0 KB/s", "1.0K"),
            (1_023_385, "999 KB/s", "999K"),      // 999.3994 KB
            (1_023_590, "1.0 MB/s", "1.0M"),      // 999.5996 KB
            (99.94 * 1_048_576, "99.9 MB/s", "99.9M"),
            (99.96 * 1_048_576, "100 MB/s", "100M"),
            (999 * 1_073_741_824.0, "999 GB/s", "999G"),
        ]
        for (bytes, full, compact) in boundaries {
            check(NetworkSpeedFormatter.fullString(bytesPerSecond: bytes, unit: .bytesPerSecond) == full,
                  "进位边界 \(bytes) B/s 不对：\(NetworkSpeedFormatter.fullString(bytesPerSecond: bytes, unit: .bytesPerSecond))")
            check(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: bytes,
                                                      uploadBytesPerSecond: 0,
                                                      unit: .bytesPerSecond) == "↓\(compact) ↑0B",
                  "进位边界紧凑写法 \(bytes) B/s 不对")
        }
        // ⑤ 末档（GB）无处可进：≥ 999.5 GB 落成降级串，完整写法给 `>999 GB/s`。
        let beyondGigabytes = 1_024 * 1_073_741_824.0
        check(NetworkSpeedFormatter.fullString(bytesPerSecond: beyondGigabytes, unit: .bytesPerSecond)
              == ">999 GB/s",
              "GB 档以上没有降级：\(NetworkSpeedFormatter.fullString(bytesPerSecond: beyondGigabytes, unit: .bytesPerSecond))")
        let degradedTitle = NetworkSpeedFormatter.compactString(downloadBytesPerSecond: beyondGigabytes,
                                                                uploadBytesPerSecond: beyondGigabytes,
                                                                unit: .bytesPerSecond)
        check(degradedTitle == "↓>999G ↑>999G", "紧凑降级串不对：\(degradedTitle)")
        let degradedTooltip = NetworkSpeedStatusItem.toolTip(
            rates: NetworkSpeedRates(downloadBytesPerSecond: beyondGigabytes,
                                     uploadBytesPerSecond: beyondGigabytes),
            unit: .bytesPerSecond)
        check(degradedTooltip.contains(">999 GB/s"), "tooltip 没有给降级单位：\(degradedTooltip)")
        // bps 模式同样四档、同样自适应小数：×8、1000 进制。
        check(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_400_000, unit: .bitsPerSecond) == "11.2 Mbps",
              "bps 完整格式不对：\(NetworkSpeedFormatter.fullString(bytesPerSecond: 1_400_000, unit: .bitsPerSecond))")
        check(NetworkSpeedFormatter.fullString(bytesPerSecond: 32_400, unit: .bitsPerSecond) == "259 kbps",
              "bps ≥ 100 应无小数：\(NetworkSpeedFormatter.fullString(bytesPerSecond: 32_400, unit: .bitsPerSecond))")
        check(NetworkSpeedFormatter.fullString(bytesPerSecond: 4, unit: .bitsPerSecond) == "32 bps",
              "bps 第一档应无小数：\(NetworkSpeedFormatter.fullString(bytesPerSecond: 4, unit: .bitsPerSecond))")
        check(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_400_000,
                                                  uploadBytesPerSecond: 32_400,
                                                  unit: .bitsPerSecond) == "↓11.2M ↑259K",
              "bps 紧凑格式不对：\(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 1_400_000, uploadBytesPerSecond: 32_400, unit: .bitsPerSecond))")
        check(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0,
                                                  unit: .bytesPerSecond) == "↓0B ↑0B",
              "空闲紧凑格式不对：\(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, unit: .bytesPerSecond))")
        check(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0,
                                                  unit: .bitsPerSecond) == "↓0b ↑0b",
              "空闲 bps 紧凑格式不对：\(NetworkSpeedFormatter.compactString(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0, unit: .bitsPerSecond))")

        // ⑥ tooltip / 设置页 / VoiceOver 的完整写法：同一份自适应小数 + `/s` 后缀。
        let tooltip = NetworkSpeedStatusItem.toolTip(
            rates: NetworkSpeedRates(downloadBytesPerSecond: 831_795, uploadBytesPerSecond: 33_178),
            unit: .bytesPerSecond)
        check(tooltip.contains("812 KB/s") && tooltip.contains("32.4 KB/s") && tooltip.contains(" · "),
              "tooltip 完整写法不对：\(tooltip)")

        // ---- ① 唯一呈现：只有两行，没有单行路径 -----------------------------
        let rates = NetworkSpeedRates(downloadBytesPerSecond: 1_468_006,
                                      uploadBytesPerSecond: 33_178)
        let icon = ReplicaBrand.menuBarImage()
        let lines = NetworkSpeedStatusItem.lines(rates: rates, unit: .bytesPerSecond)
        // ---- ② 第一行 `↑`（上传）、第二行 `↓`（下载） -----------------------
        check(lines.upload == "↑32.4K", "第一行（上传）不对：\(lines.upload)")
        check(lines.download == "↓1.4M", "第二行（下载）不对：\(lines.download)")
        check(lines.upload.hasPrefix("↑") && lines.download.hasPrefix("↓"),
              "两行箭头不对：\(lines)")
        let emptyLines = NetworkSpeedStatusItem.lines(rates: nil, unit: .bytesPerSecond)
        check(emptyLines.upload == "↑—" && emptyLines.download == "↓—",
              "首拍两行占位不对：\(emptyLines)")
        let bitLines = NetworkSpeedStatusItem.lines(
            rates: NetworkSpeedRates(downloadBytesPerSecond: 1_400_000, uploadBytesPerSecond: 32_400),
            unit: .bitsPerSecond)
        check(bitLines.upload == "↑259K" && bitLines.download == "↓11.2M",
              "bps 两行不对：\(bitLines)")

        // ---- ⑤ 不再补位、不再补字距 -----------------------------------------
        check(!lines.upload.contains("\u{2007}") && !lines.download.contains("\u{2007}"),
              "两行里仍有 U+2007 补位：\(lines)")
        let attributes = NetworkSpeedStatusItem.rowAttributes(color: .black)
        check(attributes[.kern] == nil, "两行文字仍带 kern 字距")
        check(Set(attributes.keys) == [.font, .foregroundColor],
              "两行文字属性多出了别的键：\(attributes.keys)")

        // ---- 图几何：固定 62×22pt -------------------------------------------
        let image = NetworkSpeedStatusItem.twoLinesImage(icon: icon, rates: rates,
                                                         unit: .bytesPerSecond)
        check(abs(image.size.width - NetworkSpeedStatusItem.FixedWidth.imageWidth) < 0.01,
              "两行图宽不是固定 \(NetworkSpeedStatusItem.FixedWidth.imageWidth)：\(image.size.width)")
        check(image.size.height <= NetworkSpeedStatusItem.TwoLines.maxHeight,
              "两行图高 \(image.size.height) 超过菜单栏可用高度 22pt")
        check(abs(image.size.height - 22) < 0.01,
              "两行图高应正好两行行高（22pt），实际 \(image.size.height)")
        check(image.isTemplate, "两行图不是模板图（深色/高亮会看不清）")
        // VoiceOver 走完整写法（与 tooltip 同一份字符串、同样自适应小数）。
        let imageDescription = image.accessibilityDescription ?? "nil"
        check(imageDescription == NetworkSpeedStatusItem.toolTip(rates: rates, unit: .bytesPerSecond),
              "无障碍描述不是 tooltip 的完整写法：\(imageDescription)")
        check(imageDescription.contains("1.4 MB/s") && imageDescription.contains("32.4 KB/s"),
              "无障碍描述缺完整读数：\(imageDescription)")
        check(!imageDescription.contains("\u{2007}"),
              "无障碍描述里仍有补位字符")

        // 宽度预算：最宽正常串与降级串都必须落在固定文字区内。
        let widestRow = NetworkSpeedStatusItem.FixedWidth.widestLine
        let widestMeasured = textWidth(widestRow, font: NetworkSpeedStatusItem.TwoLines.font)
        let degradeMeasured = textWidth(NetworkSpeedStatusItem.FixedWidth.degradedLine,
                                        font: NetworkSpeedStatusItem.TwoLines.font)
        check(abs(widestMeasured - NetworkSpeedStatusItem.FixedWidth.widestLineWidth) < 0.05,
              "最宽串实测 \(widestMeasured)pt 与常量 \(NetworkSpeedStatusItem.FixedWidth.widestLineWidth)pt 不符")
        check(abs(degradeMeasured - NetworkSpeedStatusItem.FixedWidth.degradedLineWidth) < 0.05,
              "降级串实测 \(degradeMeasured)pt 与常量 \(NetworkSpeedStatusItem.FixedWidth.degradedLineWidth)pt 不符")
        check(widestMeasured <= NetworkSpeedStatusItem.FixedWidth.textWidth,
              "最宽正常串 \(widestMeasured)pt 放不进 \(NetworkSpeedStatusItem.FixedWidth.textWidth)pt 文字区")
        // 自适应小数之后降级串反而更宽（`>999` 比三位数字宽），文字区必须同时容下它。
        check(degradeMeasured > widestMeasured,
              "降级串 \(degradeMeasured)pt 应该比最宽正常串 \(widestMeasured)pt 宽")
        check(degradeMeasured <= NetworkSpeedStatusItem.FixedWidth.textWidth,
              "降级串 \(degradeMeasured)pt 放不进固定文字区")
        check(NetworkSpeedStatusItem.FixedWidth.imageWidth
              == NetworkSpeedStatusItem.TwoLines.iconWidth + NetworkSpeedStatusItem.TwoLines.iconGap
                 + NetworkSpeedStatusItem.FixedWidth.textWidth,
              "图宽不是「图标 + 间距 + 文字区」")

        // ---- 像素证据：两行、上↑下↓、左对齐 ---------------------------------
        // 用一个「上传比下载宽很多」的读数：`↑812K`（30.80pt）在上、`↓0B`（19.12pt）在下。
        let lopsided = NetworkSpeedRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 831_795)
        let lopsidedLines = NetworkSpeedStatusItem.lines(rates: lopsided, unit: .bytesPerSecond)
        check(lopsidedLines.upload == "↑812K" && lopsidedLines.download == "↓0B",
              "上传在上用的样例不对：\(lopsidedLines)")
        let lopsidedImage = NetworkSpeedStatusItem.twoLinesImage(icon: icon, rates: lopsided,
                                                                 unit: .bytesPerSecond)
        // ④ 左对齐的强化版：三种不同位数的读数下，两行墨迹左边缘之差必须是同一个常数
        // （`↑` 与 `↓` 的字形包围盒差半格），说明两行共用同一个排版原点、
        // 不会因为数字变宽而各自漂移。
        let alignmentFrames: [NetworkSpeedRates] = [
            lopsided,
            NetworkSpeedRates(downloadBytesPerSecond: 1_468_006, uploadBytesPerSecond: 33_178),
            NetworkSpeedRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0),
        ]
        var leftOffsets: [Int] = []
        for frame in alignmentFrames {
            let frameImage = NetworkSpeedStatusItem.twoLinesImage(icon: icon, rates: frame,
                                                                  unit: .bytesPerSecond)
            guard let frameRep = rasterize(frameImage, scale: 2) else {
                print("FAIL 两行图无法栅格化（左对齐采样）")
                exit(1)
            }
            let frameBands = inkBands(frameRep, columns: (20 * 2)..<frameRep.pixelsWide)
            check(frameBands.count == 2, "左对齐采样帧没有两行墨迹：\(frameBands)")
            if frameBands.count == 2 {
                leftOffsets.append(frameBands[0].minColumn - frameBands[1].minColumn)
            }
        }
        check(leftOffsets.count == alignmentFrames.count, "左对齐采样帧不足：\(leftOffsets)")
        check(Set(leftOffsets).count == 1,
              "两行左边缘之差随读数变化（不是同一个排版原点）：\(leftOffsets)")

        var bandEvidence: [String: Any] = [:]
        if let rep = rasterize(lopsidedImage, scale: 2) {
            let scale = 2
            check(hasInk(rep, columns: 0..<(18 * scale)), "两行图左侧 18pt 图标区域没有墨迹")
            check(!hasInk(rep, columns: (18 * scale)..<(24 * scale)), "两行图图标与文字之间（6pt 间距）有墨迹")
            let bands = inkBands(rep, columns: (20 * scale)..<rep.pixelsWide)
            check(bands.count == 2, "两行文字没有分成两段：\(bands)")
            if bands.count == 2 {
                let top = bands[0], bottom = bands[1]
                // ① 只有两行：行带恰好两条，且两段起点间距 ≈ 一行行高（没有额外行距）。
                let expectedStep = Double(NetworkSpeedStatusItem.TwoLines.lineHeight) * Double(scale)
                let step = Double(bottom.minRow - top.minRow)
                check(abs(step - expectedStep) <= 2,
                      "两行基线间距 \(step)px，应约等于一行行高 \(expectedStep)px")
                // ② 第一行是上传（本样例里上传串比下载串宽 11.7pt），第二行是下载。
                check(top.width > bottom.width + 8,
                      "上下顺序反了：第一行墨迹 \(top.width)px 应明显宽于第二行 \(bottom.width)px")
                // ④ 左对齐：两行从同一个 x 起画。`↑` 与 `↓` 的字形墨迹包围盒本身差
                // 半个点（排版原点相同，墨迹左边界不同），所以按 1pt（=2px @2x）比较。
                check(abs(top.minColumn - bottom.minColumn) <= 2,
                      "两行左边缘不齐：第一行 x=\(top.minColumn)px 第二行 x=\(bottom.minColumn)px")
                check(min(top.minColumn, bottom.minColumn) >= 20 * scale,
                      "两行文字压到图标区：\(top.minColumn)px / \(bottom.minColumn)px")
                check(bottom.maxColumn < rep.pixelsWide, "第二行文字被画到图外：\(bottom) 高 \(rep.pixelsHigh)")
                let inkExtent = CGFloat(bottom.maxRow - top.minRow + 1) / CGFloat(scale)
                check(inkExtent <= 22, "两行文字墨迹高 \(inkExtent)pt 超过菜单栏可用高度")
                bandEvidence = ["topMinColumn": top.minColumn, "bottomMinColumn": bottom.minColumn,
                                "topWidth": top.width, "bottomWidth": bottom.width,
                                "leftOffsets": leftOffsets]
            }
        } else {
            print("FAIL 两行图无法栅格化")
            exit(1)
        }

        // ---- ③ 连续 10 帧不同数值：宽度恒定 --------------------------------
        let frames: [NetworkSpeedRates] = [
            NetworkSpeedRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0),
            NetworkSpeedRates(downloadBytesPerSecond: 999, uploadBytesPerSecond: 1_024),
            NetworkSpeedRates(downloadBytesPerSecond: 34_600, uploadBytesPerSecond: 33_178),
            NetworkSpeedRates(downloadBytesPerSecond: 1_468_006, uploadBytesPerSecond: 4_500_000),
            NetworkSpeedRates(downloadBytesPerSecond: 12_000_000, uploadBytesPerSecond: 900_000),
            NetworkSpeedRates(downloadBytesPerSecond: 99_900_000, uploadBytesPerSecond: 102_400_000),
            NetworkSpeedRates(downloadBytesPerSecond: 870_000_000, uploadBytesPerSecond: 1_046_000_000),
            NetworkSpeedRates(downloadBytesPerSecond: 2_000_000_000, uploadBytesPerSecond: 33_178),
            NetworkSpeedRates(downloadBytesPerSecond: 1_020_000_000, uploadBytesPerSecond: 1_022_000_000),
            NetworkSpeedRates(downloadBytesPerSecond: 5_368_709_120, uploadBytesPerSecond: 12_582_912),
        ]
        var frameLengths = Set<CGFloat>()
        var frameImageWidths = Set<CGFloat>()
        var frameButtonWidths = Set<CGFloat>()
        var frameTexts = Set<String>()
        var frameButtonWidthList: [Double] = []
        for frame in frames {
            frameLengths.insert(NetworkSpeedStatusItem.length(enabled: true))
            let frameLines = NetworkSpeedStatusItem.lines(rates: frame, unit: .bytesPerSecond)
            frameTexts.insert(frameLines.upload + frameLines.download)
            let frameImage = NetworkSpeedStatusItem.twoLinesImage(icon: icon, rates: frame,
                                                                 unit: .bytesPerSecond)
            frameImageWidths.insert(frameImage.size.width)
            let measured = NetworkSpeedStatusItem.measuredWidths(
                enabled: true, rates: frame, unit: .bytesPerSecond, icon: icon)
            frameButtonWidths.insert(measured.button)
            frameButtonWidthList.append(Double((measured.button * 100).rounded() / 100))
            check(measured.image <= NetworkSpeedStatusItem.FixedWidth.imageWidth + 0.01,
                  "图在按钮里被放大：\(measured.image)pt")
        }
        check(frameTexts.count == frames.count, "10 帧文字没有全部不同：\(frameTexts.count)")
        check(frameLengths == [NetworkSpeedStatusItem.FixedWidth.length],
              "10 帧状态项长度不一致：\(frameLengths)")
        check(frameImageWidths == [NetworkSpeedStatusItem.FixedWidth.imageWidth],
              "10 帧两行图宽不一致：\(frameImageWidths)")
        check(frameButtonWidths == [NetworkSpeedStatusItem.FixedWidth.length],
              "10 帧按钮拟合宽不一致：\(frameButtonWidths)")
        check(NetworkSpeedStatusItem.overflowLogs == 0,
              "正常读数触发了超宽日志：\(NetworkSpeedStatusItem.overflowLogs)")

        // ---- ⑥ 关闭开关：宽度回 24pt（squareLength）、图片恢复纯图标 --------
        check(NetworkSpeedStatusItem.length(enabled: false) == NSStatusItem.squareLength,
              "关闭后长度不是 squareLength")
        let disabledWidths = NetworkSpeedStatusItem.measuredWidths(
            enabled: false, rates: nil, unit: .bytesPerSecond, icon: icon)
        check(abs(disabledWidths.button - 24) < 0.01,
              "关闭后宽度没回到 24pt：\(disabledWidths.button)")
        check(disabledWidths.image >= 16, "关闭状态下图标被挤掉了：\(disabledWidths.image)")

        // 同一颗按钮上开/关：不重建状态项，标题永远为空、图片在模板图与原生图标之间切换。
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        button.imageScaling = .scaleProportionallyDown
        NetworkSpeedStatusItem.configure(button, enabled: true, rates: rates,
                                         unit: .bytesPerSecond, icon: icon)
        check(button.attributedTitle.string.isEmpty, "打开后仍有 attributedTitle（单行路径没删掉）")
        check(button.imagePosition == .imageOnly, "打开后图标位置不是 imageOnly：\(button.imagePosition.rawValue)")
        check(button.image !== icon && button.image?.isTemplate == true,
              "打开后没有换成自绘模板图")
        check(abs(button.fittingSize.width - NetworkSpeedStatusItem.FixedWidth.length) < 0.01,
              "打开后按钮拟合宽 \(button.fittingSize.width) 不是固定长度")
        NetworkSpeedStatusItem.configure(button, enabled: false, rates: nil,
                                         unit: .bytesPerSecond, icon: icon)
        check(button.attributedTitle.string.isEmpty, "关闭后仍有标题")
        check(button.image === icon, "关闭后没有恢复纯图标")
        check(abs(button.fittingSize.width - 24) < 0.01,
              "关闭后宽度 \(button.fittingSize.width) 没回到 24pt")

        // ---- 偏好落盘：只有开关与单位两个键 --------------------------------
        check(NetworkSpeedMonitor(defaults: defaults).unit == .bytesPerSecond, "默认单位不是 B/s")
        monitor.setUnit(.bitsPerSecond)
        check(monitor.snapshot.unit == .bitsPerSecond, "切换单位没有立即更新快照")
        check(defaults.string(forKey: NetworkSpeedMonitor.unitKey) == "bits",
              "单位没有写进偏好：\(defaults.string(forKey: NetworkSpeedMonitor.unitKey) ?? "nil")")
        check(NetworkSpeedMonitor(defaults: defaults).unit == .bitsPerSecond,
              "重启后单位没有从偏好恢复")
        monitor.setUnit(.bytesPerSecond)
        // 旧版本落盘的「排版 / 宽度」偏好键已经删掉：残留的脏值不参与读取，
        // 新实例既不会崩溃，也不会改变开关与单位。
        defaults.set("single", forKey: "blinkclip.networkSpeed.layout")
        defaults.set("content", forKey: "blinkclip.networkSpeed.width")
        let staleDefaults = NetworkSpeedMonitor(defaults: defaults)
        check(staleDefaults.unit == .bytesPerSecond, "残留偏好改变了单位：\(staleDefaults.unit)")
        check(staleDefaults.snapshot.isEnabled == defaults.bool(forKey: NetworkSpeedMonitor.enabledKey),
              "残留偏好改变了开关状态")

        // ---- 真状态项：同一颗 NSStatusItem 上开/关 --------------------------
        var realStatusItemChecks = 0
        var realLengths: [Double] = []
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let realButton = item.button {
            NetworkSpeedStatusItem.apply(to: item, enabled: true, rates: rates,
                                         unit: .bytesPerSecond, icon: icon)
            check(abs(item.length - NetworkSpeedStatusItem.FixedWidth.length) < 0.01,
                  "真状态项长度 \(item.length) 不是固定 \(NetworkSpeedStatusItem.FixedWidth.length)")
            for frame in frames.prefix(5) {
                NetworkSpeedStatusItem.apply(to: item, enabled: true, rates: frame,
                                             unit: .bytesPerSecond, icon: icon)
                realLengths.append(Double(item.length))
                check(item.length == NetworkSpeedStatusItem.FixedWidth.length,
                      "真状态项逐帧长度变了：\(item.length)")
                let imageRect = realButton.cell?.imageRect(forBounds: realButton.bounds) ?? .zero
                check(abs(imageRect.width - NetworkSpeedStatusItem.FixedWidth.imageWidth) < 0.5,
                      "两行图在真状态项里被缩放：\(imageRect)")
            }
            NetworkSpeedStatusItem.apply(to: item, enabled: false, rates: nil,
                                         unit: .bytesPerSecond, icon: icon)
            check(abs(item.length - NSStatusItem.squareLength) < 0.01,
                  "关闭后状态项长度 \(item.length) 没回 squareLength")
            check(realButton.attributedTitle.string.isEmpty, "关闭后状态项仍有标题")
            realStatusItemChecks = 1
            NSStatusBar.system.removeStatusItem(item)
        } else {
            print("NOTE 本次运行没有 NSStatusBar（无菜单栏），真状态项断言只用离屏按钮")
        }

        let payload: [String: Any] = [
            "passed": true,
            "checks": checks,
            "enabledLength": Double(NetworkSpeedStatusItem.FixedWidth.length),
            "imageWidth": Double(NetworkSpeedStatusItem.FixedWidth.imageWidth),
            "imageHeight": Double(NetworkSpeedStatusItem.TwoLines.height),
            "textWidth": Double(NetworkSpeedStatusItem.FixedWidth.textWidth),
            "widestLine": widestRow,
            "widestLineWidth": Double((widestMeasured * 100).rounded() / 100),
            "degradeLine": NetworkSpeedStatusItem.FixedWidth.degradedLine,
            "degradeLineWidth": Double((degradeMeasured * 100).rounded() / 100),
            "disabledLength": Double(NSStatusItem.squareLength),
            "disabledButtonWidth": Double((disabledWidths.button * 100).rounded() / 100),
            "frameButtonWidths": frameButtonWidthList,
            "frameImageWidth": Double((image.size.width * 100).rounded() / 100),
            "bands": bandEvidence,
            "lines": ["upload": lines.upload, "download": lines.download],
            "formatSamples": carrySamples.map { ["bytes": $0.0, "full": $0.1, "compact": $0.2] },
            "boundarySamples": boundaries.map { ["bytes": $0.0, "full": $0.1, "compact": $0.2] },
            "tooltip": tooltip,
            "accessibilityDescription": imageDescription,
            "degradeCompact": degradedTitle,
            "degradeFull": NetworkSpeedFormatter.fullString(bytesPerSecond: beyondGigabytes,
                                                            unit: .bytesPerSecond),
            "overflowLogs": NetworkSpeedStatusItem.overflowLogs,
            "realStatusItem": realStatusItemChecks,
            "realLengths": realLengths,
            "sampleCount": monitor.snapshot.sampleCount,
            "baselineResetCount": monitor.snapshot.baselineResetCount,
            "boundary": "生产 NetworkSpeedMonitor / NetworkSpeedInterfaceReader / NetworkSpeedStatusItem / NetworkSpeedFormatter + 注入假计数器；真实 NSStatusBarButton 尺寸；不访问用户历史与剪贴板。",
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
