# Configuration

Everything supaline reads, in the order you are likely to need it. The
[README](../README.md) has the short version; [Colours](colours.md) and
[Writing a column](columns.md) have the rest.

## `setup` options

| Option      | Default     | Meaning                                              |
| ----------- | ----------- | ---------------------------------------------------- |
| `linemodes` | —           | Required. Map of linemode name to a list of columns. |
| `separator` | `" "`       | Drawn between columns, unless a column opts out. A table carries a colour; see [A coloured separator](colours.md#a-coloured-separator). |
| `scale`     | `"linear"`  | Normalisation for columns that take a range. Outranks a column definition's own; see [`scale`](colours.md#scale). |
| `lightness` | —           | The lightness ranges a `<->` may ask for, by name. Nothing is defined by default, so a `<->` with no range behind it is refused; see [`lightness`](colours.md#lightness). |
| `order`     | `1400`      | Where the parent/preview child sits among `Linemode`'s children, as a whole number. |
| `toggles`   | —           | Another plugin's `Linemode` child by name, as the `order` it sits at, for a key to hide; see [Toggling from a key](#toggling-from-a-key). |

Those six are the whole of it: a key that is none of them — `scal`, `bnad`,
`seperator` — is refused by name rather than quietly ignored, as one is inside
a linemode, a column, or a style. Nothing else would say so; a plugin-wide
`scale` written `scal` is read by nobody and every column goes on scaling the
way it did.

A value none of them takes is refused the same way, and for the same reason.
`scale = "LOG"` is spelled right and means nothing, and until it was refused it
reached every column and scaled none of them — a wrong value was accepted by
being ignored, which is the quieter half of the same mistake.

A linemode name is 1 to 20 bytes, which Yazi counts rather than characters, so
a CJK name has room for six. Yazi keeps its `Linemode` component's
own machinery on the table the linemodes are looked up on, so any name already
on that table is refused — `new`, `redraw`, `padding`, `children_add`,
`children_remove`, `solo` — as is anything beginning with `_`, and `none`,
which is Yazi's name for no linemode at all. The
exception is Yazi's own linemodes: naming one `size`, `mtime`, `btime`,
`atime`, `permissions` or `owner` replaces it, which is allowed.

## Linemode options

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

### Different columns per pane

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

[Writing a column](columns.md) has the rest of what one may do.

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

## Toggling from a key

Yazi's own `linemode` action switches to a linemode and never back, so no one
key can both show the columns and hide them. `plugin supaline -- toggle` can.
Handed a linemode's name, it switches the active tab to that linemode, or to
`none` when it is the one showing:

```toml
# ~/.config/yazi/keymap.toml
[[mgr.prepend_keymap]]
on   = [ "m", "d" ]
run  = "plugin supaline -- toggle detail"
desc = "Toggle supaline's columns"
```

The `--` is needed: without it Yazi hands the plugin `toggle` and drops the
name, and the press is refused for naming nothing. A press `toggle` cannot act
on says why in a notification, rather than doing nothing.

`none` hides supaline's columns and nothing else, so a sign another plugin
draws as a `Linemode` child of its own — [git.yazi](#alongside-gityazi)'s — is
still drawn. Hiding that takes a name for it, which `toggles` gives: the name
a key presses, and the `order` the child was added at.

```lua
-- ~/.config/yazi/init.lua
require("git"):setup { order = 1500 }
require("supaline"):setup {
  linemodes = { detail = { "size", "mtime" } },
  toggles   = { git = 1500 },
}
```

```toml
# ~/.config/yazi/keymap.toml
[[mgr.prepend_keymap]]
on   = [ "m", "g" ]
run  = "plugin supaline -- toggle git"
desc = "Toggle git.yazi's sign"
```

Each key leaves the other's alone: `m d` keeps the sign and `m g` the columns.
A hidden child is hidden in every tab, since every tab draws through the same
`Linemode`, where a linemode is switched in the active tab alone.

An `order` rather than a plugin's name, because git.yazi's `setup` keeps to
itself the id `Linemode` handed back for its child, and the `order` is the one
thing your configuration knows about it — 1500 unless its `setup` names
another. Every child another plugin added at that `order` is hidden, so give a
second plugin sharing it an `order` of its own. supaline's own child and
Yazi's two are never hidden. That nothing sits at the `order` is said when the
key is pressed rather than at `setup`, which may run before the plugin that
adds the child.

`setup` refuses two names in `toggles`: one that is also a linemode's, since
`toggle` would then have two things to do with it, and a second name for an
`order` another already has, since each would undo what the other did. A name
with a space in it is pressed quoted, as a shell word: `toggle 'my sign'`.

## Column specs

A column is written in one of these shapes:

```lua
"size"                                  -- a registered column, by name
{ "size", width = 9, scale = "log" }    -- ... with its options overridden
function(file, ctx) return "..." end    -- an inline definition, render only
{ render = fn, stats = fn, width = 6 }  -- ... with options beside it
```

`[1]` is what tells a use of a column from a definition of one, and it holds
one kind of value: the **name** of a column registered elsewhere. A table with
a name there is a use of that column, and everything else in it — `render`
included — overrides what the definition set. A table with nothing there is a
definition; a render written at `[1]` rather than under `render` is refused,
with the spelling to use instead.

Every option below but the last two can be set on the definition or overridden
per use. `options` and `validate` are the definition's alone, and so is `name` —
a definition written inline may give itself one, and a definition handed to
`register` is named by that call instead.

A name holds 1 to 20 characters, from lowercase letters, digits and `_`, and
anything else is refused where it is written. The rule is not supaline's: a
column's theme layer is the `[supaline]` field called after it, and a field
name Yazi will not parse does not merely go unread — it is an error in
`theme.toml`, which Yazi answers by discarding the whole file and falling back
to its preset. So `my-col` would cost you every other colour you wrote, and
supaline turns the name away instead — wherever you wrote it, a `register` call
and a definition that names itself alike.

| Option      | Default      | Meaning                                                  |
| ----------- | ------------ | -------------------------------------------------------- |
| `render`    | —            | Required. `function(file, ctx)`, run for every visible row. |
| `stats`     | `nil`        | `function(files)`, run over the listing and cached; result reaches `ctx.stats`. See [How often `stats` runs](columns.md#how-often-stats-runs) for when it runs again. |
| `refresh`   | `nil`        | `function()`, run at `setup`, after every theme reload supaline resolves, and on every `cd`. |
| `width`     | `nil`        | A whole number of cells, 1 or more; `"auto"`; or `function(stats) -> number`, which is held to the same. |
| `max_width` | `nil`        | Caps the column's width, however it was derived. A whole number of cells, 1 or more. |
| `align`     | `"right"`    | `"right"` or `"left"`, within the column's width.        |
| `overflow`  | `"ellipsis"` | `"ellipsis"`, `"clip"`, or `"grow"`.                      |
| `style`     | `nil`        | A colour, a gradient, a style table, a `ui.Style`, `false`, or a function returning one. See [Colours](colours.md). |
| `scale`     | from `setup` | `"linear"` or `"log"`. See [`scale`](colours.md#scale).             |
| `separator` | `nil`        | `false` drops the separator before this column; a string or a table replaces it. See [A coloured separator](colours.md#a-coloured-separator). |
| `options`   | `nil`        | The definition's alone: the names of the extra keys it reads off `ctx.opts`, each of which it may also default. See [Options of its own](columns.md#options-of-its-own). |
| `validate`  | `nil`        | The definition's alone: a check per declared option, `function(value)`, run by `column` and `setup` on each value of it written. See [Options of its own](columns.md#options-of-its-own). |

Any other key is refused by name, on a definition and on a spec alike, and so
is one of those written where it is not read — `options` or `validate` at a use
site, `name` on a definition `register` has already named, an entry at `[1]`
beside a `render`. Nothing else would say so: a misspelled `max_widht` is read by
nobody, and the column draws at its natural width without a word about why.

So is a value the key does not take. `align = "centre"` is spelled right and
means nothing, and `render`, `stats` and `refresh` are *called* rather than
read, so anything but a function written there is turned away while `setup` can
still say so. Left to itself a `stats = 42` reaches you at the first row as this
column throwing from its `stats` — about a function you never wrote — and a
`refresh = 42` reaches you as every linemode drawn on screen as its own name.

`width = "auto"` measures every file in the folder, as often as a
[`stats` would run](columns.md#how-often-stats-runs), and takes the widest
result. It is exact, and it costs a pass over the listing; a stated number
costs nothing.
`function(stats)` sits in between, for a column whose width follows from the
extremes.

`refresh` is for a column that caches something across rows which is not a
property of any file — the built-in timestamp columns hold the current year, so
`smart` can decide its format with an integer comparison instead of an
`os.date` per cell. Nothing about the folder is passed in, because nothing
about the folder is what changed.

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
the per-character painting off in the first place. What it cannot do is take
one of those `[status]` colours *away*: `style = { bg = false }` is a
background this column does not write rather than one it removes, for the
reason [`style`](colours.md#style) gives.

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
`stats` takes one pass over the listing each time a folder is
[measured](columns.md#how-often-stats-runs) — cheap next to what Yazi has
already done to list it, and the same pass a gradient reads from.

## Alongside git.yazi

[git.yazi](https://github.com/yazi-rs/plugins/tree/main/git.yazi) draws its
status sign as a `Linemode` child of its own, at `order = 1500` by default.
Yazi lays a row's children out in `order` and aligns the whole line right, so
the sign lands to the right of supaline's columns. A changed file has a sign
and a clean one has none, so every row with a sign has supaline's columns
pushed left by the sign's width — three cells, with git.yazi's default signs.

Either of two options git.yazi documents lines them up again:

- `require("git"):setup { order = 500 }` puts the sign before the slot
  supaline draws in, which is Yazi's own linemode at `order = 1000`. The
  columns stay flush right, and the sign sits between the name and the first
  of them.
- Keeping the sign at the right edge takes a sign on every row. Give the two
  that are empty by default one as wide as the rest — two spaces, beside the
  default signs:

  ```toml
  # ~/.config/yazi/theme.toml
  [git]
  clean_sign   = "  "
  unknown_sign = "  "
  ```

  The sign's cells are then taken on every row, in a repository or not.

To hide the sign without the columns, or the columns without the sign, see
[Toggling from a key](#toggling-from-a-key).

## Caveats

- **The preview pane repaints on its next peek, not on a linemode switch or a
  `toggle`.** Yazi caches the previewer's output, so either reaches the preview
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
- Statistics and derived widths are cached, and measured again whenever Yazi
  reports that a folder's listing changed — which it does for a file written
  in place, and for a directory's size arriving under `sort_by = "size"`.
