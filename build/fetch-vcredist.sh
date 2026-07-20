#!/usr/bin/env bash
#
# Akeeba Extract — extracts Akeeba Backup archives on your desktop.
# Copyright (c) 2026 Nicholas K. Dionysopoulos / Akeeba Ltd
# GNU General Public License version 3, or later.
#
# Extract the Microsoft Visual C++ x64 runtime DLLs into build/redist/win-x64/,
# for app-local deployment beside akeeba-extract.exe.
#
# WHY: libboson-windows-x86_64.dll (the Boson/saucer WebView runtime) imports
# MSVCP140.dll, MSVCP140_ATOMIC_WAIT.dll, VCRUNTIME140.dll and
# VCRUNTIME140_1.dll. None of these ship with Windows — they come from the VC++
# redistributable. Installing that redistributable requires administrator
# rights, but our NSIS/Inno installers are deliberately per-user
# (PrivilegesRequired=lowest), so we cannot invoke it. Shipping the four DLLs
# next to the exe is the supported alternative: Windows searches the process
# executable's own directory first when resolving a DLL's dependencies, and
# app-local deployment of the VC++ runtime is permitted by Microsoft's
# redistributable terms.
#
# MSVCP140_ATOMIC_WAIT.dll is the one that is easy to miss: it only exists from
# Visual Studio 2019 16.7 onwards, so a machine carrying an older VC++
# redistributable satisfies the other three and still fails to load the Boson
# runtime.
#
# The four are dependency-closed: they import only each other plus Windows
# system DLLs (kernel32, ntdll, advapi32, api-ms-win-crt-*).
#
# Usage:  build/fetch-vcredist.sh [--force]
#   --force   re-download and re-extract even when the DLLs are already present
#
# Requires: curl, cabextract (brew install cabextract).
#
# This is best-effort, like build/fetch-sfx.sh: on failure it leaves nothing
# behind and exits non-zero, and packaging still succeeds — it just warns and
# ships without the runtime, which works on any machine that already has the
# redistributable installed.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/build/redist/win-x64"
URL="https://aka.ms/vs/17/release/vc_redist.x64.exe"

# The four DLLs libboson-windows-x86_64.dll actually imports. Add to this list
# only if a future Boson runtime's import table grows — check with:
#   python3 -c "..."  (see build/readme/ for the PE import dump helper)
WANTED=(msvcp140 msvcp140_atomic_wait vcruntime140 vcruntime140_1)

FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

# Already there? Nothing to do.
if [ "$FORCE" != 1 ]; then
    ALL_PRESENT=1
    for n in "${WANTED[@]}"; do
        [ -f "$DEST/$n.dll" ] || ALL_PRESENT=0
    done
    if [ "$ALL_PRESENT" = 1 ]; then
        echo "✓ VC++ runtime DLLs already present in build/redist/win-x64/ (use --force to refresh)"
        exit 0
    fi
fi

if ! command -v cabextract >/dev/null 2>&1; then
    echo "ERROR: 'cabextract' is required to unpack the VC++ redistributable." >&2
    echo "       Install it with: brew install cabextract" >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading the Microsoft VC++ x64 redistributable …"
if ! curl -fsSL -o "$TMP/vc_redist.x64.exe" "$URL"; then
    echo "  ✗ download failed — $URL" >&2
    exit 1
fi

# vc_redist.x64.exe is a WiX "burn" bundle: a PE stub followed by two embedded
# cabinets. The first (UX) container holds the installer's own resources; the
# second (attached) container holds the payload MSIs and cabinets, one of which
# carries the x64 CRT. 7-Zip only unpacks the UX container, so we locate the
# attached one by scanning for the second MSCF magic and carve it out.
echo "Locating the attached payload container …"
OFFSET="$(python3 - "$TMP/vc_redist.x64.exe" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
offs, i = [], 0
while True:
    i = d.find(b'MSCF', i)
    if i < 0:
        break
    offs.append(i)
    i += 4
# [0] is the UX container, [1] is the attached payload container.
print(offs[1] if len(offs) > 1 else -1)
PY
)"

if [ "$OFFSET" -lt 0 ]; then
    echo "  ✗ could not find the attached cabinet inside vc_redist.x64.exe." >&2
    echo "    Microsoft may have changed the bundle format; extract manually." >&2
    exit 1
fi

python3 - "$TMP/vc_redist.x64.exe" "$OFFSET" "$TMP/attached.cab" <<'PY'
import sys
d = open(sys.argv[1], 'rb').read()
open(sys.argv[3], 'wb').write(d[int(sys.argv[2]):])
PY

mkdir -p "$TMP/att"
cabextract -q -d "$TMP/att" "$TMP/attached.cab" >/dev/null 2>&1 || true

# The payload cabinets are named a0, a1, … with no extension. The x64 CRT lives
# in whichever one contains "vcruntime140.dll_amd64"; find it rather than
# hard-coding an index, since the ordering shifts between redist releases.
CRTCAB=""
for f in "$TMP/att"/*; do
    [ -f "$f" ] || continue
    if cabextract -l "$f" 2>/dev/null | grep -q 'vcruntime140\.dll_amd64'; then
        CRTCAB="$f"
        break
    fi
done

if [ -z "$CRTCAB" ]; then
    echo "  ✗ no payload cabinet containing the x64 CRT was found." >&2
    exit 1
fi

mkdir -p "$DEST"
FAILED=0
for n in "${WANTED[@]}"; do
    if cabextract -q -F "$n.dll_amd64" -d "$TMP" "$CRTCAB" >/dev/null 2>&1 \
       && [ -f "$TMP/$n.dll_amd64" ]; then
        mv "$TMP/$n.dll_amd64" "$DEST/$n.dll"
        echo "  ✓ $n.dll ($(stat -f%z "$DEST/$n.dll") bytes)"
    else
        echo "  ✗ $n.dll_amd64 not found in $(basename "$CRTCAB")" >&2
        FAILED=1
    fi
done

exit $FAILED
