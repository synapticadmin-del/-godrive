# scripts/

Repository checks run by CI (`.github/workflows/ci.yml`) and available locally.

## Running them

```bash
npm run check     # the four Python checks below
npm run verify    # everything CI runs: typecheck + build + tests + check
```

Each script is stdlib-only Python 3 — no `pip install`, no dependencies. Each
exits `0` when clean and `1` on the first category of failure it finds, and
prints one `FAIL` line per problem with the file and line number.

Run any of them individually:

```bash
python3 scripts/check_migrations.py
python3 scripts/check_migrations_apply.py
python3 scripts/check_l10n_parity.py
python3 scripts/check_repo_hygiene.py
```

## What each one guards

### `check_migrations.py` — static migration checks

Filename shape, contiguous numbering, valid UTF-8, no empty files, no UTF-8 BOM,
and no mojibake in executable SQL.

Mojibake inside a `--` comment is **allowed on purpose**: a repair migration has
to be able to quote the corrupted value it is fixing, which is exactly what
`0017_fix_document_type_titles.sql` does.

Two files are explicitly grandfathered in the script, with the reason stated
there: `0014_document_types.sql` (BOM + double-encoded Arabic seed values) and
`0015_captain_onboarding_fields.sql` (BOM). Both have already been applied in
real environments. D1 tracks applied migrations by filename, so rewriting them
now would change nothing for any existing database while making the committed
file diverge from what actually ran. `0017` repairs the data forward instead.

### `check_migrations_apply.py` — migrations actually execute

Applies all migrations in order to a throwaway SQLite database. Catches the
class of bug where an early migration is retro-edited so a later one can no
longer apply — invisible to everyone who already has a database, fatal to
anyone creating one. That exact fault shipped once: `0001_init.sql` was edited
to declare `password_hash`, so `0007_add_password_hash.sql` failed with
"duplicate column name" and a fresh environment aborted at step 7 of 17.

Uses stdlib `sqlite3` with `PRAGMA foreign_keys = ON`. D1 is SQLite underneath,
so this catches schema-ordering faults, but it does **not** validate
D1-specific behaviour and never touches a real database.

### `check_l10n_parity.py` — string catalogue integrity

Covers `packages/flutter_shared/lib/l10n/app_strings.dart`:

- no member declared twice in the same class (a Dart compile error — two
  separate commits in this repo exist purely to undo duplicate getters that
  merges introduced)
- every member on the abstract `AppStrings` implemented by every locale class
- the locale classes declare identical member sets, so a string cannot be added
  to Arabic and forgotten in English

Members implemented by a locale class but not declared abstract are reported as
notes, not failures — that is legal Dart and one such member exists on purpose.

If the parser meets a member shape it does not understand it **fails** rather
than skipping it, so the check can never give a false OK on a catalogue it was
not designed for. If you add a genuinely new member shape, teach the script
about it.

`flutter analyze` would catch all of this too, but Flutter is not installed on
the CI runners; this needs nothing but Python.

### `check_repo_hygiene.py` — merge and encoding hygiene

Conflict markers left in any text file, stray merge/backup artifacts
(`*.orig`, `*.rej`, `*.BASE.*`, …), UTF-8 BOMs outside `migrations/`, mojibake
outside `migrations/`, and committed `.env` files (`.env.example` and friends
are fine).

A bare seven-equals line is only reported when a real `<<<<<<<` or `>>>>>>>`
marker exists in the same file, so a Markdown rule or comment banner cannot
trip it.

## A note on the mojibake pattern

Both encoding checks use a deliberately narrow lead-byte set,
`[ÃØ-Û]` followed by `[-¿]`.

Arabic (U+0600–U+06FF) encodes to UTF-8 lead bytes `0xD8`–`0xDB`, so Arabic
re-read as cp1252 always shows a lead in that band. `0xC3` is the classic
Latin-1 double-encode lead.

`0xD7` and `0xF7` — the multiplication and division signs — are excluded on
purpose. Real Arabic UI copy in this repo tells the user to press the `×`
delete glyph inside guillemets, and a wider lead set reports that valid text as
mojibake.

The pattern is written with escape sequences rather than literal characters so
these files stay pure ASCII: a literal high-Latin-1 pattern makes the checker
flag its own source, and an invisible C1 byte in a pattern is easy to lose in
transit and silently turns the check into one that always passes.

## What is not covered

- **`flutter analyze` / `flutter build`.** Neither Flutter app is compiled in
  CI. `check_l10n_parity.py` covers the one failure mode that has actually
  recurred, but a real Flutter job would be a strict improvement.
- **Tests for `apps/admin`.** There are none. `npm test` currently runs the nine
  tests in `packages/shared` and nothing else.
- **Anything against real D1 or a deployed Worker.**
