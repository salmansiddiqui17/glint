import Testing
@testable import GlintCore

struct TimeoutTests {
    struct Boom: Error, Equatable {}

    @Test func returnsTheValueWhenTheOperationIsFast() async throws {
        let value = try await withTimeout(.seconds(2)) { 42 }
        #expect(value == 42)
    }

    @Test func throwsTimeoutWhenTheOperationIsSlow() async {
        let started = ContinuousClock.now
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(.milliseconds(50)) {
                try await Task.sleep(for: .seconds(5))
                return 1
            }
        }
        #expect(ContinuousClock.now - started < .seconds(1))
    }

    @Test func passesThroughTheOperationsError() async {
        await #expect(throws: Boom.self) {
            try await withTimeout(.seconds(2)) { () async throws -> Int in throw Boom() }
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
