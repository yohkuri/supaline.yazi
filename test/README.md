# Testing supaline

Three layers, in increasing order of what they can tell you:

| | Covers | Run |
|---|---|---|
| `run.lua` | Pure logic: colour maths, normalisation, padding, the ratio contract | `lua test/run.lua` |
| `e2e.sh` | A real Yazi, headless — proves rendering and the fetchers work at all | `test/e2e.sh` |
| `manual.sh` | The same, interactive — the only way to judge how it *looks* | `test/manual.sh` |

The unit tests stub the Yazi globals, so they can say nothing about rendering,
fetchers or `ya.sync`. Every bug found in this project so far lived in exactly
that gap. Do not report that something works on the strength of `run.lua` alone.

---

## Headless testing

```sh
test/e2e.sh                          # a generated fixture
test/e2e.sh ~/src                    # any directory
test/e2e.sh ~/src color              # keep the ANSI escapes, to see gradients
test/e2e.sh ~/src plain lua          # search for "lua" rather than "txt"
```

Each run prints the target twice: once as an ordinary listing, once as a
`search://` one. Point it at a directory of your own and the search term has to
match something there, or the second screen is empty and proves nothing.

**Read the exit code, not just the screen.** It is non-zero on a Lua error in
the log *and* on a task that never succeeded. The second matters more than it
looks: a broken fetcher writes its reason only to the task's own log, which
nothing here can read, so the one signal that escapes is the status bar's
`N left` counter. The screen looked entirely correct through the whole of the
26.8.15 breakage, while all four fetchers were failing.

---

## Manual testing

```sh
test/manual.sh                          # a generated fixture
test/manual.sh ~/src                    # any directory
test/manual.sh ~/.local/share/chezmoi   # a chezmoi source tree
test/manual.sh --clean                  # throw it all away
```

Your own `~/.config/yazi` is never read or written. The throwaway configuration
lives in `${TMPDIR}/supaline-manual/` and is reused between runs, so the
linemode you picked last time is still selected when you come back.

### Switching linemodes

Yazi already uses `m` as its linemode leader, and these extend it. Press `m` to
see the whole list in the which menu.

| Key | Shows |
|---|---|
| `m 1` | chezmoi + git + size + mtime — the intended configuration |
| `m 2` | size, log scale |
| `m 3` | size, linear scale |
| `m 4` | size, gradient off |
| `m 5` | mtime + btime + atime |
| `m 6` | permissions + owner + size + btime |
| `m t` | reload the theme |
| `m s` | Yazi's own `size` linemode |
| `m n` | none |

---

## The checklist

### Gradients

| Step | Expected |
|---|---|
| `m 2`, look down the size column | Colour brightens with size, across the whole range |
| `m 3` | Nearly flat: everything below ~10M sits at the dark end. This is what eza's linear normalisation does, and why `scale = "log"` exists |
| `m 4` | One flat colour. Compare with `m 2` to judge whether the ramp is worth it |
| `m 5` | Newest is brightest; the 2023 file is darkest |
| `m 1`, then `cd` into `src/` and back | Colours **change** between directories — the scale is relative to the listing you are in. Working as designed, and the main thing to have an opinion about |
| `m t` | Nothing visibly changes, and nothing breaks. This rebuilds every ramp through the `theme` subscription |

If every row is the same colour in `m 2`, your terminal is probably not
advertising truecolor — see Troubleshooting.

### Git

In the fixture root:

| Row | Expected |
|---|---|
| `build/`, `debug.log` | ignored |
| `docs/` | deleted — a deleted file is not in the listing, so the directory above it is the only place that state can appear |
| `src/` | untracked, inherited from `new.txt` below it |
| `large.bin`, `medium.bin` | untracked |
| `back\slash.txt`, `quote"name.txt` | untracked — plain `--porcelain` C-quotes these, so a blank here means the `-z` parsing regressed |
| `tiny.bin`, `small.bin`, `.gitignore` | clean, no sign |

Inside `src/`: `new.txt` untracked, `staged.txt` added, `tracked.txt` modified.
Cross-check any of it with `git status --porcelain`.

Then press `s`, search for `txt`, and confirm the same signs survive into the
listing — `src/new.txt` untracked, `src/staged.txt` added, `src/tracked.txt`
modified, all from directories other than the one you started in. Those URLs
carry a `search://` scheme that supaline has to flatten before either the
fetcher or the render path can match on it, and getting the two sides out of
step blanks the column with no error anywhere.

Merge conflicts are not in the fixture — every unmerged code (`DD`, `AU`, `UD`,
`UA`, `DU`, `AA`, `UU`) must render as `updated`, and `test/git_spec.lua` pins
that. To see one for yourself:

```sh
cd "$(mktemp -d)" && git init -q -b main .
echo base >base.txt && git add . && git commit -qm base
git checkout -qb side && echo side >c.txt && git add . && git commit -qm side
git checkout -q main && echo main >c.txt && git add . && git commit -qm main
git merge side   # AA
```

### chezmoi

The fixture cannot cover this; point it at real data.

```sh
test/manual.sh ~                        # destination side
test/manual.sh ~/.local/share/chezmoi   # source side
```

Both sides should resolve. On the source side the names carry chezmoi's
attribute prefixes (`private_dot_config`), and the status still lines up —
that mapping is the part worth confirming. Cross-check with
`chezmoi status --path-style absolute`.

Directories inherit the state below them on both sides. A file that is managed
and unchanged shows nothing by default; set `[chezmoi] managed_sign` in
`theme.toml` if you want to see the managed set.

### Alignment and width

| Check | Expected |
|---|---|
| `日本語ファイル.txt` | Columns stay aligned — the name is double-width, and the padding must measure display width, not bytes |
| `a-deliberately-long-…txt` | Yazi truncates the *name*; the columns are unaffected |
| `empty.bin` | `0B`, not blank |
| `empty/` | `-` (never visited, so no entry count) |
| `link-to-tiny.bin` | Shows the target's size and time |
| Narrow the terminal | Columns are **not** truncated; they push instead. Known limitation |
| `m 6` | The widest configuration. Check it still reads at a normal width |

### Behaviour under change

| Step | Expected |
|---|---|
| Create or delete a file (`a`, `d`) | Gradient re-normalises immediately — the file count is part of the cache key |
| Append to a file from another terminal, without changing the count | The ramp does **not** update until you leave the directory and come back. A deliberate trade to keep rendering O(1) per row; documented in the README |
| Scroll a large directory (`test/manual.sh ~/some/big/dir`) | No perceptible lag. Rendering must not do colour maths per row |

---

## Changing the configuration

The scratch config is a normal Yazi config; edit and restart.

```sh
$EDITOR "${TMPDIR}/supaline-manual/config/init.lua"
test/manual.sh
```

`test/setup.sh` rewrites `init.lua`, `yazi.toml` and `keymap.toml` on every run,
so keep experiments you want to survive somewhere else — or edit `setup.sh`
itself, which is the file both `manual.sh` and `e2e.sh` read.

---

## Troubleshooting

**Every row is the same colour.** The gradient is on `colors = "auto"` in normal
use, which requires `COLORTERM=truecolor`. `setup.sh` forces
`colors = "truecolor"`, so if it is still flat, either the column has
`gradient = "off"` (`m 4` does) or your terminal is dropping 24-bit colour.
Check with `printf '\e[38;2;255;0;0mred\e[0m\n'`.

**Boxes instead of Git signs.** The defaults are Nerd Font glyphs, inherited
from git.yazi. Either install a Nerd Font or override them:

```toml
# ${TMPDIR}/supaline-manual/config/theme.toml
[git]
modified_sign  = "M"
untracked_sign = "?"
```

**No Git signs at all.** The fetcher only runs for files on the local
filesystem. Check `git` is on PATH. Note `setup.sh` deliberately writes no
fetcher rules — supaline registers its own at setup, and this is what proves
it — so a blank column may equally mean that registration broke.

**Nothing at all in the trash bin (`g t`).** Reading `~/.Trash` needs Full Disk
Access on macOS; without it Yazi cannot list it and shows
`Operation not permitted`. Nothing to do with supaline.

**No chezmoi signs.** Needs `chezmoi` on PATH and an initialised source state.
The provider disables itself permanently for the session if either is missing,
so restart after fixing it.

**Something is broken and you want the error.** Yazi logs Lua errors:

```sh
YAZI_LOG=debug test/manual.sh
# then, after quitting:
grep -i lua ~/.local/state/yazi/yazi.log
```

---

## What is not a bug

- Colours differ for the same file in different directories. The scale is
  relative to the current listing, like eza's.
- A column wider than its `width` pushes the row instead of being cut.
- A file edited in place, with the directory's file count unchanged, keeps a
  stale gradient until you leave and return.
- `permissions` and `owner` are empty on Windows.
- Virtual files (`sftp://`, `trash://`) carry no Git or chezmoi state; nothing
  shells out for them. A `search://` listing is *not* one of these — its files
  are real, and both columns are expected to work there.
