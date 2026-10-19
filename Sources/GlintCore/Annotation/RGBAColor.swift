import CoreGraphics

/// An annotation colour as sRGB components, each 0…1 (FR-37).
///
/// Colours from any colour space, including greyscale and catalogue colours, are converted to RGB
/// on the way in, so every tool (the marker's translucency, redaction) can draw them.
public struct RGBAColor: Equatable, Hashable, Sendable {
    public let red: CGFloat
    public let green: CGFloat
    public let blue: CGFloat
    public let alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        func unit(_ value: CGFloat) -> CGFloat { value.isFinite ? min(max(value, 0), 1) : 0 }
        self.red = unit(red)
        self.green = unit(green)
        self.blue = unit(blue)
        self.alpha = unit(alpha)
    }

    /// The default annotation colour: pure red (FR-37).
    public static let red = RGBAColor(red: 1, green: 0, blue: 0)

    /// `color` converted to sRGB, or nil when it has no RGB equivalent (a pattern, for example).
    public init?(_ color: CGColor) {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count == 4 else { return nil }
        self.init(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public func withAlpha(_ alpha: CGFloat) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// `[red, green, blue, alpha]`, as stored in preferences (FR-47: sRGB components, not an
    /// archived object).
    public var components: [Double] {
        [red, green, blue, alpha].map(Double.init)
    }

    /// Reads stored components; nil unless there are exactly four.
    public init?(components: [Double]) {
        guard components.count == 4 else { return nil }
        self.init(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }
}
