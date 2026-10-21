#!/usr/bin/env bash
# Refreshes Resources/Localizable.xcstrings, the String Catalog that holds every user-visible
# string (NFR-15), from the sources: String(localized:) calls and SwiftUI text. Run it after
# changing user-visible text, and commit the catalog. CI fails when the catalog is out of date.
#
#   scripts/sync-strings.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

CATALOG="Resources/Localizable.xcstrings"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

find Sources/GlintApp Sources/GlintCore -name '*.swift' -print0 \
  | xargs -0 xcrun xcstringstool extract --SwiftUI --modern-localizable-strings --output-directory "$OUT"
if [[ ! -f "$CATALOG" ]]; then
  printf '{\n  "sourceLanguage" : "en",\n  "strings" : {\n\n  },\n  "version" : "1.0"\n}\n' > "$CATALOG"
fi
# Untranslated strings no longer in the source are removed; translated ones are kept and marked
# stale for review.
xcrun xcstringstool sync "$CATALOG" --stringsdata "$OUT"/*.stringsdata

# xcstringstool writes an interpolation as %arg, a key the app never looks up, so its translation
# would silently never show.
if grep -q '%arg' "$CATALOG"; then
  echo "error: $CATALOG has a %arg key. Write interpolated text with an explicit format key," >&2
  echo "       e.g. String(format: String(localized: \"%lld by %lld\"), w, h). See CONTRIBUTING.md." >&2
  echo "       The keys:" >&2
  grep -o '"[^"]*%arg[^"]*" :' "$CATALOG" | sed 's/ :$//; s/^/         /' >&2
  exit 1
fi
