# Changelog

All notable changes to Glint are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and Glint uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
