import Synchronization

/// Thrown by `withTimeout` when the operation doesn't finish in time.
public struct TimeoutError: Error, Equatable {
    public init() {}
}

/// Runs `operation`, or throws `TimeoutError` after `timeout`, whichever comes first.
///
/// Meant for system calls that can't be cancelled (e.g. ScreenCaptureKit): the operation keeps
/// running after a timeout and its late result is discarded.
public func withTimeout<T: Sendable>(_ timeout: Duration,
                                     _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let once = OnceFlag()
        let timer = Task {
            try? await Task.sleep(for: timeout)
            if once.claim() { continuation.resume(throwing: TimeoutError()) }
        }
        Task {
            do {
                let value = try await operation()
                if once.claim() { continuation.resume(returning: value) }
            } catch {
                if once.claim() { continuation.resume(throwing: error) }
            }
            timer.cancel()   // don't leave the timer sleeping (NFR-7)
        }
    }
}

/// True for exactly one caller.
final class OnceFlag: Sendable {
    private let claimed = Mutex(false)

    func claim() -> Bool {
        claimed.withLock { claimed in
            defer { claimed = true }
            return !claimed
        }
    }
}
