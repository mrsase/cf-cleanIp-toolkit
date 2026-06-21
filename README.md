# tunnel — Cloudflare Clean IP Toolkit

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

**tunnel** scans Cloudflare's edge network from your location, finds the
lowest-latency / most responsive IPs, and stores every measurement in a
local SQLite database so you can query, export, and track performance
trends over days and weeks.

```
                         ┌─────────────────┐
                         │   Cloudflare     │
                         │   Edge Network   │
                         └────────┬────────┘
                                  │ probes
                         ┌────────▼────────┐
                         │    tunnel       │
                         │  (this project) │
                         └──┬──────┬───────┘
                            │      │
                    ┌───────▼┐  ┌──▼────────┐
                    │ cfst   │  │ SenPai    │
                    │ (batch)│  │ (interact)│
                    └───┬────┘  └─────┬─────┘
                        │             │
                        ▼             ▼
                    ┌──────────────────────┐
                    │   SQLite Database    │
                    │   (db/clean_ips.db)  │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │  tunnel top / export │
                    │  tunnel history      │
                    └──────────────────────┘
```

## Installation

### Option A — Download a release (recommended)

Grab the tarball for your platform from the
[Releases page](https://github.com/<your-org>/tunnel/releases), then:

```bash
tar -xzf tunnel-<your-os>-<your-arch>.tar.gz
cd tunnel-<your-os>-<your-arch>
./install.sh
```

The tarball comes with pre-compiled binaries — no Go toolchain needed.

### Option B — Build from source

```bash
git clone https://github.com/<your-org>/tunnel.git
cd tunnel
./install.sh           # compiles cfst + senpaiscanner from upstream source
```

Requires [Go](https://go.dev/doc/install) 1.21+. The installer auto-detects
your OS/arch, clones the upstream scanner repos, and compiles them.

### Dependencies

- **Python 3** — for data ingestion, querying, and export
- **SQLite 3** — embedded database
- **curl** — for downloading IP ranges

---

## Usage

### Scanning

```bash
./tunnel scan                  # TCPing scan (recommended default)
./tunnel scan --httping        # HTTP latency scan (more realistic)
./tunnel scan --fast           # Quick filter, no download test
./tunnel scan --ipv6           # IPv6 ranges
./tunnel scan -- -n 500 -tl 150    # Custom CFST flags
./tunnel senpai                # Interactive TUI scanner
```

### Query & export

```bash
./tunnel top                              # Top 10 (IPv4, 14 days)
./tunnel top -n 50 --max-latency 120      # Filtered
./tunnel top --family 6 -n 20             # IPv6 only
./tunnel top --raw -n 30 > /tmp/ips.txt   # Plain IP list

./tunnel export -n 100 --format json
./tunnel export -n 50 --format txt -o /tmp/out.txt
```

### System

```bash
./tunnel status                # One-page overview
./tunnel history               # Last 10 scans + DB stats
./tunnel history --scan 3      # Rows from scan ID 3
./tunnel update ranges         # Refresh Cloudflare IP ranges
./tunnel version               # Version info
```

### Scheduling (macOS)

```bash
./tunnel install               # Load daily launchd agent (04:17)
./tunnel install unload        # Unload the agent
```

### Ingest external CSVs

```bash
./tunnel ingest results/senpai/senpai_<ts>.csv --engine senpai
./tunnel ingest results/cfst/cfst_<ts>.csv --engine cfst
```

---

## Database

**Location:** `db/clean_ips.db` (SQLite, WAL mode)

| Table / View | Description |
|---|---|
| `scans` | One row per scan run |
| `clean_ips` | One row per IP measurement |
| `latest_per_ip` | Most recent measurement per IP |
| `best_recent` | Aggregated stats over the last 14 days |

```bash
sqlite3 db/clean_ips.db "SELECT ip, MIN(latency_ms), AVG(speed_mbps)
  FROM clean_ips WHERE measured_at > datetime('now','-3 days')
  GROUP BY ip ORDER BY 2 LIMIT 30;"
```

---

## Project structure

```
tunnel/
├── tunnel                  # CLI dispatcher
├── install.sh              # Installer (download or compile)
├── Makefile                # build / release / lint / check
├── VERSION                 # Current version
├── LICENSE                 # MIT
├── bin/                    # Scanner binaries
├── scripts/
│   ├── build-scanners.sh   # Compile cfst + senpai from source
│   ├── scan.sh             # CFST scan wrapper
│   ├── scheduled_scan.sh   # launchd daily scan
│   ├── senpai.sh           # SenPaiScanner launcher
│   ├── store.py            # CSV → SQLite ingestion
│   ├── top.py              # Best-IP queries
│   ├── export.py           # Export to JSON/CSV/TXT
│   ├── history.py          # Scan history & stats
│   ├── schema.sql          # Database schema
│   ├── update-ranges.sh    # Refresh CF IP range files
│   └── version.sh          # Version info
├── data/                   # Cloudflare IP ranges (v4/v6)
├── db/                     # SQLite database
├── launchd/                # macOS launchd plist
├── exports/                # Exported IP lists
├── results/cfst/           # Raw CFST scan CSVs
├── results/senpai/         # Raw SenPaiScanner CSVs
└── logs/                   # Scheduled-scan logs
```

---

## Development

```bash
make build       # Compile scanners for current arch
make release     # Build release tarballs for all platforms
make check       # Verify installation health
make lint        # Shellcheck
make clean       # Remove compiled binaries
```

---

## Credits

tunnel is a **wrapper / orchestrator** that builds on these excellent open-source projects:

### CloudflareSpeedTest (cfst) — [XIU2/CloudflareSpeedTest](https://github.com/XIU2/CloudflareSpeedTest)

The headless batch scanner. Probes thousands of Cloudflare IPs in parallel
using TCPing or HTTPing, measures latency, packet loss, and download speed,
then outputs a ranked CSV. Licensed under GPL-3.0.

- **Author:** XIU2
- **Version bundled:** v2.3.5
- **License:** GPL-3.0

### SenPaiScanner — [MatinSenPai/SenPaiScanner](https://github.com/MatinSenPai/SenPaiScanner)

The interactive TUI scanner. Provides a full terminal UI for live
scanning with custom configs, Xray validation, and neighbor discovery.
Licensed under GPL-3.0.

- **Author:** MatinSenPai
- **Version bundled:** v0.5.0
- **License:** GPL-3.0

### How tunnel relates to these projects

tunnel does **not** fork or modify the upstream scanners. It:

1. Downloads or compiles the upstream binaries
2. Wraps them with a unified CLI (`tunnel scan`, `tunnel senpai`)
3. Ingests their CSV output into a SQLite database
4. Provides query (`tunnel top`), export (`tunnel export`), and history
   (`tunnel history`) commands on top of the stored data

Think of tunnel as **glue** — it wires together purpose-built scanning
engines with a local database and a convenient command-line interface.

---

## License

tunnel itself is [MIT](LICENSE). The bundled scanner binaries are
GPL-3.0 licensed (see [Credits](#credits) above).
