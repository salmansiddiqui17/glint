import Foundation

/// Default file name for saved captures (FR-44): "Screenshot 2026-10-14 at 16.24.05.png".
public enum FileNaming {
    public static func defaultFileName(for date: Date, format: ImageFormat,
                                       timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"   // yyyy: calendar year (YYYY is the week-based year)
        return "Screenshot \(formatter.string(from: date)).\(format.fileExtension)"
    }

    /// `name` with `format`'s extension: a known image extension is replaced, anything else is
    /// kept, so a name such as "build 1.4" keeps its dot.
    public static func fileName(_ name: String, withExtensionOf format: ImageFormat) -> String {
        let name = name as NSString
        let known = Set(ImageFormat.allCases.map(\.fileExtension) + ["jpeg"])
        let base = known.contains(name.pathExtension.lowercased()) ? name.deletingPathExtension : name as String
        return "\(base).\(format.fileExtension)"
    }
}
