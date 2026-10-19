import CoreGraphics

/// Reads `CGWindowListCopyWindowInfo` entries.
public enum WindowList {
    /// IDs of other apps' windows at the normal level (layer 0), which belong to a Space.
    ///
    /// Palettes, menu extras, popovers and banners sit at higher levels and come and go without a
    /// Space change, so they are left out. Window numbers, levels and owners need no Screen
    /// Recording permission.
    public static func normalWindowIDs(in windows: [[String: Any]], excludingProcess processID: Int) -> Set<Int> {
        Set(windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? Int) != processID,
                  (window[kCGWindowLayer as String] as? Int) == 0 else { return nil }
            return window[kCGWindowNumber as String] as? Int
        })
    }
}
