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
            enabled: true, rates: rates, unit: .bytesPerSecond, layout: .singleLine, icon: icon)
        let disabledWidths = NetworkSpeedStatusItem.measuredWidths(
            enabled: false, rates: nil, unit: .bytesPerSecond, layout: .twoLines, icon: icon)
        check(singleWidths.button > disabledWidths.button + 40,
              "开启网速后状态栏没有变宽：\(disabledWidths.button) → \(singleWidths.button)")
        check(singleWidths.image >= 16, "图标被挤掉了：\(singleWidths.image)")
        check(disabledWidths.image >= 16, "关闭状态下图标被挤掉了：\(disabledWidths.image)")
        // 关闭态 = 纯图标 24pt（`NSStatusItem.squareLength` 是 -2 这个哨兵值，
        // 真实布局宽度是 18pt 图标 + 左右各 3pt；生产代码仍写 `squareLength`）。
        check(abs(disabledWidths.button - 24) < 0.01,
              "关闭态宽度没回到 24pt：\(disabledWidths.button)")
        let title = NetworkSpeedStatusItem.attributedTitle(rates: rates, unit: .bytesPerSecond).string
        check(title == "↓1.4M ↑32.4K", "菜单栏紧凑文字不对：\(title)")
        let bitRates = NetworkSpeedRates(downloadBytesPerSecond: 1_400_000,
                                         uploadBytesPerSecond: 32_400)
        let bitsTitle = NetworkSpeedStatusItem.attributedTitle(rates: bitRates, unit: .bitsPerSecond).string
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
            enabled: true, rates: rates, unit: .bytesPerSecond, layout: .twoLines, icon: icon)
        let twoLineImage = NetworkSpeedStatusItem.twoLinesImage(icon: icon, rates: rates,
                                                               unit: .bytesPerSecond)
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
                                         layout: .singleLine, icon: icon)
        let beforeSwitch = button.fittingSize.width
        check(button.image === icon, "单行模式应继续用原生模板图标")
        check(button.imagePosition == .imageLeading, "单行模式图标位置不对：\(button.imagePosition.rawValue)")
        NetworkSpeedStatusItem.configure(button, enabled: true, rates: rates, unit: .bytesPerSecond,
                                         layout: .twoLines, icon: icon)
        let afterSwitch = button.fittingSize.width
        check(afterSwitch < beforeSwitch,
              "切到两行后宽度没有立刻变小：\(beforeSwitch) → \(afterSwitch)")
        check(button.attributedTitle.string.isEmpty, "两行模式仍在显示 attributedTitle")
        check(button.image !== icon && button.image?.isTemplate == true,
              "两行模式没有换成自绘模板图")
        NetworkSpeedStatusItem.configure(button, enabled: true, rates: rates, unit: .bytesPerSecond,
                                         layout: .singleLine, icon: icon)
        check(abs(button.fittingSize.width - beforeSwitch) < 0.01,
              "切回单行宽度没有恢复：\(button.fittingSize.width) vs \(beforeSwitch)")
        check(button.image === icon && button.attributedTitle.string == title,
              "切回单行没有恢复原生图标 + attributedTitle")

        // ---- ④ 关闭开关：宽度回 24pt、标题清空、图片是纯图标 ------------------
        NetworkSpeedStatusItem.configure(button, enabled: false, rates: nil, unit: .bytesPerSecond,
                                         layout: .twoLines, icon: icon)
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
                                         unit: .bytesPerSecond, layout: .singleLine, icon: icon)
            let singleLength = realButton.fittingSize.width
            check(item.length == NSStatusItem.variableLength, "开网速后状态项不是 variableLength")
            NetworkSpeedStatusItem.apply(to: item, enabled: true, rates: rates,
                                         unit: .bytesPerSecond, layout: .twoLines, icon: icon)
            let twoLineLength = realButton.fittingSize.width
            check(twoLineLength < singleLength,
                  "真状态项切到两行没有变窄：\(singleLength) → \(twoLineLength)")
            NetworkSpeedStatusItem.apply(to: item, enabled: false, rates: nil,
                                         unit: .bytesPerSecond, layout: .twoLines, icon: icon)
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
            "menuBarWidth": Double((singleWidths.button * 100).rounded() / 100),
            "menuBarDisabledWidth": Double((disabledWidths.button * 100).rounded() / 100),
            "twoLineWidth": Double((twoLineWidths.button * 100).rounded() / 100),
            "twoLineImageWidth": Double((twoLineImage.size.width * 100).rounded() / 100),
            "twoLineImageHeight": Double((twoLineImage.size.height * 100).rounded() / 100),
            "imageWidth": Double((singleWidths.image * 100).rounded() / 100),
            "iconWidth": Double((singleWidths.image * 100).rounded() / 100),
            "realStatusItem": realStatusItemChecks,
            "layouts": NetworkSpeedLayout.allCases.map(\.rawValue),
            "sampleCount": monitor.snapshot.sampleCount,
            "baselineResetCount": monitor.snapshot.baselineResetCount,
            "boundary": "生产 NetworkSpeedMonitor / NetworkSpeedInterfaceReader / NetworkSpeedStatusItem + 注入假计数器；真实 NSStatusBarButton 尺寸；不访问用户历史与剪贴板。",
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
