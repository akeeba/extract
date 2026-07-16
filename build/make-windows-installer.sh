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

SRC_DIR="$PROJECT_ROOT/build/output/windows/amd64"
WIN_BIN="$SRC_DIR/akeeba-extract.exe"
DIST="$PROJECT_ROOT/build/dist"
mkdir -p "$DIST"

if [[ ! -f "$WIN_BIN" ]]; then
    echo "ERROR: Windows binary not found at: $WIN_BIN" >&2
    echo "Run 'php vendor/bin/boson compile' first." >&2
    exit 1
fi

# CRUCIAL: akeeba-extract.exe is a phpmicro self-executable — the PE stub with
# the application PHAR appended after it. Authenticode signing appends its
# certificate table at EOF, i.e. AFTER the PHAR, which corrupts the PHAR's own
# trailing signature and makes the app die at startup with "akeeba-extract.exe
# has a broken signature" (Phar::mapPhar). So we must NEVER sign the combined
# binary.
#
# When akeeba-extract.exe was compiled against the patched sibling-payload SFX
# (build/sfx/windows-x86_64.standard.sfx, from the nikosdion/phpmicro
# `sibling-phar` fork — see build/readme/02-signing-architecture.md), we split
# it, exactly like build/macos-app.sh does for the .app bundle: the clean PE
# stub becomes akeeba-extract.exe and the payload becomes a sibling
# akeeba-extract.phar the patched stub loads at run time. Only the clean stub is
# signed. Everything packaged below (NSIS/Inno installer or portable .zip) is
# built from PKG_DIR.
SIGNING=0
[[ -n "${WINDOWS_SIGN_OP_ITEM:-}" ]] && SIGNING=1

PKG_DIR="$SRC_DIR"   # what we package; the split staging dir when applicable
HAVE_PHAR=0

if LC_ALL=C grep -aq "next to this executable" "$WIN_BIN"; then
    # Patched, sibling-capable stub: split at phpmicro's SFX size (the section
    # end; pe-sfxsize.php also asserts Boson's extra-ini magic sits there).
    SFXSIZE="$(php "$PROJECT_ROOT/build/tasks/pe-sfxsize.php" "$WIN_BIN")" || {
        echo "ERROR: patched Windows SFX detected but could not locate the appended payload in" >&2
        echo "       $WIN_BIN (see the message above). Refusing to package a broken binary." >&2
        exit 1
    }
    STAGE_SPLIT="$PROJECT_ROOT/build/output/.stage-win-split"
    rm -rf "$STAGE_SPLIT"; mkdir -p "$STAGE_SPLIT"
    echo "Patched sibling-payload SFX detected: splitting $(( $(stat -f%z "$WIN_BIN") - SFXSIZE )) payload bytes into akeeba-extract.phar"
    head -c "$SFXSIZE" "$WIN_BIN" > "$STAGE_SPLIT/akeeba-extract.exe"
    tail -c "+$((SFXSIZE + 1))" "$WIN_BIN" > "$STAGE_SPLIT/akeeba-extract.phar"
    # The runtime DLL and mounted UI/language assets must sit beside the exe
    # (NSIS/Inno/zip copy them from PKG_DIR).
    cp "$SRC_DIR"/*.dll "$STAGE_SPLIT/" 2>/dev/null || true
    [[ -d "$SRC_DIR/public" ]]   && cp -R "$SRC_DIR/public"   "$STAGE_SPLIT/public"
    [[ -d "$SRC_DIR/language" ]] && cp -R "$SRC_DIR/language" "$STAGE_SPLIT/language"
    PKG_DIR="$STAGE_SPLIT"
    HAVE_PHAR=1
    # Sign the CLEAN stub (no appended payload) — this is the entire point.
    "$SCRIPT_DIR/sign-windows-exe.sh" "$STAGE_SPLIT/akeeba-extract.exe"
elif [[ "$SIGNING" = 1 ]]; then
    echo "" >&2
    echo "ERROR: cannot Authenticode-sign $WIN_BIN." >&2
    echo "  It was compiled against a STOCK Boson SFX, whose appended PHP payload sits" >&2
    echo "  after the executable. Signing it would append the certificate past the PHAR" >&2
    echo "  and corrupt its trailing signature (Phar::mapPhar fails at startup)." >&2
    echo "  Build the patched sibling-payload SFX into build/sfx/windows-x86_64.standard.sfx" >&2
    echo "  (build/fetch-sfx.sh) and recompile — see build/readme/02-signing-architecture.md." >&2
    exit 1
else
    echo "Note: unpatched Boson SFX — shipping the UNSIGNED combined akeeba-extract.exe (it works," >&2
    echo "      but is not code-signed). Add build/sfx/windows-x86_64.standard.sfx to sign it." >&2
fi

MAKENSIS="$(command -v makensis 2>/dev/null || true)"
ISCC="$(command -v iscc 2>/dev/null || command -v ISCC 2>/dev/null || true)"

if [[ -n "$MAKENSIS" ]]; then
    echo "Packaging Windows (amd64): NSIS installer (native makensis)"
    OUTFILE="$DIST/Akeeba-Extract-${VERSION}-windows-amd64-Setup.exe"
    # A split build ships akeeba-extract.phar beside the stub; tell the installer
    # to bundle it (the .nsi guards the extra File on HAVE_PHAR).
    NSIS_ARGS=(
        "-DSRCDIR=$PKG_DIR"
        "-DOUTFILE=$OUTFILE"
        "-DLICENSEFILE=$PROJECT_ROOT/LICENSE.txt"
        "-DICONFILE=$PROJECT_ROOT/build/extract.ico"
        "-DAPPVERSION=$VERSION"
        "-DVIVERSION=$VIVERSION"
    )
    [[ "$HAVE_PHAR" = 1 ]] && NSIS_ARGS+=("-DHAVE_PHAR=1")
    # makensis chdir's to the script dir, so pass ABSOLUTE source/output paths.
    "$MAKENSIS" -V2 "${NSIS_ARGS[@]}" build/windows-installer.nsi
    # Sign the installer executable itself too — it is a PE file end users run
    # directly. (It carries NSIS's own overlay, not a PHAR, so the sign guard in
    # sign-windows-exe.sh lets it through.)
    "$SCRIPT_DIR/sign-windows-exe.sh" "$OUTFILE"
    echo "Created: $OUTFILE"
elif [[ -n "$ISCC" ]]; then
    echo "Packaging Windows (amd64): Inno Setup installer (iscc)"
    # A split build ships akeeba-extract.phar beside the stub; point Inno at the
    # split staging dir and tell it to bundle the phar (the .iss guards the extra
    # file on HavePhar).
    ISS_ARGS=("/DAppVersion=$VERSION" "/DBinDir=$PKG_DIR")
    [[ "$HAVE_PHAR" = 1 ]] && ISS_ARGS+=("/DHavePhar=1")
    "$ISCC" "${ISS_ARGS[@]}" build/windows-installer.iss
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
    # PKG_DIR is the split staging dir (stub + akeeba-extract.phar + dll +
    # assets) when the binary was split above, otherwise the compiled output.
    cp -R "$PKG_DIR/." "$STAGE/"
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
