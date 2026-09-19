# Manual testing

`test/e2e.py` asserts that the columns are *there*. It cannot tell you they
look right: whether a column is one cell out, whether a truncation lands mid
character, whether two colours fight each other. That is what this is for.

```sh
test/manual.py
```

It builds a throwaway configuration and fixture with `test/setup.py` — the same
ones `e2e.py` uses, so what you see here is what the headless run checks — and
opens Yazi on them. Your own Yazi configuration is neither read nor touched.

Quit with `q`. `test/manual.py --clean` throws the fixture away.

## The keys

Yazi's linemode leader is `m`, and it binds only letters, so the digits are
ours. Its own linemodes stay one keystroke away, which is what makes them worth
comparing against.

| Key   | Linemode     | What it isolates                                  |
| ----- | ------------ | ------------------------------------------------- |
| `m 0` | `plain`      | One column. The baseline for `m s`.               |
| `m 1` | `default`    | size + mtime — the everyday case                  |
| `m 2` | `everything` | Every built-in column                             |
| `m 3` | `widths`     | Stated width vs `"auto"` vs `max_width`           |
| `m 4` | `overflow`   | `ellipsis` vs `clip` vs `grow`, string and Line   |
| `m 5` | `seps`       | The separator, `separator = false`, and a colour  |
| `m 6` | `pane_cur`   | The current pane alone                            |
| `m 7` | `pane_par`   | `current` + `parent`, one list between them       |
| `m 8` | `pane_prev`  | `current` + `preview`, one list between them      |
| `m 9` | `custom`     | A registered user column, and an inline one       |
| `m e` | `pane_each`  | A column set per pane                             |
| `m s` | —            | Yazi's own size linemode                          |
| `m n` | —            | Yazi's own "none"                                 |
| `T`   | —            | Reload the theme                                  |

Colour has leaders of its own, `g` and `c`, and folders of its own to be read
in. They are in [Colour](#colour) below rather than here, because a colour case
is a folder and a linemode together and the table above has no column for that.

The columns that are wrong on purpose have a leader too, `b`, and are in
[Broken columns](#broken-columns). Nothing in that section is a linemode
decision; every key in it is a *report* supaline can put on the screen, and the
column under it exists only to cause one.

## What to look for

### `m 0` — one column

Every row ends with a size, right-aligned in seven cells.

```text
 exactly-1k.bin            1024B
 huge.bin                  87.9M
 nested                        2
```

- Directories show an **entry count**, not a size — `nested` is `2`, not a byte
  figure. That is what Yazi's own `size` linemode does, and supaline follows it.
- `never-opened` shows `-` until Yazi has listed it, which happens the moment
  you hover it and the preview reads it. Scroll onto it and watch the `-` turn
  into `1`. Scroll past it once and it stays `1` for the rest of the session.
- Press `m s`. Yazi's own linemode should show the same numbers in the same
  places. If they disagree, supaline is wrong.

### `m 1` — size and mtime

```text
 empty.txt                    0B 08/28 01:10
 exactly-1k.bin            1024B 08/28 01:10
 huge.bin                  87.9M 05/06  2024
```

- One space between the columns.
- A file from this year shows the time; an older one shows the year. **Both
  forms are eleven cells**, so the column below stays straight. If the dates
  jitter left and right, the widths are wrong.
- `large.bin` is from 2020 and `huge.bin` from 2024; `empty.txt` is from today.

### `m 2` — every built-in column

```text
 link-broke… lrwxr-xr-x octocat:sta… octocat  staff        14B 08/28 01:06
 nested      drwxr-xr-x octocat:sta… octocat  staff          2 08/28 01:06     2
```

- `link-broken` is `lrwxr-xr-x`, directories are `drwxr-xr-x`, and
  `read-only.txt` is `-r--------`.
- Those characters are **coloured a character at a time**, out of your own
  theme: the same colours Yazi's status bar gives the hovered file's
  permissions, for the same characters. Hover `link-broken` and hold the
  linemode cell against the status bar at the bottom — the `l`, the `r`s, the
  `w` and the `x`s should match, pair for pair. If your flavor sets no
  `[status]` permission styles the whole cell is plain, which is correct and
  worth telling apart from a cell that lost its colours.
- The owner column is twelve cells and holds your own `user:group`, so what to
  look for depends on its length: over twelve it ends in **exactly one** `…`,
  and under twelve it pads with none. Two ellipses in a row is what can go
  wrong here, and `e2e.py` counts them off the capture — it reads the cell,
  holds it against `id`, and refuses a second ellipsis or a cut that is not a
  prefix of the name. So this one is covered rather than yours.
- `user` and `group` follow it, eight cells each, and hold the two halves of
  what `owner` just said — the three agree or one of them is wrong. They are
  cut on their own lengths rather than on the pair's, so on most machines the
  two of them are whole while `owner` beside them is not.
- `count` is blank for files and a number for directories.
- The file name loses characters to make room. That is Yazi sizing the name
  against the linemode, not supaline overflowing.

### `m 3` — widths

Three columns: `size` stated as 10, `size` measured, and `owner` measured with
a cap of 8.

```text
 exactly-1k.bin           1024B   1024B octocat…
```

- The two size columns hold the same value, but the first is padded to ten
  cells whether the folder needs them or not. The measured one takes **seven**
  here — the width of `1023.4K`, the widest size in this folder.
- Those ten cells are hard to see on most rows: Yazi gives the file name
  whatever the linemode leaves over, so the padding to the *left* of the first
  column looks the same at any width. The row to read is
  `a-very-long-file-name…`, the one Yazi had to truncate — there the name fills
  its budget exactly, so the gap after it is the column's own padding.
- Now enter `nested`, where the widest size is `300K`. The measured column
  should **narrow to four** while the stated one does not move:

  ```text
   inner-b.bin              300K 300K octocat…
  ```

  Come back out and it widens again. Each folder is measured on its own.
- The third column never goes past its cap of eight — `octocat…` here.

### `m 4` — overflow

The same name, four ways, against a column of twelve.

```text
 exactly-1k.bin      exactly-1k.… exactly-1k.b exactly-1k.b exactly-1k.bin
```

- Only the **first** carries an ellipsis.
- The **second** is a hard cut — twelve cells, no ellipsis, nothing appended.
- The **third** is that same cut of a column that hands back a `ui.Line`
  instead of a string, and has to read **identically** to the second. Yazi
  cuts a Line one character shorter than it cuts a string, so this column read
  `exactly-1k.` until the cell asked for that cell back.
- The **fourth** runs past twelve and pushes the file name over.
- Every truncating column must land on a character boundary; half a character,
  or a column one cell short, is a bug. `e2e.py` asserts that on both wide
  names — `日本語のファイル名.txt` and `絵文字🎨のなまえ.txt` — the padding
  after each ellipsis cell included, which is the space a boundary miss takes
  away. They are not one case twice: `🎨` is four bytes where `日` is three and
  both are two cells, so a cut measuring bytes can be right about one name and
  wrong about the other.
- What no name here carries is a grapheme cluster. `❤️` is two characters and
  two cells, which is the trap `AGENTS.md` lists and the reason `column.lua`
  cuts on cluster boundaries at all — but that is pinned in `column_spec.lua`
  and `truncate_spec.lua`, and nothing on this screen draws one.

### `m 5` — separators

```text
 exactly-1k.bin      bin    1024B│08/28 01:10
```

- `bin` is the extension column, five cells, left-aligned.
- **No gap** between it and the size: that column sets `separator = false`.
- A `│` sits before the date, and no space either side of it.
- **That `│` is green**, and nothing else on the row is: it carries a `style`
  of its own rather than taking the row's. Compare it with the pane dividers
  either side of the middle pane, which are the same glyph in the terminal's
  own colour.
- Directories have no extension, so that cell is blank — the columns after it
  should still line up.

### `m 6` to `m 8` — panes

All three draw one column, `mark` — a single `d` or `f`. The middle pane looks
the same in all three; the difference is at the edges.

- `m 6` — the left and right panes carry no columns at all.
- `m 7` — the left pane fills in. `sibling-one` and `sibling-two` get a marker,
  measured against **their own folder**, not this one.
- `m 8` — the right pane fills in. Hover `nested` to give it a folder. Check
  **both** rows: Yazi's `in_preview` is true for the hovered row alone, so a
  pane bug here shows up on the second row and nowhere else.

One cell, and not a built-in, on purpose. Yazi gives the linemode priority over
the file name, and the parent pane is an eighth of the terminal — 21 cells at
170 columns, 10 at 80. `size` and `mtime` together are 19, which leaves nothing
at all for the name; even `mtime` alone does not fit an 80-column parent pane.
Every built-in is 5 to 12 cells wide, so what belongs at the edges is a narrow
marker, and there is no built-in that narrow to demonstrate it with. `mark` is
the fixture's own, defined in `setup.py` beside the m9 columns.

The preview pane keeps whatever its last peek drew, so switching between these
without moving the hover leaves the right pane showing the previous mode. Move
the hover — `j` then `k` — and it catches up. This is Yazi caching the
previewer's output, not a supaline bug.

### `m e` — a column set per pane

A list under each pane's own name, which is the only way the panes can carry
different columns. Compare it against `m 7`, which names the same two panes and
hands them one list between them:

- The **left pane** is identical to `m 7`'s — the same one-cell marker.
- The **middle pane** is not: extension and size, which is what a pane an eighth
  of the terminal has no room for and this one does.
- The **right pane** is bare. Nobody names `preview`, and that is all it takes;
  there is no `false` to write.

The caching note above applies here too, so move the hover before reading the
right pane.

### `m 9` — user-written columns

```text
 exactly-1k.bin      bin   exactly- file
 nested                    nested   dir
```

- `bin` comes from a column registered with `supaline.column(...)`, `exactly-`
  from one clipped to eight cells, and `file` from a bare function in the spec.
- The clipped column shows no ellipsis, and `never-opened` becomes `never-op`.
- All three go through the same interface the built-ins use. If a user column
  behaves differently from a built-in one, that is the bug.

## Colour

Everything above is about where the characters land. This is about what colour
they come out in, and it needs a fixture of its own.

Where a row sits on a ramp is `ctx.ratio`, which normalises against the
extremes of **the folder being drawn**. So the spread of values in front of you
is the whole of what decides which part of a ramp reaches the screen, and the
only way to choose that spread is to choose the folder.

`data/` is a poor instrument for it. Its mtimes land on five of the ramp's 64
steps — four of them in the top third, with a dozen rows sharing the highest —
so no two rows in it are anywhere near adjacent, and the one question worth
putting to a reader cannot be asked in it at all.

Hence folders of colour's own, under `colour/`, and two leaders instead of one.
`g` says **where you are**, which is the spread; `c` says **how it is
coloured**, which is the linemode or the theme.

| Key   | Goes to         | What its values are                       |
| ----- | --------------- | ----------------------------------------- |
| `g 1` | `data/`         | the layout fixture                        |
| `g 2` | `data/nested/`  | a folder whose widest size differs        |
| `g 3` | `colour/ramp/`  | one file per ramp step, a minute apart    |
| `g 4` | `colour/scale/` | sizes doubling from 1B                    |
| `g 5` | `colour/edge/`  | every value the same, and two with none   |

| Key   | Draws                               | Read it in |
| ----- | ----------------------------------- | ---------- |
| `c r` | a ramp climbing in every channel     | `g 3`      |
| `c b` | a band derived from one colour       | `g 3`      |
| `c h` | a ramp that turns in hue             | `g 3`      |
| `c g` | a ramp over a background, and as one | `g 3`      |
| `c a` | a bold over a colour it did not pick | `g 3`      |
| `c s` | the same size, log then linear       | `g 4`      |
| `c e` | a ramp with nothing to spread over   | `g 5`      |
| `c t` | whatever `[supaline]` says           | `g 1`      |

| Key   | Swaps the theme to                        |
| ----- | ----------------------------------------- |
| `c 1` | the default `[supaline]`                  |
| `c 2` | every field moved, the ramp furthest      |
| `c 3` | flat colours carrying backgrounds         |
| `T`   | — reloads without changing the file       |

A `g` key moves you and leaves the colours alone. A `c` key changes the colours
and leaves your folder, your scroll and your hover alone — so two of them
pressed one after the other differ in exactly one thing, which is what makes
them worth putting side by side.

Only `c t` reads the theme. The other six write their colours in the spec,
where a colour written wins over `[supaline]`'s, so they hold still while
`c 1` to `c 3` swap the file underneath them.

### Before Yazi opens

`manual.py` prints every ramp the fixture can draw, whole, before it hands over
the screen: two lines each, one cell per step.

The **solid** line is the gradient by itself. A band, a reversal, or a stretch
where several steps read as one colour shows up there and nowhere else — a
linemode can only draw the steps some folder's values happen to land on, and
even `colour/ramp` needs scrolling to reach all of them.

The **digits** are those same steps carrying text, counting in tens so you can
name the step you stopped being able to read rather than waving at the bottom
of it. That is the question the solid line cannot answer: a ramp whose low end
is as dark as the terminal is a correct gradient and an unreadable column, and
nothing here measures the terminal.

```sh
lua test/ramp.lua "#0b3d91 -> #7fd4ff"    # any ramp you like, no Yazi needed
lua test/ramp.lua --band 0.90,0.35 "#0b3d91 <->"   # ... at other bounds
```

Any Lua will do — it reads `colour.lua` and never asks Yazi anything, so this
is not the one place that wants 5.5.

### `c r` — one row per step

In `g 3`. 64 files, mtimes one minute apart, so consecutive rows land on
consecutive steps.

```text
 step-00.txt  0.00 01/01  2020
 step-01.txt  0.02 01/01  2020
 step-02.txt  0.03 01/01  2020
```

- Every row carries the **same text**. The mtimes sit in a past year, which
  `mtime` draws as `MM/DD  YYYY`, so the only thing that differs down the
  column is the colour. The step number is in the name instead.
- Adjacent rows are exactly one step apart, and this is the question no machine
  can ask. `e2e.py` can measure one step in 64 and an eye cannot see it, so
  what you are judging is how far apart two rows have to be before they read as
  two colours rather than one.
- The number is `ctx.ratio` and both columns carry the same ramp, so the two
  cells on a row are always the same colour. Two that are not mean the ratio
  and the step it chose disagree.

- Scroll. The whole ramp is 64 rows and no terminal shows them all at once;
  the line printed before Yazi opened is the one that does.

`e2e.py` reads exactly these rows, top to bottom, and takes every step from the
first to wherever the window cuts off — about 38 of the 64. It refuses a step
that goes backwards in any channel, one that repeats the row above it, and a
row whose two cells disagree. So what is left here is only ever visibility: it
already knows the steps are all different, and cannot know whether you can see
that they are.

### `c b` — a band nobody wrote the ends of

In `g 3`, the same rows on `#0b3d91 <->`. One colour, spread across the two
fixed lightnesses the fixture's `band.fg` gives it. Press `c r` and `c b` one
after the other — the same rows, the same navy, endpoints chosen by hand and
endpoints derived.

The two columns are the same band asked for two ways: the first takes the name
off the key it is written under, the second writes `<-> both` and names it. They
have to be indistinguishable, and `e2e.py` reads both with one check.

- **Is the spread worth drawing?** `e2e.py` already knows every step differs
  from the one above it, the same way it knows for `c r`. What it cannot ask is
  whether a band this wide separates the rows enough to be read as a gradient,
  or whether the derivation merely produced 64 shades of one colour.
- **The bottom row against your own terminal.** The fixture writes 0.35, the
  pair supaline recommends, picked on the assumption of a dark background —
  and yours is the one it was picked for or it is not. If the first rows are
  sunk into the background, that assumption has just failed here — raise the
  `from` of `band.fg` and look again with
  `lua test/ramp.lua --band 0.40,0.88 "#0b3d91 <->"`, which needs no Yazi.
  Nothing supaline ships applies that pair to you; this screen is where you
  find out what to write instead.
- **A light terminal instead.** Then the band is upside down rather than
  slightly wrong, and the pair goes backwards:
  `band = { fg = { from = 0.90, to = 0.35 } }`. 0.90 is derived, 0.35 is a
  guess inherited from the dark pair, and this is the screen that settles it.
- **The top.** It climbs past where `c r` ends and gives up chroma to get
  there, so it is paler than the navy it came from and paler than `c r`'s own
  last row. Whether that reads as the same colour or as a different one is the
  judgement `c r` does not need, because there both ends were written down.

### `c h` — a ramp that turns

In `g 3`, the same rows on `#0b3d91 -> #ffd400`. Navy to yellow, which crosses
the middle of Oklab rather than climbing one side of it.

Only half the ramp check can be aimed at this one, which is why it is here.
`e2e.py` refuses a sequence that goes backwards in any colour channel — a
property of a ramp climbing all three at once, and this one reverses a channel
on 49 of its 63 transitions, so that half would go red on a gradient that is
perfectly correct. It is not asked. The other half is, and holds for any ramp
that is quantising at all: no step may repeat the row above it.

So the ordering is covered and the *colours* are not, which is the part no
ordering test reaches on any ramp.

- The middle steps pass through a desaturated grey-green. The judgement is
  whether that reads as a colour on the way from one end to the other, or as a
  column that stopped working half way down.
- Both ends still have to be legible, and so does the middle, which is the
  part a two-ended check never looks at.

### `c g` — a ramp over a background, and as one

In `g 3`. The same date twice, on the same ramp. The right one is set on a
ground carrying `bg = "#8b0045"`, which every step is built on so that it
survives under 64 colours that know nothing about it; the left one has no
ground at all and is there to be held against it. Then the file's **name** on a
second ground, `#007a00`, which is that same question asked of a column that
hands a Line back rather than a string. A fourth column carries the ramp under
`bg` instead, with the row's own text over it.

The second column is what makes the first answerable. A single band can only be
compared against the terminal's own ground, which is the reader's and unknown
from here — and that is the very thing the band has to be told apart from. The
background this fixture carried first, `#241a33`, sits 0.02 away in Oklab from
Catppuccin Mocha's `#1e1e2e`: correct, drawn on every row, and invisible to
anyone reading on one. Both of the ones there now were chosen by measuring that
distance instead of guessing it — against seven terminal grounds, the 64 steps
above them, and the colours this fixture itself draws, with the two grounds held
apart from each other as well. `setup.py` writes down all three sets, both sets
of numbers, and that last distance.

- The background has to be there on **every** row and the same on every row.
  One row without it is a step that lost its ground.
- The date's band is 14 cells wide and a date is 11, so three of them carry no
  text and have to be inside the band anyway. Padding before the style is
  applied is what puts them there; padding afterwards would band the text and
  leave the rest bare. The width has to be stated for any of this to be
  visible — `mtime` is eleven wide in both of the formats it chooses between,
  so left alone the column is exactly full on every row.
- The name's band is 16 and every name in this folder is 11, so five cells
  carry no text there. It looks like the same case and is a different one: a
  column that returns a Line is padded by putting a second span beside it, and
  what has to cover that span is the style applied to the Line around both,
  after the text was measured. The two widths differ so that a glance can tell
  which band is which; nothing in `e2e.py` needs them to.
- Legibility is a different question here than anywhere else: the text is being
  read against that ground rather than against the terminal's, so a step that
  was fine in the strip before Yazi opened can be wrong here. The name is drawn
  in the row's own colour rather than the ramp's, so it is the one place to ask
  whether a ground disturbs a foreground nobody chose for it.

- The fourth column is the same question the other way up: the ramp is the
  ground, and the text over it is the row's own — supaline sets no foreground
  there at all, so what the text reads against is whatever your terminal
  supplies. Measured off a capture of this folder, against a white one: the
  ground holds 4.5:1 from the dark end up to ratio `0.40`, crosses at `0.41`,
  and reaches 1.65:1 at `1.00`. Twenty-six of the sixty-four steps read and
  thirty-eight do not. A dark foreground fails at the other end instead, and
  by less — `0.00` is 2.09:1. Neither is a fault: a `bg` gradient takes the
  two endpoints you write, and this pair spans more lightness than one
  unchosen foreground can cross. The endpoints are yours to move, and what
  you are choosing between is which end you can read.

`e2e.py` reads both bands off the capture — that each is there, that it is its
own stated width rather than the width of its text, and that no second column
picked that ground up — and that `ratio`'s background climbs a step per row. It
also refuses a grounded column added here that nothing asks it about, so the
pair above cannot quietly become a list of two out of three. Legibility is a
reader's, twice over, and is why this is a manual case at all.

### `c a` — a bold over someone else's colour

In `g 3`. The same ratio twice on the same ramp, the left one carrying
`bold = true` beside the gradient in its `style`, and `permissions` beside
them with `style = { bold = true }`. A style is merged key by key, so a bold
written next to a colour, or with no colour at all, changes nothing about the
colour: the columns here are meant to differ in exactly one way.

- The two ratio columns have to be the **same colour on every row** and differ
  only in weight. A pair that disagrees on the colour is the bold having got
  into the ramp rather than sitting beside it.
- `permissions` has to keep its reds and greens. It is the only column that
  paints its own cell, so a bold written for it reaches the characters as the
  Line's style under their own rather than inside any of them — a cell that
  came back in one flat colour is the column having stepped aside for
  something that is not a colour.
- Whether bold is **legible** here is the reader's question and the reason this
  is a manual case. A terminal that draws bold as a brighter colour rather than
  a heavier face turns one column of the pair into a different step of the
  ramp, which is not a bug in supaline and is worth knowing about your own
  terminal before reading `c r` beside it.

`e2e.py` reads the first two off the capture — the pair on each row, and a bold
opening a run of differently coloured characters. The third it cannot see.

### `c s` — log beside linear

In `g 4`. The same size twice, `scale = "log"` then `scale = "linear"`, on one
ramp and with a `┊` between them because they hold the same number. A
different character from `m 5`'s `│`, which is the one `e2e.py` splits a
capture on to find the current pane.

```text
 pow-00.bin      1B┊     1B
 pow-01.bin      2B┊     2B
 pow-02.bin      4B┊     4B
 pow-03.bin      8B┊     8B
```

The sizes double, so log spaces them evenly all the way down and linear cannot:
by 8B the left column has moved four steps and the right one has not left the
bottom step at all.

- The left column should read as a gradient over the whole folder. The right
  should read as one colour with a handful of bright rows at the bottom, which
  is what a linear ratio does to a listing whose sizes span orders of
  magnitude — and what `size` would look like without `scale = "log"`.
- This is the pair to look at before changing how a ratio is computed. The
  numbers are identical, so anything you can see is the scale.

### `c e` — nothing to spread over

In `g 5`. Every value in the folder is the same.

```text
 unlisted-a            3 1.00 12/25  2023
 unlisted-b            - 1.00 12/25  2023
 same-a.txt           3B 1.00 12/25  2023
```

- `hi == lo`, so `ratio` answers 1 rather than dividing by nothing, and every
  row with a value draws the ramp's **high** end. Not its low one, and not the
  flat ground underneath it.
- Both directories draw the **low** end, including the one showing a count. A
  directory has no size, so the count is drawn as text and `ctx.style` as its
  colour; the ratio never hears about it. `3` and `3B` read almost the same and
  are coloured from opposite ends, which is the whole reason the pair is there.
- `unlisted-b` shows `-` only because it is a row further down: Yazi lists a
  directory the moment the preview reads it, so the row you arrive hovering has
  a count and the next one does not. The colour is the same either way.
- Nothing on this screen draws a step in between. A gradient here means a ratio
  that divided by a range of zero.

### `c t` — the theme

In `g 1`. Nothing is coloured in the spec, so `size`, `mtime`, `owner` and
`ext` all take whatever `[supaline]` says. This is the only mode the theme keys
move. `mtime` alone carries `style = { bold = true }`: the colour is the
theme's ramp and the weight is the spec's, on the same cell, which is the case
the layers exist for.

Those colours should be on screen the moment Yazi opens, without pressing
anything: 26.9.1 applies the user's theme before any plugin code runs.

- `T` re-reads the file without changing it, and nothing should move.
- `c 1` to `c 3` change it and reload. Every column built from that section has
  to take the new colour **at once**, a ramp along with a flat one. A colour
  that stays put is the failure this is looking for. `mtime` keeps its bold
  through every one of them.
- `c 3` is where the theme grammar runs out, and it is worth seeing rather than
  reading about: `size` and `owner` arrive with backgrounds and `mtime` does
  not. A ramp has to be written as a string — Yazi refuses an array in a custom
  section and takes the whole file with it — and a string has no room for a
  second colour. A ramp *can* have a background; it has to be asked for in the
  spec, which is `c g`.

### Adding a case

A fourth folder is three edits, and a fourth treatment of an existing folder is
two:

1. the folder, in `build_colour` in `test/setup.py`;
2. the linemode, in the `linemodes` table of `test/fixture/init.lua`;
3. the key, in the `c`/`g` section of `test/fixture/keymap.toml`, and a name
   only that folder holds in `FOLDERS` in `test/e2e.py`, so the press can be
   waited on rather than slept through.

Then add it to the colour loop in `test/e2e.py`. That does not judge it
— judging is what this document is for — but an unregistered linemode name is
drawn as literal text and one that threw takes the rows with it, and without
that line the first person to find out is whoever next runs `manual.py`.

A case under `b` takes a different line, and takes it in the second Yazi
`e2e.py` starts for exactly these — the run that is meant to be clean fails for
logging an error at all, and a column that is wrong on purpose makes it log
one. Register the column and send its key in that run's loop. Which columns
that run expects is read out of `test/fixture/init.lua` rather than written in
`e2e.py`, so
a seventh registered and never pressed is a red suite rather than a case
nobody checks. [Broken columns](#broken-columns) has the rest of it.

## Broken columns

Everything above is a column that works. supaline can also put a **report** on
the screen, and not one appears unless a column is written to fail. Until this
section existed, the only way any of them had been read was a throwaway
configuration written beside the code that emits it, which says nothing about
how a report reads against the columns a reader actually has.

There are six a column can cause: the four functions it may write, each
throwing, and the two supaline words itself when a `width` or a `stats` came
back with something it cannot use. A seventh is not a column's and has no key
— a `[supaline]` value supaline refuses reaches the screen from the `theme`
handler, since the user wrote it after `setup` had run.

Hence a third leader. `b` says **what is broken**, and each key under it draws
one column that is wrong on purpose between a `size` and an `mtime` that are
not.

| Key   | The column's fault                          | Read it in |
| ----- | ------------------------------------------- | ---------- |
| `b r` | a `render` that throws                      | `g 1`      |
| `b s` | a `stats` that throws                       | `g 1`      |
| `b w` | a `width` function that throws              | `g 1`      |
| `b u` | a `width` function that returns `0`         | `g 1`      |
| `b g` | a `stats` that finds no extremes, on a ramp | `g 3`      |
| `b f` | two columns counting their own refreshes    | `g 1`      |

`g 6` is a seventh key on the `g` leader: it goes to `broken/`, the folder
that breaks the `refresh` of the column `b f` draws.

The notification is drawn over the top of the preview pane, a second or two
after the key, and times out after twenty seconds. Read one before pressing
the next.

It is the shorter half. What the fault cost the rest of the line, and the
traceback naming the function that threw and the line it threw on, go to the
log instead — `manual.py` prints its path before it opens Yazi, and `--clean`
takes it away with the fixture. Reading the two against each other is the only
way to judge the split, which is the whole of what `report` in `main.lua` is
for. Outside this harness there is no log at all unless `YAZI_LOG` was set
before Yazi started, which is why the notification says the traceback *goes*
to the log rather than that it is in one.

**Each of these is worth one look per session.** `told` in `main.lua` marks a
column against the kind of thing it was told off for — a `stats` with no
extremes, a `width` supaline will not take, or a throw from any of the four
stages — and drops every later report of that kind from that column, which is
what keeps a per-row failure from redrawing its own notification once a second
for ever. So a `b` key pressed twice draws the cells the second time and says
nothing. Restart `manual.py` to see a report again.

The kinds are separate, so one column can still say two different things: a
column whose `stats` found no extremes *and* whose `width` returned `0` reports
both, once each. Each column here is wrong in one way, so each is worth exactly
one sentence — and four of the six share the throw kind, which is why a column
carrying two of them would report only the first.

`e2e.py` presses all of this, in a second Yazi it starts once the run that is
meant to be clean has been torn down. That second run has a log of its own,
which is what lets the first go on failing for logging an error at all: two
logs read for opposite things rather than one taught an exception. It counts
each of the six off both halves — exactly one line in that log, and at least
one appearance on the screen — and that many lines in all, so a report that
went missing, doubled, or never reached the notification is caught without
anybody looking.

What it cannot read is the sentence. Whether a report names the right column,
whether what it says the fault cost matches the cells underneath it, and
whether the two halves of it are split where a reader needs them are what the
rest of this section is for. All three faults found here so far were of that
kind.

### Reading one

A report is two halves and only the shorter of them is on screen, so this takes
two terminals. The fixture goes in the first:

```sh
test/manual.py
```

It prints the log's path before it waits for Enter. Point the second terminal
at that path **before** you press it, because the first report can arrive as
Yazi opens:

```sh
tail -F "${TMPDIR:-/tmp}/supaline-manual/state/yazi/yazi.log" | awk '/ ERROR / { sub(/.*log: "/, ""); sub(/"$/, ""); gsub(/\\n/, "\n"); gsub(/\\t/, "    "); gsub(/\\"/, "\""); print; print ""; fflush() }'
```

One report is one physical line there, with the traceback escaped into it, so a
plain `tail` hands you a paragraph with no line breaks in it. That `awk` undoes
the escaping and puts a blank line between reports. To read them after the fact
instead, drop the `tail -F |` and give `awk` the path.

Then press **one key at a time**, and read the box and the log before the next.
Two reasons, both measured on 26.9.1. Yazi draws **three** notifications at a
time and queues the rest, so six keys pressed together expire faster than they
can be read. And each key changes the linemode, so a batch leaves you unable to
say which box belongs to which row — which is the whole of what you are here to
judge.

`b w` and `b u` are the pair that only works in sequence: their cells are
identical and their sentences are not, so press them in turn and hold the two
boxes against each other.

Yazi truncates the log when it starts, so a restart gives a clean one and there
is nothing to delete between runs. A report missed is a report gone, though —
`told` has already marked that column — and the way back is `q` and
`test/manual.py` again.

### `b r` — a `render` that throws

```text
 exactly-1k.bin           1024B !!!!!! 09/17 17:14
 huge.bin                 87.9M !!!!!! 05/06  2024
```

- The cell is filled with `!` to the column's stated width — six here — rather
  than left blank. A blank reads as a column nobody configured, and the fault
  is the opposite of that.
- `size` and `mtime` either side keep their places. Nothing else on the row
  moves, which is the whole of what the `!` is for.

### `b s` — a `stats` that throws

```text
 exactly-1k.bin           1024B     ok 09/17 17:14
```

- **Nothing on the line says so.** The column's `render` works, so every cell
  comes out as it would have anyway. `stats` is called once per folder and this
  column needs the result for nothing, so the notification is the entire
  signal — which is why it has to carry the column's name.

### `b w` — a `width` function that throws

```text
 nested                        2 dir 09/17 17:14
 exactly-1k.bin           1024B file 09/17 17:14
```

- The column is left with **no width at all** rather than a guessed one, so it
  draws unpadded: `dir` is three cells and `file` is four. Yazi draws the
  linemode flush right, so it is the `size` **before** it that takes up the
  slack and the `mtime` after it that holds its column — measured at 170x40,
  `mtime` at display column 71 on every row, `size` ending at 66 on the rows
  drawing `dir` against 65 on the rows drawing `file`. Both rows end at the
  same column, which is why the capture above is padded to one width: trimmed
  to the name alone it looks as though the `mtime` were the one that moved.
  Ragged and readable is the trade against the stated `width = 0` that `setup`
  refuses outright.

### `b u` — a `width` function that returns `0`

The same two cells, the same ragged rows, and a different sentence. This one is
supaline refusing what the function handed back; `b w` is the function throwing
and supaline reporting it. **Nothing on the screen tells the two apart**, which
is why both keys are here rather than one: press them in turn and read the two
notifications against each other.

### `b g` — a ramp with nothing to place a row in

Read it in `g 3`, where the real `ratio` column beside it climbs through every
step of the same ramp.

- The left column climbs and the right one does not move. That is what a
  `stats` returning no `min` and `max` costs: there is nothing to place a row
  between, so every row draws the ramp's low end and the column is one colour.
- Four dashes rather than a number, because with no extremes there is no ratio
  to format.
- Not a throw. The notification says what `stats` has to return rather than
  what was raised.

### `b f` — a `refresh` that throws

The fourth function a column may write, and the only one supaline calls from
outside Yazi's redraw: it runs at `setup` and again on every `cd`, whichever
linemode is showing. So no linemode key can break it. `b f` only draws it.

Both columns count their own refreshes, and they agree:

```text
 exactly-1k.bin           1024B   5   5 09/17 17:14
```

Press `g 6`, and the folder it takes you to breaks the left one:

```text
 one.txt                     1B   5   6 09/17 17:14
```

- The left column is frozen where it stood and the right one carried on. That
  is the report's two halves on screen — every other column still refreshes,
  and this one goes on drawing whatever it had cached.
- Walk about with `g 1` and `g 2` and the gap widens. The notification does not
  come back, which is `told` doing its job: a hook that throws throws again at
  every folder you walk into, and one sentence is the right number.
- `g 6` is the only thing that arms it and nothing else in the fixture goes
  there. A hook that threw unconditionally would throw during `e2e.py` too.

## The fixture

`data/` is where you start, and it holds the cases that break width
arithmetic.

| Entry                          | Why it is there                              |
| ------------------------------ | -------------------------------------------- |
| `empty.txt`, `tiny.txt`        | `0B` and `1B`                                 |
| `under-1k.bin`, `exactly-1k.bin` | Either side of the 1K boundary              |
| `widest-size.bin`              | Lands in the widest form the size column takes |
| `medium/large/huge.bin`        | 800K, 8.8M, 87.9M, and dates in 2020/2023/2024 |
| `日本語のファイル名.txt`       | Two cells per character                       |
| `絵文字🎨のなまえ.txt`         | An emoji among them                           |
| `a-very-long-...txt`           | Long enough that Yazi truncates the name      |
| `link-ok`, `link-broken`       | A symlink and a broken one                    |
| `read-only.txt`                | Mode 400, for the permissions column          |
| `nested/`                      | A folder for the preview pane                 |
| `never-opened/`                | No entry count until you go in                |

`sibling-one` and `sibling-two` sit alongside `data/` so the parent pane has
rows of its own.

`broken/` sits alongside them as well, and holds three unremarkable files. It
is not there to be looked at: walking into it is what breaks the `refresh` hook
[`b f`](#b-f--a-refresh-that-throws) draws, and nothing else in the fixture
does.

`colour/` sits alongside them too, and holds nothing that breaks width
arithmetic. Its three folders are distributions rather than awkward cases, one
each for the things a ramp can be asked to do:

| Folder   | What is in it                                                   |
| -------- | --------------------------------------------------------------- |
| `ramp/`  | One file per ramp step, mtimes a minute apart in a past year      |
| `scale/` | 21 files doubling from 1B to 1MB                                  |
| `edge/`  | Four files of equal size and mtime, and two directories           |

The count in `ramp/` is read out of `colour.lua` when the fixture is built, so
"one file per step" stays true if `STEPS` moves. A `setup.py` that could not
find it stops rather than building a folder that quietly means something else.

## Not bugs

- **`exactly-1k.bin` shows `1024B`, not `1K`.** Yazi's `ya.readable_size`
  divides only while the value is *greater* than 1024, so 1024 stays put.
  supaline uses Yazi's own formatter on purpose.
- **`link-broken` has a size.** A symlink's own size is the length of the path
  it points at.
- **`,m` and `,s` change the linemode.** Yazi's default sort bindings switch the
  linemode as a side effect, so sorting by size will take you off whichever
  supaline mode you were on. Press `m`-something to get back.
- **The file name gets shorter as you add columns.** Yazi measures the name
  against whatever the linemode occupies.
- **`c c`, `c d`, `c f` and `c n` still copy a path.** The colour keys avoid
  the four sub-keys Yazi binds under `c` rather than shadowing them, so those
  keep working and none of them is a colour case you missed.
- **A `b` key says nothing the second time you press it.** One report per
  column per session is the plugin rather than the fixture — see
  [Broken columns](#broken-columns).
- **`b` is not one of Yazi's keys.** It binds nothing at all in Yazi's own
  `mgr` table — the `b` that is bound is `m b`, its btime linemode — so nothing
  under this leader shadows anything.
- **The theme you left behind does not survive.** `c 1` to `c 3` overwrite
  `config/theme.toml`, and every run rebuilds the whole directory from
  `setup.py`, so the next one opens on the default whatever you pressed.

## If something looks wrong

Note which linemode, which row, and what you expected. `test/e2e.py --keep`
leaves its captures in `$TMPDIR/supaline-e2e.<pid>` and prints the path on the
way out — `screen-mN.txt` is the plain text and `color-mN.txt` keeps the escape
sequences, which is how to tell a colour problem from a layout one.

A regression worth keeping should end up in `test/run.lua` if it is about the
logic, or as a check in `test/e2e.py` if it is about what reaches the screen.
