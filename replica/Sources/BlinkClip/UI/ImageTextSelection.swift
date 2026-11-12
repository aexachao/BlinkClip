import AppKit
import ImageIO
import BlinkClipCore
import SwiftUI
import VisionKit

/// The reference delegates image text hit testing, dragging, and copying to
/// VisionKit. Its opaque analysis is separate from the searchable OCR cache.
@MainActor
struct ImageTextSelection: NSViewRepresentable {
    let item: ClipboardItem
    let image: NSImage

    final class Coordinator {
        var itemID: UUID?
        var sourcePayloads: [String: Data] = [:]
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ZoomableImageView {
        ZoomableImageView()
    }

    func updateNSView(_ imageView: ZoomableImageView, context: Context) {
        // Adding an OCR cache or renaming the item must not reset an active
        // Live Text selection. Only the displayed image payload identifies it.
        let payloads = item.payloads.filter { !$0.key.hasPrefix("com.chrisli.blinkclip.internal.recognized-") }
        guard context.coordinator.itemID != item.id || context.coordinator.sourcePayloads != payloads else { return }
        context.coordinator.itemID = item.id
        context.coordinator.sourcePayloads = payloads
        imageView.setImage(image)
        imageView.setTextRecognitionEnabled(false)
    }

    static func dismantleNSView(_ imageView: ZoomableImageView, coordinator: Coordinator) {
        imageView.makeImageView().hideImageAnalysisOverlay()
    }
}

@MainActor
final class ZoomableImageView: NSView {
    private var storedImageView: ImageTextImageView?
    private var storedContentView: ImageCenteringClipView?
    private var storedScrollView: NSScrollView?
    private var image: NSImage?
    private var isTextRecognitionEnabled = false

    init() {
        super.init(frame: .zero)
        let scrollView = makeScrollView()
        addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    override init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func makeImageView() -> ImageTextImageView {
        if let storedImageView { return storedImageView }
        let view = ImageTextImageView(frame: .zero)
        storedImageView = view
        return view
    }

    func makeContentView() -> ImageCenteringClipView {
        if let storedContentView { return storedContentView }
        let view = ImageCenteringClipView()
        view.documentView = makeImageView()
        view.drawsBackground = false
        storedContentView = view
        return view
    }

    func makeScrollView() -> NSScrollView {
        if let storedScrollView { return storedScrollView }
        let view = NSScrollView()
        view.hasVerticalScroller = true
        view.hasHorizontalScroller = true
        view.allowsMagnification = true
        view.drawsBackground = false
        view.contentView = makeContentView()
        storedScrollView = view
        return view
    }

    func currentImage() -> NSImage? { image }

    func setImage(_ image: NSImage?) {
        self.image = image
        makeImageView().image = self.image
    }

    func setTextRecognitionEnabled(_ value: Bool) {
        isTextRecognitionEnabled = value
        let imageView = makeImageView()
        // The reference's stored flag has this inverted interaction behavior.
        if value { imageView.hideImageAnalysisOverlay() }
        else { imageView.showImageAnalysisOverlay() }
    }

    func zoomToFit() {
        guard let image = currentImage() else { return }
        let widthRatio = image.size.width / frame.size.width
        let heightRatio = image.size.height / frame.size.height
        let ratio = widthRatio <= heightRatio ? heightRatio : widthRatio
        let scrollView = makeScrollView()
        scrollView.minMagnification = ratio >= 1 ? 1 : ratio
        scrollView.maxMagnification = ratio + ratio
        scrollView.magnification = ratio >= 1 ? 1 / ratio : ratio
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        zoomToFit()
    }

    override func layout() {
        super.layout()
        makeImageView().frame = frame
        zoomToFit()
    }
}

@MainActor
final class ImageCenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        guard let documentView else { return super.constrainBoundsRect(proposedBounds) }
        var constrained = super.constrainBoundsRect(proposedBounds)
        let scale = bounds.width > 0 ? constrained.width / bounds.width : 1
        let insets = contentInsets
        let top = scale * insets.top
        let left = scale * insets.left
        let bottom = scale * insets.bottom
        let right = scale * insets.right
        let minYInset = isFlipped ? top : bottom
        let maxYInset = isFlipped ? bottom : top
        let documentFrame = documentView.frame
        let expanded = NSRect(x: documentFrame.minX - left,
                              y: documentFrame.minY - minYInset,
                              width: left + right + documentFrame.width,
                              height: minYInset + maxYInset + documentFrame.height)
        if expanded.width < constrained.width {
            constrained.origin.x = expanded.minX + (constrained.width - expanded.width) * -0.5
        } else if constrained.width < expanded.width {
            if constrained.maxX > expanded.maxX {
                constrained.origin.x = expanded.maxX - constrained.width
            } else if constrained.minX < expanded.minX {
                constrained.origin.x = expanded.minX
            }
        }
        if expanded.height < constrained.height {
            constrained.origin.y = expanded.minY + (constrained.height - expanded.height) * -0.5
        } else if constrained.height < expanded.height {
            if constrained.maxY > expanded.maxY {
                constrained.origin.y = expanded.maxY - constrained.height
            } else if constrained.minY < expanded.minY {
                constrained.origin.y = expanded.minY
            }
        }
        return backingAlignedRect(constrained, options: .alignAllEdgesNearest)
    }
}

@MainActor
final class ImageTextImageView: NSImageView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // uses NSImageScaling raw value 3.
        imageScaling = .scaleProportionallyUpOrDown
        wantsLayer = true
        setAccessibilityLabel("图片预览，可选择图中文字")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// replace child views, track the displayed image, and
    /// retain the particular image/overlay until its unstructured task finishes.
    func showImageAnalysisOverlay() {
        subviews = []
        guard let image else { return }
        let overlay = ImageAnalysisOverlayView()
        overlay.preferredInteractionTypes = .automatic
        overlay.trackingImageView = self
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        Task { @MainActor [image, overlay] in
            let analyzer = ImageAnalyzer()
            let configuration = ImageAnalyzer.Configuration(.text)
            let rawOrientation = Self.imageOrientation(image)
            let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
            // The original failure continuation assigns nil and keeps the
            // overlay. It neither substitutes cached boxes nor exposes errors.
            overlay.analysis = try? await analyzer.analyze(image, orientation: orientation,
                                                          configuration: configuration)
        }
    }

    /// reads the NSImage TIFF representation's EXIF value,
    /// returning raw 1 whenever data, source, properties, or UInt32 conversion fail.
    static func imageOrientation(_ image: NSImage) -> UInt32 {
        guard let tiff = image.tiffRepresentation,
              let source = CGImageSourceCreateWithData(tiff as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let orientation = properties[kCGImagePropertyOrientation] as? UInt32 else { return 1 }
        return orientation
    }

    /// removes only the first matching analysis overlay.
    func hideImageAnalysisOverlay() {
        subviews.first(where: { $0 is ImageAnalysisOverlayView })?.removeFromSuperview()
    }
}
