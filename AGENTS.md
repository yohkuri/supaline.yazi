# AGENTS.md

Canonical instructions for AI agents working in this repository. Claude Code
reads this file through `CLAUDE.md`; other agents read it directly. Keep it the
single source of truth — do not copy rules into agent-specific files.

This file is the index, not the manual. What is here applies to every session.
The detail lives in three skills under `.agents/skills/`, read when the task
calls for them:

- `yazi-platform-traps` — for a change that resolves a colour, writes a
  fetcher, or touches the parent- or preview-pane child
- `verify-supaline` — for a change under `test/`
- `document-supaline` — for a change to this file, to a skill, or to a rule
  under `.claude/rules/`

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

Nine behaviours of Yazi break this plugin **silently** — no error, just an
empty column, a stale colour, or a task that never finishes. Knowing that they
exist is what this list is for, and for most changes it is the whole of what you
need; the mechanism behind each, and the experiment that established it, is in
`.agents/skills/yazi-platform-traps/`.

- `app:theme` re-reads `theme.toml` mid-run — a colour resolved once and
  cached goes stale, and nothing says so. (Read `th.*` freely at setup: 26.9.1
  merges the user's theme before any plugin code runs; it is the *reload* that
  bites)
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

**Six of the nine are refused by a check**, which prints what to write
instead: `ya.sync` placement and the two forbidden spellings in CI, an
unpublished DDS kind by the stub, a module returning a boolean by
`test/module_spec.lua`, a cut that counts characters by `truncate_spec.lua`
and `column_spec.lua`. Nobody has to read about those.

The other three are why the skill exists, because a green suite says nothing
about them. The parent-pane child is pinned against the code already here, so
**new** code can repeat it and stay green — measured, not assumed: a fresh
column written with `not is_regular` passed all 103 tests before the spelling
check existed. The fetcher has no pin at all, because there is no fetcher yet.

## Commands

```sh
lua test/run.lua                  # unit tests
lua test/run.lua column           # ... just the specs matching "column"
test/e2e.sh                       # render in a real Yazi, headless
test/manual.sh                    # ... interactively, for a human to look at
stylua --check .                  # Lua formatting
lua-language-server --check .     # Lua types
npx --yes markdownlint-cli2@0.19  # Markdown
```

The unit suite runs on **Lua 5.5**, the version Yazi embeds, and `test/run.lua`
refuses any other. Any 5.5 does: `mise.toml` pins 5.5.1 for whoever uses mise,
and CI installs its own — nothing here requires a version manager.

`lua-language-server --check .` type-checks the plugin against Yazi's own
annotations, which `.luarc.json` expects at
`~/.config/yazi/plugins/types.yazi/`; `ya pkg add yazi-rs/plugins:types`
installs them. Without that directory the check still runs and still finds
nothing — it has quietly stopped comparing the plugin against anything but
this repository. CI fetches a pinned revision of them in a step of its own, so
that not getting them fails the job rather than weakening it.

What the check reaches is what carries a type. `cx`, `ya` and a `Url` are
declared classes, so a misspelled field or a wrong arity on one is refused, and
`column.lua` declares `supaline.File` and `supaline.Ctx` for the two values a
`render` is handed, so the columns are read too — `file.cha.is_dirr` and
`ctx.basee` are both refused, in a built-in column and in a spec alike. The
records the plugin passes around carry classes as well: a linemode, a column, a
folder and a bound entry. So does the configuration `setup` is given — the
plugin-wide options, a linemode spec, and the four shapes a column may be
written in — so `cfg.orderr`, `opts.linemodess` and `spec.paness` are refused
where they used to cost nothing.

That last one reaches only so far, and the limit is worth knowing before
trusting it. A wrong **value** in a spec is refused: `separator = 42` on a
linemode, `width = "wide"` on a column inside one. A misspelled **key** in the
same table is not — a table constructor passed as an argument is not checked
for keys its class does not declare, and marking those classes `(exact)` was
measured to change that at no site here. What a user writes wrong is still
`setup`'s to refuse at runtime, which is what all those errors are for.

`require(".main")` does not resolve to this repository's `main.lua`.
`types.yazi` ships a `main.lua` of its own, on `workspace.library` — 3,235 lines
of annotations with no `return` — so the name resolves there, and every call a
spec made into the plugin was silently checked against a module that exports
nothing: `main.setup(42, ...)` and `main.columnn(...)` both passed. `main.lua`
declares `supaline.Main` and `main_spec.lua` claims it at the `require`, which
is the repair `supaline.Stub` already is for the stub. Only `main` collides;
`.column` and `.builtin` resolve to this tree.

Yazi's own annotations are not the last word on Yazi. `types.yazi` describes
neither `file.idx`, `file.in_current` nor `Url.spec`, and gives `Cha.perm` as a
string where 26.9.1 has a method — so `column.lua` declares the difference
itself, with the probe that established it written beside the classes. A newer
Yazi is a reason to run that probe again and correct them there, never to work
around them at the call site.

Those differences are declared by inheriting from Yazi's class, never by
re-opening it, which means a folder taken off `cx` is cast where it arrives.
The cast is the price of the subclass and it is worth paying: re-opening
`fs__File` and `Cha` to write the fields straight onto them removed the casts
and, in one arrangement, silently stopped refusing a misspelling — a check that
quietly does nothing is the failure mode this whole job exists to avoid.

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
GitHub, which makes a nested example look absurd. `MD010` covers that one, tabs
inside fences included.

Markdown is `markdownlint-cli2`, configured in `.markdownlint-cli2.yaml`, which
says why each rule it turns off is off. It holds prose to the 80-column wrap
these documents already keep, and exempts what cannot be wrapped: a table cell,
and a fenced block quoting Yazi's source or its output verbatim. Table
alignment is not checked at all, because `test/MANUAL.md` pads its tables to
the width the screen draws Japanese at and the rule measures characters.

Both linters see only what Git tracks. Personal files are ignored, translations
under `.ai-local/` included.
