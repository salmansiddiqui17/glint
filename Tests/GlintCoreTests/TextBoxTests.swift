import CoreGraphics
import Foundation
import Testing
@testable import GlintCore

struct TextBoxTests {
    func box(_ text: String = "") -> TextBox {
        var box = TextBox(origin: CGPoint(x: 10, y: 20), fontSize: 24, color: .red)
        if !text.isEmpty { box.insert(text) }
        return box
    }

    // MARK: Typing

    @Test func typingInsertsAtTheCaret() {
        var b = box("helo")
        b.moveLeft()
        b.insert("l")
        #expect(b.text == "hello" && b.caret == 4)
    }

    @Test func returnAndTabInsertLineBreaksAndTabs() {
        var b = box("a")
        b.type("\n")
        b.type("\t")
        b.type("b")
        #expect(b.text == "a\n\tb")
    }

    @Test func everyKindOfLineBreakIsNormalised() {
        #expect(box("one\r\ntwo\rthree").text == "one\ntwo\nthree")
        #expect(box("a\u{2028}b\u{2029}c").text == "a\nb\nc")     // line and paragraph separators
        var b = box()
        b.setMarkedText("x\ry", selectedOffset: 3)
        #expect(b.text == "x\ny" && b.markedRange == NSRange(location: 0, length: 3))
    }

    @Test func insertReplacesAGivenRange() {
        var b = box("hello")
        b.insert("J", replacing: NSRange(location: 0, length: 1))
        #expect(b.text == "Jello" && b.caret == 1)
        b.insert("!", replacing: NSRange(location: 99, length: 5))   // out of range: clamped to the end
        #expect(b.text == "Jello!")
    }

    // MARK: Whole characters

    @Test func deletingRemovesWholeCharacters() {
        var b = box("a👍🏽é")
        b.deleteBackward()
        #expect(b.text == "a👍🏽")
        b.deleteBackward()
        #expect(b.text == "a" && b.caret == 1)
        b.moveLeft()
        b.deleteForward()
        #expect(b.text.isEmpty && b.caret == 0)
        b.deleteBackward()
        b.deleteForward()
        #expect(b.text.isEmpty)
    }

    @Test func decomposedAccentsFlagsAndZWJSequencesAreOneCharacter() {
        var accent = box("e\u{301}\u{323}")                          // e + acute + dot below
        accent.deleteBackward()
        #expect(accent.text.isEmpty)
        var family = box("👨‍👩‍👧x")
        family.moveLeft()
        family.moveLeft()
        #expect(family.caret == 0)
        var flags = box("🇸🇪🇫🇮")
        flags.moveLeft()
        #expect(flags.caret == 4)
    }

    @Test func caretMovesByWholeCharactersAndStopsAtTheEnds() {
        var b = box("👍🏽x")
        b.moveLeft()
        #expect(b.caret == 4)          // the emoji with its skin tone is 4 UTF-16 units
        b.moveLeft()
        b.moveLeft()
        #expect(b.caret == 0)
        b.moveRight()
        #expect(b.caret == 4)
        b.moveCaret(to: 2)             // inside the emoji: back to its start
        #expect(b.caret == 0)
        b.moveCaret(to: 99)
        #expect(b.caret == 5)
    }

    @Test func textThatMergesWithTheNextCharacterPutsTheCaretAfterIt() {
        var accent = box("\u{301}")                                   // a lone combining acute
        accent.moveLeft()
        accent.insert("e")                                            // now "é", one character
        #expect(accent.text == "e\u{301}" && accent.caret == 2)
        accent.deleteForward()                                        // nothing after the caret
        accent.moveLeft()
        accent.deleteForward()
        #expect(accent.text.isEmpty && accent.caret == 0)
        var flag = box("🇸")
        flag.moveLeft()
        flag.insert("🇺")                                             // "🇺🇸", one flag
        #expect(flag.caret == 4)
        flag.moveLeft()
        #expect(flag.caret == 0)
    }

    @Test func caretAlwaysStaysBetweenCharactersWithinTheText() {
        let pieces = ["a", "\u{301}", "🇸", "🇺", "👍", "🏽", "\n", "é", "日", "\u{200D}"]
        var b = box()
        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        for _ in 0..<3000 {
            switch next(10) {
            case 0, 1: b.insert(pieces[next(pieces.count)])
            case 2: b.setMarkedText(pieces[next(pieces.count)], selectedOffset: next(3))
            case 3: b.deleteBackward()
            case 4: b.deleteForward()
            case 5: b.moveLeft()
            case 6: b.moveRight()
            case 7: b.moveUp()
            case 8: b.moveDown()
            default: b.moveCaret(to: next(b.text.utf16.count + 2))
            }
            let text = b.text as NSString
            let onBoundary = b.caret == text.length || text.rangeOfComposedCharacterSequence(at: b.caret).location == b.caret
            if !(0...text.length).contains(b.caret) || !onBoundary {
                Issue.record("caret \(b.caret) is not a character boundary in \(b.text.debugDescription)")
                return
            }
        }
    }

    // MARK: Lines

    @Test func upAndDownKeepTheColumnTheyStartedFrom() {
        var b = box("abcd\nxy\nlonger")
        b.moveCaret(to: 3)             // "abc|d"
        b.moveDown()
        #expect(b.caret == 7)          // end of "xy"
        b.moveDown()
        #expect(b.caret == 11)         // back to column 3, in "longer"
        b.moveDown()
        #expect(b.caret == 14)         // past the last line: the end
        b.moveUp()
        #expect(b.caret == 7)          // column 6 is past the end of "xy"
        b.moveUp()
        #expect(b.caret == 4)          // still aiming for column 6: the end of "abcd"
        b.moveUp()
        #expect(b.caret == 0)
    }

    @Test func columnsCountCharactersNotCodeUnits() {
        var b = box("👍🏽👍🏽\nabcdefghij")
        b.moveCaret(to: 8)             // after the second emoji: column 2
        b.moveDown()
        #expect(b.caret == 11)         // "ab|cdefghij"
    }

    @Test func upAndDownAreSafeInEmptyAndBlankBoxes() {
        var empty = box()
        empty.moveUp()
        empty.moveDown()
        #expect(empty.caret == 0)
        var blank = box("\n\n\n")
        blank.moveUp()
        #expect(blank.caret == 2)
        blank.moveUp()
        blank.moveUp()
        blank.moveUp()
        #expect(blank.caret == 0)
        blank.moveDown()
        #expect(blank.caret == 1)
        var marked = box("ab\n\u{301}c\nx")                         // the second line starts with a lone accent
        marked.moveCaret(to: 0)
        marked.moveDown()
        #expect(marked.caret == 4)                                    // into that line, not stuck above it
        marked.moveDown()
        #expect(marked.caret == 6)                                    // still column 0: the start of "x"
    }

    // MARK: Composition

    @Test func markedTextIsReplacedThenAccepted() {
        var b = box("a")
        b.setMarkedText("´", selectedOffset: 1)          // ⌥E
        #expect(b.text == "a´" && b.markedRange == NSRange(location: 1, length: 1) && b.caret == 2)
        b.insert("é")                                     // then E
        #expect(b.text == "aé" && b.markedRange == nil && b.caret == 2)
    }

    @Test func pressAndHoldReplacesTheTypedLetter() {
        var b = box("hle")
        b.setMarkedText("e", selectedOffset: 1, replacing: NSRange(location: 2, length: 1))
        #expect(b.markedRange == NSRange(location: 2, length: 1))
        b.insert("é")
        #expect(b.text == "hlé" && b.caret == 3 && b.markedRange == nil)
    }

    @Test func markedTextKeptAsTypedWhenUnmarked() {
        var b = box()
        b.setMarkedText("にほ", selectedOffset: 2)
        b.setMarkedText("日本", selectedOffset: 2)
        b.unmarkText()
        #expect(b.text == "日本" && b.markedRange == nil)
        b.setMarkedText("", selectedOffset: 0)
        #expect(b.markedRange == nil && b.text == "日本")
    }

    @Test func typingOutsideTheInputMethodKeepsTheComposition() {
        var b = box("a")
        b.setMarkedText("にほ", selectedOffset: 2)
        b.type("X")                                       // paste, Return or Tab mid-composition
        #expect(b.text == "aにほX" && b.markedRange == nil && b.caret == 4)
    }

    @Test func movingOrDeletingEndsTheComposition() {
        var b = box("a")
        b.setMarkedText("に", selectedOffset: 1)
        b.moveLeft()
        #expect(b.markedRange == nil && b.text == "aに")
        b.setMarkedText("ほ", selectedOffset: 1)
        b.deleteForward()
        #expect(b.markedRange == nil)
    }

    // MARK: Committing

    @Test func emptyOrBlankBoxHasNoAnnotation() {
        #expect(box().annotation == nil)
        #expect(box(" \n\t").annotation == nil)
        #expect(box("hi").annotation == .text(TextAnnotation(origin: CGPoint(x: 10, y: 20), string: "hi",
                                                             fontSize: 24, color: .red)))
    }
}
