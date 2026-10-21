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
# diskutil image replaces hdiutil create, which macOS 27 deprecates. The volume is APFS, which
# every supported macOS (15+) reads. Image tools fail now and then on CI runners, so it gets
# three tries and its error is shown.
for attempt in 1 2 3; do
  if diskutil image create from --format UDZO --volumeName "Glint $VERSION" "$STAGING" "dist/$DMG"; then
    break
  fi
  rm -f "dist/$DMG"   # a failed attempt can leave a partial image behind
  if (( attempt == 3 )); then
    echo "error: diskutil could not create $DMG after 3 attempts." >&2
    exit 1
  fi
  echo "diskutil failed (attempt $attempt); retrying in 5 s." >&2
  sleep 5
done

(cd dist && shasum -a 256 "$ZIP" "$DMG" > SHA256SUMS.txt)
echo "Packaged Glint $VERSION:"
ls -l dist
