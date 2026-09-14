---
name: yazi-platform-traps
description: >-
  Three behaviours of Yazi 26.9.1 that break this plugin silently and that CI
  does not catch: a theme reload replaces colours already resolved and the
  flavor lands after `init.lua` has run, a fetcher returns a function rather
  than a boolean, and linemode children also render in the parent pane. Plus
  the budget a linemode render runs under. Read when a change resolves a colour
  or reads the theme, writes a fetcher, touches the parent- or preview-pane
  child, or adds a column's render or stats -- not for every edit to plugin
  Lua, and not for a rename or a format string. Seven
  further traps are refused by a test or a CI job that prints the fix, so they
  need no reading in advance; references/checked-traps.md has them for when one
  fires, and references/probes.md has what was run to establish the three
  above.
---

# Yazi platform traps

None of these are in Yazi's documentation, and none of them error: the symptom
is an empty column, a stale colour, or a task that never finishes.

Every claim here and in `references/checked-traps.md` was measured on Yazi
26.9.1 (Homebrew 2026-09-01) in a detached tmux, with a probe plugin and
`ya.dbg`; where a measurement stops short, it says so. A different Yazi is a
reason to re-run the experiment rather than trust the sentence — and when you
do, write down what you ran. `references/probes.md` holds what was run for the
three below, which is what you would be re-running.

Seven of the ten traps are refused by a test or a CI job that prints the fix,
and live in `references/checked-traps.md`, worth opening when one fires. The
three below are what no check catches. When you find a way to move one into the
checked list, take it.

## A theme reload replaces colours already resolved

On 26.9.1 the user's `theme.toml` is merged **before any plugin code runs**:
`th.supaline` and a `[mgr]` override alike are readable from the first line of
`init.lua`, so a section the user wrote reaches a colour resolved inside
`setup`.

**The flavor is not there yet.** A field only the flavor supplies —
`th.status.perm_read`, `th.mode.normal_main` — still holds Yazi's preset while
`init.lua` runs, and reaches the flavor's value with the `theme` event that
fires a few milliseconds later, unasked. So "resolve it at setup and it is the
user's" is true of `theme.toml` and false of a flavor, and the two are
indistinguishable from Lua: both arrive as `th.<section>.<key>`.

That is also why `style` takes a function. A spec that reads `th` at load time
freezes what it read and holds it through every reload -- the stored spec is
re-read on each `theme` event, never evaluated again -- so a user borrowing a
colour from their own theme has no correct way to write it as a value. A
function is called inside `build`, which is the same repair the plugin makes
for itself.

**The reload bites too.** `app:theme` re-reads `theme.toml` from disk
mid-run, and a plugin that resolved its colours once at `setup` goes on drawing
the old ones — no error, just a stale colour, because a `Style` out of `th` is
a value frozen when it was read rather than a handle. So: resolve the colours
and build styles inside `ps.sub("theme", ...)`, and run that same builder once
at setup so the plugin has something to draw with before the first event. One
subscription answers both halves — the unasked event corrects the flavor, a
later one the reload — which is why the plugin is not already broken.

Custom theme sections are read as `th.<section>`. Section names are normalised
from kebab-case to snake_case (`[my-plugin]` becomes `th.my_plugin`), field
values may only be a style table or a string, and **built-in section names are
reserved** — a custom field added to `[mgr]` is unreachable.

Pinned twice, by `test/main_spec.lua` and by `test/e2e.sh` against a real Yazi,
and both pins discriminate.

## Fetchers return a function, not a boolean

Yazi calls whatever `fetch` returns, repeatedly, and expects
`file, { retry = …, error = … }` each time; `nil` ends the loop. Report each
file exactly once: reporting one twice fails the task, and leaving one
unreported does not.

A failed fetcher is nearly invisible. The body has already run, so the side
effects landed and a column still fills in. **Nothing reaches `yazi.log`, not
even at `YAZI_LOG=debug`** — the message is in the task manager alone (`w`,
then Enter on the failed row), and the only sign on screen is a stuck `1 left`
in the status bar. Look there before believing a fetcher worked.

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

Pinned by `test/main_spec.lua` "a pane key opts into the pane it names", which
covers the code that exists and not a column written tomorrow.

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
- **`ui.Line` consumes what it is given**, spans and whole Lines alike, so
  nothing renderable can be built once and drawn twice: the second `ui.Line`
  over the same table — or over the same Line — raises `expected a string,
  Span, Line, or a table of them`, and the pane stops drawing. Cache the
  styles, rebuild the rest. Measured on 26.9.1, and refused by the stub —
  `column_spec.lua` "a span drawn a second time is refused" and "a whole Line
  drawn a second time is refused too". The Line half was missing from the stub
  until a review asked for it, and it is the half `column.cell` walks into:
  every render's output goes through one `ui.Line`.

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
