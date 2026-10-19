/// Thrown when every operation in a batch failed. Carries every error, so callers can classify
/// any of them (one display's permission error can follow another's timeout).
public struct AllFailedError: Error {
    public let errors: [any Error]

    public init(errors: [any Error]) {
        self.errors = errors
    }
}

/// Collects a batch where some operations may fail (FR-15: displays that fail are skipped).
public enum PartialResults {
    /// The successful values, in order. Throws `AllFailedError` with every error when none succeeded.
    public static func successes<Value>(_ results: [Result<Value, any Error>]) throws -> [Value] {
        var values: [Value] = []
        var errors: [any Error] = []
        for result in results {
            switch result {
            case let .success(value): values.append(value)
            case let .failure(error): errors.append(error)
            }
        }
        if values.isEmpty { throw AllFailedError(errors: errors) }
        return values
    }
}
