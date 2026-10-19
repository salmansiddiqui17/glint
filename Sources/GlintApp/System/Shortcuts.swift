import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The global capture hotkey (FR-6). ⇧⌘9 is written once as the initial value (on first access,
    /// which AppDelegate does at launch); after that the user's choice wins, and clearing it is
    /// stored as "disabled", so it survives relaunch (FR-8). Stored by KeyboardShortcuts under the
    /// defaults key `KeyboardShortcuts_captureScreenshot`.
    ///
    /// Always clear or reset through this name (e.g. `KeyboardShortcuts.reset(.captureScreenshot)`).
    /// Names rebuilt from a raw value (`resetAll()`, `Name(rawValue:)`) have no initial value, so
    /// clearing through them deletes the key and ⇧⌘9 would come back at the next launch.
    static let captureScreenshot = Self("captureScreenshot", initial: .init(.nine, modifiers: [.command, .shift]))
}
