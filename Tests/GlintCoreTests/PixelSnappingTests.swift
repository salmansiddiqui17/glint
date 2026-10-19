import CoreGraphics
import Testing
@testable import GlintCore

struct PixelSnappingTests {
    @Test func roundsEdgesToDevicePixels() {
        #expect(PixelSnapping.aligned(CGRect(x: 10.3, y: 20.6, width: 5.2, height: 4.1), scale: 1)
            == CGRect(x: 10, y: 21, width: 6, height: 4))
        #expect(PixelSnapping.aligned(CGRect(x: 10.3, y: 20.6, width: 5.2, height: 4.1), scale: 2)
            == CGRect(x: 10.5, y: 20.5, width: 5, height: 4))
    }

    @Test(arguments: [CGFloat(1), 2, 3])
    func agreesWithTheExportedPixelRect(scale: CGFloat) {
        // Includes exact half-pixel ties, where rounding direction matters.
        let selection = CGRect(x: 10.25, y: 7.75, width: 33.5, height: 20.25)
        let drawn = PixelSnapping.aligned(selection, scale: scale)
        let exported = OutputGeometry.pixelRect(for: selection, scale: scale,
                                                imageSize: PixelSize(width: 10_000, height: 10_000))
        let drawnInPixels = [drawn.minX, drawn.minY, drawn.maxX, drawn.maxY].map { $0 * scale }
        let exportedEdges = [exported.minX, exported.minY, exported.maxX, exported.maxY]
        for (drawnEdge, exportedEdge) in zip(drawnInPixels, exportedEdges) {
            #expect(abs(drawnEdge - exportedEdge) < 1e-9)
        }
    }

    @Test func veilBandsSurroundTheHoleExactly() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        let hole = CGRect(x: 20, y: 10, width: 30, height: 40)
        let bands = PixelSnapping.veilBands(around: hole, in: bounds)
        #expect(bands == [
            CGRect(x: 0, y: 0, width: 100, height: 10),
            CGRect(x: 0, y: 50, width: 100, height: 30),
            CGRect(x: 0, y: 10, width: 20, height: 40),
            CGRect(x: 50, y: 10, width: 50, height: 40),
        ])
        let covered = bands.reduce(0) { $0 + $1.width * $1.height } + hole.width * hole.height
        #expect(covered == bounds.width * bounds.height)
    }

    @Test func noHoleVeilsEverything() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 80)
        #expect(PixelSnapping.veilBands(around: nil, in: bounds) == [bounds, .zero, .zero, .zero])
    }
}
