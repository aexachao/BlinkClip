import AppKit
import Foundation

/// The controller's windowDidLoad implementation, including super.
@MainActor public final class StackWindowController: NSWindowController {
    public static let stackFrameAutosaveName = "com.chrisli.blinkclip.paste-stack-frame"

    public override func windowDidLoad() { configureWindow() }

    public func configureWindow() {
        super.windowDidLoad()
        window?.level = .statusBar
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window?.isMovableByWindowBackground = true
        window?.setFrameAutosaveName(Self.stackFrameAutosaveName)
    }
}

/// Address-level reconstructions used by the real UI, not placeholder exports.
public enum StackFunctions {
    @MainActor public static func canBecomeMain() -> Bool { canBecomeKeyOrMain() }
    @MainActor public static func canBecomeKey() -> Bool { canBecomeKeyOrMain() }

    /// Original helper checks MainActor isolation and returns false for both window selectors.
    @MainActor public static func canBecomeKeyOrMain() -> Bool { false }

    /// Original in-place reversal swaps both ends and preserves Swift Array copy-on-write.
    /// The decompiler's ulong return is an ABI recovery artifact; callers use the mutated array.
    public static func reverseValues<T>(_ values: inout [T]) { values.reverse() }
}
