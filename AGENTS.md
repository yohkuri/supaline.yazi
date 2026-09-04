# AGENTS.md

Canonical instructions for AI agents working in this repository. Claude Code
reads this file through `CLAUDE.md`; other agents read it directly. Keep it the
single source of truth — do not copy rules into agent-specific files.

This file is the index, not the manual. What is here applies to every session.
The detail lives in two skills under `.agents/skills/`, read when the task
calls for them:

- `yazi-platform-traps` — for a change that resolves a colour, writes a
  fetcher, or touches the parent- or preview-pane child
- `verify-supaline` — for a change under `test/`

## What this is

supaline is a [Yazi](https://github.com/sxyazi/yazi) plugin that replaces the
linemode with a configurable set of columns: sizes and timestamps coloured on an
eza-style gradient. Built-in columns and user-written ones go through the same
interface; neither has a privileged path.

Whether supaline ships status columns of its own — version control, dotfile
management — is **undecided**. Do not describe them as planned or forthcoming,
and do not justify a design choice by pointing at one; if such a column has to
come up at all, say plainly that it is hypothetical.

## Source of truth

Prefer code, tests, Git history, and actual tool output over documentation when
they conflict — this file included. Every platform claim below held for one
Yazi build on one machine, and the Yazi in front of you is what decides. When a
document turns out to be wrong, fix the document rather than working around it.

## Language

This repository is public. **Everything tracked in Git is written in English** —
code comments, documentation, README, user-facing error messages, and commit
messages. This includes files only agents read.

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

## Target platform

Yazi **26.8.15 or newer**. Start every Lua file with `--- @since 26.8.15` —
Yazi enforces the annotation, and an older Yazi refuses to load the plugin
outright.

Yazi is on CalVer and breaks the plugin API freely between releases. 26.8.15
changed the fetcher calling convention and silently renamed a DDS event, so code
written for 26.5.6 — let alone 0.4.x — will not run.

## Traps

Eight behaviours of Yazi 26.8.15 break this plugin **silently** — no error, just
an empty column, a stale colour, or a task that never finishes. Knowing that
they exist is what this list is for, and for most changes it is the whole of
what you need; the mechanism behind each is in
`.agents/skills/yazi-platform-traps/`.

- `THEME` holds preset values until the `theme` event — a colour resolved at
  setup is the preset's, for good
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

**Five of the eight are refused by a check**, which prints what to write
instead: `ya.sync` placement and the two forbidden spellings in CI, an
unpublished DDS kind by the stub, a module returning a boolean by
`test/module_spec.lua`. Nobody has to read about those.

The other three are why the skill exists. The theme timing and the parent-pane
child are pinned only against the code that is already here, so **new** code can
repeat them and keep the suite green — measured, not assumed: a fresh column
written with `not is_regular` passed all 103 tests before the spelling check
existed. The fetcher one has no pin at all, because there is no fetcher yet.

So the skill is worth opening for a change that resolves a colour, writes a
fetcher, or touches the parent- or preview-pane child — and not otherwise. A
format string or a rename does not need it.

## Commands

```sh
lua test/run.lua            # unit tests
lua test/run.lua column     # ... just the specs matching "column"
test/e2e.sh                 # render in a real Yazi, headless
test/manual.sh              # ... interactively, for a human to look at
stylua --check .            # formatting
```

`test/e2e.sh` and `test/manual.sh` need a real Yazi and a real terminal and are
deliberately not in CI. Run them yourself before claiming anything about the
screen — and note that a green exit is worth more than the screen looking
right, because a broken fetcher shows up nowhere on it.

Running them needs nothing else. `.agents/skills/verify-supaline/SKILL.md` is
for **changing** the harness — writing a spec, adding a stub, or editing one of
the shell scripts — and says what a stub owes Yazi in fidelity, what the unit
suite can and cannot prove, and how a headless run differs from a terminal.

## Formatting

`stylua.toml` and `.luarc.json` are copied verbatim from
[yazi-rs/plugins](https://github.com/yazi-rs/plugins). Keep them that way.

`.lua` files are tab-indented: `indent_width = 2` is a tab's assumed display
width when measuring against `column_width`, not two spaces. Markdown code
blocks are the exception — keep documentation snippets on spaces, because a tab
inside a fenced block renders at the viewer's tab width, 8 by default on
GitHub, which makes a nested example look absurd. Nothing checks that one;
stylua and CI cover the Lua.
