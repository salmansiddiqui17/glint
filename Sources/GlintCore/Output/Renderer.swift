import CoreGraphics

/// Flattens the frozen display image and its annotations into the exported image (FR-40, FR-42,
/// FR-45), and renders the redaction patches the live overlay shows (FR-36).
///
/// Every result is drawn into a new bitmap, never cut out of the frozen image, so an export does
/// not keep the whole frozen display alive (about 59 MB on a 5K display) while the Save panel is
/// open. Colour space and depth follow the source (NFR-10): deep or extended-range sources use a
/// 16-bit float context, opaque sources stay opaque, and sRGB is only a last resort.
public enum Renderer {
    /// The selection with its annotations, at the output resolution.
    ///
    /// - Parameters:
    ///   - image: the frozen display image at native pixels.
    ///   - scale: the image's pixels per point.
    ///   - annotations: in drawing order, in display points. Only what falls inside the selection
    ///     is exported.
    ///   - selection: display-local points, top-left origin.
    ///   - standardResolution: scale the result down to 1× (FR-45).
    ///   - known: redaction patches already made, by annotation index: the overlay's, so the
    ///     export shows exactly what the user saw and redoes none of it.
    /// - Returns: an image whose pixel size is exactly `OutputGeometry.outputPixelSize` (the badge
    ///   numbers). Nil when that size is zero, when Core Graphics cannot produce the image, or when
    ///   a redaction that shows in the selection cannot be made: never an unredacted export
    ///   (FR-36 AC1).
    ///   - obscure: how a redaction hides its area; tests replace it to check that a failed
    ///     redaction fails the export.
    public static func renderSelection(_ image: CGImage, scale: CGFloat, annotations: [Annotation],
                                       selection: CGRect, standardResolution: Bool,
                                       patches known: [Int: CGImage] = [:],
                                       obscure: Obscure = Redaction.obscure) -> CGImage? {
        let output = OutputGeometry.outputPixelSize(for: selection, scale: scale, imageSize: size(of: image),
                                                    standardResolution: standardResolution)
        guard output.width > 0, output.height > 0,
              let patches = redactionPatches(image, scale: scale, annotations: annotations, covering: selection,
                                             reusing: known, obscure: obscure),
              let native = render(image, scale: scale, annotations: annotations, patches: patches,
                                  region: selection) else { return nil }
        guard output != size(of: native) else { return native }
        return resample(native, to: output)
    }

    /// `region` of the frozen image with `annotations` drawn over it, at native pixels. The
    /// region's edges are rounded to whole pixels as in `OutputGeometry.pixelRect`.
    ///
    /// Redactions show their image from `patches`, keyed by their index in `annotations` (see
    /// `redactionPatches`); a redaction without one is skipped, so callers pass every patch that
    /// reaches `region`.
    public static func render(_ image: CGImage, scale: CGFloat, annotations: [Annotation],
                              patches: [Int: CGImage], region: CGRect) -> CGImage? {
        let pixels = OutputGeometry.pixelRect(for: region, scale: scale, imageSize: size(of: image))
        let regionSize = PixelSize(width: Int(pixels.width), height: Int(pixels.height))
        guard regionSize.width > 0, regionSize.height > 0 else { return nil }
        return bitmap(like: image, size: regionSize) { context in
            // Core Graphics is bottom-left: the region's top-left pixel goes to the context's top-left.
            context.draw(image, in: CGRect(x: -pixels.minX, y: pixels.maxY - CGFloat(image.height),
                                           width: CGFloat(image.width), height: CGFloat(image.height)))
            // From here on, user space is display points with a top-left origin, like the annotations.
            context.translateBy(x: 0, y: pixels.height)
            context.scaleBy(x: 1, y: -1)
            context.translateBy(x: -pixels.minX, y: -pixels.minY)
            context.scaleBy(x: scale, y: scale)
            for (index, annotation) in annotations.enumerated() {
                draw(annotation, patch: patches[index], in: context, imageSize: size(of: image), scale: scale)
            }
        }
    }

    /// The images the redactions in `annotations` show, keyed by index, worked out in drawing
    /// order with earlier patches drawn as images, so each redaction is rendered once.
    ///
    /// With `region`, only the redactions that show there are made: those reaching `region`, and
    /// those under a later one that does (it obscures what is beneath it). `known` patches are
    /// reused. Nil when a patch that is needed cannot be made.
    public static func redactionPatches(_ image: CGImage, scale: CGFloat, annotations: [Annotation],
                                        covering region: CGRect? = nil,
                                        reusing known: [Int: CGImage] = [:],
                                        obscure: Obscure = Redaction.obscure) -> [Int: CGImage]? {
        let imageSize = size(of: image)
        var needed = Set<Int>()
        var reach = region.map { [$0] } ?? []
        for index in annotations.indices.reversed() {
            guard case let .redaction(rect, _, _) = annotations[index] else { continue }
            let frame = patchFrame(for: rect, scale: scale, imageSize: imageSize)
            guard frame.width > 0, frame.height > 0 else { continue }   // covers no pixels: nothing to show
            if region == nil || reach.contains(where: { $0.intersects(frame) }) {
                needed.insert(index)
                reach.append(frame)
            }
        }
        var patches: [Int: CGImage] = [:]
        for index in annotations.indices where needed.contains(index) {
            guard case let .redaction(rect, style, width) = annotations[index] else { continue }
            guard let patch = known[index]
                ?? redactionPatch(image, scale: scale, below: Array(annotations[..<index]), patches: patches,
                                  rect: rect, style: style, strokeWidth: width, obscure: obscure) else { return nil }
            patches[index] = patch
        }
        return patches
    }

    /// What a redaction over `rect` shows: the image and every annotation drawn before it, with
    /// earlier redactions taken from `patches`, obscured (FR-36). The overlay shows this exact
    /// image, at `patchFrame(for:)`.
    public static func redactionPatch(_ image: CGImage, scale: CGFloat, below annotations: [Annotation],
                                      patches: [Int: CGImage], rect: CGRect, style: RedactionStyle,
                                      strokeWidth: CGFloat, obscure: Obscure = Redaction.obscure) -> CGImage? {
        guard let region = render(image, scale: scale, annotations: annotations, patches: patches, region: rect) else {
            return nil
        }
        return obscure(region, style, Redaction.strength(strokeWidth: strokeWidth))
    }

    /// Hides an image's content for a redaction (`Redaction.obscure`), or nil when it cannot.
    public typealias Obscure = @Sendable (CGImage, RedactionStyle, CGFloat) -> CGImage?

    /// Where a redaction patch for `rect` goes, in display points: `rect` rounded to whole pixels
    /// and clipped to the image.
    public static func patchFrame(for rect: CGRect, scale: CGFloat, imageSize: PixelSize) -> CGRect {
        let pixels = OutputGeometry.pixelRect(for: rect, scale: scale, imageSize: imageSize)
        return CGRect(x: pixels.minX / scale, y: pixels.minY / scale,
                      width: pixels.width / scale, height: pixels.height / scale)
    }

    // MARK: Drawing

    private static func draw(_ annotation: Annotation, patch: CGImage?, in context: CGContext, imageSize: PixelSize,
                             scale: CGFloat) {
        switch annotation {
        case let .text(text):
            TextLayout(text: text.string, fontSize: text.fontSize).draw(in: context, at: text.origin, color: text.color)
        case let .redaction(rect, _, _):
            guard let patch else { return }
            drawUpright(patch, in: patchFrame(for: rect, scale: scale, imageSize: imageSize), context: context)
        default:
            if let shape = AnnotationGeometry.shape(for: annotation) { paint(shape, in: context) }
        }
    }

    private static func paint(_ shape: VectorShape, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        if let fill = shape.fill {
            context.setFillColor(shape.color.cgColor)
            context.addPath(fill)
            context.fillPath()
        }
        if let stroke = shape.stroke {
            context.setStrokeColor(shape.color.cgColor)
            context.setLineWidth(shape.lineWidth)
            context.setLineCap(shape.lineCap)
            context.setLineJoin(shape.lineJoin)
            context.addPath(stroke)
            context.strokePath()
        }
    }

    /// Draws `image` into `rect` of the y-down user space without turning it upside down.
    private static func drawUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
    }

    // MARK: Bitmaps

    /// High-quality resample to `size` (FR-45), keeping the colour space and depth.
    static func resample(_ image: CGImage, to size: PixelSize) -> CGImage? {
        bitmap(like: image, size: size) { context in
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        }
    }

    /// `draw` run on a new bitmap like `image`: its own colour space and depth, else 8-bit sRGB.
    /// Each attempt covers the whole draw, because some colour spaces only fail when the image is
    /// made.
    private static func bitmap(like image: CGImage, size: PixelSize, draw: (CGContext) -> Void) -> CGImage? {
        let sourceSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        let deep = image.bitsPerComponent > 8 || (sourceSpace.map(CGColorSpaceUsesExtendedRange) ?? false)
        let opaque = [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let attempts: [(CGColorSpace?, Bool)] = [(sourceSpace, deep), (CGColorSpace(name: CGColorSpace.sRGB), false)]
        for (space, deep) in attempts {
            guard let space else { continue }
            let bitmapInfo: UInt32 = if deep {
                (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue
                    | CGBitmapInfo.floatComponents.rawValue | CGImageByteOrderInfo.order16Little.rawValue
            } else {
                (opaque ? CGImageAlphaInfo.noneSkipFirst : CGImageAlphaInfo.premultipliedFirst).rawValue
                    | CGImageByteOrderInfo.order32Little.rawValue
            }
            guard let context = CGContext(data: nil, width: size.width, height: size.height,
                                          bitsPerComponent: deep ? 16 : 8, bytesPerRow: 0, space: space,
                                          bitmapInfo: bitmapInfo) else { continue }
            draw(context)
            if let result = context.makeImage() { return result }
        }
        return nil
    }

    private static func size(of image: CGImage) -> PixelSize {
        PixelSize(width: image.width, height: image.height)
    }
}
