#!/usr/bin/env bash
# Conservative daily scan invoked by launchd.
# Runs a short HTTPing-based test (closer to real proxy traffic) limited
# to a small number of fast IPs to keep CPU + bandwidth use modest.
#
# Anything written to stdout / stderr goes to logs/scan.log and scan.err.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT/logs"
mkdir -p "$LOG_DIR"

START="$(date -u +%FT%TZ)"
echo "==== scheduled scan start $START ====" >&2

# Daily IPv4 scan: HTTPing mode, top 20 sorted, latency threshold 250ms,
# 3 download samples for ranking. Tweak as needed.
"$ROOT/scripts/scan.sh" --httping -- \
    -n 200 -t 4 -dn 3 -dt 8 -tl 250 -tlr 0.3 -p 20

END="$(date -u +%FT%TZ)"
echo "==== scheduled scan end   $END ====" >&2
