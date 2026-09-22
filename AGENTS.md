# AGENTS.md

Canonical instructions for AI agents working in this repository. Claude Code
reads this file through `CLAUDE.md`; other agents read it directly. Keep it the
single source of truth — do not copy rules into agent-specific files.

This file is the index, not the manual. It carries the rule and not the
mechanism behind it: what applies to every session, and a pointer to whoever
holds the rest. The detail lives in five skills under `.agents/skills/`, read
when the task calls for them:

- `yazi-platform-traps` — for a change that resolves a colour, writes a
  fetcher, or touches the parent- or preview-pane child
- `annotate-supaline` — for a change that declares or edits a type annotation
  in the plugin's own Lua
- `verify-supaline` — for a change under `test/`
- `landing-a-change` — for when the route to `main` refuses something: a
  commit, a push or a merge turned down, or a red check about any of them
- `document-supaline` — for a change to this file, to a skill, or to a rule
  under `.claude/rules/`

The rest is a comment beside the check that enforces it. A budget in
`.github/scripts/skills.py` holds this file to that, along with the skills it
indexes: a section that outgrows it is carrying something one of them should
have.

## What this is

supaline is a [Yazi](https://github.com/sxyazi/yazi) plugin that replaces the
linemode with a configurable set of columns: sizes and timestamps, coloured
flat or on a gradient. Built-in columns and user-written ones go through the
same interface; neither has a privileged path.

Three things about it get described wrongly by default. `README.md` and
`colour.lua`'s `M.band` carry the reasoning; the rule is here.

- **Neither the gradient nor the band is eza's.** eza replaces a lightness and
  has no endpoints to interpolate between; supaline interpolates, and gives up
  chroma rather than turn the hue. What it takes from eza is the shape of the
  idea and the extremes of the listing.
- **A band's two ends are fixed lightnesses**, not derived from the colour —
  black and white give the identical grey band. "Spread a colour both ways"
  names an endpoint that does not exist.
- **No band name has a default and none is built in**, so a `<->` with no band
  behind it is refused rather than drawn. `style.lua` recommends a pair and
  every refusal quotes it; calling that a default is the mistake.

Whether supaline ships status columns of its own — version control, dotfile
management — is **undecided**. Not planned and not forthcoming; if one has to
come up at all, say plainly that it is hypothetical.

## Source of truth

Prefer code, tests, Git history, and actual tool output over documentation when
they conflict — this file included. Every platform claim here was measured on
26.9.1, on one machine, and the Yazi in front of you is still what decides.
When a document turns out to be wrong, fix the document rather than working
around it.

## Language

This repository is public, and **everything tracked in Git is written in
English** — code comments, documentation, README, user-facing error messages,
and commit messages. This includes files only agents read, and the history as
much as the tree.

Commit messages follow the Conventional Commits specification. Do not
capitalise the first letter of the subject, and keep emoji out: none at all in
the header, and no Gitmoji shortcode anywhere in the message. The header — the
whole first line — must be 72 characters or fewer, and that limit is hard. A
subject of 50 characters or fewer is preferred; going over is a warning rather
than a refusal, because a style point is not worth rewriting published history
for.

## Landing a change

Work reaches `main` through a pull request. A commit that reaches it any other
way is one **nothing read**, because `Commit messages` runs on a pull request
and nowhere else.

`.githooks/pre-commit` and `.githooks/pre-push` refuse the two spellings that
mistake is made in. `.git/hooks` is not tracked, so install both per clone —
these two lines work from a linked worktree as well as from the clone itself,
where `ln -sf ../../.githooks/...` does not:

```sh
common=$(git rev-parse --path-format=absolute --git-common-dir)
ln -sf "${common%/.git}/.githooks"/* "$common/hooks/"
```

A pull request lands by **rebase**, and `main` is a line with no merge commit
on it. Bring a branch up to date with `git fetch origin` and then
`git rebase origin/main`, force-pushed; merging main into the branch instead
takes the rebase away. What that costs is a branch **stacked** on the one that
lands: its commits get new hashes, so the child turns `CONFLICTING` the moment
the parent merges. Rebase the child onto main and force-push it, and find out
whether there is one before the merge — `gh pr list --base <branch>`.

**An agent's work on a change ends with the pull request open and its checks
reported.** Whether to merge it, and what to do next, is the maintainer's. The
work inside the review needs no asking for: another commit on the branch, a
correction to one already there, what CI came back with.

That is the whole route. Why each part of it is the way it is, and what none
of these checks can do, are in `landing-a-change`.

## Target platform

Yazi **26.9.1 or newer**. Start every Lua file with `--- @since 26.9.1` —
Yazi enforces the annotation, and an older Yazi refuses to load the plugin
outright.

Yazi is on CalVer and breaks the plugin API freely between releases, and not
always in the changelog. Code written for 26.5.6 — let alone 0.4.x — will not
run. Only one version is ever supported at a time, because supporting two
means writing to whichever behaves more strictly and saying in every document
which one a sentence is about.

## Traps

Eleven behaviours of Yazi break this plugin **silently** — no error, just an
empty column, a stale colour, or a task that never finishes. Seven are refused
by a test or a CI job that prints what to write instead, so nobody has to read
about those in advance; they are in
`.agents/skills/yazi-platform-traps/references/checked-traps.md`.

The other four are why the skill exists, because a green suite says nothing
about them:

- `app:theme` re-reads `theme.toml` mid-run, so a colour resolved once and
  cached goes stale. The first `theme` event bites too: the flavor lands a few
  milliseconds after `theme.toml`, so a field it supplies still holds Yazi's
  preset while `init.lua` runs
- a fetcher returns a function, not a boolean — the error reaches only the task
  log, and the column still fills in
- a linemode child is called for parent-pane rows too — `solo()` guards
  `in_current`, a child does not
- an error raised under a linemode's render fails the whole `Root` component
  rather than the row, so the file list, the header and the status bar stop
  drawing on every frame — and nothing reaches the log unless `YAZI_LOG` was
  set before Yazi started

## Layering

Yazi's globals belong to `main.lua`, which reads them and hands down what it
read, so a module under it takes a parameter where it would otherwise have
named one. `Yazi globals outside the adapter` refuses a module that names one,
prints what to take instead, and carries beside itself which global goes where
and why `builtin.lua` and `ui` are exempt. What it does not reach is an alias:
`local c = cx` and then `c.active` goes past it.

## Commands

```sh
lua test/run.lua                  # unit tests, over the plugin
lua test/run.lua column           # ... just the specs matching "column"
test/e2e.py                       # render in a real Yazi, headless
test/manual.py                    # ... interactively, for a human to look at
stylua --check .                  # Lua formatting
lua-language-server --check .     # Lua types
npx --yes markdownlint-cli2@0.19  # Markdown
uv run .github/scripts/skills.py  # Agent Skills, and this file's budget

python3 -m unittest discover -s test -p 'test_*.py'  # the screen parsers

uvx ruff@0.16.7 check test .github/scripts           # the Python lint
uvx ruff@0.16.7 format --check test .github/scripts  # ... and its shape

npx -p @commitlint/cli@21 -p @commitlint/config-conventional@21 \
  commitlint --from origin/main --to HEAD            # the commit messages
```

Each of those refuses a wrong version of itself, with one exception worth
knowing before you trust a green run: `lua-language-server --check .` compares
the plugin against Yazi's own annotations, which `.luarc.json` expects at
`~/.config/yazi/plugins/types.yazi/` and `ya pkg add yazi-rs/plugins:types`
installs. Without that directory the check still runs and still finds nothing,
having quietly stopped comparing the plugin against anything but this
repository.

`test/e2e.py` and `test/manual.py` need a real Yazi and a real terminal and are
deliberately not in CI. Run them yourself before claiming anything about the
screen — and a green exit is worth more than the screen looking right, because
a broken fetcher shows up nowhere on it.

Anything else about these is in `annotate-supaline`, `verify-supaline`, or the
comment beside the step in `.github/workflows/check.yml`.

## Formatting

`stylua.toml` and `.luarc.json` are copied verbatim from
[yazi-rs/plugins](https://github.com/yazi-rs/plugins). Keep them that way.
`ruff.toml` beside them is this repository's own, because nothing upstream
exists to copy for Python.

`.lua` files are tab-indented, and `indent_width = 2` is a tab's assumed
display width when measuring against `column_width`, not two spaces. Markdown
code blocks are the exception and stay on spaces, which `MD010` enforces.

Everything else about form belongs to `stylua`, `markdownlint-cli2` and
`ruff` — CI runs all three, each says beside itself why a rule is set the way
it is, and a clean lint is the whole of what form asks. All three see only what
Git tracks, so a personal file is out of scope wherever a contributor keeps one.
