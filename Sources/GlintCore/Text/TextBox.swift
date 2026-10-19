import CoreGraphics
import Foundation

/// A text box being edited (FR-35): its text, caret and any marked (uncommitted input-method) text.
///
/// Offsets are UTF-16 code units, as in `NSRange` and the macOS text-input protocol. Lines are
/// separated by "\n"; Return and Tab type "\n" and "\t". There is no text selection: the caret
/// moves by whole characters (an emoji or accented letter is one step) and always sits between
/// characters, within the text.
public struct TextBox: Equatable, Sendable {
    /// Top-left of the first line, in display points.
    public var origin: CGPoint
    public var fontSize: CGFloat
    public var color: RGBAColor
    public private(set) var text = ""
    /// Always between characters: an edit can regroup the characters around it (a combining mark
    /// joining a line break, regional-indicator letters pairing into a different flag), so every
    /// move lands on the start of the character it would fall inside.
    public private(set) var caret = 0 {
        didSet {
            let length = text.utf16.count
            caret = min(max(caret, 0), length)
            if caret > 0, caret < length { caret = characterRange(at: caret).location }
        }
    }
    /// Text the input method is still composing (for example while typing Japanese, or after
    /// ⌥E on its way to "é"). It is part of `text` and is kept as typed if editing ends.
    public private(set) var markedRange: NSRange?
    /// The column, in characters, that ↑ and ↓ aim for, kept while they pass shorter lines.
    private var goalColumn: Int?

    public init(origin: CGPoint, fontSize: CGFloat, color: RGBAColor) {
        self.origin = origin
        self.fontSize = fontSize
        self.color = color
    }

    private var length: Int { text.utf16.count }

    /// The committed annotation, or nil for a box with nothing visible in it (FR-35 AC: an empty
    /// box adds no undo step, and nor does one holding only spaces, tabs or line breaks).
    public var annotation: Annotation? {
        text.allSatisfy(\.isWhitespace)
            ? nil
            : .text(TextAnnotation(origin: origin, string: text, fontSize: fontSize, color: color))
    }

    // MARK: Typing

    /// Typing that doesn't come from the input method (paste, Return, Tab): ends any
    /// composition first, then inserts at the caret.
    public mutating func type(_ string: String) {
        unmarkText()
        insert(string)
    }

    /// The input method's text: inserts `string` in place of `range`, or of the marked text, or
    /// at the caret, and ends the composition. Every kind of line break becomes "\n".
    public mutating func insert(_ string: String, replacing range: NSRange? = nil) {
        let normalized = string.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        let target = clampedRange(range ?? markedRange ?? NSRange(location: caret, length: 0))
        replace(target, with: normalized)
        markedRange = nil
        // The new text can merge with the character after it (a combining accent, half a flag):
        // then the caret goes after the whole character.
        caret = boundary(after: target.location + normalized.utf16.count)
    }

    /// Shows the input method's composition `string` in place of `range`, or of the current
    /// marked text, or at the caret. `selectedOffset` is the caret's place inside `string`.
    public mutating func setMarkedText(_ string: String, selectedOffset: Int, replacing range: NSRange? = nil) {
        let marked = string.replacingOccurrences(of: "\r", with: "\n")   // same length, so offsets hold
        let target = clampedRange(range ?? markedRange ?? NSRange(location: caret, length: 0))
        replace(target, with: marked)
        let count = marked.utf16.count
        markedRange = count > 0 ? NSRange(location: target.location, length: count) : nil
        caret = boundary(after: target.location + min(max(selectedOffset, 0), count))
    }

    /// Accepts the marked text as typed.
    public mutating func unmarkText() {
        markedRange = nil
    }

    public mutating func deleteBackward() {
        unmarkText()
        guard caret > 0 else { return }
        let character = characterRange(at: caret - 1)
        replace(character, with: "")
        caret = character.location
    }

    public mutating func deleteForward() {
        unmarkText()
        guard caret < length else { return }
        let character = characterRange(at: caret)
        replace(character, with: "")
        caret = character.location
    }

    // MARK: Caret

    public mutating func moveLeft() {
        unmarkText()
        goalColumn = nil
        if caret > 0 { caret = characterRange(at: caret - 1).location }
    }

    public mutating func moveRight() {
        unmarkText()
        goalColumn = nil
        if caret < length { caret = NSMaxRange(characterRange(at: caret)) }
    }

    /// To the same column on the line above, or the start of the text on the first line. Columns
    /// count characters, and the column ↑/↓ started from is kept across shorter lines.
    public mutating func moveUp() {
        moveVertically(by: -1)
    }

    /// To the same column on the line below, or the end of the text on the last line.
    public mutating func moveDown() {
        moveVertically(by: 1)
    }

    /// Places the caret at `offset`, moved back to the start of the character it falls inside.
    public mutating func moveCaret(to offset: Int) {
        unmarkText()
        goalColumn = nil
        caret = offset
    }

    private mutating func moveVertically(by delta: Int) {
        unmarkText()
        let lines = text.components(separatedBy: "\n")
        var start = 0, line = 0
        while line < lines.count - 1, caret > start + lines[line].utf16.count {
            start += lines[line].utf16.count + 1
            line += 1
        }
        let column = goalColumn ?? (lines[line] as NSString).substring(to: caret - start).count
        let target = line + delta
        guard lines.indices.contains(target) else {
            caret = delta < 0 ? 0 : length
            goalColumn = nil
            return
        }
        let targetStart = lines[..<target].reduce(0) { $0 + $1.utf16.count + 1 }
        // Forwards to a whole character: a line starting with a combining mark joins it to the
        // line break before it, and snapping back there would never reach that line.
        caret = boundary(after: targetStart + lines[target].prefix(column).utf16.count)
        goalColumn = column
    }

    // MARK: Helpers

    private func clampedRange(_ range: NSRange) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(max(range.length, 0), length - location))
    }

    private func characterRange(at offset: Int) -> NSRange {
        (text as NSString).rangeOfComposedCharacterSequence(at: offset)
    }

    /// `offset`, or the end of the character it falls inside.
    private func boundary(after offset: Int) -> Int {
        guard offset > 0, offset < length else { return min(max(offset, 0), length) }
        let character = characterRange(at: offset)
        return character.location < offset ? NSMaxRange(character) : offset
    }

    /// Every edit forgets the ↑/↓ column.
    private mutating func replace(_ range: NSRange, with string: String) {
        text = (text as NSString).replacingCharacters(in: range, with: string)
        goalColumn = nil
    }
}
