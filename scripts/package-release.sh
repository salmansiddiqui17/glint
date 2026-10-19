#!/usr/bin/env bash
# Packages build/Glint.app (made by scripts/build-app.sh) for a GitHub release:
#
#   scripts/package-release.sh <version>
#
# Writes to dist/: Glint-<version>.zip, Glint-<version>.dmg (with an Applications shortcut for
# drag-to-install) and SHA256SUMS.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: $0 <version>}"
APP="build/Glint.app"
if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found; run scripts/build-app.sh release first." >&2
  exit 1
fi

rm -rf dist
mkdir -p dist
ZIP="Glint-$VERSION.zip"
DMG="Glint-$VERSION.dmg"

# ditto keeps the bundle's symlinks, extended attributes and code signature intact.
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/$ZIP"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/Glint.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "Glint $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "dist/$DMG"

(cd dist && shasum -a 256 "$ZIP" "$DMG" > SHA256SUMS.txt)
echo "Packaged Glint $VERSION:"
ls -l dist
