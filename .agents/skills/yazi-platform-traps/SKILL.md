---
name: yazi-platform-traps
description: >-
  Four behaviours of Yazi 26.9.1 that break this plugin silently and that CI
  does not catch: a theme reload replaces colours already resolved and the
  flavor lands after `init.lua` has run, a fetcher returns a function rather
  than a boolean, linemode children also render in the parent pane, and an
  error raised under a render blanks the whole screen rather than the row.
  Plus the budget a linemode render runs under. Read when a change resolves a
  colour or reads the theme, writes a fetcher, touches the parent- or
  preview-pane child, adds a column's render or stats, or adds a call into a
  function a column wrote -- not for every edit to plugin
  Lua, and not for a rename or a format string. Seven
  further traps are refused by a test or a CI job that prints the fix, so they
  need no reading in advance; references/checked-traps.md has them for when one
  fires, and references/probes.md has what was run to establish the four
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
four below, which is what you would be re-running.

Seven of the eleven traps are refused by a test or a CI job that prints the
fix, and live in `references/checked-traps.md`, worth opening when one fires.
The four below are what no check catches. When you find a way to move one into
the checked list, take it.

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

A field **name** is not normalised the way a section name is; it is refused.
Yazi takes 1 to 20 characters of lowercase letters, digits and `_`, and answers
anything else with a TOML parse error that discards the whole of `theme.toml`
and falls back to the preset — so one bad field name costs every colour in the
file, not just its own. That is loud, and the silent half is supaline's: a
column's theme layer is `th.supaline[name]`, so a column registered under a
name no field can hold draws perfectly and can never be themed. `register`
refuses such a name, and `column_spec.lua` pins both halves of the rule,
including the three spellings Yazi's own "snake-case" message implies it
refuses and in fact accepts. `references/probes.md` has the measurement.

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
  Span, Line, or a table of them`, and the screen stops drawing — see the
  section below for how much of it. Cache the
  styles, rebuild the rest. Measured on 26.9.1, and refused by the stub —
  `column_spec.lua` "a span drawn a second time is refused" and "a whole Line
  drawn a second time is refused too". The Line half is the one `column.cell`
  walks into: every render's output goes through one `ui.Line`.

A linemode name is 1 to 20 characters. An unregistered name renders as literal
text, so a name registered late shows up on screen.

## An error under a render takes the whole screen, not the row

Measured on 26.9.1, in a real Yazi. An error raised anywhere beneath a
linemode's render fails the **`Root` component** — the file list, the header
and the status bar all stop drawing, leaving the terminal blank but for the
preview pane's own placeholder. It is not a one-off: the redraw is attempted
and fails again on every frame, for as long as that folder is open, while Yazi
goes on accepting keys against a screen showing nothing. `Failed to redraw the
'Root' component` reaches the log and nothing reaches the screen — and there is
no log at all unless `YAZI_LOG` was set before Yazi started, which is not how
anybody runs it.

So an `error` is the most expensive thing a column can do, and it costs the
same whoever wrote it. A reader's own `render` raising produced exactly that
blank screen with no part of this plugin involved.

supaline calls four functions a column may write. Three of them — `stats`, a
`width` that is one, and `render` — are called inside that redraw, and all
three are made under `pcall` in `main.lua`, which reports once per column and
goes on drawing; `broke` there carries the reasoning and `main_spec.lua`'s
`throwing:` specs pin it. **A new call into a column's code belongs under the
same containment**, and that is the part no check will tell you: the suite
stays green either way, because a spec only ever reaches code that already
exists.

The fourth is `refresh`, and it is the one that shows the rule is about the
caller rather than the render. It is not called under a render at all, so a
blank screen is not what a bare one costs; what it costs is a silence per
caller. On `cd` it runs from a `ps.sub` handler, which Yazi puts no error out
of in front of anybody, so the hooks queued behind a throwing one stop running
and another column's cached value goes stale for the rest of the session. From
`setup` it runs after the commit — `uninstall` done, the registration loop not
yet run — so a throw there leaves every supaline linemode unregistered, which
Yazi draws as literal text on every row. Both halves are contained, and
`main_spec.lua`'s "a `refresh` that throws" pins them.

So the rule is not "wrap what is called under a render". It is that a call into
a column's own code is contained wherever it is made, because the question is
never whether the throw is survivable — it is who the error would reach, and in
this plugin the answer has so far always been nobody.

What must not be contained this way is a mistake in the *configuration*.
`setup` runs from `init.lua`, before any component draws, and an error there
stops Yazi starting and prints the whole message to the terminal — which is
the loudest and most useful refusal available. Refuse what can be refused
there; contain only what cannot be known until a render.

The containment has one more consequence, and it is easy to walk into:
**supaline's own refusals inside a contained call must not be raised.** A
`pcall` cannot tell who threw, so a refusal raised in there comes back out
worded as the reader's code failing — `column.resolve_width` refusing a
`width` function's return of `0` would be reported as that function throwing,
which it did not. It returns `nil, why` instead, and `main.lua` words the two
differently. Narrowing the `pcall` to the reader's function alone would sort
them out too, and is the wrong half to take: it puts supaline's own raise back
on the path that blanks the screen.

## Caught by a check, not by reading

Detail in `references/checked-traps.md`; the failure itself will usually be
enough.

- `ya.sync` must sit at the top level of `main.lua` — CI job `ya.sync placement`
- `in_preview` must not appear in plugin Lua — CI job `Forbidden spellings`
- `is_regular` must not appear in plugin Lua — CI job `Forbidden spellings`
- a DDS kind Yazi does not publish is refused by the stub's `ps.sub`
- a module that returns a boolean fails `test/module_spec.lua`
