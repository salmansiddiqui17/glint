import CoreGraphics
import Testing
@testable import GlintCore

struct HandleTests {
    let selection = CGRect(x: 100, y: 100, width: 200, height: 100)
    let tiny = CGRect(x: 0, y: 0, width: 4, height: 4)

    @Test func centresSitOnTheBorder() {
        #expect(Handle.topLeft.center(in: selection) == CGPoint(x: 100, y: 100))
        #expect(Handle.top.center(in: selection) == CGPoint(x: 200, y: 100))
        #expect(Handle.topRight.center(in: selection) == CGPoint(x: 300, y: 100))
        #expect(Handle.right.center(in: selection) == CGPoint(x: 300, y: 150))
        #expect(Handle.bottomRight.center(in: selection) == CGPoint(x: 300, y: 200))
        #expect(Handle.bottom.center(in: selection) == CGPoint(x: 200, y: 200))
        #expect(Handle.bottomLeft.center(in: selection) == CGPoint(x: 100, y: 200))
        #expect(Handle.left.center(in: selection) == CGPoint(x: 100, y: 150))
    }

    @Test func visibleSquareIsSixPointsCentredOnHandle() {
        #expect(Handle.bottomRight.visibleFrame(in: selection) == CGRect(x: 297, y: 197, width: 6, height: 6))
        #expect(Handle.top.visibleFrame(in: selection) == CGRect(x: 197, y: 97, width: 6, height: 6))
    }

    @Test func hitAreaIsTwelvePoints() {
        #expect(Handle.hit(CGPoint(x: 105.9, y: 94.1), selection: selection) == .topLeft)
        #expect(Handle.hit(CGPoint(x: 106.1, y: 100), selection: selection) == nil)
        #expect(Handle.hit(CGPoint(x: 200, y: 203), selection: selection) == .bottom)
    }

    @Test(arguments: [Handle.topLeft, .topRight, .bottomRight, .bottomLeft])
    func eachCornerIsHitAtItsOwnCentreOnTinySelections(corner: Handle) {
        #expect(Handle.hit(corner.center(in: tiny), selection: tiny) == corner)
    }

    @Test func cornersWinOverNearerEdges() {
        // (1.5, 0.5) is nearer the top edge's centre (2, 0) than the top-left corner (0, 0),
        // but it lies inside top-left's hit square, and corners win.
        #expect(Handle.hit(CGPoint(x: 1.5, y: 0.5), selection: tiny) == .topLeft)
    }

    @Test(arguments: Handle.allCases)
    func clickWithoutMovementChangesNothing(handle: Handle) {
        let centre = handle.center(in: selection)
        let grab = CGPoint(x: centre.x + 4, y: centre.y - 3)
        #expect(handle.resize(selection, grabbedAt: grab, to: grab) == selection)
    }

    @Test func edgeHandlesResizeOneAxis() {
        let right = Handle.right.center(in: selection)
        #expect(Handle.right.resize(selection, grabbedAt: right, to: CGPoint(x: 400, y: 999)) ==
            CGRect(x: 100, y: 100, width: 300, height: 100))
        let top = Handle.top.center(in: selection)
        #expect(Handle.top.resize(selection, grabbedAt: top, to: CGPoint(x: -50, y: 50)) ==
            CGRect(x: 100, y: 50, width: 200, height: 150))
    }

    @Test func grabOffsetIsPreserved() {
        // Grabbed 4 pt right of the right handle's centre; moving 10 pt right moves the edge 10 pt.
        #expect(Handle.right.resize(selection, grabbedAt: CGPoint(x: 304, y: 150), to: CGPoint(x: 314, y: 150)) ==
            CGRect(x: 100, y: 100, width: 210, height: 100))
    }

    @Test func draggingPastOppositeEdgeFlips() {
        let topLeft = Handle.topLeft.center(in: selection)
        #expect(Handle.topLeft.resize(selection, grabbedAt: topLeft, to: CGPoint(x: 350, y: 250)) ==
            CGRect(x: 300, y: 200, width: 50, height: 50))
        let left = Handle.left.center(in: selection)
        #expect(Handle.left.resize(selection, grabbedAt: left, to: CGPoint(x: 320, y: 150)) ==
            CGRect(x: 300, y: 100, width: 20, height: 100))
    }
}
