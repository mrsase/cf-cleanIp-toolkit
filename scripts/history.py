#!/usr/bin/env python3
"""Quick stats / history summary of recorded scans and clean IPs.

Examples:
    history.py                  # show last 10 scans + DB stats
    history.py -n 20            # last 20 scans
    history.py --scan 12        # detail rows for scan id 12
"""
from __future__ import annotations

import argparse
import pathlib
import sqlite3
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO_ROOT / "db" / "clean_ips.db"


def show_summary(conn: sqlite3.Connection) -> None:
    cur = conn.execute("SELECT COUNT(*) FROM scans")
    total_scans = cur.fetchone()[0]
    cur = conn.execute("SELECT COUNT(*) FROM clean_ips")
    total_ips = cur.fetchone()[0]
    cur = conn.execute("SELECT COUNT(DISTINCT ip) FROM clean_ips")
    distinct_ips = cur.fetchone()[0]
    cur = conn.execute(
        "SELECT COUNT(DISTINCT ip) FROM clean_ips WHERE measured_at >= datetime('now','-1 day')")
    today_ips = cur.fetchone()[0]
    cur = conn.execute(
        "SELECT MIN(measured_at), MAX(measured_at) FROM clean_ips")
    first, last = cur.fetchone()
    print("== Database summary ==")
    print(f"  total scans            : {total_scans}")
    print(f"  total measurements     : {total_ips}")
    print(f"  unique IPs ever seen   : {distinct_ips}")
    print(f"  unique IPs last 24h    : {today_ips}")
    print(f"  earliest measurement   : {first}")
    print(f"  latest measurement     : {last}")
    print()


def show_scans(conn: sqlite3.Connection, n: int) -> None:
    rows = conn.execute(
        "SELECT id, started_at, finished_at, engine, mode, ip_count, status "
        "FROM scans ORDER BY id DESC LIMIT ?", (n,)).fetchall()
    print(f"== Last {len(rows)} scans ==")
    print(f"  {'id':>5}  {'started':<20}  {'finished':<20}  {'engine':<8}  "
          f"{'mode':<10}  {'count':>6}  status")
    print("  " + "-" * 84)
    for r in rows:
        sid, started, finished, engine, mode, count, status = r
        print(f"  {sid:>5}  {started or '-':<20}  {finished or '-':<20}  "
              f"{engine or '-':<8}  {(mode or '-'):<10}  {count:>6}  {status}")


def show_scan_detail(conn: sqlite3.Connection, scan_id: int) -> None:
    meta = conn.execute(
        "SELECT * FROM scans WHERE id = ?", (scan_id,)).fetchone()
    if not meta:
        print(f"no scan with id {scan_id}", file=sys.stderr)
        return
    print(f"== Scan #{scan_id} ==")
    cols = [d[0] for d in conn.execute("SELECT * FROM scans WHERE id = ?", (scan_id,)).description]
    for k, v in zip(cols, meta):
        print(f"  {k:<14}: {v}")
    print()
    rows = conn.execute(
        "SELECT ip, family, sent, received, loss_rate, latency_ms, speed_mbps "
        "FROM clean_ips WHERE scan_id = ? "
        "ORDER BY latency_ms ASC LIMIT 50", (scan_id,)).fetchall()
    print(f"  Top {len(rows)} results from this scan:")
    print(f"    {'ip':<32} {'fam':<3} {'sent':>4} {'recv':>4} {'loss':>5} "
          f"{'lat_ms':>8} {'spd':>7}")
    for r in rows:
        ip, fam, sent, recv, loss, lat, spd = r
        print(f"    {ip:<32} {fam:<3} {sent or 0:>4} {recv or 0:>4} "
              f"{(loss or 0)*100:>4.1f}% {(lat or 0):>8.1f} {(spd or 0):>7.2f}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-n", "--number", type=int, default=10)
    parser.add_argument("--scan", type=int, default=None,
                        help="Show detailed rows for a specific scan id")
    parser.add_argument("--db", default=str(DEFAULT_DB))
    args = parser.parse_args()
    db_path = pathlib.Path(args.db)
    if not db_path.is_file():
        print(f"[history] no database at {db_path}", file=sys.stderr)
        return 2
    conn = sqlite3.connect(db_path)
    show_summary(conn)
    if args.scan is not None:
        show_scan_detail(conn, args.scan)
    else:
        show_scans(conn, args.number)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
