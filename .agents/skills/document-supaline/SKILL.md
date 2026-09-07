---
name: document-supaline
description: >-
  How this repository's instruction documents are written, and where a rule
  has to live to reach the agent it is for. Read before changing `AGENTS.md`,
  a skill under `.agents/skills/`, or a rule under `.claude/rules/` -- not for
  `README.md` or `test/MANUAL.md`, which are written for people, and not for
  comments inside Lua. Covers why a check is worth more than a paragraph, who
  reads which file, what a description owes a reader who has not opened the
  skill, the three questions that decide whether a paragraph belongs in a
  skill or in a reference file beside it, the standard a claim about the
  platform has to meet, and the places one change has to land in step.
  Markdown style is markdownlint's business and is not in here.
---

# Writing the instruction documents

The reader is an agent starting cold: no memory of the last session, no idea
which of the things it is about to try has already been tried and rejected.
Everything below follows from that.

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

When it is checkable, three places take it. Try them in this order; the first
that fits is the cheapest one that works.

1. **A `grep` over the tracked files**, as a step in
   `.github/workflows/check.yml` — for a rule about what the source *says*: a
   forbidden name, a required annotation, where a call has to sit.
2. **A spec under `test/`** — for a rule about what this repository's own code
   *does* with a given input.
3. **A stub that raises** — for a rule about what Yazi accepts, including the
   ones Yazi itself accepts silently.

A check that only says no is half-written. Print the spelling to use and the
reason, because the right one is not guessable from the wrong one; otherwise
the reader goes straight back to a paragraph and you have written both.

Know what a check cannot do before you trust one. A test runs over the code
that exists, so it pins that code and nothing else — code written tomorrow can
repeat the same mistake and keep the suite green. A fresh column written with
`not is_regular` passed all 103 tests before the spelling check existed. A rule
that has to hold for code nobody has written yet needs a check over the source,
which is why some of them are greps rather than tests.

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
the whole of it: question one is about which skill, and asking it second is how
the mechanism behind a type collision ends up filling half the skill for the
test harness.

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

`Skills stay inside the progressive-disclosure budget` checks the half that can
be counted — a body under 500 lines, a `## Contents` on any reference over 100.
Passing it means nothing about the three questions above; every skill here is
well inside both numbers, and always was.

## What a description owes a reader who has not opened it

The description is the only part read before the file is. It does three jobs,
and the second is the one that gets left out:

1. When to read it — the kinds of change, not the subject matter.
2. **When not to.** `yazi-platform-traps` says "not for every edit to plugin
   Lua, and not for a rename or a format string"; without that line it loads on
   every Lua edit and stops meaning anything.
3. What is inside, in enough detail that a reader can decide against opening
   it. Deciding against is the point, not a failure.

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

- Name the version and the method: measured on 26.9.1, in a detached tmux,
  with a probe plugin and `ya.dbg`.
- Say where the measurement stops instead of rounding it off. `is_virtual =
  true` was never observed, and the skill says so rather than implying a run
  that did not happen.
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

- the Traps list in `AGENTS.md`, and the counts around it — spelled as words,
  so `grep -rn 'nine\|six of' --include='*.md'` is how you find them
- the traps skill: its description, its body, and both files under
  `references/` — `checked-traps.md`, where a trap goes once a check catches
  it, and `probes.md`, which holds the evidence for the ones no check catches
- the check itself, and the sentence naming which check prints what

Nothing counts these for you. `.claude/rules/lua.md` said "the other five" for
the whole life of the ninth trap, because the commit that made it nine updated
`AGENTS.md` and the skill and not the rule; it was found by reading, which is
the only thing that finds it.

A new skill has one more step that is easy to miss: `.claude/skills/<name>`
must be a symlink to `../../.agents/skills/<name>`, tracked like the two
already there. Claude Code looks under `.claude/skills`; the skill itself lives
under `.agents/`, where every agent can reach it.
