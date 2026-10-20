import AppKit
import GlintCore

/// Draws the frozen image, the annotations, the 50 % veil, the selection border, handles, size
/// badge and brush preview with Core Animation layers (FR-17, FR-20, FR-25, FR-38). Takes no
/// mouse events.
///
/// Callers pass rectangles in display-local points with a top-left origin. They are snapped to
/// device pixels in that space (matching the export) and then converted to this view's
/// bottom-left layer coordinates.
final class OverlayChromeView: NSView {
    private let imageLayer = CALayer()
    /// Between the image and the veil, so annotations outside the selection are dimmed too.
    let annotations: AnnotationLayers
    /// Four plain bands around the selection: pure GPU compositing, no per-frame path rasterising (NFR-2).
    private let veilLayers = (0..<4).map { _ in CALayer() }
    private let borderLayer = CAShapeLayer()
    private let dashLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    private let badgeLayer = CALayer()
    private let badgeTextLayer = CATextLayer()
    private let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
    /// The brush preview (FR-38): a hairline circle, white with a black dash so it shows on any colour.
    private let brushLayers = [CAShapeLayer(), CAShapeLayer()]
    /// Device pixels per point, for pixel snapping.
    private let scale: CGFloat
    /// 1 pt, or 2 pt with Increase Contrast (NFR-14). Read once per capture.
    private let borderWidth: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 2 : 1

    private var flip: FlippedCoordinates { FlippedCoordinates(height: bounds.height) }

    init(frame: NSRect, image: CGImage, scale: CGFloat) {
        self.scale = scale
        annotations = AnnotationLayers(frame: CGRect(origin: .zero, size: frame.size), image: image, scale: scale)
        super.init(frame: frame)
        let root = CALayer()
        layer = root
        wantsLayer = true

        imageLayer.contents = image
        imageLayer.contentsGravity = .resize
        imageLayer.isOpaque = true
        imageLayer.frame = bounds

        for band in veilLayers {
            band.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor
        }

        for line in [borderLayer, dashLayer] {
            line.fillColor = nil
            line.lineWidth = borderWidth
        }
        borderLayer.strokeColor = NSColor.white.cgColor
        dashLayer.strokeColor = NSColor.black.cgColor
        dashLayer.lineDashPattern = [3, 3]
        dashLayer.lineDashPhase = borderWidth / 2   // dash ends on whole pixels (the path is inset by half a line)

        handlesLayer.fillColor = NSColor.black.cgColor
        handlesLayer.strokeColor = NSColor.white.cgColor
        handlesLayer.lineWidth = 1

        badgeLayer.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        badgeLayer.cornerRadius = 4
        badgeTextLayer.font = badgeFont
        badgeTextLayer.fontSize = badgeFont.pointSize
        badgeTextLayer.foregroundColor = NSColor.white.cgColor
        badgeTextLayer.alignmentMode = .center
        badgeTextLayer.contentsScale = scale
        badgeLayer.addSublayer(badgeTextLayer)

        for (layer, color) in zip(brushLayers, [NSColor.white, NSColor.black]) {
            layer.fillColor = nil
            layer.strokeColor = color.cgColor
            layer.lineWidth = 1 / scale
            layer.contentsScale = scale
        }
        brushLayers[1].lineDashPattern = [2, 2]

        ([imageLayer, annotations.container] + veilLayers + [borderLayer, dashLayer, handlesLayer, badgeLayer]
            + brushLayers).forEach(root.addSublayer)
        update(selection: nil, badgeText: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Size the badge needs for `text`, so the caller can lay it out.
    func badgeSize(for text: String) -> CGSize {
        let size = (text as NSString).size(withAttributes: [.font: badgeFont])
        return CGSize(width: ceil(size.width) + 12, height: ceil(size.height) + 6)
    }

    /// - Parameters:
    ///   - selection: top-left-origin points, or nil for no selection.
    ///   - badgeText: badge contents and its top-left-origin frame, or nil to hide it.
    ///   - showsHandles: false for a snap highlight (FR-19), which has the border and badge only.
    func update(selection: CGRect?, badgeText: (text: String, frame: CGRect)?, showsHandles: Bool = true) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let model = CGRect(origin: .zero, size: bounds.size)
        let hole = selection.map(snapped)
        for (band, rect) in zip(veilLayers, PixelSnapping.veilBands(around: hole, in: model)) {
            band.frame = toLayer(rect)
        }
        guard let selection, let hole else {
            [borderLayer, dashLayer, handlesLayer].forEach { $0.path = nil }
            badgeLayer.isHidden = true
            return
        }

        // Inset by half the line so it lies inside the hole; never past its centre (a 0 pt wide
        // selection mid-drag would otherwise give a null rect).
        let layerHole = toLayer(hole)
        let border = CGPath(rect: layerHole.insetBy(dx: min(borderWidth, layerHole.width) / 2,
                                                    dy: min(borderWidth, layerHole.height) / 2), transform: nil)
        borderLayer.path = border
        dashLayer.path = border

        // Inset by half the 1 pt stroke so each handle's outer edge is exactly 6 pt and pixel-aligned.
        let handles = CGMutablePath()
        for handle in Handle.allCases where showsHandles {
            handles.addRect(toLayer(snapped(handle.visibleFrame(in: selection))).insetBy(dx: 0.5, dy: 0.5))
        }
        handlesLayer.path = handles

        if let badgeText {
            badgeLayer.isHidden = false
            badgeLayer.frame = toLayer(snapped(badgeText.frame))
            badgeTextLayer.string = badgeText.text
            let textHeight = ceil(badgeFont.ascender - badgeFont.descender)
            badgeTextLayer.frame = CGRect(x: 0, y: ((badgeLayer.bounds.height - textHeight) / 2 * scale).rounded() / scale,
                                          width: badgeLayer.bounds.width, height: textHeight)
        } else {
            badgeLayer.isHidden = true
        }
    }

    /// Shows the brush preview centred on `center` (top-left points), or hides it.
    func showBrush(at center: CGPoint?, diameter: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let path = center.map { center -> CGPath in
            let point = flip.point(center)
            return CGPath(ellipseIn: CGRect(x: point.x - diameter / 2, y: point.y - diameter / 2,
                                            width: diameter, height: diameter), transform: nil)
        }
        brushLayers.forEach { $0.path = path }
    }

    /// Top-left model rect snapped to device pixels (same rounding as the export).
    func snapped(_ rect: CGRect) -> CGRect {
        PixelSnapping.aligned(rect, scale: scale)
    }

    private func toLayer(_ rect: CGRect) -> CGRect {
        flip.rect(rect)
    }
}
