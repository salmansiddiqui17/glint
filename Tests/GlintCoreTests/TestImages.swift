import CoreGraphics
import CoreImage

/// A solid blue test image with a red `marker` × `marker` block in its top-left corner.
///
/// - Parameters:
///   - space: the image's colour space (default sRGB).
///   - deep: 16-bit float components instead of 8-bit integers (for extended-range spaces).
func makeTestImage(width: Int, height: Int, marker: Int = 1,
                   space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!, deep: Bool = false) -> CGImage {
    let bitmapInfo = deep
        ? CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.floatComponents.rawValue
            | CGImageByteOrderInfo.order16Little.rawValue
        : CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: deep ? 16 : 8,
                            bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)!
    context.setFillColor(CGColor(colorSpace: space, components: [0, 0, 1, 1])!)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(colorSpace: space, components: [1, 0, 0, 1])!)
    context.fill(CGRect(x: 0, y: height - marker, width: marker, height: marker))   // CG origin is bottom-left
    return context.makeImage()!
}

/// Whether the image's top-left pixel is (mostly) red.
func topLeftPixelIsRed(_ image: CGImage) -> Bool {
    var pixel = [UInt8](repeating: 0, count: 4)
    let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        // Draw the image so that its top-left pixel lands on the single-pixel context.
        context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        return true
    }
    return drawn && pixel[0] > 200 && pixel[2] < 50
}

/// An 8-bit sRGB pixel.
struct RGBA8: Equatable, CustomStringConvertible {
    let red, green, blue, alpha: Int

    var description: String { "(\(red), \(green), \(blue), \(alpha))" }
}

/// The colour a redaction patch shows at pixel (`x`, `y`) of its area, `frameWidth` pixels wide:
/// a full-size patch's own pixel, or for a patch with one pixel per block, its block's pixel.
func shownColor(_ patch: CGImage, frameWidth: Int, x: Int, y: Int, strength: Int) -> RGBA8 {
    patch.width == frameWidth ? pixelColor(patch, x: x, y: y) : pixelColor(patch, x: x / strength, y: y / strength)
}

/// Core Image's pixellate at full size, the way P2 made pixelate patches: the reference the
/// one-pixel-per-block patches must match.
func fullSizePixellate(_ image: CGImage, strength: CGFloat) -> CGImage? {
    let input = CIImage(cgImage: image)
    let output = CIFilter(name: "CIPixellate", parameters: [
        kCIInputImageKey: input.clampedToExtent(),
        kCIInputScaleKey: strength,
        kCIInputCenterKey: CIVector(x: input.extent.minX, y: input.extent.maxY),
    ])?.outputImage?.cropped(to: input.extent)
    return output.flatMap {
        CIContext().createCGImage($0, from: input.extent, format: .RGBA8,
                                  colorSpace: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
    }
}

/// The colour of the pixel at (`x`, `y`) counted from the image's top-left corner, converted to sRGB.
func pixelColor(_ image: CGImage, x: Int, y: Int) -> RGBA8 {
    var pixel = [UInt8](repeating: 0, count: 4)
    pixel.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        // Shift the image so that pixel (x, y) lands on the single-pixel context (CG is bottom-left).
        context.draw(image, in: CGRect(x: -x, y: y + 1 - image.height, width: image.width, height: image.height))
    }
    return RGBA8(red: Int(pixel[0]), green: Int(pixel[1]), blue: Int(pixel[2]), alpha: Int(pixel[3]))
}

/// Every pixel of `image` the way `pixelColor` reads it, drawn once: `[y][x]` from the top-left corner.
func pixelColors(_ image: CGImage) -> [[RGBA8]] {
    let (width, height) = (image.width, image.height)
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))   // memory starts at the top row
    }
    return (0..<height).map { y in
        (0..<width).map { x in
            let i = (y * width + x) * 4
            return RGBA8(red: Int(bytes[i]), green: Int(bytes[i + 1]), blue: Int(bytes[i + 2]), alpha: Int(bytes[i + 3]))
        }
    }
}
