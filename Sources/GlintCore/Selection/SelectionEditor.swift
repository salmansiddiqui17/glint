import CoreGraphics

/// Selection editing on one display: create, move, resize, nudge and the full-display toggle.
///
/// Pure state machine with no AppKit. All points are display-local points with a top-left origin
/// (y grows downward); `bounds` is the whole display, `CGRect(origin: .zero, size: displaySize)`.
/// A selection, when present, is always inside `bounds` and at least 1 × 1 pt once a gesture ends.
public struct SelectionEditor: Equatable, Sendable {
    /// Pointer travel (points) that turns a press into a drag (FR-18).
    public static let dragThreshold: CGFloat = 3

    public let bounds: CGRect
    public private(set) var selection: CGRect?
    private var gesture: Gesture = .idle
    private var fullDisplayToggle: FullDisplayToggle = .inactive

    private enum Gesture: Equatable, Sendable {
        case idle
        case pending(start: CGPoint)
        case creating(anchor: CGPoint)
        case moving(start: CGPoint, original: CGRect)
        case resizing(handle: Handle, start: CGPoint, original: CGRect)
    }

    private enum FullDisplayToggle: Equatable, Sendable {
        case inactive
        case active(previous: CGRect?)
    }

    public init(bounds: CGRect) {
        self.bounds = bounds
    }

    /// True while a press-and-drag gesture is changing the selection: from mouse-down on the
    /// selection or a handle, or once a new selection's drag passes the threshold, until mouse-up.
    public var isDragging: Bool {
        switch gesture {
        case .creating, .moving, .resizing: true
        case .idle, .pending: false
        }
    }

    /// True while a drag is moving the selection (for the closed-hand cursor).
    public var isMoving: Bool {
        if case .moving = gesture { return true }
        return false
    }

    /// True while a drag is drawing a new selection (for the crosshair cursor).
    public var isCreating: Bool {
        if case .creating = gesture { return true }
        return false
    }

    /// The handle being dragged, so the resize cursor stays steady for the whole gesture.
    public var resizingHandle: Handle? {
        if case let .resizing(handle, _, _) = gesture { return handle }
        return nil
    }

    // MARK: Mouse

    public mutating func mouseDown(at rawPoint: CGPoint, clickCount: Int) {
        let point = clamp(rawPoint)
        guard let current = selection else {
            gesture = .pending(start: point)
            return
        }
        if clickCount >= 2, current.contains(point) {
            // Checked before handles so a double-click toggles even on a tiny selection (FR-23).
            gesture = .idle
            toggleFullDisplay()
        } else if let handle = Handle.hit(point, selection: current) {
            gesture = .resizing(handle: handle, start: point, original: current)
        } else if current.contains(point) {
            gesture = .moving(start: point, original: current)
        } else {
            gesture = .pending(start: point)
        }
    }

    /// Returns `true` when this drag has just started a brand-new selection, so the caller can
    /// clear selections on other displays (FR-18).
    @discardableResult
    public mutating func mouseDragged(to rawPoint: CGPoint) -> Bool {
        let point = clamp(rawPoint)
        switch gesture {
        case .idle:
            return false
        case let .pending(start):
            guard hypot(point.x - start.x, point.y - start.y) > Self.dragThreshold else { return false }
            gesture = .creating(anchor: start)
            fullDisplayToggle = .inactive
            selection = normalizedRect(start, point)
            return true
        case let .creating(anchor):
            selection = normalizedRect(anchor, point)
        case let .moving(start, original):
            selection = moved(original, by: CGPoint(x: point.x - start.x, y: point.y - start.y))
        case let .resizing(handle, start, original):
            // The grab offset can push an edge up to half a hit square past the display; keep it on-screen.
            // The result always contains the in-bounds anchor edge, so this is never `.null`.
            selection = handle.resize(original, grabbedAt: start, to: point).intersection(bounds)
        }
        return false
    }

    /// Ends the gesture at `rawPoint`. Returns `true` when the release itself created a new selection
    /// (a fast flick with no intermediate drag events), so the caller can clear other displays (FR-18).
    @discardableResult
    public mutating func mouseUp(at rawPoint: CGPoint) -> Bool {
        var beganNewSelection = mouseDragged(to: rawPoint)
        switch gesture {
        case .creating:
            if let rect = selection, rect.width < 1 || rect.height < 1 {
                selection = nil
                beganNewSelection = false
            }
        case let .resizing(_, _, original):
            if let rect = selection, rect.width < 1 || rect.height < 1 { selection = original }
        case .idle, .pending, .moving:
            break
        }
        gesture = .idle
        return beganNewSelection
    }

    // MARK: Keyboard and commands (ignored mid-drag: the drag would overwrite them)

    /// Arrow keys (FR-24): move by (dx, dy), or with `resize` grow/shrink keeping the top-left fixed.
    public mutating func nudge(dx: CGFloat, dy: CGFloat, resize: Bool) {
        guard !isDragging, let current = selection else { return }
        if resize {
            let width = min(max(1, current.width + dx), bounds.maxX - current.minX)
            let height = min(max(1, current.height + dy), bounds.maxY - current.minY)
            selection = CGRect(x: current.minX, y: current.minY, width: width, height: height)
        } else {
            selection = moved(current, by: CGPoint(x: dx, y: dy))
        }
    }

    /// Double-click inside, ⌘A or ⌘F (FR-23): select the whole display, or restore the previous rectangle.
    public mutating func toggleFullDisplay() {
        guard !isDragging else { return }
        if case let .active(previous) = fullDisplayToggle, selection == bounds {
            selection = previous
            fullDisplayToggle = .inactive
        } else {
            fullDisplayToggle = .active(previous: selection)
            selection = bounds
        }
    }

    /// Removes the selection, for example because another display started one.
    public mutating func clearSelection() {
        selection = nil
        gesture = .idle
        fullDisplayToggle = .inactive
    }

    /// Replaces the selection with `rect` clipped to the display (window snapping in P3).
    /// A rect that is off this display, or clips to less than 1 × 1 pt, clears the selection.
    public mutating func select(_ rect: CGRect) {
        let clipped = rect.standardized.intersection(bounds)
        selection = clipped.isNull || clipped.width < 1 || clipped.height < 1 ? nil : clipped
        gesture = .idle
        fullDisplayToggle = .inactive
    }

    // MARK: Helpers

    private func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    /// Moves `rect` by `delta`, keeping it fully inside `bounds` without changing its size (FR-22).
    private func moved(_ rect: CGRect, by delta: CGPoint) -> CGRect {
        let x = min(max(rect.minX + delta.x, bounds.minX), bounds.maxX - rect.width)
        let y = min(max(rect.minY + delta.y, bounds.minY), bounds.maxY - rect.height)
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
}

private func normalizedRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
    CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
}
