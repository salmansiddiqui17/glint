import CoreGraphics
import Foundation

/// When to warm up Vision's text model (FR-46, OQ-18). The first recognition after a new build
/// is installed makes macOS compile the model for the Neural Engine, which took about 55 s; the
/// compiled model is then cached for that build, so Glint warms up once per build.
public enum TextRecognitionWarmUp {
    /// Identifies the running build, or nil if it can't be told apart from others. Local builds all
    /// carry the same version and build, so the key adds the executable's modification date, which
    /// changes whenever the binary is linked or signed and survives installing the app unchanged.
    public static func buildKey(version: String, build: String, executableModified: Date?) -> String? {
        guard let executableModified else { return nil }
        return "\(version) (\(build)) \(Int64(executableModified.timeIntervalSince1970.rounded(.down)))"
    }

    /// Whether to warm up: unless `currentBuild` is the build already warmed up. A build without
    /// a key is warmed up on every launch, which costs a fraction of a second once compiled.
    public static func isNeeded(warmedUpBuild: String?, currentBuild: String?) -> Bool {
        currentBuild == nil || warmedUpBuild != currentBuild
    }
}

extension TextRecognition {
    /// Why `warmUp()` failed, other than Vision's own errors.
    public enum WarmUpError: Error {
        /// The generated image couldn't be drawn.
        case noImage
        /// Vision answered but read nothing, so its text model may not have run.
        case nothingRead
    }

    /// The line `warmUpImage()` shows.
    static let warmUpText = "Ready to copy text"

    /// `warmUpText` in black on white, generated rather than captured: the warm-up never reads
    /// the screen (OQ-18).
    static func warmUpImage() -> CGImage? {
        let layout = TextLayout(text: warmUpText, fontSize: 32)
        let scale: CGFloat = 2
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
