#!/usr/bin/env bash
# ============================================================================
# Akeeba Extract — Windows installer / portable zip creator
# A cross-platform desktop application to extract Akeeba Backup archives
#
# Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
# License: GNU General Public License version 3, or later
#
# Usage:
#   ./build/make-windows-installer.sh
#
# Run `php vendor/bin/boson compile` first to produce the Windows binary in
# build/output/windows/amd64/.
#
# Preferred: NSIS — its `makensis` compiler runs natively on macOS and Linux,
# so the installer cross-compiles from this host (no Wine/Docker/Windows).
# Fallbacks: Inno Setup's `iscc` (e.g. on a Windows host), else a portable
# .zip.
#
# Output: build/dist/Akeeba-Extract-<version>-windows-amd64-Setup.exe
#      or build/dist/Akeeba-Extract-<version>-windows-amd64.zip
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

VERSION="${AKEEBA_EXTRACT_VERSION:-$(sed -nE "s/.*VERSION = '([^']+)'.*/\1/p" "$PROJECT_ROOT/src/App.php" | head -1)}"

# NSIS's VIProductVersion requires a strict 4-component numeric X.X.X.X form,
# unlike VERSION (e.g. "0.1"). Sanitise to digits/dots, take up to 4 numeric
# components, and pad any missing ones with 0.
VI_PARTS="$(echo "$VERSION" | grep -oE '[0-9]+' | head -4 | paste -sd. -)"
IFS='.' read -ra VI_ARR <<< "$VI_PARTS"
while [[ ${#VI_ARR[@]} -lt 4 ]]; do VI_ARR+=("0"); done
VIVERSION="${VI_ARR[0]}.${VI_ARR[1]}.${VI_ARR[2]}.${VI_ARR[3]}"

WIN_BIN="build/output/windows/amd64/akeeba-extract.exe"
DIST="$PROJECT_ROOT/build/dist"
mkdir -p "$DIST"

if [[ ! -f "$WIN_BIN" ]]; then
    echo "ERROR: Windows binary not found at: $WIN_BIN" >&2
    echo "Run 'php vendor/bin/boson compile' first." >&2
    exit 1
fi

# Sign the compiled binary itself first, so both the installer and the
# portable .zip fallback below carry a signed akeeba-extract.exe. A no-op
# unless WINDOWS_SIGN_OP_ITEM is set (see build/sign-windows-exe.sh) — never
# runs for a local 'phing git-win-x86' compile, only from packaging.
"$SCRIPT_DIR/sign-windows-exe.sh" "$WIN_BIN"

MAKENSIS="$(command -v makensis 2>/dev/null || true)"
ISCC="$(command -v iscc 2>/dev/null || command -v ISCC 2>/dev/null || true)"

if [[ -n "$MAKENSIS" ]]; then
    echo "Packaging Windows (amd64): NSIS installer (native makensis)"
    OUTFILE="$DIST/Akeeba-Extract-${VERSION}-windows-amd64-Setup.exe"
    # makensis chdir's to the script dir, so pass ABSOLUTE source/output paths.
    "$MAKENSIS" -V2 \
        "-DSRCDIR=$PROJECT_ROOT/build/output/windows/amd64" \
        "-DOUTFILE=$OUTFILE" \
        "-DLICENSEFILE=$PROJECT_ROOT/LICENSE.txt" \
        "-DICONFILE=$PROJECT_ROOT/build/extract.ico" \
        "-DAPPVERSION=$VERSION" \
        "-DVIVERSION=$VIVERSION" \
        build/windows-installer.nsi
    # Sign the installer executable itself too — it is a PE file end users run directly.
    "$SCRIPT_DIR/sign-windows-exe.sh" "$OUTFILE"
    echo "Created: $OUTFILE"
elif [[ -n "$ISCC" ]]; then
    echo "Packaging Windows (amd64): Inno Setup installer (iscc)"
    "$ISCC" "/DAppVersion=$VERSION" build/windows-installer.iss
    OUTFILE="$DIST/Akeeba-Extract-${VERSION}-windows-amd64-Setup.exe"
    mv "build/output/Akeeba-Extract-Setup.exe" "$OUTFILE"
    # Sign the installer executable itself too — it is a PE file end users run directly.
    "$SCRIPT_DIR/sign-windows-exe.sh" "$OUTFILE"
    echo "Created: $OUTFILE"
else
    echo "Packaging Windows (amd64): portable .zip (no installer compiler found)"
    echo "  No installer compiler found — produced a portable .zip. Install NSIS ('brew install makensis') for a native Windows installer, or build build/windows-installer.iss on Windows." >&2
    STAGE="$PROJECT_ROOT/build/output/.stage-win/Akeeba Extract"
    rm -rf "$PROJECT_ROOT/build/output/.stage-win"; mkdir -p "$STAGE"
    cp -R "build/output/windows/amd64/." "$STAGE/"
    cp "build/extract.ico" "$STAGE/extract.ico"
    ZIP_OUT="$DIST/Akeeba-Extract-${VERSION}-windows-amd64.zip"
    rm -f "$ZIP_OUT"
    if command -v zip >/dev/null 2>&1; then
        ( cd "$PROJECT_ROOT/build/output/.stage-win" && zip -qr "$ZIP_OUT" "Akeeba Extract" )
        echo "Created: $ZIP_OUT"
    else
        echo "ERROR: 'zip' not available — could not produce the portable .zip." >&2
        rm -rf "$PROJECT_ROOT/build/output/.stage-win"
        exit 1
    fi
    rm -rf "$PROJECT_ROOT/build/output/.stage-win"
fi
