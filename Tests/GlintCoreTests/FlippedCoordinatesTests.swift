import CoreGraphics
import Testing
@testable import GlintCore

struct FlippedCoordinatesTests {
    let flip = FlippedCoordinates(height: 800)

    @Test func flipsPoints() {
        #expect(flip.point(CGPoint(x: 10, y: 0)) == CGPoint(x: 10, y: 800))
        #expect(flip.point(CGPoint(x: 10, y: 300)) == CGPoint(x: 10, y: 500))
    }

    @Test func flipsRectsByTheirFarEdge() {
        #expect(flip.rect(CGRect(x: 10, y: 20, width: 30, height: 40)) == CGRect(x: 10, y: 740, width: 30, height: 40))
    }

    @Test func negativeSizesCoverTheSameArea() {
        #expect(flip.rect(CGRect(x: 40, y: 60, width: -30, height: -40)) == CGRect(x: 10, y: 740, width: 30, height: 40))
    }

    @Test func isItsOwnInverse() {
        let rect = CGRect(x: 1.5, y: 2.25, width: 30, height: 40.5)
        #expect(flip.rect(flip.rect(rect)) == rect)
        #expect(flip.point(flip.point(CGPoint(x: 3, y: 4))) == CGPoint(x: 3, y: 4))
    }
}
