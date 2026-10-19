import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// File formats Glint can save (FR-44).
public enum ImageFormat: String, CaseIterable, Sendable {
    case png, jpeg

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    /// The format's Uniform Type, e.g. for `NSSavePanel.allowedContentTypes`.
    public var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }

    /// Uniform Type Identifier string, as ImageIO expects it.
    public var typeIdentifier: String { contentType.identifier }

    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        }
    }
}

/// Encodes images with ImageIO (FR-44, NFR-10).
///
/// - The image's colour space travels with the file: an ICC profile, or ImageIO's equivalent
///   standard tag (`sRGB` chunk, `cICP`) when the profile matches a standard space. The colour is
///   never converted to sRGB.
/// - Resolution is written as DPI metadata (PNG `pHYs`; JPEG Exif). ImageIO also writes basic Exif
///   (resolution, pixel dimensions, colour space) but nothing identifying: no location, device or
///   software name.
/// - Extended-range (HDR) values are clipped to SDR; P1 captures are SDR.
/// - JPEG has no alpha: translucent pixels are flattened onto white (screenshots are opaque).
public enum ImageEncoder {
    public static let jpegQuality: Double = 0.9

    public static func encode(_ image: CGImage, as format: ImageFormat, dpi: CGFloat) -> Data? {
        precondition(dpi.isFinite && dpi > 0, "dpi must be a positive number")
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, format.typeIdentifier as CFString, 1, nil
        ) else { return nil }
        var properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
