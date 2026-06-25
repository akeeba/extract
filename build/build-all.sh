#!/usr/bin/env bash
# ============================================================================
# Akeeba Extract — build & package everything, for every supported platform
# A cross-platform desktop application to extract Akeeba Backup archives
#
# Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
# License: GNU General Public License version 3, or later
#
# This is the one-shot build pipeline invoked by `composer build` (and
# automatically by `composer update`). It:
#
#   1. Compiles self-contained binaries for all targets (php vendor/bin/boson
#      compile → macOS arm64/amd64, Windows amd64, Linux amd64, PHAR).
#   2. Packages each platform's distributable:
#        - macOS : .app bundle + compressed .dmg  (per architecture; macOS host only)
#        - Linux : .tar.gz of the binary + runtime .so + public/
#        - Windows: Inno Setup installer if `iscc` is available, otherwise a
#                   portable .zip fallback (the signed installer is built on
#                   Windows from build/windows-installer.iss).
#
# Design notes for the `composer update` hook:
#   - If the Boson compiler is absent (e.g. `composer update --no-dev`), the
#     script no-ops with a friendly message and exit 0, so it never breaks an
#     update that simply didn't install dev tools.
#   - A failing `boson compile` is fatal (exit 1). Per-platform packaging is
#     tolerant: a missing binary is a skip (warning), but a packaging tool
#     that genuinely errors marks the run as failed (exit 1) so problems stay
#     visible.
# ============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

BOSON="vendor/bin/boson"
OUT="build/output"
APPVERSION="1.0.0"

PRODUCED=()
WARNINGS=()
FAIL=0

heading() { printf '\n==> %s\n' "$*"; }
warn()    { echo "  WARNING: $*" >&2; WARNINGS+=("$*"); }

# ---------------------------------------------------------------------------
# 0. Guard — is the Boson compiler available? (skip cleanly if not)
# ---------------------------------------------------------------------------
if [[ ! -f "$BOSON" ]]; then
    echo "Akeeba Extract: '$BOSON' not found — skipping build/package."
    echo "  Run 'composer install' (with dev dependencies) to enable building."
    exit 0
fi

# ---------------------------------------------------------------------------
# 1. Compile all targets (fatal on failure)
# ---------------------------------------------------------------------------
heading "Compiling binaries for all targets ($BOSON compile)"
if ! php "$BOSON" compile; then
    echo "ERROR: 'boson compile' failed. Aborting." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. macOS — .app + .dmg, per architecture (macOS host only; needs hdiutil)
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" == "Darwin" ]]; then
    for ARCH in arm64 amd64; do
        [[ "$ARCH" == "arm64" ]] && BOSON_DIR="aarch64" || BOSON_DIR="$ARCH"
        BIN="$OUT/macos/$BOSON_DIR/akeeba-extract"

        if [[ -f "$BIN" ]]; then
            heading "Packaging macOS ($ARCH): .app + .dmg"
            if bash build/macos-app.sh "$ARCH" && bash build/make-dmg.sh "$ARCH"; then
                PRODUCED+=("$OUT/Akeeba-Extract-${ARCH}.dmg")
            else
                warn "macOS $ARCH packaging failed"
                FAIL=1
            fi
        else
            warn "macOS $ARCH binary missing ($BIN) — skipped"
        fi
    done
else
    warn "Host is not macOS — skipping .app/.dmg packaging (run on macOS to build these)"
fi

# ---------------------------------------------------------------------------
# 3. Linux — .tar.gz (portable: binary + libboson .so + public/)
# ---------------------------------------------------------------------------
LINUX_BIN="$OUT/linux/amd64/akeeba-extract"
if [[ -f "$LINUX_BIN" ]]; then
    heading "Packaging Linux (amd64): .tar.gz"
    STAGE="$OUT/.stage-linux/akeeba-extract"
    rm -rf "$OUT/.stage-linux"; mkdir -p "$STAGE"
    cp -R "$OUT/linux/amd64/." "$STAGE/"

    # Desktop integration: ship the icon, a .desktop launcher and an installer
    # so users get the Akeeba Extract icon in their menus (see build/linux-install.sh).
    cp "build/extract.png"             "$STAGE/akeeba-extract.png"
    cp "build/akeeba-extract.desktop"  "$STAGE/akeeba-extract.desktop"
    cp "build/linux-install.sh"        "$STAGE/install.sh"
    chmod +x "$STAGE/install.sh"

    TGZ="$OUT/Akeeba-Extract-linux-amd64.tar.gz"
    rm -f "$TGZ"
    if tar -czf "$TGZ" -C "$OUT/.stage-linux" akeeba-extract; then
        PRODUCED+=("$TGZ")
    else
        warn "Linux tarball failed"
        FAIL=1
    fi
    rm -rf "$OUT/.stage-linux"
else
    warn "Linux binary missing ($LINUX_BIN) — skipped"
fi

# ---------------------------------------------------------------------------
# 4. Windows — Inno Setup installer if available, else a portable .zip
# ---------------------------------------------------------------------------
WIN_BIN="$OUT/windows/amd64/akeeba-extract.exe"
if [[ -f "$WIN_BIN" ]]; then
    # Preferred: NSIS — its `makensis` compiler runs natively on macOS/Linux,
    # so the installer cross-compiles from this host (no Wine/Docker/Windows).
    # Fallbacks: Inno Setup's `iscc` (e.g. on a Windows host), else a portable .zip.
    MAKENSIS="$(command -v makensis 2>/dev/null || true)"
    ISCC="$(command -v iscc 2>/dev/null || command -v ISCC 2>/dev/null || true)"

    if [[ -n "$MAKENSIS" ]]; then
        heading "Packaging Windows (amd64): NSIS installer (native makensis)"
        # makensis chdir's to the script dir, so pass ABSOLUTE source/output paths.
        if "$MAKENSIS" -V2 \
            "-DSRCDIR=$PROJECT_ROOT/$OUT/windows/amd64" \
            "-DOUTFILE=$PROJECT_ROOT/$OUT/Akeeba-Extract-Setup.exe" \
            "-DLICENSEFILE=$PROJECT_ROOT/LICENSE.txt" \
            "-DICONFILE=$PROJECT_ROOT/build/extract.ico" \
            "-DAPPVERSION=$APPVERSION" \
            build/windows-installer.nsi; then
            PRODUCED+=("$OUT/Akeeba-Extract-Setup.exe")
        else
            warn "NSIS (makensis) build failed"
            FAIL=1
        fi
    elif [[ -n "$ISCC" ]]; then
        heading "Packaging Windows (amd64): Inno Setup installer (iscc)"
        if "$ISCC" build/windows-installer.iss; then
            PRODUCED+=("$OUT/Akeeba-Extract-Setup.exe")
        else
            warn "Inno Setup (iscc) build failed"
            FAIL=1
        fi
    else
        heading "Packaging Windows (amd64): portable .zip (no installer compiler found)"
        warn "No installer compiler found — produced a portable .zip. Install NSIS ('brew install makensis') for a native Windows installer, or build build/windows-installer.iss on Windows."
        STAGE="$OUT/.stage-win/Akeeba Extract"
        rm -rf "$OUT/.stage-win"; mkdir -p "$STAGE"
        cp -R "$OUT/windows/amd64/." "$STAGE/"
        cp "build/extract.ico" "$STAGE/extract.ico"
        ZIP_OUT="$OUT/Akeeba-Extract-windows-amd64.zip"
        rm -f "$ZIP_OUT"
        if command -v zip >/dev/null 2>&1; then
            if ( cd "$OUT/.stage-win" && zip -qr "../Akeeba-Extract-windows-amd64.zip" "Akeeba Extract" ); then
                PRODUCED+=("$ZIP_OUT")
            else
                warn "Windows .zip packaging failed"
                FAIL=1
            fi
        else
            warn "'zip' not available — skipped Windows .zip"
        fi
        rm -rf "$OUT/.stage-win"
    fi
else
    warn "Windows binary missing ($WIN_BIN) — skipped"
fi

# ---------------------------------------------------------------------------
# 5. PHAR (cross-platform; emitted by the compiler)
# ---------------------------------------------------------------------------
if [[ -f "$OUT/phar/akeeba-extract.phar" ]]; then
    PRODUCED+=("$OUT/phar/akeeba-extract.phar")
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
heading "Build summary"
if [[ ${#PRODUCED[@]} -gt 0 ]]; then
    echo "Artifacts:"
    for a in "${PRODUCED[@]}"; do echo "  [ok] $a"; done
else
    echo "No artifacts were produced."
    FAIL=1
fi
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
    echo "Notes:"
    for w in "${WARNINGS[@]}"; do echo "  [!]  $w"; done
fi

exit "$FAIL"
