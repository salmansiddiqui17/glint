import CoreGraphics
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

    @Test func strengthIsAtLeastEightPixels() {
        #expect(Redaction.strength(strokeWidth: 1) == 8)
        #expect(Redaction.strength(strokeWidth: 3) == 12)
        #expect(Redaction.strength(strokeWidth: 10) == 40)
    }

    @Test func pixelateMakesFlatDistinctBlocksOnAGridFromTheTopLeft() throws {
        let (width, height) = (25, 17)                                 // partial blocks on the right and bottom
        let result = try #require(Redaction.obscure(gradient(width: width, height: height), style: .pixelate,
                                                    strength: 8))
        #expect(result.width == width && result.height == height)
        var blocks: [[RGBA8]] = []
        for blockY in stride(from: 0, to: height, by: 8) {
            var row: [RGBA8] = []
            for blockX in stride(from: 0, to: width, by: 8) {
                let reference = pixelColor(result, x: blockX, y: blockY)
                #expect(reference.alpha == 255)
                for x in blockX..<min(blockX + 8, width) {
                    for y in blockY..<min(blockY + 8, height) where pixelColor(result, x: x, y: y) != reference {
                        Issue.record("block at \(blockX),\(blockY) is not flat at \(x),\(y)")
                        return
                    }
                }
                row.append(reference)
            }
            blocks.append(row)
        }
        // Neighbouring blocks differ, across and down: the blocks really follow this grid.
        for (y, row) in blocks.enumerated() {
            for (x, block) in row.enumerated() {
                if x + 1 < row.count { #expect(block != row[x + 1]) }
                if y + 1 < blocks.count { #expect(block != blocks[y + 1][x]) }
            }
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
        let before = pixelColor(source, x: 8, y: 8), after = pixelColor(result, x: 8, y: 8)
        #expect(abs(before.red - after.red) <= 1 && abs(before.green - after.green) <= 1
                    && abs(before.blue - after.blue) <= 1)
    }

    @Test func deepSourcesStayDeep() throws {
        let extended = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
        let result = try #require(Redaction.obscure(flat([1, 0.5, 0.25, 1], in: extended, deep: true),
                                                    style: .pixelate, strength: 8))
        #expect(result.bitsPerComponent == 16)
        #expect(result.colorSpace?.name == CGColorSpace.extendedLinearDisplayP3)
    }
}
