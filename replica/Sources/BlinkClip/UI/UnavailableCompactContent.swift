import AppKit
import BlinkClipCore
import SwiftUI

@MainActor
final class UnavailableCompactContentView: NSView {
    private let imageView = NSImageView(frame: .zero)
    private let textLabel = NSTextField(labelWithString: "")
    private lazy var imageTop = imageView.topAnchor.constraint(equalTo: topAnchor)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let pointSize: CGFloat
        if #available(macOS 26, *) { pointSize = 32 } else { pointSize = 48 }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [ToolbarAppearance.secondaryForeground()]))
        let image: NSImage
        if NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil) == nil {
            image = NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)!
        } else {
            image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)!
        }
        imageView.image = image.withSymbolConfiguration(configuration)
        textLabel.stringValue = String(localized: UnavailablePreviewLocalization.previewUnavailableTitle())
        textLabel.alignment = .center
        textLabel.textColor = ToolbarAppearance.secondaryForeground()
        textLabel.font = NSFont.preferredFont(forTextStyle: .callout, options: [:])
        for view in [imageView, textLabel] as [NSView] {
            addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        // Project only the original shortcut view's vertical anchors, not its behavior.
        let shortcutAlignment = NSLayoutGuide()
        addLayoutGuide(shortcutAlignment)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            imageTop,
            imageView.bottomAnchor.constraint(equalTo: textLabel.topAnchor, constant: -10),
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            textLabel.centerYAnchor.constraint(equalTo: shortcutAlignment.centerYAnchor),
            shortcutAlignment.heightAnchor.constraint(equalToConstant: 19),
            shortcutAlignment.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            shortcutAlignment.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            shortcutAlignment.widthAnchor.constraint(equalToConstant: 0)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(sizeClass: UInt8) {
        imageTop.constant = sizeClass == 3 ? 0 : 10
    }
}

@MainActor
struct UnavailableCompactContent: NSViewRepresentable {
    let sizeClass: UInt8

    func makeNSView(context: Context) -> UnavailableCompactContentView {
        let view = UnavailableCompactContentView(frame: .zero)
        view.configure(sizeClass: sizeClass)
        return view
    }

    func updateNSView(_ nsView: UnavailableCompactContentView, context: Context) {
        nsView.configure(sizeClass: sizeClass)
    }
}
