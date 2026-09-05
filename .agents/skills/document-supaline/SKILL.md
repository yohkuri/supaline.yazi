---
name: document-supaline
description: >-
  How this repository's instruction documents are written, and where a rule
  has to live to reach the agent it is for. Read before changing `AGENTS.md`,
  a skill under `.agents/skills/`, or a rule under `.claude/rules/` -- not for
  `README.md` or `test/MANUAL.md`, which are written for people, and not for
  comments inside Lua. Covers why a check is worth more than a paragraph, who
  reads which file, what a description owes a reader who has not opened the
  skill, the standard a claim about the platform has to meet, and the places
  one change has to land in step. Markdown style is markdownlint's business
  and is not in here.
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

Six of the nine platform traps are refused by a CI step, a spec, or a stub that
fails loudly, and `AGENTS.md` tells the reader not to bother reading about
those. That is the shape to aim for: prose is what is left over once you have
failed to make it a check.

The refusal is the documentation. `Forbidden spellings` prints the spelling to
use and the reason, because the right one is not guessable from the wrong one;
a check that only says no sends the reader straight back to a paragraph, and
you have written both.

Know what a check cannot do before you trust one. A spec pins the code it was
written against, so **new** code can repeat a trap and keep the suite green —
a fresh column written with `not is_regular` passed all 103 tests before the
spelling check existed. Catching what is not written yet takes a check over the
source, not a test over the behaviour.

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

## What a description owes a reader who has not opened it

The description is the only part read before the file is. It does three jobs,
and the second is the one that gets left out:

1. When to read it — the kinds of change, not the subject matter.
2. **When not to.** `yazi-platform-traps` says "not for every edit to plugin
   Lua, and not for a rename or a format string"; without that line it loads on
   every Lua edit and stops meaning anything.
3. What is inside, in enough detail that a reader can decide against opening
   it. Deciding against is the point, not a failure.

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
- the traps skill: its description, its body, and
  `references/checked-traps.md`, which is where a trap goes once a check
  catches it
- the check itself, and the sentence naming which check prints what

Nothing counts these for you. `.claude/rules/lua.md` said "the other five" for
the whole life of the ninth trap, because the commit that made it nine updated
`AGENTS.md` and the skill and not the rule; it was found by reading, which is
the only thing that finds it.

A new skill has one more step that is easy to miss: `.claude/skills/<name>`
must be a symlink to `../../.agents/skills/<name>`, tracked like the two
already there. Claude Code looks under `.claude/skills`; the skill itself lives
under `.agents/`, where every agent can reach it.
