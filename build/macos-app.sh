#!/usr/bin/env bash
# ============================================================================
# Akeeba Extract — macOS .app bundle creator
# A cross-platform desktop application to extract Akeeba Backup archives
#
# Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
# License: GNU General Public License version 3, or later
#
# Usage:
#   ./build/macos-app.sh [ARCH]
#
# ARCH can be: arm64 (default) or amd64
#
# Run `php vendor/bin/boson compile` first to produce binaries in build/output/.
#
# The Boson compiler emits, per macOS target:
#   build/output/macos/aarch64/akeeba-extract          (arm64 binary)
#   build/output/macos/aarch64/libboson-darwin-universal.dylib
#   build/output/macos/amd64/akeeba-extract            (x86_64 binary)
#   build/output/macos/amd64/libboson-darwin-universal.dylib
#
# NOTE: The Boson compiler names the arm64 output directory "aarch64",
# not "arm64". This script accepts "arm64" and maps it automatically.
#
# The resulting .app lands at:
#   build/output/macos/<BOSON_DIR>/Akeeba Extract.app
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
APP_NAME="Akeeba Extract"
BUNDLE_ID="com.akeeba.extract"
BUNDLE_VERSION="1.0.0"
BINARY_NAME="akeeba-extract"
RUNTIME_DYLIB="libboson-darwin-universal.dylib"

ARCH="${1:-arm64}"

if [[ "$ARCH" != "arm64" && "$ARCH" != "aarch64" && "$ARCH" != "amd64" ]]; then
    echo "ERROR: Unknown architecture '$ARCH'. Use 'arm64' (or 'aarch64') or 'amd64'." >&2
    exit 1
fi

# Boson compiler uses "aarch64" for the arm64 output directory
if [[ "$ARCH" == "arm64" ]]; then
    BOSON_DIR="aarch64"
else
    BOSON_DIR="$ARCH"
fi

INPUT_DIR="$PROJECT_ROOT/build/output/macos/$BOSON_DIR"
BINARY_PATH="$INPUT_DIR/$BINARY_NAME"
APP_BUNDLE="$INPUT_DIR/$APP_NAME.app"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if [[ ! -f "$BINARY_PATH" ]]; then
    echo "ERROR: Binary not found at: $BINARY_PATH" >&2
    echo "Run 'php vendor/bin/boson compile' first." >&2
    exit 1
fi

echo "Building: $APP_BUNDLE"
echo "  Binary : $BINARY_PATH"
echo "  Arch   : $ARCH"
echo ""

# ---------------------------------------------------------------------------
# Create bundle structure
# ---------------------------------------------------------------------------
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# ---------------------------------------------------------------------------
# Copy binary (rename to match CFBundleExecutable)
# ---------------------------------------------------------------------------
cp "$BINARY_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# ---------------------------------------------------------------------------
# Copy the Boson WebView dylib (if present beside the binary)
# The dylib must sit next to the main executable inside Contents/MacOS/.
# ---------------------------------------------------------------------------
if [[ -f "$INPUT_DIR/$RUNTIME_DYLIB" ]]; then
    cp "$INPUT_DIR/$RUNTIME_DYLIB" "$APP_BUNDLE/Contents/MacOS/$RUNTIME_DYLIB"
    echo "  Copied dylib: $RUNTIME_DYLIB"
else
    echo "  WARNING: $RUNTIME_DYLIB not found in $INPUT_DIR — WebView may not work."
fi

# ---------------------------------------------------------------------------
# Copy mounted asset directories (e.g. public/) that the Boson compiler placed
# BESIDE the binary. The PHAR stub mounts these relative to the executable's
# own directory — Phar::mount('public', __DIR__ . '/public') — so they MUST sit
# next to the executable inside Contents/MacOS/, not in Contents/Resources/.
# Without this the app loads app://host/index.html and the scheme handler 404s.
# ---------------------------------------------------------------------------
if [[ -d "$INPUT_DIR/public" ]]; then
    cp -R "$INPUT_DIR/public" "$APP_BUNDLE/Contents/MacOS/public"
    echo "  Copied mounted assets: public/"
else
    echo "  WARNING: public/ not found in $INPUT_DIR — the UI will 404."
    echo "           Run 'php vendor/bin/boson compile' so the compiler mounts public/ beside the binary."
fi

# ---------------------------------------------------------------------------
# Info.plist
# ---------------------------------------------------------------------------
# Map build arch to the Apple CPU type string
if [[ "$ARCH" == "arm64" ]]; then
    PLIST_CPU="arm64"
else
    PLIST_CPU="x86_64"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>

    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>

    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>

    <key>CFBundleVersion</key>
    <string>${BUNDLE_VERSION}</string>

    <key>CFBundleShortVersionString</key>
    <string>${BUNDLE_VERSION}</string>

    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>

    <key>CFBundlePackageType</key>
    <string>APPL</string>

    <key>CFBundleSignature</key>
    <string>????</string>

    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>

    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>

    <key>NSHighResolutionCapable</key>
    <true/>

    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Nicholas K. Dionysopoulos / Akeeba Ltd. Licensed under the GNU GPL v3 or later.</string>

    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>

    <key>LSArchitecturePriority</key>
    <array>
        <string>${PLIST_CPU}</string>
    </array>
</dict>
</plist>
PLIST

# ---------------------------------------------------------------------------
# Validate the plist
# ---------------------------------------------------------------------------
if command -v plutil &>/dev/null; then
    plutil -lint "$APP_BUNDLE/Contents/Info.plist"
    echo "  Info.plist: valid"
fi

# ---------------------------------------------------------------------------
# Icon placeholder — copy a generic .icns if one exists, or note it's missing
# ---------------------------------------------------------------------------
ICON_SRC="$PROJECT_ROOT/build/AppIcon.icns"
if [[ -f "$ICON_SRC" ]]; then
    cp "$ICON_SRC" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
        "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
    echo "  Copied icon: AppIcon.icns"
else
    echo "  NOTE: No AppIcon.icns found at build/AppIcon.icns — bundle has no icon."
    echo "        Create a 1024×1024 PNG, convert with 'iconutil', and save as build/AppIcon.icns."
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "Created: $APP_BUNDLE"
echo ""
echo "Next steps:"
echo "  1. Run ./build/make-dmg.sh $ARCH  to create the distributable .dmg"
echo "  2. (Optional) Sign with:  codesign --deep -s 'Developer ID Application: …' \"$APP_BUNDLE\""
echo "  3. (Optional) Notarize with: xcrun notarytool submit … --wait"
