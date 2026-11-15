import AppKit

/// The one accent that means "this is the selection" everywhere in the product.
///
/// Both the capture overlay (`SelectionView`'s `selectionTint`) and the
/// editor's own selection chrome draw the same blue: frame/outline, the eight
/// resize handles, the size label and the magnifier lens crosshair. It is
/// defined once here so the editor and the lens cannot drift away from the
/// overlay, and so neither of them carries its own literal RGB.
///
/// Resolves to the system accent colour (converted to sRGB, because the drawing
/// code mixes it with `CGColor` and alpha) and only falls back to `systemBlue`
/// when the accent cannot be expressed in sRGB. On the reference machine the
/// system accent resolves to `#007AFF` / rgb(0, 122, 255), the same value the
/// overlay's `selectionTint` reports.
///
/// Not the same thing as `accentGreen` (see `ToolbarChrome.swift`): that one is
/// the "which tool / which option is active" accent used by the toolbar's
/// selected chips, the preset pickers and the confirm button. Selection
/// semantics — where the crop is — use this one.
let selectionAccent: NSColor = {
    NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue
}()
