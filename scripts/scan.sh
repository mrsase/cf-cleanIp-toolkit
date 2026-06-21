#!/usr/bin/env bash
# Run a CloudflareSpeedTest scan and store results.
# All output is in English - the cfst binary output is suppressed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CFST="$ROOT/bin/cfst"
PYTHON="${PYTHON:-/usr/bin/env python3}"
STORE="$ROOT/scripts/store.py"
TOP="$ROOT/scripts/top.py"
RESULTS_DIR="$ROOT/results/cfst"
DATA_DIR="$ROOT/data"
LOG_DIR="$ROOT/logs"

mkdir -p "$RESULTS_DIR" "$LOG_DIR"

if [[ ! -x "$CFST" ]]; then
    echo "Error: cfst binary not found or not executable: $CFST" >&2
    exit 1
fi

MODE="tcping"
FAMILY="v4"
EXTRA_ARGS=()
FAST=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --httping)  MODE="httping"; shift ;;
        --tcping)   MODE="tcping";  shift ;;
        --ipv6)     FAMILY="v6";    shift ;;
        --ipv4)     FAMILY="v4";    shift ;;
        --fast)     FAST=1;         shift ;;
        --)         shift; EXTRA_ARGS+=("$@"); break ;;
        -h|--help)
            sed -n '2,12p' "$0"; exit 0 ;;
        *)
            EXTRA_ARGS+=("$1"); shift ;;
    esac
done

TS="$(date -u +%Y%m%dT%H%M%SZ)"
CSV="$RESULTS_DIR/cfst_${MODE}_${FAMILY}_${TS}.csv"

if [[ "$FAMILY" == "v6" ]]; then
    IP_FILE="$DATA_DIR/ipv6.txt"
else
    IP_FILE="$DATA_DIR/ip.txt"
fi

CFST_ARGS=(-o "$CSV" -f "$IP_FILE")
if [[ "$MODE" == "httping" ]]; then
    CFST_ARGS+=(-httping)
fi
if [[ "$FAST" == "1" ]]; then
    CFST_ARGS+=(-dd -n 200 -t 4 -p 0)
fi
if [[ ${#EXTRA_ARGS[@]} -gt 0 ]]; then
    CFST_ARGS+=("${EXTRA_ARGS[@]}")
fi

echo ">>> Cloudflare IP Scanner"
echo "    mode          : $MODE"
echo "    address family: $FAMILY"
echo "    output        : $CSV"

set +e
"$CFST" "${CFST_ARGS[@]}" >/dev/null 2>/dev/null
rc=$?
set -e

if [[ ! -s "$CSV" ]]; then
    echo "Error: scan failed (exit code $rc) - no results produced" >&2
    exit "${rc:-1}"
fi

ARGS_STR="${CFST_ARGS[*]}"
$PYTHON "$STORE" --csv "$CSV" --engine cfst --mode "$MODE" --args "$ARGS_STR"

echo ""
BEST_JSON=$($PYTHON "$TOP" -n 1 --format json 2>/dev/null)
if [[ -n "$BEST_JSON" ]] && [[ "$BEST_JSON" != "[]" ]]; then
    BEST_IP=$(echo "$BEST_JSON" | $PYTHON -c "import json,sys; r=json.load(sys.stdin); print(f\"{r[0]['ip']} @ {r[0]['best_latency_ms']}ms\")" 2>/dev/null)
    echo ">>> Scan complete - best IP: $BEST_IP"
else
    echo ">>> Scan complete - no clean IPs found"
fi
exit "$rc"
