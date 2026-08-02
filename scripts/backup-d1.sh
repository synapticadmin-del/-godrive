#!/usr/bin/env bash
#
# backup-d1.sh — export a D1 database to R2, and prove the object arrived.
#
# ---------------------------------------------------------------------------
# Why this script exists (task E18, launch-gate item 15, finding F-08-04 / S-015)
# ---------------------------------------------------------------------------
# Before this file, the only backup of a database holding wallet balances was
# platform-default D1 Time Travel. Three things are wrong with that as a
# position to launch from:
#
#   1. It had never been rehearsed. "We think we can restore" is not a backup.
#   2. Restoring it is a *destructive in-place overwrite* of the live database.
#      There is no "restore to a copy and compare" in Time Travel, so the first
#      time anyone runs it is also the moment the live data is replaced.
#   3. It lives inside the same account and the same product as the thing it
#      protects. An account-level accident takes both.
#
# This script produces the missing third leg: a portable `.sql` dump, held in
# object storage, that can be loaded into a NEW database and inspected before
# anything live is touched. The restore procedure is `docs/RUNBOOK-restore.md`.
#
# ---------------------------------------------------------------------------
# --remote is load-bearing, in both directions
# ---------------------------------------------------------------------------
# Wrangler's D1 and R2 commands default to LOCAL storage. A `wrangler d1 export`
# without `--remote` writes you a dump of your laptop's dev database and exits 0,
# and a `wrangler r2 object put` without `--remote` files it in a local
# simulator directory. Both look exactly like a successful backup.
#
# This repository has already shipped that precise bug once, in the other
# direction: the old deploy.sh ran `wrangler d1 execute --file=…` with no
# `--remote`, so the one migration it applied went to the local database while
# the deploy two lines later went to production (see docs/DEPLOYMENT.md). Every
# wrangler invocation below therefore passes `--remote` explicitly, and
# `--self-test` asserts that none of them can lose it.
#
# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
#   bash scripts/backup-d1.sh <env>                  # <env> is REQUIRED: prod | staging
#   bash scripts/backup-d1.sh prod
#   bash scripts/backup-d1.sh prod --dry-run         # print every command, run none
#   bash scripts/backup-d1.sh prod --keep-local DIR  # also leave the dump on disk
#   bash scripts/backup-d1.sh prod --bucket NAME     # default: synaptic-go-backups
#
#   bash scripts/backup-d1.sh --self-test            # assert the guards hold (offline)
#   bash scripts/backup-d1.sh --rehearse             # dump/restore drill on a scratch db
#   bash scripts/backup-d1.sh --check-dump FILE.sql  # validate a dump before importing it
#
# Auth comes from CLOUDFLARE_API_TOKEN / CLOUDFLARE_ACCOUNT_ID in the
# environment, or from `wrangler login` state — the same inputs deploy.sh uses.
# The token needs D1:Read and R2:Edit ("Workers R2 Storage:Edit").
#
# One-time setup, by a human with those credentials:
#   npx wrangler r2 bucket create synaptic-go-backups
#
# The last three modes need no credentials, no network and no wrangler. They are
# what CI and a nervous operator can run.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd -P)"
WRANGLER_TOML="$REPO_ROOT/apps/api/wrangler.toml"
MIGRATIONS_DIR="$REPO_ROOT/migrations"

# Deliberately NOT the application's own bucket. `synaptic-go-files` holds the
# identity documents and avatars the Worker serves; a backup that shares a
# bucket with live application data is destroyed by the same mistake that
# destroys the data. Override with --bucket or D1_BACKUP_BUCKET.
DEFAULT_BUCKET="${D1_BACKUP_BUCKET:-synaptic-go-backups}"

die()  { printf 'backup-d1.sh: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

usage() {
  cat >&2 <<'USAGE'
usage: bash scripts/backup-d1.sh <env> [--bucket NAME] [--keep-local DIR] [--dry-run]
       bash scripts/backup-d1.sh --self-test
       bash scripts/backup-d1.sh --rehearse [--keep]
       bash scripts/backup-d1.sh --check-dump FILE.sql

  <env>          REQUIRED. The wrangler environment whose D1 database to export,
                 validated against the [env.*] blocks in apps/api/wrangler.toml.
                 There is deliberately no default: backing up the wrong database
                 is indistinguishable from backing up the right one until the
                 day you need it.

  --bucket NAME  R2 bucket to write to. Default: synaptic-go-backups
                 (or $D1_BACKUP_BUCKET).
  --keep-local D Also leave the dump and its manifest in directory D.
  --dry-run      Print every command that would run, execute none of them.

  --self-test    Assert the guards below still hold. No network, no wrangler,
                 no credentials. Safe anywhere.
  --rehearse     Build a scratch database from migrations/, seed it with money
                 rows, dump it, restore the dump into a NEW database and compare
                 the two. This is the drill gate item 15 asks for; the recorded
                 run is in docs/RUNBOOK-restore.md.
  --check-dump F Load dump F into a throwaway database and report what is in it,
                 without touching anything live. Run this on a downloaded backup
                 BEFORE importing it into a real database.
USAGE
}

# --- reading the config, never guessing it -----------------------------------
# Same idiom as apps/api/deploy.sh: the environment list and the database name
# are parsed out of wrangler.toml so this script cannot drift from the config it
# is backing up. A hardcoded database name here is how you end up faithfully
# backing up staging every night for a year.
list_envs() {
  sed -n 's/^\[env\.\([A-Za-z0-9_-]*\)\]$/\1/p' "$WRANGLER_TOML" | sort -u
}

# Pull one key out of the [[env.<env>.d1_databases]] block.
d1_field_for_env() { # d1_field_for_env <env> <field>
  awk -v e="$1" -v f="$2" '
    $0 ~ "^\\[\\[env\\." e "\\.d1_databases\\]\\]$" { inblock = 1; next }
    /^\[/ { inblock = 0 }
    inblock && $0 ~ "^[[:space:]]*" f "[[:space:]]*=" {
      line = $0
      sub("^[[:space:]]*" f "[[:space:]]*=[[:space:]]*\"", "", line)
      sub(/".*$/, "", line)
      print line
      exit
    }
  ' "$WRANGLER_TOML"
}

# Portable, and the fallback is python3 because every check in scripts/ already
# requires it. Prints the bare hex digest.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    python3 - "$1" <<'PY'
import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as fh:
    for chunk in iter(lambda: fh.read(1 << 20), b""):
        h.update(chunk)
print(h.hexdigest())
PY
  fi
}

bytes_of() { wc -c < "$1" | tr -d ' '; }

# --- the offline SQLite drill ------------------------------------------------
# Written out to a temp file and run with python3 rather than inlined, so the
# quoting stays readable. stdlib only, exactly like the four checks in scripts/.
write_drill_py() { # write_drill_py <path>
  cat > "$1" <<'PY'
"""Offline dump/restore drill for the D1 backup path.

D1 is SQLite underneath and `wrangler d1 export` emits a plain SQL dump, so a
dump/restore cycle can be rehearsed faithfully with stdlib sqlite3 — no
credentials, no network, nothing live. What this proves and does not prove is
written down in docs/RUNBOOK-restore.md; the short version is that it exercises
the dump format, the restore-into-a-new-database procedure and the verification
queries, and it cannot exercise wrangler, R2 or D1's own limits.
"""
import hashlib
import re
import sqlite3
import sys
import time
from pathlib import Path

BOM = b"\xef\xbb\xbf"
FAILURES = []
CHECKS = 0


def check(desc, ok, detail=""):
    global CHECKS
    CHECKS += 1
    if ok:
        print(f"  PASS  {desc}" + (f"  [{detail}]" if detail else ""))
    else:
        print(f"  FAIL  {desc}" + (f"  [{detail}]" if detail else ""))
        FAILURES.append(desc)


def apply_migrations(conn, migrations_dir):
    files = sorted(Path(migrations_dir).glob("*.sql"))
    if not files:
        raise SystemExit(f"no .sql files in {migrations_dir}")
    for path in files:
        raw = path.read_bytes()
        if raw.startswith(BOM):
            raw = raw[len(BOM):]
        conn.executescript(raw.decode("utf-8"))
    conn.commit()
    return len(files)


def seed_money(conn):
    """Rows that make the drill mean something.

    A schema-only restore proves almost nothing: the finding is about wallet
    balances. These touch every money-bearing table the launch shape keeps
    live — users.wallet_balance, the wallet_transactions ledger, a completed
    trip with a settled fare, and a payout request from 0020.
    """
    cur = conn.cursor()
    cur.execute("PRAGMA foreign_keys = ON")
    for i in range(1, 6):
        cur.execute(
            "INSERT INTO users (id, email, name, phone, role, wallet_balance,"
            " wallet_balance_piastres) VALUES (?,?,?,?,?,?,?)",
            (f"u{i}", f"u{i}@example.test", f"مستخدم {i}", f"+2010000000{i}",
             "captain" if i % 2 else "rider", i * 12.34,
             int(round(i * 12.34 * 100))),
        )
    cur.execute(
        "INSERT INTO trips (id, rider_id, captain_id, status, pickup_lat,"
        " pickup_lng, dropoff_lat, dropoff_lng, final_fare, final_fare_piastres,"
        " commission, commission_piastres, payment_method, completed_at)"
        " VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        ("t1", "u2", "u1", "completed", 30.0444, 31.2357, 30.0131, 31.2089,
         87.65, 8765, 17.53, 1753, "cash", "2026-08-01T12:00:00Z"),
    )
    cur.execute(
        "INSERT INTO wallet_transactions (id, user_id, type, direction, amount,"
        " amount_piastres, trip_id, status, idempotency_key)"
        " VALUES (?,?,?,?,?,?,?,?,?)",
        ("wt1", "u1", "commission", "debit", 17.53, 1753, "t1", "settled",
         "commission:t1"),
    )
    cur.execute(
        "INSERT INTO payout_requests (id, user_id, amount, amount_piastres,"
        " method, account_info, status, idempotency_key)"
        " VALUES (?,?,?,?,?,?,?,?)",
        ("pr1", "u1", 50.00, 5000, "vodafone_cash", "+201000000001",
         "requested", "payout:u1:1"),
    )
    conn.commit()


def fingerprint(conn):
    """Content fingerprint of every user table: name, row count, and a hash of
    the rows themselves in primary-key order. Row counts alone would not notice
    a restore that kept the right number of rows with the wrong values."""
    tables = [
        r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
            " AND name NOT LIKE 'sqlite_%' ORDER BY name"
        )
    ]
    out = {}
    for t in tables:
        cols = [r[1] for r in conn.execute(f'PRAGMA table_info("{t}")')]
        order = ", ".join(f'"{c}"' for c in cols) or "1"
        rows = conn.execute(f'SELECT * FROM "{t}" ORDER BY {order}').fetchall()
        h = hashlib.sha256()
        for row in rows:
            h.update(repr(row).encode("utf-8"))
            h.update(b"\x1e")
        out[t] = (len(rows), h.hexdigest())
    return out


def integrity(conn, label):
    ok = conn.execute("PRAGMA integrity_check").fetchone()[0]
    check(f"{label}: PRAGMA integrity_check", ok == "ok", ok)
    fk = conn.execute("PRAGMA foreign_key_check").fetchall()
    check(f"{label}: PRAGMA foreign_key_check", not fk, f"{len(fk)} violation(s)")


RESTORE_PRELUDE = "PRAGMA defer_foreign_keys = ON;"
RESTORE_POSTLUDE = "PRAGMA defer_foreign_keys = OFF;"


def load_dump(db_path, dump_path, strategy="fk_off"):
    """Replay a dump against an empty database, the way
    `wrangler d1 execute --file=` does.

    strategy:
      "naive"   foreign keys enforced, dump replayed as-is. This is what an
                operator types at 3 a.m., and on a .dump-shaped export it FAILS
                — see the comment in cmd_rehearse.
      "defer"   the dump bracketed by PRAGMA defer_foreign_keys, which is what
                Cloudflare's D1 documentation prescribes for imports that
                violate foreign key order.
      "fk_off"  foreign keys disabled on the connection before the replay and
                re-checked afterwards. The reliable local-SQLite procedure.
    """
    sql = Path(dump_path).read_text(encoding="utf-8")
    conn = sqlite3.connect(db_path)
    if strategy == "fk_off":
        # Must be set outside any transaction: PRAGMA foreign_keys is a no-op
        # inside one. This is exactly why D1 offers defer_foreign_keys instead —
        # D1 wraps every statement in an implicit transaction.
        conn.execute("PRAGMA foreign_keys = OFF")
    else:
        conn.execute("PRAGMA foreign_keys = ON")
        if strategy == "defer":
            sql = f"{RESTORE_PRELUDE}\n{sql}\n{RESTORE_POSTLUDE}\n"
    conn.executescript(sql)
    conn.commit()
    if strategy == "fk_off":
        conn.execute("PRAGMA foreign_keys = ON")
    return conn


def try_load(db_path, dump_path, strategy):
    """Returns (ok, error-string). Used to measure which restore procedure
    actually works rather than assuming one does."""
    try:
        load_dump(db_path, dump_path, strategy).close()
        return True, ""
    except sqlite3.Error as exc:
        return False, f"{type(exc).__name__}: {exc}"


def split_statements(sql_text):
    """Split a dump into complete SQL statements.

    Line-splitting is not good enough: a TEXT value can contain a newline, and
    this database stores Arabic addresses and free-text notes. sqlite3's own
    completeness test is stdlib and is what the sqlite3 CLI uses.
    """
    buf = ""
    for line in sql_text.splitlines(keepends=True):
        buf += line
        if sqlite3.complete_statement(buf):
            stmt = buf.strip()
            if stmt:
                yield stmt
            buf = ""
    if buf.strip():
        yield buf.strip()


# The dump's own bookkeeping table. A restored database gets its migration
# history from `wrangler d1 migrations apply`, which is authoritative for the
# new database; replaying the old rows on top duplicates them.
BOOKKEEPING_TABLES = {"d1_migrations"}
INSERT_RE = re.compile(r'^INSERT\s+INTO\s+["`\[]?([A-Za-z_0-9]+)', re.I)


def restore_over_migrated_schema(db_path, dump_path, migrations_dir):
    """The restore procedure that survives D1's constraints.

    Why not just replay the dump: D1 runs every statement in an implicit
    transaction and therefore refuses `PRAGMA foreign_keys = OFF` — it offers
    only `defer_foreign_keys`, which defers constraint *checking* and cannot
    help when the failure is that the parent table has not been created yet.
    A .dump-shaped export orders tables alphabetically, so it hits exactly that.

    So take the schema from the place that already orders itself correctly —
    migrations/, which `wrangler d1 migrations apply` runs in numeric order —
    and take only the data from the dump. Row-order foreign key violations are
    then genuine deferred-constraint cases, which is what defer_foreign_keys is
    for.

    Returns (conn, statements_applied, tables_loaded).
    """
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA foreign_keys = ON")
    apply_migrations(conn, migrations_dir)

    inserts, tables = [], []
    for stmt in split_statements(Path(dump_path).read_text(encoding="utf-8")):
        m = INSERT_RE.match(stmt)
        if not m:
            continue                       # schema, indexes, BEGIN/COMMIT
        table = m.group(1)
        if table in BOOKKEEPING_TABLES:
            continue
        inserts.append(stmt)
        if table not in tables:
            tables.append(table)

    cur = conn.cursor()
    cur.execute("PRAGMA defer_foreign_keys = ON")
    cur.execute("BEGIN")
    # Several migrations seed reference data (document_types in 0014,
    # system_config in 0016). Those rows exist in the freshly migrated schema
    # AND in the dump, so loading the dump on top collides on the primary key.
    # The dump is the authority for data; clear what the migrations seeded.
    for table in tables:
        cur.execute(f'DELETE FROM "{table}"')
    for stmt in inserts:
        cur.execute(stmt)
    conn.commit()
    cur.execute("PRAGMA defer_foreign_keys = OFF")
    return conn, len(inserts), tables


def money_totals(conn):
    def one(sql, default=0):
        try:
            v = conn.execute(sql).fetchone()[0]
        except sqlite3.Error:
            return None
        return default if v is None else v
    return {
        "users.wallet_balance": one("SELECT ROUND(SUM(wallet_balance),2) FROM users"),
        "users.wallet_balance_piastres": one("SELECT SUM(wallet_balance_piastres) FROM users"),
        "wallet_transactions.amount": one("SELECT ROUND(SUM(amount),2) FROM wallet_transactions"),
        "trips.final_fare": one("SELECT ROUND(SUM(final_fare),2) FROM trips"),
        "payout_requests.amount": one("SELECT ROUND(SUM(amount),2) FROM payout_requests"),
    }


def cmd_rehearse(workdir, migrations_dir):
    workdir = Path(workdir)
    origin_db = workdir / "origin.db"
    dump_sql = workdir / "export.sql"
    restored_db = workdir / "restored.db"

    print("restore rehearsal — scratch SQLite, nothing live is touched\n")

    t0 = time.monotonic()
    origin = sqlite3.connect(origin_db)
    origin.execute("PRAGMA foreign_keys = ON")
    n_mig = apply_migrations(origin, migrations_dir)
    t_build = time.monotonic() - t0

    seed_money(origin)
    before = fingerprint(origin)
    before_money = money_totals(origin)
    integrity(origin, "origin")

    # 1. export — the shape `wrangler d1 export --remote --output` produces.
    t0 = time.monotonic()
    with open(dump_sql, "w", encoding="utf-8") as fh:
        for line in origin.iterdump():
            fh.write(line + "\n")
    t_dump = time.monotonic() - t0
    origin.close()
    dump_bytes = dump_sql.stat().st_size

    check("export produced a non-empty dump", dump_bytes > 0, f"{dump_bytes} bytes")
    text = dump_sql.read_text(encoding="utf-8")
    check("dump contains schema", "CREATE TABLE" in text)
    check("dump contains data", "INSERT INTO" in text)
    check("dump is complete, not truncated mid-statement",
          text.rstrip().endswith(";"))

    # 2. Which restore procedure actually works?
    #
    #    This is the finding this rehearsal exists to produce, and it is not
    #    theoretical. A .dump-shaped export lists tables in ALPHABETICAL order,
    #    not in dependency order: `audit_log`, `captains` and `payout_requests`
    #    all carry `REFERENCES users(id)` and all sort before `users`. Replaying
    #    that with foreign keys enforced dies partway through with
    #    "no such table: main.users" — an error that reads like a corrupt backup
    #    and is nothing of the sort. Cloudflare's own D1 import documentation
    #    prescribes bracketing the file with PRAGMA defer_foreign_keys for
    #    exactly this case.
    #
    #    So: measure all three, report which work, and let the runbook state a
    #    procedure that has been observed rather than one that sounds right.
    naive_ok, naive_err = try_load(workdir / "naive.db", dump_sql, "naive")
    check("naive replay with foreign keys enforced fails (expected)",
          not naive_ok, naive_err or "unexpectedly succeeded")
    defer_ok, defer_err = try_load(workdir / "defer.db", dump_sql, "defer")
    print(f"  note  defer_foreign_keys prelude on local SQLite: "
          f"{'works' if defer_ok else 'does not work — ' + defer_err}")

    #    The procedure the runbook prescribes is the third one: schema from
    #    migrations/ (which orders itself), data from the dump. It is the only
    #    one of the three that is available on D1, where `PRAGMA foreign_keys`
    #    cannot be turned off at all.
    t0 = time.monotonic()
    restored, n_inserts, loaded_tables = restore_over_migrated_schema(
        restored_db, dump_sql, migrations_dir)
    t_restore = time.monotonic() - t0
    check("schema-from-migrations + data-from-dump restores cleanly",
          True, f"{n_inserts} INSERTs across {len(loaded_tables)} table(s)")

    # And the local-only shortcut, kept because it is the fastest path when you
    # are restoring to a laptop rather than to D1.
    fkoff_ok, fkoff_err = try_load(workdir / "fkoff.db", dump_sql, "fk_off")
    check("local shortcut (foreign_keys=OFF) also restores — laptops only",
          fkoff_ok, fkoff_err or "not available on D1")

    # 3. compare.
    after = fingerprint(restored)
    after_money = money_totals(restored)
    integrity(restored, "restored")

    comparable = set(before) - BOOKKEEPING_TABLES
    check("same set of tables", comparable <= set(after),
          f"{len(before)} vs {len(after)}")
    mismatched_counts = [t for t in comparable if t in after and before[t][0] != after[t][0]]
    check("every table has the same row count", not mismatched_counts,
          ", ".join(mismatched_counts) or "all equal")
    mismatched_content = [t for t in comparable if t in after and before[t][1] != after[t][1]]
    check("every table has byte-identical contents", not mismatched_content,
          ", ".join(mismatched_content) or "all equal")

    for k in before_money:
        check(f"money preserved: {k}", before_money[k] == after_money[k],
              f"{before_money[k]} -> {after_money[k]}")

    seeded = sum(c for c, _ in before.values())
    check("the drill actually had rows to lose", seeded > 0, f"{seeded} rows")

    # 4. the failure mode the runbook warns about: importing a dump into a
    #    database that is not empty. It must fail loudly, not merge silently.
    dirty = workdir / "dirty.db"
    dirty_conn = sqlite3.connect(dirty)
    dirty_conn.execute("PRAGMA foreign_keys = ON")
    apply_migrations(dirty_conn, migrations_dir)
    dirty_conn.close()
    clashed, clash_err = try_load(dirty, dump_sql, "fk_off")
    check("importing into a non-empty database fails loudly, not silently",
          not clashed, clash_err or "restore target must be a NEW database")

    restored.close()

    print()
    print(f"  migrations applied     {n_mig}")
    print(f"  tables                 {len(before)}")
    print(f"  rows                   {seeded}")
    print(f"  dump size              {dump_bytes} bytes")
    print(f"  sha256(dump)           {hashlib.sha256(dump_sql.read_bytes()).hexdigest()}")
    print()
    print(f"  build scratch schema   {t_build:.3f}s")
    print(f"  export (dump)          {t_dump:.3f}s")
    print(f"  restore (import)       {t_restore:.3f}s")
    print(f"  total drill            {t_build + t_dump + t_restore:.3f}s")
    print()
    print(f"{CHECKS - len(FAILURES)} passed, {len(FAILURES)} failed")
    return 1 if FAILURES else 0


def cmd_check_dump(dump_path, workdir):
    """Validate a dump without touching anything live."""
    dump_path = Path(dump_path)
    if not dump_path.is_file():
        print(f"  FAIL  no such file: {dump_path}")
        return 1

    size = dump_path.stat().st_size
    text = dump_path.read_text(encoding="utf-8")
    print(f"dump: {dump_path}")
    print(f"  bytes   {size}")
    print(f"  sha256  {hashlib.sha256(dump_path.read_bytes()).hexdigest()}")
    print()

    check("non-empty", size > 0, f"{size} bytes")
    check("contains schema", "CREATE TABLE" in text)
    check("complete, not truncated mid-statement", text.rstrip().endswith(";"))

    # Does this particular dump need the foreign-key prelude? Measure it rather
    # than assume, and say so — the operator is about to type the restore
    # command and needs to know which form of it to use.
    naive_ok, naive_err = try_load(Path(workdir) / "naive.db", dump_path, "naive")
    if naive_ok:
        print("  note  replays as-is with foreign keys enforced — a plain "
              "`wrangler d1 execute --file` will work")
    else:
        print(f"  note  will NOT replay as-is: {naive_err}")
        print("  note  the tables in this dump are ordered alphabetically, not "
              "by dependency.")
        print("  note  restore it with procedure B in docs/RUNBOOK-restore.md "
              "(schema from migrations/, data from this dump).")

    target = Path(workdir) / "check.db"
    try:
        conn = load_dump(target, dump_path, "fk_off")
    except sqlite3.Error as exc:
        check("loads into an empty database", False, f"{type(exc).__name__}: {exc}")
        print(f"\n{CHECKS - len(FAILURES)} passed, {len(FAILURES)} failed")
        return 1
    check("loads into an empty database", True)
    integrity(conn, "dump")

    fp = fingerprint(conn)
    total = sum(c for c, _ in fp.values())
    check("carries data, not just schema", total > 0, f"{total} rows")

    print()
    print(f"  {len(fp)} table(s), {total} row(s)")
    for t in sorted(fp):
        if fp[t][0]:
            print(f"    {fp[t][0]:>9}  {t}")
    print()
    print("  money totals in this dump:")
    for k, v in money_totals(conn).items():
        print(f"    {k} = {v}")
    conn.close()
    print()
    print(f"{CHECKS - len(FAILURES)} passed, {len(FAILURES)} failed")
    return 1 if FAILURES else 0


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "rehearse":
        sys.exit(cmd_rehearse(sys.argv[2], sys.argv[3]))
    if mode == "check-dump":
        sys.exit(cmd_check_dump(sys.argv[2], sys.argv[3]))
    raise SystemExit(f"unknown drill mode: {mode}")
PY
}

run_rehearse() { # run_rehearse <keep:0|1>
  command -v python3 >/dev/null 2>&1 || die "python3 is required for --rehearse (stdlib only)"
  [[ -d "$MIGRATIONS_DIR" ]] || die "migrations directory not found at $MIGRATIONS_DIR"
  local work drill rc=0
  work="$(mktemp -d "${TMPDIR:-/tmp}/d1-rehearse-XXXXXX")"
  drill="$work/drill.py"
  write_drill_py "$drill"
  python3 "$drill" rehearse "$work" "$MIGRATIONS_DIR" || rc=$?
  if [[ "$1" == "1" ]]; then
    printf '\nartefacts kept in %s\n' "$work"
  else
    rm -rf "$work"
  fi
  return $rc
}

run_check_dump() { # run_check_dump <file>
  command -v python3 >/dev/null 2>&1 || die "python3 is required for --check-dump (stdlib only)"
  local work drill rc=0
  work="$(mktemp -d "${TMPDIR:-/tmp}/d1-checkdump-XXXXXX")"
  drill="$work/drill.py"
  write_drill_py "$drill"
  python3 "$drill" check-dump "$1" "$work" || rc=$?
  rm -rf "$work"
  return $rc
}

# --- self-test ---------------------------------------------------------------
# Executable form of this task's acceptance criteria, in the shape deploy.sh
# established: every path is exercised through --dry-run, so it runs with no
# wrangler, no credentials and no network.
run_self_test() {
  local pass=0 fail=0 out rc

  check() { # check <description> <0-or-1>
    if [[ "$2" == "0" ]]; then
      printf '  PASS  %s\n' "$1"; pass=$((pass + 1))
    else
      printf '  FAIL  %s\n' "$1"; fail=$((fail + 1))
    fi
  }

  printf 'backup-d1.sh self-test\n\n'

  # 1. No environment must not back anything up. Backing up the wrong database
  #    is silent until the day it matters, so the guard is the same as deploy.sh's.
  rc=0; out="$(bash "$0" 2>&1)" || rc=$?
  check "no argument exits non-zero" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
  check "no argument refuses explicitly, not incidentally" \
    "$(grep -q 'refusing to back up' <<<"$out" && echo 0 || echo 1)"
  check "no argument names the environments it will accept" \
    "$(grep -q 'backup-d1.sh prod' <<<"$out" && echo 0 || echo 1)"
  check "no argument issues no wrangler command at all" \
    "$(grep -qE 'wrangler (d1|r2)' <<<"$out" && echo 1 || echo 0)"
  # Exiting non-zero is not proof the guard held: a script that fell through and
  # then crashed on a missing wrangler also exits non-zero. Assert it never
  # reached the backup path at all.
  check "no argument never reaches the backup path" \
    "$(grep -q 'backup-d1.sh: environment=' <<<"$out" && echo 1 || echo 0)"

  # 2. An unknown environment is refused here, not passed through to wrangler.
  rc=0; out="$(bash "$0" definitely-not-an-env --dry-run 2>&1)" || rc=$?
  check "unknown environment exits non-zero" "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
  check "unknown environment lists the valid ones" \
    "$(grep -q 'prod' <<<"$out" && echo 0 || echo 1)"

  # 3. The real path, planned.
  rc=0; out="$(bash "$0" prod --dry-run 2>&1)" || rc=$?
  check "prod --dry-run exits zero" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  check "prod exports the database named in wrangler.toml" \
    "$(grep -q 'wrangler d1 export synaptic-go ' <<<"$out" && echo 0 || echo 1)"
  check "prod passes an explicit --env prod" \
    "$(grep -q 'd1 export synaptic-go --remote --env prod' <<<"$out" && echo 0 || echo 1)"

  # 4. The defect class this repo has already shipped once: a wrangler command
  #    that silently addresses LOCAL storage. Every planned command must carry
  #    --remote. Asserted per-line, so a future edit cannot drop it from one.
  local remoteless
  remoteless="$(grep -E '\[dry-run\].*wrangler (d1|r2)' <<<"$out" | grep -vc -- '--remote' || true)"
  check "every planned wrangler command passes --remote" \
    "$([[ "$remoteless" == "0" ]] && echo 0 || echo 1)"
  check "the R2 upload passes --remote" \
    "$(grep -qE 'r2 object put .*--remote' <<<"$out" && echo 0 || echo 1)"
  check "the R2 read-back passes --remote" \
    "$(grep -qE 'r2 object get .*--remote' <<<"$out" && echo 0 || echo 1)"

  # 5. A backup nobody read back is not a backup — this is gate item 15's whole
  #    lesson, and root R3 in miniature: the artefact exists, the effect is
  #    unverified. The get must be planned, and planned after the put.
  check "the upload is followed by a read-back, in that order" \
    "$([[ -n "$(grep -n 'r2 object put' <<<"$out" | head -1)" && \
          -n "$(grep -n 'r2 object get' <<<"$out" | head -1)" && \
          "$(grep -n 'r2 object put' <<<"$out" | head -1 | cut -d: -f1)" -lt \
          "$(grep -n 'r2 object get' <<<"$out" | head -1 | cut -d: -f1)" ]] && echo 0 || echo 1)"

  # 6. The object key must identify the database and the moment, or a bucket of
  #    backups is unsearchable at 3 a.m.
  check "the object key carries the database name and a UTC timestamp" \
    "$(grep -qE 'synaptic-go-backups/d1/synaptic-go/[0-9]{4}/[0-9]{2}/[0-9]{2}/synaptic-go-[0-9]{8}T[0-9]{6}Z\.sql' <<<"$out" && echo 0 || echo 1)"
  check "a manifest is written alongside the dump" \
    "$(grep -q '\.manifest\.json' <<<"$out" && echo 0 || echo 1)"

  # 7. The default bucket is not the application's own bucket.
  check "the default bucket is not the app's live FILES bucket" \
    "$(grep -q 'synaptic-go-files/' <<<"$out" && echo 1 || echo 0)"

  # 8. staging is refused while its database_id is still a placeholder
  #    (wrangler.toml:167, finding S-153). Exporting it would fail obscurely.
  rc=0; out="$(bash "$0" staging --dry-run 2>&1)" || rc=$?
  check "staging is refused while its database_id is a placeholder" \
    "$([[ $rc -ne 0 ]] && echo 0 || echo 1)"
  check "staging refusal explains why rather than just failing" \
    "$(grep -q 'placeholder' <<<"$out" && echo 0 || echo 1)"

  # 9. Static guarantees about the executable path, comments excluded. The scan
  #    starts below this function so it reads the code that runs, not the
  #    assertion strings above — which necessarily contain the literals searched for.
  # Backslash continuations are folded first, so a command split across two
  # lines is scanned as the one command it is.
  local code
  code="$(sed -n '/^# --- the backup path/,$p' "$0" | grep -vE '^[[:space:]]*#' \
          | sed -e ':a' -e '/\\$/{N;s/\\\n[[:space:]]*//;ba' -e '}')"
  check "no hardcoded database name in executable code" \
    "$(grep -qE '"synaptic-go"|=synaptic-go[^-]' <<<"$code" && echo 1 || echo 0)"
  # `d1 execute --command` is used once, read-only, to record the applied
  # migration list in the manifest. `d1 execute --file` is the IMPORT direction
  # and must never appear in a backup script: this file must not be able to
  # write to a database, only read from one.
  check "the backup path never runs 'd1 execute --file', the import direction" \
    "$(grep -qE 'd1 execute[^|]*--file' <<<"$code" && echo 1 || echo 0)"
  check "the only 'd1 execute' in the backup path is a read-only SELECT" \
    "$(grep -o 'd1 execute.*' <<<"$code" | grep -qvE -- '--command "SELECT' && echo 1 || echo 0)"
  check "the backup path never runs 'time-travel restore'" \
    "$(grep -q 'time-travel' <<<"$code" && echo 1 || echo 0)"

  # 10. The offline drill must actually pass, or the runbook's rehearsal line is
  #     a claim rather than a result.
  rc=0; out="$(bash "$0" --rehearse 2>&1)" || rc=$?
  check "the restore rehearsal passes" "$([[ $rc -eq 0 ]] && echo 0 || echo 1)"
  check "the rehearsal restores into a new database and compares contents" \
    "$(grep -q 'byte-identical contents' <<<"$out" && echo 0 || echo 1)"
  check "the rehearsal proves money survives the round trip" \
    "$(grep -q 'money preserved: users.wallet_balance' <<<"$out" && echo 0 || echo 1)"

  printf '\n%d passed, %d failed\n' "$pass" "$fail"
  [[ $fail -eq 0 ]] || return 1
  return 0
}

# --- argument parsing --------------------------------------------------------
MODE="backup"
ENVIRONMENT=""
BUCKET="$DEFAULT_BUCKET"
KEEP_LOCAL=""
KEEP_REHEARSAL=0
DUMP_TO_CHECK=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test)  MODE="self-test"; shift ;;
    --rehearse)   MODE="rehearse"; shift ;;
    --check-dump) MODE="check-dump"; DUMP_TO_CHECK="${2:-}"; [[ -n "$DUMP_TO_CHECK" ]] || die "--check-dump needs a file"; shift 2 ;;
    --keep)       KEEP_REHEARSAL=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --bucket)     BUCKET="${2:-}"; [[ -n "$BUCKET" ]] || die "--bucket needs a name"; shift 2 ;;
    --keep-local) KEEP_LOCAL="${2:-}"; [[ -n "$KEEP_LOCAL" ]] || die "--keep-local needs a directory"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    --env)        die "pass the environment positionally: bash scripts/backup-d1.sh ${2:-<env>}" ;;
    -*)           die "unknown option: $1" ;;
    *)
      [[ -z "$ENVIRONMENT" ]] || die "unexpected extra argument: $1"
      ENVIRONMENT="$1"; shift ;;
  esac
done

case "$MODE" in
  self-test)   run_self_test; exit $? ;;
  rehearse)    run_rehearse "$KEEP_REHEARSAL"; exit $? ;;
  check-dump)  run_check_dump "$DUMP_TO_CHECK"; exit $? ;;
esac

# --- the backup path ---------------------------------------------------------
[[ -f "$WRANGLER_TOML" ]] || die "wrangler.toml not found at $WRANGLER_TOML"

VALID_ENVS="$(list_envs)"
[[ -n "$VALID_ENVS" ]] || die "no [env.*] blocks found in $WRANGLER_TOML"

if [[ -z "$ENVIRONMENT" ]]; then
  printf 'backup-d1.sh: refusing to back up: no environment given.\n\n' >&2
  printf '  There is no default on purpose. A backup of the wrong database is\n' >&2
  printf '  indistinguishable from a backup of the right one until the day you\n' >&2
  printf '  need it, and that is the day it has to be right.\n\n' >&2
  printf '  Choose an environment explicitly:\n' >&2
  while IFS= read -r e; do printf '    bash scripts/backup-d1.sh %s\n' "$e" >&2; done <<<"$VALID_ENVS"
  printf '\n' >&2
  exit 1
fi

if ! grep -qx "$ENVIRONMENT" <<<"$VALID_ENVS"; then
  printf 'backup-d1.sh: unknown environment "%s".\n\n  wrangler.toml defines:\n' "$ENVIRONMENT" >&2
  while IFS= read -r e; do printf '    %s\n' "$e" >&2; done <<<"$VALID_ENVS"
  printf '\n' >&2
  exit 1
fi

DB_NAME="$(d1_field_for_env "$ENVIRONMENT" database_name)"
DB_ID="$(d1_field_for_env "$ENVIRONMENT" database_id)"
[[ -n "$DB_NAME" ]] || die "no d1_databases.database_name for [env.$ENVIRONMENT] in wrangler.toml — refusing to guess"

# staging's database_id is the literal string "staging-d1-database-id-placeholder"
# (wrangler.toml, finding S-153: staging is a stub). Exporting it produces a
# confusing wrangler error at best; worse, an operator reads the failure as "the
# backup ran and something went wrong" rather than "there is no such database".
case "$DB_ID" in
  *placeholder*)
    printf 'backup-d1.sh: [env.%s] has a placeholder database_id (%s).\n\n' "$ENVIRONMENT" "$DB_ID" >&2
    printf '  That environment does not point at a real D1 database, so there is\n' >&2
    printf '  nothing to export. Fill in a real database_id in wrangler.toml first.\n\n' >&2
    exit 1
    ;;
esac

TS="$(date -u +%Y%m%dT%H%M%SZ)"
DATE_PREFIX="$(date -u +%Y/%m/%d)"
BASENAME="${DB_NAME}-${TS}.sql"
KEY="d1/${DB_NAME}/${DATE_PREFIX}/${BASENAME}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/d1-backup-XXXXXX")"
DUMP="$WORK/$BASENAME"
MANIFEST="$WORK/${BASENAME}.manifest.json"
READBACK="$WORK/readback.sql"
trap 'rm -rf "$WORK"' EXIT

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '    [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

printf 'backup-d1.sh: environment=%s  database=%s  bucket=%s%s\n' \
  "$ENVIRONMENT" "$DB_NAME" "$BUCKET" "$([[ $DRY_RUN -eq 1 ]] && printf '  (dry run)')"
printf '            object=%s\n' "$KEY"

# 1/5 -------------------------------------------------------------------------
# --remote or this dumps the local dev database and exits 0.
step "1/5 exporting '$DB_NAME' from $ENVIRONMENT"
run npx wrangler d1 export "$DB_NAME" --remote --env "$ENVIRONMENT" --output "$DUMP"

# 2/5 -------------------------------------------------------------------------
# Check the dump before uploading it. An empty or truncated dump uploaded on
# schedule is worse than no backup: it reports success for months.
step "2/5 checking the dump before it is stored"
if [[ $DRY_RUN -eq 1 ]]; then
  printf '    [dry-run] verify %s is non-empty, contains CREATE TABLE, ends in a complete statement\n' "$DUMP"
  printf '    [dry-run] sha256sum %s\n' "$DUMP"
  DUMP_SHA="(dry-run)"; DUMP_BYTES=0; TABLE_COUNT=0
else
  [[ -s "$DUMP" ]] || die "export produced an empty file — refusing to store it as a backup"
  grep -q 'CREATE TABLE' "$DUMP" || die "export contains no CREATE TABLE — refusing to store it as a backup"
  tail -c 200 "$DUMP" | tr -d '[:space:]' | grep -q ';$' \
    || die "export does not end in a complete statement — it is truncated, refusing to store it"
  DUMP_SHA="$(sha256_of "$DUMP")"
  DUMP_BYTES="$(bytes_of "$DUMP")"
  TABLE_COUNT="$(grep -c 'CREATE TABLE' "$DUMP" || true)"
  printf '    %s bytes, %s CREATE TABLE statements, sha256 %s\n' "$DUMP_BYTES" "$TABLE_COUNT" "$DUMP_SHA"
fi

# 3/5 -------------------------------------------------------------------------
# The manifest makes the dump self-describing: which schema version it is, and
# what it should hash to. Restoring is much less frightening when the object
# says what it is.
step "3/5 writing the manifest"
if [[ $DRY_RUN -eq 1 ]]; then
  printf '    [dry-run] wrangler d1 execute %s --remote --env %s --json --command "SELECT name FROM d1_migrations ORDER BY id"\n' \
    "$DB_NAME" "$ENVIRONMENT"
  printf '    [dry-run] write %s\n' "$MANIFEST"
else
  APPLIED_MIGRATIONS="$(npx wrangler d1 execute "$DB_NAME" --remote --env "$ENVIRONMENT" \
      --json --command "SELECT name FROM d1_migrations ORDER BY id" 2>/dev/null || echo 'null')"
  LOCAL_MIGRATIONS="$(ls -1 "$MIGRATIONS_DIR"/*.sql 2>/dev/null | wc -l | tr -d ' ')"
  GIT_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
  cat > "$MANIFEST" <<JSON
{
  "database": "$DB_NAME",
  "environment": "$ENVIRONMENT",
  "taken_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "object_key": "$KEY",
  "bytes": $DUMP_BYTES,
  "sha256": "$DUMP_SHA",
  "create_table_statements": $TABLE_COUNT,
  "migrations_in_repo_at_backup_time": $LOCAL_MIGRATIONS,
  "repo_commit": "$GIT_SHA",
  "applied_migrations_remote": $APPLIED_MIGRATIONS
}
JSON
  printf '    %s\n' "$MANIFEST"
fi

# 4/5 -------------------------------------------------------------------------
step "4/5 uploading to r2://$BUCKET"
run npx wrangler r2 object put "$BUCKET/$KEY" --file "$DUMP" --remote --content-type "application/sql"
run npx wrangler r2 object put "$BUCKET/$KEY.manifest.json" --file "$MANIFEST" --remote --content-type "application/json"

# 5/5 -------------------------------------------------------------------------
# The step that makes this a backup rather than an artefact. PR #46 in this
# repository was titled "deploy the API from main", merged, and did not do that;
# the whole programme exists because work was declared done at the point of
# definition rather than effect. An upload that was never read back is the same
# shape. Fetch the object and compare hashes.
step "5/5 reading the object back and comparing hashes"
run npx wrangler r2 object get "$BUCKET/$KEY" --file "$READBACK" --remote
if [[ $DRY_RUN -eq 1 ]]; then
  printf '    [dry-run] compare sha256 of the downloaded object against %s\n' "$DUMP"
else
  [[ -s "$READBACK" ]] || die "read-back downloaded nothing from $BUCKET/$KEY — the backup is NOT stored"
  READBACK_SHA="$(sha256_of "$READBACK")"
  if [[ "$READBACK_SHA" != "$DUMP_SHA" ]]; then
    die "read-back hash mismatch: uploaded $DUMP_SHA, downloaded $READBACK_SHA — the backup is NOT trustworthy"
  fi
  printf '    verified: %s == %s\n' "$DUMP_SHA" "$READBACK_SHA"
fi

if [[ -n "$KEEP_LOCAL" && $DRY_RUN -eq 0 ]]; then
  mkdir -p "$KEEP_LOCAL"
  cp "$DUMP" "$MANIFEST" "$KEEP_LOCAL"/
  printf '\nlocal copy: %s/%s\n' "$KEEP_LOCAL" "$BASENAME"
fi

printf '\nbackup-d1.sh: done.\n'
printf '  object    r2://%s/%s\n' "$BUCKET" "$KEY"
printf '  restore   see docs/RUNBOOK-restore.md — restore into a NEW database, never in place\n'
printf '  inspect   bash scripts/backup-d1.sh --check-dump <downloaded file>\n'
