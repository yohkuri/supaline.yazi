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
  and under twelve it pads with none. Two ellipses in a row was a real bug.
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
- Look at `日本語のファイル名.txt`. Every truncating column must land on a
  character boundary; half a character, or a column one cell short, is a bug.

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

### `T` — the theme

The fixture sets a `[supaline]` section: size orange, owner blue, extension
magenta, and mtime **a ramp** — `#0b3d91 -> #7fd4ff`, dark blue to pale.

Those colours should already be on screen when Yazi opens, without pressing
anything: Yazi applies the user's theme before the plugin runs.

`e2e.sh` pins the ramp's two ends, and that the steps between them climb with
the date: it reads the colour out of each row's mtime cell and refuses a
sequence that runs backwards or that never leaves the ends. What it cannot ask
is whether the climb is one a reader can see. These are the rows to compare on
`m 1`, listed oldest first rather than in the order they appear:

```text
 large.bin                  8.8M 01/02  2020    <- the ramp's low end
 medium.bin                 800K 12/25  2023
 huge.bin                  87.9M 05/06  2024
 under-1k.bin              1023B 01/01 00:00
 empty.txt                    0B 09/09 12:34    <- its high end
```

- Adjacent rows have to be tellable apart at a glance. A ramp is quantised
  into 64 steps, and one step is a difference the check above can measure and
  an eye cannot; what you are judging is whether the rows a year apart read as
  different colours rather than as the same one.
- Every step has to stay legible against the background. A ramp whose low end
  is as dark as the terminal is a correct gradient and an unreadable column, and
  nothing here measures the terminal.
- There is no colour for "no value" on screen here, because every file has an
  mtime. A column whose value is missing draws the ramp's **low** end — that is
  what `size` does for a directory it has not evaluated.

The reload is worth doing by hand as well. Edit `[supaline]` in
`$TMPDIR/supaline-manual/config/theme.toml` and press `T`. Every column built
from that section should take the new colour at once, a ramp along with a flat
one. A colour that stays put is the failure this is looking for, and `e2e.sh`
pins both shapes by rewriting the file and sending `app:theme` itself.

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

## If something looks wrong

Note which linemode, which row, and what you expected. `test/e2e.sh --keep`
leaves its captures in `$TMPDIR/supaline-e2e.<pid>` and prints the path on the
way out — `screen-mN.txt` is the plain text and `color-mN.txt` keeps the escape
sequences, which is how to tell a colour problem from a layout one.

A regression worth keeping should end up in `test/run.lua` if it is about the
logic, or as a check in `test/e2e.sh` if it is about what reaches the screen.
