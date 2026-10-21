import CoreGraphics
import Foundation

/// When to warm up Vision's text model (FR-46, OQ-18). The first recognition after a new build
/// is installed makes macOS compile the model for the Neural Engine, which took about 55 s; the
/// compiled model is then cached, so Glint warms up once per build and macOS version.
public enum TextRecognitionWarmUp {
    /// Identifies the running build on this macOS, or nil if the build can't be told apart from
    /// others. Local builds all carry the same version and build, so the key adds the executable's
    /// modification date, which changes whenever the binary is linked or signed and survives
    /// installing the app with ditto or Finder (a plain `cp -R` costs one extra warm-up). It also
    /// adds `operatingSystem` (the macOS version and build), since a macOS update most likely
    /// replaces Vision's models, so the compiled model is rebuilt.
    public static func buildKey(version: String, build: String, executableModified: Date?,
                                operatingSystem: String) -> String? {
        guard let executableModified else { return nil }
        let modified = Int64(executableModified.timeIntervalSince1970.rounded(.down))
        return "\(version) (\(build)) \(modified) on \(operatingSystem)"
    }

    /// Whether to warm up: only while Copy Text is turned on (`isEnabled`), since otherwise Glint
    /// never runs Vision (OQ-22), and unless `currentBuild` is the build, on this macOS, already
    /// warmed up. A build without a key is warmed up on every launch, which costs a fraction of a
    /// second once compiled.
    public static func isNeeded(isEnabled: Bool, warmedUpBuild: String?, currentBuild: String?) -> Bool {
        isEnabled && (currentBuild == nil || warmedUpBuild != currentBuild)
    }
}

extension TextRecognition {
    /// Why `warmUp()` failed, other than Vision's own errors.
    public enum WarmUpError: Error {
        /// The generated image couldn't be drawn.
        case noImage
        /// Vision answered but read nothing. An empty result counts as a failure, so the next
        /// launch tries again.
        case nothingRead
    }

    /// The line `warmUpImage()` shows.
    static let warmUpText = "Ready to copy text"

    /// `warmUpText` in black on white, generated rather than captured: the warm-up never reads
    /// the screen (OQ-18).
    static func warmUpImage() -> CGImage? {
        image(of: warmUpText)
    }

    /// `text` in black on white, `fontSize` points at `scale`, with a 20 pt margin.
    static func image(of text: String, fontSize: CGFloat = 32, scale: CGFloat = 2) -> CGImage? {
        let layout = TextLayout(text: text, fontSize: fontSize)
        let margin: CGFloat = 20
        guard let context = CGContext(data: nil, width: Int((layout.size.width + 2 * margin) * scale),
                                      height: Int((layout.size.height + 2 * margin) * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        // Top-left-origin points, as the renderer draws annotations.
        context.translateBy(x: 0, y: CGFloat(context.height))
        context.scaleBy(x: scale, y: -scale)
        layout.draw(in: context, at: CGPoint(x: margin, y: margin), color: RGBAColor(red: 0, green: 0, blue: 0, alpha: 1))
        return context.makeImage()
    }

    /// Recognises a small generated image with Copy Text's request, so macOS prepares Vision's
    /// text model before the user needs it (FR-46, OQ-18). Throws if Vision fails or reads nothing.
    public static func warmUp() async throws {
        guard let image = warmUpImage() else { throw WarmUpError.noImage }
        let text = try await recognizeText(in: image)
        guard !text.isEmpty else { throw WarmUpError.nothingRead }
    }
}
