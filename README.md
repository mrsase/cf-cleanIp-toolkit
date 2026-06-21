# tunnel — Cloudflare Clean IP Toolkit

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Go](https://img.shields.io/badge/CFST-v2.3.5-00ADD8?logo=go)]()
[![Go](https://img.shields.io/badge/SenPaiScanner-v0.5.0-00ADD8?logo=go)]()

**tunnel** scans Cloudflare's edge network from your location, finds the lowest-latency / most responsive IPs, and stores every measurement in a local SQLite database. Query the best IPs at any time, export them, and track performance trends over days and weeks.

Two battle-tested scanner engines are bundled:

| Engine | Mode | Best for |
|--------|------|----------|
| **CloudflareSpeedTest** ([XIU2](https://github.com/XIU2/CloudflareSpeedTest) v2.3.5) | Headless CLI | Scheduled scans, scripting, CI/CD |
| **SenPaiScanner** ([MatinSenPai](https://github.com/MatinSenPai/SenPaiScanner) v0.5.0) | Interactive TUI | Hands-on exploration, custom configs |

---

## Features

- **Dual-engine** — automated batch scanning + interactive TUI exploration
- **SQLite-backed** — all results persisted and queryable
- **Trend analysis** — track IP performance over days/weeks with `history`
- **Export** — best IPs to JSON, CSV, or plain text
- **Scheduling** — built-in `launchd` integration for daily macOS scans
- **Cross-platform** — macOS (arm64/amd64) and Linux (arm64/amd64/386)
- **Zero configuration** — scan right after install; no API keys needed

---

## Installation

### Quick install (recommended)

```bash
git clone https://github.com/<your-org>/tunnel.git
cd tunnel
./install.sh
```

The installer will:
1. Detect your OS and CPU architecture
2. Download the correct scanner binaries
3. Fetch the latest Cloudflare IP ranges
4. Initialize the SQLite database
5. Optionally add `tunnel` to your `PATH`

### Manual install

```bash
# Download binaries for your platform
make build

# Or fetch IP ranges manually
./tunnel update ranges

# Create the database
sqlite3 db/clean_ips.db < scripts/schema.sql
```

### Dependencies

- **Python 3** — for database ingestion, querying, and export scripts
- **SQLite 3** — local data store
- **curl** or **wget** — for downloading binaries and IP ranges

---

## Usage

### Scanning

```bash
# Quick TCPing scan (recommended for most users)
./tunnel scan

# HTTP latency scan (more realistic for proxy use)
./tunnel scan --httping

# Fast filter (no download speed test)
./tunnel scan --fast

# IPv6 scan
./tunnel scan --ipv6

# Custom CFST flags
./tunnel scan -- -n 500 -tl 150 -sl 5 -dn 20

# Interactive TUI scanner
./tunnel senpai
```

### Querying results

```bash
# Top 10 best IPs (IPv4, last 14 days)
./tunnel top

# Top 50, with filters
./tunnel top -n 50 --max-latency 120 --min-speed 5

# Top IPv6 only
./tunnel top --family 6 -n 20

# Raw IP list (one per line, for piping)
./tunnel top --raw -n 30 > /tmp/best.txt
```

### Exporting

```bash
./tunnel export -n 100 --format json
./tunnel export -n 50  --format txt -o /tmp/cf.txt
./tunnel export -n 200 --format csv
```

### System management

```bash
./tunnel status          # one-page system overview
./tunnel history         # last 10 scans + DB stats
./tunnel history --scan 3  # rows from scan ID 3
./tunnel update ranges   # refresh Cloudflare IP range files
```

### Scheduling (macOS)

A `launchd` agent runs the scheduled scan every day at 04:17.

```bash
./tunnel install         # load the daily agent
./tunnel install unload  # uninstall the agent
```

Default scheduled scan: HTTPing, latency ≤ 250 ms, loss ≤ 0.3, 3 download samples, top 20 results.

### Ingesting external CSVs

If you run SenPaiScanner manually (or any CFST-compatible scanner):

```bash
./tunnel ingest results/senpai/senpai_<ts>.csv --engine senpai
./tunnel ingest results/cfst/cfst_<ts>.csv --engine cfst
```

---

## Database

**Location:** `db/clean_ips.db` (SQLite, WAL mode)

### Schema

| Table | Description |
|-------|-------------|
| `scans` | One row per scan run (engine, mode, args, CSV path, IP count, status, timing) |
| `clean_ips` | One row per IP measurement (IP, family, loss, latency, speed, colo, timestamp) |

### Views

| View | Description |
|------|-------------|
| `latest_per_ip` | Most recent measurement per IP |
| `best_recent` | Aggregated stats per IP over the last 14 days |

### Ad-hoc queries

```bash
sqlite3 db/clean_ips.db

# Best IPs by latency in the last 3 days
SELECT ip, MIN(latency_ms), AVG(speed_mbps)
FROM clean_ips
WHERE measured_at > datetime('now', '-3 days')
GROUP BY ip
ORDER BY 2 LIMIT 30;
```

---

## Project structure

```
tunnel/
├── tunnel                  # Main CLI dispatcher
├── install.sh              # Install script
├── Makefile                # Build / release / lint targets
├── VERSION                 # Current version
├── bin/                    # Scanner binaries (downloaded by install)
├── scripts/
│   ├── scan.sh             # CFST scan wrapper
│   ├── scheduled_scan.sh   # launchd daily scan
│   ├── senpai.sh           # SenPaiScanner launcher
│   ├── store.py            # CSV → SQLite ingestion
│   ├── top.py              # Best-IP queries
│   ├── export.py           # Export to JSON/CSV/TXT
│   ├── history.py          # Scan history & DB stats
│   ├── schema.sql          # Database schema
│   ├── update-ranges.sh    # Refresh CF IP range files
│   └── prepare-release.sh  # Cross-platform release builds
├── data/                   # Cloudflare IP ranges (v4/v6)
├── db/                     # SQLite database
├── exports/                # Exported IP lists
├── results/cfst/           # Raw CFST scan CSVs
├── results/senpai/         # Raw SenPaiScanner CSVs
├── logs/                   # Scheduled-scan logs
└── launchd/                # launchd plist source (macOS)
```

---

## Development

### Prerequisites

- Go 1.21+ (to rebuild scanner binaries from source)
- Python 3.8+
- shellcheck (for linting shell scripts)

### Commands

```bash
make lint     # Check shell scripts
make check   # Verify installation health
make build   # Download binaries for current arch
make release # Build release tarballs for all archs
make clean   # Remove downloaded binaries
```

### Building from source

The scanner binaries (`cfst` and `senpaiscanner`) are pre-built Go programs. To rebuild them:

```bash
git clone https://github.com/XIU2/CloudflareSpeedTest
cd CloudflareSpeedTest && go build -o ../tunnel/bin/cfst

git clone https://github.com/MatinSenPai/SenPaiScanner
cd SenPaiScanner && go build -o ../tunnel/bin/senpaiscanner
```

---

## Notes

- **macOS Gatekeeper:** First run may be blocked. Run `xattr -d com.apple.quarantine bin/cfst bin/senpaiscanner` if needed.
- **Network scanning:** CFST sends up to 200 concurrent probes. On a home/laptop network this is fine; on a server it may trip abuse alarms.
- **Speed = 0 MB/s:** Means no download test was run (`-dd` flag). Use default `scan` mode for speed data.
- **SenPaiScanner is TUI-only:** Requires a TTY; won't work from `launchd` or cron.
- All scans run as your user — no root privileges needed.

---

## License

[MIT](LICENSE)
