# The traps a check already catches

Seven of the eleven constraints are refused by a test or a CI job, so writing
one the wrong way fails on its own and prints what to write instead. They are
here rather than in `SKILL.md` for that reason: reading about them in advance
buys nothing the check does not already give you.

Read this when one of them fires and the message is not enough.

## Contents

- `ya.sync` state is scoped to the file the call is written in
- `in_preview` is not the counterpart of `in_current`
- DDS event names are not all in the changelog
- Truncation counts characters; the screen counts clusters
- Every module must return a table
- An attribute method takes a removal flag, not the value
- Prefer `Url.spec.*`
- `in_preview`, in Yazi's own source
- `AuthKind`, and why `is_regular` is the wrong question

## `ya.sync` state is scoped to the file the call is written in

Yazi matches the async and sync sides **by the position of the call**, and
scopes the state table to the file the call was written in.

Measured with a probe plugin, using `cx` — which exists in the sync VM and not
the async one — to make the two loads disagree about how many blocks there are:

```lua
local first
if cx then                                    -- sync VM only
    first = ya.sync(function() return "body-of-FIRST" end)
end
local second = ya.sync(function() return "body-of-SECOND" end)
```

Called from the async entry, `second()` returned **`body-of-FIRST`** — the
wrong body, with no error: `pcall` reported success. One block skipped on one
side shifts every block after it, and the result is a plausible value from the
wrong closure.

A second probe settles the state table. A block in `main.lua` set `st.mark`;
a block in a sibling module of the same plugin read `st.mark` back as `nil`.
Same plugin, same run, different table.

So: every `ya.sync` call lives at the top level of `main.lua`, unconditionally
and in a fixed order. Never inside an `if`, never inside a `pairs` loop, never
inside `setup`. Providers export plain reducers that `main.lua` wraps.

This is also why a third-party column cannot own asynchronous state: the async
VM never runs `init.lua` at all. The same probe logged one line from `init.lua`
per session, and `cx` was already `nil` there — so a `ya.sync` written in the
user's config has no async-side counterpart to be matched against.

Pinned by the `ya.sync placement` job in CI, which fails on a call outside
`main.lua` or one that any condition, loop or function encloses. The job checks
where the call sits; the probes above are what say why that is the rule.

## `in_preview` is not the counterpart of `in_current`

The names suggest a pair of pane flags. They are not. `in_current` compares
folders, so it holds for every row of the current pane; `in_preview` also
requires `idx == cursor`, so it holds for **one row** of the preview pane. There
is no `in_parent`.

Ask the preview folder whether the row is one of its own instead. `file.idx` is
its 1-based position in its own folder, so `folder.files[file.idx]` settles it
in O(1).

**Checked.** The `Forbidden spellings` CI job refuses `in_preview` anywhere in
plugin Lua and prints this, so a new pane test written the wrong way fails
without anyone having read the skill. The Rust that settles it is at the end
of this file. The existing `pane_of` is also pinned by `test/stub.lua` and by
`main_spec.lua` "every preview row draws, not just the one Yazi flags".

## DDS event names are not all in the changelog

The event is `bulk-rename`. An earlier Yazi called it `bulk` and renamed it
without saying so, and `ps.sub` accepts any string, so a stale name is a
subscription that simply never fires.

Measured: a probe subscribed to `bulk`, `bulk-rename`, `rename` and `cd` in one
session, then renamed two files through the bulk editor. `cd` fired at startup,
`bulk-rename` fired on the rename, and `bulk` and `rename` never fired at all —
so the old name is dead rather than merely deprecated, and a single rename event
is not published alongside the bulk one.

The kinds actually published live in `pub_after!` in
`yazi-dds/src/pubsub.rs` — plus one that does not: `bulk-rename` comes from a
hand-written `pub_after_bulk_rename` beside the macro, which is exactly why
reading the macro alone misses it.

**Checked.** The stub's `ps.sub` refuses a kind Yazi does not publish, so any
subscription with a bad name fails the unit suite the moment a spec loads the
module. `test/dds_spec.lua` holds the list of fifteen.

## Truncation counts characters; the screen counts clusters

`ui.width` measures a string the way the terminal draws it. Both of Yazi's
truncations add up characters instead, and the two disagree wherever a cluster
is not the sum of its parts. Measured on 26.9.1 across six strings, every `max`
from 0 to 8, with and without an ellipsis:

```text
-- \u{2764} is a heart, \u{FE0F} the selector that makes it an emoji. Spelled
-- out because the pair is two characters and one character on screen.
ui.width("\u{2764}") = 1     ui.width("\u{FE0F}") = 0
ui.width("\u{2764}\u{FE0F}") = 2                    -- not the sum
ui.truncate("\u{2764}\u{FE0F}abc", { max = 3 })  ->  "\u{2764}\u{FE0F}a…"
                                              -- four cells, for a max of 3
```

So a cut asked for three cells hands back four, and the columns after it shift.
The same count drops a skin-tone modifier from its emoji, and stops between a
joiner and what it joined.

`Line:truncate` adds a second habit. It holds back the ellipsis's width and
then drops the character that lands exactly on `max` as well -- to make room --
and goes on doing it when the ellipsis is empty, so a Line cut to twelve cells
is eleven where the same string is twelve. And because it counts characters, a
line it decides already fits comes back **wider** than `max`: `❤️abc` at
`max = 4` is returned untouched, five cells. There is no `max` that cuts that
line to four, which is why `column.cell` asks for one cell more than the column
has and then cuts again while the result is still too wide.

Two more things it does, worth knowing before reaching for it: it mutates the
line it is called on and hands the same one back, and the spans of a Line
cannot be read from Lua at all, so this is the only way in.

**Checked.** `test/truncate_spec.lua` holds the measured table, `stub.lua`
reproduces both habits rather than repairing them -- a stub that quietly did
the right thing would let the correction be deleted with the suite still green
-- and `test/column_spec.lua` pins the corrected cut in both directions. On the
screen side, `test/e2e.py` runs one column that hands back a string and one
that hands back a Line through the same name and width, and fails unless the
two read identically.

## Every module must return a table

Yazi wraps each module in a state table. `return true` from a side-effect-only
file fails with "error converting Lua boolean to table"; return `{}` instead.

**Checked.** `test/module_spec.lua` asks `git ls-files` for the plugin's
modules and requires each, so a module added later is covered without anyone
adding it to a list.

## An attribute method takes a removal flag, not the value

`ui.Style`'s attribute methods take **`remove`**, not the value the attribute
is being given. `bold()` and `bold(false)` both *add* bold; only `bold(true)`
takes it off. Read off `yazi-binding/src/style/style.rs`, where every one of
the nine is written `|_, me, remove: bool|` over `add_modifier` and
`remove_modifier`, and measured through `Style:raw()`:

| call | `raw()` |
| ---- | ------- |
| `ui.Style():bold()` | `{ bold = true }` |
| `ui.Style():bold(false)` | `{ bold = true }` |
| `ui.Style():bold(true)` | `{ bold = false }` |

That `false` is not the absence of bold. A style field holds three states, and
`bold = false` is the attribute **removed** — `ratatui`'s `sub_modifier`,
which strips a `bold` off whatever the style is patched onto or drawn over. A
theme carries the same three: `bold = false` under `[supaline]` reaches a
plugin as a style whose raw `bold` is `false`, because a custom theme section
deserializes into the same `StyleFlat`.

So a theme's `bold = false` copied into a call arrives as a second `true`, the
attribute is added where the user asked for it to be taken off, and nothing is
said anywhere. It shows on screen only where something underneath carries the
attribute: measured in a detached tmux with a `[filetype]` rule drawing `*.txt`
bold, a linemode cell built with the value passed through kept the row's bold,
and the same cell built with the removal reset it.

**Checked.** `test/colour_spec.lua` builds every attribute both ways through
`colour.style` and asserts the removal, and `test/stub.lua` models the
argument as `remove` so the suite cannot agree with the wrong reading.

## Prefer `Url.spec.*`

`Url.is_regular`, `Url.is_search`, `Url.domain` and `Url.scheme` are deprecated
in favour of the same names under `Url.spec`.

`is_regular` does not mean "a real file on disk". It holds for exactly one of
Yazi's six `AuthKind` variants, and a search result is a local file with
`is_regular = false` — so a check written as `not is_regular` demotes every
search hit along with the remote ones. The partition worth asking for is
`spec.is_virtual`.

**Checked.** The `Forbidden spellings` CI job refuses `is_regular` anywhere in
plugin Lua and prints this. The six variants, what a machine-local value costs
over a remote file, and Yazi's own predicates are at the end of this file;
`test/auth_spec.lua` pins the partition in the stub.

## `in_preview`, in Yazi's own source

From `yazi-actor/src/lives/file.rs`:

```rust
fields.add_field_method_get("in_current", |_, me| Ok(ptr::eq(&*me.folder, &me.tab.current)));
fields.add_field_method_get("in_preview", |_, me| {
  Ok(me.idx == me.folder.cursor && me.tab.hovered().is_some_and(|f| f.url == me.folder.url))
});
```

`in_current` compares folders, so it holds for every row of the current pane.
`in_preview` also requires `idx == cursor`, so it holds for the previewed
folder's **hovered row alone** — one row of the pane, whatever the pane's
length. There is no `in_parent`: every other preview row reports
`in_current == false, in_preview == false`, which is exactly what a parent-pane
row reports too.

So a pane test written as `file.in_preview and "preview" or "parent"` draws the
preview pane's first row and treats the rest as parent rows — bare when the
preview was asked for, drawn when it was not, and measured against the wrong
folder either way.

`test/stub.lua` reproduces the rule rather than the name, so a regression fails
the unit suite the same way it fails on screen: the second preview row, not the
first.

## `AuthKind`, and why `is_regular` is the wrong question

`Url.is_regular`, `Url.is_search`, `Url.domain` and `Url.scheme` are deprecated
in favour of the same names under `Url.spec`; the binary carries a deprecation
warning for each of the four.

`is_regular` does not mean "a real file on disk". Yazi's `AuthKind` has six
variants and `is_regular` holds for exactly one of them. Measured, by asking a
running Yazi:

```text
Url("/tmp/plain.txt").spec
    kind=regular  domain=    reg=true   srch=false  virt=false
Url("search://kw//tmp/plain.txt").spec
    kind=search   domain=kw  reg=false  srch=true   virt=false
```

So a search result is a **local** file with `is_regular = false`, and a check
written as `not is_regular` demotes every search hit along with the remote
ones. That is the whole trap, and it is reproducible in four lines of
`init.lua`.

The six variants come from Yazi's own parser rather than from counting. Two are
not configurable — `regular` and `search`, the two above — and the other four
are what `vfs.toml` accepts as a service `kind`:

```console
$ printf '[services.box]\nkind = "definitely-not-a-kind"\n' > vfs.toml
unknown variant `definitely-not-a-kind`, expected one of `sftp`, `mount`, `hub`, `scope`
```

The partition worth asking for is the one Yazi uses itself,
`AuthKind::is_local()`: `regular` and `search` are local, `mount`, `hub`,
`scope` and `sftp` are not. That method is not bound to Lua, but it is the
exact complement of `spec.is_virtual`, which is; `spec.kind` gives the variant
name as a lowercase string, and `spec.scheme` returns the same string.
`Url.spec` is a cached field, so reading it once per row costs nothing.

**Where this stops.** Only the local half was measured: both authorities a
machine can produce on its own report `is_virtual = false`. Declaring a service
in `vfs.toml` is not enough to make `sftp://…` or `scope://…` parse — the
authority is registered when the service actually connects, so
`Url("scope://box/x")` still raises `unknown VFS authority` — and a live remote
was out of scope. `is_virtual = true` is therefore inferred from the
complement, not seen. Anyone with an SFTP host to hand can close that gap in
one run.

It matters wherever a value only means something on the machine Yazi is running
on. `ya.user_name` and `ya.group_name` read that machine's passwd and group
databases, and an SFTP file's UID was minted on the server, where the same
number is very likely a different account. Yazi's own `Linemode:owner` resolves
them regardless, so the `owner`, `user` and `group` columns deliberately differ
from it and print the numbers instead.

Pinned by `test/auth_spec.lua`, which holds all six variants and the
`is_virtual` / `is_local` complement, and by the stub, which refuses an
`AuthKind` Yazi does not have rather than treating a typo as virtual.
