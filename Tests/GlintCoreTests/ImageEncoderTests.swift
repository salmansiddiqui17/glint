import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import GlintCore

struct ImageEncoderTests {
    struct Decoded {
        let type: String
        let width: Int
        let dpi: Double
        let properties: [CFString: Any]
        let image: CGImage
    }

    func decode(_ data: Data) throws -> Decoded {
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        let type = try #require(CGImageSourceGetType(source)) as String
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        return Decoded(type: type, width: width, dpi: (properties[kCGImagePropertyDPIWidth] as? Double) ?? 0,
                       properties: properties, image: image)
    }

    @Test(arguments: ImageFormat.allCases)
    func encodesWithTypeSizeAndDPI(format: ImageFormat) throws {
        let data = try #require(ImageEncoder.encode(makeTestImage(width: 8, height: 4), as: format, dpi: 144))
        let decoded = try decode(data)
        #expect(decoded.type == format.typeIdentifier)
        #expect(decoded.width == 8)
        #expect(abs(decoded.dpi - 144) < 1)
    }

    /// The embedded profile keeps its identity. (PNG may re-serialise the ICC bytes, so compare the
    /// profile, not the bytes.)
    @Test(arguments: ImageFormat.allCases, [
        (CGColorSpace.displayP3 as String, "Display P3"),
        (CGColorSpace.adobeRGB1998 as String, "Adobe RGB (1998)"),
    ])
    func keepsTheColourProfile(format: ImageFormat, profile: (spaceName: String, profileName: String)) throws {
        let space = try #require(CGColorSpace(name: profile.spaceName as CFString))
        let data = try #require(ImageEncoder.encode(makeTestImage(width: 8, height: 4, space: space),
                                                    as: format, dpi: 72))
        let decoded = try decode(data)
        #expect(decoded.properties[kCGImagePropertyProfileName] as? String == profile.profileName)
        #expect(decoded.image.colorSpace?.copyICCData() != nil)
    }

    @Test(arguments: ImageFormat.allCases)
    func encodesDeepExtendedRangeImages(format: ImageFormat) throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3))
        let image = makeTestImage(width: 8, height: 4, space: space, deep: true)
        let data = try #require(ImageEncoder.encode(image, as: format, dpi: 144))
        let decoded = try decode(data)
        #expect(decoded.width == 8)
        #expect(decoded.properties[kCGImagePropertyProfileName] as? String == "Display P3")   // the gamut survives
    }

    @Test(arguments: ImageFormat.allCases)
    func writesNoIdentifyingMetadata(format: ImageFormat) throws {
        let data = try #require(ImageEncoder.encode(makeTestImage(width: 8, height: 4), as: format, dpi: 144))
        let properties = try decode(data).properties
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware,
                    kCGImagePropertyTIFFDateTime] {
            #expect(tiff[key] == nil)
        }
    }
}
