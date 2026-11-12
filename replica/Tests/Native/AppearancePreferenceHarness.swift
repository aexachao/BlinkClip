import Combine
import Foundation

@main
struct AppearancePreferenceHarness {
    struct Failure: Error { let message: String }
    struct Preferences {
        var appearance = "system"
        var panelHeight = 332.0
        var historyRetentionDays = 7
        var playSounds = true
    }
    @MainActor final class Fixture: ObservableObject {
        @Published var preferences = Preferences()
    }
    @MainActor static func drain() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
    @MainActor static func main() async {
        do { try await run() }
        catch { print("FAIL: \(error)"); exit(1) }
    }
    @MainActor static func run() async throws {
        let out = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixture = Fixture()
        var appearances: [String] = []
        var geometries: [Double] = []
        var assertions = 0
        func check(_ condition: Bool, _ message: String) throws {
            assertions += 1
            if !condition { throw Failure(message: message) }
        }
        func projection() -> WindowAppearancePreferences {
            WindowAppearancePreferences(appearance: fixture.preferences.appearance,
                                        panelHeight: fixture.preferences.panelHeight)
        }
        var observer: WindowAppearancePreferenceObservation? = WindowAppearancePreferenceObservation(
            initial: projection(),
            changes: fixture.$preferences.map {
                WindowAppearancePreferences(appearance: $0.appearance, panelHeight: $0.panelHeight)
            }.eraseToAnyPublisher(),
            applyAppearance: {
                appearances.append(projection().appearance)
                // Mirrors the existing appearance operation's visible-panel positioning.
                geometries.append(projection().panelHeight)
            },
            positionPanel: { geometries.append(projection().panelHeight) })
        try check(appearances == ["system"] && geometries == [332], "initial apply exactly once")
        await drain()
        try check(appearances.count == 1, "publisher's initial value does not duplicate init")
        for day in 1...100 {
            fixture.preferences.historyRetentionDays = day
            fixture.preferences.playSounds.toggle()
            await drain()
        }
        try check(appearances.count == 1 && geometries.count == 1, "100 unrelated preference updates do not touch windows")
        for style in ["light", "dark", "system"] {
            fixture.preferences.appearance = style
            try check(appearances.last != style, "work waits for Published assignment to complete")
            await drain()
            try check(appearances.last == style, "genuine theme change reads the new value")
        }
        try check(appearances.count == 4 && geometries.count == 4, "three theme changes apply once each")
        fixture.preferences.panelHeight = 450
        await drain()
        try check(appearances.count == 4 && geometries == [332,332,332,332,450], "height-only change positions without resetting appearance")
        fixture.preferences.panelHeight = 450
        await drain()
        try check(geometries.count == 5, "identical height is ignored")
        fixture.preferences.panelHeight = .nan
        await drain()
        try check(geometries.last == 332 && geometries.count == 6, "invalid height uses existing effective fallback")
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1] {
            fixture.preferences.panelHeight = invalid
            await drain()
        }
        try check(geometries.count == 6, "equivalent invalid heights do not produce repeated geometry")
        for invalidStyle in ["", "auto", "unknown"] {
            fixture.preferences.appearance = invalidStyle
            await drain()
        }
        try check(appearances.count == 4, "unknown appearances normalize to system without repaint")
        fixture.preferences.appearance = "dark"
        fixture.preferences.panelHeight = 600
        await drain()
        try check(appearances == ["system","light","dark","system","dark"], "simultaneous fields apply the final appearance once")
        try check(geometries.count == 7 && geometries.last == 600, "combined theme and geometry does not position twice")
        fixture.preferences.appearance = "light"
        fixture.preferences.panelHeight = 700
        fixture.preferences.appearance = "dark"
        fixture.preferences.panelHeight = 600
        await drain()
        try check(appearances.count == 5 && geometries.count == 7, "burst returning to current effective values performs no work")
        fixture.preferences.historyRetentionDays = 1
        fixture.preferences.historyRetentionDays = 60
        await drain()
        try check(appearances.count == 5 && geometries.count == 7, "shorter and longer periods remain unrelated to appearance")
        fixture.preferences.appearance = "light"
        weak var released = observer
        observer = nil
        try check(released == nil, "observation has no retain cycle")
        await drain()
        try check(appearances.count == 5, "queued work is cancelled by observer lifetime")
        fixture.preferences.appearance = "system"
        await drain()
        try check(appearances.count == 5, "publisher is unsubscribed after destruction")
        let result: [String: Any] = ["passed":true,"assertions":assertions,
            "appearanceApplications":appearances.count,"geometryApplications":geometries.count,
            "unrelatedPreferenceUpdates":200,
            "boundary":"Actual production observer with Published fixture and operation spies; no NSApp, windows, ClipboardStore, TCC or user defaults. No claim about full save latency."]
        try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:out.appendingPathComponent("result.json"))
        print(String(decoding:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),as:UTF8.self))
    }
}
