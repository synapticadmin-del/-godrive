#!/usr/bin/env python3
"""Structural hygiene checks over the working tree.

Background — why this script exists
-----------------------------------
On 2026-07-30 a batch of merges landed on `main` in which a conflict in
`apps/admin/src/pages/CaptainVerificationPage.tsx` was resolved by keeping both
sides. That produced a duplicated status badge, a duplicated container, an
unbalanced JSX tree, and a reference to an identifier that does not exist in
the file — leaving `apps/admin` unable to typecheck or build from `main`.

Nothing in the repo noticed. `typecheck` and `build` (see the `node` job in
.github/workflows/ci.yml) are the real defence against that specific damage;
this script covers the cheaper, adjacent failure modes that a type checker
cannot see — conflict markers left in files that are not type-checked at all
(SQL, YAML, Markdown, Dart), and stray merge artifacts.

Checks performed
----------------
1. No git conflict markers left in any text file
2. No merge/backup artifacts on disk (*.orig, *.rej, *.BASE.*, *~, ...)
3. No UTF-8 BOM in text files (migrations are delegated to check_migrations.py)
4. No mojibake outside migrations/
5. No committed environment files that would carry real secrets

Exit code 0 = clean, 1 = at least one error.
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Directories never worth walking.
SKIP_DIRS = {
    ".git", "node_modules", ".dart_tool", "build", "dist", ".next",
    ".wrangler", "coverage", ".venv", "__pycache__", ".idea", ".gradle",
    "Pods", ".symlinks", ".zcode",
}

# Extensions treated as binary / not our business.
SKIP_SUFFIXES = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".svg",
    ".mp4", ".mov", ".webm", ".mp3", ".wav",
    ".ttf", ".otf", ".woff", ".woff2", ".eot",
    ".zip", ".gz", ".tgz", ".jar", ".apk", ".aab", ".keystore", ".jks",
    ".pdf", ".so", ".dylib", ".dll", ".exe", ".class", ".pyc",
}

# Generated and therefore not hand-audited for encoding.
SKIP_FILES = {"package-lock.json", "pubspec.lock"}

# `migrations/` has its own dedicated checker with a documented grandfather
# list; scanning it here too would double-report the known-damaged files.
BOM_EXEMPT_DIRS = {"migrations"}
MOJIBAKE_EXEMPT_DIRS = {"migrations"}

CONFLICT_START = re.compile(r"^<{7}(?:\s|$)")
CONFLICT_END = re.compile(r"^>{7}(?:\s|$)")
CONFLICT_MID = re.compile(r"^={7}$")

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

BOM = b"\xef\xbb\xbf"

ENV_FILE_RE = re.compile(r"^\.env(\.|$)")
ENV_ALLOWED_SUFFIXES = (".example", ".sample", ".template", ".dist")


def iter_files(root: Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        if path.suffix.lower() in SKIP_SUFFIXES:
            continue
        if path.name in SKIP_FILES:
            continue
        yield path, rel


def read_text(path: Path):
    """Return decoded text, or None when the file is binary/undecodable."""
    raw = path.read_bytes()
    if b"\x00" in raw[:8192]:
        return None, raw
    body = raw[len(BOM):] if raw.startswith(BOM) else raw
    try:
        return body.decode("utf-8"), raw
    except UnicodeDecodeError:
        return None, raw


def main() -> int:
    errors: list[str] = []
    scanned = 0

    for path, rel in iter_files(REPO_ROOT):
        parts = set(rel.parts)

        # --- 2. merge / backup artifacts ---------------------------------
        name = path.name
        if (
            name.endswith((".orig", ".rej", "~"))
            or ".BASE." in name
            or ".LOCAL." in name
            or ".REMOTE." in name
            or ".BACKUP." in name
        ):
            errors.append(f"{rel}: merge/backup artifact should not be committed")
            continue

        # --- 5. committed env files ---------------------------------------
        if ENV_FILE_RE.match(name) and not name.endswith(ENV_ALLOWED_SUFFIXES):
            errors.append(
                f"{rel}: environment file is committed. Move real values to "
                f"Wrangler secrets / CI secrets and commit only a .env.example."
            )

        text, raw = read_text(path)
        if text is None:
            continue
        scanned += 1

        # --- 1. conflict markers ------------------------------------------
        starts, ends, mids = [], [], []
        for lineno, line in enumerate(text.splitlines(), start=1):
            if CONFLICT_START.match(line):
                starts.append(lineno)
            elif CONFLICT_END.match(line):
                ends.append(lineno)
            elif CONFLICT_MID.match(line):
                mids.append(lineno)

        if starts or ends:
            # A bare 7-equals line is only reported alongside a real <<<<<<< or
            # >>>>>>> marker, so a Markdown rule or comment banner made of
            # exactly seven equals signs cannot trip this check on its own.
            hits = sorted(starts + ends + mids)
            shown = ", ".join(str(n) for n in hits[:8])
            if len(hits) > 8:
                shown += f", +{len(hits) - 8} more"
            errors.append(f"{rel}: git conflict marker(s) at line(s) {shown}")

        # --- 3. BOM --------------------------------------------------------
        if raw.startswith(BOM) and not (parts & BOM_EXEMPT_DIRS):
            errors.append(
                f"{rel}: starts with a UTF-8 BOM. Re-save as UTF-8 without a signature."
            )

        # --- 4. mojibake ---------------------------------------------------
        if not (parts & MOJIBAKE_EXEMPT_DIRS):
            moji = [
                lineno
                for lineno, line in enumerate(text.splitlines(), start=1)
                if MOJIBAKE_RE.search(line)
            ]
            if moji:
                shown = ", ".join(str(n) for n in moji[:8])
                if len(moji) > 8:
                    shown += f", +{len(moji) - 8} more"
                errors.append(
                    f"{rel}: mojibake at line(s) {shown} — text was encoded as "
                    f"UTF-8 then re-read as cp1252."
                )

    print(f"scanned {scanned} text file(s) under {REPO_ROOT}")

    if errors:
        print()
        for err in errors:
            print(f"  FAIL  {err}")
        print(f"\ncheck_repo_hygiene: {len(errors)} error(s)")
        return 1

    print("check_repo_hygiene: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
