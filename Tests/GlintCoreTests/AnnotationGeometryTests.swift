import CoreGraphics
import Testing
@testable import GlintCore

struct ShapeConstraintTests {
    let start = CGPoint(x: 100, y: 100)

    @Test func diagonalSnapsTo45Degrees() {
        let end = ShapeConstraint.angleSnapped(from: start, to: CGPoint(x: 190, y: 170))
        #expect(end.x - start.x == end.y - start.y)
        #expect(abs(hypot(end.x - start.x, end.y - start.y) - hypot(90, 70)) < 1e-9)   // keeps the length
        let uneven = CGPoint(x: 100.5, y: 37.25)
        let other = ShapeConstraint.angleSnapped(from: uneven, to: CGPoint(x: 190.5, y: 107.25))
        #expect(abs((other.x - uneven.x) - (other.y - uneven.y)) < 1e-9)
    }

    @Test func nearlyFlatSnapsToHorizontalAndVertical() {
        let horizontal = ShapeConstraint.angleSnapped(from: start, to: CGPoint(x: 200, y: 110))
        #expect(horizontal.y == 100 && abs(horizontal.x - (100 + hypot(100, 10))) < 1e-9)
        let vertical = ShapeConstraint.angleSnapped(from: start, to: CGPoint(x: 95, y: 20))
        #expect(vertical.x == 100 && abs(vertical.y - (100 - hypot(5, 80))) < 1e-9)
    }

    @Test(arguments: [(CGFloat(-80), CGFloat(-70)), (-80, 70), (80, -70)])
    func snapsInEveryQuadrant(dx: CGFloat, dy: CGFloat) {
        let end = ShapeConstraint.angleSnapped(from: start, to: CGPoint(x: start.x + dx, y: start.y + dy))
        #expect(abs(end.x - start.x) == abs(end.y - start.y))
        #expect((end.x - start.x).sign == dx.sign && (end.y - start.y).sign == dy.sign)
    }

    @Test func zeroLengthStaysPut() {
        #expect(ShapeConstraint.angleSnapped(from: start, to: start) == start)
    }

    @Test func squareUsesTheLargerDistanceAndKeepsDirection() {
        #expect(ShapeConstraint.squared(from: start, to: CGPoint(x: 160, y: 120)) == CGPoint(x: 160, y: 160))
        #expect(ShapeConstraint.squared(from: start, to: CGPoint(x: 90, y: 20)) == CGPoint(x: 20, y: 20))
    }
}

struct ArrowGeometryTests {
    @Test func headAndShaftFollowTheSpecFormulas() throws {
        let width: CGFloat = 5
        let arrow = try #require(ArrowGeometry(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 0), width: width))
        let headLength = 4 * width + 15                      // 35
        let halfBase = headLength * tan(CGFloat.pi / 16)     // 11.25° half-angle
        #expect(arrow.head[0] == CGPoint(x: 200, y: 0))
        #expect(abs(arrow.head[1].x - (200 - headLength)) < 1e-9 && abs(abs(arrow.head[1].y) - halfBase) < 1e-9)
        #expect(abs(arrow.head[2].x - (200 - headLength)) < 1e-9 && abs(arrow.head[1].y + arrow.head[2].y) < 1e-9)
        let shaft = try #require(arrow.shaft)
        #expect(shaft.start == .zero)
        #expect(abs(shaft.end.x - (200 - (3 * width + 15))) < 1e-9 && shaft.end.y == 0)
    }

    @Test func headIsSymmetricAcrossADiagonalShaft() throws {
        let from = CGPoint(x: 0, y: 0), tip = CGPoint(x: 100, y: 100), width: CGFloat = 3
        let arrow = try #require(ArrowGeometry(from: from, to: tip, width: width))
        let headLength = 4 * width + 15
        let unit = CGPoint(x: (0.5 as CGFloat).squareRoot(), y: (0.5 as CGFloat).squareRoot())
        let back = CGPoint(x: arrow.head[1].x - arrow.head[2].x, y: arrow.head[1].y - arrow.head[2].y)
        let middle = CGPoint(x: (arrow.head[1].x + arrow.head[2].x) / 2, y: (arrow.head[1].y + arrow.head[2].y) / 2)
        #expect(abs(back.x * unit.x + back.y * unit.y) < 1e-9)                        // the base is across the shaft
        #expect(abs(hypot(back.x, back.y) - 2 * headLength * tan(CGFloat.pi / 16)) < 1e-9)
        #expect(abs(middle.x - (tip.x - unit.x * headLength)) < 1e-9)                // centred on the shaft line
        #expect(abs(middle.y - (tip.y - unit.y * headLength)) < 1e-9)
    }

    @Test func anArrowAsLongAsItsHeadHasAShaftInsideTheHead() throws {
        let width: CGFloat = 50
        let headLength = 4 * width + 15
        let arrow = try #require(ArrowGeometry(from: .zero, to: CGPoint(x: headLength, y: 0), width: width))
        let shaft = try #require(arrow.shaft)
        // Where the shaft (and its round cap) ends, the head is wider than half the stroke.
        let capEnd = shaft.end.x + width / 2
        #expect((headLength - capEnd) * tan(CGFloat.pi / 16) > width / 2)
    }

    @Test func shortArrowHasNoShaft() throws {
        let arrow = try #require(ArrowGeometry(from: .zero, to: CGPoint(x: 0, y: 20), width: 3))   // head is 27 pt
        #expect(arrow.shaft == nil)
        #expect(arrow.head[0] == CGPoint(x: 0, y: 20))
    }

    @Test func zeroLengthHasNoGeometry() {
        #expect(ArrowGeometry(from: .zero, to: .zero, width: 3) == nil)
    }
}

struct AnnotationGeometryTests {
    @Test func penStrokesHaveRoundCapsAndJoins() throws {
        let shape = try #require(AnnotationGeometry.shape(for: .pencil(points: [.zero, CGPoint(x: 5, y: 5)],
                                                                       color: .red, width: 4)))
        #expect(shape.stroke != nil && shape.fill == nil)
        #expect(shape.lineCap == .round && shape.lineJoin == .round && shape.lineWidth == 4)
    }

    @Test func aClickIsADotAsWideAsTheStroke() throws {
        let shape = try #require(AnnotationGeometry.shape(for: .pencil(points: [CGPoint(x: 10, y: 10)],
                                                                       color: .red, width: 6)))
        #expect(shape.stroke == nil)
        #expect(shape.fill?.boundingBox == CGRect(x: 7, y: 7, width: 6, height: 6))
    }

    @Test func markerIs30PercentOfTheColoursOpacity() throws {
        let shape = try #require(AnnotationGeometry.shape(for: .marker(points: [.zero, CGPoint(x: 9, y: 0)],
                                                                       color: .red, width: 10)))
        #expect(abs(shape.color.alpha - 0.3) < 1e-9)
        #expect(shape.color.red == 1)
        let faint = try #require(AnnotationGeometry.shape(for: .marker(points: [.zero, CGPoint(x: 9, y: 0)],
                                                                       color: .red.withAlpha(0.5), width: 10)))
        #expect(abs(faint.color.alpha - 0.15) < 1e-9)
    }

    @Test func lineHasRoundCaps() throws {
        let shape = try #require(AnnotationGeometry.shape(for: .line(from: .zero, to: CGPoint(x: 40, y: 0),
                                                                     color: .red, width: 5)))
        #expect(shape.lineCap == .round && shape.fill == nil && shape.lineWidth == 5)
        #expect(shape.stroke?.boundingBox == CGRect(x: 0, y: 0, width: 40, height: 0))
    }

    @Test func rectangleHasSharpCorners() throws {
        let rect = CGRect(x: 10, y: 10, width: 50, height: 30)
        let shape = try #require(AnnotationGeometry.shape(for: .rectangle(rect, color: .red, width: 3)))
        #expect(shape.lineJoin == .miter)
        #expect(shape.stroke?.boundingBox == rect)
    }

    @Test func ellipseIsInscribedInItsBox() throws {
        let rect = CGRect(x: 10, y: 10, width: 50, height: 30)
        let shape = try #require(AnnotationGeometry.shape(for: .ellipse(rect, color: .red, width: 3)))
        #expect(shape.stroke?.boundingBox == rect)
        #expect(shape.fill == nil)
        #expect(shape.stroke?.contains(CGPoint(x: rect.minX + 1, y: rect.minY + 1)) == false)   // not a rectangle
        #expect(shape.stroke?.contains(CGPoint(x: rect.midX, y: rect.midY)) == true)
    }

    @Test func arrowFillsItsHeadAndStrokesItsShaft() throws {
        let shape = try #require(AnnotationGeometry.shape(for: .arrow(from: .zero, to: CGPoint(x: 100, y: 0),
                                                                      color: .red, width: 3)))
        #expect(shape.fill != nil && shape.stroke != nil)
        let short = try #require(AnnotationGeometry.shape(for: .arrow(from: .zero, to: CGPoint(x: 10, y: 0),
                                                                      color: .red, width: 3)))
        #expect(short.stroke == nil && short.fill != nil)
    }

    @Test func textAndRedactionAreNotVectorShapes() {
        #expect(AnnotationGeometry.shape(for: .redaction(CGRect(x: 0, y: 0, width: 9, height: 9), style: .blur,
                                                         width: 3)) == nil)
        #expect(AnnotationGeometry.shape(for: .text(TextAnnotation(origin: .zero, string: "a", fontSize: 24,
                                                                   color: .red))) == nil)
    }
}
