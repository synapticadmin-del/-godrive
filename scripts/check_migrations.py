#!/usr/bin/env python3
"""Guard the D1 migration directory against the encoding and ordering faults
that have already shipped to production once.

Background — why this script exists
-----------------------------------
`0014_document_types.sql` was committed with a UTF-8 BOM *and* with its Arabic
seed values double-encoded (UTF-8 bytes read back as cp1252). In every
environment that ran it, each `document_types.title_ar` value is stored as a
run of Latin-1 lead/continuation pairs instead of the intended Arabic — text
that is user-facing in both the captain upload grid and the admin verification
page.
`0017_fix_document_type_titles.sql` repairs those rows forward.

Editing an already-applied migration cannot help environments that ran it, and
D1 tracks applied migrations by filename, so the damaged files are deliberately
left alone and listed in GRANDFATHERED below. The point of this check is to
stop the *next* one.

Checks performed
----------------
1. Filenames match NNNN_lower_snake_case.sql
2. Numbering is contiguous from 0001 with no gaps and no duplicates
3. Every file decodes as UTF-8
4. No file is empty
5. No UTF-8 BOM (grandfathered: see GRANDFATHERED_BOM)
6. No mojibake in executable SQL (grandfathered: see GRANDFATHERED_MOJIBAKE)

On the mojibake rule: mojibake inside a `--` comment is ALLOWED. A repair
migration has to name the corrupted value it is fixing, and 0017 legitimately
quotes the broken string in a comment. Only mojibake that would be *written to
the database* is an error.

Exit code 0 = clean, 1 = at least one error.
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MIGRATIONS_DIR = REPO_ROOT / "migrations"

FILENAME_RE = re.compile(r"^(\d{4})_[a-z0-9]+(?:_[a-z0-9]+)*\.sql$")

# Signature of UTF-8 bytes decoded as cp1252/latin1, written as explicit
# escapes so this file stays pure ASCII and cannot flag itself.
#
# Lead set is deliberately narrow. Arabic (U+0600-U+06FF) encodes to UTF-8
# lead bytes 0xD8-0xDB, so Arabic re-read as cp1252 always shows a lead in
# that band ("\u00d8", "\u00d9", "\u00da", "\u00db"). 0xC3 is the classic
# Latin-1 double-encode lead. 0xD7 and 0xF7 are EXCLUDED on purpose: they are
# the multiplication and division signs, and real Arabic UI copy in this repo
# contains the delete-button glyph "\u00d7" followed by a guillemet, which a
# wider lead set reports as mojibake when it is perfectly valid text.
MOJIBAKE_RE = re.compile("[\u00c3\u00d8-\u00db][\u0080-\u00bf]")

# Already applied in production. Cannot be repaired in place — D1 keys applied
# migrations by filename, so rewriting these files would change nothing for
# existing environments while silently diverging from what actually ran.
GRANDFATHERED_BOM = {
    "0014_document_types.sql",
    "0015_captain_onboarding_fields.sql",
}
GRANDFATHERED_MOJIBAKE = {
    # Double-encoded Arabic seed values; repaired forward by 0017.
    "0014_document_types.sql",
}

BOM = b"\xef\xbb\xbf"


def strip_sql_comments(line: str) -> str:
    """Return the executable part of a line: everything before a `--` comment.

    Quote-aware so that a `--` inside a string literal is not mistaken for the
    start of a comment.
    """
    in_single = False
    in_double = False
    i = 0
    while i < len(line):
        ch = line[i]
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif (
            ch == "-"
            and i + 1 < len(line)
            and line[i + 1] == "-"
            and not in_single
            and not in_double
        ):
            return line[:i]
        i += 1
    return line


def main() -> int:
    errors: list[str] = []
    notes: list[str] = []

    if not MIGRATIONS_DIR.is_dir():
        print(f"FAIL  migrations directory not found at {MIGRATIONS_DIR}")
        return 1

    files = sorted(p for p in MIGRATIONS_DIR.iterdir() if p.is_file())

    if not files:
        print(f"FAIL  no files found in {MIGRATIONS_DIR}")
        return 1

    # --- 1. filenames -----------------------------------------------------
    numbers: dict[int, list[str]] = {}
    for path in files:
        if path.suffix != ".sql":
            errors.append(f"{path.name}: non-.sql file in migrations/")
            continue
        m = FILENAME_RE.match(path.name)
        if not m:
            errors.append(
                f"{path.name}: filename must match NNNN_lower_snake_case.sql"
            )
            continue
        numbers.setdefault(int(m.group(1)), []).append(path.name)

    # --- 2. numbering -----------------------------------------------------
    for num, names in sorted(numbers.items()):
        if len(names) > 1:
            errors.append(
                f"duplicate migration number {num:04d}: {', '.join(sorted(names))}"
            )
    if numbers:
        expected = set(range(1, max(numbers) + 1))
        gaps = sorted(expected - set(numbers))
        if gaps:
            errors.append(
                "gap(s) in migration numbering: "
                + ", ".join(f"{n:04d}" for n in gaps)
            )

    # --- 3-6. per-file content -------------------------------------------
    for path in sorted(p for p in files if p.suffix == ".sql"):
        name = path.name
        raw = path.read_bytes()

        if not raw.strip():
            errors.append(f"{name}: file is empty")
            continue

        has_bom = raw.startswith(BOM)
        body = raw[len(BOM):] if has_bom else raw

        try:
            text = body.decode("utf-8")
        except UnicodeDecodeError as exc:
            errors.append(f"{name}: not valid UTF-8 ({exc})")
            continue

        if has_bom:
            if name in GRANDFATHERED_BOM:
                notes.append(f"{name}: UTF-8 BOM (grandfathered — already applied)")
            else:
                errors.append(
                    f"{name}: starts with a UTF-8 BOM. Save the file as UTF-8 "
                    f"without a signature; a BOM can break the first statement."
                )

        moji_lines = []
        for lineno, line in enumerate(text.splitlines(), start=1):
            executable = strip_sql_comments(line)
            if MOJIBAKE_RE.search(executable):
                moji_lines.append(lineno)

        if moji_lines:
            shown = ", ".join(str(n) for n in moji_lines[:8])
            if len(moji_lines) > 8:
                shown += f", +{len(moji_lines) - 8} more"
            if name in GRANDFATHERED_MOJIBAKE:
                notes.append(
                    f"{name}: {len(moji_lines)} mojibake line(s) in SQL "
                    f"(grandfathered — repaired forward by 0017)"
                )
            else:
                errors.append(
                    f"{name}: mojibake in executable SQL at line(s) {shown}. "
                    f"Arabic text was encoded as UTF-8 then re-read as cp1252. "
                    f"Re-save the file as UTF-8 and re-enter the Arabic values."
                )

    # --- report -----------------------------------------------------------
    sql_count = sum(1 for p in files if p.suffix == ".sql")
    print(f"checked {sql_count} migration(s) in {MIGRATIONS_DIR.relative_to(REPO_ROOT)}")

    for note in notes:
        print(f"  note  {note}")

    if errors:
        print()
        for err in errors:
            print(f"  FAIL  {err}")
        print(f"\ncheck_migrations: {len(errors)} error(s)")
        return 1

    print("check_migrations: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
