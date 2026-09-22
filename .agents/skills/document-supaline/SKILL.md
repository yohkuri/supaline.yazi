---
name: document-supaline
description: >-
  How this repository's instruction documents are written, and where a rule
  has to live to reach the agent it is for. Read before changing `AGENTS.md`,
  a skill under `.agents/skills/`, or a rule under `.claude/rules/` -- not for
  `README.md` or `test/MANUAL.md`, which are written for people, and not for
  Lua comments. Covers why a check is worth more than a paragraph and has to
  be seen failing before it is believed, who reads which file, the two
  questions that route a rule into `AGENTS.md` and the budgets that hold it
  and every skill to a length, where a check's reason goes once the check
  exists, what a description owes a reader who has not opened the
  skill and the specification's limits on it, the three questions that route
  a paragraph to a skill or to a reference beside it, the standard a claim
  about the platform has to meet, and the places one change has to land in
  step. The evidence behind it is in references/behind-these-rules.md.
  Markdown style is markdownlint's business and is not in here.
---

# Writing the instruction documents

The reader is an agent starting cold: no memory of the last session, no idea
what has already been tried and rejected. It has `README.md` and `AGENTS.md`,
and nothing else — not this repository's history, not the sessions that
produced it, not another skill unless it was sent there.

One rule follows from that, about what a sentence here may lean on. Name a
check, a file or a command and the reader can go and look. Name an incident — a
commit, a pull request, a session that left no file behind — and it cannot, so
the sentence lands as an assertion it can neither check nor apply. Write the
shape of the mistake rather than the day it happened.

Style is not in here: `.markdownlint-cli2.yaml` holds it and CI runs it, so a
document that lints clean is finished as far as form goes.

## Try to make it a check first

Prose is what is left over once you have failed to make it a check. Before
writing a paragraph, spend the same effort trying to make the mistake refuse
itself.

**Whether it can be one is decidable, so decide it rather than guessing.** Can
you write down what a violation looks like — the wrong spelling and the right
one, or an input and the output it has to produce — without reading the
author's intent? If you can, a paragraph is the wrong form for it. If telling a
violation from a deliberate exception takes judgement about why the code is the
way it is, prose is the right one.

One rule here came out the other way, and `references/behind-these-rules.md`
has it, along with the hand sweep that does work and the check that looks
promising and is not. Read it before attempting a third.

### Where a check goes, and what it has to print

When it is checkable, three places take it. Try them in this order; the first
that fits is the cheapest that works.

1. **A step in `.github/workflows/check.yml`** over the tracked files — for a
   rule about what the source *says*: a forbidden name, a required annotation,
   where a call has to sit, a field that has to stay inside a limit.
2. **A spec under `test/`** — for a rule about what this repository's own code
   *does* with a given input.
3. **A stub that raises** — for a rule about what Yazi accepts, including the
   ones Yazi itself accepts silently.

A check that only says no is half-written. Print the spelling to use and the
reason: the right one is not guessable from the wrong one, and without it the
reader goes back to a paragraph and you have written both.

**And when you succeed, the reason goes beside the check.** It lives beside
the step, the spec or the stub, and the index gets a line only when the reader
has to know the rule *before* the check would tell them. If the check prints
the fix when it fires, the index owes its existence and not its mechanism. Do
not write the paragraph as well: a second wording cannot see the first, and the
two drift apart without either looking wrong.

### Before you trust one

**Watch it fail.** A check is finished when you have seen it refuse something:
plant the violation it is for, run it, read what it prints, and take the plant
back out. Until you have, what you have is something that exits 0, which is
what a working check and a broken one have in common. Reading it back is not
the same test — it was written to look correct, and it does.

A step in `check.yml` needs that more than the other two do, because `run:` is
`bash -e` and a step's exit status says less than it looks like it does:

- A pipeline's status is its last command's, so a `find` or a `grep` that fails
  before a `sort` still leaves the step exiting 0 over an empty result.
- `grep -c` exits 1 when it matches nothing, which aborts the step *mid-way*:
  the checks written after it never run, and nothing in the log says it stopped
  early rather than finished. Write `|| true`.

A rule that has to hold for code nobody has written yet is a grep over the
source rather than a test, because a test pins the code that exists.
`references/behind-these-rules.md` has the case that made that one a rule.

## Where a rule belongs

| File | Who reads it | What belongs |
| ---- | ------------ | ------------ |
| `AGENTS.md` | every agent, every session | the rule, on a budget |
| `.agents/skills/*/SKILL.md` | an agent whose task the description matches | the detail for one kind of change |
| `.agents/skills/*/references/*.md` | opened from a skill, on purpose | what you want in hand when something fires |
| `.claude/rules/*.md` | Claude Code alone, scoped to a path | a pointer at a tracked document |
| `CLAUDE.md`, `AGENTS.override.md` | Claude Code, Codex | imports and nothing else |

One consequence is worth stating, since it is not visible from inside the file
you are editing: a rule that lives only under `.claude/rules/` reaches Claude
Code and no one else. Those files are pointers by design — path-scoped offers
that fire on the file rather than waiting to be asked for — and a pointer is
not a place to keep the only copy of a rule.

### What the index takes, and how long it may run

"What applies to every session" refuses nothing on its own. Ask both of these
instead:

1. Would a session that never touches this subject be wrong without it?
2. Does the reader have to know it **before** a check would tell them?

A no to either sends it to a skill, however every-session the subject sounds.
A yes to both keeps it here, and the budget is what says how long it may run.
`references/behind-these-rules.md` has what that criterion cost while it stood
alone.

`.github/scripts/skills.py` holds that budget, counting what is outside a
fenced block and outside the frontmatter: 30 lines for a section and 200 for
the file in `AGENTS.md`, 30 and 250 in every `SKILL.md`. A `###` under a long
section counts as a section, so the handhold a reader wants is the one the
budget accepts too. The two file numbers differ, and the script says why
beside each.

## What a skill carries

Three questions, in this order, for every paragraph of an instruction
document here — a skill, a reference, or `AGENTS.md`. The order is
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

The standard below is a rule against discarding a measurement, not one about
where to keep it: the claim belongs in the skill, the probe behind it does not.

None of this is visible while you are writing, so here is the tripwire: when a
section runs longer than the thing it tells you to do, it is carrying evidence.
That tripwire is the budget above, and it is a check in `AGENTS.md` and in
every `SKILL.md` alike.

### What sits beside it

A reference is opened from `SKILL.md`, and nothing opens from a reference. One
that points on to another gets previewed rather than read — `head` on the
second file — so what that one holds belongs in the first, or in a file
`SKILL.md` links itself.

`Skills, and the budget on the documents` refuses the countable half: the
frontmatter limits, the two budgets, and a reference over 100 lines whose
`## Contents` is incomplete. Passing it says nothing about the three questions.

## What a description owes a reader who has not opened it

The description is the only part read before the file is. It does three jobs,
and the second is the one that gets left out:

1. When to read it — the kinds of change, not the subject matter.
2. **When not to.** `yazi-platform-traps` says "not for every edit to plugin
   Lua"; without that line it loads on every Lua edit and means nothing.
3. What is inside, in enough detail that a reader can decide against opening
   it. Deciding against is the point, not a failure.

Write it in the third person, in the words an agent would use for the task. It
is matched against a request rather than read as prose: "Read when a change
resolves a colour" does that work, and "I can help with themes" none of it.

The limits are the specification's rather than a preference, and the step above
refuses all of them. What is worth knowing in advance is only what breaking the
1024-character cap costs: a strict client refuses the skill and a lenient one
truncates, taking job 2 first because it is written second. Treat it as
reachable rather than as headroom — `references/behind-these-rules.md` has how
close the descriptions here have come.

Keep a literal `---` out of the description, annotation names included: it
truncates the listing an agent sees, silently, at the first one.
`references/behind-these-rules.md` has what that cost and how it was measured.

## A claim about the platform names its evidence

A sentence about Yazi's behaviour is a measurement with a version on it rather
than a fact, for the reason `AGENTS.md`'s `Target platform` gives.

- Name the version and the method: measured on 26.9.1, in a detached tmux, by
  a throwaway plugin that printed the values into Yazi's debug log.
- Say where the measurement stops instead of rounding it off. A variant you
  never managed to produce is written down as never observed, rather than left
  out as though the run had covered it.
- A different Yazi is a reason to re-run the experiment, not to trust the
  sentence — and when you re-run it, write down what you ran.
- `AGENTS.md`'s `Source of truth` outranks every document including itself, so
  a document that turns out to be wrong is fixed rather than worked around.

## One change lands in several places

Adding, removing or moving a platform trap touches, at minimum:

- the Traps list in `AGENTS.md`, and the counts around it
- `.claude/rules/lua.md`, which carries the same arithmetic in its own words
- the traps skill: its description, its body, and both files under
  `references/` — `checked-traps.md`, where a trap goes once a check catches
  it, and `probes.md`, which holds the evidence for the ones no check catches
- the check itself, and the sentence naming which check prints what

The counts are spelled as words, so a grep is the only way to sweep them:
`grep -rn 'eleven\|seven\|the four\|other four' --include='*.md'` reaches
every Markdown file that carries one today. Sweep with the counts written now
rather than with the ones this example was written for. Expect noise:
`test/MANUAL.md` counts cells, keys and terminal grounds in the same words. The
check itself is not Markdown and no grep here reaches it.

A new skill needs one more thing, invisible from inside it: under
`.claude/skills`, a tracked symlink for **every file in it** -- `SKILL.md` and
each `references/` file alike -- at the same path, pointing back into
`.agents/skills`. Claude Code reads `.claude/skills`; the skill itself lives
under `.agents/`, where every agent can reach it. One link per file and not one
per skill, because `ya pkg add` refuses a symlink to a directory and then
installs nothing at all, so adding a reference file is two steps rather than
one. `Every skill is reachable from .claude/skills` refuses a missing link and
prints the `ln -s` to run.
