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
| `m 4` | `overflow`   | `ellipsis` vs `clip` vs `grow`                    |
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

```
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

```
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

```
 link-broken -> nowhere-at-all lrwxr-xr-x yohkuri:sta…     14B 08/28 01:06
 nested                        drwxr-xr-x yohkuri:sta…       2 08/28 01:06     2
```

- `link-broken` is `lrwxr-xr-x`, directories are `drwxr-xr-x`, and
  `read-only.txt` is `-r--------`.
- The owner column is twelve cells and `yohkuri:staff` is thirteen, so it ends
  in **exactly one** `…`. Two ellipses in a row was a real bug.
- `count` is blank for files and a number for directories.
- The file name loses characters to make room. That is Yazi sizing the name
  against the linemode, not supaline overflowing.

### `m 3` — widths

Three columns: `size` stated as 10, `size` measured, and `owner` measured with
a cap of 8.

```
 exactly-1k.bin           1024B   1024B yohkuri…
```

- The two size columns hold the same value, but the first is padded to ten
  cells whether the folder needs them or not. The measured one takes **seven**
  here — the width of `1023.4K`, the widest size in this folder.
- Now enter `nested`, where the widest size is `300K`. The measured column
  should **narrow to four** while the stated one does not move:

  ```
   inner-b.bin              300K 300K yohkuri…
  ```

  Come back out and it widens again. Each folder is measured on its own.
- The third column stops at eight: `yohkuri…`.

### `m 4` — overflow

The same name, three ways, against a column of twelve.

```
 exactly-1k.bin      exactly-1k.… exactly-1k.b exactly-1k.bin
```

- Only the **first** carries an ellipsis.
- The **second** is a hard cut — twelve cells, no ellipsis, nothing appended.
- The **third** runs past twelve and pushes the file name over.
- Look at `日本語のファイル名.txt`. Both truncating columns must land on a
  character boundary; half a character, or a column one cell short, is a bug.

### `m 5` — separators

```
 exactly-1k.bin      bin    1024B│08/28 01:10
```

- `bin` is the extension column, five cells, left-aligned.
- **No gap** between it and the size: that column sets `sep = false`.
- A `│` sits before the date, and no space either side of it.
- Directories have no extension, so that cell is blank — the columns after it
  should still line up.

### `m 6` to `m 8` — panes

The middle pane looks the same in all three; the difference is at the edges.

- `m 6` — the left and right panes carry no columns at all.
- `m 7` — the left pane fills in. `sibling-one` and `sibling-two` get a size and
  a date, measured against **their own folder**, not this one.
- `m 8` — the right pane fills in. Hover `nested` to give it a folder.

The preview pane keeps whatever its last peek drew, so switching between these
without moving the hover leaves the right pane showing the previous mode. Move
the hover — `j` then `k` — and it catches up. This is Yazi caching the
previewer's output, not a supaline bug.

### `m 9` — user-written columns

```
 exactly-1k.bin      bin   exactly- file
 nested                    nested   dir
```

- `bin` comes from a column registered with `supaline.column(...)`, `exactly-`
  from one clipped to eight cells, and `file` from a bare function in the spec.
- The clipped column shows no ellipsis, and `never-opened` becomes `never-op`.
- All three go through the same interface the built-ins use. If a user column
  behaves differently from a built-in one, that is the bug.

### `T` — the theme

The fixture sets a `[supaline]` section: size orange, mtime green, owner blue,
extension magenta.

Those colours should already be on screen when Yazi opens. `T` re-applies them,
which is worth doing once to confirm nothing goes missing on a theme reload —
and it is the only way the headless harness gets them at all, since a detached
tmux never answers the terminal probe that triggers the load.

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
leaves its captures in `$TMPDIR/supaline-e2e` — `screen-mN.txt` is the plain
text and `color-mN.txt` keeps the escape sequences, which is how to tell a
colour problem from a layout one.

A regression worth keeping should end up in `test/run.lua` if it is about the
logic, or as a check in `test/e2e.sh` if it is about what reaches the screen.
