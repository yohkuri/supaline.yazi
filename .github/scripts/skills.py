# /// script
# requires-python = ">=3.11"
# dependencies = ["skills-ref==0.1.1"]
# ///
"""Every skill under `.agents/skills` against the Agent Skills
specification, and `AGENTS.md` against the budget that keeps it an index.

The specification's own half is `skills-ref`, the reference library the
specification points at for exactly this
(<https://agentskills.io/specification>, read 2026-09-12). It parses the
frontmatter with a real YAML parser, so a duplicate key, an unquoted `:` and
a field the specification does not define are refused here as well -- the
shell this replaced read the frontmatter with `awk`, which took the first
`name:` line it saw and said nothing about the rest.

Only what the library exports is called. `validate` and `read_properties` are
in its `__all__`; the internals under them are not, and a release that moves
one would be an ImportError rather than a finding.

`skills.py.lock` beside this file pins what the header cannot: `strictyaml`,
which is what actually refuses a duplicate key and folds a `>-` description
before it is measured. Written by `uv lock --script`, read by `uv run` with no
flag. Re-run that after changing the header.

What the library does **not** reach, and this file does:

- a literal `---` in the frontmatter. Its parser is `content.split("---", 2)`,
  so a `---` anywhere past the opening fence ends the frontmatter there, and
  what follows is dropped in silence. Measured on 0.1.1: a 2045-character
  description with `---` at character 41 is read as 40 characters and passes
  the 1024 limit. What the library would say about such a file is withheld
  rather than printed, because past that point it is measuring something else.
- a name carrying `anthropic` or `claude`. Not the specification's -- it
  reserves nothing (read 2026-09-12, and no commit in the last 200 of its
  history added such a rule), and Claude Code's reserved names are a rule
  about a *marketplace* name. This one is this repository's own: a plugin not
  from those vendors does not put their names in a skill's.
- a name outside a-z, 0-9 and single hyphens. The specification's wording is
  "unicode lowercase alphanumeric characters (`a-z`, `0-9`)", and `skills-ref`
  reads it the permissive way: a name in Japanese validates. This tree stays
  ASCII, which is this repository's choice rather than the specification's.
- `SKILL.md` by that spelling. The library reads `skill.md` too, and a
  case-insensitive filesystem answers to either, so the directory is read by
  name -- otherwise the tree passes on macOS and fails on the runner.
- a file of 500 lines or more, and a reference over 100 whose `## Contents`
  does not name every section it has. Neither is a frontmatter rule, so
  neither is in the library at all.
- `AGENTS.md`, which is not a skill and is checked here anyway. It is the
  index the skills hang off, and it was the one instruction document under no
  budget at all while every `SKILL.md` had one -- which is the asymmetry that
  let it reach 381 lines. `check_index` is that budget.
"""

import re
import sys
from pathlib import Path

from skills_ref import SkillError, read_properties, validate

ROOT = Path(__file__).resolve().parents[2]
SKILLS = ROOT / ".agents" / "skills"
INDEX = ROOT / "AGENTS.md"

# "Keep your main `SKILL.md` under 500 lines", from the specification -- the
# file, so a long frontmatter counts, and *under*, so 500 is already over.
FILE_LIMIT = 500
# This repository's: past it a reference is read in parts, and a part has to
# show what the whole covers.
CONTENTS_LIMIT = 100

# `AGENTS.md`'s, and a budget rather than a measurement. A section past this
# is carrying detail that belongs in a skill or evidence that belongs in a
# `references/` file, and the way to spend the budget is to move something out
# rather than to raise the number. The file stood at 173 prose lines over nine
# sections, the longest 27, at the commit that set these -- so the headroom is
# a rule or two that genuinely applies to every session, and not a mechanism.
INDEX_SECTION_LIMIT = 30
INDEX_LIMIT = 200

# A skill's. The section number is the index's, because it is the same rule:
# `document-supaline` says a section running longer than the thing it tells you
# to do is carrying evidence, and then left the noticing to whoever happened to
# be reading. That sentence is this check, and it holds wherever prose is
# written here.
SKILL_SECTION_LIMIT = 30
# The file number is not the index's, and matching them was a mistake worth
# leaving a note about. The index is held just above where it sits because
# every line in it is read by every session. A skill is opened by the task that
# needs it, so what a tight cap here buys is not a cheaper session -- it is a
# push towards `references/`, which has no budget at all. Pushed too hard it
# moves the wrong things: at 200 this check refused the `|| true` rule going
# back into `document-supaline`, where its own three questions say an
# instruction belongs. So it sits far enough above the files that the next rule
# is a judgement rather than a forced relocation, and near enough that a file
# drifting towards the specification's 500 still has to answer for it.
SKILL_LIMIT = 250

NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
# A heading under the title, at any level. The title itself is not one:
# it would leave every file with an empty opening section.
SUBHEADING = re.compile(r"#{2,6} ")
RESERVED = ("anthropic", "claude")

# A Contents entry names its section and may gloss it after one of these.
# Both spellings are in the prose here already, so a heading written with one
# of them is not a heading that cannot be listed: the entry is matched against
# the headings first, longest one wins, and this is only where that fails.
GLOSSES = (" — ", " -- ")

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
    "Field 'description'": (
        "Any scalar style is read -- a block, or one line, quoted or not.",
    ),
}

problems = []


def report(where, what, *notes):
    """Say what is wrong, then what to write instead. Never just the first."""
    print(f"{where}: {what}")
    for note in notes:
        print(f"  {note}")
    problems.append(where)


def rel(path):
    return path.relative_to(ROOT)


def read(path):
    """The file's text, or None once the reason it has none is reported."""
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, ValueError) as e:
        # A dangling symlink, a directory wearing the name, a byte that is not
        # UTF-8. Each of these used to be a traceback, which says the same
        # thing in a form nobody can act on.
        #
        # `strerror` rather than the exception: an OSError prints the absolute
        # path it was given, and every other line this script writes names a
        # file the way the repository does. A decode error has no `strerror`
        # and names no path of its own.
        reason = getattr(e, "strerror", None) or e
        report(rel(path), "cannot be read.", f"    {reason}")
        return None


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
    """The lines under `## Contents`, to the next heading outside a fence.

    A fenced line is not one of them, for the reason a fenced `## ` is not a
    heading: a `- ` in an example block is an example. `headings` skipped
    fences and this did not, so a list quoted under Contents was counted as
    entries against sections it was never describing.
    """
    out, fence, seen = [], False, False
    for line in lines:
        if line.startswith("```"):
            fence = not fence
        elif fence:
            continue
        elif line == "## Contents":
            seen = True
        elif line.startswith("## ") and seen:
            break
        elif seen:
            out.append(line)
    return out


def entry_name(entry, sections):
    """The section a Contents entry names, gloss removed.

    Matched against the headings first and longest one first, so a heading
    that carries a gloss separator of its own is still listable -- splitting
    at the first one would name half of it, and the entry would be refused
    from both sides at once with no spelling that satisfies either.
    """
    for section in sorted(sections, key=len, reverse=True):
        if entry == section or entry.startswith(
            tuple(section + gloss for gloss in GLOSSES)
        ):
            return section
    # Names no section here: cut at the first gloss, so what is reported is
    # the entry's own claim about its heading rather than the gloss with it.
    cut = min(
        (entry.index(gloss) for gloss in GLOSSES if gloss in entry),
        default=len(entry),
    )
    return entry[:cut].strip()


def check_length(f, lines):
    count = len(lines)
    if count >= FILE_LIMIT:
        report(
            rel(f),
            f"is {count} lines, at or over the {FILE_LIMIT}-line budget.",
            "Move what a reader does not need every time into references/.",
        )


def check_skill(directory):
    # Read off the directory rather than asking whether the path exists: a
    # case-insensitive filesystem answers yes to `SKILL.md` when the file on
    # disk is `skill.md`, so the same tree that passes on macOS fails on the
    # runner. Measured here, on APFS, by planting the lowercase one.
    names = {p.name for p in directory.iterdir()}
    if "SKILL.md" not in names:
        notes = []
        if "skill.md" in names:
            notes.append(
                "There is a skill.md here. `skills-ref` reads that spelling"
            )
            notes.append(
                "too; every skill in this tree spells it SKILL.md, and which"
            )
            notes.append("clients read the lowercase one is not measured here.")
        report(rel(directory), "no SKILL.md.", *notes)
        return

    f = directory / "SKILL.md"
    text = read(f)
    if text is None:
        return

    lines = text.splitlines()

    # Before the fences and before the library, because it is the one rule
    # that needs neither: a file is as long as it is however it parses.
    # `splitlines` rather than counting newlines: a file whose last line has
    # no newline is one line shorter by that arithmetic, and the only reason
    # nothing here shows it is that MD047 refuses such a file. A count that
    # leans on another linter's rule is a count that breaks when it moves.
    check_length(f, lines)
    check_budget(
        f,
        lines,
        SKILL_SECTION_LIMIT,
        SKILL_LIMIT,
        (
            "A section this long is carrying its own evidence. Move that to a",
            "references/ file, or split it where a reader would stop reading",
            "and go and do the thing.",
        ),
        (
            "This is the file a task loads whole, so every line in it is paid",
            "for by readers who needed one other line. What is read once goes",
            "in references/, which is opened on purpose.",
        ),
    )

    if not lines or lines[0] != "---":
        report(
            rel(f),
            "does not open with a --- frontmatter fence.",
            "A client reads no skill here, and nothing below can be measured.",
        )
        return

    fm_end = next(
        (n for n, line in enumerate(lines[1:], 2) if line == "---"), 0
    )
    if not fm_end:
        report(
            rel(f),
            "the frontmatter never closes.",
            "Add the closing ---. Without it a client reads no skill here, and",
            "nothing below can be measured.",
        )
        return

    cut = next(
        (
            (n, line)
            for n, line in enumerate(lines[1 : fm_end - 1], 2)
            if "---" in line
        ),
        None,
    )
    if cut:
        n, line = cut
        report(
            f"{rel(f)}:{n}",
            "a literal --- inside the frontmatter.",
            f"    {line.strip()}",
            "A client cuts the frontmatter at the first --- after the opening",
            "fence, so everything from here on is dropped: the description in",
            "the listing ends at this point, and a field below it is not read",
            "at all. Name a class or a field annotation rather than spelling",
            "one. The frontmatter rules are withheld until it is gone, because",
            "past it the library is measuring something else.",
        )
        return

    for error in validate(directory):
        headline, *rest = error.splitlines()
        notes = list(rest)
        for prefix, note in LIBRARY_NOTES.items():
            if headline.startswith(prefix):
                notes.extend(note)
        report(rel(f), headline, *notes)

    try:
        name = read_properties(directory).name
    except SkillError:
        return  # `validate` above has already said why.

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


def check_reference(f):
    text = read(f)
    if text is None:
        return
    lines = text.splitlines()
    count = len(lines)
    if count <= CONTENTS_LIMIT:
        return

    heads = headings(lines)
    if "Contents" not in heads:
        report(
            rel(f),
            f"{count} lines and no '## Contents' heading.",
            "List the sections at the top, so a partial read still shows what",
            "the file covers.",
        )
        return

    sections = [h for h in heads if h != "Contents"]
    # The entry names the section; anything after a gloss separator describes
    # it. Named rather than contained: a section renamed to a prefix of its
    # own entry is a rename the count cannot see and a substring test reads as
    # present.
    listed = [
        entry_name(line[2:].strip(), sections)
        for line in contents_block(lines)
        if line.startswith("- ")
    ]
    if listed == sections:
        return

    if len(listed) != len(sections):
        report(
            rel(f), f"Contents lists {len(listed)} of {len(sections)} sections."
        )
    for name in dict.fromkeys(listed):
        if listed.count(name) > 1:
            report(
                rel(f),
                f"in Contents {listed.count(name)} times: {name}",
                "One entry per section. Two entries naming one heading make",
                "the count above come out right while a section goes unnamed,",
                "so the line that would have found it never prints.",
            )
    for heading in sections:
        if heading not in listed:
            report(
                rel(f),
                f"not in Contents: {heading}",
                "A renamed section keeps the count and loses its entry, so the",
                "count above says nothing about it.",
            )
    for entry in listed:
        if entry not in sections:
            report(
                rel(f),
                f"in Contents, but no section has that heading: {entry}",
                "An entry names its section exactly, and may gloss it after an",
                "em dash or a double hyphen -- including a heading that",
                "carries one, which is matched whole before any gloss is cut.",
                "Rename the entry, or the heading.",
            )
    if sorted(listed) == sorted(sections):
        report(
            rel(f),
            "Contents lists every section, in a different order than the file.",
            "Put the entries in the order the sections come in.",
        )


def prose_sections(lines):
    """`[(heading, lines outside a fence)]`, the opening section first.

    The opening one is everything before the first heading under the title,
    and its heading is None. Fenced lines are not counted: the command list
    and the two snippets in `AGENTS.md` are the index doing its job, and a
    fence is not where a paragraph gets hidden. Prose is what swelled.

    Frontmatter is not counted either. A description is what the
    specification asks for, it is capped on its own, and there is nowhere to
    move it to: charging a budget for it would be asking for the one thing
    that cannot be paid.

    Any heading from `##` down ends a section, not just `##`. A `###` under a
    long section is the handhold the budget is asking for, so it has to count
    as one -- and a budget that saw only `##` would be answered by promoting
    every subheading, which is the same file with a flatter contents list.
    """
    if lines and lines[0] == "---" and "---" in lines[1:]:
        lines = lines[lines.index("---", 1) + 1 :]

    out, fence, heading, count = [], False, None, 0
    for line in lines:
        if line.startswith("```"):
            fence = not fence
        elif fence:
            continue
        elif SUBHEADING.match(line):
            out.append((heading, count))
            heading, count = line.rstrip(), 0
        else:
            count += 1
    out.append((heading, count))
    return out


def check_budget(f, lines, section_limit, file_limit, per_section, per_file):
    """Every section over its budget, and then the file over its own."""
    sections = prose_sections(lines)

    for heading, count in sections:
        if count <= section_limit:
            continue
        where = f"`{heading}`" if heading else "the opening"
        report(
            rel(f),
            f"{where} is {count} lines, over the {section_limit}-line budget.",
            *per_section,
        )

    total = sum(count for _, count in sections)
    if total > file_limit:
        report(
            rel(f),
            f"is {total} lines, over the {file_limit}-line budget.",
            *per_file,
        )


def check_index():
    text = read(INDEX)
    if text is None:
        return
    check_budget(
        INDEX,
        text.splitlines(),
        INDEX_SECTION_LIMIT,
        INDEX_LIMIT,
        (
            "The index says what applies to every session and points at the",
            "skill that carries the rest. Move the detail into that skill, or",
            "the evidence into a references/ file beside it.",
        ),
        (
            "Sections that each stay inside their own budget still add up,",
            "which is how this file grew before. Move one of them out.",
        ),
    )


def main():
    # `*/` in the shell this replaced skipped a dotted directory, and
    # `Path.glob` does not. A personal scratch directory under here is not
    # this check's business -- `AGENTS.md` says the linters see what Git
    # tracks -- and the step below that walks `.agents/skills/*/` would
    # disagree about what a skill is.
    directories = sorted(
        p for p in SKILLS.glob("*") if p.is_dir() and not p.name.startswith(".")
    )
    if not directories:
        report(f"{rel(SKILLS)}/", "no skill found. Has the tree moved?")
    # The references are walked from that same list rather than from a glob of
    # their own, so the filter above is the only one there is. Two globs meant
    # two chances to forget it, and the second one had: a notes file under a
    # personal `.scratch` was read as a skill's reference.
    for directory in directories:
        check_skill(directory)
        for reference in sorted((directory / "references").glob("*.md")):
            check_reference(reference)
    check_index()
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
