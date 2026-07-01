#!/usr/bin/env bash
# ============================================================================
# Akeeba Extract — Linux tarball creator
# A cross-platform desktop application to extract Akeeba Backup archives
#
# Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
# License: GNU General Public License version 3, or later
#
# Usage:
#   ./build/make-linux-tarball.sh [ARCH]
#
# ARCH can be: amd64 (default; the only target boson.json currently builds)
#
# Run `php vendor/bin/boson compile` first to produce the Linux binary in
# build/output/linux/<ARCH>/.
#
# Output: build/dist/Akeeba-Extract-<version>-linux-<ARCH>.tar.gz
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

ARCH="${1:-amd64}"
VERSION="${AKEEBA_EXTRACT_VERSION:-$(sed -nE "s/.*VERSION = '([^']+)'.*/\1/p" "$PROJECT_ROOT/src/App.php" | head -1)}"

LINUX_BIN="build/output/linux/$ARCH/akeeba-extract"
DIST="$PROJECT_ROOT/build/dist"
mkdir -p "$DIST"

if [[ ! -f "$LINUX_BIN" ]]; then
    echo "ERROR: Linux binary not found at: $LINUX_BIN" >&2
    echo "Run 'php vendor/bin/boson compile' first." >&2
    exit 1
fi

echo "Packaging Linux ($ARCH): .tar.gz"

STAGE="build/output/.stage-linux/akeeba-extract"
rm -rf "build/output/.stage-linux"; mkdir -p "$STAGE"
cp -R "build/output/linux/$ARCH/." "$STAGE/"

# Desktop integration: ship the icon, a .desktop launcher and an installer
# so users get the Akeeba Extract icon in their menus (see build/linux-install.sh).
cp "build/extract.png"             "$STAGE/akeeba-extract.png"
cp "build/akeeba-extract.desktop"  "$STAGE/akeeba-extract.desktop"
cp "build/linux-install.sh"        "$STAGE/install.sh"
chmod +x "$STAGE/install.sh"

TGZ="$DIST/Akeeba-Extract-${VERSION}-linux-${ARCH}.tar.gz"
rm -f "$TGZ"
tar -czf "$TGZ" -C "build/output/.stage-linux" akeeba-extract
rm -rf "build/output/.stage-linux"

echo "Created: $TGZ"
