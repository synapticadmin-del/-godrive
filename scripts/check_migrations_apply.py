#!/usr/bin/env python3
"""Apply every migration, in order, to a throwaway SQLite database.

Why this is separate from check_migrations.py
---------------------------------------------
`check_migrations.py` is a static check: naming, ordering, encoding. This one
actually executes the SQL. They are kept apart because they fail for different
reasons and you usually want to know which: a BOM is an authoring mistake, a
"duplicate column name" is a broken migration chain.

Background — the bug this would have caught
-------------------------------------------
`0001_init.sql` was retroactively edited to declare `password_hash`, which made
`0007_add_password_hash.sql` fail with "duplicate column name" on any fresh
database. Migrations aborted at step 7 of 17, so a brand-new environment could
not be bootstrapped at all — while every existing environment stayed fine,
because D1 tracks applied migrations by filename and had already run 0007. That
is the signature of this whole class of bug: invisible to everyone who already
has a database, fatal to anyone creating one.

D1 is SQLite under the hood, so stdlib `sqlite3` is a faithful enough harness
to catch schema-ordering faults. It does NOT validate D1-specific behaviour, and
it does not touch any real database.

Exit code 0 = every migration applied, 1 = at least one failed.
"""

import sqlite3
import sys
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = REPO_ROOT / "migrations"
BOM = b"\xef\xbb\xbf"


def main() -> int:
    if not MIGRATIONS_DIR.is_dir():
        print(f"FAIL  migrations directory not found at {MIGRATIONS_DIR}")
        return 1

    files = sorted(MIGRATIONS_DIR.glob("*.sql"))
    if not files:
        print(f"FAIL  no .sql files found in {MIGRATIONS_DIR}")
        return 1

    tmpdir = tempfile.mkdtemp(prefix="migration-check-")
    db_path = Path(tmpdir) / "fresh.db"

    conn = sqlite3.connect(db_path)
    # Match D1: foreign keys are enforced.
    conn.execute("PRAGMA foreign_keys = ON")

    applied = 0
    failed: list[tuple[str, str]] = []

    for path in files:
        raw = path.read_bytes()
        # Strip a leading BOM for execution only. The file on disk is left
        # alone; check_migrations.py is what reports the BOM itself.
        if raw.startswith(BOM):
            raw = raw[len(BOM):]
        sql = raw.decode("utf-8")
        try:
            conn.executescript(sql)
            conn.commit()
            applied += 1
            print(f"  ok    {path.name}")
        except Exception as exc:  # noqa: BLE001 - surface whatever sqlite raises
            failed.append((path.name, f"{type(exc).__name__}: {exc}"))
            print(f"  FAIL  {path.name}: {type(exc).__name__}: {exc}")
            # Stop at the first failure: everything after it is applied to a
            # schema that never existed, so later errors would be noise.
            break

    table_count = conn.execute(
        "SELECT count(*) FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%'"
    ).fetchone()[0]
    conn.close()

    print()
    print(f"applied {applied}/{len(files)} migration(s) to a fresh database")
    print(f"resulting schema: {table_count} table(s)")

    if failed:
        print()
        for name, err in failed:
            print(f"  FAIL  {name}: {err}")
        print(
            f"\ncheck_migrations_apply: aborted at {failed[0][0]}. "
            f"A fresh environment cannot be bootstrapped until this is fixed."
        )
        return 1

    print("check_migrations_apply: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
