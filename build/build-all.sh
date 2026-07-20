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
#   2. Packages each platform's distributable into build/dist/:
#        - macOS : .app bundle + compressed .dmg  (per architecture; macOS host only)
#        - Linux : .tar.gz of the binary + runtime .so + public/
#        - Windows: NSIS installer (native cross-compile via `makensis`) if
#                   available, else Inno Setup's `iscc`, else a portable .zip.
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
DIST="build/dist"
APPVERSION="${AKEEBA_EXTRACT_VERSION:-$(sed -nE "s/.*VERSION = '([^']+)'.*/\1/p" src/App.php | head -1)}"

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
# 1. Fetch the patched sibling-payload micro.sfx runtimes (best effort)
# ---------------------------------------------------------------------------
# Makes macOS builds Developer-ID signable — see build/readme/01-macos-signing.md.
# Offline machines still build fine; affected targets just fall back to the
# stock (unsignable) Boson runtime.
heading "Fetching patched micro.sfx runtimes (build/fetch-sfx.sh)"
bash build/fetch-sfx.sh || warn "could not fetch all patched SFX runtimes — affected targets use the stock runtime"

heading "Fetching the Microsoft VC++ x64 runtime (build/fetch-vcredist.sh)"
bash build/fetch-vcredist.sh || warn "could not fetch the VC++ runtime — the Windows installer will not bundle it (users need the redistributable installed)"

# ---------------------------------------------------------------------------
# 2. Compile all targets (fatal on failure)
# ---------------------------------------------------------------------------
heading "Compiling binaries for all targets ($BOSON compile)"
if ! php "$BOSON" compile; then
    echo "ERROR: 'boson compile' failed. Aborting." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# 3. macOS — .app + .dmg, per architecture (macOS host only; needs hdiutil)
# ---------------------------------------------------------------------------
if [[ "$(uname -s)" == "Darwin" ]]; then
    for ARCH in arm64 amd64; do
        [[ "$ARCH" == "arm64" ]] && BOSON_DIR="aarch64" || BOSON_DIR="$ARCH"
        BIN="$OUT/macos/$BOSON_DIR/akeeba-extract"

        if [[ -f "$BIN" ]]; then
            heading "Packaging macOS ($ARCH): .app + .dmg"
            if bash build/macos-app.sh "$ARCH" && bash build/make-dmg.sh "$ARCH"; then
                PRODUCED+=("$DIST/Akeeba-Extract-${APPVERSION}-macos-${ARCH}.dmg")
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
# 4. Linux — .tar.gz (portable: binary + libboson .so + public/)
# ---------------------------------------------------------------------------
LINUX_BIN="$OUT/linux/amd64/akeeba-extract"
if [[ -f "$LINUX_BIN" ]]; then
    heading "Packaging Linux (amd64): .tar.gz"
    if bash build/make-linux-tarball.sh amd64; then
        PRODUCED+=("$DIST/Akeeba-Extract-${APPVERSION}-linux-amd64.tar.gz")
    else
        warn "Linux tarball failed"
        FAIL=1
    fi
else
    warn "Linux binary missing ($LINUX_BIN) — skipped"
fi

# ---------------------------------------------------------------------------
# 4. Windows — NSIS installer, Inno Setup installer, or a portable .zip
# ---------------------------------------------------------------------------
WIN_BIN="$OUT/windows/amd64/akeeba-extract.exe"
if [[ -f "$WIN_BIN" ]]; then
    if bash build/make-windows-installer.sh; then
        if [[ -f "$DIST/Akeeba-Extract-${APPVERSION}-windows-amd64-Setup.exe" ]]; then
            PRODUCED+=("$DIST/Akeeba-Extract-${APPVERSION}-windows-amd64-Setup.exe")
        else
            PRODUCED+=("$DIST/Akeeba-Extract-${APPVERSION}-windows-amd64.zip")
        fi
    else
        warn "Windows packaging failed"
        FAIL=1
    fi
else
    warn "Windows binary missing ($WIN_BIN) — skipped"
fi

# ---------------------------------------------------------------------------
# 5. PHAR (cross-platform; emitted by the compiler)
# ---------------------------------------------------------------------------
if [[ -f "$OUT/phar/akeeba-extract.phar" ]]; then
    if bash build/make-phar-dist.sh; then
        PRODUCED+=("$DIST/Akeeba-Extract-${APPVERSION}.phar")
    else
        warn "PHAR packaging failed"
        FAIL=1
    fi
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
