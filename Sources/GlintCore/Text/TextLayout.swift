import CoreGraphics
import CoreText
import Foundation

/// Lays out and draws annotation text (FR-35) with Core Text: Verdana (or the system font when
/// Verdana is missing), one line per "\n", no wrapping.
///
/// The live overlay and the export both draw through `draw(in:at:color:)`, so committed text
/// lands exactly where it was while being edited. Coordinates are points relative to the box's
/// top-left corner, y growing downward.
///
/// Immutable once made, and Core Text lines are safe to share between threads, hence the
/// unchecked `Sendable` (the canvas keeps the edited box's layout).
public struct TextLayout: @unchecked Sendable {
    public let fontSize: CGFloat
    /// Distance from the top of a line to its baseline.
    public let ascent: CGFloat
    /// Height of every line: the font's ascent + descent + leading.
    public let lineHeight: CGFloat
    /// Width of the widest line (including trailing spaces) by the number of lines.
    public let size: CGSize
    private let lines: [CTLine]
    /// UTF-16 offset where each line starts in the text.
    private let lineStarts: [Int]
    /// The font's underline: how far below the baseline, and how thick.
    private let underlineOffset: CGFloat
    private let underlineThickness: CGFloat

    public init(text: String, fontSize: CGFloat) {
        self.fontSize = fontSize
        let font = Self.font(size: fontSize)
        ascent = CTFontGetAscent(font)
        lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        underlineOffset = -CTFontGetUnderlinePosition(font)
        underlineThickness = max(CTFontGetUnderlineThickness(font), 0.5)

        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): Self.paragraphStyle(tabInterval: fontSize * 2),
        ]
        var starts: [Int] = []
        var offset = 0
        lines = text.components(separatedBy: "\n").map { line in
            starts.append(offset)
            offset += line.utf16.count + 1
            return CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
        }
        lineStarts = starts
        let width = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        size = CGSize(width: width, height: CGFloat(lines.count) * lineHeight)
    }

    /// Verdana at `size`, or the system font when Verdana is not installed.
    public static func font(size: CGFloat) -> CTFont {
        let verdana = CTFontCreateWithName("Verdana" as CFString, size, nil)
        if CTFontCopyFamilyName(verdana) as String == "Verdana" { return verdana }
        return CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    /// Tab stops every `tabInterval` points (FR-35: Tab inserts a tab).
    private static func paragraphStyle(tabInterval: CGFloat) -> CTParagraphStyle {
        var interval = tabInterval
        var noFixedStops = [] as CFArray
        return withUnsafePointer(to: &interval) { interval in
            withUnsafePointer(to: &noFixedStops) { stops in
                let settings = [
                    CTParagraphStyleSetting(spec: .defaultTabInterval, valueSize: MemoryLayout<CGFloat>.size,
                                            value: interval),
                    CTParagraphStyleSetting(spec: .tabStops, valueSize: MemoryLayout<CFArray>.size, value: stops),
                ]
                return CTParagraphStyleCreate(settings, settings.count)
            }
        }
    }

    /// The caret's line box at `offset`: x is the caret position, the height is one line.
    public func caretRect(at offset: Int) -> CGRect {
        let line = lineIndex(containing: offset)
        let x = CTLineGetOffsetForStringIndex(lines[line], offset - lineStarts[line], nil)
        return CGRect(x: x, y: CGFloat(line) * lineHeight, width: 0, height: lineHeight)
    }

    /// The text offset nearest to `point`.
    public func offset(at point: CGPoint) -> Int {
        let line = min(max(Int((point.y / lineHeight).rounded(.down)), 0), lines.count - 1)
        let index = CTLineGetStringIndexForPosition(lines[line], CGPoint(x: point.x, y: 0))
        return lineStarts[line] + (index == kCFNotFound ? 0 : index)
    }

    /// One underline per line covered by `range`, where the font puts its underline (for marked
    /// text). It spans every caret position in the range, so right-to-left runs are covered too.
    public func underlines(for range: NSRange) -> [CGRect] {
        lines.indices.compactMap { line in
            let start = lineStarts[line]
            let end = start + CTLineGetStringRange(lines[line]).length
            let lower = max(range.location, start), upper = min(NSMaxRange(range), end)
            guard lower < upper else { return nil }
            let xs = (lower...upper).map { CTLineGetOffsetForStringIndex(lines[line], $0 - start, nil) }
            let x0 = xs.min() ?? 0, x1 = xs.max() ?? 0
            let y = CGFloat(line) * lineHeight + ascent + underlineOffset - underlineThickness / 2
            return CGRect(x: x0, y: y, width: x1 - x0, height: underlineThickness)
        }
    }

    /// Draws the text with its top-left at `origin` in a context whose user space is top-left-origin
    /// points (y down), as the renderer and the overlay's text bitmap both set up.
    public func draw(in context: CGContext, at origin: CGPoint, color: RGBAColor) {
        context.saveGState()
        let savedTextMatrix = context.textMatrix   // not part of the graphics state
        defer {
            context.textMatrix = savedTextMatrix
            context.restoreGState()
        }
        context.setFillColor(color.cgColor)
        context.setAllowsFontSmoothing(false)   // same glyph pixels on any background
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)   // glyphs upright in a y-down space
        // Only the lines that can reach the drawable area, so a long text draws what is visible.
        let drawable = context.boundingBoxOfClipPath.standardized.offsetBy(dx: -origin.x, dy: -origin.y)
        for index in lineIndices(near: drawable) {
            context.textPosition = CGPoint(x: origin.x, y: origin.y + ascent + CGFloat(index) * lineHeight)
            CTLineDraw(lines[index], context)
        }
    }

    /// The text alone on a transparent sRGB bitmap at `scale` pixels per point, for the live
    /// overlay, or nil when the text is empty or none of it is visible.
    ///
    /// The bitmap covers the line boxes with a margin of a quarter of the font size, grown to any
    /// ink beyond that (stacked accents), so nothing is clipped that the export would draw.
    /// `visible`, relative to the box's top-left, limits it to what can be seen (the display):
    /// a huge pasted text never needs a huge bitmap. `frame` is where the bitmap goes, relative
    /// to the box's top-left, on whole pixels.
    public func image(scale: CGFloat, color: RGBAColor, visible: CGRect? = nil) -> (image: CGImage, frame: CGRect)? {
        guard size.width > 0 else { return nil }
        var area = inkFrame(near: visible)
        if let visible { area = area.intersection(visible) }
        guard !area.isNull, area.width > 0, area.height > 0 else { return nil }
        // Out to whole pixels, so the bitmap's pixels line up with the display's.
        let minX = (area.minX * scale).rounded(.down), minY = (area.minY * scale).rounded(.down)
        let maxX = (area.maxX * scale).rounded(.up), maxY = (area.maxY * scale).rounded(.up)
        let width = Int(maxX - minX), height = Int(maxY - minY)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -minX / scale, y: -minY / scale)
        draw(in: context, at: .zero, color: color)
        guard let image = context.makeImage() else { return nil }
        return (image, CGRect(x: minX / scale, y: minY / scale, width: CGFloat(width) / scale,
                              height: CGFloat(height) / scale))
    }

    /// Everything the glyphs can cover, relative to the box's top-left: the line boxes with a
    /// quarter-font-size margin, grown to the actual ink of each line that can reach `visible`
    /// (every line when nil), so a long pasted text only measures what is on screen.
    private func inkFrame(near visible: CGRect?) -> CGRect {
        var frame = CGRect(origin: .zero, size: size).insetBy(dx: -fontSize / 4, dy: -fontSize / 4)
        for index in lineIndices(near: visible) {
            let line = lines[index]
            let ink = CTLineGetImageBounds(line, nil)
            guard !ink.isNull, ink.width > 0, ink.height > 0 else { continue }
            let baseline = ascent + CGFloat(index) * lineHeight
            // 1 pt beyond the outlines, for anti-aliasing.
            frame = frame.union(CGRect(x: ink.minX, y: baseline - ink.maxY, width: ink.width, height: ink.height)
                .insetBy(dx: -1, dy: -1))
        }
        return frame
    }

    /// The lines whose box, grown by two line heights each way, meets `rect`: ink never reaches
    /// that far beyond its line (every line when `rect` is nil or unbounded).
    private func lineIndices(near rect: CGRect?) -> Range<Int> {
        guard let rect, !rect.isNull, rect.minY.isFinite, rect.maxY.isFinite, lineHeight > 0 else { return lines.indices }
        func line(_ y: CGFloat) -> Int { Int(min(max(y / lineHeight, -2), CGFloat(lines.count + 2))) }
        let first = max(line(rect.minY) - 2, 0)
        let last = min(line(rect.maxY) + 3, lines.count)
        return first..<max(last, first)
    }

    private func lineIndex(containing offset: Int) -> Int {
        lineStarts.lastIndex { $0 <= offset } ?? 0
    }
}
