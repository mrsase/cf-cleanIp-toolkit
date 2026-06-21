#!/usr/bin/env python3
"""Show the top-N Cloudflare clean IPs currently stored in the database.

By default lists results from the last 14 days, ranked by recent latency
(and download speed when available). Supports filtering by IP family,
minimum/maximum latency, minimum speed, etc.

Examples:
    top.py                              # default 10 best (v4) in last 14 days
    top.py -n 25 --family 4             # 25 best IPv4
    top.py --family 6                   # IPv6
    top.py --max-latency 120 --min-speed 5
    top.py --days 1                     # only consider last 24h scans
    top.py --raw                        # space separated ip list only (script friendly)
    top.py --format json                # JSON output
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import pathlib
import sqlite3
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO_ROOT / "db" / "clean_ips.db"


def fetch(args) -> list[dict]:
    if not pathlib.Path(args.db).is_file():
        print(f"[top] no database yet at {args.db}; run a scan first", file=sys.stderr)
        return []
    conn = sqlite3.connect(args.db)
    conn.row_factory = sqlite3.Row

    where = ["measured_at >= datetime('now', ?)"]
    params: list = [f"-{args.days} days"]

    if args.family in (4, 6):
        where.append("family = ?")
        params.append(args.family)

    if args.max_latency is not None:
        where.append("latency_ms IS NOT NULL AND latency_ms <= ?")
        params.append(args.max_latency)

    if args.min_latency is not None:
        where.append("latency_ms IS NOT NULL AND latency_ms >= ?")
        params.append(args.min_latency)

    if args.max_loss is not None:
        where.append("loss_rate IS NOT NULL AND loss_rate <= ?")
        params.append(args.max_loss)

    if args.min_speed is not None:
        where.append("speed_mbps IS NOT NULL AND speed_mbps >= ?")
        params.append(args.min_speed)

    where_sql = " AND ".join(where)

    # Aggregate per IP across the window: prefer recent successful results.
    # Rank by: lower latency, higher speed, lower loss.
    sql = f"""
        SELECT  ip,
                family,
                MIN(latency_ms)                                    AS best_latency_ms,
                AVG(latency_ms)                                    AS avg_latency_ms,
                AVG(loss_rate)                                     AS avg_loss_rate,
                MAX(COALESCE(speed_mbps, 0))                       AS best_speed_mbps,
                AVG(COALESCE(speed_mbps, 0))                       AS avg_speed_mbps,
                COUNT(*)                                           AS samples,
                MAX(measured_at)                                   AS last_seen
          FROM  clean_ips
         WHERE  {where_sql}
      GROUP BY  ip, family
      ORDER BY  best_latency_ms ASC,
                best_speed_mbps DESC,
                avg_loss_rate ASC,
                last_seen DESC
         LIMIT  ?
    """
    params.append(args.number)
    rows = [dict(r) for r in conn.execute(sql, params).fetchall()]
    conn.close()
    return rows


def fmt_table(rows: list[dict]) -> str:
    if not rows:
        return "(no rows match filters)"
    headers = ["#", "ip", "fam", "best_lat", "avg_lat", "loss%", "best_spd", "avg_spd", "n", "last_seen"]
    line = []
    line.append("  ".join(f"{h:<{w}}" for h, w in zip(
        headers, [3, 32, 3, 8, 8, 6, 8, 8, 3, 20])))
    line.append("-" * 110)
    for i, r in enumerate(rows, 1):
        line.append("  ".join([
            f"{i:<3}",
            f"{r['ip']:<32}",
            f"{r['family']:<3}",
            f"{r['best_latency_ms']:<8.1f}" if r['best_latency_ms'] is not None else f"{'-':<8}",
            f"{r['avg_latency_ms']:<8.1f}" if r['avg_latency_ms'] is not None else f"{'-':<8}",
            f"{(r['avg_loss_rate'] or 0) * 100:<6.1f}",
            f"{r['best_speed_mbps']:<8.2f}",
            f"{r['avg_speed_mbps']:<8.2f}",
            f"{r['samples']:<3}",
            f"{r['last_seen']:<20}",
        ]))
    return "\n".join(line)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("-n", "--number", type=int, default=10)
    parser.add_argument("--family", type=int, default=4, choices=[4, 6, 0],
                        help="IP family (4, 6, or 0 for both). Default 4.")
    parser.add_argument("--days", type=int, default=14,
                        help="Look back N days (default 14)")
    parser.add_argument("--max-latency", type=float, default=None,
                        help="Max best latency in ms")
    parser.add_argument("--min-latency", type=float, default=None,
                        help="Min best latency in ms")
    parser.add_argument("--max-loss", type=float, default=None,
                        help="Max avg loss rate (0.0-1.0)")
    parser.add_argument("--min-speed", type=float, default=None,
                        help="Min best download speed MB/s")
    parser.add_argument("--format", choices=["table", "json", "csv", "raw"], default="table")
    parser.add_argument("--raw", action="store_true", help="Alias for --format raw")
    parser.add_argument("--db", default=str(DEFAULT_DB))
    args = parser.parse_args()

    if args.raw:
        args.format = "raw"

    rows = fetch(args)

    if args.format == "json":
        print(json.dumps(rows, indent=2, default=str))
    elif args.format == "csv":
        import csv as _csv
        writer = _csv.writer(sys.stdout)
        if rows:
            writer.writerow(rows[0].keys())
            for r in rows:
                writer.writerow(r.values())
    elif args.format == "raw":
        for r in rows:
            print(r["ip"])
    else:
        print(fmt_table(rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
