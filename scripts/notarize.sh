#!/usr/bin/env bash
# Notarizes and staples build/Glint.app with Apple's notary service, using an App Store Connect
# API key. The app must be signed with a Developer ID Application identity and a secure timestamp
# (GLINT_SIGN_IDENTITY=… GLINT_SECURE_TIMESTAMP=1 scripts/build-app.sh release).
#
#   NOTARY_KEY_PATH=AuthKey_XXXX.p8 NOTARY_KEY_ID=XXXX NOTARY_ISSUER_ID=uuid scripts/notarize.sh
#
# Used by the release workflow when notarization is enabled; see README › Releases.
set -euo pipefail
cd "$(dirname "$0")/.."

: "${NOTARY_KEY_PATH:?set NOTARY_KEY_PATH to the .p8 API key file}"
: "${NOTARY_KEY_ID:?set NOTARY_KEY_ID}"
: "${NOTARY_ISSUER_ID:?set NOTARY_ISSUER_ID}"

APP="build/Glint.app"
SUBMISSION="$(mktemp -d)/Glint-notarize.zip"
ditto -c -k --keepParent "$APP" "$SUBMISSION"

xcrun notarytool submit "$SUBMISSION" \
  --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" \
  --wait --timeout 30m
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
echo "Notarized and stapled $APP"
