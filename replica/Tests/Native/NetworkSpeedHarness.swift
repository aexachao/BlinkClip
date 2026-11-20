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

        // ---- 菜单栏渲染：宽度增长、图标不被挤掉、tooltip 完整 --------------
        let rates = NetworkSpeedRates(downloadBytesPerSecond: 1_468_006,
                                      uploadBytesPerSecond: 33_178)
        let icon = ReplicaBrand.menuBarImage()
        let singleWidths = NetworkSpeedStatusItem.measuredWidths(
            enabled: true, rates: rates, unit: .bytesPerSecond, layout: .singleLine,
            width: .content, icon: icon)
        let disabledWidths = NetworkSpeedStatusItem.measuredWidths(
            enabled: false, rates: nil, unit: .bytesPerSecond, layout: .twoLines,
            width: .fixed, icon: icon)
        check(singleWidths.button > disabledWidths.button + 40,
              "开启网速后状态栏没有变宽：\(disabledWidths.button) → \(singleWidths.button)")
        check(singleWidths.image >= 16, "图标被挤掉了：\(singleWidths.image)")
        check(disabledWidths.image >= 16, "关闭状态下图标被挤掉了：\(disabledWidths.image)")
        // 关闭态 = 纯图标 24pt（`NSStatusItem.squareLength` 是 -2 这个哨兵值，
        // 真实布局宽度是 18pt 图标 + 左右各 3pt；生产代码仍写 `squareLength`）。
        check(abs(disabledWidths.button - 24) < 0.01,
              "关闭态宽度没回到 24pt：\(disabledWidths.button)")
        let title = NetworkSpeedStatusItem.attributedTitle(rates: rates, unit: .bytesPerSecond,
                                                           width: .content).string
        check(title == "↓1.4M ↑32.4K", "菜单栏紧凑文字不对：\(title)")
        let bitRates = NetworkSpeedRates(downloadBytesPerSecond: 1_400_000,
                                         uploadBytesPerSecond: 32_400)
        let bitsTitle = NetworkSpeedStatusItem.attributedTitle(rates: bitRates, unit: .bitsPerSecond,
                                                               width: .content).string
        check(bitsTitle == "↓11.2M ↑259K", "bps 菜单栏文字不对：\(bitsTitle)")
        let tooltip = NetworkSpeedStatusItem.toolTip(rates: rates, unit: .bytesPerSecond)
        check(tooltip.contains("1.4 MB/s") && tooltip.contains("32.4 KB/s") && tooltip.contains("·"),
              "tooltip 不完整：\(tooltip)")

        // ---- ① 两种排版的文字内容 -------------------------------------------
        let lines = NetworkSpeedStatusItem.menuBarLines(rates: rates, unit: .bytesPerSecond)
        check(lines.download == "↓1.4M", "两行排版第一行不对：\(lines.download)")
        check(lines.upload == "↑32.4K", "两行排版第二行不对：\(lines.upload)")
        check(lines.download + " " + lines.upload == title,
              "两行文字拼起来应与单行一致：\(lines.download) / \(lines.upload) vs \(title)")
        let bitLines = NetworkSpeedStatusItem.menuBarLines(rates: bitRates, unit: .bitsPerSecond)
        check(bitLines.download == "↓11.2M" && bitLines.upload == "↑259K",
              "bps 两行文字不对：\(bitLines)")
        let emptyLines = NetworkSpeedStatusItem.menuBarLines(rates: nil, unit: .bytesPerSecond)
        check(emptyLines.download == "↓—" && emptyLines.upload == "↑—",
              "首拍两行占位不对：\(emptyLines)")

        // ---- ② 两行排版更窄，且高度压在菜单栏可用高度内 ----------------------
        let twoLineWidths = NetworkSpeedStatusItem.measuredWidths(
            enabled: true, rates: rates, unit: .bytesPerSecond, layout: .twoLines,
            width: .content, icon: icon)
        let twoLineImage = NetworkSpeedStatusItem.twoLinesImage(icon: icon, rates: rates,
                                                               unit: .bytesPerSecond, width: .content)
        check(twoLineWidths.button < singleWidths.button,
              "两行排版没有比单行窄：\(twoLineWidths.button) vs \(singleWidths.button)")
        check(NetworkSpeedStatusItem.TwoLines.expectedWidth.contains(twoLineWidths.button),
              "两行排版宽度 \(twoLineWidths.button) 不在 \(NetworkSpeedStatusItem.TwoLines.expectedWidth) 内")
        check(twoLineImage.size.height <= NetworkSpeedStatusItem.TwoLines.maxHeight,
              "两行图高 \(twoLineImage.size.height) 超过菜单栏可用高度 22pt")
        check(abs(twoLineImage.size.height - 22) < 0.01,
              "两行图高应正好两行行高（22pt），实际 \(twoLineImage.size.height)")
        check(twoLineImage.size.width > 18 + 2,
              "两行图宽没有把 18pt 图标算进去：\(twoLineImage.size.width)")
        // 模板图：深浅色与高亮由 AppKit 反色，两行文字不需要自己解析 appearance。
        check(twoLineImage.isTemplate, "两行图不是模板图（深色/高亮会看不清）")
        check(twoLineImage.accessibilityDescription == title,
              "两行图的无障碍描述应与单行文字一致：\(twoLineImage.accessibilityDescription ?? "nil")")

        // 像素证据：左侧 18pt 是图标，右侧两行文字各占一段墨迹，且第一行比第二行窄
        // （↓1.4M 比 ↑32.4K 窄），中间没有多余空白行。
        if let rep = rasterize(twoLineImage, scale: 2) {
            let scale = 2
            check(hasInk(rep, columns: 0..<(18 * scale)), "两行图左侧 18pt 图标区域没有墨迹")
            check(!hasInk(rep, columns: (18 * scale)..<(20 * scale)), "两行图图标与文字之间（2pt 间距）有墨迹")
            let textBands = inkBands(rep, columns: (20 * scale)..<rep.pixelsWide)
            check(textBands.count == 2, "两行文字没有分成两段：\(textBands)")
            if textBands.count == 2 {
                let top = textBands[0], bottom = textBands[1]
                // 两段墨迹的起点间距必须正好一行行高：多出来的空白就是多余行距。
                let expectedStep = Double(NetworkSpeedStatusItem.TwoLines.lineHeight) * Double(scale)
                let step = Double(bottom.minRow - top.minRow)
                check(abs(step - expectedStep) <= 2,
                      "两行基线间距 \(step)px，应约等于一行行高 \(expectedStep)px（有多余行距或行重叠）")
                check(top.width < bottom.width,
                      "上下两行顺序反了：第一行(↓)宽 \(top.width)px 应窄于第二行(↑) \(bottom.width)px")
                check(bottom.maxRow < rep.pixelsHigh, "第二行文字被画到图外：\(bottom) 高 \(rep.pixelsHigh)")
                let inkExtent = CGFloat(bottom.maxRow - top.minRow + 1) / CGFloat(scale)
                check(inkExtent <= 22, "两行文字墨迹高 \(inkExtent)pt 超过菜单栏可用高度")
            }
        } else {
            print("FAIL 两行图无法栅格化")
            exit(1)
        }

        // ---- ③ 切换排版即时生效（同一颗按钮，不重建） ------------------------
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 100, height: 22))
        button.imageScaling = .scaleProportionallyDown
        NetworkSpeedStatusItem.configure(button, enabled: true, rates: rates, unit: .bytesPerSecond,
                                         layout: .singleLine, width: .content, icon: icon)
        let beforeSwitch = button.fittingSize.width
        check(button.image === icon, "单行模式应继续用原生模板图标")
        check(button.imagePosition == .imageLeading, "单行模式图标位置不对：\(button.imagePosition.rawValue)")
        NetworkSpeedStatusItem.configure(button, enabled: true, rates: rates, unit: .bytesPerSecond,
                                         layout: .twoLines, width: .content, icon: icon)
        let afterSwitch = button.fittingSize.width
        check(afterSwitch < beforeSwitch,
              "切到两行后宽度没有立刻变小：\(beforeSwitch) → \(afterSwitch)")
        check(button.attributedTitle.string.isEmpty, "两行模式仍在显示 attributedTitle")
        check(button.image !== icon && button.image?.isTemplate == true,
              "两行模式没有换成自绘模板图")
        NetworkSpeedStatusItem.configure(button, enabled: true, rates: rates, unit: .bytesPerSecond,
                                         layout: .singleLine, width: .content, icon: icon)
        check(abs(button.fittingSize.width - beforeSwitch) < 0.01,
              "切回单行宽度没有恢复：\(button.fittingSize.width) vs \(beforeSwitch)")
        check(button.image === icon && button.attributedTitle.string == title,
              "切回单行没有恢复原生图标 + attributedTitle")

        // ---- ④ 关闭开关：宽度回 24pt、标题清空、图片是纯图标 ------------------
        NetworkSpeedStatusItem.configure(button, enabled: false, rates: nil, unit: .bytesPerSecond,
                                         layout: .twoLines, width: .fixed, icon: icon)
        check(button.attributedTitle.string.isEmpty, "关闭后仍有标题")
        check(button.imagePosition == .imageOnly, "关闭后图标位置不对")
        check(button.image === icon, "关闭后没有恢复纯图标")
        check(abs(button.fittingSize.width - 24) < 0.01,
              "关闭后宽度 \(button.fittingSize.width) 没回到 24pt")

        // ---- 偏好落盘：默认单行，切换即写盘并更新快照 ------------------------
        check(NetworkSpeedMonitor(defaults: defaults).layout == .singleLine, "默认排版不是单行")
        monitor.setLayout(.twoLines)
        check(monitor.snapshot.layout == .twoLines, "切换排版没有立即更新快照")
        check(defaults.string(forKey: NetworkSpeedMonitor.layoutKey) == "twoLines",
              "排版没有写进偏好：\(defaults.string(forKey: NetworkSpeedMonitor.layoutKey) ?? "nil")")
        let restored = NetworkSpeedMonitor(defaults: defaults)
        check(restored.layout == .twoLines, "重启后排版没有从偏好恢复：\(restored.layout)")

        // ---- 真状态项：同一颗 NSStatusItem 上切换排版与开关 ------------------
        var realStatusItemChecks = 0
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let realButton = item.button {
            NetworkSpeedStatusItem.apply(to: item, enabled: true, rates: rates,
                                         unit: .bytesPerSecond, layout: .singleLine,
                                         width: .content, icon: icon)
            let singleLength = realButton.fittingSize.width
            check(item.length == NSStatusItem.variableLength, "开网速后状态项不是 variableLength")
            NetworkSpeedStatusItem.apply(to: item, enabled: true, rates: rates,
                                         unit: .bytesPerSecond, layout: .twoLines,
                                         width: .content, icon: icon)
            let twoLineLength = realButton.fittingSize.width
            check(twoLineLength < singleLength,
                  "真状态项切到两行没有变窄：\(singleLength) → \(twoLineLength)")
            NetworkSpeedStatusItem.apply(to: item, enabled: false, rates: nil,
                                         unit: .bytesPerSecond, layout: .twoLines,
                                         width: .fixed, icon: icon)
            check(abs(item.length - NSStatusItem.squareLength) < 0.01,
                  "关闭后状态项长度 \(item.length) 没回 squareLength")
            check(realButton.attributedTitle.string.isEmpty, "关闭后状态项仍有标题")
            realStatusItemChecks = 1
            NSStatusBar.system.removeStatusItem(item)
        } else {
            print("NOTE 本次运行没有 NSStatusBar（无菜单栏），真状态项断言只用离屏按钮")
        }

        // ---- ⑤ 宽度策略：固定（默认）/ 随内容 × 单行 / 两行 ----------------
        check(NetworkSpeedWidth.allCases.map(\.rawValue) == ["fixed", "content"],
              "宽度策略的落盘契约变了：\(NetworkSpeedWidth.allCases.map(\.rawValue))")
        check(NetworkSpeedMonitor(defaults: defaults).width == .fixed, "默认宽度策略不是固定")
        check(NetworkSpeedStatusItem.FixedWidth.segmentSlots == 6,
              "一段的字符位不是 6：\(NetworkSpeedStatusItem.FixedWidth.segmentSlots)")
        check(NetworkSpeedStatusItem.FixedWidth.singleLineSlots == 13,
              "单行字符位不是 13：\(NetworkSpeedStatusItem.FixedWidth.singleLineSlots)")
        let figureSpace = NetworkSpeedStatusItem.FixedWidth.pad

        // 10 帧覆盖：空闲（B/s）、K、M、G、T、两位小数、三位整数、最宽后缀。
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
        // 最宽的一帧：两段都是三位整数 + 宽后缀 `M`（`↓ 870M ↑ 999M` 量级）。
        let worstRates = frames[6]

        // ① 固定宽度：10 帧不同读数，状态项长度恒定（0 变化），文字区放得下每一个标题。
        var fixedLengths = Set<CGFloat>()
        var fixedTitleSlots = Set<Int>()
        var fixedTitleWidths: [CGFloat] = []
        for frame in frames {
            fixedLengths.insert(NetworkSpeedStatusItem.length(enabled: true, layout: .singleLine,
                                                              width: .fixed))
            let fixedTitle = NetworkSpeedStatusItem.fixedTitle(rates: frame, unit: .bytesPerSecond)
            fixedTitleSlots.insert(fixedTitle.count)
            fixedTitleWidths.append(textWidth(fixedTitle, font: NetworkSpeedStatusItem.titleFont))
            let fitted = NetworkSpeedStatusItem.measuredWidths(
                enabled: true, rates: frame, unit: .bytesPerSecond, layout: .singleLine,
                width: .fixed, icon: icon)
            check(fitted.button <= NetworkSpeedStatusItem.FixedWidth.singleLineLength,
                  "固定宽度单行拟合宽 \(fitted.button) 超过状态项长度")
        }
        check(fixedLengths == [NetworkSpeedStatusItem.FixedWidth.singleLineLength],
              "固定宽度模式下 10 帧长度不一致：\(fixedLengths)")
        check(fixedTitleSlots == [NetworkSpeedStatusItem.FixedWidth.singleLineSlots],
              "补位后的单行字符位数不恒定：\(fixedTitleSlots)")
        let widestFixedTitle = fixedTitleWidths.max() ?? 0
        // 真实菜单栏里文字区左右各 9pt、图标 18pt、图标与文字间距 2pt = 38pt 固定开销。
        check(widestFixedTitle + 38 <= NetworkSpeedStatusItem.FixedWidth.singleLineLength,
              "最宽固定标题 \(widestFixedTitle)pt + 38pt 开销超过 \(NetworkSpeedStatusItem.FixedWidth.singleLineLength)pt")

        // ② 随内容：同一组 10 帧里拟合宽度确实在变（对照固定模式）。
        var contentWidths = Set<CGFloat>()
        for frame in frames {
            contentWidths.insert(NetworkSpeedStatusItem.measuredWidths(
                enabled: true, rates: frame, unit: .bytesPerSecond, layout: .singleLine,
                width: .content, icon: icon).button)
        }
        check(contentWidths.count > 1,
              "随内容模式下 10 帧宽度没有变化：\(contentWidths.sorted())")

        // ③ 超预算降级：数字位超过 4 位时换成 `>999` + 后缀，一段仍然 6 位。
        let overflowRates = NetworkSpeedRates(downloadBytesPerSecond: Double(20_480) * pow(1024, 4),
                                              uploadBytesPerSecond: Double(12_300) * pow(1024, 4))
        let overflowTitle = NetworkSpeedStatusItem.fixedTitle(rates: overflowRates,
                                                             unit: .bytesPerSecond)
        check(overflowTitle.contains(">999T"),
              "超预算没有降级：\(overflowTitle.debugDescription)")
        check(overflowTitle.count == NetworkSpeedStatusItem.FixedWidth.singleLineSlots,
              "降级后字符位数变了：\(overflowTitle.debugDescription)")
        let overflowSegment = NetworkSpeedStatusItem.segment(from: "↓20480T")
        check(NetworkSpeedStatusItem.fixedSegmentText(overflowSegment) == "↓>999T",
              "降级文本不对：\(NetworkSpeedStatusItem.fixedSegmentText(overflowSegment).debugDescription)")
        let overflowFitted = NetworkSpeedStatusItem.measuredWidths(
            enabled: true, rates: overflowRates, unit: .bytesPerSecond, layout: .singleLine,
            width: .fixed, icon: icon)
        check(overflowFitted.button <= NetworkSpeedStatusItem.FixedWidth.singleLineLength,
              "降级后宽度 \(overflowFitted.button) 仍然撑破固定宽度")
        // 不足 1 个单位时后缀压成一位：`B/s` → `B`、`bps` → `b`，仍占 6 位。
        let idleTitle = NetworkSpeedStatusItem.fixedTitle(
            rates: NetworkSpeedRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0),
            unit: .bytesPerSecond)
        check(idleTitle == "↓\(figureSpace)\(figureSpace)\(figureSpace)0B ↑\(figureSpace)\(figureSpace)\(figureSpace)0B",
              "固定宽度空闲文字不对：\(idleTitle.debugDescription)")
        let idleBitsTitle = NetworkSpeedStatusItem.fixedTitle(
            rates: NetworkSpeedRates(downloadBytesPerSecond: 0, uploadBytesPerSecond: 0),
            unit: .bitsPerSecond)
        check(idleBitsTitle == "↓\(figureSpace)\(figureSpace)\(figureSpace)0b ↑\(figureSpace)\(figureSpace)\(figureSpace)0b",
              "固定宽度 bps 空闲文字不对：\(idleBitsTitle.debugDescription)")
        // 数字格像素恒定：`1.2` / `32.4` / `99.9`（带小数点）与 `812` / `999` 画的
        // 都是 4 个数字宽——小数点比数字窄，靠 `.kern` 补回差额。
        let cellWidths = ["1.2", "32.4", "99.9", "812", "999", ">999"]
            .map { number -> CGFloat in
                let segment = NetworkSpeedStatusItem.fixedSegmentText(
                    .init(arrow: "↓", number: number, suffix: "K"))
                return NetworkSpeedStatusItem.fixedAttributedText(
                    segment, font: NetworkSpeedStatusItem.titleFont, color: .black).size().width
            }
        let cellSpread = (cellWidths.max() ?? 0) - (cellWidths.min() ?? 0)
        check(cellSpread < 0.01,
              "数字格宽度不稳定（最大差 \(cellSpread)pt）：\(cellWidths)")
        // 数字右对齐：`0` 与 `812` 落在同一列的右边（补位字符数 = 4 − 数字长度）。
        let shortSegment = NetworkSpeedStatusItem.fixedSegmentText(
            NetworkSpeedStatusItem.segment(from: "↓0B/s"))
        let longSegment = NetworkSpeedStatusItem.fixedSegmentText(
            NetworkSpeedStatusItem.segment(from: "↓812K"))
        check(shortSegment.count == longSegment.count,
              "不同位数的数字补位后长度不同：\(shortSegment.debugDescription) / \(longSegment.debugDescription)")
        check(shortSegment.hasSuffix("0B") && longSegment.hasSuffix("812K"),
              "补位没有把数字顶到右边：\(shortSegment.debugDescription) / \(longSegment.debugDescription)")

        // ④ 四种组合：单行/两行 × 固定/随内容，长度与图宽各按自己的策略落定。
        var combinationLengths: [String: Double] = [:]
        for layout in NetworkSpeedLayout.pickerOrder {
            for width in NetworkSpeedWidth.pickerOrder {
                let length = NetworkSpeedStatusItem.length(enabled: true, layout: layout, width: width)
                combinationLengths["\(layout.rawValue)-\(width.rawValue)"] = Double(length)
                if width.isFixed {
                    let expected = layout == .singleLine
                        ? NetworkSpeedStatusItem.FixedWidth.singleLineLength
                        : NetworkSpeedStatusItem.FixedWidth.twoLinesLength
                    check(length == expected,
                          "固定宽度 \(layout.rawValue) 的长度 \(length) 不是 \(expected)")
                } else {
                    check(length == NSStatusItem.variableLength,
                          "随内容 \(layout.rawValue) 的长度 \(length) 不是 variableLength")
                }
            }
        }
        check(combinationLengths.count == 4, "四种组合没有各自独立：\(combinationLengths)")
        let fixedTwoImage = NetworkSpeedStatusItem.twoLinesImage(
            icon: icon, rates: worstRates, unit: .bytesPerSecond, width: .fixed)
        check(abs(fixedTwoImage.size.width - NetworkSpeedStatusItem.FixedWidth.twoLinesImageWidth) < 0.01,
              "固定宽度两行图宽不是 \(NetworkSpeedStatusItem.FixedWidth.twoLinesImageWidth)：\(fixedTwoImage.size.width)")
        check(abs(fixedTwoImage.size.height - NetworkSpeedStatusItem.TwoLines.height) < 0.01,
              "固定宽度两行图高不是 \(NetworkSpeedStatusItem.TwoLines.height)：\(fixedTwoImage.size.height)")
        let fixedTwoLines = NetworkSpeedStatusItem.fixedLines(rates: worstRates, unit: .bytesPerSecond)
        check(fixedTwoLines.download.count == 6 && fixedTwoLines.upload.count == 6,
              "两行文字段不是 6 位：\(fixedTwoLines)")
        check(fixedTwoLines.download.hasPrefix("↓") && fixedTwoLines.upload.hasPrefix("↑"),
              "两行箭头顺序不对：\(fixedTwoLines)")
        let contentTwoImage = NetworkSpeedStatusItem.twoLinesImage(
            icon: icon, rates: rates, unit: .bytesPerSecond, width: .content)
        check(contentTwoImage.size.width < fixedTwoImage.size.width,
              "随内容两行图没有比固定宽度窄：\(contentTwoImage.size.width) vs \(fixedTwoImage.size.width)")
        // 两行固定时文字格放得下最宽的一行。
        let widestTwoLine = max(textWidth(fixedTwoLines.download, font: NetworkSpeedStatusItem.TwoLines.font),
                                textWidth(fixedTwoLines.upload, font: NetworkSpeedStatusItem.TwoLines.font))
        check(widestTwoLine <= NetworkSpeedStatusItem.FixedWidth.twoLinesTextWidth,
              "两行最宽文字 \(widestTwoLine)pt 超过固定文字格 \(NetworkSpeedStatusItem.FixedWidth.twoLinesTextWidth)pt")

        // ⑤ 关闭：固定/随内容都回到 24pt（`squareLength`），不留白。
        for layout in NetworkSpeedLayout.pickerOrder {
            for width in NetworkSpeedWidth.pickerOrder {
                check(NetworkSpeedStatusItem.length(enabled: false, layout: layout, width: width)
                      == NSStatusItem.squareLength,
                      "关闭后 \(layout.rawValue)/\(width.rawValue) 没有回 squareLength")
            }
        }
        let disabledFixed = NetworkSpeedStatusItem.measuredWidths(
            enabled: false, rates: nil, unit: .bytesPerSecond, layout: .singleLine,
            width: .fixed, icon: icon)
        check(abs(disabledFixed.button - 24) < 0.01,
              "固定宽度关闭后宽度 \(disabledFixed.button) 没回到 24pt")

        // 偏好：默认固定，切换即写盘并可从偏好恢复。
        monitor.setWidth(.content)
        check(monitor.snapshot.width == .content, "切换宽度策略没有立即更新快照")
        check(defaults.string(forKey: NetworkSpeedMonitor.widthKey) == "content",
              "宽度策略没有写进偏好：\(defaults.string(forKey: NetworkSpeedMonitor.widthKey) ?? "nil")")
        check(NetworkSpeedMonitor(defaults: defaults).width == .content,
              "重启后宽度策略没有从偏好恢复")
        monitor.setWidth(.fixed)

        // 真状态项：固定宽度下逐帧长度不变、文字区放得下最宽标题、两行图不被缩放。
        var fixedRealChecks = 0
        let fixedItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let fixedButton = fixedItem.button {
            NetworkSpeedStatusItem.apply(to: fixedItem, enabled: true, rates: worstRates,
                                         unit: .bytesPerSecond, layout: .singleLine,
                                         width: .fixed, icon: icon)
            check(fixedItem.length == NetworkSpeedStatusItem.FixedWidth.singleLineLength,
                  "真状态项固定单行长度 \(fixedItem.length) 不对")
            let worstTitleWidth = textWidth(NetworkSpeedStatusItem.fixedTitle(rates: worstRates,
                                                                             unit: .bytesPerSecond),
                                            font: NetworkSpeedStatusItem.titleFont)
            let titleArea = fixedButton.cell?.titleRect(forBounds: fixedButton.bounds).width ?? 0
            check(titleArea >= worstTitleWidth,
                  "固定单行文字区 \(titleArea)pt 放不下最宽标题 \(worstTitleWidth)pt（会被截断）")
            for frame in frames {
                NetworkSpeedStatusItem.apply(to: fixedItem, enabled: true, rates: frame,
                                             unit: .bytesPerSecond, layout: .singleLine,
                                             width: .fixed, icon: icon)
                check(fixedItem.length == NetworkSpeedStatusItem.FixedWidth.singleLineLength,
                      "真状态项固定单行长度变了：\(fixedItem.length)")
                let area = fixedButton.cell?.titleRect(forBounds: fixedButton.bounds).width ?? 0
                let needed = textWidth(NetworkSpeedStatusItem.fixedTitle(rates: frame,
                                                                        unit: .bytesPerSecond),
                                       font: NetworkSpeedStatusItem.titleFont)
                check(area >= needed,
                      "固定单行文字区 \(area)pt 放不下 \(needed)pt 的标题")
            }
            NetworkSpeedStatusItem.apply(to: fixedItem, enabled: true, rates: worstRates,
                                         unit: .bytesPerSecond, layout: .twoLines,
                                         width: .fixed, icon: icon)
            check(fixedItem.length == NetworkSpeedStatusItem.FixedWidth.twoLinesLength,
                  "真状态项固定两行长度 \(fixedItem.length) 不对")
            let imageRect = fixedButton.cell?.imageRect(forBounds: fixedButton.bounds) ?? .zero
            check(abs(imageRect.width - NetworkSpeedStatusItem.FixedWidth.twoLinesImageWidth) < 0.5,
                  "两行图在真状态项里被缩放：\(imageRect)")
            fixedRealChecks = 1
            NSStatusBar.system.removeStatusItem(fixedItem)
        } else {
            print("NOTE 本次运行没有 NSStatusBar（无菜单栏），固定宽度的真状态项断言只用离屏按钮")
        }

        let payload: [String: Any] = [
            "passed": true,
            "checks": checks,
            "menuBarWidth": Double((singleWidths.button * 100).rounded() / 100),
            "menuBarDisabledWidth": Double((disabledWidths.button * 100).rounded() / 100),
            "twoLineWidth": Double((twoLineWidths.button * 100).rounded() / 100),
            "twoLineImageWidth": Double((twoLineImage.size.width * 100).rounded() / 100),
            "twoLineImageHeight": Double((twoLineImage.size.height * 100).rounded() / 100),
            "imageWidth": Double((singleWidths.image * 100).rounded() / 100),
            "iconWidth": Double((singleWidths.image * 100).rounded() / 100),
            "realStatusItem": realStatusItemChecks,
            "layouts": NetworkSpeedLayout.allCases.map(\.rawValue),
            "widths": NetworkSpeedWidth.allCases.map(\.rawValue),
            "fixedSingleLength": Double(NetworkSpeedStatusItem.FixedWidth.singleLineLength),
            "fixedTwoLinesLength": Double(NetworkSpeedStatusItem.FixedWidth.twoLinesLength),
            "fixedTwoLinesImageWidth": Double(NetworkSpeedStatusItem.FixedWidth.twoLinesImageWidth),
            "fixedTitleSlots": NetworkSpeedStatusItem.FixedWidth.singleLineSlots,
            "fixedWidestTitleWidth": Double((widestFixedTitle * 100).rounded() / 100),
            "fixedTitleSample": NetworkSpeedStatusItem.fixedTitle(rates: worstRates,
                                                                 unit: .bytesPerSecond),
            "fixedIdleTitle": idleTitle,
            "degradeText": NetworkSpeedStatusItem.fixedSegmentText(
                NetworkSpeedStatusItem.segment(from: "↓20480T")),
            "fixedWidthStable": fixedLengths.count == 1,
            "fixedNumberCellWidth": Double(((cellWidths.first ?? 0) * 100).rounded() / 100),
            "fixedNumberCellSpread": Double((cellSpread * 1000).rounded() / 1000),
            "contentWidthCount": contentWidths.count,
            "combinationLengths": combinationLengths,
            "fixedRealStatusItem": fixedRealChecks,
            "sampleCount": monitor.snapshot.sampleCount,
            "baselineResetCount": monitor.snapshot.baselineResetCount,
            "boundary": "生产 NetworkSpeedMonitor / NetworkSpeedInterfaceReader / NetworkSpeedStatusItem + 注入假计数器；真实 NSStatusBarButton 尺寸；不访问用户历史与剪贴板。",
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
