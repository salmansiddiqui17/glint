import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import GlintCore

struct TextLayoutTests {
    @Test func usesVerdanaWhenInstalled() {
        #expect(CTFontCopyFamilyName(TextLayout.font(size: 24)) as String == "Verdana")
    }

    @Test func oneLinePerLineBreak() {
        let one = TextLayout(text: "Hello", fontSize: 24)
        let three = TextLayout(text: "Hello\n\nWorld", fontSize: 24)
        #expect(one.size.height == one.lineHeight)
        #expect(three.size.height == 3 * one.lineHeight)
        #expect(one.size.width > 0)
        #expect(TextLayout(text: "", fontSize: 24).size == CGSize(width: 0, height: one.lineHeight))
    }

    @Test func lineHeightScalesWithFontSize() {
        let small = TextLayout(text: "a", fontSize: 12), big = TextLayout(text: "a", fontSize: 48)
        #expect(abs(big.lineHeight - 4 * small.lineHeight) < 0.01)
    }

    @Test func tabsAdvanceToTheNextStop() {
        let tabbed = TextLayout(text: "a\tb", fontSize: 24), plain = TextLayout(text: "ab", fontSize: 24)
        #expect(tabbed.size.width >= 48)          // stops every 2 × font size
        #expect(tabbed.size.width > plain.size.width)
        #expect(TextLayout(text: "\t\t", fontSize: 24).size.width == 96)
    }

    @Test func caretFollowsTheText() {
        let layout = TextLayout(text: "ab\ncd", fontSize: 24)
        #expect(layout.caretRect(at: 0).minX == 0)
        #expect(layout.caretRect(at: 1).minX > 0)
        #expect(layout.caretRect(at: 2).minX > layout.caretRect(at: 1).minX)
        #expect(layout.caretRect(at: 3) == CGRect(x: 0, y: layout.lineHeight, width: 0, height: layout.lineHeight))
    }

    @Test func pointsMapBackToOffsets() {
        let layout = TextLayout(text: "abc\ndef", fontSize: 24)
        #expect(layout.offset(at: CGPoint(x: -5, y: 2)) == 0)
        #expect(layout.offset(at: CGPoint(x: 999, y: 2)) == 3)
        #expect(layout.offset(at: CGPoint(x: -5, y: layout.lineHeight + 1)) == 4)
        #expect(layout.offset(at: CGPoint(x: 999, y: 999)) == 7)
        let middle = layout.caretRect(at: 1).minX
        #expect(layout.offset(at: CGPoint(x: middle + 1, y: 1)) == 1)
        let blank = TextLayout(text: "a\n\nb", fontSize: 24)
        #expect(blank.offset(at: CGPoint(x: 5, y: blank.lineHeight * 1.5)) == 2)   // the empty middle line
    }

    @Test func underlinesCoverOnlyTheRangeOnEachLine() {
        let layout = TextLayout(text: "abc\ndef", fontSize: 24)
        let lines = layout.underlines(for: NSRange(location: 1, length: 5))
        #expect(lines.count == 2)
        #expect(lines[0].minX == layout.caretRect(at: 1).minX && lines[0].minY > layout.ascent)
        #expect(lines[1].minX == 0 && lines[1].minY > layout.lineHeight)
        #expect(lines[0].maxY < layout.lineHeight)               // below the baseline, within its line
        #expect(layout.underlines(for: NSRange(location: 3, length: 0)).isEmpty)
    }

    @Test func underlinesCoverRightToLeftText() {
        let hebrew = TextLayout(text: "שלום", fontSize: 24)
        let line = hebrew.underlines(for: NSRange(location: 0, length: 4))
        #expect(line.count == 1 && abs(line[0].width - hebrew.size.width) < 1)
    }

    @Test func drawingRestoresTheTextMatrix() throws {
        let context = try #require(CGContext(data: nil, width: 50, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let matrix = CGAffineTransform(a: 2, b: 0, c: 0, d: 3, tx: 5, ty: 7)
        context.textMatrix = matrix
        TextLayout(text: "a", fontSize: 12).draw(in: context, at: .zero, color: .red)
        #expect(context.textMatrix == matrix)
    }

    @Test func bitmapCoversTheTextWithAPixelAlignedMargin() throws {
        let layout = TextLayout(text: "W", fontSize: 40)
        let (image, frame) = try #require(layout.image(scale: 2, color: .red))
        #expect(frame.minX == -10 && frame.minY == -10)          // a quarter of the font size
        #expect(frame.width >= layout.size.width + 20 && frame.height >= layout.size.height + 20)
        let small = try #require(TextLayout(text: "W", fontSize: 13).image(scale: 2, color: .red))
        #expect(small.frame.minX == -3.5 && small.frame.minY == -3.5)   // 3.25 pt, out to a whole pixel
        let row = Int((10 + layout.ascent) * 2) - 4              // just above the baseline, inside the W
        let ink = (0..<image.width).map { pixelColor(image, x: $0, y: row) }.filter { $0.alpha == 255 }
        #expect(!ink.isEmpty)
        #expect(ink.allSatisfy { $0.red > 200 && $0.blue < 50 })
        #expect(TextLayout(text: "", fontSize: 40).image(scale: 2, color: .red) == nil)
    }

    @Test func glyphsOverhangingTheLineBoxAreNotClipped() throws {
        let layout = TextLayout(text: "j", fontSize: 100)        // Verdana's j hooks left of its origin
        let (image, frame) = try #require(layout.image(scale: 1, color: .red))
        let originX = Int(-frame.minX)
        let leftOfOrigin = (0..<originX).flatMap { x in (0..<image.height).map { pixelColor(image, x: x, y: $0) } }
        #expect(leftOfOrigin.contains { $0.alpha > 0 })
    }

    @Test func inkBeyondTheMarginIsStillInTheBitmap() throws {
        let layout = TextLayout(text: "A\u{30A}\u{302}\u{302}\u{302}\u{302}", fontSize: 40)   // accents stacked high
        let (image, _) = try #require(layout.image(scale: 1, color: .red))
        let border = (0..<image.width).flatMap { [pixelColor(image, x: $0, y: 0), pixelColor(image, x: $0, y: image.height - 1)] }
            + (0..<image.height).flatMap { [pixelColor(image, x: 0, y: $0), pixelColor(image, x: image.width - 1, y: $0)] }
        #expect(border.allSatisfy { $0.alpha == 0 })               // nothing touches the edge
    }

    @Test func bitmapIsLimitedToWhatIsVisible() throws {
        let long = TextLayout(text: String(repeating: "x", count: 3000), fontSize: 24)   // far wider than a display
        let visible = CGRect(x: 0, y: 0, width: 500, height: 200)
        let (image, frame) = try #require(long.image(scale: 2, color: .red, visible: visible))
        #expect(visible.contains(frame))
        #expect(image.width == 1000 && CGFloat(image.height) == frame.height * 2)
        #expect(long.image(scale: 2, color: .red, visible: CGRect(x: 0, y: 500, width: 10, height: 10)) == nil)
    }

    @Test func aVisibleWindowOfALongTextMatchesTheWholeText() throws {
        // Only the lines near the window are measured and drawn; what shows must not change.
        let text = (0..<100).map { "line \($0) ÅÉ gjpqy" }.joined(separator: "\n")
        let layout = TextLayout(text: text, fontSize: 24)
        let visible = CGRect(x: 0, y: 40 * layout.lineHeight + 7, width: 300, height: 5 * layout.lineHeight)
        let (window, windowFrame) = try #require(layout.image(scale: 1, color: .red, visible: visible))
        let (whole, wholeFrame) = try #require(layout.image(scale: 1, color: .red))
        let dx = Int(windowFrame.minX - wholeFrame.minX), dy = Int(windowFrame.minY - wholeFrame.minY)
        let windowPixels = rgba(window), wholePixels = rgba(whole)
        var differing = 0
        for y in 0..<window.height {
            for x in 0..<window.width
            where windowPixels[(y * window.width + x) * 4 + 3] != wholePixels[((y + dy) * whole.width + x + dx) * 4 + 3] {
                differing += 1
            }
        }
        #expect(differing == 0)
    }

    /// The image's pixels as top-down RGBA bytes.
    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                    bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
