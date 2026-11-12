import AppKit
import SwiftUI
import BlinkClipObjC

/// The panel meets the bottom screen edge with square corners.
enum ReplicaPanelSurface {
    static func shape(cornerRadius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: cornerRadius, bottomLeadingRadius: 0,
                               bottomTrailingRadius: 0, topTrailingRadius: cornerRadius,
                               style: .continuous)
    }
}

/// One native glass surface behind the toolbar and card collection.
struct ReplicaPanelGlassBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> PRPanelGlassBackground {
        let view = PRPanelGlassBackground(frame: .zero)
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ view: PRPanelGlassBackground, context: Context) {
        view.cornerRadius = cornerRadius
    }
}
