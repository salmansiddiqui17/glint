import CoreGraphics
import Foundation
import Testing
@testable import GlintCore

struct RedactionTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Every pixel a different colour: red = 8·x, green = 8·y (from the top-left corner).
    func gradient(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        for x in 0..<width {
            for y in 0..<height {
                context.setFillColor(CGColor(colorSpace: sRGB, components: [CGFloat(8 * x) / 255,
                                                                             CGFloat(8 * y) / 255, 0.5, 1])!)
                context.fill(CGRect(x: x, y: height - 1 - y, width: 1, height: 1))   // CG is bottom-left
            }
        }
        return context.makeImage()!
    }

    /// Vertical one-pixel stripes: black and white alternating columns.
    func stripes(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: sRGB, components: [1, 1, 1, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(colorSpace: sRGB, components: [0, 0, 0, 1])!)
        for x in stride(from: 0, to: width, by: 2) { context.fill(CGRect(x: x, y: 0, width: 1, height: height)) }
        return context.makeImage()!
    }

    func flat(_ components: [CGFloat], in space: CGColorSpace, size: Int = 16, deep: Bool = false) -> CGImage {
        let bitmapInfo = deep
            ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
                | CGImageByteOrderInfo.order16Little.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: deep ? 16 : 8, bytesPerRow: 0,
                                space: space, bitmapInfo: bitmapInfo)!
        context.setFillColor(CGColor(colorSpace: space, components: components)!)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return context.makeImage()!
    }

    /// A redaction over a line of 13 pt UI text keeps max(8, 4·w).
    @Test func smallRedactionsKeepTheStrokeWidthsStrength() {
        let line = CGRect(x: 30, y: 40, width: 300, height: 20)        // 40 px tall at 2×
        #expect(Redaction.strength(strokeWidth: 1, frame: line, scale: 2) == 8)
        #expect(Redaction.strength(strokeWidth: 3, frame: line, scale: 2) == 12)
        #expect(Redaction.strength(strokeWidth: 10, frame: line, scale: 2) == 40)
        #expect(Redaction.strength(strokeWidth: 3, frame: line, scale: 1) == 12)
    }

    /// Larger redactions grow with their shorter side in pixels, so text of any size beneath them
    /// can't be read (FR-36, OQ-19). At 1× and 2× they hide the same share of the content.
    @Test func largeRedactionsGrowWithTheirShorterSide() {
        let wide = CGRect(x: 0, y: 0, width: 600, height: 250), tall = CGRect(x: 0, y: 0, width: 250, height: 900)
        #expect(Redaction.strength(strokeWidth: 3, frame: wide, scale: 2) == 100)
        #expect(Redaction.strength(strokeWidth: 3, frame: tall, scale: 2) == 100)
        #expect(Redaction.strength(strokeWidth: 3, frame: wide, scale: 1) == 50)
        #expect(Redaction.strength(strokeWidth: 50, frame: wide, scale: 1) == 200)   // a wide stroke still wins
    }

    /// The patch is made and drawn with whole pixels (`blockSize`), however the frame falls.
    @Test func strengthIsAlwaysWholePixels() {
        for height in stride(from: CGFloat(0.5), through: 400, by: 0.5) {
            for scale in [CGFloat(1), 2, 3] {
                let strength = Redaction.strength(strokeWidth: 3, frame: CGRect(x: 0, y: 0, width: 500, height: height),
                                                  scale: scale)
                if strength != strength.rounded() {
                    Issue.record("\(height) pt at \(scale)× is strength \(strength)")
                    return
                }
            }
        }
    }

    @Test func pixelateKeepsOnePixelPerBlockOnAGridFromTheTopLeft() throws {
        let (width, height) = (25, 17)                                 // partial blocks on the right and bottom
        let source = gradient(width: width, height: height)
        let result = try #require(Redaction.obscure(source, style: .pixelate, strength: 8))
        #expect(result.width == 4 && result.height == 3)               // NFR-6: 1/64 of the pixels
        // Each block's pixel is what a full-size pixellate shows across that whole block.
        let reference = try #require(fullSizePixellate(source, strength: 8))
        for x in 0..<width {
            for y in 0..<height where pixelColor(reference, x: x, y: y) != pixelColor(result, x: x / 8, y: y / 8) {
                Issue.record("pixel \(x),\(y) differs from its block")
                return
            }
        }
        // Neighbouring blocks differ, across and down: the blocks really follow this grid.
        for x in 0..<4 {
            for y in 0..<3 {
                #expect(pixelColor(result, x: x, y: y).alpha == 255)
                if x < 3 { #expect(pixelColor(result, x: x, y: y) != pixelColor(result, x: x + 1, y: y)) }
                if y < 2 { #expect(pixelColor(result, x: x, y: y) != pixelColor(result, x: x, y: y + 1)) }
            }
        }
    }

    @Test func blockRectCoversWholeBlocksFromTheFrameCorner() throws {
        let frame = CGRect(x: 10, y: 20, width: 12.5, height: 8.5)    // 25 × 17 px at 2×
        let compact = try #require(Redaction.obscure(gradient(width: 25, height: 17), style: .pixelate, strength: 8))
        #expect(Redaction.blockRect(for: compact, frame: frame, scale: 2, strength: 8)
            == CGRect(x: 10, y: 20, width: 16, height: 12))            // 4 × 3 blocks of 8 px
        let blurred = try #require(Redaction.obscure(gradient(width: 25, height: 17), style: .blur, strength: 8))
        #expect(Redaction.blockRect(for: blurred, frame: frame, scale: 2, strength: 8) == frame)
    }

    /// Stroke widths are whole points today, but a fractional strength must not leave an
    /// unredacted strip along the right and bottom edges: the patch and where it is drawn use the
    /// same whole-pixel block (FR-36).
    @Test(arguments: [CGFloat(8.4), 8.5, 8.6, 12.6])
    func aFractionalStrengthStillCoversTheWholeFrame(strength: CGFloat) throws {
        let frame = CGRect(x: 10, y: 20, width: 39, height: 38)       // 39 × 38 px at 1×
        let source = gradient(width: 39, height: 38)
        for patch in [try #require(Redaction.obscure(source, style: .pixelate, strength: strength)),
                      try #require(Redaction.solid(source, style: .pixelate, strength: strength))] {
            let drawn = Redaction.blockRect(for: patch, frame: frame, scale: 1, strength: strength)
            #expect(drawn.contains(frame), "\(drawn) leaves part of \(frame) uncovered")
        }
    }

    @Test func blurRemovesTheStripesAndStaysOpaque() throws {
        let result = try #require(Redaction.obscure(stripes(width: 40, height: 40), style: .blur, strength: 8))
        #expect(result.width == 40 && result.height == 40)
        let a = pixelColor(result, x: 20, y: 20), b = pixelColor(result, x: 21, y: 20)
        #expect(abs(a.red - b.red) < 20)                 // neighbouring stripes now look alike
        #expect(pixelColor(result, x: 0, y: 0).alpha == 255)
        #expect(pixelColor(result, x: 39, y: 39).alpha == 255)
    }

    @Test(arguments: [RedactionStyle.pixelate, .blur])
    func keepsTheColourSpaceAndTheColours(style: RedactionStyle) throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let source = flat([0.2, 0.6, 0.4, 1], in: p3)
        let result = try #require(Redaction.obscure(source, style: style, strength: 8))
        #expect(result.colorSpace?.name == CGColorSpace.displayP3)
        let before = pixelColor(source, x: 8, y: 8)
        let after = pixelColor(result, x: result.width / 2, y: result.height / 2)
        #expect(abs(before.red - after.red) <= 1 && abs(before.green - after.green) <= 1
                    && abs(before.blue - after.blue) <= 1)
    }

    /// Pixels that aren't a whole number of bytes can't be copied byte by byte: no image rather
    /// than a garbled one. The copy's own CGImage(…) returns nil for these formats too, so this pins
    /// the outcome, not the guard. (bits per component, bits per pixel, components)
    @Test(arguments: [(4, 4, 1), (12, 12, 1), (3, 9, 3), (4, 12, 3), (5, 15, 3), (10, 30, 3)])
    func onePixelPerBlockFailsClosedOnPixelsThatArentWholeBytes(format: (Int, Int, Int)) throws {
        let (bitsPerComponent, bitsPerPixel, components) = format
        let (size, bytesPerRow) = (24, (24 * bitsPerPixel + 7) / 8)
        let provider = try #require(CGDataProvider(data: Data(repeating: 0x5A, count: bytesPerRow * size) as CFData))
        let space = components == 1 ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
        let image = try #require(CGImage(width: size, height: size, bitsPerComponent: bitsPerComponent,
                                         bitsPerPixel: bitsPerPixel, bytesPerRow: bytesPerRow, space: space,
                                         bitmapInfo: [], provider: provider, decode: nil, shouldInterpolate: false,
                                         intent: .defaultIntent))
        #expect(Redaction.onePixelPerBlock(image, block: 8) == nil)
    }

    @Test func deepSourcesStayDeep() throws {
        let extended = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        let result = try #require(Redaction.obscure(flat([1, 0.5, 0.25, 1], in: extended, deep: true),
                                                    style: .pixelate, strength: 8))
        #expect(result.bitsPerComponent == 16)
        #expect(result.colorSpace?.name == CGColorSpace.extendedLinearDisplayP3)
    }
}
