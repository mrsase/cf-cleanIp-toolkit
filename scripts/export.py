#!/usr/bin/env python3
"""Export stored clean IPs to a portable file (JSON, CSV, plain text).

Examples:
    export.py                                  # writes exports/clean_ips_<ts>.json (top 50)
    export.py -n 100 --format txt              # plain ip list
    export.py --format csv -o /tmp/cf.csv
    export.py --family 6 --format json
"""
from __future__ import annotations

import argparse
import csv as _csv
import datetime as _dt
import json
import pathlib
import sqlite3
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO_ROOT / "db" / "clean_ips.db"
DEFAULT_DIR = REPO_ROOT / "exports"


def collect(db_path: pathlib.Path, *, number: int, family: int, days: int) -> list[dict]:
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    where = ["measured_at >= datetime('now', ?)"]
    params: list = [f"-{days} days"]
    if family in (4, 6):
        where.append("family = ?")
        params.append(family)
    sql = f"""
        SELECT ip,
               family,
               MIN(latency_ms)              AS best_latency_ms,
               AVG(latency_ms)              AS avg_latency_ms,
               AVG(loss_rate)               AS avg_loss_rate,
               MAX(COALESCE(speed_mbps,0))  AS best_speed_mbps,
               AVG(COALESCE(speed_mbps,0))  AS avg_speed_mbps,
               COUNT(*)                     AS samples,
               MAX(measured_at)             AS last_seen,
               MIN(measured_at)             AS first_seen
          FROM clean_ips
         WHERE {' AND '.join(where)}
      GROUP BY ip, family
      ORDER BY best_latency_ms ASC, best_speed_mbps DESC
         LIMIT ?
    """
    params.append(number)
    rows = [dict(r) for r in conn.execute(sql, params).fetchall()]
    conn.close()
    return rows


def write_output(rows: list[dict], fmt: str, out_path: pathlib.Path) -> None:
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if fmt == "json":
        with open(out_path, "w", encoding="utf-8") as fh:
            json.dump(rows, fh, indent=2, default=str)
    elif fmt == "csv":
        with open(out_path, "w", encoding="utf-8", newline="") as fh:
            writer = _csv.writer(fh)
            if rows:
                writer.writerow(rows[0].keys())
                for r in rows:
                    writer.writerow(r.values())
    elif fmt == "txt":
        with open(out_path, "w", encoding="utf-8") as fh:
            for r in rows:
                fh.write(f"{r['ip']}\n")
    else:
        raise ValueError(f"unknown format: {fmt}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-n", "--number", type=int, default=50)
    parser.add_argument("--family", type=int, default=4, choices=[4, 6, 0])
    parser.add_argument("--days", type=int, default=14)
    parser.add_argument("--format", choices=["json", "csv", "txt"], default="json")
    parser.add_argument("-o", "--output", default=None,
                        help="Output file path; default exports/clean_ips_<ts>.<fmt>")
    parser.add_argument("--db", default=str(DEFAULT_DB))
    args = parser.parse_args()

    db_path = pathlib.Path(args.db)
    if not db_path.is_file():
        print(f"[export] no database at {db_path}", file=sys.stderr)
        return 2

    rows = collect(db_path, number=args.number, family=args.family, days=args.days)

    if args.output:
        out_path = pathlib.Path(args.output).expanduser()
    else:
        ts = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        suffix = args.format
        out_path = DEFAULT_DIR / f"clean_ips_{ts}.{suffix}"

    write_output(rows, args.format, out_path)
    print(f"[export] wrote {len(rows)} rows to {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
