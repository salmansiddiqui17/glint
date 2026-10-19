import CoreGraphics
import Testing
@testable import GlintCore

struct RGBAColorTests {
    @Test func defaultIsPureRed() {
        #expect(RGBAColor.red == RGBAColor(red: 1, green: 0, blue: 0, alpha: 1))
    }

    @Test func greyscaleColoursBecomeRGB() throws {
        let grey = try #require(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2)!,
                                        components: [0.5, 0.4]))
        let color = try #require(RGBAColor(grey))
        #expect(abs(color.red - color.green) < 0.01 && abs(color.green - color.blue) < 0.01)
        #expect(color.red > 0.3 && color.red < 0.7)
        #expect(abs(color.alpha - 0.4) < 0.001)
    }

    @Test func otherRGBSpacesAreConverted() throws {
        let p3Red = try #require(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                                         components: [1, 0, 0, 1]))
        let clipped = try #require(RGBAColor(p3Red))
        #expect(clipped.red > 0.99 && clipped.green < 0.01)   // P3 red is outside sRGB; it is clipped, not lost
        let genericRed = try #require(RGBAColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)))
        #expect(genericRed.green > 0.1)                      // generic RGB red really is converted
    }

    @Test func sRGBColoursRoundTrip() throws {
        let color = RGBAColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let back = try #require(RGBAColor(color.cgColor))
        #expect(abs(back.red - 0.2) < 1e-6 && abs(back.green - 0.4) < 1e-6 && abs(back.blue - 0.6) < 1e-6)
        #expect(abs(back.alpha - 0.8) < 1e-6)
    }

    @Test func componentsRoundTripAndAreClamped() {
        let color = RGBAColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)
        #expect(RGBAColor(components: color.components) == color)
        #expect(RGBAColor(components: [2, -1, 0.5, 1]) == RGBAColor(red: 1, green: 0, blue: 0.5, alpha: 1))
        #expect(RGBAColor(components: [1, 0, 0]) == nil)
        #expect(RGBAColor(components: [.nan, 0, 0, 1])?.red == 0)
    }

    @Test func withAlphaKeepsTheColour() {
        #expect(RGBAColor.red.withAlpha(0.3) == RGBAColor(red: 1, green: 0, blue: 0, alpha: 0.3))
    }
}

struct DrawingLimitsTests {
    @Test func strokeWidthStepsAndClamps() {
        #expect(DrawingLimits.strokeWidth(3, steppedBy: 1) == 4)
        #expect(DrawingLimits.strokeWidth(3, steppedBy: -1) == 3)
        #expect(DrawingLimits.strokeWidth(50, steppedBy: 1) == 50)
        #expect(DrawingLimits.strokeWidth(500, steppedBy: 0) == 50)
        #expect(DrawingLimits.strokeWidth(.nan, steppedBy: 0) == 3)
        #expect(DrawingLimits.strokeWidth(3.6, steppedBy: 0) == 4)        // whole points
    }

    @Test func fontSizeStepsAndClamps() {
        #expect(DrawingLimits.fontSize(24, steppedBy: 2) == 26)
        #expect(DrawingLimits.fontSize(10, steppedBy: -1) == 10)
        #expect(DrawingLimits.fontSize(250, steppedBy: 1) == 250)
        #expect(DrawingLimits.fontSize(0, steppedBy: 0) == 10)
        #expect(DrawingLimits.fontSize(.infinity, steppedBy: 0) == 24)   // non-finite: the default, not a bound
    }

    @Test func styleDefaultsMatchTheSpec() {
        let style = DrawingStyle()
        #expect(style.color == .red && style.strokeWidth == 3 && style.fontSize == 24 && style.redactionStyle == .pixelate)
        #expect(DrawingStyle(strokeWidth: 99, fontSize: 1).strokeWidth == 50)
        #expect(DrawingStyle(strokeWidth: 99, fontSize: 1).fontSize == 10)
    }

    @Test func styleWidthsStayInRangeWhenSet() {
        var style = DrawingStyle()
        style.strokeWidth = 99
        style.fontSize = .nan
        #expect(style.strokeWidth == 50 && style.fontSize == 24)
        style.strokeWidth = 7.4
        #expect(style.strokeWidth == 7)
    }

    @Test func brushPreviewIsForStrokingTools() {
        #expect(Tool.allCases.filter(\.showsBrushPreview) == [.pencil, .line, .arrow, .ellipse, .rectangle, .marker])
    }

    @Test func paletteOrderMatchesTheSpec() {
        #expect(Tool.allCases == [.pencil, .line, .arrow, .ellipse, .rectangle, .marker, .text, .redact])
    }
}

struct AnnotationDocumentTests {
    let a = Annotation.line(from: .zero, to: CGPoint(x: 10, y: 0), color: .red, width: 3)
    let b = Annotation.rectangle(CGRect(x: 0, y: 0, width: 5, height: 5), color: .red, width: 3)
    let c = Annotation.ellipse(CGRect(x: 0, y: 0, width: 5, height: 5), color: .red, width: 3)

    @Test func startsEmpty() {
        let document = AnnotationDocument()
        #expect(document.annotations.isEmpty && !document.canUndo && !document.canRedo)
    }

    @Test func undoAndRedoOneAnnotationAtATime() {
        var document = AnnotationDocument()
        document.add(a)
        document.add(b)
        let undid = document.undo()
        #expect(undid && document.annotations == [a])
        #expect(document.canRedo)
        let redid = document.redo()
        #expect(redid && document.annotations == [a, b])
        let redidAgain = document.redo()
        #expect(!redidAgain)
    }

    @Test func redoRestoresInReverseOrderOfUndo() {
        var document = AnnotationDocument()
        document.add(a)
        document.add(b)
        document.add(c)
        document.undo()
        document.undo()
        document.redo()
        #expect(document.annotations == [a, b])
        document.redo()
        #expect(document.annotations == [a, b, c])
    }

    @Test func drawingClearsRedo() {
        var document = AnnotationDocument()
        document.add(a)
        document.add(b)
        document.undo()
        document.add(c)
        #expect(!document.canRedo)
        #expect(document.annotations == [a, c])
    }

    @Test func undoOnEmptyDoesNothing() {
        var document = AnnotationDocument()
        let undid = document.undo()
        #expect(!undid && document.annotations.isEmpty)
    }
}
