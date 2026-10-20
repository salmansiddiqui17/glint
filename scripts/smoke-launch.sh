#!/usr/bin/env bash
# Launch smoke test (NFR-11): opens a built Glint.app and checks that it is still running 10 s
# later. CI runs it on the oldest supported macOS versions, to catch a crash at launch from an API
# that a newer SDK has and they lack. Quits any Glint that is already running first.
#
#   scripts/smoke-launch.sh path/to/Glint.app
set -euo pipefail

APP="${1:?usage: $0 path/to/Glint.app}"
pkill -x Glint 2>/dev/null || true
for _ in {1..20}; do pgrep -x Glint >/dev/null || break; sleep 0.25; done

open "$APP"
for _ in {1..40}; do pgrep -x Glint >/dev/null && break; sleep 0.25; done
if ! pgrep -x Glint >/dev/null; then
  echo "::error::Glint did not start on macOS $(sw_vers -productVersion)."
  exit 1
fi

sleep 10
if ! pgrep -x Glint >/dev/null; then
  echo "::error::Glint quit or crashed within 10 s of launching on macOS $(sw_vers -productVersion)."
  find ~/Library/Logs/DiagnosticReports -name 'Glint*' -exec head -n 80 {} \; 2>/dev/null || true
  exit 1
fi
echo "Glint is still running 10 s after launch on macOS $(sw_vers -productVersion)."
pkill -x Glint
