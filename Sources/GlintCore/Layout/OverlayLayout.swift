import CoreGraphics

/// Where the size badge, action toolbar and tools palette go around a selection (FR-25, FR-26).
///
/// Display-local points, top-left origin (y grows downward). Only `bounds` limits are used, never
/// literal zeros, so the maths also holds for bounds with a non-zero origin.
public enum OverlayLayout {
    public static let badgeGap: CGFloat = 5
    public static let toolbarGap: CGFloat = 6

    /// 5 pt above the selection's top-left corner. Falls back, in order, to:
    /// - above the selection, beside `palette` (the tools palette, which beside a narrow
    ///   selection reaches up into the badge's row);
    /// - inside the top-left corner (inset 5 pt);
    /// - left of `obstacle` (the action toolbar);
    /// - above it, then below it, each also tried beside the palette.
    ///
    /// It takes the first that fits on the display without overlapping either toolbar. Tiny or
    /// thin selections at a display edge are the cases that need the toolbar fallbacks. Never
    /// off the display.
    public static func badgeFrame(size: CGSize, selection: CGRect, bounds: CGRect,
                                  avoiding obstacle: CGRect? = nil, palette: CGRect? = nil) -> CGRect {
        func frame(x: CGFloat, y: CGFloat) -> CGRect {
            CGRect(x: clampX(x, width: size.width, bounds: bounds), y: y, width: size.width, height: size.height)
        }
        /// At height `y`: at `x`, then left and right of the palette.
        func row(x: CGFloat, y: CGFloat) -> [CGRect] {
            [frame(x: x, y: y)] + (palette.map { palette in
                [frame(x: palette.minX - badgeGap - size.width, y: y), frame(x: palette.maxX + badgeGap, y: y)]
            } ?? [])
        }
        let inside = frame(x: selection.minX + badgeGap, y: selection.minY + badgeGap)
        var candidates = row(x: selection.minX, y: selection.minY - badgeGap - size.height) + [inside]
        if let obstacle {
            candidates.append(CGRect(x: obstacle.minX - badgeGap - size.width, y: obstacle.minY,
                                     width: size.width, height: size.height))
            candidates += row(x: obstacle.minX, y: obstacle.minY - badgeGap - size.height)
            candidates += row(x: obstacle.minX, y: obstacle.maxY + badgeGap)
        }
        let toolbars = [obstacle, palette].compactMap { $0 }
        return candidates.first { candidate in
            bounds.contains(candidate) && !toolbars.contains { $0.intersects(candidate) }
        } ?? clamp(inside, into: bounds)
    }

    /// Right-aligned to the selection and kept on the display horizontally, then the first vertical
    /// position that fits: below, above, inside the selection's bottom-right corner, else clamped
    /// onto the display.
    public static func actionToolbarFrame(size: CGSize, selection: CGRect, bounds: CGRect) -> CGRect {
        let x = clampX(selection.maxX - size.width, width: size.width, bounds: bounds)
        let below = CGRect(x: x, y: selection.maxY + toolbarGap, width: size.width, height: size.height)
        let above = CGRect(x: x, y: selection.minY - toolbarGap - size.height, width: size.width, height: size.height)
        let inside = CGRect(x: selection.maxX - toolbarGap - size.width, y: selection.maxY - toolbarGap - size.height,
                            width: size.width, height: size.height)
        if bounds.contains(below) { return below }
        if bounds.contains(above) { return above }
        if selection.contains(inside) { return inside }
        return clamp(below, into: bounds)
    }

    /// Bottom-aligned with the selection and kept on the display vertically, then the first
    /// horizontal position that fits on the display without overlapping `toolbar` (the action
    /// toolbar): right of the selection, left of it, inside its right edge, inside its right edge
    /// stacked above the toolbar (for a full-display selection; both inside spots only when the
    /// palette fits inside the selection, like the toolbar's), else beside the toolbar (right, then
    /// left, bottom-aligned with it), clamped onto the display.
    public static func toolsPaletteFrame(size: CGSize, selection: CGRect, bounds: CGRect,
                                         avoiding toolbar: CGRect) -> CGRect {
        func frame(x: CGFloat, bottom: CGFloat) -> CGRect {
            CGRect(x: x, y: clampY(bottom - size.height, height: size.height, bounds: bounds),
                   width: size.width, height: size.height)
        }
        let insideX = selection.maxX - toolbarGap - size.width
        let besideToolbar = frame(x: toolbar.maxX + toolbarGap, bottom: toolbar.maxY)
        // The inside spots count only when the palette is really inside the selection: beside a tiny
        // selection they would float above the toolbar, and the palette belongs beside it (FR-26).
        let inside = [
            frame(x: insideX, bottom: selection.maxY - toolbarGap),
            CGRect(x: insideX, y: toolbar.minY - toolbarGap - size.height, width: size.width, height: size.height),
        ].filter { selection.contains($0) }
        let candidates = [
            frame(x: selection.maxX + toolbarGap, bottom: selection.maxY),
            frame(x: selection.minX - toolbarGap - size.width, bottom: selection.maxY),
        ] + inside + [
            besideToolbar,
            frame(x: toolbar.minX - toolbarGap - size.width, bottom: toolbar.maxY),
        ]
        return candidates.first { bounds.contains($0) && !$0.intersects(toolbar) } ?? clamp(besideToolbar, into: bounds)
    }

    /// Something taller than the display is pinned to its top, so its first items stay visible.
    static func clampY(_ y: CGFloat, height: CGFloat, bounds: CGRect) -> CGFloat {
        max(min(y, bounds.maxY - height), bounds.minY)
    }

    static func clampX(_ x: CGFloat, width: CGFloat, bounds: CGRect) -> CGFloat {
        min(max(x, bounds.minX), bounds.maxX - width)
    }

    static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        CGRect(x: clampX(rect.minX, width: rect.width, bounds: bounds),
               y: clampY(rect.minY, height: rect.height, bounds: bounds),
               width: rect.width, height: rect.height)
    }
}
