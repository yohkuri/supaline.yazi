# Behind these rules

What `SKILL.md` asserts, and what was run or tried to arrive at it. Open it
when a rule there looks arbitrary, when you are about to attempt a check it
says was attempted already, or when you want a worked case of the decision it
asks you to make.

## Contents

- A rule that came out the other way — the one paragraph decided as prose
- The sweep that works, and the check that does not
- How the index reached 381 lines
- A `---` in a description truncates the listing
- How close a description has come to the 1024-character cap
- What a test cannot pin, and why some rules are greps
- What made `.claude/skills` one link per file

## A rule that came out the other way — the one paragraph decided as prose

`SKILL.md` asks whether a rule can be a check, and says to decide rather than
guess. One rule here came out the other way, and knowing which saves deciding
it twice: the paragraph that skill opens with — that the reader starts cold, so
a sentence may lean on a check, a file or a command but not on an incident — is
not checkable. Two attempts at making it one have been dropped, and the second
is the instructive one.

## The sweep that works, and the check that does not

Sweeping for it by hand works, and is worth doing before an audit: diff every
backticked identifier in `AGENTS.md` and `.claude/rules/` against what
`README.md` and `AGENTS.md` name, then match every "the X step / job / check"
phrase against the names in `check.yml`. Expect most hits of the first to be
legitimate — general shell, a path the reader can open, a term its own sentence
defines.

Turning the second into a check is what looks promising and is not. Nearly
every backticked capitalised phrase in tracked Markdown is already exactly a
name in `check.yml`, and the few that are not are quoted tool or API output, so
a convention telling those apart costs almost nothing. It buys almost nothing
either, because a marked name is not the mistake anyone makes. The one that
gets made is `the spelling check` for a job named `Forbidden spellings` — and
telling that from "a CI job that prints the fix", which correctly names none,
means knowing whether the phrase meant to name one. That is intent, and intent
is where the rule says to stop.

## How the index reached 381 lines

The routing table's `AGENTS.md` row read "what applies to every session" for as
long as the file was growing, and on its own that criterion refuses nothing: CI,
git, the commands and the conventions all plausibly apply to every session, so
everything qualified and the file reached 381 lines. It is the same fault a
description has when it never says when *not* to read the skill. The two
questions in `SKILL.md` are what replaced it, and the budget is what replaced
"however long it runs", which was the other half of how this happened.

Measured from the history rather than by reading the file: six `ci:` commits
added 99 lines of it, 46% of its growth, every one of them explaining a job
whose own `run:` comment already said the same thing in different words. Only
two commits of the forty-four that touched the file ever made it shorter.

## A `---` in a description truncates the listing

Keep a literal `---` out of a description, annotation names included.
`annotate-supaline` first said it was read before changing a `---@class` or a
`---@field`; the listing an agent sees cut the text at the backtick before the
first of them, so the description's first job survived truncated and its other
two were gone altogether. Measured by loading the skill both ways and reading
the listing back. Say "a class or a field annotation" instead — a reader
deciding whether to open the file does not need the spelling.

## How close a description has come to the 1024-character cap

`SKILL.md` says to treat the cap as reachable. Two measurements say how
reachable: one description in this tree stands five characters under 1024, and
another reached 1083 and was refused by the step — which is also what says the
limit is enforced here rather than only written down. Both got there the same
way, while a pointer to a `references/` file was added to a description that
already said everything else it needed to. The cap is reached by the last
sentence, not by the first.

## What a test cannot pin, and why some rules are greps

A test runs over the code that exists, so it pins that code and nothing else —
code written tomorrow can repeat the same mistake and keep the suite green.
That has happened here: one of the traps `AGENTS.md` lists was repeated in a
column written after the suite, and the whole suite passed, which is why a
check over the source refuses that spelling now. A rule that has to hold for
code nobody has written yet needs one of those rather than a test.

## What made `.claude/skills` one link per file

`ya pkg add yohkuri/supaline` installed nothing at all while the entries under
`.claude/skills` were symlinks to directories. It walks the clone and stops at
the first one — `the source path is neither a regular file nor a symlink to a
regular file` — and deploys no plugin. The same tree with a symlink per file
deployed and said `Done!`.

Measured on ya 26.9.1 (Homebrew 2026-09-01), by pushing each spelling as `main`
in a throwaway bare repository, pointing the clone under
`~/.cache/yazi/packages` at it, and running the add against a
`YAZI_CONFIG_HOME` of its own. `ya pkg add` reuses that clone and resets it to
the branch named `main`, so a feature branch alone cannot be tested with. What
was never tried is a symlink pointing out of the repository, and what the
refusal costs is a check that has to name every file rather than every skill.
