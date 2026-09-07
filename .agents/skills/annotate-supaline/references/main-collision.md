# The `.main` collision

`types.yazi` ships its annotations as a single `main.lua` — 3,235 lines with no
`return` — and a Yazi plugin's entry point is also `main.lua`. So
`require(".main")` has two candidates and `lua-language-server` takes exactly
one. Which one is a property of the absolute path the tree sits at, not of
either file's name.

None of that is needed to write a spec or an annotation. `annotate-supaline`
and `verify-supaline` each say what to do about it in a paragraph — declare
`supaline.Main`, claim it at the `require`, keep `MAIN_EXPORTS` in step — and
that is the whole of the working knowledge. Read this file for the other case:
a checkout somewhere new, an annotations revision that moves, the shadow step
in CI firing, or the upstream issue landing.

Everything here was measured on `lua-language-server` 3.19.1 against
`yazi-rs/plugins@0be29a9`, the two revisions CI pins.

## Contents

- Which candidate wins — the sort order that decides it
- Measured on this plugin's own files — the two-directory probe
- Re-taking it — the scratch-directory trap and how to count
- Where the collision is stated — the four places, and the count
- Filed upstream — `---@meta _`, and what it would retire
- `.main` is the only name that can collide — depth, and `init.lua`

## Which candidate wins

`lua-language-server` collects every candidate for a require name and takes the
first. The list is sorted by `file://` URI, so the winner is whichever path
sorts first in byte order over the **percent-encoded** URI. Nothing about it
follows from the plugin's name.

This checkout is under `~/ghq/`, and `g` sorts after the `.` of
`~/.config/yazi/plugins/types.yazi/`, so the annotations win. CI checks out
under `/home/runner/work/`, which sorts after `/home/runner/.config/` the same
way — read off the two paths, not measured on the runner. Those are the two
arrangements this repository is written for, and both land on the same side.

## Measured on this plugin's own files

By copying `main.lua`, `column.lua`, `builtin.lua` and `.luarc.json` into two
directories differing in nothing but their name, and checking a planted
`require(".main").setup(42)` in each:

| workspace | the planted `setup(42)` |
| --- | --- |
| `~/zz-supaline-probe` | not reported, 12 problems |
| `~/!supaline-probe` | `param-type-mismatch` reported, 13 problems |

The other 12 are the same 12 in both runs, so the library loaded either way and
the one diagnostic that moved is the call through `require(".main")`. A
checkout at `~/開発/` or `~/!work/` sits on the second row — the URI encodes
them as `%E9…` and `%21`, and `%` sorts before `.` — and reads `.main` from
this tree, with `supaline.Main` claimed over it regardless. The class stays
right there; what stops applying is the reason given for it.

## Re-taking it

Use two real directories under `$HOME`. A scratch directory measures nothing:
`mktemp -d` gives `/var/folders/…`, which sorts after `/Users/…` however it
resolves, so the annotations win there under every name — the tree that reports
the mismatch at `~/!supaline-probe` reports none from a `mktemp -d`.

Read the total off the final `Diagnosis complete` line, never off `Found N
problems`, which is a progress checkpoint and is printed more than once.

## Where the collision is stated

Four places state it, each scoped to the two arrangements above and none of
them repeating the mechanism:

- the comment above `supaline.Main` in `main.lua`
- the comment above `supaline.ColumnModule` in `column.lua`
- the comment above `MAIN_EXPORTS` in `test/module_spec.lua`
- the shadow step in `.github/workflows/check.yml`

All four point back here, so a re-measurement lands in this file and the count
of places that have to move with it is four. The shadow step is the one that
does not depend on the answer at all: it reports a name the library ships twice
without working out which copy would win, which is why it keeps holding
wherever a runner puts the checkout.

## Filed upstream

[yazi-rs/plugins#238](https://github.com/yazi-rs/plugins/issues/238), open at
the time of writing. `types.yazi/main.lua` is generated, and one line in the
template that generates it — `---@meta _`, the meta name that makes a file
impossible to require — takes it off the candidate list while leaving it on
`workspace.library`. Measured on a minimal demo plugin rather than on this
tree: the diagnostic the collision swallows comes back, and `ya.dbg` and
`cx.active.current.cwd` still resolve, so the annotations go on doing their
job.

If it lands, `supaline.Main`, the `MAIN_EXPORTS` list pinning it, the cast at
each spec's `require` and the `main.lua` exception in the shadow step all stop
being needed — but only from the annotations revision that carries the line,
and CI pins that revision by hash.

## `.main` is the only name that can collide

`.luarc.json` puts one directory on `workspace.library`, and at `0be29a9` that
directory holds a single Lua file, so nothing there shadows `.builtin` or
`.column`. No probe reached that: `.builtin` returns a bare `{}`, and an empty
table looks the same whichever module it came from. The `lua-language-server`
job reads the directory rather than this sentence — beside the clone, it names
any tracked plugin file the annotations ship a file of that name, at any depth
and `main.lua` excepted. Growing a `builtin.lua` fails that step instead of
quietly retiring this section.

Depth is the part that is not guessable. `runtime.pathStrict` defaults to
false, so `?.lua` is tried against every subdirectory of a library root, and
`nested/column.lua` shadows `.column` exactly as a `column.lua` beside
`main.lua` does; `a/b/c/column.lua` too. Measured by planting an annotation
file with no `return` — the shape `types.yazi`'s own `main.lua` has — and
watching `--check` go from refusing a misspelled `column.normalizze` to
reporting no problems at all.

Two things the same probe found. A planted file that *does* return a table is
loud rather than silent. And `column/init.lua` did not shadow: `Lua.runtime.path`
is walked entry by entry, `?.lua` before `?/init.lua`, and the URI sort above
only breaks ties inside one entry, so a `column.lua` anywhere beats every
`column/init.lua`.

Turning `runtime.pathStrict` on would narrow this to the root and is not on the
table, because `.luarc.json` is upstream's verbatim.
