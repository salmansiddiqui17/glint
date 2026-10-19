import CoreGraphics
import Testing
@testable import GlintCore

struct AnnotationCanvasTests {
    let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let style = DrawingStyle(color: RGBAColor(red: 0, green: 0, blue: 1), strokeWidth: 4, fontSize: 30)

    func canvas() -> AnnotationCanvas { AnnotationCanvas(bounds: display, scale: 2) }

    func drag(_ c: inout AnnotationCanvas, _ tool: Tool, from a: CGPoint, to b: CGPoint, shift: Bool = false) {
        c.mouseDown(at: a, tool: tool, style: style, constrained: shift)
        c.mouseDragged(to: b, constrained: shift)
        c.mouseUp(at: b, constrained: shift)
    }

    // MARK: Shapes

    @Test func dragAddsOneAnnotationAndOneUndoStep() {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 10, y: 10), tool: .rectangle, style: style, constrained: false)
        #expect(c.isDrawing)
        c.mouseDragged(to: CGPoint(x: 60, y: 40), constrained: false)
        #expect(c.draft?.annotation != nil)
        #expect(c.document.annotations.isEmpty)
        c.mouseUp(at: CGPoint(x: 60, y: 40), constrained: false)
        #expect(!c.isDrawing && c.draft == nil)
        #expect(c.document.annotations == [.rectangle(CGRect(x: 10, y: 10, width: 50, height: 30),
                                                      color: style.color, width: 4)])
        c.undo()
        #expect(c.document.annotations.isEmpty && c.document.canRedo)
    }

    @Test func tooSmallShapeAddsNothing() {
        var c = canvas()
        drag(&c, .ellipse, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 10.5, y: 50))
        #expect(c.document.annotations.isEmpty && !c.canUndo)
    }

    @Test func pointsAreClampedToTheDisplay() {
        var c = canvas()
        drag(&c, .line, from: CGPoint(x: 990, y: 10), to: CGPoint(x: 1500, y: -40))
        #expect(c.document.annotations == [.line(from: CGPoint(x: 990, y: 10), to: CGPoint(x: 1000, y: 0),
                                                 color: style.color, width: 4)])
    }

    @Test func shiftHeldAtThePressConstrainsAndReleasingItFreesTheShape() {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 100), tool: .rectangle, style: style, constrained: true)
        c.mouseDragged(to: CGPoint(x: 150, y: 120), constrained: true)
        #expect(c.draft?.annotation == .rectangle(CGRect(x: 100, y: 100, width: 50, height: 50),
                                                  color: style.color, width: 4))
        c.setConstrained(false)
        #expect(c.draft?.annotation == .rectangle(CGRect(x: 100, y: 100, width: 50, height: 20),
                                                  color: style.color, width: 4))
    }

    @Test func escapeMidDragDropsTheShapeAndKeepsDrawing() {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 10, y: 10), tool: .rectangle, style: style, constrained: false)
        c.mouseDragged(to: CGPoint(x: 80, y: 60), constrained: false)
        c.cancelGesture()
        #expect(c.draft == nil && !c.isDrawing && c.document.annotations.isEmpty)
        c.mouseUp(at: CGPoint(x: 80, y: 60), constrained: false)     // the release that follows adds nothing
        #expect(c.document.annotations.isEmpty)
    }

    // MARK: Text (FR-35)

    @Test func textClickPlacesABoxOnWholePixels() {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100.3, y: 50.2), tool: .text, style: style, constrained: false)
        c.mouseUp(at: CGPoint(x: 100.3, y: 50.2), constrained: false)
        #expect(c.textBox?.origin == CGPoint(x: 100.5, y: 50))
        #expect(c.textBox?.fontSize == 30 && c.textBox?.color == style.color)
        #expect(c.document.annotations.isEmpty)
    }

    @Test func committingAddsTheTextAtExactlyItsEditingPosition() {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.mouseUp(at: CGPoint(x: 100, y: 50), constrained: false)
        c.editText { $0.insert("Hi") }
        c.commitText()
        #expect(c.textBox == nil)
        #expect(c.document.annotations == [.text(TextAnnotation(origin: CGPoint(x: 100, y: 50), string: "Hi",
                                                                fontSize: 30, color: style.color))])
    }

    @Test func emptyBoxIsDiscardedWithoutAnUndoStep() {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.commitText()
        #expect(c.textBox == nil && c.document.annotations.isEmpty && !c.canUndo)
    }

    @Test func clickingOutsideCommitsAndStartsANewBox() {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.mouseUp(at: CGPoint(x: 100, y: 50), constrained: false)
        c.editText { $0.insert("one") }
        c.mouseDown(at: CGPoint(x: 400, y: 300), tool: .text, style: style, constrained: false)
        c.mouseUp(at: CGPoint(x: 400, y: 300), constrained: false)
        #expect(c.document.annotations.count == 1)
        #expect(c.textBox?.origin == CGPoint(x: 400, y: 300) && c.textBox?.text == "")
    }

    @Test func draggingTheBoxMovesItBeforeCommit() throws {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.mouseUp(at: CGPoint(x: 100, y: 50), constrained: false)
        c.editText { $0.insert("drag me") }
        let frame = try #require(c.textBoxFrame)
        c.mouseDown(at: CGPoint(x: frame.midX, y: frame.midY), tool: .text, style: style, constrained: false)
        #expect(!c.isMovingText)
        c.mouseDragged(to: CGPoint(x: frame.midX + 40, y: frame.midY + 20), constrained: false)
        #expect(c.isMovingText && c.isDrawing)
        c.mouseUp(at: CGPoint(x: frame.midX + 40, y: frame.midY + 20), constrained: false)
        #expect(c.textBox?.origin == CGPoint(x: 140, y: 70) && c.textBox?.text == "drag me")
        #expect(c.document.annotations.isEmpty)
    }

    @Test func escapeMidDragPutsTheTextBoxBack() throws {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.editText { $0.insert("stay") }
        let frame = try #require(c.textBoxFrame)
        c.mouseDown(at: CGPoint(x: frame.midX, y: frame.midY), tool: .text, style: style, constrained: false)
        c.mouseDragged(to: CGPoint(x: frame.midX + 50, y: frame.midY), constrained: false)
        c.cancelGesture()
        #expect(c.textBox?.origin == CGPoint(x: 100, y: 50) && c.textBox?.text == "stay" && !c.isDrawing)
    }

    @Test func clickingInsideTheBoxMovesTheCaret() throws {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.editText { $0.insert("abcdef") }
        let frame = try #require(c.textBoxFrame)
        c.mouseDown(at: CGPoint(x: frame.minX + 1, y: frame.midY), tool: .text, style: style, constrained: false)
        c.mouseUp(at: CGPoint(x: frame.minX + 1, y: frame.midY), constrained: false)
        #expect(c.textBox?.caret == 0 && c.textBox?.origin == CGPoint(x: 100, y: 50))
    }

    @Test func emptyBoxStillHasAFrameToGrab() throws {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        let frame = try #require(c.textBoxFrame)
        #expect(frame.width > 0 && frame.height > 0 && frame.origin == CGPoint(x: 100, y: 50))
    }

    @Test func drawingAShapeCommitsPendingText() {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.editText { $0.insert("note") }
        drag(&c, .pencil, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 20, y: 20))
        #expect(c.textBox == nil && c.document.annotations.count == 2)
        guard case .text? = c.document.annotations.first else { Issue.record("the text should come first"); return }
    }

    @Test func aPressWhoseReleaseWasLostLeavesNothingBehind() {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 10, y: 10), tool: .rectangle, style: style, constrained: false)
        c.mouseDragged(to: CGPoint(x: 200, y: 200), constrained: false)       // no mouse-up arrives
        c.mouseDown(at: CGPoint(x: 300, y: 300), tool: .text, style: style, constrained: false)
        c.mouseUp(at: CGPoint(x: 300, y: 300), constrained: false)
        #expect(c.document.annotations.isEmpty && c.draft == nil && !c.isDrawing && c.textBox != nil)
    }

    @Test func theCaretGoesWhereTheClickPressedNotWhereItWasReleased() throws {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.editText { $0.insert("abcdef\nghijkl") }
        let frame = try #require(c.textBoxFrame)
        let lineHeight = frame.height / 2
        c.mouseDown(at: CGPoint(x: frame.minX + 1, y: frame.minY + lineHeight - 1), tool: .text, style: style,
                    constrained: false)
        c.mouseUp(at: CGPoint(x: frame.minX + 1, y: frame.minY + lineHeight + 1.5), constrained: false)   // 2.5 pt
        #expect(c.textBox?.caret == 0 && c.textBox?.origin == frame.origin)
        c.mouseDown(at: CGPoint(x: frame.minX + 1, y: frame.minY + lineHeight * 1.5), tool: .text, style: style,
                    constrained: false)
        c.mouseUp(at: CGPoint(x: frame.minX + 1, y: frame.minY + lineHeight * 1.5), constrained: false)
        #expect(c.textBox?.caret == 7)                                        // start of the second line
    }

    @Test func textBoxesStayOnTheDisplay() throws {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 1000, y: 800), tool: .text, style: style, constrained: false)
        let placed = try #require(c.textBoxFrame)
        #expect(display.contains(placed))
        c.editText { $0.insert("near the corner") }
        let frame = try #require(c.textBoxFrame)
        c.mouseDown(at: CGPoint(x: frame.midX, y: frame.midY), tool: .text, style: style, constrained: false)
        c.mouseDragged(to: CGPoint(x: frame.midX + 500, y: frame.midY + 500), constrained: false)
        c.mouseUp(at: CGPoint(x: frame.midX + 500, y: frame.midY + 500), constrained: false)
        #expect(display.contains(try #require(c.textBoxFrame)))
    }

    @Test func aDraggedBoxLandsOnWholePixels() throws {
        var c = canvas()                                                      // scale 2
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.editText { $0.insert("move") }
        let frame = try #require(c.textBoxFrame)
        c.mouseDown(at: CGPoint(x: frame.midX, y: frame.midY), tool: .text, style: style, constrained: false)
        c.mouseUp(at: CGPoint(x: frame.midX + 40.3, y: frame.midY + 20.2), constrained: false)
        #expect(c.textBox?.origin == CGPoint(x: 140.5, y: 70))
    }

    @Test func fontSizeIsKeptInRange() {
        var c = canvas()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.editText { $0.fontSize = 900 }
        #expect(c.textBox?.fontSize == 250)
    }

    // MARK: Undo with pending text (FR-39)

    @Test func undoCommitsPendingTextThenUndoesIt() {
        var c = canvas()
        drag(&c, .line, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10))
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.editText { $0.insert("typo") }
        #expect(c.canUndo)
        c.undo()
        #expect(c.textBox == nil && c.document.annotations.count == 1)
        c.redo()
        #expect(c.document.annotations.count == 2)
    }

    @Test func redoIsUnavailableWhileTypingText() {
        var c = canvas()
        drag(&c, .line, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10))
        c.undo()
        #expect(c.canRedo)
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        #expect(c.canRedo)                       // an empty box would be discarded
        c.editText { $0.insert("x") }
        #expect(!c.canRedo)                      // committing it will clear the redo history
    }

    @Test func redoCommitsPendingTextFirst() {
        var c = canvas()
        drag(&c, .line, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 10))
        c.undo()
        c.mouseDown(at: CGPoint(x: 100, y: 50), tool: .text, style: style, constrained: false)
        c.editText { $0.insert("x") }
        let redid = c.redo()                     // the text is committed, which clears the redo history
        #expect(!redid && c.textBox == nil && c.document.annotations.count == 1 && !c.canRedo)
    }
}

struct EscapeActionTests {
    @Test func escapeGoesThroughTheStagesInOrder() {
        #expect(EscapeAction.resolve(isEditingText: true, isToolActive: true) == .commitText)
        #expect(EscapeAction.resolve(isEditingText: false, isToolActive: true) == .deselectTool)
        #expect(EscapeAction.resolve(isEditingText: false, isToolActive: false) == .cancelCapture)
    }
}

struct ScrollStepperTests {
    @Test func wheelGivesOneStepPerNotch() {
        var stepper = ScrollStepper()
        #expect(stepper.steps(for: 1, precise: false) == 1)
        #expect(stepper.steps(for: 4.5, precise: false) == 1)
        #expect(stepper.steps(for: -0.1, precise: false) == -1)
        #expect(stepper.steps(for: 0, precise: false) == 0)
    }

    @Test func trackpadAccumulatesPoints() {
        var stepper = ScrollStepper()
        #expect(stepper.steps(for: 5, precise: true) == 0)
        #expect(stepper.steps(for: 5, precise: true) == 0)
        #expect(stepper.steps(for: 5, precise: true) == 1)
        #expect(stepper.steps(for: 30, precise: true) == 2)
    }

    @Test func changingDirectionStartsAfresh() {
        var stepper = ScrollStepper()
        #expect(stepper.steps(for: 10, precise: true) == 0)
        #expect(stepper.steps(for: -10, precise: true) == 0)
        #expect(stepper.steps(for: -2, precise: true) == -1)
    }

    @Test func downwardScrollingAccumulatesToo() {
        var stepper = ScrollStepper()
        #expect(stepper.steps(for: -30, precise: true) == -2)
        #expect(stepper.steps(for: -6, precise: true) == -1)          // 6 pt were left over
    }

    @Test func aWheelNotchDropsTrackpadLeftovers() {
        var stepper = ScrollStepper()
        #expect(stepper.steps(for: 10, precise: true) == 0)
        #expect(stepper.steps(for: 1, precise: false) == 1)
        #expect(stepper.steps(for: 5, precise: true) == 0)            // not 15
    }
}
