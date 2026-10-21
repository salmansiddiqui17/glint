import Testing
@testable import GlintCore

struct TextRecognitionLimitsTests {
    @Test func theFirstAttemptMayTakeLongerAndSaysSo() {
        #expect(TextRecognitionLimits.timeout(isFirstSinceLaunch: true) == .seconds(45))
        #expect(TextRecognitionLimits.noticeDelay(isFirstSinceLaunch: true) == .seconds(10))
    }

    @Test func laterAttemptsKeepTheUsualLimitAndShowNoNotice() {
        // The notice would race the 10 s timeout and flash just before "Couldn't read text".
        #expect(TextRecognitionLimits.timeout(isFirstSinceLaunch: false) == .seconds(10))
        #expect(TextRecognitionLimits.noticeDelay(isFirstSinceLaunch: false) == nil)
    }

    @Test func theNoticeComesBeforeTheFirstAttemptTimesOut() throws {
        let delay = try #require(TextRecognitionLimits.noticeDelay(isFirstSinceLaunch: true))
        #expect(delay < TextRecognitionLimits.timeout(isFirstSinceLaunch: true))
    }

    /// macOS may still be preparing Vision's text model, so the user is told to try again (OQ-18).
    @Test func aFirstAttemptThatTimesOutIsStillGettingReady() {
        #expect(TextRecognitionLimits.failure(isFirstSinceLaunch: true, error: TimeoutError()) == .stillGettingReady)
    }

    @Test func otherFailuresCouldNotReadTheText() {
        struct VisionFailure: Error {}
        #expect(TextRecognitionLimits.failure(isFirstSinceLaunch: true, error: VisionFailure()) == .couldNotRead)
        #expect(TextRecognitionLimits.failure(isFirstSinceLaunch: false, error: TimeoutError()) == .couldNotRead)
        #expect(TextRecognitionLimits.failure(isFirstSinceLaunch: false, error: VisionFailure()) == .couldNotRead)
    }
}
