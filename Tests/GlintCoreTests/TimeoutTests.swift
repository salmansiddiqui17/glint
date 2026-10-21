import Testing
@testable import GlintCore

struct TimeoutTests {
    struct Boom: Error, Equatable {}

    /// Long enough that a loaded CI virtual machine can't stall the operation past it. A test whose
    /// operation finishes first never waits for it: the timer is cancelled.
    let generousTimeout = Duration.seconds(30)

    @Test func returnsTheValueWhenTheOperationIsFast() async throws {
        let value = try await withTimeout(generousTimeout) { 42 }
        #expect(value == 42)
    }

    /// Returns at the timeout, not when the slow operation would finish. The bound is half the
    /// operation's duration rather than a fixed second: a loaded CI runner took 1.6 s to return
    /// from a 50 ms timeout, but waiting for the operation would take the full 60 s.
    @Test func throwsTimeoutWhenTheOperationIsSlow() async {
        let slow = Duration.seconds(60)
        let started = ContinuousClock.now
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: slow)
                return 1
            }
        }
        #expect(ContinuousClock.now - started < slow / 2)
    }

    @Test func passesThroughTheOperationsError() async {
        await #expect(throws: Boom.self) {
            try await withTimeout(generousTimeout) { () async throws -> Int in throw Boom() }
        }
    }

    @Test func onceFlagIsClaimedExactlyOnce() async {
        let flag = OnceFlag()
        let claims = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for _ in 0..<100 { group.addTask { flag.claim() } }
            var count = 0
            for await claimed in group where claimed { count += 1 }
            return count
        }
        #expect(claims == 1)
    }
}
