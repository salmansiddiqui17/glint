import CoreGraphics
import Vision

/// On-device text recognition for Copy Text (FR-46): Vision in accurate mode, with automatic
/// language detection and language correction. Nothing leaves the Mac.
public enum TextRecognition {
    /// The text in `image`, one recognised line per line in Vision's reading order, or an empty
    /// string when there is none. Throws if Vision fails or the task is cancelled.
    public static func recognizeText(in image: CGImage) async throws -> String {
        let observations = try await request().perform(on: image)
        try Task.checkCancellation()
        return joinedLines(observations.compactMap { $0.topCandidates(1).first?.string })
    }

    /// The Vision request Copy Text uses.
    static func request() -> RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        // The default skips text under 1/32 of the image height, which drops ordinary UI text
        // in a window-sized selection.
        request.minimumTextHeightFraction = 0
        return request
    }

    /// `lines` separated by line breaks, leaving out lines that are empty or only whitespace.
    static func joinedLines(_ lines: [String]) -> String {
        lines.filter { !$0.allSatisfy(\.isWhitespace) }.joined(separator: "\n")
    }
}
