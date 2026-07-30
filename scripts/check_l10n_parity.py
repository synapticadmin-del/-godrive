#!/usr/bin/env python3
"""Guard the shared Flutter string catalogue against locale drift and duplicates.

Background — why this script exists
-----------------------------------
`packages/flutter_shared/lib/l10n/app_strings.dart` holds one abstract class
(`AppStrings`) plus one concrete implementation per locale (`AppStringsAr`,
`AppStringsEn`). Two failure modes have already cost real time in this repo:

* **Duplicate getters.** Two separate commits (`11e3464`, `c6d54c09`) exist
  purely to delete duplicate getters that merges introduced. In Dart a
  duplicated member is a hard compile error, so this breaks the Flutter build
  for everyone — but nothing in the repo catches it before a developer runs
  `flutter analyze` locally.
* **Locale drift.** A string added to the Arabic class but not the English one
  (or vice versa) means the app silently falls back or fails to compile
  depending on where the gap is.

`flutter analyze` would catch both, but Flutter is not installed on CI runners
here. This is a cheap structural check that needs nothing but Python.

Checks performed
----------------
1. The abstract class and at least two implementations are present
2. No duplicate member declared twice inside the same class (Dart compile error)
3. Every abstract member is implemented by every locale class (compile error)
4. All locale classes declare exactly the same member set (locale drift)
5. Any member lines the parser could not classify are surfaced, not ignored

Members implemented by the locale classes but NOT declared abstract are
reported as notes, not errors — that is legal Dart and at least one such member
exists on purpose.

Exit code 0 = clean, 1 = at least one error.
"""

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CATALOG = REPO_ROOT / "packages" / "flutter_shared" / "lib" / "l10n" / "app_strings.dart"

# Members are declared at exactly one level of indentation inside the class
# body. Anchoring on that depth is what keeps statements inside method bodies
# from being mistaken for member declarations.
MEMBER_INDENT = "  "

CLASS_RE = re.compile(r"^(?P<abstract>abstract\s+)?class\s+(?P<name>\w+)\b")
GETTER_RE = re.compile(
    r"^" + MEMBER_INDENT + r"(?![ \t])"
    r"[\w<>,\[\]?\s]+?\bget\s+(?P<name>\w+)\s*(?P<tail>;|=>)"
)
METHOD_RE = re.compile(
    r"^" + MEMBER_INDENT + r"(?![ \t])"
    r"[\w<>,\[\]?\s]+?\s(?P<name>\w+)\s*\((?P<args>[^()]*)\)\s*(?P<tail>.*)$"
)
# Lines that look member-shaped but are not members.
SKIP_RE = re.compile(
    r"^" + MEMBER_INDENT + r"(?![ \t])"
    r"(@|//|/\*|\*|const\s|factory\s|static\s|\}|\{)"
)


class ClassInfo:
    def __init__(self, name: str, is_abstract: bool, start: int):
        self.name = name
        self.is_abstract = is_abstract
        self.start = start
        self.members: dict[str, int] = {}       # name -> first line seen
        self.duplicates: list[tuple[str, int]] = []
        self.unparsed: list[tuple[int, str]] = []

    def add(self, name: str, lineno: int) -> None:
        if name in self.members:
            self.duplicates.append((name, lineno))
        else:
            self.members[name] = lineno


def parse(path: Path) -> list[ClassInfo]:
    lines = path.read_text(encoding="utf-8").splitlines()

    classes: list[ClassInfo] = []
    current: ClassInfo | None = None

    for lineno, line in enumerate(lines, start=1):
        cm = CLASS_RE.match(line)
        if cm:
            current = ClassInfo(
                cm.group("name"), bool(cm.group("abstract")), lineno
            )
            classes.append(current)
            continue

        if current is None:
            continue
        if not line.startswith(MEMBER_INDENT) or line[2:3] in (" ", "\t", ""):
            continue
        if SKIP_RE.match(line):
            continue

        gm = GETTER_RE.match(line)
        if gm:
            current.add(gm.group("name"), lineno)
            continue

        mm = METHOD_RE.match(line)
        if mm:
            current.add(mm.group("name"), lineno)
            continue

        stripped = line.strip()
        # A member-depth line that declares something we do not understand.
        # Report it rather than silently dropping it, so the check cannot give
        # a false OK on a catalogue shape it was not designed for.
        if stripped and not stripped.startswith(("return", "if", "switch", "case",
                                                 "default:", "}", "assert")):
            current.unparsed.append((lineno, stripped[:90]))

    return classes


def main() -> int:
    if not CATALOG.is_file():
        print(f"FAIL  string catalogue not found at {CATALOG}")
        return 1

    classes = parse(CATALOG)
    abstracts = [c for c in classes if c.is_abstract]
    locales = [c for c in classes if not c.is_abstract]

    errors: list[str] = []
    notes: list[str] = []

    rel = CATALOG.relative_to(REPO_ROOT)
    print(f"checked {rel}")

    if len(abstracts) != 1:
        print(f"  FAIL  expected exactly 1 abstract class, found {len(abstracts)}")
        return 1
    if len(locales) < 2:
        print(f"  FAIL  expected at least 2 locale classes, found {len(locales)}")
        return 1

    base = abstracts[0]
    print(
        f"  {base.name} (abstract): {len(base.members)} member(s)  "
        + "  ".join(f"{c.name}: {len(c.members)}" for c in locales)
    )

    # --- 2. duplicates ----------------------------------------------------
    for c in classes:
        for name, lineno in c.duplicates:
            errors.append(
                f"{c.name}: '{name}' declared more than once "
                f"(first at line {c.members[name]}, again at line {lineno}). "
                f"Dart rejects duplicate members — this breaks the build."
            )

    # --- 5. unparsed member-depth lines -----------------------------------
    for c in classes:
        for lineno, text in c.unparsed:
            errors.append(
                f"{c.name}: could not classify member-depth line {lineno}: {text!r}. "
                f"If this is a valid new member shape, teach this script about it."
            )

    # --- 3. abstract fully implemented ------------------------------------
    for c in locales:
        missing = sorted(set(base.members) - set(c.members))
        if missing:
            shown = ", ".join(missing[:10])
            if len(missing) > 10:
                shown += f", +{len(missing) - 10} more"
            errors.append(
                f"{c.name}: {len(missing)} member(s) declared on {base.name} "
                f"but not implemented: {shown}"
            )

    # --- 4. locale classes agree with each other --------------------------
    reference = locales[0]
    for other in locales[1:]:
        only_ref = sorted(set(reference.members) - set(other.members))
        only_other = sorted(set(other.members) - set(reference.members))
        if only_ref:
            shown = ", ".join(only_ref[:10])
            if len(only_ref) > 10:
                shown += f", +{len(only_ref) - 10} more"
            errors.append(
                f"locale drift: {len(only_ref)} member(s) in {reference.name} "
                f"missing from {other.name}: {shown}"
            )
        if only_other:
            shown = ", ".join(only_other[:10])
            if len(only_other) > 10:
                shown += f", +{len(only_other) - 10} more"
            errors.append(
                f"locale drift: {len(only_other)} member(s) in {other.name} "
                f"missing from {reference.name}: {shown}"
            )

    # --- extras (legal, informational) ------------------------------------
    for c in locales:
        extra = sorted(set(c.members) - set(base.members))
        if extra:
            notes.append(
                f"{c.name}: {len(extra)} member(s) not declared on {base.name} "
                f"(legal Dart): {', '.join(extra[:10])}"
            )

    for note in notes:
        print(f"  note  {note}")

    if errors:
        print()
        for err in errors:
            print(f"  FAIL  {err}")
        print(f"\ncheck_l10n_parity: {len(errors)} error(s)")
        return 1

    print("check_l10n_parity: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
