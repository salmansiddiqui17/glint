import CoreGraphics

/// One of the eight resize handles on a selection rectangle.
///
/// Coordinates are display-local points with a top-left origin (y grows downward).
public enum Handle: CaseIterable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    /// Which side of an axis a handle controls: the minimum or maximum coordinate.
    enum Side { case min, max }

    /// The x-side (left = min, right = max) this handle moves, if any.
    var xSide: Side? {
        switch self {
        case .topLeft, .left, .bottomLeft: .min
        case .topRight, .right, .bottomRight: .max
        case .top, .bottom: nil
        }
    }

    /// The y-side (top = min, bottom = max) this handle moves, if any.
    var ySide: Side? {
        switch self {
        case .topLeft, .top, .topRight: .min
        case .bottomLeft, .bottom, .bottomRight: .max
        case .left, .right: nil
        }
    }

    var isCorner: Bool { xSide != nil && ySide != nil }

    /// Visible handle size in points (FR-20).
    public static let visibleSize: CGFloat = 6
    /// Hit-test target size in points (FR-20).
    public static let hitSize: CGFloat = 12

    private static let corners = allCases.filter(\.isCorner)
    private static let edges = allCases.filter { !$0.isCorner }

    /// Centre of this handle: on the selection border.
    public func center(in selection: CGRect) -> CGPoint {
        let x: CGFloat = switch xSide {
        case .min: selection.minX
        case .max: selection.maxX
        case nil: selection.midX
        }
        let y: CGFloat = switch ySide {
        case .min: selection.minY
        case .max: selection.maxY
        case nil: selection.midY
        }
        return CGPoint(x: x, y: y)
    }

    /// The square drawn for this handle.
    public func visibleFrame(in selection: CGRect) -> CGRect {
        square(around: center(in: selection), side: Handle.visibleSize)
    }

    /// The handle under `point`, if any. Corners win over edges; within each group the handle whose
    /// centre is nearest wins, so on tiny selections you get the corner you aimed at.
    /// Hit squares are half-open (`CGRect.contains`), like AppKit hit-testing.
    public static func hit(_ point: CGPoint, selection: CGRect) -> Handle? {
        func nearest(_ group: [Handle]) -> Handle? {
            group
                .filter { square(around: $0.center(in: selection), side: hitSize).contains(point) }
                .min { distance($0.center(in: selection), point) < distance($1.center(in: selection), point) }
        }
        return nearest(corners) ?? nearest(edges)
    }

    /// `original` resized by dragging this handle from `start` (where it was grabbed) to `point`.
    ///
    /// The grab offset is preserved, so the edge moves by exactly the pointer's travel and a click
    /// without movement changes nothing (FR-21). Dragging past the opposite edge flips the rectangle.
    public func resize(_ original: CGRect, grabbedAt start: CGPoint, to point: CGPoint) -> CGRect {
        let handleCenter = center(in: original)
        let target = CGPoint(x: handleCenter.x + point.x - start.x, y: handleCenter.y + point.y - start.y)
        var minX = original.minX, maxX = original.maxX
        var minY = original.minY, maxY = original.maxY
        switch xSide {
        case .min: minX = target.x
        case .max: maxX = target.x
        case nil: break
        }
        switch ySide {
        case .min: minY = target.y
        case .max: maxY = target.y
        case nil: break
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                      width: abs(maxX - minX), height: abs(maxY - minY))
    }
}

private func square(around center: CGPoint, side: CGFloat) -> CGRect {
    CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}
