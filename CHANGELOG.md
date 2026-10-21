# Changelog

All notable changes to Glint are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Glint uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **Window snapping**, optional and off by default: turn it on in Preferences with **Select windows by clicking**. With it on, before you make a selection, the window under the pointer is highlighted; click to select exactly that window, or click the desktop for the whole display. Dragging still makes a free selection, and clicking outside a selection selects the window under the pointer instead. Snapping is off while a drawing tool is selected. A window counts only if at least 40 × 40 pt of it is on that display. After a click selects the whole display, ⌘A, ⌘F or a double-click inside clears the selection, so you can pick a window again.
- **Copy Text**, optional and off by default: turn it on in Preferences with **Copy text from screenshots**, or in the first-run window. With it on, ⌘O or the new button in the toolbar under the selection recognises the text in the selection, on your Mac, and copies it as plain text. Redacted areas are never read. If there is no text, the overlay says "No text found" and stays open; if the text can't be read, it says "Couldn't read text". Esc or ⌘X while it reads stops it and closes the capture. With it off, the toolbar is Copy, Save, Close, ⌘O does nothing, and Glint never loads text recognition.
- When you turn Copy Text on, and on the first launch after you install or update Glint with it on, Glint prepares text recognition in the background, so the first **Copy Text** is quick. If you use it straight away, it may take up to 45 seconds, says so after 10 seconds, and if it runs out of time asks you to try again.
- **About Glint** in the menu-bar menu: version, copyright and acknowledgements.
- **VoiceOver.** The overlay speaks the selection's size once it settles, and the Colour button reads out the current colour.

### Changed
- Pixelate redactions use far less memory and look the same. A redaction completely covered by a later one frees its memory until the later one is undone.
- Larger redactions are obscured more strongly, so text of any size beneath them can't be read.
- Redact: dragging along a line of text now redacts it. A Redact box thinner than the band (6 × the stroke width) is made that thick, and before you drag, the pointer shows the band's size.
- Glint is ready to be translated: all its text is now in one String Catalog.

## [0.1.1] - 2026-10-19

### Fixed
- **Grant Access…** no longer opens System Settings at the same moment as the macOS permission prompt. The Screen Recording row now has separate **Grant Access…**, **Open Settings…** and **Relaunch** buttons, with a hint for a stale permission entry after an update.

## [0.1.0] - 2026-10-19

The first public version: capture and the annotation editor.

### Capture
- Menu-bar app with a global capture hotkey (⇧⌘9 by default, changeable in Preferences).
- Freezes every display at once and dims it, with a single selection across all of them.
- Selection with eight resize handles, a live pixel-size badge, arrow-key nudging (⇧ to resize) and ⌘A for the whole display.
- Copy (⌘C or Return) puts a PNG on the clipboard; Save (⌘S) writes PNG or JPEG and remembers the folder.
- Exports at full Retina resolution, or at 1× with "Save at standard resolution", keeping the display's colour profile and DPI.
- Launch at login, onboarding for the Screen Recording permission, and a single running instance.

### Editor
- Tools palette beside the selection: Pencil, Line, Arrow, Ellipse, Rectangle, Marker, Text and Redact, plus Colour, Undo and Redo.
- ⇧ constrains shapes: 45° lines and arrows, squares and circles.
- Stroke width from 3 to 50 (scroll, or ⌘+ / ⌘−) with a brush preview. Colour and width are remembered across captures and launches.
- Text boxes in Verdana with line breaks, tabs, paste, scroll-to-resize, and full input-method support (dead keys, the accent menu, Japanese and Chinese input).
- Redact (⌘B) pixelates or blurs. A redaction that can't be produced blocks the export rather than leaking the original pixels.
- Undo and redo for every annotation. Esc works in stages: cancel the shape, then leave the tool, then close the capture.
- Keyboard shortcuts work on non-Latin layouts (Russian, Greek) and on layouts with their own ⌘ mapping (Dvorak – QWERTY ⌘).

### Privacy
- Sandboxed, with no network entitlement. Nothing leaves your Mac.

[Unreleased]: https://github.com/salmansiddiqui17/glint/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/salmansiddiqui17/glint/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/salmansiddiqui17/glint/releases/tag/v0.1.0
