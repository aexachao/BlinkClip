import AppKit

/// Editor-only gesture state. Both taps must include a short press and release.
struct EditorCommandDoubleTap {
    private var pressedAt: TimeInterval?
    private var pressedKey: UInt16?
    private var firstReleaseAt: TimeInterval?
    private let interval: TimeInterval = 0.4

    mutating func reset() {
        pressedAt = nil
        pressedKey = nil
        firstReleaseAt = nil
    }

    mutating func flagsChanged(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                               timestamp: TimeInterval) -> Bool {
        let flags = modifiers.intersection([.command, .shift, .option, .control, .function])
        guard keyCode == 54 || keyCode == 55 else { reset(); return false }
        if flags == .command {
            guard pressedAt == nil else { reset(); return false }
            if let firstReleaseAt, !(0...interval).contains(timestamp - firstReleaseAt) {
                self.firstReleaseAt = nil
            }
            pressedAt = timestamp
            pressedKey = keyCode
            return false
        }
        guard flags.isEmpty, let pressedAt, pressedKey == keyCode,
              (0...interval).contains(timestamp - pressedAt) else { reset(); return false }
        self.pressedAt = nil
        pressedKey = nil
        if let firstReleaseAt, (0...interval).contains(timestamp - firstReleaseAt) {
            reset()
            return true
        }
        firstReleaseAt = timestamp
        return false
    }
}
