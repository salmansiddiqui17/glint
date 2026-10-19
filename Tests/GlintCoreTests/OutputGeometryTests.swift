import CoreGraphics
import Testing
@testable import GlintCore

struct OutputGeometryTests {
    let selection = CGRect(x: 10, y: 20, width: 300, height: 200)
    let bigImage = PixelSize(width: 10_000, height: 10_000)

    @Test(arguments: [
        (CGFloat(2), false, PixelSize(width: 600, height: 400)),
        (CGFloat(2), true, PixelSize(width: 300, height: 200)),
        (CGFloat(3), false, PixelSize(width: 900, height: 600)),
        (CGFloat(3), true, PixelSize(width: 300, height: 200)),
        (CGFloat(1), false, PixelSize(width: 300, height: 200)),
        (CGFloat(1), true, PixelSize(width: 300, height: 200)),
    ])
    func outputSize(scale: CGFloat, standard: Bool, expected: PixelSize) {
        #expect(OutputGeometry.outputPixelSize(for: selection, scale: scale, imageSize: bigImage,
                                               standardResolution: standard) == expected)
    }

    @Test func pixelRectRoundsEachEdge() {
        let rect = OutputGeometry.pixelRect(for: CGRect(x: 0.3, y: 0.2, width: 10.4, height: 10.4), scale: 2,
                                            imageSize: bigImage)
        #expect(rect == CGRect(x: 1, y: 0, width: 20, height: 21))
    }

    @Test func pixelRectIsClippedToTheImage() {
        let image = PixelSize(width: 200, height: 100)            // a 100 × 50 pt display at 2×
        let rect = OutputGeometry.pixelRect(for: CGRect(x: 90, y: 40, width: 20.4, height: 20), scale: 2, imageSize: image)
        #expect(rect == CGRect(x: 180, y: 80, width: 20, height: 20))
        #expect(OutputGeometry.outputPixelSize(for: CGRect(x: 90, y: 40, width: 20.4, height: 20), scale: 2,
                                               imageSize: image, standardResolution: false)
            == PixelSize(width: 20, height: 20))
    }

    @Test func oddPixelWidthRoundsAtStandardResolution() {
        let size = OutputGeometry.outputPixelSize(for: CGRect(x: 0, y: 0, width: 300.5, height: 10), scale: 2,
                                                  imageSize: bigImage, standardResolution: true)
        #expect(size == PixelSize(width: 301, height: 10))      // 601 px / 2 = 300.5 → 301
    }

    @Test func fractionalScale() {
        let rect = OutputGeometry.pixelRect(for: CGRect(x: 1, y: 1, width: 3, height: 3), scale: 1.5, imageSize: bigImage)
        #expect(rect == CGRect(x: 2, y: 2, width: 4, height: 4))   // edges 1.5→2 and 6
        #expect(OutputGeometry.dpi(scale: 1.5, standardResolution: false) == 108)
    }

    @Test(arguments: [false, true])
    func degenerateSelectionsAreZeroInBothModes(standard: Bool) {
        #expect(OutputGeometry.outputPixelSize(for: .zero, scale: 2, imageSize: bigImage,
                                               standardResolution: standard) == PixelSize(width: 0, height: 0))
        #expect(OutputGeometry.outputPixelSize(for: CGRect(x: 5, y: 5, width: 0, height: 40), scale: 2,
                                               imageSize: bigImage, standardResolution: standard).width == 0)
    }

    @Test func badgeTextUsesMultiplicationSign() {
        #expect(OutputGeometry.badgeText(PixelSize(width: 600, height: 400)) == "600 × 400")
    }

    @Test func dpiFollowsScale() {
        #expect(OutputGeometry.dpi(scale: 1, standardResolution: false) == 72)
        #expect(OutputGeometry.dpi(scale: 2, standardResolution: false) == 144)
        #expect(OutputGeometry.dpi(scale: 3, standardResolution: false) == 216)
        #expect(OutputGeometry.dpi(scale: 2, standardResolution: true) == 72)
    }
}
