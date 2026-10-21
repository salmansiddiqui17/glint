<div align="center">

<img src="Resources/Icon/GlintIcon-1024.png" alt="Glint icon" width="128" height="128">

# Glint

**Fast, private screenshots for macOS: select, annotate, copy.**

A native Swift menu-bar app for Apple silicon, inspired by Lightshot's quick capture-and-mark-up workflow.

[![CI](https://github.com/salmansiddiqui17/glint/actions/workflows/ci.yml/badge.svg)](https://github.com/salmansiddiqui17/glint/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/salmansiddiqui17/glint?include_prereleases&sort=semver)](https://github.com/salmansiddiqui17/glint/releases)
[![Platform](https://img.shields.io/badge/macOS-15%2B-blue?logo=apple)](#requirements)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)](https://www.swift.org)
[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE)

[Download](#installation) · [Usage](#usage) · [Build from source](#building-from-source) · [Releases](#releases) · [Contributing](CONTRIBUTING.md)

</div>

---

## Why Glint?

- **Instant.** One hotkey freezes every display. Drag a selection, mark it up, and press Return to copy it.
- **Native.** Swift 6, AppKit and ScreenCaptureKit, built for Apple silicon. No Rosetta, Electron or web view.
- **Private.** Sandboxed, with no network access at all: no uploads, accounts, analytics or telemetry.
- **Sharp.** Exports keep full Retina resolution, the display's colour profile and the DPI. What you see in the overlay is exactly what you get.

## Features

**Capture**
- Global hotkey (⇧⌘9 by default, changeable in Preferences) or the menu-bar icon.
- Freezes all displays at once, including mixed-scale and negative-origin setups, with one selection across them.
- Optional window snapping, off by default: turn on **Select windows by clicking** in Preferences, then click a window to select exactly that window, title bar included and shadow left out, or click the desktop for the whole display.
- Resize handles, a live pixel-size badge, arrow-key nudging and ⌘A for the whole display.
- Copy as PNG, or save as PNG or JPEG. The Save panel remembers the last folder. Optionally export at standard (1×) resolution.
- **Copy Text** (⌘O) recognises the text in the selection, on your Mac, and copies it as plain text. Redacted areas are never read. If there is no text, or it can't be read, the overlay says so and stays open. Pressing Esc or ⌘X while it reads stops it and closes the capture.
- On the first launch after you install or update Glint, it prepares text recognition in the background, so your first **Copy Text** is quick. If you use it straight away, it may take up to 45 seconds, says so after 10 seconds, and if it runs out of time asks you to try again.

**Annotate**
- Pencil, Line, Arrow, Ellipse, Rectangle, Marker, Text and Redact, in a palette beside the selection.
- Hold ⇧ for 45° lines, squares and circles. Scroll or press ⌘+ / ⌘− to change the stroke width.
- Text boxes with full input-method support: dead keys, the accent menu, and Japanese and Chinese input.
- **Redact** (⌘B) pixelates or blurs. Drag along a line of text to redact it; scroll or press ⌘+ / ⌘− before dragging to make the band taller or shorter; the pointer shows its size. Larger redactions are obscured more strongly, so text of any size beneath them can't be read. If a redaction can't be produced, the export is refused rather than leaking the original pixels.
- Unlimited undo and redo. Colour, width and text size are remembered.

**System**
- Launch at login, a guided Screen Recording permission flow, and Preferences that apply instantly.
- **About Glint** in the menu-bar menu shows the version, copyright and acknowledgements.
- VoiceOver labels on every control, and the **Colour** button reads out the current colour. With VoiceOver on, the overlay speaks the selection's size once it settles.
- Shortcuts work on any keyboard layout, including Russian, Greek, Dvorak – QWERTY ⌘, German and Turkish.

## Requirements

- A Mac with Apple silicon (M1 or later)
- macOS 15 Sequoia or later
- Screen Recording permission, which Glint asks for on first launch

## Installation

1. Download `Glint-<version>.dmg` (or `.zip`) from the [latest release](https://github.com/salmansiddiqui17/glint/releases/latest).
2. Drag **Glint** into **Applications** and open it. A camera icon appears in the menu bar.
3. Glint is not yet notarized by Apple, so the first launch is blocked. Allow it once:
   - open **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to the Glint message; or
   - run `xattr -dr com.apple.quarantine /Applications/Glint.app` in Terminal.
4. Grant **Screen Recording** when asked (**System Settings › Privacy & Security › Screen & System Audio Recording**).

> [!NOTE]
> Releases are currently ad-hoc signed, so macOS treats each update as a new app. If, after an
> update, Glint says Screen Recording is not granted even though it's switched on in System Settings,
> reset its entry and allow it again:
> ```bash
> tccutil reset ScreenCapture com.salmanfurqan.glint
> ```
> Then reopen Glint and click **Grant Access…** (or press ⇧⌘9).

To check a download, compare its checksum with `SHA256SUMS.txt` on the release page:

```bash
shasum -a 256 Glint-*.dmg
gh attestation verify Glint-*.dmg --repo salmansiddiqui17/glint   # build provenance, optional
```

## Usage

Press **⇧⌘9**, or choose **Take Screenshot** from the menu-bar icon, then drag to select an area.

| Action | Shortcut |
| --- | --- |
| Select a window, or the whole display (with **Select windows by clicking** on) | **Click** the window, or the desktop |
| Copy to the clipboard and close | **Return** or **⌘C** |
| Copy the text in the selection and close | **⌘O** |
| Save to a file | **⌘S** |
| Close without saving | **Esc** or **⌘X** |
| Select the whole display | **⌘A** (or **⌘F**) |
| Move or resize the selection | **Arrow keys** / **⇧ Arrow keys** |
| Redact tool | **⌘B** |
| Undo / redo | **⌘Z** / **⇧⌘Z** |
| Stroke width or text size | **Scroll**, or **⌘+** / **⌘−** |
| Constrain a shape (45°, square, circle) | Hold **⇧** while dragging |

**Esc** works in stages: it cancels the shape you're drawing or finishes the text you're typing, then
leaves the tool, then closes the capture. While **Copy Text** is reading, Esc closes the capture at once.

Window snapping is optional and off by default: the screen dims, nothing is highlighted, and a click
never selects a window, so you drag exactly the area you want. To select windows by clicking, turn on
**Select windows by clicking** in Preferences; it applies from the next capture. Then, before you make
a selection, the window under the pointer is highlighted. Only other apps' windows count, not the
Dock, the menu bar or floating panels. Clicking outside a selection selects the window under the
pointer instead. After a click selects the whole display, **⌘A**, **⌘F** or a double-click inside
clears the selection, so you can pick a window again. Snapping is off while a drawing tool is selected.

Click a tool in the palette to select it, and click it again to put it down. With no tool selected,
dragging moves or resizes the selection.

## Privacy

Glint runs in the macOS App Sandbox, and its only file access is to locations you pick in the Save
panel. It has **no network entitlement** (the build script refuses to produce an app that has one),
so Glint itself never sends your screenshots or their text anywhere. **Copy Text** uses Apple's
on-device Vision text recognition. Glint's logs hold only diagnostics such as image sizes, timings
and errors, never what you capture, type or copy as text. What you copy goes to the macOS clipboard,
which Universal Clipboard may share with your other Apple devices, and macOS uploads files you save
to a synced folder such as iCloud Drive.

## Building from source

**Prerequisites:** an Apple silicon Mac with macOS 15 or later and **Xcode 27** or later. The build
uses SwiftPM's Swift Build backend.

```bash
git clone https://github.com/salmansiddiqui17/glint.git
cd glint

swift test                                 # run the unit tests
scripts/build-app.sh                       # release build → build/Glint.app
scripts/build-app.sh debug                 # debug build (lldb can attach)
scripts/build-app.sh release --install     # build and copy to /Applications
```

`scripts/build-app.sh` compiles with SwiftPM, assembles the `.app` bundle, and signs it with the
hardened runtime and the sandbox entitlements. It signs with these, in order:

1. `GLINT_SIGN_IDENTITY`, if set (a certificate name or SHA-1, or `-` for ad-hoc);
2. otherwise your first **Apple Development** certificate, which keeps the Screen Recording permission across rebuilds;
3. otherwise ad-hoc.

To package a build the way releases are packaged:

```bash
scripts/package-release.sh 1.2.3          # dist/Glint-1.2.3.zip, .dmg and SHA256SUMS.txt
```

### Project layout

```
Sources/
  Glint/        Entry point
  GlintApp/     AppKit and SwiftUI shell: menu bar, overlay, capture, editor views, export, Preferences
  GlintCore/    Pure logic: geometry, window snapping, layout, annotations, text, text recognition, rendering, redaction (unit-tested)
Tests/
  GlintCoreTests/   Unit tests, and Goldens/ with the renderer's golden images
Resources/      Info.plist, entitlements, app icon, Localizable.xcstrings (the String Catalog)
scripts/        build-app.sh, package-release.sh, notarize.sh, make-icon.sh, sync-strings.sh, smoke-launch.sh
```

## Releases

Releases are fully automated with GitHub Actions:

- **[CI](.github/workflows/ci.yml)** runs on every push to `main` and every pull request. It checks
  the String Catalog is up to date, runs the tests on macOS 27, builds an ad-hoc signed app, packages
  it, and uploads it as a workflow artifact. Then it launches that app on macOS 15 and 26 to check it
  still starts. When a golden-image test fails, it uploads the expected, actual and diff images as a
  `test-attachments-…` artifact.
- **[Release](.github/workflows/release.yml)** runs when a version tag is pushed. It tests, builds
  with the tag's version, packages a `.dmg`, a `.zip` and `SHA256SUMS.txt`, attests build provenance,
  and publishes a GitHub release. The release notes come from that version's section of
  [CHANGELOG.md](CHANGELOG.md).

To cut a release:

```bash
# 1. In CHANGELOG.md, rename "Unreleased" to the new version, e.g. "## [1.2.3] - 2026-10-19", and commit.
# 2. Tag and push:
git tag v1.2.3
git push origin v1.2.3
```

A tag with a suffix, such as `v1.3.0-beta.1`, is published as a pre-release.

### Enabling notarization

The release workflow can sign with a Developer ID and notarize, so users never see a Gatekeeper
warning. This needs an [Apple Developer Program](https://developer.apple.com/programs/) membership.

1. In the repository's **Settings › Secrets and variables › Actions**, add these secrets:

   | Secret | Value |
   | --- | --- |
   | `DEVELOPER_ID_CERTIFICATE_P12_BASE64` | Your *Developer ID Application* certificate and its private key, exported as `.p12`, base64-encoded (`base64 -i cert.p12 \| pbcopy`) |
   | `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The `.p12` export password |
   | `NOTARY_API_KEY_BASE64` | An App Store Connect API key (`AuthKey_XXXX.p8`), base64-encoded |
   | `NOTARY_KEY_ID` | The API key's ID |
   | `NOTARY_ISSUER_ID` | The API key's issuer ID |

2. Add a repository **variable** `NOTARIZE` with the value `true`.

From then on, every tagged release is signed with the Developer ID, notarized and stapled.

## Roadmap

- Developer ID signed, notarized releases, and a Homebrew cask
- Translations: every string is already in a String Catalog

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and
guidelines, and [SECURITY.md](SECURITY.md) to report vulnerabilities privately.

## Acknowledgements

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus (MIT), for the global hotkey and its recorder.
- Inspired by [Lightshot](https://app.prntscr.com). Glint is an independent project, not affiliated with or endorsed by Lightshot or its developers.

## License

Glint is released under the [MIT License](LICENSE). © 2026 SFS Tech.
