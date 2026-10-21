/// How long Copy Text waits for Vision (FR-46, OQ-10, OQ-18).
public enum TextRecognitionLimits {
    /// The first recognition in a session may run for 45 s, because macOS sometimes prepares
    /// Vision's text model first; once one has finished, later ones give up after 10 s.
    public static func timeout(afterEarlierFinished: Bool) -> Duration {
        afterEarlierFinished ? .seconds(10) : .seconds(45)
    }

    /// How long a recognition runs before the overlay says it is still reading. No later
    /// recognition runs this long, so only a slow first one shows the notice.
    public static let noticeDelay: Duration = .seconds(10)
}
