#!/usr/bin/env bash
# ============================================================================
# Akeeba Extract — macOS DMG creator
# A cross-platform desktop application to extract Akeeba Backup archives
#
# Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
# License: GNU General Public License version 3, or later
#
# Usage:
#   ./build/make-dmg.sh [ARCH]
#
# ARCH can be: arm64 (default) or amd64
#
# Prerequisite: run ./build/macos-app.sh [ARCH] first.
#
# Output: build/output/Akeeba-Extract-<ARCH>.dmg
#
# This script uses `hdiutil` (built into macOS) to create a compressed
# read-only DMG. If you have `create-dmg` installed (brew install create-dmg),
# see the commented alternative at the bottom for a fancier DMG with a
# background image and Applications folder symlink.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
APP_NAME="Akeeba Extract"
ARCH="${1:-arm64}"

if [[ "$ARCH" != "arm64" && "$ARCH" != "amd64" ]]; then
    echo "ERROR: Unknown architecture '$ARCH'. Use 'arm64' or 'amd64'." >&2
    exit 1
fi

# Boson compiler uses "aarch64" for the arm64 output directory
if [[ "$ARCH" == "arm64" ]]; then
    BOSON_DIR="aarch64"
else
    BOSON_DIR="$ARCH"
fi

APP_BUNDLE="$PROJECT_ROOT/build/output/macos/$BOSON_DIR/$APP_NAME.app"
DMG_OUT="$PROJECT_ROOT/build/output/Akeeba-Extract-${ARCH}.dmg"
STAGING_DIR="$PROJECT_ROOT/build/output/.dmg-staging-${BOSON_DIR}"
VOLUME_NAME="Akeeba Extract"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "ERROR: .app bundle not found at: $APP_BUNDLE" >&2
    echo "Run ./build/macos-app.sh $ARCH first." >&2
    exit 1
fi

echo "Building DMG for arch: $ARCH"
echo "  Source : $APP_BUNDLE"
echo "  Output : $DMG_OUT"
echo ""

# ---------------------------------------------------------------------------
# Build a staging folder with the .app and an Applications symlink
# ---------------------------------------------------------------------------
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# ---------------------------------------------------------------------------
# Estimate the size of the staging folder (+ some headroom)
# ---------------------------------------------------------------------------
STAGING_BYTES=$(du -sk "$STAGING_DIR" | awk '{print $1}')
DMG_MB=$(( (STAGING_BYTES / 1024) + 20 ))

echo "  Staging size : ${STAGING_BYTES} KB → DMG capacity ${DMG_MB} MB"

# ---------------------------------------------------------------------------
# Create the DMG via hdiutil
# ---------------------------------------------------------------------------

# Step 1: Create a writable temporary DMG from the staging folder
TEMP_DMG="$PROJECT_ROOT/build/output/.temp-${BOSON_DIR}.dmg"
rm -f "$TEMP_DMG"

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    -size "${DMG_MB}m" \
    "$TEMP_DMG"

# Step 2: Convert to a compressed read-only DMG
rm -f "$DMG_OUT"
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_OUT"

# ---------------------------------------------------------------------------
# Clean up temporaries
# ---------------------------------------------------------------------------
rm -f "$TEMP_DMG"
rm -rf "$STAGING_DIR"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "Created: $DMG_OUT"
echo ""
echo "Next steps:"
echo "  - Test: open \"$DMG_OUT\""
echo "  - Distribute the .dmg to end users."
echo "  - (Optional) Sign the DMG: codesign --sign 'Developer ID Application: …' \"$DMG_OUT\""
echo ""
echo "=== create-dmg alternative (fancier DMG, if installed) ==="
echo "  brew install create-dmg"
echo "  create-dmg \\"
echo "    --volname \"Akeeba Extract\" \\"
echo "    --window-pos 200 120 \\"
echo "    --window-size 600 400 \\"
echo "    --icon-size 100 \\"
echo "    --icon \"$APP_NAME.app\" 150 185 \\"
echo "    --hide-extension \"$APP_NAME.app\" \\"
echo "    --app-drop-link 450 185 \\"
echo "    \"$DMG_OUT\" \\"
echo "    \"build/output/macos/$BOSON_DIR/\""
