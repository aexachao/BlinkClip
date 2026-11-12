import AppKit

enum NavigationKey: UInt8 {
    case enter, tab, space, escape, home, pageUp, end, pageDown
    case left, right, down, up, other

    /// reads only the physical key code.
    @MainActor
    static func fromEvent(_ event: NSEvent) -> Self {
        fromKeyCode(event.keyCode)
    }

    /// modifiers and characters do not affect this classification.
    static func fromKeyCode(_ keyCode: UInt16) -> Self {
        switch keyCode {
        case 0x24: return .enter
        case 0x30: return .tab
        case 0x31: return .space
        case 0x35: return .escape
        case 0x73: return .home
        case 0x74: return .pageUp
        case 0x77: return .end
        case 0x79: return .pageDown
        case 0x7b: return .left
        case 0x7c: return .right
        case 0x7d: return .down
        case 0x7e: return .up
        default: return .other
        }
    }
}
