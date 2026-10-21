import CoreGraphics
import Testing
@testable import GlintCore

struct AnnotationDraftTests {
    let display = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let style = DrawingStyle(color: RGBAColor(red: 0, green: 0, blue: 1), strokeWidth: 5)

    func draft(_ tool: Tool, from start: CGPoint = CGPoint(x: 100, y: 100), scale: CGFloat = 2,
               strokeWidth: CGFloat? = nil) -> AnnotationDraft {
        var style = style
        if let strokeWidth { style.strokeWidth = strokeWidth }
        return AnnotationDraft(tool: tool, start: start, style: style, bounds: display, scale: scale)
    }

    /// The redaction a drag from `start` to `end` makes at stroke width `width` (scale 2).
    func redaction(from start: CGPoint, to end: CGPoint, width: CGFloat = 3, constrained: Bool = false) -> CGRect? {
        var d = draft(.redact, from: start, strokeWidth: width)
        d.drag(to: end, constrained: constrained)
        guard case let .redaction(rect, _, _)? = d.annotation else { return nil }
        return rect
    }

    @Test func pencilCollectsThePathWithTheStyle() {
        var d = draft(.pencil)
        d.drag(to: CGPoint(x: 110, y: 100), constrained: false)
        d.drag(to: CGPoint(x: 110, y: 100), constrained: false)   // repeated positions are dropped
        d.drag(to: CGPoint(x: 120, y: 105), constrained: true)    // ⇧ does not affect the pencil
        #expect(d.annotation == .pencil(points: [CGPoint(x: 100, y: 100), CGPoint(x: 110, y: 100),
                                                 CGPoint(x: 120, y: 105)], color: style.color, width: 5))
    }

    @Test func pencilSkipsSubPixelMovesButEndsAtThePointer() {
        var d = draft(.pencil)                                     // scale 2: one pixel is 0.5 pt
        d.drag(to: CGPoint(x: 100.2, y: 100), constrained: false)
        d.drag(to: CGPoint(x: 100.4, y: 100), constrained: false)
        d.drag(to: CGPoint(x: 101, y: 100), constrained: false)
        d.drag(to: CGPoint(x: 101.3, y: 100), constrained: false)
        #expect(d.annotation == .pencil(points: [CGPoint(x: 100, y: 100), CGPoint(x: 101, y: 100),
                                                 CGPoint(x: 101.3, y: 100)], color: style.color, width: 5))
    }

    @Test func pencilClickIsADot() {
        #expect(draft(.pencil).annotation == .pencil(points: [CGPoint(x: 100, y: 100)], color: style.color, width: 5))
        #expect(draft(.marker).annotation == .marker(points: [CGPoint(x: 100, y: 100)], color: style.color, width: 5))
    }

    @Test func lineGoesFromPressToPointer() {
        var d = draft(.line)
        d.drag(to: CGPoint(x: 300, y: 150), constrained: false)
        #expect(d.annotation == .line(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 150),
                                      color: style.color, width: 5))
    }

    @Test func shiftSnapsArrowsTo45DegreesLive() throws {
        var d = draft(.arrow)
        d.drag(to: CGPoint(x: 190, y: 170), constrained: true)
        guard case let .arrow(from, to, _, _)? = d.annotation else { Issue.record("not an arrow"); return }
        #expect(to.x - from.x == to.y - from.y)
        d.setConstrained(false)                                   // ⇧ released mid-drag
        guard case let .arrow(_, free, _, _)? = d.annotation else { Issue.record("not an arrow"); return }
        #expect(free == CGPoint(x: 190, y: 170))
    }

    @Test func tooShortLinesAndBoxesDrawNothing() {
        #expect(draft(.line).annotation == nil)
        #expect(draft(.arrow).annotation == nil)
        var flat = draft(.rectangle)
        flat.drag(to: CGPoint(x: 200, y: 100.5), constrained: false)
        #expect(flat.annotation == nil)
        #expect(draft(.ellipse).annotation == nil)
        #expect(draft(.redact).annotation == nil)
    }

    @Test func boxesNormaliseAndSquareWithShift() {
        var d = draft(.rectangle)
        d.drag(to: CGPoint(x: 40, y: 70), constrained: false)
        #expect(d.annotation == .rectangle(CGRect(x: 40, y: 70, width: 60, height: 30), color: style.color, width: 5))
        d.setConstrained(true)
        #expect(d.annotation == .rectangle(CGRect(x: 40, y: 40, width: 60, height: 60), color: style.color, width: 5))
        var e = draft(.ellipse)
        e.drag(to: CGPoint(x: 130, y: 200), constrained: true)
        #expect(e.annotation == .ellipse(CGRect(x: 100, y: 100, width: 100, height: 100), color: style.color, width: 5))
    }

    @Test func redactionSnapsToPixelsStaysOnTheDisplayAndRecordsStyle() {
        var d = draft(.redact, from: CGPoint(x: 900.3, y: 700.2))
        d.drag(to: CGPoint(x: 1100, y: 900), constrained: true)   // square runs off the display
        #expect(d.annotation == .redaction(CGRect(x: 900.5, y: 700, width: 99.5, height: 99.5),
                                           style: .pixelate, width: 5))     // still square on pixels
        var free = draft(.redact, from: CGPoint(x: 10.3, y: 20.2))
        free.drag(to: CGPoint(x: 60.6, y: 55.9), constrained: false)       // taller than the 30 pt band
        #expect(free.annotation == .redaction(CGRect(x: 10.5, y: 20, width: 50, height: 36),
                                              style: .pixelate, width: 5))
    }

    // MARK: Sweeping Redact along a line (OQ-20)

    @Test func aSidewaysSweepBecomesABandCentredOnTheDrag() {
        // 6 × 3 = 18 pt, centred on y 200.5: 191.5 to 209.5, already whole pixels at 2×.
        #expect(redaction(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 201))
                == CGRect(x: 100, y: 191.5, width: 200, height: 18))
        #expect(redaction(from: CGPoint(x: 300, y: 201), to: CGPoint(x: 100, y: 200))   // right to left
                == CGRect(x: 100, y: 191.5, width: 200, height: 18))
    }

    @Test func aVerticalSweepBecomesABandAcross() {
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 101, y: 300))
                == CGRect(x: 91.5, y: 100, width: 18, height: 200))
        #expect(redaction(from: CGPoint(x: 101, y: 300), to: CGPoint(x: 100, y: 100))   // bottom to top
                == CGRect(x: 91.5, y: 100, width: 18, height: 200))
    }

    @Test func theBandFollowsTheStrokeWidth() {
        #expect(redaction(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 200), width: 10)
                == CGRect(x: 100, y: 170, width: 200, height: 60))
    }

    @Test func aBoxAtLeastTheBandEachWayIsUnchanged() {
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 200))
                == CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200), width: 10)   // 60 pt band
                == CGRect(x: 100, y: 100, width: 100, height: 100))
    }

    @Test func eachSideThinnerThanTheBandBecomesTheBand() {
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 110))
                == CGRect(x: 96, y: 96, width: 18, height: 18))
    }

    @Test func nearTheDiagonalTheBandDoesNotFlip() {
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 111))
                == CGRect(x: 96, y: 96.5, width: 18, height: 18))
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 111, y: 110))
                == CGRect(x: 96.5, y: 96, width: 18, height: 18))
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 290), width: 50)   // 300 pt band
                == CGRect(x: 50, y: 45, width: 300, height: 300))
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 290, y: 300), width: 50)
                == CGRect(x: 45, y: 50, width: 300, height: 300))
    }

    @Test func aMoveWithinTheDragThresholdAddsNothing() {
        #expect(SelectionEditor.dragThreshold == 3)
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 103, y: 100)) == nil)
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 102)) == nil)   // 2.8 pt away
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 102), constrained: true) == nil)
        #expect(redaction(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 97))           // 3.6 pt away
                == CGRect(x: 92, y: 89.5, width: 18, height: 18))
    }

    @Test func aBandAtTheDisplayEdgeIsShiftedInsideNotCut() {
        #expect(redaction(from: CGPoint(x: 100, y: 4), to: CGPoint(x: 300, y: 5))
                == CGRect(x: 100, y: 0, width: 200, height: 18))
        #expect(redaction(from: CGPoint(x: 100, y: 800), to: CGPoint(x: 300, y: 799))
                == CGRect(x: 100, y: 782, width: 200, height: 18))
        #expect(redaction(from: CGPoint(x: 999, y: 100), to: CGPoint(x: 1000, y: 300))
                == CGRect(x: 982, y: 100, width: 18, height: 200))
    }

    @Test func aBandThickerThanTheDisplayCoversIt() {
        var d = AnnotationDraft(tool: .redact, start: CGPoint(x: 10, y: 5), style: DrawingStyle(strokeWidth: 50),
                                bounds: CGRect(x: 0, y: 0, width: 400, height: 200), scale: 2)
        d.drag(to: CGPoint(x: 390, y: 5), constrained: false)                // a 300 pt band on a 200 pt display
        #expect(d.annotation == .redaction(CGRect(x: 10, y: 0, width: 380, height: 200), style: .pixelate, width: 50))
    }

    @Test func shiftStillMakesASquareRedaction() {
        #expect(redaction(from: CGPoint(x: 100, y: 200), to: CGPoint(x: 300, y: 201), constrained: true)
                == CGRect(x: 100, y: 200, width: 200, height: 200))
    }

    @Test func otherToolsDoNotSweepABand() {
        let from = CGPoint(x: 100, y: 200), to = CGPoint(x: 300, y: 201)
        var pencil = draft(.pencil, from: from, strokeWidth: 3)
        pencil.drag(to: to, constrained: false)
        #expect(pencil.annotation == .pencil(points: [from, to], color: style.color, width: 3))
        var rectangle = draft(.rectangle, from: from, strokeWidth: 3)
        rectangle.drag(to: to, constrained: false)
        #expect(rectangle.annotation == .rectangle(CGRect(x: 100, y: 200, width: 200, height: 1),
                                                   color: style.color, width: 3))
        var ellipse = draft(.ellipse, from: from, strokeWidth: 3)
        ellipse.drag(to: CGPoint(x: 300, y: 200.5), constrained: false)
        #expect(ellipse.annotation == nil)
    }

    @Test func redactionAtOneXCoversTheDisplayCorner() {
        var d = draft(.redact, from: CGPoint(x: 950, y: 750), scale: 1)
        d.drag(to: CGPoint(x: 1000, y: 800), constrained: false)
        #expect(d.annotation == .redaction(CGRect(x: 950, y: 750, width: 50, height: 50), style: .pixelate, width: 5))
    }

    @Test func shiftSquareAlongTheRightOrBottomEdgeOpensInwards() {
        var right = draft(.rectangle, from: CGPoint(x: 1000, y: 100))
        right.drag(to: CGPoint(x: 1000, y: 300), constrained: true)
        #expect(right.annotation == .rectangle(CGRect(x: 800, y: 100, width: 200, height: 200),
                                               color: style.color, width: 5))
        var bottom = draft(.redact, from: CGPoint(x: 100, y: 800))
        bottom.drag(to: CGPoint(x: 160, y: 800), constrained: true)
        #expect(bottom.annotation == .redaction(CGRect(x: 100, y: 740, width: 60, height: 60),
                                                style: .pixelate, width: 5))
    }

    @Test func constrainedEndsStayOnTheDisplayWithoutLosingTheirShape() {
        var line = draft(.arrow, from: CGPoint(x: 900, y: 100))
        line.drag(to: CGPoint(x: 1000, y: 140), constrained: true)       // snaps to 0°, which runs past x = 1000
        guard case let .arrow(_, end, _, _)? = line.annotation else { Issue.record("not an arrow"); return }
        #expect(end == CGPoint(x: 1000, y: 100))
        var diagonal = draft(.line, from: CGPoint(x: 950, y: 100))
        diagonal.drag(to: CGPoint(x: 1000, y: 160), constrained: true)
        guard case let .line(_, tip, _, _)? = diagonal.annotation else { Issue.record("not a line"); return }
        #expect(tip.x <= 1000 && abs((tip.x - 950) - (tip.y - 100)) < 1e-9)
        var square = draft(.rectangle, from: CGPoint(x: 980, y: 700))
        square.drag(to: CGPoint(x: 1000, y: 790), constrained: true)     // a 90 pt square won't fit
        guard case let .rectangle(rect, _, _)? = square.annotation else { Issue.record("not a rectangle"); return }
        #expect(rect == CGRect(x: 980, y: 700, width: 20, height: 20))
        var leftTop = draft(.ellipse, from: CGPoint(x: 30, y: 50))
        leftTop.drag(to: CGPoint(x: 0, y: 0), constrained: true)          // a 50 pt square would cross x = 0
        #expect(leftTop.annotation == .ellipse(CGRect(x: 0, y: 20, width: 30, height: 30),
                                               color: style.color, width: 5))
        var up = draft(.arrow, from: CGPoint(x: 500, y: 20))
        up.drag(to: CGPoint(x: 498, y: 0), constrained: true)              // snaps straight up, 0.1 pt past y = 0
        guard case let .arrow(_, top, _, _)? = up.annotation else { Issue.record("not an arrow"); return }
        #expect(top == CGPoint(x: 500, y: 0))
    }

    @Test func aConstrainedLineWithNoRoomLeftDrawsNothing() {
        var d = draft(.line, from: CGPoint(x: 1000, y: 400))
        d.drag(to: CGPoint(x: 1003, y: 400.4), constrained: true)          // snaps to 0°, straight off the edge
        #expect(d.annotation == nil)
        d.setConstrained(false)
        #expect(d.annotation != nil)
    }
}
