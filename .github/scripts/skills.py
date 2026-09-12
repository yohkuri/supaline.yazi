# /// script
# requires-python = ">=3.11"
# dependencies = ["skills-ref==0.1.1"]
# ///
"""Every skill under `.agents/skills`, against the Agent Skills specification.

The specification's own half is `skills-ref`, the reference library the
specification points at for exactly this (<https://agentskills.io/specification>,
read 2026-09-12). It parses the frontmatter with a real YAML parser, so a
duplicate key, an unquoted `:` and a field the specification does not define
are refused here as well now -- the shell this replaced read the frontmatter
with `awk`, which took the first `name:` line it saw and said nothing about the
rest.

The pin is in the header above and nowhere else: `uv run` reads it, and CI runs
the same line rather than installing anything of its own. `skills-ref` is
0.1.1 on PyPI and 0.1.0 in its own tree; the published one is the one pinned,
and it carries a fix the tree does not.

What `skills-ref validate` does **not** reach, and this file does:

- a literal `---` in the frontmatter. Its parser is `content.split("---", 2)`,
  so a `---` anywhere past the opening fence ends the frontmatter there, and
  what follows is dropped in silence. Measured on 0.1.1: a 2045-character
  description with `---` at character 41 is read as 40 characters and passes
  the 1024 limit. This one is checked first and stops the rest of the file
  being measured, because past it `skills-ref` is measuring something else.
- a name carrying `anthropic` or `claude`. Not the specification's -- it
  reserves nothing (read 2026-09-12, and no commit in the last 200 of its
  history added such a rule), and Claude Code's reserved names are a rule
  about a *marketplace* name. This one is this repository's own: a plugin not
  from those vendors does not put their names in a skill's.
- a name outside a-z, 0-9 and single hyphens. The specification's wording is
  "unicode lowercase alphanumeric characters (`a-z`, `0-9`)", and `skills-ref`
  reads it the permissive way: a name in Japanese validates. This tree stays
  ASCII, which is this repository's choice rather than the specification's.
- a body over 500 lines, and a reference over 100 without a `## Contents` that
  names every section it has. Neither is a frontmatter rule, so neither is in
  the library at all.
"""

import re
import sys
from pathlib import Path

from skills_ref.errors import ParseError
from skills_ref.parser import parse_frontmatter
from skills_ref.validator import validate_metadata

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / ".agents" / "skills"

# "Keep your main `SKILL.md` under 500 lines", from the specification.
BODY_LIMIT = 500
# This repository's: past it a reference is read in parts, and a part has to
# show what the whole covers.
CONTENTS_LIMIT = 100

NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
RESERVED = ("anthropic", "claude")

# `skills-ref` says what the rule is; these say what breaking it costs, which
# is the half a reader cannot work out from the message.
LIBRARY_NOTES = {
    "Description exceeds": (
        "Past it a strict client rejects the skill outright, and a lenient",
        "one truncates -- taking the 'when not to read it' half with it.",
    ),
    "Unexpected fields": (
        "The specification defines those six and no others. Anything of your",
        "own goes under `metadata:`, as a map of string to string.",
    ),
}

rc = 0


def report(where, what, *notes):
    """Say what is wrong, then what to write instead. Never just the first."""
    global rc
    print(f"{where}: {what}")
    for note in notes:
        print(f"  {note}")
    rc = 1


def rel(path):
    return path.relative_to(ROOT)


def headings(lines):
    """The `## ` headings outside fenced blocks, in order.

    A heading inside a fence is not one: these files quote shell, where `##`
    is a comment.
    """
    out, fence = [], False
    for line in lines:
        if line.startswith("```"):
            fence = not fence
        elif not fence and line.startswith("## "):
            out.append(line[3:])
    return out


def contents_block(lines):
    """The lines under `## Contents`, to the next heading outside a fence."""
    out, fence, seen = [], False, False
    for line in lines:
        if line.startswith("```"):
            fence = not fence
            if seen:
                out.append(line)
            continue
        if not fence and line == "## Contents":
            seen = True
            continue
        if not fence and line.startswith("## ") and seen:
            break
        if seen:
            out.append(line)
    return out


def check_skill(directory):
    # Read off the directory rather than asking whether the path exists: a
    # case-insensitive filesystem answers yes to `SKILL.md` when the file on
    # disk is `skill.md`, so the same tree that passes on macOS fails on the
    # runner. Measured here, on APFS, by planting the lowercase one.
    names = {p.name for p in directory.iterdir()}
    if "SKILL.md" not in names:
        notes = []
        if "skill.md" in names:
            notes.append("There is a skill.md here. `skills-ref` reads that spelling")
            notes.append("too; every skill in this tree spells it SKILL.md, and which")
            notes.append("clients read the lowercase one is not measured here.")
        report(rel(directory), "no SKILL.md.", *notes)
        return

    f = directory / "SKILL.md"

    text = f.read_text(encoding="utf-8")
    lines = text.splitlines()

    if not lines or lines[0] != "---":
        report(
            rel(f),
            "does not open with a --- frontmatter fence.",
            "A client reads no skill here, and nothing below can be measured.",
        )
        return

    fm_end = next((n for n, line in enumerate(lines[1:], 2) if line == "---"), 0)
    if not fm_end:
        report(
            rel(f),
            "the frontmatter never closes.",
            "Add the closing ---. Without it a client reads no skill here, and",
            "nothing below can be measured.",
        )
        return

    cut = [
        (n, line) for n, line in enumerate(lines[1 : fm_end - 1], 2) if "---" in line
    ]
    if cut:
        n, line = cut[0]
        report(
            f"{rel(f)}:{n}",
            "a literal --- inside the frontmatter.",
            f"    {line.strip()}",
            "A client cuts the frontmatter at the first --- after the opening",
            "fence, so everything from here on is dropped: the description in",
            "the listing ends at this point, and a field below it is not read",
            "at all. Name a class or a field annotation rather than spelling",
            "one. Nothing else in this frontmatter is measured until it is gone.",
        )
        return

    try:
        metadata, _ = parse_frontmatter(text)
    except ParseError as e:
        headline, *rest = str(e).splitlines()
        report(rel(f), headline, *rest)
        return

    for error in validate_metadata(metadata, directory):
        headline, *rest = error.splitlines()
        notes = [line for line in rest]
        for prefix, note in LIBRARY_NOTES.items():
            if headline.startswith(prefix):
                notes.extend(note)
        report(rel(f), headline, *notes)

    name = metadata.get("name")
    if isinstance(name, str) and name.strip():
        name = name.strip()
        if not NAME.fullmatch(name):
            report(
                rel(f),
                f"name `{name}` is not lowercase-alphanumeric-hyphen.",
                "The specification allows a Unicode letter and skills-ref takes",
                "it at its word; this tree stays on a-z, 0-9 and single hyphens.",
            )
        for word in RESERVED:
            if word in name:
                report(
                    rel(f),
                    f"name `{name}` carries `{word}`.",
                    "This plugin is not from that vendor, so its skills do not",
                    "say so. This rule is this repository's, not the spec's.",
                )

    body = text.count("\n") - fm_end
    if body > BODY_LIMIT:
        report(
            rel(f),
            f"body is {body} lines, over the {BODY_LIMIT}-line budget.",
            "Move what a reader does not need every time into references/.",
        )


def check_reference(f):
    text = f.read_text(encoding="utf-8")
    count = text.count("\n")
    if count <= CONTENTS_LIMIT:
        return

    lines = text.splitlines()
    heads = headings(lines)
    if "Contents" not in heads:
        report(
            rel(f),
            f"{count} lines and no '## Contents' heading.",
            "List the sections at the top, so a partial read still shows what",
            "the file covers.",
        )
        return

    block = contents_block(lines)
    sections = [h for h in heads if h != "Contents"]
    listed = sum(1 for line in block if line.startswith("- "))
    if listed != len(sections):
        report(rel(f), f"Contents lists {listed} of {len(sections)} sections.")

    joined = "\n".join(block)
    for heading in sections:
        if heading not in joined:
            report(
                rel(f),
                f"not in Contents: {heading}",
                "A renamed section keeps the count and loses its entry, so the",
                "count above says nothing about it.",
            )


def main():
    directories = sorted(p for p in SKILLS.glob("*") if p.is_dir())
    if not directories:
        report(f"{rel(SKILLS)}/", "no skill found. Has the tree moved?")
    for directory in directories:
        check_skill(directory)
    for reference in sorted(SKILLS.glob("*/references/*.md")):
        check_reference(reference)
    return rc


if __name__ == "__main__":
    sys.exit(main())
