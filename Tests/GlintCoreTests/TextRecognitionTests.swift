import CoreGraphics
import Testing
@testable import GlintCore

struct TextRecognitionTests {
    /// Black text on white, `fontSize` points at `scale`, one string per line.
    func textImage(_ lines: [String], fontSize: CGFloat = 32, scale: CGFloat = 2) -> CGImage {
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

    /// "Redacted areas are never read" (FR-46): large text stays legible through the lightest
    /// pixelate, so recognition must see the redaction as a solid block instead.
    @Test func redactedTextIsNeverRead() async throws {
        let fontSize: CGFloat = 96
        let image = textImage(["Password hunter2"], fontSize: fontSize)   // at 2×
        let size = CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
        let secretStart = 20 + TextLayout(text: "Password ", fontSize: fontSize).size.width
        let secret = CGRect(x: secretStart - 4, y: 0, width: size.width - secretStart + 4, height: size.height)
        let rendered = try #require(Renderer.renderSelectionForTextRecognition(
            image, scale: 2, annotations: [.redaction(secret, style: .pixelate, width: 3)],
            selection: CGRect(origin: .zero, size: size), standardResolution: false))
        let text = try await TextRecognition.recognizeText(in: rendered)
        #expect(text.contains("Password"))   // the rest is still read
        #expect(!text.contains("hunter2"))
    }

    /// The export hides text of any size under a redaction (FR-36 AC1, OQ-19): with a fixed
    /// strength, 96 pt text at 2× was read word for word through both styles. The redaction is
    /// drawn tightly round the secret's line, the smallest box a user would draw.
    /// (font size, scale, standard resolution)
    @Test(arguments: [RedactionStyle.pixelate, .blur],
          [(CGFloat(48), CGFloat(2), false), (96, 2, false), (160, 2, false), (300, 2, false), (96, 1, false),
           (96, 2, true)])
    func exportedRedactionsHideTextOfAnySize(style: RedactionStyle,
                                             text: (fontSize: CGFloat, scale: CGFloat, standard: Bool)) async throws {
        let (fontSize, scale) = (text.fontSize, text.scale)
        let image = textImage(["Password hunter2"], fontSize: fontSize, scale: scale)
        let size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        let line = TextLayout(text: "Password hunter2", fontSize: fontSize).size
        let secretStart = 20 + TextLayout(text: "Password ", fontSize: fontSize).size.width
        let secret = CGRect(x: secretStart - 4, y: 20, width: line.width - secretStart + 28, height: line.height)
        let exported = try #require(Renderer.renderSelection(
            image, scale: scale, annotations: [.redaction(secret, style: style, width: 3)],
            selection: CGRect(origin: .zero, size: size), standardResolution: text.standard))
        let read = try await TextRecognition.recognizeText(in: exported).lowercased()
        #expect(read.contains("password"))   // the rest is still read, so recognition did run
        let secretWord = Array("hunter2")
        for start in 0...(secretWord.count - 4) {
            let fragment = String(secretWord[start..<start + 4])   // every longer fragment contains one
            #expect(!read.contains(fragment), "read \"\(fragment)\" under the redaction: \(read)")
        }
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
