---
name: yazi-platform-traps
description: >-
  Three behaviours of Yazi 26.9.1 that break this plugin silently and that CI
  does not catch: a theme reload replaces colours already resolved, a fetcher
  returns a function rather than a boolean, and linemode children also render
  in the parent pane. Plus the budget a linemode render runs under. Read when
  a change resolves a colour or reads the theme, writes a fetcher, touches the
  parent- or preview-pane child, or adds a column's render or stats -- not for
  every edit to plugin Lua, and not for a rename or a format string. Six
  further traps -- ya.sync binding by call position, in_preview versus
  in_current, the bulk to bulk-rename rename, modules that must return a table,
  is_regular versus the six AuthKind variants, and truncation counting
  characters where the screen counts clusters -- are refused by a test or a CI
  job instead, and are in references/checked-traps.md for when one of them
  fires.
---

# Yazi platform traps

None of these are in Yazi's documentation, and none of them error: the symptom
is an empty column, a stale colour, or a task that never finishes.

Every claim here and in `references/checked-traps.md` was measured on Yazi
26.9.1 (Homebrew 2026-09-01) in a detached tmux, with a probe plugin and
`ya.dbg`; where a measurement stops short, it says so. A different Yazi is a
reason to re-run the experiment rather than trust the sentence — and when you
do, write down what you ran.

Six of the nine traps are refused by a test or a CI job that prints the fix,
and live in `references/checked-traps.md`, worth opening when one fires. The
three below are what no check catches. When you find a way to move one into the
checked list, take it.

## A theme reload replaces colours already resolved

On 26.9.1 the user's `theme.toml` and flavor are merged **before any plugin
code runs**. `th.supaline` and a `[mgr]` override alike are readable from the
first line of `init.lua`, so resolving a base colour inside `setup` gets the
user's value, not a preset's.

Measured with `ya.dbg` and a probe column painted from `init.lua`:

- `th.supaline.mtime` reads the user's `green` at the top of `init.lua`, before
  `setup` is called and before any `theme` event.
- A `[mgr] cwd` override captured into an upvalue at load time paints the
  user's colour, so built-in sections are merged that early too. It keeps that
  colour across a reload while the same field re-read inside the handler
  follows the new one — a `Style` out of `th` is a **value frozen when it was
  read**, not a handle, which is what makes the capture evidence rather than an
  artefact.
- A `theme` event fires by itself a couple of milliseconds after `init.lua`,
  without the terminal probe ever being answered.

**What still bites is the reload.** `app:theme` re-reads `theme.toml` from disk
mid-run, and a plugin that resolved its colours once at `setup` goes on drawing
the old ones — no error, just a stale colour. So: resolve base colours and
build styles inside `ps.sub("theme", ...)`, and run that same builder once at
setup so the plugin has something to draw with before the first event.

Custom theme sections are read as `th.<section>`. Section names are normalised
from kebab-case to snake_case (`[my-plugin]` becomes `th.my_plugin`), field
values may only be a style table or a string, and **built-in section names are
reserved** — a custom field added to `[mgr]` is unreachable.

**Pinned twice, and both pins discriminate**: comment out
`ps.sub("theme", build)` and each goes red on its own. `test/main_spec.lua`
sets the section, runs `setup`, changes the section, and fires `theme` —
changing it *after* setup is what makes the test say anything, since a section
that never changed would also pass for a plugin that never subscribed.
`test/e2e.sh` does the same against a real Yazi, rewriting `theme.toml` on disk,
where the unit stub's model cannot be the thing that is wrong.

## Fetchers return a function, not a boolean

Yazi calls whatever `fetch` returns, repeatedly, and expects
`file, { retry = …, error = … }` each time; `nil` ends the loop.

Measured with a throwaway fetcher over a two-file folder:

- Returning the old boolean fails with `error converting Lua boolean to
  function`, and the failure is nearly invisible: the body had already run, so
  the side effects landed and a column would still fill in. **Nothing reaches
  `yazi.log`, not even at `YAZI_LOG=debug`** — the message is in the task
  manager alone (`w`, then Enter on the failed row), and the only sign on
  screen is a stuck `1 left` in the status bar. Returning a loop instead
  clears the count, which is what makes this a measurement and not an anecdote.
- Reporting one file twice fails the task the same way, with the same stuck
  count: `fetcher reported an unknown or duplicate file`.
- Reporting only one of the two did **not** fail the task — it completed and
  the count cleared. Do not go looking for a complaint Yazi never makes.

`retry = true` clears the loaded bit and runs again on the next visit. Fetchers
can register themselves with `rt.plugin.fetchers:insert()`, sparing the user a
`[[plugin.prepend_fetchers]]` block; Yazi caps the list at 16 and runs only the
first matching rule per `group`.

**Measured, not pinned** — the only constraint here with no test behind it, and
only because the plugin has no fetcher yet. Pin it with the first one: have the
stub call what `fetch` returns and refuse a boolean, the way it refuses an
unknown `AuthKind`.

## Linemode children also render in the parent pane

`Linemode:solo()` guards `in_current` itself, but a child added with
`Linemode:children_add()` does not, and `parent.lua` calls
`Linemode:new(f):redraw()` too. A child is therefore called for rows in the
parent pane. Decide explicitly whether a given child renders there, and
remember that folder-wide statistics for such a row must come from the parent
folder, not `cx.active.current`.

Pinned by `test/main_spec.lua` "a list opts into the panes it names", which
calls the child directly for a row with `in_current = false` — the case
`solo()` would have refused and the child does not.

## The rendering budget

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

## Caught by a check, not by reading

Detail in `references/checked-traps.md`; the failure itself will usually be
enough.

- `ya.sync` must sit at the top level of `main.lua` — CI job `ya.sync placement`
- `in_preview` must not appear in plugin Lua — CI job `Forbidden spellings`
- `is_regular` must not appear in plugin Lua — CI job `Forbidden spellings`
- a DDS kind Yazi does not publish is refused by the stub's `ps.sub`
- a module that returns a boolean fails `test/module_spec.lua`
