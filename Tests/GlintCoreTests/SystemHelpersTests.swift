import CoreGraphics
import Foundation
import Testing
@testable import GlintCore

struct LaunchOrderTests {
    let early = Date(timeIntervalSince1970: 100)
    let late = Date(timeIntervalSince1970: 200)

    @Test func earlierLaunchIsOlder() {
        #expect(LaunchOrder(launchDate: early, processID: 900) < LaunchOrder(launchDate: late, processID: 100))
    }

    @Test func missingLaunchDateSortsLast() {
        #expect(LaunchOrder(launchDate: late, processID: 900) < LaunchOrder(launchDate: nil, processID: 100))
    }

    @Test func lowerProcessIDBreaksTies() {
        #expect(LaunchOrder(launchDate: early, processID: 100) < LaunchOrder(launchDate: early, processID: 101))
        #expect(LaunchOrder(launchDate: nil, processID: 100) < LaunchOrder(launchDate: nil, processID: 101))
    }

    @Test func equalityAgreesWithOrdering() {
        let missing = LaunchOrder(launchDate: nil, processID: 5)
        let distant = LaunchOrder(launchDate: .distantFuture, processID: 5)
        #expect(!(missing < distant) && !(distant < missing))
        #expect(missing == distant)
    }
}

struct WindowListTests {
    func window(_ number: Int, pid: Int, layer: Int) -> [String: Any] {
        [kCGWindowNumber as String: number, kCGWindowOwnerPID as String: pid, kCGWindowLayer as String: layer]
    }

    @Test func keepsOtherAppsNormalWindowsOnly() {
        let windows = [
            window(1, pid: 10, layer: 0),
            window(2, pid: 10, layer: 3),       // floating palette
            window(3, pid: 99, layer: 0),       // our own overlay or panel
            window(4, pid: 11, layer: 0),
            window(5, pid: 11, layer: 25),      // menu extra
            [kCGWindowNumber as String: 6],     // incomplete entry
        ]
        #expect(WindowList.normalWindowIDs(in: windows, excludingProcess: 99) == [1, 4])
    }
}

struct PartialResultsTests {
    struct Failure: Error, Equatable { let id: Int }

    @Test func keepsSuccessesInOrderAndSkipsFailures() throws {
        let results: [Result<Int, any Error>] = [.success(1), .failure(Failure(id: 1)), .success(3)]
        #expect(try PartialResults.successes(results) == [1, 3])
    }

    @Test func throwsEveryErrorWhenAllFail() {
        let results: [Result<Int, any Error>] = [.failure(Failure(id: 1)), .failure(Failure(id: 2))]
        #expect {
            try PartialResults.successes(results)
        } throws: { error in
            ((error as? AllFailedError)?.errors.map { $0 as? Failure }) == [Failure(id: 1), Failure(id: 2)]
        }
    }

    @Test func emptyBatchThrows() {
        #expect(throws: AllFailedError.self) { try PartialResults.successes([Result<Int, any Error>]()) }
    }
}
