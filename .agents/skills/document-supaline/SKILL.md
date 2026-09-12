---
name: document-supaline
description: >-
  How this repository's instruction documents are written, and where a rule
  has to live to reach the agent it is for. Read before changing `AGENTS.md`,
  a skill under `.agents/skills/`, or a rule under `.claude/rules/` -- not for
  `README.md` or `test/MANUAL.md`, which are written for people, and not for
  comments inside Lua. Covers why a check is worth more than a paragraph and
  why one has to be seen failing before it is believed, who reads which file,
  what a description owes a reader who has not opened the skill and the
  specification's limits on it, the three questions that decide whether a
  paragraph belongs in a skill or in a reference file beside it, the standard
  a claim about the platform has to meet, and the places one change has to
  land in step.
  Markdown style is markdownlint's business and is not in here.
---

# Writing the instruction documents

The reader is an agent starting cold: no memory of the last session, no idea
which of the things it is about to try has already been tried and rejected.
It has `README.md` and `AGENTS.md`, and nothing else — not this repository's
history, not the sessions that produced it, not another skill unless it was
sent there.

Everything below follows from that, and so does one rule about what a
sentence here may lean on. Name a check, a file, a command or something
`AGENTS.md` already carries, and the reader can go and look. Name an incident
— a commit, a pull request, a session that left no file behind — and it
cannot, so the sentence lands as an assertion it can neither check nor apply.
Write the shape of the mistake rather than the day it happened.

Style is not in here. `.markdownlint-cli2.yaml` holds the wrap, the bullet, the
heading level and the fence language, and CI runs it — so a document that lints
clean is finished as far as form goes, and nothing in this skill will tell you
where to put a comma.

## Try to make it a check first

Prose is what is left over once you have failed to make it a check. Before
writing a paragraph, spend the same effort trying to make the mistake refuse
itself.

**Whether it can be one is decidable, so decide it rather than guessing.** Can
you write down what a violation looks like — the wrong spelling and the right
one, or an input and the output it has to produce — without reading the
author's intent? If you can, it is checkable, and a paragraph is the wrong form
for it. If telling a violation from a deliberate exception takes judgement
about why the code is the way it is, it is not, and prose is the right form.

One rule here came out the other way, and knowing which saves deciding it
twice. The paragraph this skill opens with — that the reader starts cold, so a
sentence may lean on a check, a file or a command but not on an incident — is
not checkable, and two attempts at making it one have been dropped.

Sweeping for it by hand works, and is worth doing before an audit: diff every
backticked identifier in `AGENTS.md` and `.claude/rules/` against what
`README.md` and `AGENTS.md` name, then match every "the X step / job / check"
phrase against the names in `check.yml`. Expect most hits of the first to be
legitimate — general shell, a path the reader can open, a term its own
sentence defines.

Turning the second into a check is what looks promising and is not. Nearly
every backticked capitalised phrase in tracked Markdown is already exactly a
name in `check.yml`, and the few that are not are quoted tool or API output,
so a convention telling those apart costs almost nothing. It buys almost
nothing either, because a marked name is not the mistake anyone makes. The one
that gets made is `the spelling check` for a job named `Forbidden spellings` —
and telling that from "a CI job that prints the fix", which correctly names
none, means knowing whether the phrase meant to name one. That is intent, and
intent is where the paragraph above says to stop.

When it is checkable, three places take it. Try them in this order; the first
that fits is the cheapest one that works.

1. **A step in `.github/workflows/check.yml`** over the tracked files — for a
   rule about what the source *says*: a forbidden name, a required
   annotation, where a call has to sit, a frontmatter field that has to stay
   inside a limit. A `grep` covers most of them; reach past one when the rule
   needs more, as two of the steps there already do. When a rule needs more
   than `bash -e` can hold — a real parse, or a library someone else
   maintains — it goes in a script under `.github/scripts/` that the step
   calls, as `skills.py` does; what stays in the YAML is the reason, not the
   logic.
2. **A spec under `test/`** — for a rule about what this repository's own code
   *does* with a given input.
3. **A stub that raises** — for a rule about what Yazi accepts, including the
   ones Yazi itself accepts silently.

A check that only says no is half-written. Print the spelling to use and the
reason, because the right one is not guessable from the wrong one; otherwise
the reader goes straight back to a paragraph and you have written both.

**Then watch it fail.** A check is finished when you have seen it refuse
something: plant the violation it is for, run it, read what it prints, and
take the plant back out. Until you have, what you have written is something
that exits 0, and that is what a working check and a broken one have in
common. Reading it back is not the same test — it was written to look
correct, and it does.

A step in `check.yml` needs this more than the other two places do, because
`run:` is `bash -e` and a step's exit status says less than it looks like it
does:

- A pipeline's status is its last command's, so a `find` or a `grep` that
  fails before a `sort` still leaves the step exiting 0 over an empty result.
- `grep -c` exits 1 when it matches nothing, which aborts the step *mid-way*:
  the checks written after it never run, and nothing in the log says it
  stopped early rather than finished. Write `|| true`.

Know what a check cannot do before you trust one. A test runs over the code
that exists, so it pins that code and nothing else — code written tomorrow can
repeat the same mistake and keep the suite green. That has happened here: one
of the traps `AGENTS.md` lists was repeated in a column written after the
suite, and the whole suite passed, which is why a check over the source
refuses that spelling now. A rule that has to hold for code nobody has written
yet needs one of those rather than a test, which is why some of them are
greps.

## Where a rule belongs

| File | Who reads it | What belongs |
| ---- | ------------ | ------------ |
| `AGENTS.md` | every agent, every session | what applies to every session |
| `.agents/skills/*/SKILL.md` | an agent whose task the description matches | the detail for one kind of change |
| `.agents/skills/*/references/*.md` | opened from a skill, on purpose | what you want in hand when something fires |
| `.claude/rules/*.md` | Claude Code alone, scoped to a path | a pointer at a tracked document |
| `CLAUDE.md`, `AGENTS.override.md` | Claude Code, Codex | imports and nothing else |

Two consequences worth stating, since neither is visible from inside the file
you are editing:

- A rule that lives only under `.claude/rules/` reaches Claude Code and no one
  else. Those files are pointers by design — path-scoped offers that fire on
  the file rather than waiting to be asked for — and a pointer is not a place
  to keep the only copy of a rule.
- `AGENTS.md` is the index. A paragraph that matters only for one kind of
  change belongs in a skill with a line in the index pointing at it; one that
  applies to every session belongs in `AGENTS.md` however long it runs. What it
  must never be is in both, in two wordings that can drift.

## What a skill carries, and what sits beside it

Three questions, in this order, for every paragraph of a skill. The order is
the whole of it: question one asks which skill a paragraph belongs to, and
asking it second is how a long mechanism ends up filling half of whichever
skill happened to run into it.

1. **Is this the subject the skill is read for?** If the change that needs it
   is a different kind of change, it belongs in that other skill, however few
   lines it runs to. `references/` is not where out-of-scope material goes.
2. **Does it change what the reader does?** Cut it and see whether any action
   changes. If none does, the rule stays and the evidence moves: the
   mechanism, the measurement, the version it was taken on, and whatever was
   tried and rejected all belong in `references/`.
3. **Does a check already refuse it?** Then the section above applies, and the
   prose is the leftover rather than the documentation.

The standard below — that a claim about the platform names its evidence — is a
rule against discarding a measurement, not a rule about where to keep it. The
claim belongs in the skill; the probe behind it usually does not.

None of this is visible while you are writing, so here is the tripwire: when a
section runs longer than the thing it tells you to do, it is carrying evidence.

A reference is opened from `SKILL.md`, and nothing opens from a reference. One
that points on to another gets previewed rather than read — `head` on the
second file, and the rest of it is never seen — so what the second one holds
belongs either in the first or in a file `SKILL.md` links itself.

`Skills match the Agent Skills specification` refuses the half that can be
counted: the frontmatter limits below, a body over 500 lines, and a reference
over 100 whose `## Contents` does not name every section it has. The
frontmatter is parsed rather than read a line at a time, so a duplicate key or
a field the specification does not define is refused as well. Passing it means
nothing about the three questions above — and every rule in it has been seen
refusing a planted violation, which is the only thing separating a check that
works from one that exits 0.

## What a description owes a reader who has not opened it

The description is the only part read before the file is. It does three jobs,
and the second is the one that gets left out:

1. When to read it — the kinds of change, not the subject matter.
2. **When not to.** `yazi-platform-traps` says "not for every edit to plugin
   Lua, and not for a rename or a format string"; without that line it loads on
   every Lua edit and stops meaning anything.
3. What is inside, in enough detail that a reader can decide against opening
   it. Deciding against is the point, not a failure.

Write it in the third person, in the words an agent would already be using for
the task. It is injected into the system prompt and matched against a request,
not read as prose: "Read when a change resolves a colour" does that work, and
"I can help with themes" does none of it.

The limits are the specification's, not a preference
(<https://agentskills.io/specification>, read 2026-09-08): `name` at most 64
characters of lowercase alphanumerics and single hyphens, equal to its own
directory; `description` non-empty and at most **1024 characters**. Past 1024 a
strict client refuses the skill outright and a lenient one truncates, which
costs job 2 first because it is written second. The cap is reachable: one
description here came within five characters of it before it was cut back. The
step named above refuses all of it.

Keep a literal `---` out of the description, annotation names included.
`annotate-supaline` first said it was read before changing a `---@class` or a
`---@field`; the listing an agent sees cut the text at the backtick before the
first of them, so job 1 survived truncated and jobs 2 and 3 were gone
altogether. Measured by loading the skill both ways and reading the listing
back. Say "a class or a field annotation" instead — a reader deciding whether
to open the file does not need the spelling.

## A claim about the platform names its evidence

Yazi is on CalVer and breaks the plugin API between releases, so a sentence
about its behaviour is a measurement with a date on it, not a fact.

- Name the version and the method: measured on 26.9.1, in a detached tmux, by
  a throwaway plugin that printed the values into Yazi's debug log.
- Say where the measurement stops instead of rounding it off. A variant you
  never managed to produce is written down as never observed, rather than left
  out as though the run had covered it.
- A different Yazi is a reason to re-run the experiment, not to trust the
  sentence — and when you re-run it, write down what you ran.
- What is undecided is written as undecided. Status columns of supaline's own
  are hypothetical; they are not "planned".
- `AGENTS.md` ranks code, tests, history and tool output above every document
  including itself. When one of them turns out to be wrong, **fix the
  document**. Working around it leaves the next reader the same wrong sentence
  and no way to tell.

## One change lands in several places

Adding, removing or moving a platform trap touches, at minimum:

- the Traps list in `AGENTS.md`, and the counts around it
- `.claude/rules/lua.md`, which carries the same arithmetic in its own words
- the traps skill: its description, its body, and both files under
  `references/` — `checked-traps.md`, where a trap goes once a check catches
  it, and `probes.md`, which holds the evidence for the ones no check catches
- the check itself, and the sentence naming which check prints what

The counts are spelled as words, so a grep is the only way to sweep them:
`grep -rn 'nine\|six of\|other six\|other three' --include='*.md'` reaches
every Markdown file that carries one today. Widen it before you trust it: a
narrower form of this same grep missed a file that had been carrying a stale
count since the day it went stale, and missed it for as long as the count was
wrong. The check itself is not Markdown and no grep here reaches it. Nothing
counts these for you.

A new skill needs one more thing, invisible from inside it:
`.claude/skills/<name>`, a tracked symlink to `../../.agents/skills/<name>`.
Claude Code reads `.claude/skills`; the skill itself lives under `.agents/`,
where every agent can reach it. `Every skill is reachable from .claude/skills`
refuses a missing one and prints the `ln -s` to run. It was this paragraph
until it was a check, which is the order the first section asks for.
