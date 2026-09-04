# The traps a check already catches

Five of the eight constraints are refused by a test or a CI job, so writing one
the wrong way fails on its own and prints what to write instead. They are here
rather than in `SKILL.md` for that reason: reading about them in advance buys
nothing the check does not already give you.

Read this when one of them fires and the message is not enough.

## `ya.sync` state is scoped to the file the call is written in

Yazi binds a `ya.sync` block to the name of the plugin being loaded and matches
the async and sync sides **by the position of the call**. A closure written in
one module therefore writes to a different state table than one written in
another, and reordering the calls silently rebinds them.

So: every `ya.sync` call lives at the top level of `main.lua`, unconditionally
and in a fixed order. Never inside an `if`, never inside a `pairs` loop, never
inside `setup`. Providers export plain reducers that `main.lua` wraps.

This is also why a third-party column cannot own asynchronous state: a `ya.sync`
call made from the user's `init.lua` is never replayed in the async VM.

Pinned by the `ya.sync placement` job in CI, which fails on a call outside
`main.lua` or one that any condition, loop or function encloses.

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

26.8.15 renamed `bulk` to `bulk-rename` without saying so. Yazi's `ps.sub`
accepts any string, so a stale name is a subscription that simply never fires.
The kinds actually published live in `pub_after!` in
`yazi-dds/src/pubsub.rs` — plus one that does not: `bulk-rename` comes from a
hand-written `pub_after_bulk_rename` beside the macro, which is exactly why
reading the macro alone misses it.

**Checked.** The stub's `ps.sub` refuses a kind Yazi does not publish, so any
subscription with a bad name fails the unit suite the moment a spec loads the
module. `test/dds_spec.lua` holds the list of fifteen.

## Every module must return a table

Yazi wraps each module in a state table. `return true` from a side-effect-only
file fails with "error converting Lua boolean to table"; return `{}` instead.

**Checked.** `test/module_spec.lua` asks `git ls-files` for the plugin's
modules and requires each, so a module added later is covered without anyone
adding it to a list.

## Prefer `Url.spec.*`

`Url.is_regular`, `Url.is_search` and `Url.domain` are deprecated in 26.8.15 in
favour of `Url.spec.is_regular`, `Url.spec.is_search` and `Url.spec.domain`.

`is_regular` does not mean "a real file on disk". It holds for exactly one of
Yazi's six `AuthKind` variants, and a search result is a local file with
`is_regular = false` — so a check written as `not is_regular` demotes every
search hit along with the remote ones. The partition worth asking for is
`spec.is_virtual`, the exposed complement of Yazi's own `AuthKind::is_local()`.

It matters wherever a value only means something on the machine Yazi is running
on: `ya.user_name` and `ya.group_name` read that machine's databases, and an
SFTP file's UID was minted on the server. Yazi's own `Linemode:owner` resolves
them regardless, so the `owner` column deliberately differs from it and prints
the numbers instead.

**Checked.** The `Forbidden spellings` CI job refuses `is_regular` anywhere in
plugin Lua and prints this. The six variants and Yazi's own predicates are at
the end of this file; `test/auth_spec.lua` pins the partition in the stub.

# `in_preview`, in Yazi's own source

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

# `AuthKind`, and why `is_regular` is the wrong question

`Url.is_regular`, `Url.is_search` and `Url.domain` are deprecated in 26.8.15 in
favour of `Url.spec.is_regular`, `Url.spec.is_search` and `Url.spec.domain`.

`is_regular` does not mean "a real file on disk". Yazi's `AuthKind` has six
variants and `is_regular` holds for exactly one of them; a search result is a
local file with `kind = "search"`, `is_regular = false` and
`is_virtual = false`. A check written as `not is_regular` therefore demotes
every search hit along with the remote ones.

The partition worth asking for is the one Yazi uses itself,
`AuthKind::is_local()`: `regular` and `search` are local, `mount`, `hub`,
`scope` and `sftp` are not. That method is not bound to Lua, but it is the
exact complement of `spec.is_virtual`, which is; `spec.kind` gives the variant
name as a lowercase string. `Url.spec` is a cached field, so reading it once
per row costs nothing.

It matters wherever a value only means something on the machine Yazi is running
on. `ya.user_name` and `ya.group_name` read that machine's passwd and group
databases, and an SFTP file's UID was minted on the server, where the same
number is very likely a different account. Yazi's own `Linemode:owner` resolves
them regardless, so the `owner` column deliberately differs from it and prints
the numbers instead.

Pinned by `test/auth_spec.lua`, which holds all six variants and the
`is_virtual` / `is_local` complement, and by the stub, which refuses an
`AuthKind` Yazi does not have rather than treating a typo as virtual.

