# supaline.yazi

Replace Yazi's linemode with as many columns as you like, in any order, at any
width.

Yazi ships one linemode at a time: size, or mtime, or permissions, never two
together. supaline turns the linemode into a list of columns, and lets you
write your own in Lua. Built-in columns and user-written ones go through the
same interface — neither has a privileged path.

```
 deep                             drwxr-xr-x yohkuri:wheel      1 08/27 23:52
 inner-a.txt                      -rw-r--r-- yohkuri:wheel     1B 12/25  2023
 inner-b.bin                      -rw-r--r-- yohkuri:wheel   300K 08/27 23:52
```

## Status

The column framework and the built-in columns are in place. **Gradients** are
not: columns draw flat, in their base colour. The eza-style Oklab ramp lands
next, and the `base` and `scale` options are already wired for it.

Whether supaline ships status columns of its own — version control, dotfile
management — is undecided. Nothing here depends on the answer: such a column
would go through `column.register` like any other.

## Requirements

Yazi **26.8.15 or newer**. Older releases refuse to load the plugin: Yazi
enforces the `--- @since` annotation, and the fetcher and theme APIs this is
written against did not exist before.

## Installation

```sh
ya pkg add yohkuri/supaline
```

## Quick start

```toml
# ~/.config/yazi/yazi.toml
[mgr]
linemode = "detail"
```

```lua
-- ~/.config/yazi/init.lua
require("supaline"):setup {
  linemodes = {
    detail = { "size", "mtime" },
  },
}
```

Every key of `linemodes` becomes a real linemode, so Yazi's own `linemode`
action switches between them:

```toml
# ~/.config/yazi/keymap.toml
[[mgr.prepend_keymap]]
on   = [ "m", "d" ]
run  = "linemode detail"
desc = "Linemode: size and mtime"
```

## Configuration

### `setup` options

| Option      | Default     | Meaning                                              |
| ----------- | ----------- | ---------------------------------------------------- |
| `linemodes` | —           | Required. Map of linemode name to a list of columns. |
| `separator` | `" "`       | Drawn between columns, unless a column opts out.     |
| `scale`     | `"linear"`  | Default normalisation for columns that take a range. |
| `order`     | `1400`      | Where the parent/preview child sits among `Linemode`'s children. |

A linemode name is 1 to 20 characters. Yazi keeps its `Linemode` component's
own machinery on the table the linemodes are looked up on, so any name already
on that table is refused — `new`, `redraw`, `padding`, `children_add`,
`children_remove`, `solo`, `none` — as is anything beginning with `_`. The
exception is Yazi's own linemodes: naming one `size`, `mtime`, `btime`,
`atime`, `permissions` or `owner` replaces it, which is allowed.

### Linemode options

A linemode is a list of columns, and may carry named options alongside them:

```lua
linemodes = {
  wide = {
    "permissions",
    "owner",
    "size",
    "mtime",

    panes     = { "current", "parent", "preview" },
    separator = " ",
  },
}
```

| Option      | Default       | Meaning                                       |
| ----------- | ------------- | --------------------------------------------- |
| `panes`     | `{ "current" }` | Which panes this linemode draws in.         |
| `separator` | from `setup`  | Overrides the plugin-wide separator.          |

`panes` is a list of pane names:

```lua
panes = { "current" }                       -- the default, and all Yazi itself does
panes = { "current", "preview" }            -- any combination
panes = { "current", "parent", "preview" }  -- every pane
```

Yazi only ever draws a linemode in the current pane; the parent and preview
panes are supaline's own addition. Leaving `current` off the list is allowed and
means what it says — the current pane draws nothing for that linemode.

**Mind the width at the edges.** `panes` applies the whole column set to every
pane it names, and Yazi gives the linemode priority over the file name: what
does not fit is taken out of the name, not out of the columns. The parent pane
is an eighth of the terminal under Yazi's default `ratio`, so:

| Terminal | Parent pane |
| -------- | ----------- |
| 170      | 21 cells    |
| 120      | 15 cells    |
| 80       | 10 cells    |

`size` (7) and `mtime` (11) come to 19 cells with the separator, which leaves an
80-column parent pane nothing for the name and a 170-column one a cell or two.
Every built-in column is 5 to 12 cells wide. The parent pane is worth turning on
for a **narrow marker** — one or two cells — and not for the built-ins as they
stand. The preview pane is three eighths, so it is far less tight.

### Column specs

A column is written in one of four shapes:

```lua
"size"                                  -- a registered column, by name
{ "size", width = 9, scale = "log" }    -- ... with its options overridden
function(file, ctx) return "..." end    -- render-only shorthand
{ render = fn, stats = fn, width = 6 }  -- an inline definition
```

Any option below can be set on the definition or overridden per use.

| Option      | Default      | Meaning                                                  |
| ----------- | ------------ | -------------------------------------------------------- |
| `render`    | —            | Required. `function(file, ctx)`, run for every visible row. |
| `stats`     | `nil`        | `function(files)`, run once per folder; result reaches `ctx.stats`. |
| `width`     | `nil`        | A number, `"auto"`, or `function(stats) -> number`.      |
| `max_width` | `nil`        | Caps the column's width, however it was derived.          |
| `align`     | `"right"`    | `"right"` or `"left"`, within the column's width.        |
| `overflow`  | `"ellipsis"` | `"ellipsis"`, `"clip"`, or `"grow"`.                      |
| `base`      | `nil`        | Base colour: `"#rrggbb"` or an ANSI colour name.         |
| `scale`     | from `setup` | `"linear"` or `"log"`.                                    |
| `sep`       | `nil`        | `false` drops the separator before this column; a string replaces it. |

`width = "auto"` measures every file in the folder once per `cd` and takes the
widest result. It is exact, and it costs a pass over the listing; a stated
number costs nothing. `function(stats)` sits in between, for a column whose
width follows from the extremes.

### `ctx`

`render` is handed one context table per column, reused across rows:

| Field          | Meaning                                                     |
| -------------- | ----------------------------------------------------------- |
| `ctx.base`     | The column's base style.                                     |
| `ctx.stats`    | Whatever `stats(files)` returned for the folder being drawn. |
| `ctx.opts`     | The options written in the spec, verbatim.                   |
| `ctx.ratio(v)` | Where `v` sits between the extremes, 0 to 1, or `nil`.       |
| `ctx.style(r)` | The style for a ratio. Flat for now; the gradient hooks in here. |

`render` may return one renderable, or `text, style` — the second form skips
building an intermediate line, and is what the built-in columns do.

## Built-in columns

| Column        | Width | Align | Notes                                            |
| ------------- | ----- | ----- | ------------------------------------------------ |
| `size`        | 7     | right | Falls back to the entry count for a directory Yazi has already listed. |
| `mtime`       | 11    | right | `ctx.opts.format` takes an `os.date` format; the default is Yazi's own. |
| `btime`       | 11    | right | Birth time.                                       |
| `atime`       | 11    | right | Access time.                                      |
| `permissions` | 10    | left  | Unix only.                                        |
| `owner`       | 12    | left  | `user:group`. Unix only.                          |
| `count`       | 5     | right | Entry count, directories only.                    |

There is no `ctime` column: Yazi's `Cha` exposes `atime`, `btime` and `mtime`
only.

Widths are stated rather than measured, so none of them renders the folder
twice. Set `width = "auto"` on any of them to have it fit instead.

They do each declare `stats`, and a column that declares `stats` takes one pass
over the listing every time you enter a folder — cheap next to what Yazi has
already done to list it, and the same pass the gradient will read from.

## Writing a column

Register it before `setup`, then use it by name:

```lua
local supaline = require("supaline")

supaline.column("ext", {
  width = 6,
  align = "left",
  base  = "magenta",
  render = function(file, ctx) return file.url.ext or "", ctx.base end,
})

supaline:setup {
  linemodes = {
    detail = { "ext", "size", "mtime" },
  },
}
```

`render` runs for every visible row on every frame, so keep it O(1) and let it
allocate as little as possible. Anything that has to look at the whole folder
belongs in `stats`, which runs once per folder and is cached.

A column cannot define `fetch`. Yazi matches `ya.sync` blocks between its sync
and async interpreters by the position of the call, and a block registered from
your `init.lua` is never replayed on the async side, so a third-party column
cannot own asynchronous state. A column that needs it has to be built into
supaline itself.

## Theming

Base colours come from a `[supaline]` section, whose fields are named after the
columns:

```toml
# ~/.config/yazi/theme.toml
[supaline]
size  = { fg = "#ff8800" }
mtime = "green"
```

Either shape works: a style table, or a colour string. A `base` written in the
spec wins over the theme.

## Caveats

- **The preview pane repaints on its next peek, not on a linemode switch.**
  Yazi caches the previewer's output, so a linemode change reaches the preview
  pane when the hover moves — or immediately, on `app:theme`.
- **Yazi's default `,` bindings change the linemode as a side effect.** `,m`
  sorts by mtime *and* switches to the `mtime` linemode. Rebind them if you
  want your own linemode to stay put:

  ```toml
  [mgr]
  prepend_keymap = [
    { on = [ ",", "m" ], run = "sort mtime --reverse=no" },
  ]
  ```

- **A cell wider than its column is truncated, not allowed to push.** Yazi
  sizes the file name against whatever the linemode takes, so an overlong cell
  would otherwise eat the name. Use `overflow = "grow"` to opt out.
- Statistics and derived widths are cached per folder, keyed partly on the file
  count. A write that changes a file's size without changing the count keeps
  the previous extremes until the next file operation or `cd`.

## License

MIT
