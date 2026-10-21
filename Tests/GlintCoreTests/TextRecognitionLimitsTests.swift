import Testing
@testable import GlintCore

struct TextRecognitionLimitsTests {
    @Test func theFirstRecognitionMayTakeLonger() {
        #expect(TextRecognitionLimits.timeout(afterEarlierFinished: false) == .seconds(45))
    }

    @Test func laterRecognitionsKeepTheUsualLimit() {
        #expect(TextRecognitionLimits.timeout(afterEarlierFinished: true) == .seconds(10))
    }

    @Test func theNoticeShowsAfterTenSeconds() {
        #expect(TextRecognitionLimits.noticeDelay == .seconds(10))
    }

    @Test func onlyTheFirstRecognitionRunsLongEnoughForTheNotice() {
        #expect(TextRecognitionLimits.noticeDelay < TextRecognitionLimits.timeout(afterEarlierFinished: false))
        #expect(TextRecognitionLimits.noticeDelay >= TextRecognitionLimits.timeout(afterEarlierFinished: true))
    }
}
