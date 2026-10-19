import AppKit
import GlintCore
import os

/// The annotations over the frozen image (FR-29 to FR-36, FR-40): the committed ones, the shape
/// being dragged and the text box being edited.
///
/// `container` is geometry-flipped, so every sublayer uses GlintCore's top-left display points.
/// Vector shapes are shape layers (GPU paths; the frozen image is never redrawn, NFR-2). Text and
/// redactions show the very images the export renderer draws, so the export matches the screen.
@MainActor
final class AnnotationLayers {
    private static let logger = Logger(subsystem: GlintCore.bundleIdentifier, category: "capture")
    let container = CALayer()
    private let image: CGImage
    private let scale: CGFloat
    private let committedRoot = CALayer()
    /// Layers for the committed annotations, in order, with each redaction's patch.
    private var committed: [(annotation: Annotation, layer: CALayer, patch: CGImage?)] = []
    private let draftShape: VectorLayer
    private let draftOutline: DashedOutline
    private let textLayer = CALayer()
    private let markedLayer = CAShapeLayer()
    private let caretLayer = CALayer()
    private let textOutline: DashedOutline
    /// What `textLayer` currently shows, with its bitmap's frame relative to the box, so typing
    /// re-renders only when something changed and a move usually only moves the layer.
    private var shownText: (text: String, fontSize: CGFloat, color: RGBAColor, origin: CGPoint, bitmap: CGRect?)?

    init(frame: CGRect, image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
        draftShape = VectorLayer(scale: scale)
        draftOutline = DashedOutline(scale: scale)
        textOutline = DashedOutline(scale: scale)
        container.frame = frame
        container.isGeometryFlipped = true
        textLayer.contentsGravity = .resize
        markedLayer.contentsScale = scale
        for layer in [committedRoot, draftShape.root, draftOutline.root, textLayer, markedLayer, caretLayer,
                      textOutline.root] {
            layer.frame = container.bounds
            container.addSublayer(layer)
        }
    }

    /// Shows `annotations` in drawing order, the drag in progress and the text box being edited.
    /// Layers for annotations that did not change are kept, so undo, redo and new annotations
    /// only build what is new (a redaction is rebuilt when anything under it changed). The text
    /// box comes with the canvas's layout of it, so a long text is laid out once per edit.
    func update(annotations: [Annotation], draft: Annotation?,
                text: (box: TextBox, frame: CGRect, layout: TextLayout)?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        syncCommitted(annotations)
        showDraft(draft)
        showText(text)
    }

    /// The redaction patches on screen for `annotations`, by index, for the export to reuse
    /// (`Renderer.renderSelection(patches:)`). Only patches whose annotation and everything
    /// below it are unchanged count, so a stale patch is never exported.
    func patches(matching annotations: [Annotation]) -> [Int: CGImage] {
        var patches: [Int: CGImage] = [:]
        for (index, entry) in committed.enumerated() {
            guard index < annotations.count, entry.annotation == annotations[index] else { break }
            if let patch = entry.patch { patches[index] = patch }
        }
        return patches
    }

    // MARK: Committed

    private func syncCommitted(_ annotations: [Annotation]) {
        var kept = 0
        while kept < committed.count, kept < annotations.count, committed[kept].annotation == annotations[kept] {
            kept += 1
        }
        for stale in committed[kept...] { stale.layer.removeFromSuperlayer() }
        committed.removeSubrange(kept...)
        for index in kept..<annotations.count {
            let (layer, patch) = makeLayer(for: annotations[index], below: Array(annotations[..<index]))
            committedRoot.addSublayer(layer)
            committed.append((annotations[index], layer, patch))
        }
    }

    /// The layer for one annotation, and the patch it shows if it is a redaction. Redactions
    /// beneath it reuse the patches already made, so each redaction is rendered once.
    private func makeLayer(for annotation: Annotation, below: [Annotation]) -> (CALayer, CGImage?) {
        switch annotation {
        case let .text(text):
            let layer = CALayer()
            let layout = TextLayout(text: text.string, fontSize: text.fontSize)
            setText(layout, color: text.color, origin: text.origin, on: layer)
            return (layer, nil)
        case let .redaction(rect, style, width):
            let layer = CALayer()
            let patches = Dictionary(uniqueKeysWithValues: committed.enumerated().compactMap { index, entry in
                entry.patch.map { (index, $0) }
            })
            let patch = Renderer.redactionPatch(image, scale: scale, below: below, patches: patches, rect: rect,
                                                style: style, strokeWidth: width)
            layer.contents = patch
            layer.contentsGravity = .resize
            layer.isOpaque = true
            if patch == nil {
                // Never show the area unredacted; the export fails closed for the same reason.
                Self.logger.error("Could not make a redaction patch")
                layer.backgroundColor = NSColor.gray.cgColor
            }
            layer.frame = Renderer.patchFrame(for: rect, scale: scale,
                                              imageSize: PixelSize(width: image.width, height: image.height))
            return (layer, patch)
        default:
            let vector = VectorLayer(scale: scale)
            vector.root.frame = container.bounds
            vector.apply(AnnotationGeometry.shape(for: annotation))
            return (vector.root, nil)
        }
    }

    // MARK: Drag in progress

    /// Shapes show as they will be drawn; a redaction shows a dashed outline until it is
    /// released, because obscuring is too slow to redo on every pointer move.
    private func showDraft(_ draft: Annotation?) {
        if case let .redaction(rect, _, _)? = draft {
            draftShape.apply(nil)
            draftOutline.show(rect)
        } else {
            draftShape.apply(draft.flatMap(AnnotationGeometry.shape(for:)))
            draftOutline.show(nil)
        }
    }

    // MARK: Text box

    private func showText(_ text: (box: TextBox, frame: CGRect, layout: TextLayout)?) {
        guard let (box, frame, layout) = text else {
            textLayer.contents = nil
            shownText = nil
            markedLayer.path = nil
            caretLayer.isHidden = true
            textOutline.show(nil)
            return
        }
        let sameText = shownText.map { $0.text == box.text && $0.fontSize == box.fontSize && $0.color == box.color }
            ?? false
        if sameText, shownText?.origin == box.origin {
            // Only the caret or the marked text changed.
        } else if sameText, let shown = shownText, let bitmap = shown.bitmap,
                  Self.isWhole(bitmap, origin: shown.origin, in: container.bounds),
                  Self.isWhole(bitmap, origin: box.origin, in: container.bounds) {
            // Moved, with nothing cut off by the display's edge before or after: the same bitmap.
            textLayer.frame = bitmap.offsetBy(dx: box.origin.x, dy: box.origin.y)
            shownText?.origin = box.origin
        } else {
            let bitmap = setText(layout, color: box.color, origin: box.origin, on: textLayer)
            shownText = (box.text, box.fontSize, box.color, box.origin, bitmap)
        }

        let underline = CGMutablePath()
        if let marked = box.markedRange {
            for rect in layout.underlines(for: marked) { underline.addRect(rect.offsetBy(dx: box.origin.x, dy: box.origin.y)) }
        }
        markedLayer.path = underline
        markedLayer.fillColor = box.color.cgColor

        // The caret's left edge, top and bottom on whole pixels, so it stays crisp on every line.
        let caret = PixelSnapping.aligned(layout.caretRect(at: box.caret).offsetBy(dx: box.origin.x, dy: box.origin.y),
                                          scale: scale)
        let width = max(1, (box.fontSize / 12 * scale).rounded() / scale)
        caretLayer.isHidden = false
        caretLayer.backgroundColor = box.color.cgColor
        caretLayer.frame = CGRect(x: caret.minX, y: caret.minY, width: width, height: caret.height)
        textOutline.show(PixelSnapping.aligned(frame.insetBy(dx: -3, dy: -3), scale: scale))
    }

    /// Puts `layout`'s bitmap on `layer`, placed for a box at `origin`, and returns the bitmap's
    /// frame relative to the box. Only the part on this display is drawn, so a huge pasted text
    /// never needs a huge bitmap.
    @discardableResult
    private func setText(_ layout: TextLayout, color: RGBAColor, origin: CGPoint, on layer: CALayer) -> CGRect? {
        let display = container.bounds.offsetBy(dx: -origin.x, dy: -origin.y)
        let bitmap = layout.image(scale: scale, color: color, visible: display)
        layer.contents = bitmap?.image
        layer.frame = (bitmap?.frame ?? .zero).offsetBy(dx: origin.x, dy: origin.y)
        return bitmap?.frame
    }

    /// Whether a text bitmap at `frame` (relative to a box at `origin`) lies strictly inside
    /// `display`, so the display's edge did not cut it off.
    private static func isWhole(_ frame: CGRect, origin: CGPoint, in display: CGRect) -> Bool {
        let placed = frame.offsetBy(dx: origin.x, dy: origin.y)
        return placed.minX > display.minX && placed.maxX < display.maxX
            && placed.minY > display.minY && placed.maxY < display.maxY
    }
}

/// A vector annotation as a pair of shape layers: the fill (dots, arrow heads) under the stroke.
@MainActor
private final class VectorLayer {
    let root = CALayer()
    private let fill = CAShapeLayer()
    private let stroke = CAShapeLayer()

    init(scale: CGFloat) {
        for layer in [fill, stroke] {
            layer.contentsScale = scale
            root.addSublayer(layer)
        }
        stroke.fillColor = nil
    }

    func apply(_ shape: VectorShape?) {
        let color = shape?.color.cgColor
        fill.path = shape?.fill
        fill.fillColor = color
        stroke.path = shape?.stroke
        stroke.strokeColor = color
        stroke.lineWidth = shape?.lineWidth ?? 0
        stroke.lineCap = switch shape?.lineCap {
        case .butt?: .butt
        case .square?: .square
        default: .round
        }
        stroke.lineJoin = switch shape?.lineJoin {
        case .miter?: .miter
        case .bevel?: .bevel
        default: .round
        }
    }
}

/// A 1 pt white outline with a black 3-on/3-off dash, like the selection border (FR-20).
@MainActor
private final class DashedOutline {
    let root = CALayer()
    private let white = CAShapeLayer()
    private let dash = CAShapeLayer()

    init(scale: CGFloat) {
        for (layer, color) in [(white, NSColor.white), (dash, NSColor.black)] {
            layer.contentsScale = scale
            layer.fillColor = nil
            layer.strokeColor = color.cgColor
            layer.lineWidth = 1
            root.addSublayer(layer)
        }
        dash.lineDashPattern = [3, 3]
        dash.lineDashPhase = 0.5   // dash ends on whole pixels (the path is inset by half a line)
    }

    func show(_ rect: CGRect?) {
        let path = rect.map { CGPath(rect: $0.insetBy(dx: 0.5, dy: 0.5), transform: nil) }
        white.path = path
        dash.path = path
    }
}
