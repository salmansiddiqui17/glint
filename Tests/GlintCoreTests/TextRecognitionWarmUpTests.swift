import Foundation
import Testing
@testable import GlintCore

struct TextRecognitionWarmUpTests {
    let built = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func warmUpImageReadsAsItsText() async throws {
        let image = try #require(TextRecognition.warmUpImage())
        #expect(try await TextRecognition.recognizeText(in: image) == TextRecognition.warmUpText)
    }

    @Test func warmUpRunsVision() async throws {
        try await TextRecognition.warmUp()
    }

    @Test func warmsUpUntilThisBuildHasBeen() {
        #expect(TextRecognitionWarmUp.isNeeded(warmedUpBuild: nil, currentBuild: "a"))
        #expect(TextRecognitionWarmUp.isNeeded(warmedUpBuild: "a", currentBuild: "b"))
        #expect(!TextRecognitionWarmUp.isNeeded(warmedUpBuild: "a", currentBuild: "a"))
    }

    @Test func warmsUpEveryLaunchWhenTheBuildIsUnknown() {
        #expect(TextRecognitionWarmUp.isNeeded(warmedUpBuild: nil, currentBuild: nil))
        #expect(TextRecognitionWarmUp.isNeeded(warmedUpBuild: "a", currentBuild: nil))
    }

    @Test func buildKeyIsStableForOneBinary() {
        #expect(TextRecognitionWarmUp.buildKey(version: "0.1.0", build: "1", executableModified: built)
            == TextRecognitionWarmUp.buildKey(version: "0.1.0", build: "1", executableModified: built))
    }

    /// Local builds all say 0.1.0 (1), so the executable's date tells them apart (OQ-18).
    @Test func buildKeyChangesWithEveryBuiltBinary() {
        let key = TextRecognitionWarmUp.buildKey(version: "0.1.0", build: "1", executableModified: built)
        #expect(key != TextRecognitionWarmUp.buildKey(version: "0.1.0", build: "1",
                                                      executableModified: built.addingTimeInterval(1)))
        #expect(key != TextRecognitionWarmUp.buildKey(version: "0.1.1", build: "1", executableModified: built))
        #expect(key != TextRecognitionWarmUp.buildKey(version: "0.1.0", build: "2", executableModified: built))
    }

    @Test func noBuildKeyWithoutTheExecutablesDate() {
        #expect(TextRecognitionWarmUp.buildKey(version: "0.1.0", build: "1", executableModified: nil) == nil)
    }
}
