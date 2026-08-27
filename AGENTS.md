# AGENTS.md

Canonical instructions for AI agents working in this repository. Claude Code
reads this file through `CLAUDE.md`; other agents read it directly. Keep it the
single source of truth — do not copy rules into agent-specific files.

## What this is

supaline is a [Yazi](https://github.com/sxyazi/yazi) plugin that replaces the
linemode with a configurable set of columns: sizes and timestamps coloured on an
eza-style gradient, plus Git and chezmoi status. Built-in columns and
user-written ones go through the same interface; neither has a privileged path.

## Language

This repository is public. **Everything tracked in Git is written in English** —
code comments, documentation, README, user-facing error messages, and commit
messages. This includes files only agents read.

Contributors may keep translations outside the repository. Those are never
authoritative and never tracked; when a translation disagrees with the English,
the translation is wrong.

Commit messages follow the Conventional Commits specification. No emoji or
Gitmoji anywhere in the message. Do not capitalise the first letter of the
subject; keep the subject to 50 characters and the whole header to 72.

## Target platform

Yazi **26.8.15 or newer**. Start every Lua file with `--- @since 26.8.15` —
Yazi enforces the annotation, and an older Yazi refuses to load the plugin
outright.

Yazi is on CalVer and breaks the plugin API freely between releases. 26.8.15
changed the fetcher calling convention and silently renamed a DDS event, so code
written for 26.5.6 — let alone 0.4.x — will not run.

## Platform constraints

Each of these was found by instrumenting a running Yazi or by reading its
source. None are in the official documentation. Writing code without accounting
for them breaks things silently: no error, just an empty column.

### The theme is not loaded when `setup` runs

At startup `THEME` is initialised from the **preset theme only**
(`THEME.init(Preset::theme(false))`). The user's `theme.toml` and flavor are
merged exclusively inside the `app:theme` actor, which then fires the `theme`
DDS event. This applies to built-in sections as much as to custom ones — a
`[mgr] cwd` override written in `theme.toml` is not in effect when `setup` runs.

So: never cache anything read from `th.*` at setup time. Resolve base colours
and build styles inside `ps.sub("theme", ...)`, and run that same builder once
at setup so the plugin has something to draw with in the meantime.

Custom theme sections are read as `th.<section>`. Section names are normalised
from kebab-case to snake_case (`[my-plugin]` becomes `th.my_plugin`), field
values may only be a style table or a string, and **built-in section names are
reserved** — a custom field added to `[mgr]` is unreachable.

### `ya.sync` state is scoped to the file the call is written in

Yazi binds a `ya.sync` block to the name of the plugin being loaded and matches
the async and sync sides **by the position of the call**. A closure written in
one module therefore writes to a different state table than one written in
another, and reordering the calls silently rebinds them.

So: every `ya.sync` call lives at the top level of `main.lua`, unconditionally
and in a fixed order. Never inside an `if`, never inside a `pairs` loop, never
inside `setup`. Providers export plain reducers that `main.lua` wraps.

This is also why a third-party column cannot own asynchronous state: a `ya.sync`
call made from the user's `init.lua` is never replayed in the async VM.

### Fetchers return a function, not a boolean

Since 26.8.15 Yazi calls whatever `fetch` returns, repeatedly, and expects
`file, { retry = …, error = … }` each time; `nil` ends the loop. Returning the
old boolean fails with "error converting Lua boolean to function", and the
failure is invisible — the side effects already ran, so the column still fills
in, and the error is written only to the task log. Look for a stuck "N left" in
the status bar.

Every file in `job.files` must be reported exactly once. Omitting one gets it
retried and logs the fetcher as having quit early; reporting one twice is a hard
error. `retry = true` clears the loaded bit and runs again on the next visit.

Fetchers can register themselves with `rt.plugin.fetchers:insert()`, sparing the
user a `[[plugin.prepend_fetchers]]` block. Yazi caps the list at 16 and runs
only the first matching rule per `group`.

### Linemode children also render in the parent pane

`Linemode:solo()` guards `in_current` itself, but a child added with
`Linemode:children_add()` does not, and `parent.lua` calls
`Linemode:new(f):redraw()` too. A child is therefore called for rows in the
parent pane. Decide explicitly whether a given child renders there, and
remember that folder-wide statistics for such a row must come from the parent
folder, not `cx.active.current`.

### DDS event names are not all in the changelog

26.8.15 renamed `bulk` to `bulk-rename` without saying so. `ps.sub` accepts any
string, so a stale name is a subscription that simply never fires. The kinds
actually published live in `pub_after!` in `yazi-dds/src/pubsub.rs`; read them
there rather than trusting the changelog.

### Every module must return a table

Yazi wraps each module in a state table. `return true` from a side-effect-only
file fails with "error converting Lua boolean to table"; return `{}` instead.

### Prefer `Url.spec.*`

`Url.is_regular`, `Url.is_search` and `Url.domain` are deprecated in 26.8.15 in
favour of `Url.spec.is_regular`, `Url.spec.is_search` and `Url.spec.domain`.

## Rendering budget

`render` runs for every visible row on every frame. It must be O(1) and
allocate as little as possible.

- Gradient ramps are built once and quantised into buckets, so no colour maths
  and no `ui.Style` allocation happens per row.
- Anything that needs the whole folder belongs in `stats`, computed once per
  folder and cached.
- `render` may return `text, style` instead of a renderable, which skips
  building an intermediate line. The built-in columns use this.
- `ui.Style` is immutable as of 26.5.6, so `style:fg(c)` returns a new style.

A linemode name is 1 to 20 characters. An unregistered name renders as literal
text, so a name registered late shows up on screen.

## Formatting

`stylua.toml` and `.luarc.json` are copied verbatim from
[yazi-rs/plugins](https://github.com/yazi-rs/plugins). Keep them that way.

`indent_width = 2` does **not** mean two spaces. `indent_type` defaults to
`Tabs`, so `.lua` files are tab-indented, as upstream Yazi's are; `indent_width`
is only the assumed display width of a tab when measuring against
`column_width`.

Markdown code blocks are the exception: a tab inside a fenced block renders at
the viewer's tab width — 8 by default on GitHub — which makes a nested example
look absurd. Keep documentation snippets on spaces and `.lua` files on tabs.

Claude Code formats `.lua` files in this repository automatically: a
`PostToolUse` hook in `.claude/settings.json` runs stylua after every write.
The hook is scoped to `.lua` files inside this repository and never blocks a
write. Other agents and hand edits are not covered — run stylua yourself:

```sh
stylua --check .
```

## Verification

```sh
lua test/run.lua            # unit tests
lua test/run.lua column     # ... just the specs matching "column"
test/e2e.sh                 # render in a real Yazi, headless
test/e2e.sh --keep          # ... and leave the scratch directory behind
test/manual.sh              # ... interactively, for a human to look at
test/manual.sh --clean      # discard the manual fixture
```

`e2e.sh` and `manual.sh` both build their configuration and fixture with
`test/setup.sh`, so what a person looks at and what the headless run asserts on
cannot drift apart. The fixture opens on a directory carrying the cases that
break width arithmetic — CJK, emoji, an over-long name, sizes either side of
the 1K boundary — with siblings above it and a subdirectory below, so all three
panes have rows. `m0` to `m9` switch between the linemodes, one per decision
worth looking at, and `test/MANUAL.md` says what to look for in each; Yazi's own `m s` and `m n` still work, which is what makes
them worth comparing against.

Unit tests can only cover pure logic — normalisation, layout, the ratio
contract, the built-in formatters — because they stub the Yazi globals. They
can say nothing about rendering, fetchers or `ya.sync`, which is exactly where
the bugs live. Run the plugin in a real Yazi and read the output before
reporting that anything works.

The stubs are only worth as much as their fidelity, so `ui.truncate` is a
line-by-line port of Yazi's own and `truncate_spec.lua` pins it against the
assertions in Yazi's test suite. If you stub something new, pin it the same
way.

Keep the test code within the Lua 5.1 subset: the local interpreter may be 5.1,
CI runs 5.4, and Yazi itself runs 5.5.

Two things make headless runs behave unlike a real terminal:

- A detached tmux never answers the terminal probe, so `rt.term.light()` stays
  `nil` and `app:theme` never runs on its own. **Send `app:theme` before
  capturing**, or the user's theme is not applied at all and every `th.*` read
  returns preset values.
- Yazi queries the terminal on startup and aborts if nothing answers, so
  `script`-style pseudo-terminals do not work. Use tmux, which is a real
  terminal emulator.

A green exit is worth more than the screen looking right: a broken fetcher shows
up nowhere on screen, only as a task that never succeeded.
