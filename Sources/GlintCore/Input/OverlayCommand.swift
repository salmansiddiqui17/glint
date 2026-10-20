/// The modifier keys overlay shortcuts look at. Caps Lock, Fn and the numeric-pad flag are ignored.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = KeyModifiers(rawValue: 1 << 0)
    public static let shift = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// The overlay's ⌘ shortcuts (§4.4).
///
/// Shortcuts match the character the key types in the current layout, with exact modifiers, like
/// menus. A key that types a non-Latin letter (Cyrillic, Greek and so on, on a layout without its
/// own ⌘ mapping) falls back to its QWERTY position, as menus do too. Accented Latin letters and
/// dead keys never fall back, so ⌘ö on Turkish F is not ⌘X.
public enum OverlayCommand: Equatable, Sendable {
    case copyText            // ⌘O (FR-46)
    case copy                // ⌘C (FR-43)
    case save                // ⌘S (FR-44)
    case close               // ⌘X (FR-27)
    case toggleFullDisplay   // ⌘A, ⌘F (FR-23)
    case redact              // ⌘B (FR-28)
    case undo                // ⌘Z (FR-39)
    case redo                // ⇧⌘Z (FR-39)
    case widerStroke         // ⌘+, ⌘=, ⌘ keypad + (FR-38)
    case narrowerStroke      // ⌘−, ⌘ keypad − (FR-38)
    case paste               // ⌘V, into a text box being edited (FR-35)

    /// ANSI key codes, for keys that type non-Latin letters.
    private static let keyByCode: [UInt16: String] = [
        0: "a", 1: "s", 3: "f", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 24: "=", 27: "-", 31: "o",
    ]

    /// The command for a key press, or nil when it is not an overlay shortcut.
    ///
    /// - Parameters:
    ///   - characters: what the key typed (`NSEvent.characters`). It honours layouts with their
    ///     own ⌘ mapping, such as "Dvorak – QWERTY ⌘" and Apple's Russian and Greek layouts.
    ///   - keyCode: the hardware key code, used when `characters` is a non-Latin letter.
    ///   - modifiers: the modifier keys held.
    public static func match(characters: String?, keyCode: UInt16, modifiers: KeyModifiers) -> OverlayCommand? {
        guard modifiers.contains(.command), modifiers.isDisjoint(with: [.option, .control]),
              let typed = characters?.lowercased(), !typed.isEmpty else { return nil }
        let key = typed.unicodeScalars.allSatisfy(\.isASCII) ? typed : isNonLatin(typed) ? keyByCode[keyCode] : nil
        let shift = modifiers.contains(.shift)
        switch (key, shift) {
        case ("o", false): return .copyText
        case ("c", false): return .copy
        case ("s", false): return .save
        case ("x", false): return .close
        case ("a", false), ("f", false): return .toggleFullDisplay
        case ("b", false): return .redact
        case ("z", false): return .undo
        case ("z", true): return .redo
        case ("v", false): return .paste
        case ("=", _), ("+", _): return .widerStroke     // ⌘+ is ⇧⌘= on many layouts
        case ("-", false): return .narrowerStroke
        default: return nil
        }
    }

    /// Whether `text` holds a letter outside the Latin script. Latin letters, accented ones
    /// included, sit below U+0250 or in Latin Extended Additional.
    private static func isNonLatin(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            scalar.properties.isAlphabetic && scalar.value >= 0x250 && !(0x1E00...0x1EFF).contains(scalar.value)
        }
    }
}
