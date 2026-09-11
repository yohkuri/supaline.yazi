# Manual testing

`test/e2e.sh` asserts that the columns are *there*. It cannot tell you they
look right: whether a column is one cell out, whether a truncation lands mid
character, whether two colours fight each other. That is what this is for.

```sh
test/manual.sh
```

It builds a throwaway configuration and fixture with `test/setup.sh` — the same
ones `e2e.sh` uses, so what you see here is what the headless run checks — and
opens Yazi on them. Your own Yazi configuration is neither read nor touched.

Quit with `q`. `test/manual.sh --clean` throws the fixture away.

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
| `m 5` | `seps`       | The separator, `sep = false`, and one of your own |
| `m 6` | `pane_cur`   | `panes = { "current" }`                           |
| `m 7` | `pane_par`   | `panes = { "current", "parent" }`                 |
| `m 8` | `pane_prev`  | `panes = { "current", "preview" }`                |
| `m 9` | `custom`     | A registered user column, and an inline one       |
| `m s` | —            | Yazi's own size linemode                          |
| `m n` | —            | Yazi's own "none"                                 |
| `T`   | —            | Reload the theme                                  |

Colour has leaders of its own, `g` and `c`, and folders of its own to be read
in. They are in [Colour](#colour) below rather than here, because a colour case
is a folder and a linemode together and the table above has no column for that.

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
 link-broken -> nowhere-at-all lrwxr-xr-x octocat:sta…     14B 08/28 01:06
 nested                        drwxr-xr-x octocat:sta…       2 08/28 01:06     2
```

- `link-broken` is `lrwxr-xr-x`, directories are `drwxr-xr-x`, and
  `read-only.txt` is `-r--------`.
- The owner column is twelve cells and holds your own `user:group`, so what to
  look for depends on its length: over twelve it ends in **exactly one** `…`,
  and under twelve it pads with none. Two ellipses in a row was a real bug, and
  `e2e.sh` counts them off the capture now — it reads the cell, holds it
  against `id`, and refuses a second ellipsis or a cut that is not a prefix of
  the name. So this one is covered rather than yours.
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
  or a column one cell short, is a bug. `e2e.sh` asserts that on
  `日本語のファイル名.txt`, the padding after the ellipsis cell included, which
  is the cell a boundary miss takes a space from.
- What is left is `絵文字🎨のなまえ.txt`, on the row below it. The emoji is one
  character and two cells, like the rest of that name, so it goes down the same
  path — but a cluster is not a character, and nothing in the harness measures
  one. Read it against the row above: the two names are the same shape, so the
  four cells should cut in the same places.

### `m 5` — separators

```text
 exactly-1k.bin      bin    1024B│08/28 01:10
```

- `bin` is the extension column, five cells, left-aligned.
- **No gap** between it and the size: that column sets `sep = false`.
- A `│` sits before the date, and no space either side of it.
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
the fixture's own, defined in `setup.sh` beside the m9 columns.

The preview pane keeps whatever its last peek drew, so switching between these
without moving the hover leaves the right pane showing the previous mode. Move
the hover — `j` then `k` — and it catches up. This is Yazi caching the
previewer's output, not a supaline bug.

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
| `c h` | a ramp that turns in hue             | `g 3`      |
| `c g` | a ramp over a background             | `g 3`      |
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

Only `c t` reads the theme. The other five write their endpoints in the spec,
where a `base` or a `ramp` wins over `[supaline]`, so they hold still while
`c 1` to `c 3` swap the file underneath them.

### Before Yazi opens

`manual.sh` prints every ramp the fixture can draw, whole, before it hands over
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
  can ask. `e2e.sh` can measure one step in 64 and an eye cannot see it, so
  what you are judging is how far apart two rows have to be before they read as
  two colours rather than one.
- The number is `ctx.ratio` and both columns carry the same ramp, so the two
  cells on a row are always the same colour. Two that are not mean the ratio
  and the step it chose disagree.

- Scroll. The whole ramp is 64 rows and no terminal shows them all at once;
  the line printed before Yazi opened is the one that does.

`e2e.sh` reads exactly these rows, top to bottom, and takes every step from the
first to wherever the window cuts off — about 38 of the 64. It refuses a step
that goes backwards in any channel, one that repeats the row above it, and a
row whose two cells disagree. So what is left here is only ever visibility: it
already knows the steps are all different, and cannot know whether you can see
that they are.

### `c h` — a ramp that turns

In `g 3`, the same rows on `#0b3d91 -> #ffd400`. Navy to yellow, which crosses
the middle of Oklab rather than climbing one side of it.

Only half the ramp check can be aimed at this one, which is why it is here.
`e2e.sh` refuses a sequence that goes backwards in any colour channel — a
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

### `c g` — a ramp over a background

In `g 3`. The same date twice, on the same ramp. The right one is patched onto
a ground carrying `bg = "#8b0045"`, which `patch` is field-wise so that it
survives under 64 colours that know nothing about it; the left one has no
ground at all and is there to be held against it.

The second column is what makes the first answerable. A single band can only be
compared against the terminal's own ground, which is the reader's and unknown
from here — and that is the very thing the band has to be told apart from. The
background this fixture carried first, `#241a33`, sits 0.02 away in Oklab from
Catppuccin Mocha's `#1e1e2e`: correct, drawn on every row, and invisible to
anyone reading on one. The one there now was chosen by measuring that distance
instead of guessing it, and `setup.sh` says against what.

- The background has to be there on **every** row and the same on every row.
  One row without it is a step that lost its ground.
- The band is 14 cells wide and a date is 11, so three of them carry no text
  and have to be inside the band anyway. `fit` pads before the style is
  applied, which is what puts them there; padding afterwards would band the
  text and leave the rest bare. The width has to be stated for any of this to
  be visible — `mtime` is eleven wide in both of the formats it chooses
  between, so left alone the column is exactly full on every row.
- Legibility is a different question here than anywhere else: the text is being
  read against that ground rather than against the terminal's, so a step that
  was fine in the strip before Yazi opened can be wrong here.

`e2e.sh` reads the first two off the capture — that a band is there, that it is
14 cells rather than 11, and that the column beside it did not pick one up. The
third is a reader's, and is why this is a manual case at all.

### `c s` — log beside linear

In `g 4`. The same size twice, `scale = "log"` then `scale = "linear"`, on one
ramp and with a `┊` between them because they hold the same number. A
different character from `m 5`'s `│`, which is the one `e2e.sh` splits a
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
  directory has no size, so the count is drawn as text and `ctx.base` as its
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
move.

Those colours should be on screen the moment Yazi opens, without pressing
anything: 26.9.1 applies the user's theme before any plugin code runs.

- `T` re-reads the file without changing it, and nothing should move.
- `c 1` to `c 3` change it and reload. Every column built from that section has
  to take the new colour **at once**, a ramp along with a flat one. A colour
  that stays put is the failure this is looking for.
- `c 3` is where the theme grammar runs out, and it is worth seeing rather than
  reading about: `size` and `owner` arrive with backgrounds and `mtime` does
  not. A ramp has to be written as a string — Yazi refuses an array in a custom
  section and takes the whole file with it — and a string has no room for a
  second colour. A ramp *can* have a background; it has to be asked for in the
  spec, which is `c g`.

### Adding a case

A fourth folder is three edits, and a fourth treatment of an existing folder is
two:

1. the folder, in the colour section of `test/setup.sh`;
2. the linemode, in the `linemodes` table of the `init.lua` that file writes;
3. the key, in the `c`/`g` heredoc below it.

Then add it to the `colour_shot` list in `test/e2e.sh`. That does not judge it
— judging is what this document is for — but an unregistered linemode name is
drawn as literal text and one that threw takes the rows with it, and without
that line the first person to find out is whoever next runs `manual.sh`.

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

`colour/` sits alongside them too, and holds nothing that breaks width
arithmetic. Its three folders are distributions rather than awkward cases, one
each for the things a ramp can be asked to do:

| Folder   | What is in it                                                   |
| -------- | --------------------------------------------------------------- |
| `ramp/`  | One file per ramp step, mtimes a minute apart in a past year      |
| `scale/` | 21 files doubling from 1B to 1MB                                  |
| `edge/`  | Four files of equal size and mtime, and two directories           |

The count in `ramp/` is read out of `colour.lua` when the fixture is built, so
"one file per step" stays true if `STEPS` moves. A `setup.sh` that could not
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
- **The theme you left behind does not survive.** `c 1` to `c 3` overwrite
  `config/theme.toml`, and every run rebuilds the whole directory from
  `setup.sh`, so the next one opens on the default whatever you pressed.

## If something looks wrong

Note which linemode, which row, and what you expected. `test/e2e.sh --keep`
leaves its captures in `$TMPDIR/supaline-e2e.<pid>` and prints the path on the
way out — `screen-mN.txt` is the plain text and `color-mN.txt` keeps the escape
sequences, which is how to tell a colour problem from a layout one.

A regression worth keeping should end up in `test/run.lua` if it is about the
logic, or as a check in `test/e2e.sh` if it is about what reaches the screen.
