import CoreGraphics

/// The windows that window snapping can select on one display (FR-16, FR-19), recorded when the
/// capture was triggered so they match the frozen image.
///
/// Frames are display-local points with a top-left origin, clipped to the display, front to back.
public struct SnapTargets: Equatable, Sendable {
    /// The whole display, `CGRect(origin: .zero, size: displaySize)`.
    public let bounds: CGRect
    public let frames: [CGRect]

    /// Each window is clipped to the display, and kept only when the part on this display is at
    /// least `WindowList.minimumSnapSize` points each way, so a window that grazes the display
    /// is not a thin strip to click there (OQ-17).
    /// - Parameters:
    ///   - windows: window frames in global display coordinates (origin at the main display's
    ///     top-left corner, y down), front to back, from `WindowList.snapFrames`.
    ///   - display: this display's frame in the same coordinates.
    public init(windows: [CGRect], display: CGRect) {
        bounds = CGRect(origin: .zero, size: display.size)
        frames = windows.compactMap { window in
            let clipped = window.intersection(display)
            guard !clipped.isNull, clipped.width >= WindowList.minimumSnapSize,
                  clipped.height >= WindowList.minimumSnapSize else { return nil }
            return clipped.offsetBy(dx: -display.minX, dy: -display.minY)
        }
    }

    /// The frame a click at `point` selects: the frontmost window under it, else the whole display.
    public func target(at point: CGPoint) -> CGRect {
        frames.first { $0.contains(point) } ?? bounds
    }

    /// A display's frame in global display coordinates (top-left origin), from its AppKit frame
    /// (bottom-left origin) and the height of the main display, which both systems start from.
    /// The main display is the one with the menu bar (`NSScreen.screens[0]`, `CGMainDisplayID()`),
    /// not `NSScreen.main`, which is the display with the key window.
    public static func globalFrame(ofDisplay appKitFrame: CGRect, mainDisplayHeight: CGFloat) -> CGRect {
        FlippedCoordinates(height: mainDisplayHeight).rect(appKitFrame)
    }
}
