#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from the full-bleed master Resources/Icon/GlintIcon-1024.png.
# Run after changing the master; the .icns is committed, so normal builds don't need this.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift scripts/make-icon.swift Resources/Icon/GlintIcon-1024.png "$WORK/AppIcon.iconset"
iconutil --convert icns --output Resources/AppIcon.icns "$WORK/AppIcon.iconset"
echo "Wrote Resources/AppIcon.icns ($(du -h Resources/AppIcon.icns | cut -f1))"
