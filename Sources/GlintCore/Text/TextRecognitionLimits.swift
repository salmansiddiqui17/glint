/// How long Copy Text waits for Vision (FR-46, OQ-10, OQ-18).
public enum TextRecognitionLimits {
    /// The first recognition since Glint launched may run for 45 s, because macOS sometimes
    /// prepares Vision's text model first; once one (or the warm-up) has finished, later ones give
    /// up after 10 s.
    public static func timeout(isFirstSinceLaunch: Bool) -> Duration {
        isFirstSinceLaunch ? .seconds(45) : .seconds(10)
    }

    /// How long a recognition runs before the overlay says it is still reading, or nil for none.
    /// Only the first one, with its longer limit, says so: a later one's notice would come as it
    /// times out, just before "Couldn't read text".
    public static func noticeDelay(isFirstSinceLaunch: Bool) -> Duration? {
        isFirstSinceLaunch ? .seconds(10) : nil
    }

    /// What the overlay says when a recognition fails.
    public enum Failure: Equatable, Sendable {
        /// "Couldn't read text".
        case couldNotRead
        /// "Text recognition is still getting ready. Try again in a moment."
        case stillGettingReady
    }

    /// Only the first recognition since launch timing out means macOS may still be preparing
    /// Vision's text model (OQ-18); any other failure couldn't read the text.
    public static func failure(isFirstSinceLaunch: Bool, error: any Error) -> Failure {
        isFirstSinceLaunch && error is TimeoutError ? .stillGettingReady : .couldNotRead
    }
}
