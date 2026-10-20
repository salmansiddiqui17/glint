import CoreGraphics

/// Reads `CGWindowListCopyWindowInfo` entries.
public enum WindowList {
    /// Windows narrower or shorter than this (points) are never snap targets (FR-16).
    public static let minimumSnapSize: CGFloat = 40

    /// IDs of other apps' windows at the normal level (layer 0), which belong to a Space.
    ///
    /// Palettes, menu extras, popovers and banners sit at higher levels and come and go without a
    /// Space change, so they are left out. Window numbers, levels and owners need no Screen
    /// Recording permission.
    public static func normalWindowIDs(in windows: [[String: Any]], excludingProcess processID: Int) -> Set<Int> {
        Set(windows.compactMap { window in
            guard isOtherAppsNormalWindow(window, excludingProcess: processID) else { return nil }
            return window[kCGWindowNumber as String] as? Int
        })
    }

    /// Frames of the windows snapping can select (FR-16), front to back as listed: other apps'
    /// normal-level windows that are visible and at least `minimumSnapSize` points each way.
    /// Fully transparent windows and tiny helpers, which some apps keep on screen, are left out.
    /// Frames are in global display coordinates: points, origin at the top-left of the main
    /// display, y growing downward.
    public static func snapFrames(in windows: [[String: Any]], excludingProcess processID: Int) -> [CGRect] {
        windows.compactMap { window in
            guard isOtherAppsNormalWindow(window, excludingProcess: processID),
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= minimumSnapSize, frame.height >= minimumSnapSize else { return nil }
            return frame
        }
    }

    private static func isOtherAppsNormalWindow(_ window: [String: Any], excludingProcess processID: Int) -> Bool {
        (window[kCGWindowOwnerPID as String] as? Int).map { $0 != processID } == true
            && (window[kCGWindowLayer as String] as? Int) == 0
    }
}
