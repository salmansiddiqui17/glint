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
}
