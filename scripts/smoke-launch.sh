#!/usr/bin/env bash
# Launch smoke test (NFR-11): opens a built Glint.app and checks that it is still running 10 s
# later. CI runs it on the oldest supported macOS versions, to catch a crash at launch from an API
# that a newer SDK has and they lack. Quits any Glint that is already running first.
#
#   scripts/smoke-launch.sh path/to/Glint.app
set -euo pipefail

APP="${1:?usage: $0 path/to/Glint.app}"
VERSION="$(sw_vers -productVersion)"

# Fails the job with whatever crash report and log lines macOS kept, so a launch crash on an older
# macOS shows its cause (such as a missing symbol) right in the CI log. Only reports newer than the
# marker made just before launching, so a developer Mac's old crashes aren't printed.
fail() {
  echo "::error::$1 on macOS $VERSION."
  sleep 3   # ReportCrash writes the report a moment after the crash
  local reports=""
  if [[ -n "${MARKER:-}" ]]; then
    reports="$(find ~/Library/Logs/DiagnosticReports -name 'Glint*' -newer "$MARKER" 2>/dev/null || true)"
  fi
  if [[ -n "$reports" ]]; then
    while IFS= read -r report; do
      echo "--- $report"
      grep -E '"(exception|termination|asi)"' "$report" || head -n 80 "$report"
    done <<< "$reports"
  else
    echo "No Glint crash report found."
  fi
  /usr/bin/log show --last 2m --style compact --predicate 'process == "Glint"' 2>/dev/null | tail -n 50 || true
  exit 1
}

pkill -x Glint 2>/dev/null || true
for _ in {1..20}; do pgrep -x Glint >/dev/null || break; sleep 0.25; done

MARKER="$(mktemp)"
trap 'rm -f "$MARKER"' EXIT
open "$APP" || fail "open could not launch Glint"
for _ in {1..40}; do pgrep -x Glint >/dev/null && break; sleep 0.25; done
pgrep -x Glint >/dev/null || fail "Glint did not start, or exited at once"

sleep 10
pgrep -x Glint >/dev/null || fail "Glint quit or crashed within 10 s of launching"
echo "Glint is still running 10 s after launch on macOS $VERSION."
pkill -x Glint || fail "Glint exited just after the 10 s check"
