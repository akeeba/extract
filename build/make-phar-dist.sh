#!/usr/bin/env bash
# ============================================================================
# Akeeba Extract — PHAR distributable
# A cross-platform desktop application to extract Akeeba Backup archives
#
# Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
# License: GNU General Public License version 3, or later
#
# Usage:
#   ./build/make-phar-dist.sh
#
# Run `php vendor/bin/boson compile` first to produce build/output/phar/akeeba-extract.phar.
#
# Output: build/dist/Akeeba-Extract-<version>.phar
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

VERSION="${AKEEBA_EXTRACT_VERSION:-$(sed -nE "s/.*VERSION = '([^']+)'.*/\1/p" "$PROJECT_ROOT/src/App.php" | head -1)}"

PHAR_SRC="build/output/phar/akeeba-extract.phar"
DIST="$PROJECT_ROOT/build/dist"
mkdir -p "$DIST"

if [[ ! -f "$PHAR_SRC" ]]; then
    echo "ERROR: PHAR not found at: $PHAR_SRC" >&2
    echo "Run 'php vendor/bin/boson compile' first." >&2
    exit 1
fi

PHAR_OUT="$DIST/Akeeba-Extract-${VERSION}.phar"
cp "$PHAR_SRC" "$PHAR_OUT"

echo "Created: $PHAR_OUT"
