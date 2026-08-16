# supaline.yazi

A column framework for Yazi's linemode, with eza-style gradient colouring for
file sizes and timestamps, and built-in Git and chezmoi status.

```
 M    85.8M  08/12 12:41   large.bin
 U     2.9M  08/12 12:41   medium.bin
      39.1K  06/20  2025   small.bin
~      300B  01/15  2023   tiny.bin
```

Every column -- built in or written by you -- goes through the same interface,
so extending supaline is not a different kind of work from using it.

## Requirements

- Yazi 26.8.15 or newer
- `git` on `PATH` for the `git` column, `chezmoi` for the `chezmoi` column
- A terminal with 24-bit colour for the gradients (detected automatically;
  without it, columns fall back to a flat colour)

## Installation

```sh
ya pkg add yohkuri/supaline
```

## Setup

`~/.config/yazi/init.lua`:

```lua
require("supaline"):setup {
  linemodes = {
    supaline = {
      { "git" },
      { "size", scale = "log" },
      { "mtime" },
    },
  },
}
```

`~/.config/yazi/yazi.toml`:

```toml
[mgr]
linemode = "supaline"
```

That is all. The `git` and `chezmoi` columns read the filesystem and so need a
fetcher, but supaline declares its own at setup — and only for the providers
your linemodes actually name, so an unused one costs nothing.

To declare them yourself instead — the only way to narrow their `url` patterns
or change their `prio` — pass `fetchers = false` and write them out:

```toml
[[plugin.prepend_fetchers]]
url   = "*"
run   = "supaline git"
group = "supaline-git"

[[plugin.prepend_fetchers]]
url   = "*/"
run   = "supaline git"
group = "supaline-git"
```

Two rules per provider: `*` matches files and `*/` matches directories. Note
`run = "supaline git"` and not `supaline.git` — the provider is chosen by the
argument, because Yazi scopes a plugin's sync state to each *file* and a
separate entry could not reach the state `setup` populates.

## Columns

| Name | Shows | Gradient | Default width |
|---|---|---|---|
| `size` | Human-readable size; entry count for visited directories | yes | 9 |
| `mtime` / `btime` / `atime` | Timestamp, time-of-day this year and the year before that | yes | 11 |
| `permissions` | `drwxr-xr-x` (Unix only) | no | 10 |
| `owner` | `user:group` (Unix only) | no | 12 |
| `count` | Entry count, directories only | no | 5 |
| `git` | Git status sign | no | 1 |
| `chezmoi` | chezmoi status sign | no | 1 |

Per-column options: `width`, `align` (`"left"` / `"right"`), `base` (the
gradient's base colour), `gradient` (`"relative"` / `"off"`), `scale`
(`"linear"` / `"log"`), and `format` for the time columns -- `"smart"` (the
default) or any `os.date` format string.

```lua
{ "mtime", format = "%Y-%m-%d %H:%M", width = 16 }
```

## Gradients

The default follows eza's `--color-scale-mode=gradient`: a value is normalised
against the **extremes of the listing you are currently in**, and that ratio
drives the *lightness* of the column's base colour in Oklab space, leaving hue
and chroma alone so the ramp still belongs to your theme.

```
L = min_luminance + (1 - min_luminance) * exp(-4 * (1 - ratio))
```

```lua
gradient = {
  mode = "relative", -- or "off"
  colors = "auto", -- "truecolor" / "off" to override detection
  scale = "linear", -- or "log"
  steps = 24, -- quantisation buckets
  min_luminance = 50, -- as in eza, 0-100
}
```

Two things are worth knowing:

**Colours are relative to the current directory.** The same file is a different
colour in a folder of small files than in a folder of large ones. That is what
eza does, and it makes the extremes obvious; if you would rather colours meant
the same thing everywhere, there is no absolute mode yet.

**`scale = "log"` is usually what you want for `size`.** A listing spanning
1 KiB to 1 GiB puts a 1 MiB file at ratio 0.001 under linear normalisation --
visually identical to the smallest file in the folder. On a log scale the same
file lands mid-ramp. `linear` remains the default only because it is what eza
does.

We differ from eza in one deliberate way: eza feeds gamma-encoded bytes into a
linear-sRGB constructor, so its hues drift slightly from the colour you asked
for. supaline does a gamma-correct round trip. The shape of the ramp is
identical.

## Writing a column

A column is a name, a function, or a table -- all three collapse to the same
thing.

```lua
require("supaline"):setup {
  linemodes = {
    supaline = {
      { "size", scale = "log" }, -- built in, by name
      function(file) return file.name:sub(1, 1) end, -- single use
      { -- inline, with options
        width = 6,
        render = function(file) return file.cha.is_dir and "dir" or "file" end,
      },
    },
  },
}
```

`render(file, ctx)` runs for every visible row on every frame, so it must stay
O(1). Anything that needs to see the whole folder goes in `stats(files)`, which
runs once per folder and is cached:

```lua
require("supaline").column("nlink", {
  width = 3,
  base = "green",
  stats = function(files)
    local min, max
    for i = 1, #files do
      local n = files[i].cha.nlink
      if n then
        if not min or n < min then
          min = n
        end
        if not max or n > max then
          max = n
        end
      end
    end
    return min and { min = min, max = max } or nil
  end,
  render = function(file, ctx)
    local n = file.cha.nlink
    if not n then
      return "", ctx.base
    end
    return tostring(n), ctx.style(ctx.ratio(n))
  end,
})
```

Register before calling `setup`. `render` may return an `AsLine`, or
`text, style` -- the second form skips building an intermediate Line, which is
why the built-in columns use it.

`ctx` carries:

| Field | |
|---|---|
| `ctx.stats` | whatever this column's `stats` returned, for this folder |
| `ctx.ratio(value)` | `value` normalised to 0..1 against `stats.min`/`stats.max`; `nil` without stats |
| `ctx.style(ratio)` | the ramp colour for that ratio, or the flat base colour when gradients are off |
| `ctx.base` | the flat base style, for cells that should not be graded |
| `ctx.opts` | this column's options table |

## Several linemodes

`linemodes` takes as many as you like, and the `linemode` action switches
between them:

```lua
linemodes = {
  supaline = { { "git" }, { "size", scale = "log" }, { "mtime" } },
  ["supaline-wide"] = { { "permissions" }, { "owner" }, { "size" }, { "btime" } },
}
```

```toml
# keymap.toml
[[mgr.prepend_keymap]]
on  = "L"
run = "linemode supaline-wide"
```

## Git

The `git` column is optional. The default arrangement is to keep using the
official [git.yazi][git-yazi] alongside supaline -- it renders as its own
Linemode child and needs nothing from us. Use the `git` column instead when you
want the status sign aligned with supaline's other columns; then drop git.yazi's
`setup` and fetchers, so the two do not both shell out to `git`.

Status parsing follows git.yazi, and the theme keys are the same, so any flavour
that styles git.yazi styles this column too:

```toml
# theme.toml
[git]
modified_sign = "M"
modified      = { fg = "blue" }
```

Keys: `unknown`, `ignored`, `untracked`, `modified`, `added`, `deleted`,
`updated`, `clean`, each with a matching `*_sign`.

## chezmoi

The `chezmoi` column resolves both trees: your home directory, and the source
tree at `~/.local/share/chezmoi` whose filenames carry attribute prefixes like
`dot_` and `private_`. Rather than decode that naming -- which would break the
moment chezmoi adds an attribute -- supaline asks chezmoi itself, then caches
the answer and refreshes it when a file operation invalidates it.

```
private_dot_config           ~ M         -  08/11 01:53
```

Directories inherit the state of anything beneath them, on both sides.

```toml
# theme.toml
[chezmoi]
modified_sign = "~"
added_sign    = "+"
deleted_sign  = "-"
script_sign   = "!"   # a script `chezmoi apply` will run
managed_sign  = ""    # tracked and up to date; empty by default
modified      = { fg = "yellow" }
```

## Theming supaline's own columns

Gradient base colours come from a `[supaline]` section, as `<column>_base`:

```toml
# theme.toml
[supaline]
size_base  = "#89b4fa"
mtime_base = "#a6e3a1"
```

A `base` option on the column itself wins over the theme.

## Known limitations

- **Gradients are per-directory.** See above.
- **In-place edits can leave a stale ramp.** The statistics cache is keyed on
  the directory and its file count, and dropped on rename/move/delete/trash.
  Writing to a file from outside Yazi without changing the file count leaves the
  extremes stale until you leave and come back.
- **Wide columns are not truncated.** A cell wider than its `width` pushes the
  row out rather than being cut.
- **`permissions` and `owner` are Unix-only.**
- **Fetchers are skipped for virtual files.** Nothing shells out for files that
  do not exist on the local filesystem (`sftp://`, `trash://`), so those rows
  show no Git or chezmoi state. Search listings are not affected: the files
  there are real ones, and both columns work.

## Credits

Git status handling is derived from [yazi-rs/plugins' git.yazi][git-yazi],
Copyright (c) 2023 yazi-rs, MIT licensed — the full notice is in
[LICENSE](LICENSE). The gradient scheme is modelled on [eza][eza]'s
`--color-scale`.

[git-yazi]: https://github.com/yazi-rs/plugins/tree/main/git.yazi
[eza]: https://github.com/eza-community/eza

## License

MIT. See [LICENSE](LICENSE).
