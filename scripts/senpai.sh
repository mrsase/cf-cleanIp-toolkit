#!/usr/bin/env bash
# Launch the SenPaiScanner TUI in an attached terminal.
# This tool is interactive; it cannot run in a launchd / non-tty context.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCANNER="$ROOT/bin/senpaiscanner"
if [[ ! -x "$SCANNER" ]]; then
    echo "[senpai] missing binary: $SCANNER" >&2
    exit 1
fi
if [[ ! -t 1 ]]; then
    echo "[senpai] this tool requires an interactive TTY." >&2
    exit 1
fi
echo "[senpai] starting $($SCANNER --version 2>/dev/null || echo SenPaiScanner)"
echo "[senpai] tip: in Custom Scan, set Output to:"
echo "         $ROOT/results/senpai/senpai_$(date -u +%Y%m%dT%H%M%SZ).csv"
echo "         then run: cf-cleanIp-toolkit ingest <that-file> --engine senpai"
exec "$SCANNER" "$@"
