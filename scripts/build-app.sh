#!/usr/bin/env bash
# Builds build/Glint.app: compiles with SwiftPM, assembles the bundle, signs it sandboxed with the
# hardened runtime, and optionally installs it to /Applications.
#
#   scripts/build-app.sh [debug|release] [--install]      (default: release, no install)
#
# Install before testing launch at login (FR-13): the login item records the bundle's path, so it
# must be a stable location such as /Applications, not a build folder or worktree.
#
# Signing identity: $GLINT_SIGN_IDENTITY (name or SHA-1, or "-" for ad-hoc), else the first valid
# "Apple Development" identity (by SHA-1, so a renewed certificate with the same name can't make
# codesign ambiguous), else ad-hoc. Keep using the same identity: the Screen Recording grant is
# tied to it.
#
# Release builds (CI) also set:
#   GLINT_VERSION           marketing version, e.g. 0.2.0 (CFBundleShortVersionString)
#   GLINT_BUILD             build number (CFBundleVersion)
#   GLINT_SECURE_TIMESTAMP  1 to sign with Apple's secure timestamp, which notarization requires
#
# Requires SwiftPM's Swift Build backend (Xcode 27's default; products under .../Products/<Config>):
# its generated accessors find resource bundles via Bundle.main.resourceURL, which is where this
# script puts them. The script stops if the build layout says otherwise.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    debug|release) CONFIG="$arg" ;;
    --install) INSTALL=1 ;;
    *) echo "usage: $0 [debug|release] [--install]" >&2; exit 2 ;;
  esac
done

# Use Xcode's toolchain unless the developer directory already points at a full Xcode.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# The bundle identifier lives in Info.plist and in GlintCore (logging, single instance); keep them equal.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Resources/Info.plist)"
if ! grep -q "bundleIdentifier = \"$BUNDLE_ID\"" Sources/GlintCore/GlintCore.swift; then
  echo "error: GlintCore.bundleIdentifier doesn't match Info.plist ($BUNDLE_ID)." >&2
  exit 1
fi

swift build -c "$CONFIG" --arch arm64
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"
if [[ "$BIN" != */Products/* ]]; then
  echo "error: unexpected SwiftPM build layout ($BIN): resource bundles would not be found." >&2
  exit 1
fi

APP="build/Glint.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Glint" "$APP/Contents/MacOS/Glint"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${GLINT_VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $GLINT_VERSION" "$APP/Contents/Info.plist"
fi
if [[ -n "${GLINT_BUILD:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $GLINT_BUILD" "$APP/Contents/Info.plist"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # regenerate with scripts/make-icon.sh
# SwiftPM resource bundles (KeyboardShortcuts' localisations); found via Bundle.main.resourceURL.
find "$BIN" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

# SwiftPM's build system records the deployment target as the SDK version; stamp the real SDK so
# macOS gives Glint current-SDK behaviour rather than macOS 15 compatibility mode.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Resources/Info.plist)"
codesign --remove-signature "$APP/Contents/MacOS/Glint"   # the linker's ad-hoc signature; re-signed below
vtool -set-build-version macos "$MIN_OS" "$SDK_VERSION" -replace \
  -output "$APP/Contents/MacOS/Glint" "$APP/Contents/MacOS/Glint"

IDENTITY="${GLINT_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Apple Development/ {print $2; exit}' || true)}"
if [[ -z "$IDENTITY" ]]; then
  echo "warning: no Apple Development identity found; signing ad-hoc." >&2
  echo "warning: macOS will ask for Screen Recording permission again after every rebuild." >&2
  IDENTITY="-"
fi

ENTITLEMENTS="Resources/Glint.entitlements"
if [[ "$CONFIG" == "debug" ]]; then
  # Let lldb attach to debug builds; release builds keep the strict entitlements (NFR-19).
  ENTITLEMENTS="build/Glint-debug.entitlements"
  cp Resources/Glint.entitlements "$ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" "$ENTITLEMENTS"
fi

TIMESTAMP="--timestamp=none"
if [[ "${GLINT_SECURE_TIMESTAMP:-0}" == 1 ]]; then TIMESTAMP="--timestamp"; fi
codesign --force --options runtime "$TIMESTAMP" \
  --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"
# NFR-19: the signed app must never carry a network entitlement.
if codesign -d --entitlements - "$APP" 2>/dev/null | grep -q 'com.apple.security.network'; then
  echo "error: $APP has a network entitlement." >&2
  exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "Built $APP $VERSION ($CONFIG, SDK $SDK_VERSION, signed with: $IDENTITY)"

if [[ "$INSTALL" == 1 ]]; then
  # Quit a running copy first (pkill, not osascript, which would ask for Automation permission).
  pkill -x Glint || true
  for _ in {1..20}; do pgrep -x Glint >/dev/null || break; sleep 0.25; done
  rm -rf /Applications/Glint.app
  ditto "$APP" /Applications/Glint.app
  echo "Installed /Applications/Glint.app"
fi
