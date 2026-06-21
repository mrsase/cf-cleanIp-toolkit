#!/usr/bin/env bash
# Print project version info
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo "unknown")"
CFST_VER="$("$ROOT/bin/cfst" -v 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "not installed")"
SENPAI_VER="$("$ROOT/bin/senpaiscanner" -v 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "not installed")"

echo "tunnel v${VERSION}"
echo "  os/arch       : $(uname -s)/$(uname -m)"
echo "  cfst          : ${CFST_VER}"
echo "  senpaiscanner : ${SENPAI_VER}"
echo "  python        : $(python3 --version 2>/dev/null | cut -d' ' -f2 || echo "not found")"
