import CoreGraphics

/// Turns scroll-wheel input into ±1 steps for the stroke width (FR-38) and text size (FR-35).
public struct ScrollStepper: Sendable {
    /// Trackpad and Magic Mouse scrolling (precise deltas) gives one step per this many points.
    public static let pointsPerStep: CGFloat = 12
    private var pending: CGFloat = 0

    public init() {}

    /// The steps for one scroll event: positive when scrolling up.
    ///
    /// - Parameter precise: `NSEvent.hasPreciseScrollingDeltas`. A wheel without precise deltas
    ///   gives one step per notch, however fast it turns.
    public mutating func steps(for delta: CGFloat, precise: Bool) -> Int {
        guard precise else {
            pending = 0
            return delta > 0 ? 1 : delta < 0 ? -1 : 0
        }
        if delta != 0, pending != 0, (delta > 0) != (pending > 0) { pending = 0 }   // direction changed
        pending += delta
        let steps = Int((pending / Self.pointsPerStep).rounded(.towardZero))
        pending -= CGFloat(steps) * Self.pointsPerStep
        return steps
    }
}
