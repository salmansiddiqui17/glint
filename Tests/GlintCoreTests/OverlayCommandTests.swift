import Testing
@testable import GlintCore

struct OverlayCommandTests {
    func match(_ characters: String?, code: UInt16 = 0xFFFF, _ modifiers: KeyModifiers = .command) -> OverlayCommand? {
        OverlayCommand.match(characters: characters, keyCode: code, modifiers: modifiers)
    }

    @Test(arguments: [
        ("o", OverlayCommand.copyText), ("c", .copy), ("s", .save), ("x", .close), ("a", .toggleFullDisplay),
        ("f", .toggleFullDisplay), ("b", .redact), ("z", .undo), ("v", .paste),
        ("=", .widerStroke), ("+", .widerStroke), ("-", .narrowerStroke),
    ])
    func commandLetters(characters: String, command: OverlayCommand) {
        #expect(match(characters) == command)
    }

    @Test func shiftCommandZRedoes() {
        #expect(match("Z", [.command, .shift]) == .redo)
        #expect(match("z", [.command, .shift]) == .redo)
    }

    @Test func shiftCommandEqualsWidens() {
        #expect(match("+", [.command, .shift]) == .widerStroke)   // ⌘+ on a US keyboard
    }

    @Test func extraModifiersDoNotMatch() {
        #expect(match("c", [.command, .option]) == nil)
        #expect(match("c", [.command, .control]) == nil)
        #expect(match("c", [.command, .shift]) == nil)
        #expect(match("s", [.command, .shift]) == nil)
        #expect(match("-", [.command, .shift]) == nil)
        #expect(match("o", [.command, .shift]) == nil)
    }

    @Test func needsCommand() {
        #expect(match("c", []) == nil)
        #expect(match("z", .shift) == nil)
    }

    @Test func unknownKeysDoNotMatch() {
        #expect(match("q") == nil)
        #expect(match(nil) == nil)
        #expect(match("") == nil)
    }

    @Test func appleNonLatinLayoutsTypeQWERTYLettersWithCommand() {
        #expect(match("c", code: 8) == .copy)        // Russian: ⌘ on the C key types "c"
        #expect(match("Z", code: 6, [.command, .shift]) == .redo)
    }

    @Test func layoutsWithoutACommandMapFallBackToTheQWERTYKey() {
        #expect(match("с", code: 8) == .copy)        // Cyrillic "es" on the C key
        #expect(match("ψ", code: 6) == .undo)        // Greek, Z key
        #expect(match("я", code: 6, [.command, .shift]) == .redo)
        #expect(match("и", code: 11) == .redact)
        #expect(match("щ", code: 31) == .copyText)   // Russian, O key
    }

    @Test func accentedLatinKeysAndDeadKeysNeverFallBack() {
        #expect(match("ö", code: 7) == nil)          // Turkish F: must not close the capture
        #expect(match("ç", code: 11) == nil)
        #expect(match("ß", code: 27) == nil)         // German
        #expect(match("´", code: 24) == nil)
        #expect(match("", code: 24) == nil)          // a dead key types nothing
    }

    @Test func capsLockDoesNotMatter() {
        #expect(match("C") == .copy)
    }

    @Test func keypadPlusAndMinusChangeTheWidth() {
        #expect(match("+", code: 69) == .widerStroke)
        #expect(match("-", code: 78) == .narrowerStroke)
    }

    @Test func layoutCharacterWinsOverKeyPosition() {
        #expect(match("j", code: 8) == nil)          // Dvorak: the QWERTY C key types "j"
        #expect(match("c", code: 34) == .copy)       // Dvorak: "c" is on the QWERTY I key
        #expect(match("-", code: 24) == .narrowerStroke)   // French: "-" is where QWERTY has "="
        #expect(match("=", code: 44) == .widerStroke)
        #expect(match(")", code: 27) == nil)
    }
}
