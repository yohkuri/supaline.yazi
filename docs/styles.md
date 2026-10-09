# Styles

A column's style is its colour — flat, or on a gradient across the values in
the folder — and its attributes: bold, italic, underline and the rest a
terminal draws, with a background beside them. All of it is one key, `style`,
written the same way in the spec and in your theme.

## `style`

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
supaline: setup.linemodes.detail[1].style: `strikethrough` is not a style key.
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

The asymmetry between the two is the platform's rather than a choice.
`ui.Style` carries a removal flag for every attribute and nothing of the kind
for either colour — `fg` and `bg` are set or they are absent — so `false` on a
colour can only ever mean *nothing written here*. Inside supaline's own three
layers that is enough, because they are merged before a style is built: a
spec's `bg = false` does drop the `bg` a theme or a definition wrote. It
reaches no further. A colour the **row** already carries — a `[filetype]` rule,
the hover indicator, the `[status]` styles the `permissions` characters are
drawn in — sits under the cell rather than in it, and `false` has no way to
take one of those off. An attribute does: `bold = false` strips a bold from
wherever it came.

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

## A gradient

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

## One colour across a lightness range

One colour is a gradient too. `<->` spreads it across a fixed lightness range
— two Oklab lightnesses you name in [`lightness`](#lightness):

```lua
require("supaline"):setup {
  lightness = { fg = { from = 0.40, to = 0.90 } },
  linemodes = {
    detail = { { "size", style = "#7fd4ff <->" } },
  },
}
```

```toml
[supaline]
size = "#7fd4ff <->"
```

The marker is always there. `"#7fd4ff"` on its own is a flat colour, in a spec
and in a theme alike, and the marker is what says otherwise.

**Which range it asks for is the key it was written under.** A `<->` under `fg`
takes the range called `fg`, one under `bg` the range called `bg`, and a string
on its own is the `fg` key spelled short. To ask for another, name it after the
marker:

```lua
lightness = { fg = { from = 0.40, to = 0.90 }, bg = { from = 0.15, to = 0.40 } },
...
{ "size", style = { fg = "#7fd4ff <->", bg = "#7fd4ff <->" } }  -- two ranges
{ "size", style = "#7fd4ff <-> bg" }                            -- the `bg` one under `fg`
```

**A `<->` with no range behind it is refused**, and the message carries a pair
to paste. Nothing is filled in for you — see [`lightness`](#lightness) for why.

**The hue never moves.** Both ends sit on the same ray out of Oklab's lightness
axis as the colour you wrote, so every step between them does too. As far as
the display allows, that ray is walked by scaling lightness and the two colour
axes together — an exposure change, which keeps the colour's character and not
merely its hue. Past where the display runs out, lightness is bought with
chroma, the one thing that can be given up without turning the colour.
Everything after that is the ramp above: interpolated in Oklab, quantised into
64 steps, indexed per row.

Two things follow, and they are easier read here than found on screen:

- **A dark colour is not a dim spread.** Holding the hue caps how far an
  exposure can lighten: `#0b3d91` stops at a lightness of 0.59, well short of
  the `#7fd4ff` a two-ended ramp would have reached. Above that it keeps
  climbing and gives up chroma to do it, so the spread arrives at `#ccdfff`
  with all 64 steps distinct.
- **The colour you wrote supplies the hue and nothing else.** It is not put on
  the spread anywhere, and unless its own lightness happens to fall between the
  two ends it is not on the spread at all. `#7fd4ff` sits at 0.83 and is drawn
  from `#2a4c5e` up to `#b7e6ff`; `#000000` and `#ffffff` are both greys with
  no hue to hold, and both give the same `#484848` to `#dedede`.

Fixed is the point. Two columns spread from different colours put the same
ratio at the same lightness, so a row reads across them — where a range widened
to take in whatever colour was written would leave the darkest cell of one
column and the darkest cell of the next meaning different things.

Two columns on *different* ranges are two columns you can no longer read across,
and naming a second range is how you say you meant that. `bg` is the clearest
case: it is drawn beneath the row's own text rather than on the ground, so it is
not the same question and not the same pair. Naming a range says a second place
is being drawn to — not that your terminal changed between one column and the
next.

## `lightness`

Where those two lightnesses are. Lightness ranges live here by name, and a
`<->` asks for one of them:

```lua
require("supaline"):setup {
  lightness = {
    fg  = { from = 0.40, to = 0.90 },
    bg  = { from = 0.15, to = 0.40 },
    dim = { from = 0.30, to = 0.55 },
  },
  linemodes = { ... },
}
```

`from` is what ratio 0 draws and `to` what ratio 1 draws, so each pair carries
its own direction. Names hold lowercase letters, digits and `_` — the same
characters a column's name holds, so there is one shape to learn rather than
two. The length limit on a column's name is not here, because that one is
Yazi's field parser and nothing parses a range name. `from` and `to` are a
range's own keys and cannot be a range's name.

`fg` and `bg` are ordinary names with one convenience: they are what the two
style keys are called, so a `<->` written under `fg` asks for `fg` without
saying so. Any other name is asked for after the marker, `"#7fd4ff <-> dim"`.

**Nothing is defined for you.** A `<->` with no range behind it is refused,
and the message carries a pair to paste:

```lua
lightness = { fg = { from = 0.40, to = 0.90 } }
```

### Why there is no default

Those two numbers are a claim about the **ground the column is drawn on** — and
that ground is yours. Yazi exposes no background to read, and a flavour that
sets none leaves your terminal's own showing through, which Yazi does not know
either. Beyond the ground, the hue of it, the calibration of your display and
how much contrast your eyes want at that size are all yours as well.

The pair above is what supaline measured, and measuring it took a population
rather than a person: 0.40 clears the lightest of five common dark backgrounds
by a tenth of the lightness scale — merely lighter than the ground is not
enough, and a navy step at 0.35 sinks into Solarized dark's blue — and 0.90 was
chosen by looking at nine hues on those five: at 0.95 red, orange and yellow
pale into one another. That makes it a good place to start and a poor thing to
apply to someone who never asked for it — a column would be drawn at a pair
nobody chose, and nothing on screen would say it was a knob. So supaline
recommends it, and you write it.

### Adjusting it

Look at a pair before you keep it. This needs no Yazi and no restart:

```sh
lua test/ramp.lua --lightness 0.40,0.90 "#0b3d91 <->"
```

The solid line is the spread itself — a stretch where several steps read as one
colour shows up here and nowhere else. The digits under it are the same steps
carrying text, which is the question a column actually asks: the low end has to
be legible against your ground, not merely different from it.

Move `from` up if the dark end sinks into your background, and `to` down if the
light end glares. Both numbers are Oklab lightnesses, above 0 and at most 1.

**On a light terminal, write the pair backwards:**

```lua
lightness = { fg = { from = 0.90, to = 0.40 } }
```

Ratio 0 is then the pale end and ratio 1 the dark one, and nothing else
changes: these are the dark pair's sixty-four colours in the other order. On
white and on Solarized light, 0.90 reads, though narrowly — 0.85 reads easily,
and is where to move `from` if 0.90 does not — and 0.35 at the dark end muddies
red, orange and yellow together.

A range under `bg` wants a different pair rather than a reversed one: it is
drawn *beneath* the row's own text, so both of its ends have to keep that text
readable, and supaline can see neither the text nor the ground. There is no
recommendation for that one at all — `ramp.lua` and your own screen are the
whole of the method.

Nothing checks the two ends against each other: two ends at one lightness draw
sixty-four steps of one colour, which is what a flat colour already is, and
supaline takes it rather than guessing you did not mean it — a pair a hair
apart draws the same column and no comparison of two numbers tells them apart.

## `scale`

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

## From the theme

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

A **spread** in a theme asks for the lightness range called `fg`, because a
field holds one value and a bare string is the `fg` key: `mtime` above is drawn
at whatever `lightness.fg` in your `setup` says, and is refused if you defined
none. That is the division the two files are for — a flavour knows its own hues,
and only you know the ground they will be drawn on.

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

An **empty string** is nothing written: `size = ""` leaves the column exactly
as it was, so a field can be cleared rather than deleted — which is what you
want in a file a flavor also writes. That spelling is the theme's alone. In a
spec `style = ""` is a colour Yazi does not accept and is refused as one, since
a spec that wants no colour has `false` and has leaving the key out.

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

## How the three combine

Three places may write a column's style: its definition, the `[supaline]`
field named after it, and the spec. They are read in that order, and **each
key goes to the nearest one that wrote it**. A spec that writes `fg` alone
keeps the theme's `bold` and the definition's `bg`; a theme that writes
`{ bold = true }` alone keeps the colour the definition gave.

A column written inline **is** its own definition, so its style is the
farthest of the three and a `[supaline]` field named after it reaches the
colour it chose, exactly as one reaches a column `register` declared. Only a
use of a column defined elsewhere, `"size"` or `{ "size", ... }`, writes the
nearest layer.

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

A function counts as whichever of the three wrote it saying whatever it
returns, `false` included; `nil` from one is nothing written. It is called
once per column each time the styles are built — at `setup`, and again on
every theme reload — never per row.

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

## A coloured separator

A separator is a string, and a table beside it when a string is not enough:

```lua
separator = " │ "
separator = { " │ ", style = { fg = "#585b70" } }
```

The first element is what to draw and `style` is what to draw it in — a colour
string, a style table, a `ui.Style`, or a function returning one, which is
what a column's [`style`](#style) takes. All three places that take a
separator take the table, and all three call it `separator`: in `setup`, on a
linemode, and on a column.

```lua
require("supaline"):setup {
  separator = { " │ ", style = { fg = "#585b70" } },
  linemodes = {
    detail = {
      "size",
      { "mtime", separator = { " · ", style = "#f38ba8" } },
    },
  },
}
```

A function is called wherever the colours are built, so it follows a theme
reload the way a column's does:

```lua
separator = { " │ ", style = function() return th.status.perm_sep end }
```

There is no gradient. A separator is drawn between two columns rather than on
a file, so it has no value to place between the extremes of the listing, and
one written under its `style` is refused by name.

Whichever level writes a separator supplies both halves of it. A bare string
on a column draws uncoloured even under a linemode that wrote a colour: the
nearer one replaces the farther one whole, which is the one place a nearer
writer takes everything rather than the keys it wrote. `separator = false`
still drops the separator before a column, and `""` still draws nothing
between two of them.

Written wrong it says so, while `setup` runs rather than a session later: a
table with nothing to draw, a key that is neither the text nor `style`, and a
`style` on `""` — which would colour no cells at all — are each refused by
name.

A separator is drawn *before* its column, so the first column of a pane has
nothing before it and is drawn without one. A `separator` written there is
refused rather than dropped in silence, and each pane has its own first
column: a column written first under `parent` is refused for that, wherever it
sits in the current pane's list. `separator = false` is accepted there — it
asks for nothing, which is what index 1 gets either way — and a column
*registered* with a `separator` of its own may still head a linemode, since
only what a linemode spec writes is refused.

What none of this reaches is the cell at the very start of the row. That space
is Yazi's own, added before the linemode is asked for anything, so a
background running from one edge of the linemode to the other still begins one
cell in.
