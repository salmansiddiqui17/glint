import Foundation
import Testing
@testable import GlintCore

extension Trait where Self == ConditionTrait {
    /// For tests that run Vision's text recognizer. GitHub's macOS runners are virtual machines,
    /// and there Vision fails every request with `.unknownError`, so these tests are skipped when
    /// the environment says CI *and* Vision can't read the warm-up image. They never skip locally,
    /// and a recognizer that runs but reads wrongly still fails them.
    static var requiresTextRecognition: Self {
        .enabled("Vision text recognition is unavailable on this CI runner") {
            guard ProcessInfo.processInfo.environment["CI"] == "true" else { return true }
            return await TextRecognitionProbe.recognizes.value
        }
    }
}

/// Whether Vision can recognise text here at all, probed once per test run.
enum TextRecognitionProbe {
    /// Detached so that the probe belongs to no test: its failure is only the answer.
    static let recognizes = Task.detached {
        guard let image = TextRecognition.warmUpImage() else { return true }   // let the tests fail instead
        return (try? await TextRecognition.recognizeText(in: image)) != nil
    }
}
