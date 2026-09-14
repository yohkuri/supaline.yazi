# supaline.yazi

Replace Yazi's linemode with as many columns as you like, in any order, at any
width.

Yazi ships one linemode at a time: size, or mtime, or permissions, never two
together. supaline turns the linemode into a list of columns, and lets you
write your own in Lua. Built-in columns and user-written ones go through the
same interface — neither has a privileged path.

```text
 deep                             drwxr-xr-x octocat:wheel      1 08/27 23:52
 inner-a.txt                      -rw-r--r-- octocat:wheel     1B 12/25  2023
 inner-b.bin                      -rw-r--r-- octocat:wheel   300K 08/27 23:52
```

## Status

The column framework, the built-in columns and the colours are in place. A
column draws in one colour or on a gradient across the folder, and either can
be written in the spec or come from your theme.

Whether supaline ships status columns of its own — version control, dotfile
management — is undecided. Nothing here depends on the answer: such a column
would go through `column.register` like any other.

## Requirements

Yazi **26.9.1 or newer**. Older releases refuse to load the plugin: Yazi
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
| `separator` | `" "`       | Drawn between columns, unless a column opts out. A table carries a colour; see [A coloured separator](#a-coloured-separator). |
| `scale`     | `"linear"`  | Normalisation for columns that take a range. Outranks a column definition's own; see [`scale`](#scale). |
| `band`      | `{ from = 0.35, to = 0.88 }` | The two Oklab lightnesses a one-colour band runs between, `from` at ratio 0. Write it backwards for a light terminal; see [`band`](#band). |
| `order`     | `1400`      | Where the parent/preview child sits among `Linemode`'s children. |

A linemode name is 1 to 20 characters. Yazi keeps its `Linemode` component's
own machinery on the table the linemodes are looked up on, so any name already
on that table is refused — `new`, `redraw`, `padding`, `children_add`,
`children_remove`, `solo`, `none` — as is anything beginning with `_`. The
exception is Yazi's own linemodes: naming one `size`, `mtime`, `btime`,
`atime`, `permissions` or `owner` replaces it, which is allowed.

### Linemode options

A linemode is a list of columns, and may carry one named option alongside them:

```lua
linemodes = {
  wide = {
    "permissions",
    "owner",
    "size",
    "mtime",

    separator = " ",
  },
}
```

| Option      | Default      | Meaning                              |
| ----------- | ------------ | ------------------------------------ |
| `separator` | from `setup` | Overrides the plugin-wide separator, colour and all. |

Those columns are drawn in the **current pane**, which is all Yazi itself ever
does. Whatever else the linemode carries has to be a pane's name or that
option: a key that is neither — `parnet`, `separatorr` — is refused by name
rather than quietly ignored.

#### Different columns per pane

The parent and preview panes are supaline's own addition, and each is asked for
by writing its name on the linemode, with the columns that pane draws:

```lua
linemodes = {
  wide = {
    current = { "permissions", "owner", "size", "mtime" },
    parent  = { "mark" },
  },
}
```

A pane nobody names draws nothing — `preview` above is bare — and that includes
the current pane, for a linemode that names only the other two. The two ways of
saying what the current pane draws do not mix: once any pane is named, a list
left beside it is refused rather than drawn nowhere.

`mark` there is a column of your own rather than one supaline ships. Every
built-in starts at 5 cells and a parent pane has room for one or two, which is
what the width note below is about; three lines register one that narrow:

```lua
supaline.column("mark", {
  width  = 1,
  render = function(file, ctx)
    return file.cha.is_dir and "d" or "f", ctx.style
  end,
})
```

[Writing a column](#writing-a-column) has the rest of what one may do.

Two panes can share one set of columns. Write the list once and hand it to
both: a spec is only ever read, so the same table is safe in two places, and one
written this way is compiled once rather than once per pane.

```lua
local full = { "permissions", "owner", "size", "mtime" }

linemodes = {
  wide = { current = full, preview = full, parent = { "mark" } },
}
```

**Mind the width at the edges.** Handing one list to several panes is what
costs here: Yazi gives the linemode priority over the file name, so what does
not fit is taken out of the name, not out of the columns. The parent pane is an
eighth of the terminal under Yazi's default `ratio`, so:

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

That is what a list per pane is for: give the edges a column that fits them and
leave the built-ins to the pane with the room for them.

### Column specs

A column is written in one of four shapes:

```lua
"size"                                  -- a registered column, by name
{ "size", width = 9, scale = "log" }    -- ... with its options overridden
function(file, ctx) return "..." end    -- render-only shorthand
{ render = fn, stats = fn, width = 6 }  -- an inline definition
```

Every option below but the last can be set on the definition or overridden per
use. `options` is the definition's alone, as is `name` where a definition is
written inline.

| Option      | Default      | Meaning                                                  |
| ----------- | ------------ | -------------------------------------------------------- |
| `render`    | —            | Required. `function(file, ctx)`, run for every visible row. |
| `stats`     | `nil`        | `function(files)`, run once per folder; result reaches `ctx.stats`. |
| `refresh`   | `nil`        | `function()`, run when the linemode is installed and on every `cd`. |
| `width`     | `nil`        | A number, `"auto"`, or `function(stats) -> number`.      |
| `max_width` | `nil`        | Caps the column's width, however it was derived.          |
| `align`     | `"right"`    | `"right"` or `"left"`, within the column's width.        |
| `overflow`  | `"ellipsis"` | `"ellipsis"`, `"clip"`, or `"grow"`.                      |
| `style`     | `nil`        | A colour, a gradient, a style table, a `ui.Style`, `false`, or a function returning one. See [Colours](#colours). |
| `scale`     | from `setup` | `"linear"` or `"log"`. See [`scale`](#scale).             |
| `sep`       | `nil`        | `false` drops the separator before this column; a string or a table replaces it. See [A coloured separator](#a-coloured-separator). |
| `options`   | `nil`        | The definition's alone: the names of the extra keys it reads off `ctx.opts`, each of which it may also default. See [Writing a column](#writing-a-column). |

Any other key is refused by name, on a definition and on a spec alike, and so
is one of those two written where it is not read. Nothing else would say so: a
misspelled `max_widht` is read by nobody, and the column draws at its natural
width without a word about why.

`width = "auto"` measures every file in the folder once per `cd` and takes the
widest result. It is exact, and it costs a pass over the listing; a stated
number costs nothing. `function(stats)` sits in between, for a column whose
width follows from the extremes.

`refresh` is for a column that caches something across rows which is not a
property of any file — the built-in timestamp columns hold the current year, so
`smart` can decide its format with an integer comparison instead of an
`os.date` per cell. Nothing about the folder is passed in, because nothing
about the folder is what changed.

### `ctx`

`render` is handed one context table per column, reused across rows:

| Field          | Meaning                                                     |
| -------------- | ----------------------------------------------------------- |
| `ctx.style`       | What the column is drawn in when there is no value to place: the gradient's low end, or the flat style. |
| `ctx.style_at(r)` | The style for that position on the column's gradient; `ctx.style` when there is none, and for `nil`. |
| `ctx.ratio(v)`    | Where `v` sits between the extremes, 0 to 1, or `nil`. `1` when every value in the folder is the same. |
| `ctx.stats`       | Whatever `stats(files)` returned for the folder being drawn. |
| `ctx.width`       | The width this cell is laid out in, `max_width` already applied, or `nil` for a column that states none. |
| `ctx.opts`        | The options this column declared in `options`, taken from the spec and falling back to the definition. Nothing else the spec carries. |
| `ctx.fg_written`  | Whether any of the three writers put an `fg` there, `false` included. Only a column that paints its own characters needs it; see [How the three combine](#how-the-three-combine). |

`render` may return one renderable, or a value and a style. Returning
`text, style` skips building an intermediate line, and is what the built-in
columns do; a style returned alongside a renderable is applied to it, so a
column that styles its own spans can still set the ground under them.

## Built-in columns

| Column        | Width | Align | Notes                                            |
| ------------- | ----- | ----- | ------------------------------------------------ |
| `size`        | 7     | right | `scale = "log"` by default. Falls back to the entry count for a directory Yazi has already listed. |
| `mtime`       | 11    | right | `ctx.opts.format` takes an `os.date` format; the default is Yazi's own. |
| `btime`       | 11    | right | Birth time.                                       |
| `atime`       | 11    | right | Access time.                                      |
| `permissions` | 10    | left  | Unix only. Coloured from your theme, a character at a time. |
| `owner`       | 12    | left  | `user:group`. Unix only; numeric off this machine. |
| `user`        | 8     | left  | The owning user alone, under the same rule.       |
| `group`       | 8     | left  | The owning group alone, under the same rule.      |
| `count`       | 5     | right | Entry count, directories only.                    |

There is no `ctime` column: Yazi's `Cha` exposes `atime`, `btime` and `mtime`
only.

None of them names a colour. A built-in column leaves its cell unstyled, so it
is drawn in whatever colour your flavor already gives the file row -- the same
as Yazi's own linemodes. Write a `style` in the spec or a field in
`[supaline]` to say otherwise.

`permissions` is the one built-in that colours its own cell, and it takes those
colours from your theme. Each character is drawn in the `[status]` style
Yazi's own status bar would give it -- `perm_type` for the `d` or the `l`,
`perm_read`, `perm_write`, `perm_exec`, and `perm_sep` for every bit that is
off -- so a flavor that already says what a write bit looks like says it in the
linemode too, with nothing to set up. Writing an `fg` for the column turns
that off rather than layering over it: `style = "cyan"` in the spec or
`permissions = "cyan"` in your theme is a flat colour for the whole cell, and
the characters stop being coloured apart. A `bold` or a `bg` is not a colour,
and goes over the characters, whose own colours survive it -- the style going
over them has none, because a colour written for the column would have turned
the per-character painting off in the first place.

`user` and `group` are the two halves of `owner`, each drawn on its own, for a
listing where only one of them is worth the cells. Eight cells is the
traditional passwd limit rather than a measurement; a machine whose names run
past it wants `width = "auto"`.

All three print numbers -- `501`, `20`, `501:20` -- rather than names for a
file that is not on the machine Yazi is running on, an SFTP one say. The names
come from this machine's passwd and group databases, and a remote file's
numbers were minted on the server, where the same number is very likely a
different account. Yazi's own `owner` linemode resolves them regardless, so the
two disagree there on purpose.

On Windows all three are blank for a local file, the way `permissions` is.
Yazi hands Lua a `uid` and a `gid` for every file on every platform -- they are
`u32` rather than optional -- and on Windows both are `0`, so a column that
trusted them would draw `0:0` down the whole listing, which is what Yazi's own
linemode does. A remote file still shows its numbers there: those came off the
server.

Widths are stated rather than measured, so none of them renders the folder
twice. Set `width = "auto"` on any of them to have it fit instead.

`size` and the three times each declare `stats`, and a column that declares
`stats` takes one pass over the listing every time you enter a folder — cheap
next to what Yazi has already done to list it, and the same pass a gradient
reads from.

## Writing a column

Register it before `setup`, then use it by name:

```lua
local supaline = require("supaline")

supaline.column("ext", {
  width = 6,
  align = "left",
  style = "magenta",
  render = function(file, ctx) return file.url.ext or "", ctx.style end,
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

A column that wants a gradient needs a `stats` returning `{ min, max }`, which
is almost always the extremes of one value across the listing.
`supaline.extremes(get)` is that loop — the same one the built-in columns
use — so you write the accessor and nothing else. Values that are `nil` or at
or below zero stay out of the range, so an unevaluated directory cannot drag
the minimum down:

```lua
local function name_length(file) return #file.name end

supaline.column("namelen", {
  width = 4,
  style = "#0b3d91 -> #7fd4ff",
  stats = supaline.extremes(name_length),
  render = function(file, ctx)
    local n = name_length(file)
    return tostring(n), ctx.style_at(ctx.ratio(n))
  end,
})
```

Rounding is yours, not `extremes`'s: whatever `get` hands back is what the
range is measured in, so if `render` rounds a value before `ctx.ratio` sees it,
`get` has to round it the same way or the two disagree about which step a row
is on.

A column that takes an option of its own reads it off `ctx.opts` and names it
in `options`, which is what lets a misspelling of it be refused rather than
ignored. The built-in timestamp columns do exactly this for `format`. A
declared option may be defaulted on the definition and overridden per use, the
way every other key is:

```lua
supaline.column("initials", {
  width = 3,
  options = { "separator" },
  separator = ".",
  render = function(file, ctx)
    return file.name:sub(1, 1) .. ctx.opts.separator, ctx.style
  end,
})
```

`ctx.opts` holds those names and nothing else the spec was written with. A
column's effective width is `ctx.width` rather than `ctx.opts.width`, and the
style it draws in is `ctx.style` rather than `ctx.opts.style`, which would be
the one layer the use site wrote rather than the three merged.

`options` names the keys the column reads, not the keys supaline reads: one
that is a column key already is refused, and so is one supaline answers for
itself — declaring `fetch` would buy the column an option nobody needs and
turn off the refusal below.

It is a plain list, and is checked as one. A gap in it, or a name written as a
key rather than as an entry, is refused rather than read as far as the gap and
ignored past it.

A column cannot define `fetch`. Yazi matches `ya.sync` blocks between its sync
and async interpreters by the position of the call, and a block registered from
your `init.lua` is never replayed on the async side, so a third-party column
cannot own asynchronous state. A column that needs it has to be built into
supaline itself.

## Colours

A column draws in one colour, or on a gradient across the values in the folder,
and may be bold, or on a background, beside either. All of it is one key,
`style`, written the same way in the spec and in your theme.

### `style`

`style` takes a colour string, a table of style keys, a `ui.Style`, `false`, or
a function returning one of those:

```lua
{ "size", style = "#ff8800" }
{ "size", style = "lightcyan" }
{ "size", style = "129" }
{ "size", style = { fg = "cyan", bold = true } }
{ "size", style = ui.Style():fg("cyan"):bold() }
{ "size", style = function() return th.status.perm_read end }
{ "size", style = false }
```

A string is the `fg` alone, and takes anything Yazi's own parser takes:
`"#rrggbb"`, one of the sixteen names, a 256-colour index written as a string,
`"reset"`.

The table takes the keys [a theme's does](#from-the-theme), in the same
spelling — `reversed`, not `reverse` — and here a key that is none of them is
**refused by name**, which is the one thing a theme cannot do for you:

```text
supaline: the `style` of column `size`: `strikethrough` is not a style key.
A style table takes `fg` and `bg`, plus `bold`, `dim`, `italic`, `underline`,
`blink`, `blink_rapid`, `reversed`, `hidden` and `crossed` -- the spelling
`theme.toml` uses, so a style is written the same way in both files.
`crossed` is the spelling
```

`fg` and `bg` take a colour, [a gradient](#a-gradient), or `false` for no
colour. An attribute takes `true`, or `false` for the attribute **taken off**,
which is what the same line means in a theme: a field holds three states —
absent, on, and off — and off strips a `bold` the row beneath already carries.
Write only the keys you mean. Every other key is left to whoever else wrote
one, which [How the three combine](#how-the-three-combine) is about.

A `ui.Style` says what the table says — supaline reads its keys back out of
it, in Yazi's own spelling of the colours — so `ui.Style():fg("cyan"):bold()`
and `{ fg = "cyan", bold = true }` are one style. Mind that its attribute
methods take a removal flag rather than the value: `bold()` adds, and
`bold(true)` takes off. `ui.Style` without the call, and a table with nothing
in it, are both refused, because neither says anything; a list of colours is
refused as a table of keys nobody claims, because a gradient is
[one string](#a-gradient).

`false` is nothing at all: no colour of the column's own, and nothing from the
theme or from the column's definition either. The cell is drawn in whatever
style the row already carries.

A **function** is called each time the linemode is built — at startup, on the
event the flavor arrives with, and on every reload — and what it returns is
read as any of the above; `nil` from one is nothing written. Once per column
each time, never per row. It is how you borrow a colour from the rest of your
theme:

```lua
{ "permissions", style = function() return th.status.perm_read end }
```

Write that one as a value and it comes out wrong, in a way nothing reports.
Yazi merges a flavor *after* your `init.lua` has run, so `th.status.perm_read`
read there is Yazi's preset rather than your flavor's colour — and it stays
the preset, because a spec is re-read on `app:theme` and never evaluated
again.

### A gradient

A gradient is two or more `#rrggbb` endpoints with an arrow between each pair,
written under `fg` or under `bg`. A string on its own is the `fg`:

```lua
{ "size",  style = "#0b3d91 -> #7fd4ff" }
{ "mtime", style = "#0b3d91 -> #ffffff -> #7fd4ff" }
{ "size",  style = { fg = "#0b3d91 -> #7fd4ff", bold = true } }
{ "size",  style = { bg = "#0b3d91 -> #7fd4ff", fg = "#ffffff" } }
```

Where a file lands on it is `ctx.ratio`: its position between the smallest and
largest value in the folder, on the column's `scale`. The colours between the
endpoints are interpolated in Oklab and quantised into 64 styles when the
linemode is built, so a row costs an array index and no colour arithmetic at
all. Everything written beside the gradient — a `bold`, a `bg` under an `fg`
gradient, an `fg` over a `bg` one — is on every one of the 64 steps, and two
gradients on one column land on the same step at the same ratio.

A row with no value to place draws the gradient's **low** end — a directory in
`size`, a file with no mtime.

A folder whose values are all the same has no range to divide by, and every
row in it draws the **high** end. One file on its own is that folder too. Both
ends turn up in a listing that has no spread at all, then: the files at the top
of it, and any row with nothing to place at the bottom.

A column that declares no `stats` has no extremes to place a value between, so
a gradient on one could only ever draw that low end. It is refused rather than
drawn flat, and the refusal names the file the gradient was written in.

**Endpoints have to be `#rrggbb`.** A name and a 256-colour index are whatever
your terminal's palette makes them, and supaline has no way to ask; a gradient
interpolated from a guess would not meet either end. They stay perfectly good
flat colours. **And a gradient is one string**, in the spec as in the theme:
`{ "#0b3d91", "#7fd4ff" }` is a table of keys nobody claims, and is refused as
one.

### A band around one colour

One colour is a gradient too. `<->` spreads it across a fixed band of
lightness — 0.35 to 0.88 in Oklab by default, dark end first:

```lua
{ "size", style = "#7fd4ff <->" }
{ "size", style = { bg = "#7fd4ff <->" } }
```

```toml
[supaline]
size = "#7fd4ff <->"
```

The marker is always there. `"#7fd4ff"` on its own is a flat colour, in a spec
and in a theme alike, and the marker is what says otherwise.

**The hue never moves.** Both ends sit on the same ray out of Oklab's lightness
axis as the colour you wrote, so every step between them does too. As far as
the display allows, that ray is walked by scaling lightness and the two colour
axes together — an exposure change, which keeps the colour's character and not
merely its hue. Past where the display runs out, lightness is bought with
chroma, the one thing that can be given up without turning the colour.
Everything after that is the ramp above: interpolated in Oklab, quantised into
64 steps, indexed per row.

Two things follow, and they are easier read here than found on screen:

- **A dark colour is not a dim band.** Holding the hue caps how far an exposure
  can lighten: `#0b3d91` stops at a lightness of 0.59, well short of the
  `#7fd4ff` a two-ended ramp would have reached. Above that it keeps climbing
  and gives up chroma to do it, so the band arrives at `#c2d9ff` with all 64
  steps distinct.
- **The colour you wrote supplies the hue and nothing else.** It is not put on
  the band anywhere, and unless its own lightness happens to fall between the
  two bounds it is not on the band at all. `#7fd4ff` sits at 0.83 and is drawn
  from `#223f4d` up to `#a8e1ff`; `#000000` and `#ffffff` are both greys with
  no hue to hold, and both give the same `#3a3a3a` to `#d7d7d7`.

Fixed is the point. Two columns spread from different colours put the same
ratio at the same lightness, so a row reads across them — where a band widened
to take in whatever colour was written would leave the darkest cell of one
column and the darkest cell of the next meaning different things.

### `band`

Where those two lightnesses are. `from` is what ratio 0 draws and `to` what
ratio 1 draws, so the pair carries its own direction:

```lua
require("supaline"):setup {
  band = { from = 0.35, to = 0.88 },
  linemodes = { ... },
}
```

Plugin-wide and nowhere else. A band is a claim about what your terminal can
show, and that does not change between one column and the next.

The default assumes a **dark terminal**, and supaline cannot check: Yazi
exposes no background to read, and a flavour that sets none leaves your
terminal's own showing through, which Yazi does not know either. 0.35 is where
a step stops being lighter than the ground it is drawn on, measured against
five common dark backgrounds; 0.88 was chosen by looking.

**On a light terminal, write the pair backwards:**

```lua
band = { from = 0.90, to = 0.35 }
```

Ratio 0 is then the pale end and ratio 1 the dark one, and nothing else
changes. 0.90 is the mirror of the default's own margin — it clears the
darkest light background of the five by the same amount 0.35 clears the
lightest dark one. The other end of that pair is a guess; look at it before
keeping it:

```sh
lua test/ramp.lua --band 0.90,0.35 "#0b3d91 <->"
```

Both numbers are Oklab lightnesses, above 0 and at most 1. Nothing checks them
against each other: two ends at one lightness draw sixty-four steps of one
colour, which is what a flat colour already is, and supaline takes it rather
than guessing you did not mean it — a pair a hair apart draws the same column
and no comparison of two numbers tells them apart.

### `scale`

How a value is turned into that position: `"linear"` spaces the values
themselves evenly, `"log"` spaces their magnitudes evenly.

Three places can say, and the first that does wins:

1. the column's spec — `{ "size", scale = "linear" }`;
2. `scale` in `setup`, which covers every column that did not;
3. the column's own definition — `size` is the only built-in that states one,
   and states `"log"`.

Failing all three it is `"linear"`. That order is what makes the `setup` option
worth having: a listing's sizes span orders of magnitude, so `size` defaults to
`"log"` and a linear ratio would put everything below the largest file on the
floor — but `scale = "linear"` in `setup` still reaches it, which is how you
get eza's own behaviour if you want it. A timestamp needs none of this: a
folder's mtimes sit within a few years of each other.

### From the theme

Yazi's own linemode has no colour of its own, which is why there is a section
to write one in. It is drawn *over* the file list rather than inside it, and
takes whatever style the row already carries — a `[filetype]` rule, the hover
indicator — so a built-in linemode is always the same colour as the filename
beside it, and no field of `theme.toml` names it. A colour per column has
nowhere else to go.

Fields of a `[supaline]` section are named after the columns:

```toml
# ~/.config/yazi/theme.toml
[supaline]
size  = "#0b3d91 -> #7fd4ff"
mtime = "#a6e3a1 <->"
owner = { fg = "green", bold = true }
```

A string is a colour or a gradient; a table is a style, with the keys
[`style`](#style) takes, and it says what the same table says in a spec:
`{ bold = true }` draws the column bold in whatever colour it already has,
from the row, the spec or the column's definition. What a table here cannot
hold is a **gradient**. Yazi parses the table's `fg` as a colour, and
`size = { fg = "#0b3d91 -> #7fd4ff" }` takes the whole `theme.toml` down with
`Failed to parse config` — measured on 26.9.1. A gradient is the string form,
and a bold over a themed gradient is written in the spec, which
[the next section](#how-the-three-combine) allows. A theme cannot hold a list
either: an array in a custom section is refused the same way, which is why a
gradient is written with arrows in both files.

Field names may hold lowercase letters, digits and underscores only. `my-col`
and `MyCol` are refused, and the refusal costs the whole `theme.toml`, so a
column you want themed needs a name of that shape.

Two spellings are worth getting right, because neither is refused. It is
`reversed`, where the `ui.Style` method of the same effect is `reverse()`; and
a key Yazi does not know is **ignored silently**. Measured on 26.9.1:
`reverse = true` and `strikethrough = true` each left the column with no
attribute at all, the rest of the table applied, and nothing was said anywhere
— where a *colour* Yazi cannot parse takes the whole `theme.toml` down with a
message. `reset` is not a key either; write `fg = "reset"`.

### How the three combine

Three places may write a column's style: its definition, the `[supaline]`
field named after it, and the spec. They are read in that order, and **each
key goes to the nearest one that wrote it**. A spec that writes `fg` alone
keeps the theme's `bold` and the definition's `bg`; a theme that writes
`{ bold = true }` alone keeps the colour the definition gave.

```lua
-- with `size = "#0b3d91 -> #7fd4ff"` in your theme:
{ "size", style = { bold = true } }     -- the theme's gradient, bold
{ "size", style = "#ff8800" }           -- flat orange; the gradient is gone
{ "size", style = { fg = false } }      -- no colour at all, the row's own
```

`false` under a key is written, and wins like any value: `fg = false` is no
colour whatever the theme said, and `bold = false` is the attribute taken off
whatever the theme or the row put on. `style = false` is the whole style off
— neither a colour of the column's own nor anything the theme or the
definition wrote — and is not the same as eleven `false`s: an attribute
written `false` strips the row's own, where `style = false` leaves the row as
it is.

A function counts as the spec saying whatever it returns, `false` included;
`nil` from one is nothing written.

`ctx.fg_written` is the one piece of this a column can ask about: whether any
of the three wrote `fg`, `false` included. Which of them wrote it is not there,
because that answer names a file to go and edit and `render` has nothing to do
with one. `permissions` is the column that asks. It colours each character out
of your theme's `[status]` section and steps aside the moment an `fg` is
written for it, wherever it was written — a flat colour for the whole cell, or
no colour — while a `bold` or a `bg` written for it goes over the ten
characters, which keep the reds and greens because the style going over them
carries no colour at all. Over rather than under, so that the key you wrote
wins the way it does everywhere else: a flavor that writes `bold` on
`perm_read` would otherwise take a `style = { bold = false }` back off you.

### A coloured separator

A separator is a string, and a table beside it when a string is not enough:

```lua
separator = " │ "
separator = { " │ ", style = { fg = "#585b70" } }
```

The first element is what to draw and `style` is what to draw it in — a colour
string, a style table, a `ui.Style`, or a function returning one, which is
what a column's [`style`](#style) takes. All three places that take a
separator take the table: `separator` in `setup`, `separator` on a linemode,
and a column's own `sep`.

```lua
require("supaline"):setup {
  separator = { " │ ", style = { fg = "#585b70" } },
  linemodes = {
    detail = {
      "size",
      { "mtime", sep = { " · ", style = "#f38ba8" } },
    },
  },
}
```

A function is called wherever the colours are built, so it follows a theme
reload the way a column's does:

```lua
sep = { " │ ", style = function() return th.status.perm_sep end }
```

There is no gradient. A separator is drawn between two columns rather than on
a file, so it has no value to place between the extremes of the listing, and
one written under its `style` is refused by name.

Whichever level writes a separator supplies both halves of it. A bare string
on a column draws uncoloured even under a linemode that wrote a colour: the
nearer one replaces the farther one whole, which is the one place a nearer
writer takes everything rather than the keys it wrote. `sep = false` still
drops the separator before a column, and `""` still draws nothing between two
of them.

Written wrong it says so, while `setup` runs rather than a session later: a
table with nothing to draw, a key that is neither the text nor `style`, and a
`style` on `""` — which would colour no cells at all — are each refused by
name.

What none of this reaches is the cell at the very start of the row. That space
is Yazi's own, added before the linemode is asked for anything, so a
background running from one edge of the linemode to the other still begins one
cell in.

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
- The cut lands on a grapheme cluster and counts what the terminal draws, so a
  composed emoji is kept whole or dropped whole and a cell never comes back
  wider than its column. It can come back a cell short, and is padded back.
- Statistics and derived widths are cached per folder, keyed partly on the file
  count. A write that changes a file's size without changing the count keeps
  the previous extremes until the next file operation or `cd`.

## License

MIT
