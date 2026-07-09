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
#
# --- Signable split vs. legacy combined binary ---------------------------
#
# Stock `boson compile` links against a stock phpmicro SFX, which appends the
# PHP payload directly after the Mach-O code-signature region. `codesign`
# refuses to sign a binary with trailing bytes past its signature, so such a
# binary can never be Developer-ID signed.
#
# When the binary was compiled against the PATCHED SFX runtime (the
# `nikosdion/phpmicro` `sibling-phar` fork — see build/fetch-sfx.sh and
# build/readme/01-macos-signing.md) it instead carries no appended payload:
# the patched stub looks for its PHP payload in a *sibling* file, "<self>.phar"
# first, then "../Resources/<basename>.phar". We detect that stub (by its
# "next to this executable" trace string) and SPLIT the compiled binary: the
# clean Mach-O region (up to the end of LC_CODE_SIGNATURE) becomes the bundle
# executable, and the bytes appended after it become
# Contents/Resources/akeeba-extract.phar, which the patched stub finds at run
# time. Data files must live in Resources — codesign refuses non-code files
# inside Contents/MacOS.
#
# Once split, the phar's own directory is Resources, and Boson's entrypoint
# mounts `public/` and the libboson dylib relative to the phar — so the
# mounted assets move to Resources too, and the dylib (a real file in MacOS,
# where signed code lives) gets a symlink there.
#
# If the compiled binary is a STOCK (non-split) binary, this script aborts
# with an actionable error rather than assembling an unsignable bundle.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
APP_NAME="Akeeba Extract"
BUNDLE_ID="com.akeeba.extract"
BUNDLE_VERSION="${AKEEBA_EXTRACT_VERSION:-$(sed -nE "s/.*VERSION = '([^']+)'.*/\1/p" "$PROJECT_ROOT/src/App.php" | head -1)}"
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
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

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
# Detect the split-capable stub and locate the end of its Mach-O region.
#
# The patched SFX's stub carries the "next to this executable" trace string
# (emitted when MICRO_TRACE_OPEN=1). The Mach-O image ends where its last
# segment ends — max(fileoff + filesize) across every LC_SEGMENT_64 — and
# anything past that in the file is the appended PHP payload phpmicro loads.
#
# We deliberately do NOT key off LC_CODE_SIGNATURE: only the arm64 SFX ships
# with an (ad-hoc) signature — Apple Silicon requires one — while the
# cross-compiled x86_64 SFX has no LC_CODE_SIGNATURE at all, so a
# dataoff+datasize probe returns nothing and the amd64 build would wrongly look
# unsplittable. The last-segment end is present on both arches (and, when a
# signature does exist, __LINKEDIT's filesize already covers it, so the two
# agree on arm64).
# ---------------------------------------------------------------------------
SIBLING_SFX=0
MACHO_END=""
if LC_ALL=C grep -q "next to this executable" "$BINARY_PATH"; then
    MACHO_END="$(otool -l "$BINARY_PATH" 2>/dev/null | awk '
        /cmd LC_SEGMENT_64/ {seg = 1}
        seg && /fileoff/    {fo = $2}
        seg && /filesize/   {end = fo + $2; if (end > max) max = end; seg = 0}
        END                 {if (max) print max}')"
    FILE_SIZE="$(stat -f%z "$BINARY_PATH")"
    if [[ -n "$MACHO_END" && "$FILE_SIZE" -gt "$MACHO_END" ]]; then
        SIBLING_SFX=1
    fi
fi

if [[ "$SIBLING_SFX" != 1 ]]; then
    echo "ERROR: $BINARY_PATH is not a signable split-payload binary." >&2
    echo "  Either it was compiled against a STOCK phpmicro SFX (whose appended PHP" >&2
    echo "  payload makes it unsignable), or no payload could be located past its" >&2
    echo "  code signature. Run build/fetch-sfx.sh to fetch the patched" >&2
    echo "  'sibling-phar' SFX into build/sfx/, then recompile — see" >&2
    echo "  build/readme/01-macos-signing.md." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Create bundle structure
# ---------------------------------------------------------------------------
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# ---------------------------------------------------------------------------
# Split the compiled binary into a clean Mach-O stub + its .phar payload
# ---------------------------------------------------------------------------
echo "  Splitting $((FILE_SIZE - MACHO_END)) payload bytes into Contents/Resources/$BINARY_NAME.phar"
head -c "$MACHO_END" "$BINARY_PATH" > "$MACOS_DIR/$BINARY_NAME"
tail -c "+$((MACHO_END + 1))" "$BINARY_PATH" > "$RESOURCES_DIR/$BINARY_NAME.phar"
chmod +x "$MACOS_DIR/$BINARY_NAME"

# ---------------------------------------------------------------------------
# Copy the Boson WebView dylib (if present beside the binary). It must sit
# next to the main executable inside Contents/MacOS/ (codesign requires
# executable code to live under MacOS/, not Resources/).
# ---------------------------------------------------------------------------
if [[ -f "$INPUT_DIR/$RUNTIME_DYLIB" ]]; then
    cp "$INPUT_DIR/$RUNTIME_DYLIB" "$MACOS_DIR/$RUNTIME_DYLIB"
    echo "  Copied dylib: $RUNTIME_DYLIB"
else
    echo "  WARNING: $RUNTIME_DYLIB not found in $INPUT_DIR — WebView may not work."
fi

# ---------------------------------------------------------------------------
# Copy mounted asset directories (e.g. public/) that the Boson compiler placed
# BESIDE the binary. Once split, the payload phar's own directory is
# Contents/Resources/ (that's where the sibling-phar loader found it), and the
# PHAR stub mounts these relative to the running phar's directory —
# Phar::mount('public', __DIR__ . '/public') — so they now belong in
# Contents/Resources/, not Contents/MacOS/.
# ---------------------------------------------------------------------------
if [[ -d "$INPUT_DIR/public" ]]; then
    cp -R "$INPUT_DIR/public" "$RESOURCES_DIR/public"
    echo "  Copied mounted assets: public/"
else
    echo "  WARNING: public/ not found in $INPUT_DIR — the UI will 404."
    echo "           Run 'php vendor/bin/boson compile' so the compiler mounts public/ beside the binary."
fi

# ---------------------------------------------------------------------------
# Symlink the dylib(s) back under Resources/, pointing at the real (signed)
# copy in MacOS/, so relative lookups from the phar's Resources/ vantage point
# still resolve at runtime.
# ---------------------------------------------------------------------------
for dylib in "$MACOS_DIR"/*.dylib; do
    [[ -f "$dylib" ]] || continue
    ln -s "../MacOS/$(basename "$dylib")" "$RESOURCES_DIR/$(basename "$dylib")"
done

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
    <string>${BINARY_NAME}</string>

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
    cp "$ICON_SRC" "$RESOURCES_DIR/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" \
        "$APP_BUNDLE/Contents/Info.plist" 2>/dev/null || true
    echo "  Copied icon: AppIcon.icns"
else
    echo "  NOTE: No AppIcon.icns found at build/AppIcon.icns — bundle has no icon."
    echo "        Create a 1024×1024 PNG, convert with 'iconutil', and save as build/AppIcon.icns."
fi

# ---------------------------------------------------------------------------
# Code signing
#
# For DISTRIBUTION set MACOS_SIGN_IDENTITY to a "Developer ID Application: …"
# identity (see build/readme/01-macos-signing.md). We sign inside-out — the
# bundled dylib(s), then the main executable, then the whole bundle — each
# with the hardened runtime (--options runtime) and the entitlements the
# Boson SFX + bundled PHP runtime need (build/macos/entitlements.plist). This
# REPLACES the binary's original ad-hoc SFX signature, which cannot be
# notarized.
#
# For LOCAL dev (MACOS_SIGN_IDENTITY unset) we ad-hoc sign (--sign -) at each
# of the same steps instead, so local/unsigned builds still produce a
# structurally-valid bundle that launches (but cannot be notarized).
# ---------------------------------------------------------------------------
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:-}"
ENTITLEMENTS="${MACOS_ENTITLEMENTS:-$PROJECT_ROOT/build/macos/entitlements.plist}"

if [[ -n "$SIGN_IDENTITY" ]]; then
    if ! command -v codesign &>/dev/null; then
        echo "ERROR: MACOS_SIGN_IDENTITY is set but 'codesign' was not found — install Xcode or the Command Line Tools." >&2
        exit 1
    fi
    if [[ ! -f "$ENTITLEMENTS" ]]; then
        echo "ERROR: Entitlements file not found at $ENTITLEMENTS." >&2
        exit 1
    fi
    echo "  Signing with Developer ID identity: $SIGN_IDENTITY"

    # 1) inner dylibs first (normal Mach-O files — these sign cleanly)
    for dylib in "$MACOS_DIR"/*.dylib; do
        [[ -f "$dylib" ]] || continue
        codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$dylib"
    done

    # 2) the main executable (a clean Mach-O stub after the payload split above)
    codesign --force --timestamp --options runtime \
        --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$MACOS_DIR/$BINARY_NAME"

    # 3) the whole bundle
    codesign --force --timestamp --options runtime \
        --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    echo "  Signed and verified: $APP_BUNDLE"
elif command -v codesign &>/dev/null; then
    echo "  MACOS_SIGN_IDENTITY not set — ad-hoc signing (local dev only, not notarizable)"
    for dylib in "$MACOS_DIR"/*.dylib; do
        [[ -f "$dylib" ]] && codesign --force --sign - "$dylib" >/dev/null 2>&1 || true
    done
    codesign --force --sign - "$MACOS_DIR/$BINARY_NAME" >/dev/null 2>&1 || true
    codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "Created: $APP_BUNDLE"
echo ""
echo "Next steps:"
echo "  1. Run ./build/make-dmg.sh $ARCH  to create the distributable .dmg"
echo "  2. (Optional) Notarize with: xcrun notarytool submit … --wait"
