#!/usr/bin/env python3
"""Behavioural proof for migrations 0022 and 0023.

check_migrations_apply.py proves the SQL parses and runs. It does not prove the
constraints do anything, which is the artefact/effect distinction PROTOCOL-EXEC
§7 is about. This applies 0001-0021, writes real rows, THEN applies 0022+0023,
and asserts the behaviour each one claims.
"""
import sqlite3, tempfile, sys
from pathlib import Path

MIG = Path("mig")
passed, failed = 0, 0

def check(label, fn, expect_error=None):
    global passed, failed
    try:
        fn()
        if expect_error:
            print(f"  FAIL  {label} — expected error containing {expect_error!r}, got success")
            failed += 1
        else:
            print(f"  PASS  {label}")
            passed += 1
    except Exception as e:
        if expect_error and expect_error.lower() in str(e).lower():
            print(f"  PASS  {label} — rejected: {str(e)[:72]}")
            passed += 1
        else:
            print(f"  FAIL  {label} — {type(e).__name__}: {e}")
            failed += 1

db = Path(tempfile.mkdtemp()) / "t.db"
conn = sqlite3.connect(db)
conn.execute("PRAGMA foreign_keys = ON")

def apply(*names):
    for n in names:
        conn.executescript(MIG.joinpath(n).read_text()); conn.commit()

# ── Apply everything that exists before wave 1's last two migrations ──────────
pre = sorted(p.name for p in MIG.glob("0*.sql") if p.name < "0022")
apply(*pre)
print(f"applied {len(pre)} migrations (0001-0021)\n")

# ── Write rows that exist BEFORE 0022/0023, to prove nothing rewrites them ────
conn.executescript("""
INSERT INTO users (id,email,role) VALUES ('u_rider','r@x.test','rider');
INSERT INTO users (id,email,role) VALUES ('u_admin','a@x.test','admin');
INSERT INTO trips (id,rider_id,pickup_lat,pickup_lng,dropoff_lat,dropoff_lng,estimated_fare)
  VALUES ('t_old','u_rider',30.0,31.2,30.1,31.3,88.5);
INSERT INTO sos_alerts (id,user_id,trip_id,lat,lng,reason)
  VALUES ('s_old','u_rider','t_old',30.05,31.25,'pre-existing alert');
INSERT INTO trip_share_tokens (token,trip_id,created_by,expires_at)
  VALUES ('tok_old','t_old','u_rider','2026-01-01T00:00:00Z');
""")
conn.commit()
before = conn.execute("SELECT status,resolved_at,created_at FROM sos_alerts WHERE id='s_old'").fetchone()
trip_before = conn.execute("SELECT estimated_fare FROM trips WHERE id='t_old'").fetchone()

# ── Now apply wave 1's remaining two ─────────────────────────────────────────
apply("0022_sos_lifecycle.sql", "0023_route_source.sql")
print("applied 0022 + 0023 on top of live data\n")

print("── no backfill: pre-existing rows untouched ──")
check("sos_alerts row survives 0022 byte-identical",
      lambda: (lambda a: (_ for _ in ()).throw(AssertionError(f"{before} != {a}")) if a != before else None)(
          conn.execute("SELECT status,resolved_at,created_at FROM sos_alerts WHERE id='s_old'").fetchone()))
check("its three new columns are NULL, not defaulted",
      lambda: (lambda r: (_ for _ in ()).throw(AssertionError(str(r))) if r != (None,None,None) else None)(
          conn.execute("SELECT acknowledged_at,acknowledged_by,resolved_by FROM sos_alerts WHERE id='s_old'").fetchone()))
check("trips.route_source is NULL for a pre-0023 trip, not 'unknown'",
      lambda: (lambda r: (_ for _ in ()).throw(AssertionError(str(r))) if r[0] is not None else None)(
          conn.execute("SELECT route_source FROM trips WHERE id='t_old'").fetchone()))
check("trips.estimated_fare unchanged",
      lambda: (lambda r: (_ for _ in ()).throw(AssertionError(str(r))) if r != trip_before else None)(
          conn.execute("SELECT estimated_fare FROM trips WHERE id='t_old'").fetchone()))

print("\n── 0022: the SOS trail is append-only, enforced by the database ──")
conn.execute("INSERT INTO sos_alert_events (id,alert_id,event,actor_role) VALUES ('e1','s_old','raised','rider')")
conn.commit()
check("an event row inserts", lambda: conn.execute("SELECT 1 FROM sos_alert_events WHERE id='e1'").fetchone()[0])
check("UPDATE on the trail is refused",
      lambda: conn.execute("UPDATE sos_alert_events SET note='tamper' WHERE id='e1'"), "append-only")
conn.rollback()
check("DELETE on the trail is refused",
      lambda: conn.execute("DELETE FROM sos_alert_events WHERE id='e1'"), "evidence")
conn.rollback()
check("an invented event name is refused",
      lambda: conn.execute("INSERT INTO sos_alert_events (id,alert_id,event) VALUES ('e2','s_old','deleted')"),
      "constraint")
conn.rollback()
check("deleting an alert that has a trail fails on the FK, not silently",
      lambda: conn.execute("DELETE FROM sos_alerts WHERE id='s_old'"), "foreign key")
conn.rollback()

print("\n── 0022: acknowledgement without widening the status CHECK ──")
conn.execute("UPDATE sos_alerts SET acknowledged_at=datetime('now'), acknowledged_by='u_admin' WHERE id='s_old'")
conn.commit()
check("acknowledged == open AND acknowledged_at IS NOT NULL",
      lambda: (lambda n: (_ for _ in ()).throw(AssertionError(f"got {n}")) if n != 1 else None)(
          conn.execute("SELECT count(*) FROM sos_alerts WHERE status='open' AND acknowledged_at IS NOT NULL").fetchone()[0]))
check("the 0003 status CHECK is still intact (no rebuild happened)",
      lambda: conn.execute("UPDATE sos_alerts SET status='acknowledged' WHERE id='s_old'"), "constraint")
conn.rollback()
check("acknowledged_by FK rejects an unknown user",
      lambda: conn.execute("UPDATE sos_alerts SET acknowledged_by='nobody' WHERE id='s_old'"), "foreign key")
conn.rollback()

print("\n── 0023: route_source vocabulary is enforced ──")
for v in ("osrm", "haversine", "cached"):
    check(f"accepts {v!r}",
          lambda v=v: conn.execute("UPDATE trips SET route_source=? WHERE id='t_old'", (v,)))
check("rejects a typo ('osrm ' with a trailing space)",
      lambda: conn.execute("UPDATE trips SET route_source='osrm ' WHERE id='t_old'"), "constraint")
conn.rollback()
check("rejects an unknown engine",
      lambda: conn.execute("UPDATE trips SET route_source='google' WHERE id='t_old'"), "constraint")
conn.rollback()
check("still accepts NULL (not-recorded stays expressible)",
      lambda: conn.execute("UPDATE trips SET route_source=NULL WHERE id='t_old'"))
conn.commit()

print("\n── indexes serve the queries they were added for ──")
def plan_uses(sql, idx):
    p = " ".join(r[3] for r in conn.execute("EXPLAIN QUERY PLAN " + sql))
    if idx not in p: raise AssertionError(f"{idx} not used — plan: {p}")
check("operator queue uses idx_sos_alerts_queue",
      lambda: plan_uses("SELECT * FROM sos_alerts WHERE status='open' ORDER BY created_at", "idx_sos_alerts_queue"))
check("token sweep uses idx_share_tokens_expiry",
      lambda: plan_uses("SELECT * FROM trip_share_tokens WHERE expires_at < '2026-01-01'", "idx_share_tokens_expiry"))
check("fallback metric uses idx_trips_route_source",
      lambda: plan_uses("SELECT count(*) FROM trips WHERE route_source='haversine' AND created_at > '2026-01-01'",
                        "idx_trips_route_source"))
check("alert trail read uses idx_sos_alert_events_alert",
      lambda: plan_uses("SELECT * FROM sos_alert_events WHERE alert_id='s_old' ORDER BY created_at",
                        "idx_sos_alert_events_alert"))

print(f"\n══ {passed} passed, {failed} failed ══")
sys.exit(1 if failed else 0)
