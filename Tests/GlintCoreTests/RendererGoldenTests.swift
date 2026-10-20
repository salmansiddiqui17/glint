import CoreGraphics
import Testing
@testable import GlintCore

/// Each tool rendered at 1×, 2× and 3× and compared with its golden image (NFR-17). The display
/// is rendered offscreen with the scale passed in, so no display of that scale is needed.
struct RendererGoldenTests {
    static let scales: [CGFloat] = [1, 2, 3]
    /// The scene: 120 × 80 pt.
    static let size = CGSize(width: 120, height: 80)
    let red = RGBAColor(red: 0.9, green: 0.1, blue: 0.1)

    /// A diagonal colour gradient under translucent 10 pt squares, so redactions and the marker
    /// visibly change what is beneath them.
    func background(scale: CGFloat) -> CGImage {
        let width = Int(Self.size.width * scale), height = Int(Self.size.height * scale)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let gradient = CGGradient(colorSpace: space, colorComponents: [0.95, 0.6, 0.2, 1, 0.2, 0.4, 0.8, 1],
                                  locations: [0, 1], count: 2)!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
        context.setFillColor(CGColor(colorSpace: space, components: [1, 1, 1, 0.35])!)
        let square = 10 * scale
        for column in 0..<12 {
            for row in 0..<8 where (column + row) % 2 == 0 {
                context.fill(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square, width: square, height: square))
            }
        }
        return context.makeImage()!
    }

    func render(_ annotations: [Annotation], scale: CGFloat) throws -> CGImage {
        try #require(Renderer.renderSelection(background(scale: scale), scale: scale, annotations: annotations,
                                              selection: CGRect(origin: .zero, size: Self.size),
                                              standardResolution: false))
    }

    func scenes() -> [(name: String, annotations: [Annotation])] {
        let wavy = (0...20).map { CGPoint(x: 10 + CGFloat($0) * 5, y: 40 + 15 * sin(CGFloat($0) / 3)) }
        return [
            ("pencil", [.pencil(points: wavy, color: red, width: 3)]),
            ("line", [.line(from: CGPoint(x: 10, y: 70), to: CGPoint(x: 110, y: 10), color: red, width: 4)]),
            ("arrow", [.arrow(from: CGPoint(x: 10, y: 70), to: CGPoint(x: 110, y: 15), color: red, width: 3)]),
            ("ellipse", [.ellipse(CGRect(x: 15, y: 12, width: 90, height: 56), color: red, width: 3)]),
            ("rectangle", [.rectangle(CGRect(x: 15.5, y: 12.5, width: 89, height: 55), color: red, width: 5)]),
            ("marker", [.marker(points: wavy, color: RGBAColor(red: 1, green: 0.9, blue: 0), width: 12)]),
            ("redact-pixelate", [.redaction(CGRect(x: 13, y: 9, width: 81, height: 53), style: .pixelate, width: 3)]),
            ("redact-blur", [.redaction(CGRect(x: 13, y: 9, width: 81, height: 53), style: .blur, width: 3)]),
        ]
    }

    @Test(arguments: scales)
    func shapesAndRedactionsMatchTheirGoldens(scale: CGFloat) throws {
        for scene in scenes() {
            try GoldenImages.check(try render(scene.annotations, scale: scale), named: "\(scene.name)@\(Int(scale))x")
        }
    }

    @Test(.enabled(if: GoldenImages.hasTextGoldens, "No text goldens for this macOS version"), arguments: scales)
    func textMatchesItsGolden(scale: CGFloat) throws {
        let text = TextAnnotation(origin: CGPoint(x: 8, y: 10), string: "Glint 42\nÅgé ✓", fontSize: 24, color: red)
        try GoldenImages.check(try render([.text(text)], scale: scale), named: "text@\(Int(scale))x", text: true)
    }
}
