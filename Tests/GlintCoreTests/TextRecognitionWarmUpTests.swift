import Foundation
import Testing
@testable import GlintCore

struct TextRecognitionWarmUpTests {
    let built = Date(timeIntervalSince1970: 1_800_000_000)
    let macOS = "Version 26.1 (Build 25B78)"

    func key(version: String = "0.1.0", build: String = "1", modified: Date?, macOS: String) -> String? {
        TextRecognitionWarmUp.buildKey(version: version, build: build, executableModified: modified,
                                       operatingSystem: macOS)
    }

    @Test func warmUpImageReadsAsItsText() async throws {
        let image = try #require(TextRecognition.warmUpImage())
        #expect(try await TextRecognition.recognizeText(in: image) == TextRecognition.warmUpText)
    }

    @Test func warmsUpUntilThisBuildHasBeen() {
        #expect(TextRecognitionWarmUp.isNeeded(isEnabled: true, warmedUpBuild: nil, currentBuild: "a"))
        #expect(TextRecognitionWarmUp.isNeeded(isEnabled: true, warmedUpBuild: "a", currentBuild: "b"))
        #expect(!TextRecognitionWarmUp.isNeeded(isEnabled: true, warmedUpBuild: "a", currentBuild: "a"))
    }

    @Test func warmsUpEveryLaunchWhenTheBuildIsUnknown() {
        #expect(TextRecognitionWarmUp.isNeeded(isEnabled: true, warmedUpBuild: nil, currentBuild: nil))
        #expect(TextRecognitionWarmUp.isNeeded(isEnabled: true, warmedUpBuild: "a", currentBuild: nil))
    }

    /// With Copy Text off, Glint never runs Vision, so it never warms up either (OQ-22).
    @Test func neverWarmsUpWhileCopyTextIsOff() {
        #expect(!TextRecognitionWarmUp.isNeeded(isEnabled: false, warmedUpBuild: nil, currentBuild: "a"))
        #expect(!TextRecognitionWarmUp.isNeeded(isEnabled: false, warmedUpBuild: "a", currentBuild: "b"))
        #expect(!TextRecognitionWarmUp.isNeeded(isEnabled: false, warmedUpBuild: nil, currentBuild: nil))
    }

    @Test func buildKeyIsStableForOneBinary() {
        #expect(key(modified: built, macOS: macOS) == key(modified: built, macOS: macOS))
    }

    /// Local builds all say 0.1.0 (1), so the executable's date tells them apart (OQ-18).
    @Test func buildKeyChangesWithEveryBuiltBinary() {
        let original = key(modified: built, macOS: macOS)
        #expect(original != key(modified: built.addingTimeInterval(1), macOS: macOS))
        #expect(original != key(version: "0.1.1", modified: built, macOS: macOS))
        #expect(original != key(build: "2", modified: built, macOS: macOS))
    }

    /// A macOS update most likely replaces Vision's models, so the compiled model is rebuilt (OQ-18).
    @Test func buildKeyChangesWithTheMacOSVersion() {
        #expect(key(modified: built, macOS: macOS) != key(modified: built, macOS: "Version 26.1 (Build 25B80)"))
    }

    @Test func noBuildKeyWithoutTheExecutablesDate() {
        #expect(key(modified: nil, macOS: macOS) == nil)
    }
}
