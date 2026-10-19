import CoreGraphics

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
