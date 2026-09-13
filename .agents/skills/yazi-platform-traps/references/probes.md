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
- How Yazi colours a permission string
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
because **a colour cannot be read out of a `ui.Style` from Lua**: `fg` and `bg`
are setters and raise when called with no argument, and `getmetatable` on one
returns `false`. The screen is the only reader. That is also why a flavor
cannot supply a gradient endpoint, which needs `#rrggbb` channels.

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
reaches `perm_type` only by being none of the rest. `S` and `T` — a setuid or
sticky bit with the execute bit off — were never produced, so the built-in
column's mapping sends them to `perm_exec` beside `s` and `t` on the strength
of the pattern rather than a measurement.

`?` was produced by `reveal`-ing a path that does not exist: Yazi draws the
row with a dummy `Cha`, and `cha:perm()` answers a type character followed by
nine `?`. Read off one screen, the status bar drew `-?????????` entirely in
`perm_sep` while the plugin's own column drew the nine in `perm_type` — which
is how the missing row in that mapping was found, by a review rather than by
this probe. A dummy row is not exotic: Yazi builds one for any listed entry it
cannot stat, and `Status:perm()` in `yazi-plugin/preset/components/status.lua`
tests `c == "-" or c == "?"` in one branch.

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

`test/main_spec.lua`, "a list opts into the panes it names". It calls the child
directly for a row with `in_current = false` — the case `solo()` would have
refused and a child does not.

It pins the code that exists and nothing else. A new column can repeat the trap
and keep the suite green, which is why the other two constraints of that shape
became CI spelling checks instead; this one has no spelling to grep for.
