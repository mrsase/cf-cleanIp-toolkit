PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS scans (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    started_at  TEXT    NOT NULL,
    finished_at TEXT,
    engine      TEXT    NOT NULL,
    mode        TEXT,
    args        TEXT,
    csv_path    TEXT,
    ip_count    INTEGER NOT NULL DEFAULT 0,
    status      TEXT    NOT NULL DEFAULT 'running',
    notes       TEXT
);

CREATE TABLE IF NOT EXISTS clean_ips (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    scan_id      INTEGER NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
    ip           TEXT    NOT NULL,
    port         INTEGER,
    family       INTEGER NOT NULL DEFAULT 4,
    sent         INTEGER,
    received     INTEGER,
    loss_rate    REAL,
    latency_ms   REAL,
    speed_mbps   REAL,
    colo         TEXT,
    measured_at  TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_clean_ips_ip       ON clean_ips(ip);
CREATE INDEX IF NOT EXISTS idx_clean_ips_scan     ON clean_ips(scan_id);
CREATE INDEX IF NOT EXISTS idx_clean_ips_latency  ON clean_ips(latency_ms);
CREATE INDEX IF NOT EXISTS idx_clean_ips_speed    ON clean_ips(speed_mbps);
CREATE INDEX IF NOT EXISTS idx_clean_ips_measured ON clean_ips(measured_at);
CREATE INDEX IF NOT EXISTS idx_clean_ips_family   ON clean_ips(family);

CREATE VIEW IF NOT EXISTS latest_per_ip AS
SELECT ci.*
FROM clean_ips ci
JOIN (
    SELECT ip, MAX(measured_at) AS m
    FROM clean_ips
    GROUP BY ip
) latest ON latest.ip = ci.ip AND latest.m = ci.measured_at;

CREATE VIEW IF NOT EXISTS best_recent AS
SELECT ip,
       family,
       AVG(latency_ms)        AS avg_latency_ms,
       MIN(latency_ms)        AS min_latency_ms,
       AVG(loss_rate)         AS avg_loss_rate,
       AVG(speed_mbps)        AS avg_speed_mbps,
       MAX(speed_mbps)        AS max_speed_mbps,
       COUNT(*)               AS samples,
       MAX(measured_at)       AS last_seen,
       MIN(measured_at)       AS first_seen
FROM clean_ips
WHERE measured_at >= datetime('now', '-14 days')
GROUP BY ip, family;
