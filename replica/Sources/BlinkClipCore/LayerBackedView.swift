import AppKit
import QuartzCore

@MainActor
public enum ViewLayerFunctions {
    public static func borderColor(_ view: NSView) -> NSColor? {
        guard let color = view.layer?.borderColor else { return nil }
        return NSColor(cgColor: color)
    }

    @discardableResult
    public static func setBorderColor(_ color: NSColor?, view: NSView) -> Int {
        view.wantsLayer = true
        view.layer?.borderColor = color?.cgColor
        return 0
    }

    @discardableResult
    public static func setCornerRadius(_ radius: CGFloat, curve: CALayerCornerCurve, view: NSView) -> Int {
        view.wantsLayer = true
        view.clipsToBounds = true
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = curve
        return 0
    }
}

@MainActor
open class LayerBackedView: NSView {
    private var storedBackgroundColor: NSColor?

    open var backgroundColor: NSColor? {
        get { currentStoredBackgroundColor() }
        set { setStoredBackgroundColor(newValue) }
    }

    public var replicaBorderColor: NSColor? {
        get { ViewLayerFunctions.borderColor(self) }
        set { ViewLayerFunctions.setBorderColor(newValue, view: self) }
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    public func currentStoredBackgroundColor() -> NSColor? { storedBackgroundColor }

    public func setStoredBackgroundColor(_ color: NSColor?) {
        storedBackgroundColor = color
        refreshAppearanceColors()
    }

    public func refreshAppearanceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            Self.updateLayerColors(self)
        }
    }

    public static func updateLayerColors(_ view: LayerBackedView) { view.updateLayerColors() }

    public func updateLayerColors() {
        if let layer { layer.backgroundColor = backgroundColor?.cgColor }
        if let layer { layer.borderColor = replicaBorderColor?.cgColor }
    }

    public func updateForAppearanceChange() {
        super.viewDidChangeEffectiveAppearance()
        refreshAppearanceColors()
    }

    public func updateAppearance() { updateForAppearanceChange() }
    open override func viewDidChangeEffectiveAppearance() { updateAppearance() }
}

@MainActor
public enum SearchSurfaceAppearance {
    private static let colorSlot: UnsafeMutablePointer<NSColor?> = {
        let slot = UnsafeMutablePointer<NSColor?>.allocate(capacity: 1)
        slot.initialize(to: nil)
        return slot
    }()
    private static let initialized: Void = setupBorderColor()

    public static func setupBorderColor() {
        let dark = NSColor.white.withAlphaComponent(0.1)
        let light = NSColor.black.withAlphaComponent(0.1)
        colorSlot.pointee = NSColor(name: nil) { appearance in
            SearchAppearance.appearanceColor(appearance: appearance, dark: dark, light: light)
        }
    }

    public static func borderColorSlot() -> UnsafeMutablePointer<NSColor?> {
        _ = initialized
        return colorSlot
    }
}
