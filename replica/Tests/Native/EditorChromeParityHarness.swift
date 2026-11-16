import AppKit
import Foundation
@testable import BlinkClipCapture

/// EC：编辑器 live 选框的 chrome 必须与框选覆盖层是同一套。
///
/// 「同一套」不靠人工看图判定：把两侧的真实视图离屏渲染成位图后逐像素比对。
///
/// 1. `SelectionView`（框选覆盖层）自己画一遍 → 位图 A；
/// 2. `SelectionChromeOverlay`（编辑器 live 选框）画一遍 → 位图 B；
/// 3. A、B 的强调色实心像素集合必须完全相同 —— 位置、线宽、横条、L 角标、
///    尺寸标签都一样，说明编辑器没有第二套绘制；
/// 4. 几何按规范逐项量：边框 1pt 实线（每条边虚线段数 = 0）、边中点横条
///    20×4pt、四角 L 角标 12×2pt、角内 2.5pt 对角处无像素（圆点会填满那里）；
/// 5. 命中区 22×22pt：角内 9/10pt 按下命中、12/13pt 按下不命中，且拖动链路
///    真的改了 host 的选区矩形。
@main struct EditorChromeParityHarness {
    struct Failure: Error { let message: String }

    @MainActor static var observations: [[String: Any]] = []

    @MainActor static func main() {
        do {
            print(try run())
        } catch {
            let payload: [String: Any] = [
                "passed": false, "error": "\(error)", "observations": observations,
            ]
            let data = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
                ?? Data("{\"passed\":false}".utf8)
            print(String(decoding: data, as: UTF8.self))
            exit(1)
        }
    }

    /// 归一化位图：RGBA8、非预乘、内存第 0 行是图像顶行（与屏幕截图一致）。
    struct Bitmap {
        let width: Int
        let height: Int
        let scale: CGFloat
        let bytes: [UInt8]

        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            guard x >= 0, x < width, y >= 0, y < height else { return (-1, -1, -1) }
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }

        /// 视图坐标（未翻转，原点左下）→ 位图索引。
        func index(_ point: NSPoint) -> (Int, Int) {
            let x = Int((point.x * scale).rounded())
            let y = height - 1 - Int((point.y * scale).rounded())
            return (x, y)
        }

        func isAccent(_ point: NSPoint) -> Bool {
            let (x, y) = index(point)
            return isAccent(x, y)
        }

        /// 强调色 #007AFF 的「实心」像素：抗锯齿边缘、压暗背景都不算。
        /// 只比实心像素，两侧画布底色不同（一侧压暗、一侧全透明）也不影响判定。
        func isAccent(_ x: Int, _ y: Int) -> Bool {
            let (r, g, b) = rgb(x, y)
            return b >= 240 && b - r >= 200 && g >= 90 && g <= 160
        }

        func accentPoints() -> Set<Int> {
            var set = Set<Int>()
            for y in 0..<height {
                for x in 0..<width where isAccent(x, y) {
                    set.insert(y * width + x)
                }
            }
            return set
        }

        /// 一条扫描线上最长的一段连续实心像素（横条厚度、边框厚度都用它）。
        func longestRun(_ line: [(Int, Int)], loose: Bool = false) -> Int {
            var longest = 0
            var current = 0
            for pixel in line {
                let hit = loose ? isAccentLoose(pixel.0, pixel.1) : isAccent(pixel.0, pixel.1)
                if hit {
                    current += 1
                    longest = max(longest, current)
                } else {
                    current = 0
                }
            }
            return longest
        }

        /// 至少约一半被强调色覆盖的像素。横条两端是 2pt 圆角，量长度时严判会
        /// 在两端各丢约 0.5pt（抗锯齿像素不是纯强调色），只能用这个口径量。
        func isAccentLoose(_ x: Int, _ y: Int) -> Bool {
            let (r, g, b) = rgb(x, y)
            return b >= 128 && b - r >= 100 && g >= 60 && g <= 200
        }

        func accentGaps(_ line: [(Int, Int)]) -> Int {
            var gaps = 0
            var inside = false
            for pixel in line {
                if isAccent(pixel.0, pixel.1) {
                    inside = true
                } else if inside {
                    gaps += 1
                    inside = false
                }
            }
            return gaps
        }

        /// 视图坐标里的一整行（沿 x 方向）或一整列（沿 y 方向）像素下标。
        func row(_ y: CGFloat, from minX: CGFloat, to maxX: CGFloat) -> [(Int, Int)] {
            let xs = stride(from: Int((minX * scale).rounded()), through: Int((maxX * scale).rounded()), by: 1)
            return xs.map { ($0, index(NSPoint(x: 0, y: y)).1) }
        }

        func column(_ x: CGFloat, from minY: CGFloat, to maxY: CGFloat) -> [(Int, Int)] {
            let ys = stride(from: Int((minY * scale).rounded()), through: Int((maxY * scale).rounded()), by: 1)
            return ys.map { (index(NSPoint(x: x, y: 0)).0, $0) }
        }
    }

    @MainActor static func run() throws -> String {
        _ = NSApplication.shared
        var checks = 0

        func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
            guard value() else { throw Failure(message: message) }
            checks += 1
        }
        func note(_ name: String, _ value: Any) {
            observations.append(["check": name, "value": value])
        }

        let size = NSSize(width: 600, height: 460)
        // 选区放在视图坐标系（未翻转，原点左下），四边留白，让尺寸标签也在画内。
        let rect = NSRect(x: 150, y: 130, width: 300, height: 200)

        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -5000, y: -5000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        window.contentView = container

        let host = SelectionView(frame: NSRect(origin: .zero, size: size))
        host.updateSelectionRect(rect)
        host.selectionInteractionEnabled = true
        container.addSubview(host)

        let overlay = SelectionChromeOverlay(frame: NSRect(origin: .zero, size: size))
        overlay.selectionView = host
        overlay.update(rect: rect, active: true)
        container.addSubview(overlay)

        window.orderFront(nil)
        container.layoutSubtreeIfNeeded()
        let scale = window.backingScaleFactor
        try check(scale > 0, "window must report a backing scale")

        @MainActor
        func render() throws -> Bitmap {
            guard let rep = container.bitmapImageRepForCachingDisplay(in: container.bounds) else {
                throw Failure(message: "cannot create caching bitmap")
            }
            container.cacheDisplay(in: container.bounds, to: rep)
            guard let image = rep.cgImage else { throw Failure(message: "caching bitmap has no CGImage") }
            let width = Int((size.width * scale).rounded())
            let height = Int((size.height * scale).rounded())
            let data = NSMutableData(length: width * height * 4)!
            guard let context = CGContext(
                data: data.mutableBytes, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { throw Failure(message: "cannot create raster context") }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return Bitmap(width: width, height: height, scale: scale,
                          bytes: Array(Data(bytes: data.bytes, count: data.length)))
        }

        // 1) 框选覆盖层自己画的 chrome（编辑器 overlay 隐藏，只剩 host）。
        overlay.isHidden = true
        let captureChrome = try render()
        // 2) 只剩编辑器 live 选框（host 隐藏，overlay 独占绘制）。
        overlay.isHidden = false
        host.isHidden = true
        let editorChrome = try render()
        host.isHidden = false

        // —— 逐像素同一套：强调色实心像素集合完全一致 ——
        let captureMask = captureChrome.accentPoints()
        let editorMask = editorChrome.accentPoints()
        let onlyCapture = captureMask.subtracting(editorMask).count
        let onlyEditor = editorMask.subtracting(captureMask).count
        note("accent-pixels.capture-overlay", captureMask.count)
        note("accent-pixels.editor", editorMask.count)
        note("accent-pixels.only-capture", onlyCapture)
        note("accent-pixels.only-editor", onlyEditor)
        try check(!captureMask.isEmpty, "capture overlay must paint selection chrome")
        try check(onlyCapture == 0 && onlyEditor == 0,
                  "editor chrome must be pixel-identical to the capture overlay chrome"
                  + " (only-capture \(onlyCapture), only-editor \(onlyEditor))")

        let bitmap = editorChrome
        func pt(_ pixels: Int) -> Double { Double(pixels) / Double(scale) }

        // —— 四条边：1pt 实线，虚线段数 0 ——
        let borderBands: [(String, [(Int, Int)], [(Int, Int)])] = [
            // 名字、法向扫描线（判线宽）、沿边扫描线（判虚线）
            ("top",
             bitmap.column(rect.minX + 60, from: rect.maxY - 3, to: rect.maxY + 3),
             bitmap.row(rect.maxY + 0.5, from: rect.minX, to: rect.maxX)),
            ("bottom",
             bitmap.column(rect.minX + 60, from: rect.minY - 3, to: rect.minY + 3),
             bitmap.row(rect.minY - 0.5, from: rect.minX, to: rect.maxX)),
            ("left",
             bitmap.row(rect.minY + 60, from: rect.minX - 3, to: rect.minX + 3),
             bitmap.column(rect.minX - 0.5, from: rect.minY, to: rect.maxY)),
            ("right",
             bitmap.row(rect.minY + 60, from: rect.maxX - 3, to: rect.maxX + 3),
             bitmap.column(rect.maxX + 0.5, from: rect.minY, to: rect.maxY)),
        ]
        for (name, normal, along) in borderBands {
            let thickness = normal.reduce(0) { $0 + (bitmap.isAccent($1.0, $1.1) ? 1 : 0) }
            let gaps = bitmap.accentGaps(along)
            note("border.\(name).thickness-pt", pt(thickness))
            note("border.\(name).dash-gaps", gaps)
            try check(abs(pt(thickness) - 1.0) < 0.01, "\(name) border must be 1pt, got \(pt(thickness))pt")
            try check(gaps == 0, "\(name) border must be solid — no dashed frame")
        }

        // —— 边中点横条 20×4pt，且不是圆点 ——
        let barProbes: [(String, [(Int, Int)], [(Int, Int)], NSPoint, NSPoint)] = [
            ("top",
             bitmap.column(rect.midX, from: rect.maxY - 8, to: rect.maxY + 8),
             bitmap.row(rect.maxY - 0.5, from: rect.midX - 30, to: rect.midX + 30),
             NSPoint(x: rect.midX, y: rect.maxY),
             NSPoint(x: rect.midX, y: rect.maxY - 2.5)),
            ("bottom",
             bitmap.column(rect.midX, from: rect.minY - 8, to: rect.minY + 8),
             bitmap.row(rect.minY + 0.5, from: rect.midX - 30, to: rect.midX + 30),
             NSPoint(x: rect.midX, y: rect.minY),
             NSPoint(x: rect.midX, y: rect.minY + 2.5)),
            ("left",
             bitmap.row(rect.midY, from: rect.minX - 8, to: rect.minX + 8),
             bitmap.column(rect.minX + 0.5, from: rect.midY - 30, to: rect.midY + 30),
             NSPoint(x: rect.minX, y: rect.midY),
             NSPoint(x: rect.minX + 2.5, y: rect.midY)),
            ("right",
             bitmap.row(rect.midY, from: rect.maxX - 8, to: rect.maxX + 8),
             bitmap.column(rect.maxX - 0.5, from: rect.midY - 30, to: rect.midY + 30),
             NSPoint(x: rect.maxX, y: rect.midY),
             NSPoint(x: rect.maxX - 2.5, y: rect.midY)),
        ]
        for (name, normal, along, center, dotProbe) in barProbes {
            // 垂直于边的方向：横条 4pt（含穿过它的 1pt 边框，连续实心即 4pt）。
            let thickness = bitmap.longestRun(normal)
            let length = bitmap.longestRun(along, loose: true)
            note("handle.\(name).thickness-pt", pt(thickness))
            note("handle.\(name).length-pt", pt(length))
            note("handle.\(name).length-pt.strict", pt(bitmap.longestRun(along)))
            note("handle.\(name).center", ["x": center.x, "y": center.y])
            try check(abs(pt(length) - 20.0) < 0.01, "\(name) handle must be a 20pt bar")
            try check(abs(pt(thickness) - 4.0) < 0.01, "\(name) handle must be a 4pt bar, got \(pt(thickness))pt")
            try check(!bitmap.isAccent(dotProbe), "\(name) handle must be a bar, not a dot")
        }

        // —— 四角 L 角标 12×2pt ——
        for (name, corner, sx, sy) in [
            ("topLeft", NSPoint(x: rect.minX, y: rect.maxY), CGFloat(1), CGFloat(-1)),
            ("topRight", NSPoint(x: rect.maxX, y: rect.maxY), CGFloat(-1), CGFloat(-1)),
            ("bottomLeft", NSPoint(x: rect.minX, y: rect.minY), CGFloat(1), CGFloat(1)),
            ("bottomRight", NSPoint(x: rect.maxX, y: rect.minY), CGFloat(-1), CGFloat(1)),
        ] {
            func probe(_ dx: CGFloat, _ dy: CGFloat) -> Bool {
                bitmap.isAccent(NSPoint(x: corner.x + dx * sx, y: corner.y + dy * sy))
            }
            try check(probe(11, 1), "\(name) must carry a 12pt horizontal arm")
            try check(!probe(13, 1), "\(name) horizontal arm must stop at 12pt")
            try check(probe(1, 11), "\(name) must carry a 12pt vertical arm")
            try check(!probe(1, 13), "\(name) vertical arm must stop at 12pt")
            try check(!probe(2.5, 2.5), "\(name) must be an L bracket, not a dot")
        }

        // —— 命中区 22×22pt ——
        try check(SelectionView.handleHitSize == 22, "capture overlay hit size must stay 22×22pt")
        let corner = NSPoint(x: rect.minX, y: rect.maxY)
        func hits(_ delta: CGFloat) -> Bool {
            overlay.hitTest(NSPoint(x: corner.x + delta, y: corner.y - delta)) != nil
        }
        note("hit.9pt", hits(9))
        note("hit.10pt", hits(10))
        note("hit.12pt", hits(12))
        note("hit.13pt", hits(13))
        try check(hits(9), "a press 9pt inside the corner must grab the handle (22×22pt target)")
        try check(hits(10), "a press 10pt inside the corner must still grab the handle")
        try check(!hits(12), "a press 12pt inside the corner must miss (the target is 22pt, not 24pt)")
        try check(!hits(13), "a press 13pt inside the corner must miss")

        // 拖动链路：角内 9pt 按下拖动，host 的选区左上角必须跟着指针走。
        let press = NSPoint(x: corner.x + 9, y: corner.y - 9)
        let drag = NSPoint(x: corner.x + 29, y: corner.y - 29)
        overlay.mouseDown(with: mouseEvent(.leftMouseDown, at: press, in: window))
        overlay.mouseDragged(with: mouseEvent(.leftMouseDragged, at: drag, in: window))
        overlay.mouseUp(with: mouseEvent(.leftMouseUp, at: drag, in: window))
        let resized = host.currentSelectionRect ?? .zero
        note("drag.rect", ["x": resized.minX, "y": resized.minY,
                           "width": resized.width, "height": resized.height])
        try check(abs(resized.minX - drag.x) < 0.51, "dragged corner must follow the pointer in x")
        try check(abs(resized.maxY - drag.y) < 0.51, "dragged corner must follow the pointer in y")
        try check(abs(resized.maxX - rect.maxX) < 0.51 && abs(resized.minY - rect.minY) < 0.51,
                  "resizing the top-left corner must leave the opposite corner anchored")

        window.orderOut(nil)
        container.subviews.forEach { $0.removeFromSuperview() }
        window.contentView = nil
        window.close()

        let payload: [String: Any] = [
            "passed": true, "checks": checks, "scale": Double(scale), "observations": observations,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    @MainActor
    static func mouseEvent(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        )!
    }
}
