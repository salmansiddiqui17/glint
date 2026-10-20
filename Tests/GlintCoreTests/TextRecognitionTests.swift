import CoreGraphics
import Testing
@testable import GlintCore

struct TextRecognitionTests {
    /// Black text on white, `fontSize` points at 2×, one string per line.
    func textImage(_ lines: [String], fontSize: CGFloat = 32) -> CGImage {
        let scale: CGFloat = 2
        let layout = TextLayout(text: lines.joined(separator: "\n"), fontSize: fontSize)
        let size = CGSize(width: layout.size.width + 40, height: layout.size.height + 40)
        let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        // Top-left-origin points, as the renderer draws annotations.
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: scale, y: -scale)
        layout.draw(in: context, at: CGPoint(x: 20, y: 20), color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1))
        return context.makeImage()!
    }

    @Test func recognisesLinesInReadingOrder() async throws {
        let text = try await TextRecognition.recognizeText(in: textImage(["Invoice number 4821", "Total due today"]))
        #expect(text == "Invoice number 4821\nTotal due today")
    }

    @Test func blankImageHasNoText() async throws {
        let blank = textImage([""])
        #expect(try await TextRecognition.recognizeText(in: blank) == "")
    }

    @Test func joinsLinesAndDropsBlankOnes() {
        #expect(TextRecognition.joinedLines(["a", "", "  ", "b c"]) == "a\nb c")
        #expect(TextRecognition.joinedLines([]) == "")
    }

    @Test func readsTextOfAnyHeight() {
        // Vision's default skips text under 1/32 of the image height: ordinary UI text in a
        // window-sized selection.
        #expect(TextRecognition.request().minimumTextHeightFraction == 0)
    }

    @Test func cancellingTheCallerStopsRecognition() async {
        let image = textImage(["Invoice number 4821"])
        let task = Task { try await TextRecognition.recognizeText(in: image) }
        task.cancel()
        await #expect(throws: (any Error).self) { try await task.value }
    }
}
