#!/usr/bin/env python3
"""Ingest a CloudflareSpeedTest (cfst) CSV result file into the SQLite store.

Usage:
    store.py --csv path/to/result.csv --engine cfst [--mode tcping] [--args '...']
              [--db /path/to/db.sqlite] [--family 4|6|auto]

CFST CSV columns (stable order regardless of language):
    IP, Sent, Received, LossRate, AvgLatency, DownloadSpeed(MB/s)

If the user runs cfst with `-dd` (no speed test) the 6th column is missing.
"""
from __future__ import annotations

import argparse
import csv
import datetime as _dt
import ipaddress
import os
import pathlib
import sqlite3
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_DB = REPO_ROOT / "db" / "clean_ips.db"
SCHEMA_FILE = REPO_ROOT / "scripts" / "schema.sql"


def utc_now_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ensure_schema(conn: sqlite3.Connection) -> None:
    with open(SCHEMA_FILE, "r", encoding="utf-8") as fh:
        conn.executescript(fh.read())
    conn.commit()


def family_of(ip: str) -> int:
    try:
        return 6 if isinstance(ipaddress.ip_address(ip), ipaddress.IPv6Address) else 4
    except ValueError:
        return 4


def parse_float(value: str) -> float | None:
    value = (value or "").strip()
    if not value:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def parse_int(value: str) -> int | None:
    value = (value or "").strip()
    if not value:
        return None
    try:
        return int(float(value))
    except ValueError:
        return None


def iter_rows(csv_path: pathlib.Path):
    with open(csv_path, "r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.reader(fh)
        try:
            header = next(reader)
        except StopIteration:
            return
        for row in reader:
            if not row or not row[0].strip():
                continue
            yield row


def insert_scan(conn: sqlite3.Connection, *, engine: str, mode: str | None,
                 args: str | None, csv_path: pathlib.Path) -> int:
    cur = conn.execute(
        "INSERT INTO scans (started_at, engine, mode, args, csv_path, status) "
        "VALUES (?, ?, ?, ?, ?, 'running')",
        (utc_now_iso(), engine, mode, args, str(csv_path)),
    )
    conn.commit()
    return int(cur.lastrowid)


def finalize_scan(conn: sqlite3.Connection, scan_id: int, *, count: int, status: str,
                   notes: str | None = None) -> None:
    conn.execute(
        "UPDATE scans SET finished_at = ?, ip_count = ?, status = ?, notes = COALESCE(?, notes) "
        "WHERE id = ?",
        (utc_now_iso(), count, status, notes, scan_id),
    )
    conn.commit()


def ingest_cfst(conn: sqlite3.Connection, scan_id: int, csv_path: pathlib.Path,
                 measured_at: str, default_port: int) -> int:
    inserted = 0
    rows = []
    for row in iter_rows(csv_path):
        ip = row[0].strip()
        if not ip:
            continue
        sent = parse_int(row[1]) if len(row) > 1 else None
        received = parse_int(row[2]) if len(row) > 2 else None
        loss = parse_float(row[3]) if len(row) > 3 else None
        latency = parse_float(row[4]) if len(row) > 4 else None
        speed = parse_float(row[5]) if len(row) > 5 else None
        rows.append((
            scan_id,
            ip,
            default_port,
            family_of(ip),
            sent,
            received,
            loss,
            latency,
            speed,
            None,
            measured_at,
        ))
    if rows:
        conn.executemany(
            "INSERT INTO clean_ips "
            "(scan_id, ip, port, family, sent, received, loss_rate, latency_ms, speed_mbps, colo, measured_at) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            rows,
        )
        inserted = len(rows)
        conn.commit()
    return inserted


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", required=True, help="CSV output file from cfst")
    parser.add_argument("--engine", default="cfst", choices=["cfst", "senpai", "manual"])
    parser.add_argument("--mode", default=None, help="Optional mode tag (tcping/httping/...)")
    parser.add_argument("--args", default=None, help="Optional original argv string for audit")
    parser.add_argument("--db", default=str(DEFAULT_DB))
    parser.add_argument("--port", type=int, default=443)
    args = parser.parse_args()

    csv_path = pathlib.Path(args.csv).expanduser().resolve()
    if not csv_path.is_file():
        print(f"[store] CSV not found: {csv_path}", file=sys.stderr)
        return 2

    os.makedirs(os.path.dirname(args.db), exist_ok=True)
    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA foreign_keys = ON")
    ensure_schema(conn)

    scan_id = insert_scan(conn, engine=args.engine, mode=args.mode,
                          args=args.args, csv_path=csv_path)
    measured_at = utc_now_iso()
    try:
        count = ingest_cfst(conn, scan_id, csv_path, measured_at, args.port)
    except Exception as exc:
        finalize_scan(conn, scan_id, count=0, status="failed", notes=str(exc))
        print(f"[store] ingest failed: {exc}", file=sys.stderr)
        return 1

    status = "ok" if count > 0 else "empty"
    finalize_scan(conn, scan_id, count=count, status=status)
    print(f"[store] scan_id={scan_id} engine={args.engine} ingested={count} status={status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
