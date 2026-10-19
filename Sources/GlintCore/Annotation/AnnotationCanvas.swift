import CoreGraphics

/// Drawing on one display while a tool is active (FR-28 to FR-36, FR-39, FR-56): tool gestures,
/// the text box being edited, and the annotations with their undo history.
///
/// Pure state machine with no AppKit, like `SelectionEditor`. Points are display-local, top-left
/// origin; pointer positions are clamped to `bounds`, so annotations stay on this display.
public struct AnnotationCanvas: Sendable {
    public let bounds: CGRect
    /// Device pixels per point, for pixel snapping.
    public let scale: CGFloat
    public private(set) var document = AnnotationDocument()
    /// The shape being dragged out, if any.
    public private(set) var draft: AnnotationDraft?
    /// The text box being edited, if any (FR-35).
    public private(set) var textBox: TextBox? {
        didSet {
            guard let box = textBox else {
                textLayout = nil
                return
            }
            if box.text != oldValue?.text || box.fontSize != oldValue?.fontSize {
                textLayout = TextLayout(text: box.text, fontSize: box.fontSize)
            }
        }
    }
    /// `textBox`'s layout, made only when its text or font size changes. The frame is asked for
    /// on every pointer move, and the overlay draws and measures the box with this same layout,
    /// so a long text is laid out once per edit.
    public private(set) var textLayout: TextLayout?
    /// At least half a line wide, so an empty box can be seen and grabbed.
    private var textBoxSize: CGSize {
        textLayout.map { CGSize(width: max($0.size.width, $0.lineHeight / 2), height: $0.size.height) } ?? .zero
    }
    private var textDrag: TextDrag?

    private struct TextDrag: Sendable {
        let start: CGPoint
        let origin: CGPoint
        var moved = false
    }

    public init(bounds: CGRect, scale: CGFloat) {
        self.bounds = bounds
        self.scale = scale
    }

    /// True while a drag is drawing a shape or moving the text box, so the toolbars hide (FR-26).
    public var isDrawing: Bool { draft != nil || textDrag != nil }

    /// True while the text box is being dragged (for the closed-hand cursor).
    public var isMovingText: Bool { textDrag?.moved == true }

    /// The text box's frame in display points: at least half a line wide, so an empty box can be
    /// seen and grabbed.
    public var textBoxFrame: CGRect? {
        textBox.map { CGRect(origin: $0.origin, size: textBoxSize) }
    }

    // MARK: Mouse

    /// Pressing with `tool` active. With the text tool, a press inside the text box grabs it;
    /// anywhere else commits the box and places a new one there (FR-35).
    public mutating func mouseDown(at rawPoint: CGPoint, tool: Tool, style: DrawingStyle, constrained: Bool) {
        // A press whose release never arrived leaves nothing behind.
        draft = nil
        textDrag = nil
        let point = clamp(rawPoint)
        if tool == .text {
            if let box = textBox, let frame = textBoxFrame, frame.contains(point) {
                textDrag = TextDrag(start: point, origin: box.origin)
                return
            }
            commitText()
            textBox = TextBox(origin: .zero, fontSize: style.fontSize, color: style.color)
            let origin = onDisplay(point, size: textBoxSize)   // the empty box's size, from its layout
            textBox?.origin = origin
        } else {
            commitText()
            var draft = AnnotationDraft(tool: tool, start: point, style: style, bounds: bounds, scale: scale)
            draft.setConstrained(constrained)
            self.draft = draft
        }
    }

    public mutating func mouseDragged(to rawPoint: CGPoint, constrained: Bool) {
        let point = clamp(rawPoint)
        if var drag = textDrag, var box = textBox {
            let dx = point.x - drag.start.x, dy = point.y - drag.start.y
            guard drag.moved || hypot(dx, dy) > SelectionEditor.dragThreshold else { return }
            drag.moved = true
            box.origin = onDisplay(CGPoint(x: drag.origin.x + dx, y: drag.origin.y + dy), size: textBoxSize)
            textDrag = drag
            textBox = box
        }
        draft?.drag(to: point, constrained: constrained)
    }

    /// Ends the gesture. A finished shape becomes one undo step; one too small to draw is
    /// dropped. A click inside the text box without dragging moves the caret to where it was
    /// pressed.
    public mutating func mouseUp(at rawPoint: CGPoint, constrained: Bool) {
        mouseDragged(to: rawPoint, constrained: constrained)
        if let drag = textDrag, var box = textBox {
            if !drag.moved {
                let layout = textLayout ?? TextLayout(text: box.text, fontSize: box.fontSize)
                box.moveCaret(to: layout.offset(at: CGPoint(x: drag.start.x - box.origin.x,
                                                            y: drag.start.y - box.origin.y)))
                textBox = box
            }
            textDrag = nil
        }
        if let finished = draft?.annotation { document.add(finished) }
        draft = nil
    }

    /// Esc mid-drag: drops the shape being drawn, or puts a dragged text box back where it was.
    /// The tool stays selected.
    public mutating func cancelGesture() {
        draft = nil
        if let drag = textDrag { textBox?.origin = drag.origin }
        textDrag = nil
    }

    /// ⇧ pressed or released mid-drag (FR-56).
    public mutating func setConstrained(_ constrained: Bool) {
        draft?.setConstrained(constrained)
    }

    // MARK: Text

    /// Applies an edit to the text box being edited: typing, caret moves, colour or size.
    public mutating func editText(_ edit: (inout TextBox) -> Void) {
        guard var box = textBox else { return }
        edit(&box)
        box.fontSize = DrawingLimits.fontSize(box.fontSize, steppedBy: 0)
        textBox = box
    }

    /// Ends editing (FR-35): a box with text becomes one annotation, an empty one is discarded
    /// without an undo step.
    public mutating func commitText() {
        guard let box = textBox else { return }
        textBox = nil
        textDrag = nil
        if let annotation = box.annotation { document.add(annotation) }
    }

    // MARK: Undo

    /// ⌘Z (FR-39). Pending text is committed first, so it is what gets undone.
    @discardableResult
    public mutating func undo() -> Bool {
        commitText()
        return document.undo()
    }

    /// ⇧⌘Z (FR-39).
    @discardableResult
    public mutating func redo() -> Bool {
        commitText()
        return document.redo()
    }

    /// Whether undo would remove something, counting a text box that has text.
    public var canUndo: Bool { document.canUndo || textBox?.annotation != nil }

    /// Whether redo would restore something. Typing in a box would clear it on commit, so it doesn't count then.
    public var canRedo: Bool { document.canRedo && textBox?.annotation == nil }

    // MARK: Helpers

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX), y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// A text box origin that keeps a box of `size` on the display (as far as it fits), on whole
    /// pixels so the overlay's text bitmap and the export match exactly.
    private func onDisplay(_ point: CGPoint, size: CGSize) -> CGPoint {
        func snapped(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        func pixelFloor(_ value: CGFloat) -> CGFloat { (value * scale).rounded(.down) / scale }
        let maxX = pixelFloor(bounds.maxX - min(size.width, bounds.width))
        let maxY = pixelFloor(bounds.maxY - min(size.height, bounds.height))
        return CGPoint(x: min(max(snapped(point.x), bounds.minX), maxX), y: min(max(snapped(point.y), bounds.minY), maxY))
    }
}
