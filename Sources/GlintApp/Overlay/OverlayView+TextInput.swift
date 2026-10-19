import AppKit
import GlintCore

/// Typing into the text box being edited (FR-35), through the macOS text-input system, so dead
/// keys (⌥E then E), the accent menu and input methods all work.
///
/// `keyDown(with:)` hands keys to `interpretKeyEvents` only while a box is being edited, so none
/// of this runs otherwise. Offsets are UTF-16, as in `TextBox`. AppKit calls the protocol on the
/// main thread; `@preconcurrency` checks that at run time.
extension OverlayView: @preconcurrency NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        editText { $0.insert(Self.plainText(string), replacing: Self.range(replacementRange)) }
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(insertNewline(_:)), #selector(insertLineBreak(_:)),
             #selector(insertNewlineIgnoringFieldEditor(_:)):
            editText { $0.type("\n") }                        // Return inserts a line break
        case #selector(insertTab(_:)), #selector(insertTabIgnoringFieldEditor(_:)):
            editText { $0.type("\t") }
        case #selector(deleteBackward(_:)):
            editText { $0.deleteBackward() }
        case #selector(deleteForward(_:)):
            editText { $0.deleteForward() }
        case #selector(moveLeft(_:)):
            editText { $0.moveLeft() }
        case #selector(moveRight(_:)):
            editText { $0.moveRight() }
        case #selector(moveUp(_:)):
            editText { $0.moveUp() }
        case #selector(moveDown(_:)):
            editText { $0.moveDown() }
        case #selector(cancelOperation(_:)):
            handleEscape()                                    // Esc commits the text (FR-27)
        default:
            break                                             // other editing commands don't apply
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        editText {
            $0.setMarkedText(Self.plainText(string), selectedOffset: selectedRange.location,
                             replacing: Self.range(replacementRange))
        }
    }

    func unmarkText() {
        editText { $0.unmarkText() }
    }

    func selectedRange() -> NSRange {
        guard let box = canvas.textBox else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: box.caret, length: 0)
    }

    func markedRange() -> NSRange {
        canvas.textBox?.markedRange ?? NSRange(location: NSNotFound, length: 0)
    }

    func hasMarkedText() -> Bool {
        canvas.textBox?.markedRange != nil
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let text = canvas.textBox?.text as NSString? else { return nil }
        let clipped = NSIntersectionRange(range, NSRange(location: 0, length: text.length))
        actualRange?.pointee = clipped
        return NSAttributedString(string: text.substring(with: clipped))
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    /// The overlay's level, so candidate windows and the accent menu open above it rather than
    /// at the floating level, behind the overlay.
    func windowLevel() -> Int {
        window?.level.rawValue ?? NSWindow.Level.screenSaver.rawValue
    }

    /// Where input-method windows (candidates, the accent menu) open: at the caret, in screen
    /// coordinates.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let box = canvas.textBox, let layout = textLayout, let window else { return .zero }
        let caret = layout.caretRect(at: min(max(range.location, 0), box.text.utf16.count))
        actualRange?.pointee = NSRange(location: range.location, length: 0)
        let model = caret.offsetBy(dx: box.origin.x, dy: box.origin.y)
        return window.convertToScreen(convert(flip.rect(model), to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        guard let box = canvas.textBox, let layout = textLayout, let window else { return NSNotFound }
        let local = flip.point(convert(window.convertPoint(fromScreen: point), from: nil))
        return layout.offset(at: CGPoint(x: local.x - box.origin.x, y: local.y - box.origin.y))
    }

    private static func plainText(_ string: Any) -> String {
        (string as? NSAttributedString)?.string ?? string as? String ?? ""
    }

    /// The text system passes NSNotFound for "wherever the marked text or caret is".
    private static func range(_ range: NSRange) -> NSRange? {
        range.location == NSNotFound ? nil : range
    }
}
