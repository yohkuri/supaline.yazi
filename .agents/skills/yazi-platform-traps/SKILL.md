---
name: yazi-platform-traps
description: >-
  Three behaviours of Yazi 26.8.15 that break this plugin silently and that no
  check catches: the theme is not loaded when setup runs, a fetcher returns a
  function rather than a boolean, and linemode children also render in the
  parent pane. Plus the budget a linemode render runs under. Read when a change
  resolves a colour or reads the theme, writes a fetcher, touches the parent-
  or preview-pane child, or adds a column's render or stats -- not for every
  edit to plugin Lua, and not for a rename or a format string. Five further
  traps --
  ya.sync binding by call position, in_preview versus in_current, the bulk to
  bulk-rename rename, modules that must return a table, and is_regular versus
  the six AuthKind variants -- are refused by a test or a CI job instead, and
  are in references/checked-traps.md for when one of them fires.
---

# Yazi platform traps

Each of these was found by instrumenting a running Yazi or by reading its
source. None are in the official documentation. Writing code without accounting
for them breaks things silently: no error, just an empty column.

All of them were established against **Yazi 26.8.15**. Yazi is on CalVer and
breaks the plugin API freely between releases, so a different version is reason
to re-verify rather than to assume. `test/e2e.sh` prints the version it ran
against and says so when it is not the one `main.lua` annotates.

What is below is what no check catches. Five of the eight constraints are
refused by a test or a CI job that prints what to write instead, so reading
about those in advance buys nothing — they are in
`references/checked-traps.md`, worth opening when one of them fires. The rest
are here because a green suite says nothing about them: two are pinned only
against the existing code, so new code can repeat them and stay green, and one
has no pin at all.

When you find a way to move one of these into the checked list, take it. That
is the direction knowledge travels here.

## The theme is not loaded when `setup` runs

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

Pinned by `test/main_spec.lua` "base colours are resolved on the event, not at
setup". The stub serves preset values until a `theme` event fires, so a test
can put the user's section in place *before* `setup` and still assert the
plugin cannot see it — which is the trap. A test that made the section appear
afterwards would pass for a plugin that read `th` too early.

## Fetchers return a function, not a boolean

Since 26.8.15 Yazi calls whatever `fetch` returns, repeatedly, and expects
`file, { retry = …, error = … }` each time; `nil` ends the loop. Returning the
old boolean fails with "error converting Lua boolean to function", and the
failure is invisible — the side effects already ran, so the column still fills
in, and the error is written only to the task log. Look for a stuck "N left" in
the status bar.

Every file in `job.files` must be reported exactly once. Omitting one gets it
retried and logs the fetcher as having quit early; reporting one twice is a hard
error. `retry = true` clears the loaded bit and runs again on the next visit.

**Not pinned.** This is the one constraint here that is still only prose, and
only because the plugin has no fetcher yet. Pin it with the first one: have the
stub call what `fetch` returns and refuse a boolean, the way it refuses an
unknown `AuthKind`.

Fetchers can register themselves with `rt.plugin.fetchers:insert()`, sparing the
user a `[[plugin.prepend_fetchers]]` block. Yazi caps the list at 16 and runs
only the first matching rule per `group`.

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
