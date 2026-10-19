import Foundation
import Testing
@testable import GlintCore

struct FileNamingTests {
    @Test func defaultNameHasDateAndTime() {
        let date = Date(timeIntervalSince1970: 1_791_995_045)   // 2026-10-14 16:24:05 UTC
        let name = FileNaming.defaultFileName(for: date, format: .png, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "Screenshot 2026-10-14 at 16.24.05.png")
    }

    @Test func jpegUsesJpgExtension() {
        let name = FileNaming.defaultFileName(for: Date(timeIntervalSince1970: 0), format: .jpeg,
                                              timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "Screenshot 1970-01-01 at 00.00.00.jpg")
    }

    @Test func usesTheCalendarYearAroundNewYear() {
        let date = Date(timeIntervalSince1970: 1_735_560_000)   // 2024-12-30 12:00:00 UTC, in week 1 of 2025
        let name = FileNaming.defaultFileName(for: date, format: .png, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "Screenshot 2024-12-30 at 12.00.00.png")
    }

    @Test func usesTheGivenTimeZone() {
        let date = Date(timeIntervalSince1970: 1_791_995_045)   // 2026-10-14 16:24:05 UTC
        let name = FileNaming.defaultFileName(for: date, format: .png,
                                              timeZone: TimeZone(identifier: "America/New_York")!)
        #expect(name == "Screenshot 2026-10-14 at 12.24.05.png")
    }

    @Test(arguments: [
        ("Screenshot 2026-10-14 at 16.24.05.png", ImageFormat.jpeg, "Screenshot 2026-10-14 at 16.24.05.jpg"),
        ("shot.jpg", .png, "shot.png"),
        ("shot.JPEG", .png, "shot.png"),
        ("build 1.4", .png, "build 1.4.png"),
        ("notes.txt", .jpeg, "notes.txt.jpg"),
    ])
    func fileNameGetsTheFormatsExtension(name: String, format: ImageFormat, expected: String) {
        #expect(FileNaming.fileName(name, withExtensionOf: format) == expected)
    }
}
