#!/usr/bin/env bash
# Refresh Cloudflare's published IPv4 / IPv6 range files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA="$ROOT/data"
mkdir -p "$DATA"

echo "[ranges] fetching Cloudflare IPv4 list..."
curl -fsSL --retry 3 -o "$DATA/ip.txt.new"   https://www.cloudflare.com/ips-v4
echo "[ranges] fetching Cloudflare IPv6 list..."
curl -fsSL --retry 3 -o "$DATA/ipv6.txt.new" https://www.cloudflare.com/ips-v6

mv "$DATA/ip.txt.new"   "$DATA/ip.txt"
mv "$DATA/ipv6.txt.new" "$DATA/ipv6.txt"
echo "[ranges] updated:"
wc -l "$DATA/ip.txt" "$DATA/ipv6.txt"
