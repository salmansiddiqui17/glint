# Contributing to Glint

Thanks for your interest in improving Glint! Bug reports, ideas and pull requests are all welcome.

## Reporting bugs

Please open an issue and include:
- your macOS version and Mac model, and your display setup (how many displays, Retina or not);
- the Glint version (select Glint.app in Finder › File › Get Info);
- steps to reproduce, and what you expected instead;
- relevant log lines, if any:
  ```bash
  /usr/bin/log show --last 5m --style compact --predicate 'subsystem == "com.salmanfurqan.glint"'
  ```

## Development setup

You need an Apple silicon Mac with macOS 15 or later and Xcode 27 or later.

```bash
git clone https://github.com/salmansiddiqui17/glint.git
cd glint
swift test                       # unit tests
scripts/build-app.sh debug       # builds build/Glint.app
open build/Glint.app
```

The build script signs with your first "Apple Development" certificate if you have one. That keeps
the Screen Recording permission across rebuilds. Without one, it signs ad-hoc, and macOS asks for
the permission again after each rebuild.

## How the code is organised

- **`GlintCore`** holds pure logic with no AppKit: selection geometry, toolbar layout, annotations,
  text layout, rendering and redaction, keyboard-command matching and file naming. Everything here
  is unit-tested with Swift Testing.
- **`GlintApp`** is the AppKit and SwiftUI shell: menu bar, overlay windows, ScreenCaptureKit
  capture, the editor views, export and Preferences.
- **`Glint`** is the executable entry point.

Logic that can live in `GlintCore` should live there, with tests. Code comments sometimes cite
requirement IDs such as `FR-35` or `NFR-6`. These come from the project's internal design notes;
the comment around each one explains the behaviour it refers to.

## Pull requests

- Keep each pull request focused on one change, and describe what it changes and why.
- Add or update tests for any logic change. `swift test` must pass, and CI runs it on every pull request.
- The project builds in Swift 6 language mode with strict concurrency checking; please keep it free of warnings.
- Glint must never gain a network entitlement or send data anywhere. The build script refuses to
  produce an app with one.
- Write user-visible text as `String(localized:)` in AppKit code, or as a SwiftUI string literal.
  Then run `scripts/sync-strings.sh` and commit `Resources/Localizable.xcstrings`, the String Catalog
  that translations will go into. CI fails when the catalog is out of date.
  Put values into text through an explicit format key, as in
  `String(format: String(localized: "%lld by %lld"), width, height)`: an interpolated string gets a
  catalog key the app never looks up, and the sync script rejects it.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages
  (`feat(core): …`, `fix(app): …`, `docs: …`).
- For user-visible changes, add a line to the `Unreleased` section of [CHANGELOG.md](CHANGELOG.md).

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
