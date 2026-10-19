// Renders the macOS app icon set from the full-bleed square master.
//
//   swift scripts/make-icon.swift <master.png> <out.iconset>
//
// Classic macOS icon grid: on a 1024 canvas the body is an 824 × 824 rounded square (a
// superellipse, close to Apple's continuous-corner shape), centred with a 100 pt margin that
// leaves room for a soft drop shadow. macOS 26 and later draws icons in the same shape, so the
// masked icon reads as native there too.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <master.png> <out.iconset>\n".utf8))
    exit(2)
}
let masterURL = URL(fileURLWithPath: arguments[1])
let outURL = URL(fileURLWithPath: arguments[2], isDirectory: true)

guard let source = CGImageSourceCreateWithURL(masterURL as CFURL, nil),
      let master = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    FileHandle.standardError.write(Data("error: cannot read \(masterURL.path)\n".utf8))
    exit(1)
}
guard master.width == master.height else {
    FileHandle.standardError.write(Data("error: the master must be square\n".utf8))
    exit(1)
}

/// A superellipse |x|^n + |y|^n = 1 filling `rect`; n = 5 is close to Apple's icon shape.
func superellipse(in rect: CGRect, exponent n: CGFloat = 5, steps: Int = 720) -> CGPath {
    let path = CGMutablePath()
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = copysign(pow(abs(c), 2 / n), c), y = copysign(pow(abs(s), 2 / n), s)
        let point = CGPoint(x: rect.midX + x * rect.width / 2, y: rect.midY + y * rect.height / 2)
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

func render(pixels size: Int) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let scale = CGFloat(size) / 1024
    let body = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let shape = superellipse(in: body)

    // Soft shadow under the body (CG's origin is bottom-left, so "down" is a negative y offset).
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 20 * scale,
                      color: CGColor(gray: 0, alpha: 0.3))
    context.addPath(shape)
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.addPath(shape)
    context.clip()
    context.draw(master, in: body)
    return context.makeImage()!
}

try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for factor in [1, 2] {
        let name = factor == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        let destinationURL = outURL.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            exit(1)
        }
        CGImageDestinationAddImage(destination, render(pixels: points * factor), nil)
        guard CGImageDestinationFinalize(destination) else { exit(1) }
    }
}
print("wrote \(outURL.path)")
