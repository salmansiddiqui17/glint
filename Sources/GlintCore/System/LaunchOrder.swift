import Foundation

/// Launch order of a running Glint instance, so every instance agrees on which one is older
/// (single-instance rule: the older instance wins).
///
/// Processes not started through LaunchServices (a binary run from Terminal) have no launch date
/// and sort last; the lower process ID breaks ties.
public struct LaunchOrder: Comparable, Sendable {
    public let launchDate: Date?
    public let processID: Int32

    public init(launchDate: Date?, processID: Int32) {
        self.launchDate = launchDate
        self.processID = processID
    }

    /// The one sort key, so `==` and `<` always agree.
    private var key: (Date, Int32) {
        (launchDate ?? .distantFuture, processID)
    }

    public static func == (lhs: LaunchOrder, rhs: LaunchOrder) -> Bool {
        lhs.key == rhs.key
    }

    public static func < (lhs: LaunchOrder, rhs: LaunchOrder) -> Bool {
        lhs.key < rhs.key
    }
}
