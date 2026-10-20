import AppKit
import GlintCore

@MainActor
protocol OverlayViewDelegate: AnyObject {
    /// The user started a new selection on this display; other displays must clear theirs (FR-18).
    func overlayDidBeginSelection(_ view: OverlayView)
    /// The view holding the single selection, on whichever display it is (FR-18). Keyboard focus
    /// follows the pointer, so the key view may not be the one with the selection.
    func overlaySelectionOwner() -> OverlayView?
    /// Copy and save act on the selection owner's selection, whichever view sends them.
    func overlay(_ view: OverlayView, perform action: OverlayAction)
    /// Esc (FR-27): commit the text being edited, else leave the tool, else cancel.
    func overlayEscape(_ view: OverlayView)
    /// The view whose text box is being edited. It keeps keyboard focus while the pointer
    /// visits other displays, so typing keeps going into the box (FR-35).
    func overlayTextEditor() -> OverlayView?
    /// The palette's Colour button: open the colour panel next to `anchor` (screen coordinates).
    func overlayShowColorPanel(near anchor: CGRect)
}

/// The interactive overlay for one display: mouse and keyboard editing of the selection, window
/// snapping, drawing with the tools, and the action toolbar and tools palette (FR-17 to FR-41,
/// FR-56). Geometry and drawing state live in `SelectionEditor` and `AnnotationCanvas` (GlintCore).
final class OverlayView: NSView {
    weak var delegate: OverlayViewDelegate?
    let capture: DisplayCapture
    /// The annotations on this display (FR-40).
    private(set) var canvas: AnnotationCanvas
    private let drawing: DrawingState
    private var editor: SelectionEditor
    private let standardResolution: Bool
    private let chrome: OverlayChromeView
    private let toolbar = ActionToolbar()
    private let palette = ToolsPalette()
    private var trackingArea: NSTrackingArea?
    /// True once the pointer has moved during the current press, so a plain click doesn't flash the toolbars.
    private var pointerMoved = false
    /// Which state machine the current press went to.
    private var gesture = Gesture.none
    private var scrollSteps = ScrollStepper()
    /// Whether the current trackpad scroll gesture began over the text box (it then sizes the
    /// text until the gesture ends, even if the shrinking box leaves the pointer behind).
    private var scrollingText = false
    /// The window or display highlighted under the pointer while nothing is selected (FR-19).
    private var highlight: CGRect?

    private enum Gesture {
        case none, selection, drawing
    }

    init(capture: DisplayCapture, snapTargets: SnapTargets, drawing: DrawingState, standardResolution: Bool) {
        self.capture = capture
        self.drawing = drawing
        self.standardResolution = standardResolution
        let frame = CGRect(origin: .zero, size: capture.frame.size)
        editor = SelectionEditor(bounds: frame, snapTargets: snapTargets)
        canvas = AnnotationCanvas(bounds: frame, scale: capture.scale)
        chrome = OverlayChromeView(frame: frame, image: capture.image, scale: capture.scale)
        super.init(frame: frame)
        wantsLayer = true
        addSubview(chrome)
        toolbar.isHidden = true
        toolbar.onAction = { [weak self] action in
            guard let self else { return }
            self.delegate?.overlay(self, perform: action)
        }
        addSubview(toolbar)
        palette.isHidden = true
        palette.onAction = { [weak self] action in self?.handle(action) }
        addSubview(palette)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    var selection: CGRect? { editor.selection }

    var isEditingText: Bool { canvas.textBox != nil }

    /// The layout of the text box being edited, made by the canvas once per edit.
    var textLayout: TextLayout? { canvas.textLayout }

    func clearSelection() {
        commitText()
        editor.clearSelection()
        refresh()
    }

    /// Ends text editing (FR-35): the box becomes an annotation, or is dropped if empty.
    func commitText() {
        guard canvas.textBox != nil else { return }
        endComposition()
        canvas.commitText()
        refresh()
    }

    /// Ends any input-method composition before the canvas commits text on its own (a click
    /// elsewhere, undo, redo), so the next keystroke doesn't continue it in another box.
    private func endComposition() {
        guard canvas.textBox?.markedRange != nil else { return }
        inputContext?.discardMarkedText()
        canvas.editText { $0.unmarkText() }
    }

    /// Esc (FR-27): mid-drag it cancels the shape being drawn and keeps the tool; otherwise the
    /// session works through its stages.
    func handleEscape() {
        if canvas.isDrawing {
            canvas.cancelGesture()
            gesture = .none
            refresh()
        } else {
            delegate?.overlayEscape(self)
        }
    }

    /// The selection with its annotations at the output resolution (FR-42, FR-45). Pending text
    /// is committed first.
    func renderSelection() -> CGImage? {
        commitText()
        guard let selection = editor.selection else { return nil }
        // The patches on screen are reused, so the export shows exactly what the user saw.
        let annotations = canvas.document.annotations
        return Renderer.renderSelection(capture.image, scale: capture.scale, annotations: annotations,
                                        selection: selection, standardResolution: standardResolution,
                                        patches: chrome.annotations.patches(matching: annotations))
    }

    var outputDPI: CGFloat {
        OutputGeometry.dpi(scale: capture.scale, standardResolution: standardResolution)
    }

    /// The shared tool or style changed (on any display): changing tool commits text, and a new
    /// colour applies to the text being edited (FR-35).
    func drawingStateDidChange() {
        if drawing.tool != .text { commitText() }
        canvas.editText { $0.color = drawing.style.color }
        refresh()
    }

    func undo() {
        endComposition()
        canvas.undo()
        refresh()
    }

    func redo() {
        // Disabled while a box has text (it would commit the box), as the palette shows.
        guard canvas.canRedo else { return NSSound.beep() }
        endComposition()
        canvas.redo()
        refresh()
    }

    /// ⌘V into the text box (FR-35). Any composition ends first, so the input method and the box
    /// stay in step.
    func paste(_ text: String) {
        endComposition()
        editText { $0.type(text) }
    }

    /// Applies an edit to the text box being edited, then redraws.
    func editText(_ edit: (inout TextBox) -> Void) {
        canvas.editText(edit)
        inputContext?.invalidateCharacterCoordinates()
        refresh()
    }

    private func handle(_ action: PaletteAction) {
        switch action {
        case let .tool(tool):
            drawing.tool = drawing.tool == tool ? nil : tool   // clicking the active tool deselects it
        case .color:
            guard let window else { return }
            delegate?.overlayShowColorPanel(near: window.convertToScreen(palette.convert(palette.bounds, to: nil)))
        case .undo:
            undo()
        case .redo:
            redo()
        }
    }

    // MARK: Drawing

    /// A tool draws only on the display that holds the selection; elsewhere a press starts a new
    /// selection (FR-18, FR-28).
    private var activeTool: Tool? {
        editor.selection != nil ? drawing.tool : nil
    }

    private func refresh() {
        highlight = hoverHighlight()
        var badge: (text: String, frame: CGRect)?
        if let selection = editor.selection {
            let text = OutputGeometry.badgeText(outputSize(of: selection))
            let toolbarFrame = OverlayLayout.actionToolbarFrame(size: ActionToolbar.size, selection: selection,
                                                                bounds: bounds)
            let paletteFrame = OverlayLayout.toolsPaletteFrame(size: ToolsPalette.size, selection: selection,
                                                               bounds: bounds, avoiding: toolbarFrame)
            toolbar.frame = flip.rect(chrome.snapped(toolbarFrame))
            palette.frame = flip.rect(chrome.snapped(paletteFrame))
            toolbar.selectionFrame = flip.rect(chrome.snapped(selection))
            palette.selectionFrame = toolbar.selectionFrame
            badge = (text, OverlayLayout.badgeFrame(size: chrome.badgeSize(for: text), selection: selection,
                                                    bounds: bounds, avoiding: toolbarFrame, palette: paletteFrame))
        } else if let highlight {
            let text = OutputGeometry.badgeText(outputSize(of: highlight))
            badge = (text, OverlayLayout.badgeFrame(size: chrome.badgeSize(for: text), selection: highlight,
                                                    bounds: bounds))
        }
        chrome.update(selection: editor.selection ?? highlight, badgeText: badge,
                      showsHandles: editor.selection != nil)
        chrome.annotations.update(annotations: canvas.document.annotations, draft: canvas.draft?.annotation,
                                  text: canvas.textBox.flatMap { box in
                                      canvas.textBoxFrame.flatMap { frame in canvas.textLayout.map { (box, frame, $0) } }
                                  })
        // Both toolbars hide while dragging a selection or drawing, and come back on mouse-up (FR-26).
        let busy = (editor.isDragging || canvas.isDrawing) && pointerMoved
        toolbar.isHidden = editor.selection == nil || busy
        palette.isHidden = toolbar.isHidden
        palette.update(activeTool: drawing.tool, color: drawing.style.color, canUndo: canvas.canUndo,
                       canRedo: canvas.canRedo)
        updateCursor()
    }

    /// The exported pixel size of `rect`, which the badge shows (FR-25, FR-42).
    private func outputSize(of rect: CGRect) -> PixelSize {
        OutputGeometry.outputPixelSize(for: rect, scale: capture.scale,
                                       imageSize: PixelSize(width: capture.image.width, height: capture.image.height),
                                       standardResolution: standardResolution)
    }

    // MARK: Window snapping (FR-19)

    /// The frame a click would select, while no display has a selection, no tool is active and
    /// the pointer is on this one. With a selection there is no hover highlight, though a click
    /// outside it still snaps (OQ-12).
    private func hoverHighlight() -> CGRect? {
        guard editor.selection == nil, drawing.tool == nil, delegate?.overlaySelectionOwner() == nil,
              let window else { return nil }
        let viewPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        // Inclusive of the top edge, like updateCursor(): on the edge two displays share, only
        // one of them highlights.
        guard NSMouseInRect(viewPoint, bounds, isFlipped) else { return nil }
        return editor.snapHighlight(at: flip.point(viewPoint))
    }

    /// Updates the snap highlight and the cursor for the pointer's position.
    func pointerDidMove() {
        if hoverHighlight() != highlight {
            refresh()
        } else {
            updateCursor()
        }
    }

    // MARK: Coordinates (model: top-left origin; view: bottom-left origin)

    var flip: FlippedCoordinates { FlippedCoordinates(height: bounds.height) }

    private func modelPoint(_ event: NSEvent) -> CGPoint {
        flip.point(convert(event.locationInWindow, from: nil))
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    /// Keyboard focus follows the pointer between displays (FR-17), except while a text box is
    /// being edited on another display.
    override func mouseEntered(with event: NSEvent) {
        if let editing = delegate?.overlayTextEditor(), editing !== self { return pointerDidMove() }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        pointerDidMove()
    }

    override func mouseExited(with event: NSEvent) {
        chrome.showBrush(at: nil, diameter: 0)
        pointerDidMove()
    }

    override func mouseMoved(with event: NSEvent) {
        pointerDidMove()
    }

    override func mouseDown(with event: NSEvent) {
        // A click on another display takes keyboard focus there, so it ends the editing (FR-35).
        if let editing = delegate?.overlayTextEditor(), editing !== self { editing.commitText() }
        pointerMoved = false
        let point = modelPoint(event)
        if let tool = activeTool {
            gesture = .drawing
            endComposition()
            canvas.mouseDown(at: point, tool: tool, style: drawing.style, constrained: event.modifierFlags.contains(.shift))
        } else {
            gesture = .selection
            editor.mouseDown(at: point, clickCount: event.clickCount)
        }
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        pointerMoved = true
        let point = modelPoint(event)
        switch gesture {
        case .drawing:
            canvas.mouseDragged(to: point, constrained: event.modifierFlags.contains(.shift))
        case .selection:
            if editor.mouseDragged(to: point) { delegate?.overlayDidBeginSelection(self) }
        case .none:
            break
        }
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        let point = modelPoint(event)
        switch gesture {
        case .drawing:
            canvas.mouseUp(at: point, constrained: event.modifierFlags.contains(.shift))
        case .selection:
            // A fast flick can create the selection on release, and a click snaps (FR-19). With a
            // tool active, a click on a display without the selection does nothing, as before:
            // it must not move the selection away from the annotations (OQ-12).
            if editor.mouseUp(at: point, snapping: drawing.tool == nil) {
                delegate?.overlayDidBeginSelection(self)
            }
        case .none:
            break
        }
        gesture = .none
        refresh()
    }

    /// Pressing or releasing ⇧ mid-drag updates the constraint live (FR-56).
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard gesture == .drawing else { return }
        canvas.setConstrained(event.modifierFlags.contains(.shift))
        refresh()
    }

    /// The scroll wheel changes the stroke width, or the font size over the text box (FR-35,
    /// FR-38). Pushing the wheel or fingers up makes it bigger, whatever the scroll direction setting.
    /// Ignored mid-drag: the shape being drawn keeps the width it started with. Momentum after the
    /// fingers lift is ignored too, so one flick can't run the width to its limit.
    override func scrollWheel(with event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        let overText = canvas.textBoxFrame?.contains(modelPoint(event)) == true
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            scrollSteps = ScrollStepper()   // a new gesture starts from zero
            scrollingText = overText
        }
        let delta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        let steps = scrollSteps.steps(for: delta, precise: event.hasPreciseScrollingDeltas)
        guard steps != 0, !canvas.isDrawing else { return }
        // A wheel has no gesture phases, so each notch decides for itself.
        if let box = canvas.textBox, event.phase.isEmpty ? overText : scrollingText {
            let size = DrawingLimits.fontSize(box.fontSize, steppedBy: steps)
            editText { $0.fontSize = size }
            drawing.style.fontSize = size
        } else {
            changeStrokeWidth(by: steps)
        }
    }

    /// ⌘+ / ⌘− and the scroll wheel (FR-38); ignored mid-drag, like the scroll wheel.
    private func changeStrokeWidth(by steps: Int) {
        guard !canvas.isDrawing else { return }
        drawing.style.strokeWidth = DrawingLimits.strokeWidth(drawing.style.strokeWidth, steppedBy: steps)
    }

    /// FR-21, FR-38: the cursor for the current gesture or what is under the pointer, and the
    /// brush preview while a stroking tool is active. Does nothing when the pointer is over
    /// another display, which sets its own cursor.
    func updateCursor() {
        guard let window else { return }
        let viewPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard NSMouseInRect(viewPoint, bounds, isFlipped) else {   // inclusive of the top edge
            // A drag can leave this display without an exit event, so the brush is hidden here too.
            return chrome.showBrush(at: nil, diameter: 0)
        }
        let point = flip.point(viewPoint)
        let overToolbars = (!toolbar.isHidden && toolbar.frame.contains(viewPoint))
            || (!palette.isHidden && palette.frame.contains(viewPoint))
        let tool = activeTool
        let showsBrush = tool?.showsBrushPreview == true && (canvas.draft != nil || !overToolbars)
        chrome.showBrush(at: showsBrush ? point : nil, diameter: drawing.style.strokeWidth)

        if editor.isCreating || canvas.draft != nil {
            NSCursor.crosshair.set()
        } else if editor.isMoving || canvas.isMovingText {
            NSCursor.closedHand.set()
        } else if let handle = editor.resizingHandle {
            NSCursor.frameResize(position: handle.cursorPosition, directions: .all).set()
        } else if overToolbars {
            NSCursor.arrow.set()
        } else if tool == .text {
            (canvas.textBoxFrame?.contains(point) == true ? NSCursor.openHand : NSCursor.iBeam).set()
        } else if tool != nil {
            NSCursor.crosshair.set()
        } else if let selection = editor.selection, let handle = Handle.hit(point, selection: selection) {
            NSCursor.frameResize(position: handle.cursorPosition, directions: .all).set()
        } else if let selection = editor.selection, selection.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    // MARK: Keyboard

    override var acceptsFirstResponder: Bool { true }

    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = KeyModifiers(event.modifierFlags)
        guard let command = OverlayCommand.match(characters: event.characters, keyCode: event.keyCode,
                                                 modifiers: modifiers) else {
            return super.performKeyEquivalent(with: event)
        }
        switch command {
        case .copy:
            perform(.copy)
        case .save:
            perform(.save)
        case .close:
            delegate?.overlay(self, perform: .close)
        case .toggleFullDisplay:
            guard !event.isARepeat else { return true }   // holding the keys must not flicker the toggle
            editor.toggleFullDisplay()
            delegate?.overlayDidBeginSelection(self)
            refresh()
        case .redact:
            guard selectionOwner != nil else { NSSound.beep(); return true }
            guard selectionOwner?.canvas.isDrawing != true else { return true }   // the shape keeps its tool
            drawing.tool = .redact
        case .undo:
            selectionOwner?.undo()
        case .redo:
            selectionOwner?.redo()
        case .widerStroke:
            changeStrokeWidth(by: 1)
        case .narrowerStroke:
            changeStrokeWidth(by: -1)
        case .paste:
            guard let editing = delegate?.overlayTextEditor(),
                  let text = NSPasteboard.general.string(forType: .string) else {
                return super.performKeyEquivalent(with: event)
            }
            editing.paste(text)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        // While a text box is being edited, keys type into it (FR-35); Esc arrives as cancelOperation.
        if isEditingText { return interpretKeyEvents([event]) }
        let modifiers = event.modifierFlags.intersection(Self.relevantModifiers)
        let step: CGFloat = event.isARepeat ? 2 : 1
        switch (event.keyCode, modifiers) {
        case (53, []):                                     // Esc (FR-27)
            handleEscape()
        case (36, []), (76, []):                           // Return / keypad Enter (OQ-3)
            if selectionOwner != nil { delegate?.overlay(self, perform: .copy) }
        case (123, []), (123, .shift): selectionOwner?.nudge(dx: -step, dy: 0, resize: modifiers == .shift)
        case (124, []), (124, .shift): selectionOwner?.nudge(dx: step, dy: 0, resize: modifiers == .shift)
        case (125, []), (125, .shift): selectionOwner?.nudge(dx: 0, dy: step, resize: modifiers == .shift)
        case (126, []), (126, .shift): selectionOwner?.nudge(dx: 0, dy: -step, resize: modifiers == .shift)
        default:
            super.keyDown(with: event)
        }
    }

    /// This view if it holds the selection, otherwise the display that does (FR-18).
    private var selectionOwner: OverlayView? {
        editor.selection != nil ? self : delegate?.overlaySelectionOwner()
    }

    /// Arrow keys end the active tool, then move or resize the selection (FR-24). Ignored while a
    /// shape is being drawn, which would otherwise finish as a tool that is no longer selected.
    private func nudge(dx: CGFloat, dy: CGFloat, resize: Bool) {
        guard !canvas.isDrawing else { return }
        drawing.tool = nil
        editor.nudge(dx: dx, dy: dy, resize: resize)
        refresh()
    }

    private func perform(_ action: OverlayAction) {
        guard selectionOwner != nil else { return NSSound.beep() }
        delegate?.overlay(self, perform: action)
    }
}

private extension KeyModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}

private extension Handle {
    var cursorPosition: NSCursor.FrameResizePosition {
        switch self {
        case .topLeft: .topLeft
        case .top: .top
        case .topRight: .topRight
        case .right: .right
        case .bottomRight: .bottomRight
        case .bottom: .bottom
        case .bottomLeft: .bottomLeft
        case .left: .left
        }
    }
}
