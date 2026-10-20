import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GlintCore

/// Golden-image comparison for the renderer (NFR-17).
///
/// Goldens are PNG files in `Goldens/` next to this file. Text goldens live in
/// `Goldens/text/<macOS major version>/`, because glyph rendering changes between versions.
/// Run the tests with `GLINT_RECORD_GOLDENS=1` to write new goldens instead of comparing.
enum GoldenImages {
    /// A pixel matches when every channel is within this many 8-bit steps.
    static let channelTolerance = 2
    /// The share of pixels allowed to differ by more, for anti-aliasing at shape edges.
    static let allowedMismatch = 0.001

    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Goldens")

    static var isRecording: Bool { ProcessInfo.processInfo.environment["GLINT_RECORD_GOLDENS"] == "1" }

    static var textDirectory: URL {
        directory.appendingPathComponent("text/\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)")
    }

    /// Whether this macOS version has text goldens; text cases are skipped without them.
    static var hasTextGoldens: Bool {
        isRecording || FileManager.default.fileExists(atPath: textDirectory.path)
    }

    /// Compares `image` with the golden `name`.png (in the text folder when `text`), or records it.
    static func check(_ image: CGImage, named name: String, text: Bool = false,
                      sourceLocation: SourceLocation = #_sourceLocation) throws {
        let url = (text ? textDirectory : directory).appendingPathComponent("\(name).png")
        let actual = try #require(pixels(of: image), sourceLocation: sourceLocation)
        if isRecording {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try #require(png(actual), sourceLocation: sourceLocation).write(to: url)
            return
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let golden = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let expected = pixels(of: golden) else {
            Issue.record("No golden \(url.lastPathComponent): run the tests with GLINT_RECORD_GOLDENS=1",
                         sourceLocation: sourceLocation)
            attach([(actual, "actual")], name: name)
            return
        }
        guard expected.width == actual.width, expected.height == actual.height else {
            Issue.record("\(name): \(actual.width) × \(actual.height), golden is \(expected.width) × \(expected.height)",
                         sourceLocation: sourceLocation)
            attach([(expected, "expected"), (actual, "actual")], name: name)
            return
        }
        var diff = Bitmap(width: actual.width, height: actual.height)
        var mismatched = 0
        for index in stride(from: 0, to: actual.bytes.count, by: 4) {
            let worst = (0..<4).map { abs(Int(actual.bytes[index + $0]) - Int(expected.bytes[index + $0])) }.max()!
            if worst > channelTolerance {
                mismatched += 1
                diff.bytes.replaceSubrange(index..<index + 4, with: [255, 0, 0, 255])
            }
        }
        let share = Double(mismatched) / Double(actual.width * actual.height)
        guard share > allowedMismatch else { return }
        Issue.record("\(name): \(mismatched) pixels differ (\(String(format: "%.3f", share * 100)) %)",
                     sourceLocation: sourceLocation)
        attach([(expected, "expected"), (actual, "actual"), (diff, "diff")], name: name)
    }

    /// Attaches each bitmap as `<name>-<suffix>.png`, so a failure on CI can be inspected.
    static func attach(_ bitmaps: [(Bitmap, String)], name: String) {
        for (bitmap, suffix) in bitmaps {
            if let data = png(bitmap) { Attachment.record(data, named: "\(name)-\(suffix).png") }
        }
    }

    /// 8-bit sRGB RGBA pixels, top row first.
    struct Bitmap {
        let width: Int
        let height: Int
        var bytes: [UInt8]

        init(width: Int, height: Int, bytes: [UInt8]? = nil) {
            self.width = width
            self.height = height
            self.bytes = bytes ?? [UInt8](repeating: 0, count: width * height * 4)
        }
    }

    static func pixels(of image: CGImage) -> Bitmap? {
        var bitmap = Bitmap(width: image.width, height: image.height)
        let drawn = bitmap.bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return drawn ? bitmap : nil
    }

    static func png(_ bitmap: Bitmap) -> Data? {
        var bytes = bitmap.bytes
        let image = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            CGContext(data: buffer.baseAddress, width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                      bytesPerRow: bitmap.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        return image.flatMap { ImageEncoder.encode($0, as: .png, dpi: 72) }
    }
}
