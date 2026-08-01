#!/usr/bin/env python3
"""E13 behaviour harness — asserts what the code DOES, not that it parses.

Every SQL statement below is copied verbatim out of
`apps/api/src/routes/safety.ts` on this branch, and the redaction / liveness
logic is reimplemented in Python from the same handler. The point is to prove
the behaviour the brief asks for on a real database with foreign keys on,
because the API has no test runner it can reach: `apps/api/test/` and
`apps/api/vitest.config.ts` are E19's `owns:`, E19 is round 5 and blocked, and
`ci.yml` runs `npm test -w @synaptic-go/shared` only -- it never invokes the
api workspace's test script at all. See the PR body.

Mirrors the shape of board/exec/drafts/test_migrations_0022_0023.py, which is
this board's established answer to "prove it when CI cannot run it".
"""

import json
import sqlite3
import sys
from pathlib import Path

MIG = Path(__file__).resolve().parent / "migrations"

passed = 0
failed: list[str] = []


def check(label: str, cond: bool, detail: str = "") -> None:
    global passed
    if cond:
        passed += 1
        print(f"  ok    {label}")
    else:
        failed.append(f"{label} :: {detail}")
        print(f"  FAIL  {label} :: {detail}")


def fresh() -> sqlite3.Connection:
    conn = sqlite3.connect(":memory:")
    conn.execute("PRAGMA foreign_keys = ON")
    for path in sorted(MIG.glob("*.sql")):
        raw = path.read_bytes()
        if raw.startswith(b"\xef\xbb\xbf"):
            raw = raw[3:]
        conn.executescript(raw.decode("utf-8"))
    conn.commit()
    return conn


# --- fixtures ---------------------------------------------------------------
def seed(conn: sqlite3.Connection) -> None:
    conn.execute(
        "INSERT INTO users (id, email, name, role) VALUES ('u_rider','r@x.io','Rider','rider')"
    )
    conn.execute(
        "INSERT INTO users (id, email, name, role) VALUES ('u_adm','a@x.io','Ops','admin')"
    )
    conn.execute(
        "INSERT INTO users (id, email, name, role) VALUES ('u_adm2','b@x.io','Ops2','admin')"
    )
    # A live trip with real street addresses -- the thing that must not leak.
    conn.execute(
        """INSERT INTO trips (id, rider_id, status, pickup_lat, pickup_lng, pickup_address,
                              dropoff_lat, dropoff_lng, dropoff_address)
           VALUES ('t_live','u_rider','in_progress', 30.0444, 31.2357,
                   '12 Sharia Qasr El Nil, Apartment 4, Downtown Cairo',
                   30.0131, 31.2089, '7 Road 9, Maadi')"""
    )
    conn.execute(
        """INSERT INTO trips (id, rider_id, status, pickup_lat, pickup_lng, pickup_address,
                              dropoff_lat, dropoff_lng, dropoff_address)
           VALUES ('t_done','u_rider','completed', 30.0444, 31.2357, '12 Sharia Qasr El Nil',
                   30.0131, 31.2089, '7 Road 9, Maadi')"""
    )
    conn.execute(
        """INSERT INTO trip_path_points (id, trip_id, lat, lng, recorded_at)
           VALUES ('p1','t_live', 30.04441234, 31.23571234, '2026-08-01T20:00:00Z')"""
    )
    conn.execute(
        """INSERT INTO trip_path_points (id, trip_id, lat, lng, recorded_at)
           VALUES ('p2','t_done', 30.0131, 31.2089, '2026-08-01T19:00:00Z')"""
    )
    conn.commit()


# --- the handler, ported ----------------------------------------------------
# Terminal iff the shared state machine gives it no outgoing transition.
TRIP_TRANSITIONS = {
    "searching": ["offered", "assigned", "cancelled"],
    "offered": ["assigned", "searching", "cancelled"],
    "assigned": ["arrived", "cancelled"],
    "arrived": ["in_progress", "cancelled"],
    "in_progress": ["completed", "cancelled"],
    "completed": [],
    "cancelled": [],
}
LIVE = {s for s, nxt in TRIP_TRANSITIONS.items() if nxt}
DP = 3


def coarsen(v: float) -> float:
    return round(v * 10**DP) / 10**DP


def track(conn: sqlite3.Connection, token: str, now: str):
    """GET /safety/track/:token, ported statement for statement."""
    share = conn.execute(
        "SELECT trip_id, expires_at, revoked_at FROM trip_share_tokens WHERE token = ?",
        (token,),
    ).fetchone()
    if not share:
        return 404, {"code": "NOT_FOUND"}
    trip_id, expires_at, revoked_at = share
    if revoked_at:
        return 410, {"code": "REVOKED"}
    if expires_at < now:
        return 410, {"code": "EXPIRED"}
    trip = conn.execute("SELECT id, status FROM trips WHERE id = ?", (trip_id,)).fetchone()
    if not trip:
        return 404, {"code": "NOT_FOUND"}
    live = trip[1] in LIVE
    last_point = None
    if live:
        pt = conn.execute(
            """SELECT lat, lng, recorded_at FROM trip_path_points
               WHERE trip_id = ? ORDER BY recorded_at DESC LIMIT 1""",
            (trip_id,),
        ).fetchone()
        if pt:
            last_point = {"lat": coarsen(pt[0]), "lng": coarsen(pt[1]), "at": pt[2]}
    return 200, {
        "tripId": trip[0],
        "status": trip[1],
        "live": live,
        "lastPoint": last_point,
        "precisionMeters": 110,
        "expiresAt": expires_at,
    }


def revoke_share_token(conn, trip_id, now):
    cur = conn.execute(
        "UPDATE trip_share_tokens SET revoked_at = ? WHERE trip_id = ? AND revoked_at IS NULL",
        (now, trip_id),
    )
    conn.commit()
    return cur.rowcount


def purge_expired(conn, cutoff):
    cur = conn.execute("DELETE FROM trip_share_tokens WHERE expires_at < ?", (cutoff,))
    conn.commit()
    return cur.rowcount


def ack(conn, alert_id, actor, now):
    exists = conn.execute("SELECT id FROM sos_alerts WHERE id = ?", (alert_id,)).fetchone()
    if not exists:
        return 404, False
    cur = conn.execute(
        """UPDATE sos_alerts SET acknowledged_at = ?, acknowledged_by = ?
           WHERE id = ? AND acknowledged_at IS NULL""",
        (now, actor, alert_id),
    )
    if cur.rowcount == 0:
        conn.commit()
        return 200, True  # alreadyAcknowledged
    conn.execute(
        """INSERT INTO sos_alert_events (id, alert_id, event, actor_id, actor_role, note, created_at)
           VALUES (?, ?, 'acknowledged', ?, 'admin', NULL, ?)""",
        (f"sose_{alert_id}_{actor}_{now}", alert_id, actor, now),
    )
    conn.commit()
    return 200, False


def resolve(conn, alert_id, outcome, actor, note, now):
    cur = conn.execute(
        """UPDATE sos_alerts SET status = ?, resolved_at = ?, resolved_by = ?
           WHERE id = ? AND status = 'open'""",
        (outcome, now, actor, alert_id),
    )
    if cur.rowcount == 0:
        conn.commit()
        return 409
    conn.execute(
        """INSERT INTO sos_alert_events (id, alert_id, event, actor_id, actor_role, note, created_at)
           VALUES (?, ?, ?, ?, 'admin', ?, ?)""",
        (f"sose_res_{alert_id}", alert_id, outcome, actor, note, now),
    )
    conn.commit()
    return 200


# ===========================================================================
print("E13 — safety share redaction, public tracker, SOS lifecycle")
print()

conn = fresh()
seed(conn)
NOW = "2026-08-01T21:00:00Z"
FUTURE = "2026-08-08T21:00:00Z"
PAST = "2026-07-25T21:00:00Z"

conn.execute(
    """INSERT INTO trip_share_tokens (token, trip_id, created_by, expires_at, created_at)
       VALUES ('sh_live','t_live','u_rider',?, ?)""",
    (FUTURE, NOW),
)
conn.commit()

print("1) The share payload no longer discloses an address (F-17-03)")
status, body = track(conn, "sh_live", NOW)
blob = json.dumps(body)
check("tracker returns 200 for a valid token", status == 200, str(status))
check("no pickup address anywhere in the payload", "Qasr El Nil" not in blob, blob)
check("no dropoff address anywhere in the payload", "Road 9" not in blob, blob)
check("no 'pickup'/'dropoff' keys at all", "pickup" not in body and "dropoff" not in body, blob)
check("status is still disclosed", body["status"] == "in_progress", blob)

print()
print("2) Position is coarsened, not raw (F-17-03)")
raw_lat, raw_lng = 30.04441234, 31.23571234
check("a position is served for a live trip", body["lastPoint"] is not None)
check(
    "latitude is rounded to 3dp",
    body["lastPoint"]["lat"] == 30.044 and body["lastPoint"]["lat"] != raw_lat,
    str(body["lastPoint"]),
)
check(
    "longitude is rounded to 3dp",
    body["lastPoint"]["lng"] == 31.236 and body["lastPoint"]["lng"] != raw_lng,
    str(body["lastPoint"]),
)
check("the raw fix is never echoed", str(raw_lat) not in blob, blob)

print()
print("3) A finished trip discloses no position at all")
conn.execute(
    """INSERT INTO trip_share_tokens (token, trip_id, created_by, expires_at, created_at)
       VALUES ('sh_done','t_done','u_rider',?, ?)""",
    (FUTURE, NOW),
)
conn.commit()
status, done_body = track(conn, "sh_done", NOW)
check("terminal trip still answers", status == 200, str(status))
check("but with live=false", done_body["live"] is False, str(done_body))
check("and no position", done_body["lastPoint"] is None, str(done_body))
check(
    "a point exists in the table -- it is withheld, not absent",
    conn.execute("SELECT count(*) FROM trip_path_points WHERE trip_id='t_done'").fetchone()[0] == 1,
)

print()
print("4) A status the state machine has never heard of fails CLOSED")
conn.execute("UPDATE trips SET status = 'expired_no_captain' WHERE id = 't_live'")
conn.commit()
_, unknown_body = track(conn, "sh_live", NOW)
check("unknown status -> live=false", unknown_body["live"] is False, str(unknown_body))
check("unknown status -> no position", unknown_body["lastPoint"] is None, str(unknown_body))
conn.execute("UPDATE trips SET status = 'in_progress' WHERE id = 't_live'")
conn.commit()

print()
print("5) revokeShareToken() — E09's call site, proven at the export level")
check("token is live before revocation", track(conn, "sh_live", NOW)[0] == 200)
n = revoke_share_token(conn, "t_live", NOW)
check("revoking a trip's tokens reports 1 change", n == 1, str(n))
status, revoked_body = track(conn, "sh_live", NOW)
check("the link now stops working", status == 410, str(status))
check("with code REVOKED", revoked_body["code"] == "REVOKED", str(revoked_body))
check("second call is idempotent and reports 0", revoke_share_token(conn, "t_live", NOW) == 0)
check("revoking a trip with no tokens reports 0", revoke_share_token(conn, "t_nothing", NOW) == 0)

print()
print("6) purgeExpiredShareTokens() — and the index 0022 adds for it")
conn.execute(
    """INSERT INTO trip_share_tokens (token, trip_id, created_by, expires_at, created_at)
       VALUES ('sh_old','t_done','u_rider',?, ?)""",
    (PAST, PAST),
)
conn.commit()
before = conn.execute("SELECT count(*) FROM trip_share_tokens").fetchone()[0]
removed = purge_expired(conn, NOW)
after = conn.execute("SELECT count(*) FROM trip_share_tokens").fetchone()[0]
check("the expired token is removed", removed == 1, str(removed))
check("unexpired tokens survive", after == before - 1, f"{before}->{after}")
plan = conn.execute(
    "EXPLAIN QUERY PLAN DELETE FROM trip_share_tokens WHERE expires_at < ?", (NOW,)
).fetchall()
plan_txt = " | ".join(str(r[-1]) for r in plan)
check("the sweep uses idx_share_tokens_expiry, not a scan", "idx_share_tokens_expiry" in plan_txt, plan_txt)

print()
print("7) The SOS trail is append-only in the database, not by convention")
conn.execute(
    """INSERT INTO sos_alerts (id, user_id, trip_id, lat, lng, reason, status, created_at)
       VALUES ('sos_1','u_rider','t_live',30.04,31.23,'followed','open', ?)""",
    (NOW,),
)
conn.execute(
    """INSERT INTO sos_alert_events (id, alert_id, event, actor_id, actor_role, note, created_at)
       VALUES ('ev_1','sos_1','raised','u_rider','rider','followed', ?)""",
    (NOW,),
)
conn.commit()
try:
    conn.execute("UPDATE sos_alert_events SET note = 'rewritten' WHERE id = 'ev_1'")
    check("UPDATE on the trail is refused", False, "it succeeded")
except sqlite3.IntegrityError as e:
    check("UPDATE on the trail is refused by trigger", "append-only" in str(e), str(e))
conn.rollback()
try:
    conn.execute("DELETE FROM sos_alert_events WHERE id = 'ev_1'")
    check("DELETE on the trail is refused", False, "it succeeded")
except sqlite3.IntegrityError as e:
    check("DELETE on the trail is refused by trigger", "append-only" in str(e), str(e))
conn.rollback()
try:
    conn.execute(
        """INSERT INTO sos_alert_events (id, alert_id, event, created_at)
           VALUES ('ev_x','sos_1','deleted_by_ops', ?)""",
        (NOW,),
    )
    check("an invented event name is refused", False, "it succeeded")
except sqlite3.IntegrityError as e:
    check("an invented event name is refused by CHECK", "CHECK" in str(e).upper(), str(e))
conn.rollback()
try:
    conn.execute("DELETE FROM sos_alerts WHERE id = 'sos_1'")
    check("deleting an alert that has a trail is refused", False, "it succeeded")
except sqlite3.IntegrityError as e:
    check("deleting an alert with a trail fails on the FK", "FOREIGN KEY" in str(e).upper(), str(e))
conn.rollback()

print()
print("8) Acknowledge — a named operator, and only the first one")
code, already = ack(conn, "sos_1", "u_adm", NOW)
check("first ack succeeds", code == 200 and already is False, f"{code}/{already}")
row = conn.execute(
    "SELECT acknowledged_at, acknowledged_by, status FROM sos_alerts WHERE id='sos_1'"
).fetchone()
check("acknowledged_by records who", row[1] == "u_adm", str(row))
check("the alert is STILL open -- ack is not a state", row[2] == "open", str(row))
code, already = ack(conn, "sos_1", "u_adm2", "2026-08-01T21:05:00Z")
check("a second operator's ack is a no-op", already is True, f"{code}/{already}")
row2 = conn.execute("SELECT acknowledged_by FROM sos_alerts WHERE id='sos_1'").fetchone()
check("the first acknowledger is not overwritten", row2[0] == "u_adm", str(row2))
n_ack = conn.execute(
    "SELECT count(*) FROM sos_alert_events WHERE alert_id='sos_1' AND event='acknowledged'"
).fetchone()[0]
check("and no duplicate 'acknowledged' row is appended", n_ack == 1, str(n_ack))
check("ack on a missing alert is 404", ack(conn, "sos_nope", "u_adm", NOW)[0] == 404)

print()
print("9) Resolve — mandatory reason, recorded actor, closed once")
code = resolve(conn, "sos_1", "resolved", "u_adm", "spoke to rider, police attended", NOW)
check("resolve succeeds", code == 200, str(code))
row = conn.execute(
    "SELECT status, resolved_at, resolved_by FROM sos_alerts WHERE id='sos_1'"
).fetchone()
check("status becomes 'resolved'", row[0] == "resolved", str(row))
check("resolved_by records the actor", row[2] == "u_adm", str(row))
check(
    "the reason is in the trail",
    conn.execute(
        "SELECT note FROM sos_alert_events WHERE alert_id='sos_1' AND event='resolved'"
    ).fetchone()[0]
    == "spoke to rider, police attended",
)
check("resolving twice is refused with 409", resolve(conn, "sos_1", "resolved", "u_adm2", "again", NOW) == 409)
try:
    conn.execute("UPDATE sos_alerts SET status='acknowledged' WHERE id='sos_1'")
    check("the 0003 status CHECK was not widened", False, "'acknowledged' was accepted")
except sqlite3.IntegrityError:
    check("the 0003 status CHECK was not widened ('acknowledged' still illegal)", True)
conn.rollback()

print()
print("10) The queue query, and the composite index 0022 adds for it")
qplan = conn.execute(
    "EXPLAIN QUERY PLAN SELECT id FROM sos_alerts WHERE status = ? ORDER BY created_at ASC LIMIT 50",
    ("open",),
).fetchall()
qtxt = " | ".join(str(r[-1]) for r in qplan)
check("filter+order is served by idx_sos_alerts_queue", "idx_sos_alerts_queue" in qtxt, qtxt)
check("and needs no separate sort step", "USE TEMP B-TREE" not in qtxt.upper(), qtxt)

print()
print("11) The trail is queryable as history")
hist = conn.execute(
    """SELECT event, actor_id, actor_role FROM sos_alert_events
       WHERE alert_id = ? ORDER BY created_at ASC, rowid ASC""",
    ("sos_1",),
).fetchall()
check("history reads back in order", [h[0] for h in hist] == ["raised", "acknowledged", "resolved"], str(hist))
check("every entry names an actor", all(h[1] for h in hist), str(hist))

print()
print("12) No backfill: 0022 rewrote nothing that already existed")
c2 = fresh()
c2.execute("INSERT INTO users (id,email,name,role) VALUES ('u1','e@x.io','N','rider')")
c2.commit()
cols = {r[1] for r in c2.execute("PRAGMA table_info(sos_alerts)").fetchall()}
check("acknowledged_at/by and resolved_by exist", {"acknowledged_at", "acknowledged_by", "resolved_by"} <= cols, str(sorted(cols)))
c2.execute(
    """INSERT INTO sos_alerts (id,user_id,lat,lng,status,created_at)
       VALUES ('s0','u1',30.0,31.0,'open','2026-01-01T00:00:00Z')"""
)
c2.commit()
vals = c2.execute(
    "SELECT acknowledged_at, acknowledged_by, resolved_by FROM sos_alerts WHERE id='s0'"
).fetchone()
check("new columns default to NULL, not to a value", vals == (None, None, None), str(vals))

print()
print("=" * 70)
print(f"{passed} assertion(s) passed, {len(failed)} failed")
for f in failed:
    print(f"  FAIL  {f}")
sys.exit(1 if failed else 0)
