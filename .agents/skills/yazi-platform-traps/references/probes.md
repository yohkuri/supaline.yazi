# The probes behind the three unchecked traps

`SKILL.md` states three constraints no check refuses — a theme reload replaces
colours already resolved, a fetcher returns a function rather than a boolean,
a linemode child renders in the parent pane too — and says what to do about
each in a paragraph apiece. That is the whole of the working knowledge, and a
change that resolves a colour or writes a fetcher needs nothing from here.

This file is what was actually run and what came back. Read it when the
sentence upstairs has to be doubted rather than followed: a newer Yazi, a
symptom that does not match the claim, or a check you are about to write to
retire one of the three.

Everything here was measured on Yazi 26.9.1 (Homebrew 2026-09-01), in a
detached tmux, with a probe plugin and `ya.dbg`.

## Contents

- What is merged before any plugin code runs, and what is not
- A colour read back out of a style
- A theme table cannot hold a gradient
- A Line's style sits under its spans
- How Yazi colours a permission string
- What a cell with no `style` is drawn in
- What the two theme pins discriminate
- A fetcher that returns a boolean
- What pins the parent-pane child

## What is merged before any plugin code runs, and what is not

Measured with a probe column painted from `init.lua`:

- `th.supaline.mtime` reads the user's `green` at the top of `init.lua`, before
  `setup` is called and before any `theme` event.
- A `[mgr] cwd` override captured into an upvalue at load time paints the
  user's colour, so built-in sections of `theme.toml` are merged that early
  too.
- A `theme` event fires by itself a couple of milliseconds after `init.lua`,
  without the terminal probe ever being answered. What that costs a headless
  run is `verify-supaline`'s subject, not this one's.

The second bullet is evidence rather than an artefact of the probe because the
captured value and a re-read disagree: the capture keeps its colour across a
reload while the same field read inside the handler follows the new one. That
is the mechanism behind the trap — a `Style` out of `th` is a value frozen when
it was read, not a handle.

**The flavor is merged later than all of that**, and this file said otherwise
until it was measured. Three columns drawn side by side, over a `theme.toml`
holding `[flavor] dark = "catppuccin-mocha"`, an `[mgr] cwd` override and a
`[supaline] probe` field, each column painting one capture of the same field:

| field | captured in `init.lua` | captured in a `theme` handler | read per row |
| ----- | ---------------------- | ----------------------------- | ------------ |
| `th.mgr.cwd`, overridden in `theme.toml` | `#ff00ff` | — | `#ff00ff` |
| `th.supaline.probe`, a custom section | `#00ff00` | — | `#00ff00` |
| `th.mode.normal_main`, the flavor's | `[1m[44m` | catppuccin | catppuccin |

The flavor writes every one of its colours as `#rrggbb`, so a bold 4-bit
`[44m` cannot have come from it: that is Yazi's own preset, and the capture
taken while `init.lua` ran is holding it. The middle column is what keeps the
plugin working — the unasked `theme` event of the third bullet above lands
after the flavor does, and `main.lua` rebuilds on it.

The same timing, read from a spec rather than from the plugin, is what `base`
takes a function for. Two probe columns over the same field, one capturing it
in `init.lua` and one wrapping it in a function, against catppuccin-mocha and
then a `theme.toml` that overrode `[status] perm_read` mid-run:

| how the spec wrote it | at startup | after `app:theme` |
| --------------------- | ---------- | ----------------- |
| `base = th.status.perm_read` | `[33m`, the preset | `[33m`, unchanged |
| `base = function() return th.status.perm_read end` | `#f9e2af` | `#ff00ff` |

The captured one never moves: a spec is re-read on each `theme` event and never
evaluated again. Two things the run cost an hour to learn and neither is
supaline's: a flavor is found under `YAZI_CONFIG_HOME/flavors`, so a probe
config that does not carry one silently has no flavor at all and no unasked
`theme` event either; and `[status] perm_read = "#ff00ff"` is refused as
`expected struct StyleFlat` -- a theme field wants `{ fg = "..." }`.

The probe reads the field back through supaline rather than out of `th`,
because `getmetatable` on a style returns `false` and the two spellings it
tried read nothing. What it did not reach for is `raw()`, which answers with
the colour — the section below is that measurement, taken afterwards and
against what this one had concluded. `fg()` and `bg()` called with no
argument are getters as well, measured later still: each hands back the
colour as a `Color` userdata, or nil where none is set, and `fg(true)` on a
reversed style hands back the background. The userdata has no methods, so it
can be fed back into `fg()` and nothing can be read off it; a colour as text
comes out of `raw()` alone. Read off `yazi-binding/src/style/style.rs` at
26.9.1 and measured in the same run as the table below.

## A colour read back out of a style

`ui.Style` answers `raw()` with a plain table: `fg` and `bg` as strings, the
attributes as booleans, nothing at all for a style that holds nothing.
Measured on 26.9.1 in a detached tmux, from a throwaway `init.lua` printing
into the debug log.

| built by | `raw()` |
| -------- | ------- |
| `ui.Style():fg("#ff8800")` | `{ fg = "#FF8800" }` |
| `ui.Style():fg("cyan")` | `{ fg = "Cyan" }` |
| `ui.Style():fg("129")` | `{ fg = "129" }` |
| `ui.Style():fg("reset")` | `{ fg = "Reset" }` |
| `ui.Style():fg("bright-red")` | `{ fg = "LightRed" }` |
| `ui.Style():fg("darkgray")` | `{ fg = "DarkGray" }` |
| `ui.Style():fg("bright-black")` | `{ fg = "DarkGray" }` |
| `ui.Style():fg("bright-white")` | `{ fg = "White" }` |
| `ui.Style():bg("light-blue")` | `{ bg = "LightBlue" }` |
| `ui.Style():reverse()` | `{ reversed = true }` |
| `ui.Style():bg("#112233"):bold()` | `{ bg = "#112233", bold = true }` |
| `ui.Style():bold(true)` | `{ bold = false }` |
| `ui.Style()` | `{}` |

A hex comes back uppercased and a name in the spelling ratatui's `Display`
gives it, after `FromStr` has folded what went in: `bright` to `light`, `grey`
to `gray`, `bright-black` to `DarkGray`, `bright-white` to `White`. Every one
of those goes straight back into `fg()`, `Reset` included, and `colour.lua`'s
`HEX` pattern takes either case. The folding is read off
`ratatui-core/src/style/color.rs` at the revision 26.9.1 builds against; the
rows above are measured, and `test/stub.lua` spells its `raw()` from both.

It answers for a style **Yazi** built as readily as for one built here, which
is the half that matters. The same probe over a `theme.toml` holding
`[flavor] dark = "catppuccin-mocha"` and a `[supaline]` section, reading each
field twice — once in `init.lua`, once inside a `theme` handler:

| field | in `init.lua` | in the `theme` handler |
| ----- | ------------- | ---------------------- |
| `th.status.perm_read` | `{ fg = "Yellow" }` | `{ fg = "#F9E2AF" }` |
| `th.mode.normal_main` | `{ bg = "Blue", bold = true }` | `{ bg = "#89B4FA", bold = true, fg = "#1E1E2E" }` |
| `[supaline] tbl = { fg = "#0000ff", bold = false }` | `{ bold = false, fg = "#0000FF" }` | the same |
| `[supaline] str = "#00ff00"` | a Lua string, with no `raw` | the same |

Three things fall out of it.

**A flavor can supply a gradient endpoint.** It writes every colour as
`#rrggbb`, so `raw().fg` off one is a value `colour.stops` would take. Yazi's
own preset does not: `Yellow` is a name, and a name cannot anchor a ramp. So a
gradient anchored on a colour a function returned would refuse a flavorless
user's, and refuse it from inside a `theme` handler rather than while `setup`
ran — which is the part to design before the part that works. `colour.lua`
does not do it yet.

**The flavor timing is measured a second way here.** The two columns disagree
for exactly the fields a flavor supplies, which is what the section above
established by drawing three columns on a screen and reading the escapes back.
Two lines of `ya.dbg` reach it now, and a check could.

**`colour.lua` reads every `ui.Style` it is handed through it**, which is what
lets a themed table field be merged key by key with the spec's, and taking it
cost three things. `types.yazi` declares no `raw` on `ui.Style`, which it
marks `(exact)`, so `supaline.Style` declares it and a caller casts to that
where the value arrives, the way `supaline.Line` does for `truncate`;
`test/stub.lua` models it, spelling the colours the way the table above shows
and the rest of the names the way ratatui's `Display` does, and
`colour_spec.lua` pins that; and a method the annotations do not carry is a
CalVer surface, though not one with nothing watching it — Yazi's own
`entity.lua` reads `raw().reversed` in `Entity:style_rev`, since v25.12.29,
so a rename would land in Yazi's preset first. Losing it fails loudly: the
call raises inside `build`, and `ya.notify` puts the message on screen.

## A theme table cannot hold a gradient

A `[supaline]` field written as a table is parsed by Yazi as a style before
the plugin sees it — `CustomField` in `yazi-config/src/theme/custom_field.rs`
at 26.9.1 is an untagged enum of `StyleFlat` and `String`, tried in that
order — so an arrow inside its `fg` is a colour Yazi's parser does not take.
Measured on 26.9.1 with a `theme.toml` holding
`[supaline] size = { fg = "#0b3d91 -> #7fd4ff" }` and nothing else: Yazi
printed `Failed to parse config`, then
`data did not match any variant of untagged enum CustomField`, then
`Press any key to continue with preset settings...`, and drew nothing until a
key was pressed. What `th.supaline` held after that key was not read. So a
gradient in a theme is the string form and only the string form, and a bold
over a themed gradient is written in the spec, where the layers put it over
the theme's colour.

## A Line's style sits under its spans

A style handed back beside a `ui.Line` becomes the Line's own, and Yazi puts it
*under* each span's: a span's `fg` wins, and a `bold` the Line carries reaches
every span that did not say otherwise. Read off two places at 26.9.1.
`yazi-binding/src/elements/line.rs`, in `TryFrom<Table> for Line`, sets
`line.style.patch(s.style)` on every span of a Line taken into another; and
ratatui's `Cell::set_style` in `ratatui-core/src/buffer/cell.rs` replaces a
cell's colours only where the span's style sets them and inserts the span's
modifiers over what the line put there. Seen on screen by `test/e2e.sh`, in
the `c_bold` check on `permissions`: a bold written for the column, which the
plugin hands back beside the Line and patches into no span, opens a run of
characters drawn in colours of their own. That is what lets `permissions` keep
painting its characters out of `[status]` while a `bold` or a `bg` written for
it lands on all ten.

## How Yazi colours a permission string

Measured by hovering each file of a fixture and reading the status bar's own
permission cell out of `tmux capture-pane -e`, against catppuccin-mocha:

| character | `[status]` style | colour drawn |
| --------- | ---------------- | ------------ |
| `d`, `l` | `perm_type` | `#89b4fa` |
| `r` | `perm_read` | `#f9e2af` |
| `w` | `perm_write` | `#f38ba8` |
| `x`, `s`, `t` | `perm_exec` | `#a6e3a1` |
| `-`, `?` | `perm_sep` | `#7f849c` |

It is the character that decides, not the position: the leading `-` of a
regular file draws in `perm_sep` like any other off bit, and a type character
reaches `perm_type` only by being none of the rest.

The measurement stops at the characters a fixture could produce, and source
closes the rest — read 2026-09-13 off the v26.9.1 tag of the Rust tree.
`Status:perm()` in `yazi-plugin/preset/components/status.lua` branches on the
character exactly as the built-in column does, with `x`, `s`, `S`, `t` and `T`
in one arm, so `S` and `T` — a setuid or sticky bit with the execute bit off,
never produced on screen here and still not — are Yazi's mapping rather than a
guess at it. The same branching places the type characters no fixture had:
`ChaMode::permissions` in `yazi-fs/src/cha/mode.rs` writes one of `dlbcsp-`,
so `b`, `c` and `p` join `d` and `l` in `perm_type`, and a socket's `s` goes
to `perm_exec` with every other `s`. A socket's type character drawing as an
execute bit is Yazi's own behaviour, in its status bar as here, rather than a
divergence to fix.

`?` was produced by `reveal`-ing a path that does not exist: Yazi draws the
row with a dummy `Cha`, and `cha:perm()` answers a type character followed by
nine `?`. Read off one screen, the status bar drew `-?????????` entirely in
`perm_sep` while the plugin's own column drew the nine in `perm_type` — which
is how the missing row in that mapping was found, by a review rather than by
this probe. A dummy row is not exotic: Yazi builds one for any listed entry it
cannot stat, and `Status:perm()` in `yazi-plugin/preset/components/status.lua`
tests `c == "-" or c == "?"` in one branch.

## What a cell with no `style` is drawn in

Four columns side by side, over a `theme.toml` holding nothing but
`[flavor] dark = "catppuccin-mocha"`, read off one screen out of
`tmux capture-pane -e`:

| column | how it was written | on a directory row | on a file row |
| ------ | ------------------ | ------------------ | ------------- |
| `size` | `style = "cyan"` | `[36m` | `[36m` |
| `mtime` | `style = "blue"` | `[34m` | `[34m` |
| `user` | no `style` | `#89b4fa` | `#cdd6f4` |
| `count` | no `style` | `#89b4fa` | `#cdd6f4` |

The bottom two rows move with the row and the top two do not. A cell with no
style of its own is drawn in the colour the flavor gave the file itself --
`#89b4fa` is catppuccin-mocha's directory and `#cdd6f4` its regular file --
while one of the sixteen names is resolved by the terminal, which the flavor
never reaches. `colour.lua` says the same thing from the other end:
`colour.colour("cyan")` is `nil`, because there are no channels behind a name
to interpolate between.

What produces the first behaviour is `colour.layer(nil)` reading as a layer
that says nothing, so that `colour.build` hands back an empty `ui.Style()`
rather than refusing: "no style" arrives at the screen as no style rather
than as a default of the plugin's own. Measured before the layers existed,
against `colour.style(nil)`, which answered the same empty style.

**There is no theme field a size or a timestamp could borrow instead.** Read
off `yazi-config/preset/theme-dark.toml` at v26.9.1: no section means either
of them -- `th.mgr.cwd` is the current directory's path and
`th.status.progress_*` the task gauge -- so a built-in naming one would be as
arbitrary as `cyan` and harder to see. A flavor can still ship a `[supaline]`
section of its own, which outranks a column's definition; that is the route,
not a borrowed field.

## What the two theme pins discriminate

Comment out `ps.sub("theme", build)` and each goes red on its own.

`test/main_spec.lua` sets the section, runs `setup`, changes the section, and
fires `theme`. Changing it *after* setup is what makes the test say anything: a
section that never changed would also pass for a plugin that never subscribed.
`test/e2e.sh` does the same against a real Yazi, rewriting `theme.toml` on
disk, where the unit stub's model cannot be the thing that is wrong.

## A fetcher that returns a boolean

Measured with a throwaway fetcher over a two-file folder.

| what the fetcher did | what Yazi did |
| -------------------- | ------------- |
| returned `true` | task failed, `error converting Lua boolean to function`, `1 left` stuck |
| reported one file twice | task failed, `fetcher reported an unknown or duplicate file`, `1 left` stuck |
| reported one of the two files | task **completed**, count cleared |
| returned a loop | task completed, count cleared |

Row one is nearly invisible from the outside: the body had already run, so the
side effects landed and a column would still have filled in. The last row is
why the stuck count is a measurement and not an anecdote — the same fetcher,
written correctly, clears it.

Row three is where the measurement stops rather than a finding. Yazi makes no
complaint about a file a fetcher never reports, so do not go looking for one,
and do not write a check that waits for it.

## What pins the parent-pane child

`test/main_spec.lua`, "a pane key opts into the pane it names". It calls the
child directly for a row with `in_current = false` — the case `solo()` would
have refused and a child does not.

It pins the code that exists and nothing else. A new column can repeat the trap
and keep the suite green, which is why the other two constraints of that shape
became CI spelling checks instead; this one has no spelling to grep for.
