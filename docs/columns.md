# Writing a column

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
belongs in `stats`: it is handed the listing, and every row drawn from it
shares what it returns.

## `ctx`

`render` is handed a context for that column in the folder and pane being
drawn. Rows in one cached folder reuse it; another folder or pane has its own.
Treat the context and its options as read-only. Keeping a reference does not
make it follow navigation: a later folder, or the same one
[measured again](#how-often-stats-runs), gets a new context instead of rebinding
the old one.

| Field          | Meaning                                                     |
| -------------- | ----------------------------------------------------------- |
| `ctx.style`       | What the column is drawn in when there is no value to place: the gradient's low end, or the flat style. |
| `ctx.style_at(r)` | The style for that position on the column's gradient; `ctx.style` when there is none, and for `nil`. |
| `ctx.ratio(v)`    | Where `v` sits between the extremes, 0 to 1, or `nil`. `1` when every value in the folder is the same. |
| `ctx.stats`       | Whatever `stats(files)` returned for the folder being drawn. |
| `ctx.width`       | The width this cell is laid out in, `max_width` already applied, or `nil` for a column that states none. |
| `ctx.opts`        | The options this column declared in `options`, taken from the spec and falling back to the definition. Nothing else the spec carries. |
| `ctx.fg_written`  | Whether any of the three writers put an `fg` there, `false` included. Only a column that paints its own characters needs it; see [How the three combine](styles.md#how-the-three-combine). |

`render` may return one renderable, or a value and a style. Returning
`text, style` skips building an intermediate line, and is what the built-in
columns do; a style returned alongside a renderable is applied to it, so a
column that styles its own spans can still set the ground under them. That
ground is the cell rather than the text: a renderable narrower than its column
is padded inside the style, the way a string is, so a `bg` reaches the cells
the padding added and not only the ones the text filled.

`setup` snapshots the configuration structures it interprets: column lists,
layout options, style tables, separators and named lightness ranges. Editing
those inputs or re-registering a column takes effect on the next successful
`setup`, not on a theme reload. Style functions are still called again on each
theme event, so functions that read `th` continue to follow the theme. Functions
and opaque values under a column's declared options are retained by reference;
supaline does not recursively copy arbitrary user state.

## How often `stats` runs

How often `stats` runs is not something to count on. What it returned is kept
per linemode and pane, so another of either measures the folder again, and the
folder is measured again whenever its listing may have changed — a new file
count, Yazi loading it again, a `cd`, a file operation — and after a `setup`
or theme reload that succeeds. Only a few are kept at a time, so a folder can
also be measured again with nothing about it having changed. It runs inside
the frame that needs it, so keep it to one pass over `files`.

Write `stats` as a function of the files it is handed: one that counts its
calls, or keeps something from the last of them, is measuring supaline's cache
rather than your folder.

## A column on a gradient

A column that wants a gradient needs a `stats` returning
`{ min = ..., max = ... }`, which is almost always the extremes of one value
across the listing. `supaline.extremes(get)` is that loop — the same one the
built-in columns use — so you write the accessor and nothing else. Values that
are `nil` or at or below zero stay out of the range, so an unevaluated
directory cannot drag the minimum down:

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

**Both keys are named ones**, and a `stats` of your own that writes the pair
as a list is the mistake here that draws: `{ lo, hi }` has no `min` and no
`max`, so the extremes stay unset, `ctx.ratio` answers `nil` for every row,
and the column draws flat at its gradient's low end.
[The refusal](styles.md#a-gradient) a gradient gets for a column with no
`stats` does not fire either — this column has one.

supaline says so on screen, once per column, and goes on drawing. It cannot
refuse it: what `stats` returned is knowable only while a pane is being
rendered, and raising there would take the whole screen down rather than the
colour. Only a column drawing a gradient is held to the pair — a `stats` that
derives a width, or that carries something the column's own `render` reads off
`ctx.stats`, owes nobody a `min` and a `max`.

Nor does a `stats` that returns nothing at all. `nil` is how it says the
listing in front of it held no value to measure — the built-in `size` says it
for a directory holding only directories — so it is not a mistake and is not
reported. A gradient over it draws its low end on every row, which is the
honest answer to a listing with no range in it.

**Both have to be numbers**, and that half is not only about the colour.
supaline does arithmetic on the pair from its own folder pass, outside the
containment a column's own functions get, so a `min` that came back as a string
would fail Yazi's whole screen rather than the column. It is checked with the
rest of the pair and said the same way.

## Options of its own

A column that takes an option of its own reads it off `ctx.opts` and names it
in `options`, which is what lets a misspelling of it be refused rather than
ignored. The built-in timestamp columns do exactly this for `format`. A
declared option may be defaulted on the definition and overridden per use, the
way every other key is:

```lua
supaline.column("initials", {
  width = 3,
  options = { "between" },
  between = ".",
  render = function(file, ctx)
    return file.name:sub(1, 1) .. ctx.opts.between, ctx.style
  end,
})
```

`options` may not name a key a column already takes, which is why the example
calls its option `between` rather than `separator`. Any of the keys in
[Column specs](configuration.md#column-specs) is refused there, and the
refusal says which one.

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

What `options` lets through is the value as written, and `render` is the first
thing to read it. A value it cannot use reaches you at the first row, as this
column throwing, with `!` down its length — see
[When a column fails](#when-a-column-fails). `validate` moves that to `setup`:
a check per declared option, handed the value and returning `nil` to take it or
a string saying what is wrong with it. Added to `initials` above:

```lua
validate = {
  between = function(value)
    if type(value) ~= "string" then
      return "must be the string drawn after the initial"
    end
  end,
},
```

`{ "initials", between = false }` is then refused where it was written, the
way a key supaline knows is:

```text
supaline: setup.linemodes.detail[1].between: must be the string drawn after the initial
```

A check is asked about a value somebody wrote and nothing else — each use's
own, and the definition's default whenever the definition is read — so a value
left out never reaches it. A check that raises is refused at the same path, and
so is one that answers anything but `nil` alone or a string saying why:
`return type(value) == "string"` and Lua's usual `return nil, "why"` both read
like a check, and each would get one half of its answers backwards. The
built-in timestamp columns check `format` this way, so `format = "%Q"` is
refused by `setup` rather than drawn as `!`.

## When a column fails

**A column that throws is reported on screen and cannot take Yazi with it.**
`stats`, a `width` that is a function and `render` are all called while a pane
is drawn, and an error raised there fails Yazi's whole screen — file list,
header and status bar together, on every frame, with nothing written anywhere
unless `YAZI_LOG` was set before Yazi started. So all three are called under
`pcall`: the column is named once in a notification, with what it threw in the
log, and everything else on the line goes on drawing. A
cell the column cannot draw at all is filled with `!` so the row keeps its
shape; a `width` function that threw leaves the column unpadded, which is
ragged but readable. None of this applies to a mistake in the configuration —
`setup` runs before anything draws, so what it can refuse it refuses, and Yazi
says so and does not start.

`refresh` is the fourth, and it is contained for its own reason rather than for
that one: it is not called while a pane is drawn, so an error there does not
cost the screen. What it would cost is a silence. It runs from the `cd` handler
and from `setup`, and neither has anybody to raise to — Yazi puts no error out
of an event handler in front of anyone, and `setup` has committed by the time
the hooks run, so a throw there would leave every linemode unregistered and
drawn as its own name. It is reported like the other three, once; the columns
refreshed after the one that threw go on refreshing, and the one that threw
draws with whatever it had cached, which the first time round is nothing at
all.

A `width` function that **returns** a number supaline will not take — `0`,
a negative, `2.5` — is not a throw and is not reported as one. It is the same
refusal a stated `width = 0` gets, arriving too late for `setup` to make it,
so it is said on screen instead: the notification names the column and what
came back, and the column draws unpadded exactly as a throw would leave it.

A `max_width` you stated survives either one, and survives as a cap rather than
as a width: the cell is still cut to it and is still not padded out to it. The
cap never depended on the function that failed.

## Asynchronous state

A column cannot define `fetch`. Yazi matches `ya.sync` blocks between its sync
and async interpreters by the position of the call, and a block registered from
your `init.lua` is never replayed on the async side, so a third-party column
cannot own asynchronous state. A column that needs it has to be built into
supaline itself.
