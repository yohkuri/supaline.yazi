# AGENTS.md

Canonical instructions for AI agents working in this repository. Claude Code
reads this file through `CLAUDE.md`; other agents read it directly. Keep it the
single source of truth — do not copy rules into agent-specific files.

This file is the index, not the manual. What is here applies to every session.
The detail lives in four skills under `.agents/skills/`, read when the task
calls for them:

- `yazi-platform-traps` — for a change that resolves a colour, writes a
  fetcher, or touches the parent- or preview-pane child
- `annotate-supaline` — for a change that declares or edits a type annotation
  in the plugin's own Lua
- `verify-supaline` — for a change under `test/`
- `document-supaline` — for a change to this file, to a skill, or to a rule
  under `.claude/rules/`

## What this is

supaline is a [Yazi](https://github.com/sxyazi/yazi) plugin that replaces the
linemode with a configurable set of columns: sizes and timestamps coloured flat
or on a gradient, between endpoints the user chooses or across the band one
colour is spread into. Built-in columns and user-written ones go through the
same interface; neither has a privileged path.

Do not call that gradient eza's. eza was read at v0.23.5 and it does something
else: it replaces the Oklab **lightness** of a colour it takes from the file's
magnitude class, on a ratio that is linear in bytes, and has no endpoints to
interpolate between at all. Its `--color-scale-mode=fixed` is not the
absolute-scale mode the name suggests either -- it draws every size in one
colour. What supaline does take from it is the shape of the idea and the
extremes of the listing, which is what `builtin.lua` says and all it says.

The band is not eza's either, and is the likelier of the two to be mistaken
for it, since both start from one colour. eza moves the lightness and holds
the other two Oklab axes, which runs a saturated colour out of gamut in both
directions and turns its hue at the clamp. supaline holds the hue instead and
spends whatever it has to in order to keep it -- scaling all three axes
together while the display allows, and giving up chroma rather than hue once
it does not. `colour.lua`'s `M.band` carries the measurements for both.

Both ends of that band are **fixed lightnesses**, not derived from the colour.
The colour supplies the hue and nothing else, so it need not appear in the band
it names -- black and white give the identical grey band, and neither is
refused. Say so wherever the band is described: "spread a colour both ways"
reads as though the written colour were an endpoint, which it is not.

Where those two lightnesses come from is a **name**. `band` in `setup` holds
bands by name; a `<->` takes the band called after the key it was written
under, `fg` or `bg`, or names another after the marker. **No name has a
default and none is built in**, so a `<->` with no band behind it is refused
rather than drawn. `colour.lua` carries a pair it recommends and every refusal
quotes it, which is not the same thing: the two ends are a claim about the
ground the column is drawn on, that ground is the reader's, and a pair applied
to whoever said nothing would be a guess that draws rather than a question that
asks. Do not describe the recommended pair as a default, in this file or
anywhere else.

Whether supaline ships status columns of its own — version control, dotfile
management — is **undecided**. Do not describe them as planned or forthcoming,
and do not justify a design choice by pointing at one; if such a column has to
come up at all, say plainly that it is hypothetical.

## Source of truth

Prefer code, tests, Git history, and actual tool output over documentation when
they conflict — this file included. Every platform claim below was measured on
26.9.1, on one machine; where a measurement could only be taken so far, the
skill says where it stops. The Yazi in front of you is still what decides.
When a document turns out to be wrong, fix the document rather than working
around it.

## Language

This repository is private for now and will be made public once it is ready.
**Everything tracked in Git is written in English** — code comments,
documentation, README, user-facing error messages, and commit messages. This
includes files only agents read. The rule holds from the first commit rather
than from the day the repository opens, because the history is published along
with the tree.

Commit messages follow the Conventional Commits specification. Do not
capitalise the first letter of the subject, and keep emoji out: none at all in
the header, and no Gitmoji shortcode anywhere in the message.

The header — the whole first line — must be 72 characters or fewer, and that
limit is hard. A subject of 50 characters or fewer is preferred; going over is
a warning rather than a refusal, because a style point is not worth rewriting
published history for.

`.commitlintrc.yml` holds the Conventional Commits rules and CI runs
`commitlint` over a pull request's commits. The ASCII and Gitmoji tests are a
step beside it in `.github/workflows/check.yml`; the ASCII one covers the
header alone, so a body may quote a CJK string and a name in a trailer is
spelled the way its owner spells it. To run the same check here:

```sh
npx -p @commitlint/cli@21 -p @commitlint/config-conventional@21 \
  commitlint --from origin/main --to HEAD
```

## Landing a change

Work reaches `main` through a pull request. `Commit messages` in
`.github/workflows/check.yml` — commitlint, the ASCII header, the Gitmoji
test — runs on a pull request and nowhere else, deliberately: a pull request
is the last point at which a message can still be rewritten. A commit that
reaches main any other way is one nothing read.

Three checks hold that up, so it is not this paragraph that enforces it.
`.githooks/pre-commit` refuses a commit made on main, which is how the mistake
is usually made; `.githooks/pre-push` refuses a push that would move main at
all, which is the one thing a merge, a cherry-pick, a revert and a rebase have
to pass as well. `.git/hooks` is not tracked, so install both per clone —
these two lines work from a linked worktree as well as from the clone itself,
where `ln -sf ../../.githooks/...` does not:

```sh
common=$(git rev-parse --path-format=absolute --git-common-dir)
ln -sf "${common%/.git}/.githooks"/* "$common/hooks/"
```

A clone that installed neither meets `Commits on main came from a pull
request` instead, after the fact rather than before it. It reads every commit
a push carries, merge commits included, and asks GitHub three things: that the
pull request the commit came from was **merged** — an open one reports the
association too, so a branch pushed straight to main while its own pull
request sat open would otherwise pass — that it targeted main, and that
`Commit messages` concluded `success` on its head. An API that does not answer
is reported as itself rather than as a violation.

What none of the three can do is refuse the push at the server. Branch
protection would, and neither it nor the ruleset that replaced it is available
while this repository is private: the API answers `Upgrade to GitHub Pro or
make this repository public` to both (measured 2026-09-08). Turn one on when
the repository opens, and keep these three as the half that runs before a push
rather than after it.

Who merges it is a separate question, and the answer is not the agent that
wrote it. An agent's work ends with the pull request open and its checks
reported; whether to merge it, and what to do next, is the maintainer's. The
reason is the one the first paragraph gives — a pull request is the last point
at which anything gets read — and an agent that merges its own has removed the
only reading the change was going to get. The work inside the review needs no
asking for: another commit on the branch, a correction to one already there,
what CI came back with. It is landing the change, and moving on to the next
one, that waits to be asked for.

Nothing local refuses that merge the way `pre-push` refuses a push, because it
happens at GitHub rather than in the clone. What stands in for it is
`.claude/settings.json`, which lists `gh pr merge` under `permissions.ask`, and
`gh api` narrowed to the calls naming a merge, which is the same request
spelled another way. Rules are evaluated deny, then ask, then allow, so an
`ask` entry stops a call an allow rule covers outright — measured here on
2026-09-13, by a `claude -p` session that allowed `Bash(gh pr merge *)` on the
command line and was refused anyway, against a control in the same shape that
allowed a `gh` subcommand the rule does not name and ran it. That it also
prompts inside a `&&` chain, and under a mode that otherwise stops prompting,
is read from Claude Code's permissions documentation and not measured. What it
is not is a boundary: a Bash rule matches the text of the command, so the same
call made from a script or through an absolute path goes past it, and no rule in
that file reaches an agent that is not Claude Code. It stops the spelling the
mistake is actually made in, which is all `pre-commit` does either. The ruleset
above is the one thing that would refuse the merge for everyone; require a
review on it too, on the day it becomes available.

## Target platform

Yazi **26.9.1 or newer**. Start every Lua file with `--- @since 26.9.1` —
Yazi enforces the annotation, and an older Yazi refuses to load the plugin
outright.

Yazi is on CalVer and breaks the plugin API freely between releases, and not
always in the changelog: recent ones changed the fetcher calling convention,
renamed a DDS event silently, and moved when the user's theme is merged. Code
written for 26.5.6 — let alone 0.4.x — will not run. Only one version is ever
supported at a time, because supporting two means writing to whichever behaves
more strictly and saying in every document which one a sentence is about.

## Traps

Eleven behaviours of Yazi break this plugin **silently** — no error, just an
empty column, a stale colour, or a task that never finishes. Knowing that they
exist is what this list is for, and for most changes it is the whole of what you
need; the mechanism behind each, and the experiment that established it, is in
`.agents/skills/yazi-platform-traps/`.

- `app:theme` re-reads `theme.toml` mid-run — a colour resolved once and
  cached goes stale, and nothing says so. The first `theme` event bites as
  well: `theme.toml` is merged before any plugin code runs, the flavor only a
  few milliseconds later, so a field the flavor supplies still holds Yazi's
  preset while `init.lua` runs
- `ya.sync` binds by the position of the call, per file — one written elsewhere
  reads a different state table
- a fetcher returns a function, not a boolean — the error reaches only the task
  log, and the column still fills in
- a linemode child is called for parent-pane rows too — `solo()` guards
  `in_current`, a child does not
- `in_preview` is not the counterpart of `in_current` — it holds for one row of
  the preview pane, not for all of them
- DDS renamed `bulk` to `bulk-rename` — a stale kind is a subscription that
  never fires
- every module must return a table — `return true` stops the plugin loading at
  all
- `is_regular` is one of six `AuthKind` variants, not "a real file" — a check
  written as `not is_regular` demotes every search hit along with the remote
  ones
- both truncations count characters where the screen counts clusters — three
  cells of `❤️abc` come back as four, and a Line cut without an ellipsis is a
  cell shorter than the same string
- an attribute method on `ui.Style` takes a removal flag rather than the value
  — `bold()` and `bold(false)` both add the attribute and only `bold(true)`
  takes it off, so a theme's `bold = false` copied into a call arrives as a
  second `true`
- an error raised under a linemode's render fails the whole `Root` component
  rather than the row — the file list, the header and the status bar all stop
  drawing, on every frame, and nothing is written to the log unless `YAZI_LOG`
  was set before Yazi started

**Seven of the eleven are refused by a check**, which prints what to write
instead: `ya.sync` placement in CI, the names `in_preview` and `is_regular`
by the `Forbidden spellings` job, an unpublished DDS kind by the stub, a
module returning a boolean by `test/module_spec.lua`, a cut that counts
characters by `truncate_spec.lua` and `column_spec.lua`, and an attribute
given the value rather than the removal flag by `colour_spec.lua`. Nobody has
to read about those.

The other four are why the skill exists, because a green suite says nothing
about them. The parent-pane child is pinned against the code already here, so
**new** code can repeat it and stay green — measured, not assumed: a fresh
column written with `not is_regular` passed the whole suite before
`Forbidden spellings` existed. The fetcher has no pin at all, because there is
no fetcher yet. The last of the four is the same shape as the first: the four
calls supaline makes into a column's own code are contained and pinned, but a
**new** call into it is not, and the suite goes on passing either way.

## Commands

```sh
lua test/run.lua                  # unit tests, over the plugin
lua test/run.lua column           # ... just the specs matching "column"
test/e2e.py                       # render in a real Yazi, headless
test/manual.py                    # ... interactively, for a human to look at
stylua --check .                  # Lua formatting
lua-language-server --check .     # Lua types
npx --yes markdownlint-cli2@0.19  # Markdown
uv run .github/scripts/skills.py  # Agent Skills

python3 -m unittest discover -s test -p 'test_*.py'  # the screen parsers

uvx ruff@0.16.7 check test .github/scripts           # the Python lint
uvx ruff@0.16.7 format --check test .github/scripts  # ... and its shape
```

The unit suite runs on **Lua 5.5**, the version Yazi embeds, and `test/run.lua`
refuses any other. Any 5.5 does: `mise.toml` pins 5.5.1 for whoever uses mise,
and CI installs its own — nothing here requires a version manager.

There is a second unit suite, in Python, and it is not about the plugin at all.
`test/screen.py` reads a `tmux capture-pane`: which pane a row belongs to,
which step of a ramp a cell drew in, how wide a background band came out.
`test/test_screen.py` puts captures written by hand through it. Those two are
pure — no process, no file, no clock — which is why both are in CI while
`e2e.py` around them is not. **Python 3.11 or newer**, nothing outside the
standard library, and `harness.py` refuses an older one with a sentence rather
than a traceback, the way `test/run.lua` refuses the wrong Lua.

`lua-language-server --check .` type-checks the plugin against Yazi's own
annotations, which `.luarc.json` expects at
`~/.config/yazi/plugins/types.yazi/`; `ya pkg add yazi-rs/plugins:types`
installs them. Without that directory the check still runs and still finds
nothing — it has quietly stopped comparing the plugin against anything but
this repository. CI fetches a pinned revision of them in a step of its own, so
that not getting them fails the job rather than weakening it.

What the check reaches is what carries a type, and that is most of the plugin:
Yazi's own `cx`, `ya` and `Url`, the two values a `render` is handed, the
records passed around, and the configuration `setup` is given — so
`cfg.orderr`, `opts.linemodess` and `spec.separatorr` are refused. Where that
reach stops, and the rules for declaring a class of this plugin's own, are in
`annotate-supaline`.

`.github/scripts/skills.py` reads the skills under `.agents/skills` against the
Agent Skills specification. `uv run` is the whole of what it needs and not a
detail: the `skills-ref` pin sits in that script's own header, `skills.py.lock`
beside it pins what that header cannot reach, uv reads both, and CI runs the
same line — so no version here is named twice. `mise.toml` pins uv for whoever
uses mise, as it does Lua; CI installs its own. The specification's half of the
check is that library, the one the specification points at for this; the rest
is this repository's, and the script says which is which beside each rule.

`uvx ruff@0.16.7` lints every Python file here and checks its shape, under the
rules and the 80-column wrap `ruff.toml` sets. The pin sits on the command
rather than in `ruff.toml` because ruff is a tool this repository runs, not
something any of those files imports. It is given two paths rather than the
tree the other linters get: `ruff format` reformats the Python inside a fenced
block, and the documents are markdownlint's.

`test/e2e.py` and `test/manual.py` need a real Yazi and a real terminal and are
deliberately not in CI. Run them yourself before claiming anything about the
screen — and note that a green exit is worth more than the screen looking
right, because a broken fetcher shows up nowhere on it.

Running them needs nothing else — no lock file, no virtual environment, no uv.
`.agents/skills/verify-supaline/SKILL.md` is for **changing** the harness —
writing a spec, adding a stub, or editing one of the Python harnesses — and
says what a stub owes Yazi in fidelity, what the unit suite can and cannot
prove, where the fixture lives now, and how a headless run differs from a
terminal.

## Formatting

`stylua.toml` and `.luarc.json` are copied verbatim from
[yazi-rs/plugins](https://github.com/yazi-rs/plugins). Keep them that way.
`ruff.toml` is the exception beside them: nothing upstream exists to copy for
Python, so that one is this repository's own and every line in it is a
decision it states.

`.lua` files are tab-indented: `indent_width = 2` is a tab's assumed display
width when measuring against `column_width`, not two spaces. Markdown code
blocks are the exception — keep documentation snippets on spaces, because a tab
inside a fenced block renders at the viewer's tab width, 8 by default on
GitHub, which makes a nested example look absurd. `MD010` covers that one, tabs
inside fences included.

Markdown is `markdownlint-cli2`, configured in `.markdownlint-cli2.yaml`, which
says why each rule it turns off is off. It holds prose to the 80-column wrap
these documents already keep, and exempts what cannot be wrapped: a table cell,
and a fenced block quoting Yazi's source or its output verbatim. Table
alignment is not checked at all, because `test/MANUAL.md` pads its tables to
the width the screen draws Japanese at and the rule measures characters.

Both linters see only what Git tracks. A personal file is out of scope
wherever a contributor keeps one.
