---
name: verify-supaline
description: >-
  What this plugin's test harness can and cannot say, and the rules for
  changing it. Read when writing or changing anything under `test/` -- a spec,
  a stub, or one of the shell harnesses -- and not for running the tests, which
  AGENTS.md lists and which need nothing from here. Covers stub fidelity and
  why the stubs deliberately fail loudly where Yazi fails silently, what a
  spec's calls into the plugin are actually checked against, how to plant a
  value that is wrong on purpose without the probe being what gets refused,
  what the unit suite can and cannot prove, the fixture the e2e and manual
  runs share, and the two ways a headless tmux behaves unlike a real terminal.
---

# Working on the test harness

## Stubs are worth exactly their fidelity

`ui.truncate` and `Line:truncate` are line-by-line ports of Yazi's own, and
`truncate_spec.lua` pins them: the first against the assertions in Yazi's test
suite, the second against a table measured from a running 26.9.1, since it has
no suite to copy. If you stub something new, pin it the same way — a stub
nothing measures is a stub that drifts, and it drifts towards making tests
pass.

Width is two stubs because Yazi has two: `str_width` is what `ui.width`
returns, `cp_width` what both truncations count. Collapsing them would be
tidier and would hide a trap.

Where Yazi fails silently, the stub deliberately fails **loudly** instead: an
unknown `AuthKind`, an unpublished DDS kind, a write to `th`. Yazi accepts all
three without a word, which is what makes them worth catching here — a stub
that reproduced the silence would let a test pass while the plugin was dead.
Each such divergence is pinned by a spec of its own, so the stub cannot drift
from Yazi unnoticed either.

The other side of the rule: where the behaviour under test *is* Yazi's, the
stub reproduces it exactly, name and all. `in_preview` is computed the way
`yazi-actor/src/lives/file.rs` computes it rather than the way its name reads,
so a regression fails on the second preview row — which is how it fails on
screen.

The name is not the whole of it; the parameter list counts too. Write the
parameters the real call takes, `self` included, whether or not the stub reads
them, and set the fields Yazi always sets — `preview.skip` is one nothing here
reads. Where `types.yazi` declares nothing, `stub.lua` is the workspace's only
declaration, so a wrong arity there is reported against the *plugin* file that
makes the call: a nullary `Tab:history` had the warning naming `builtin.lua`.

`stub.file` and `stub.folder` claim `supaline.File` and `supaline.Folder`
rather than `table`, and `run.lua` types the global the specs reach them
through, so a spec reading a field Yazi does not have is refused along with the
plugin that would have read it. That is the whole of
what it buys: the class is not `(exact)`, so the stub's own table is accepted
however little of it is filled in. The annotation is a claim about Yazi, not a
check on this file — fidelity is still read against a running Yazi.

## What a spec's calls are checked against

A spec's calls into the plugin are not checked against `main.lua`. Under
`lua-language-server`, `require(".main")` reaches `types.yazi`'s own `main.lua`
instead — annotations with no `return`, sitting on `workspace.library` — so
`main.setup(42, ...)` and `main.columnn(...)` were both accepted until
`main.lua` declared `supaline.Main` and each spec claimed it at the `require`.
That is the same repair `supaline.Stub` is for the stub. `.column` is not
affected: it resolves to this tree, and `column.lua`'s signatures are read
normally.

Two things follow for anyone writing a spec:

- The cast at a spec's `require` is load-bearing, not decoration. Drop it and
  every call in that file goes unchecked again, silently, with the suite still
  green.
- `supaline.Main` is written by hand, so a new export in `main.lua` has to be
  added to that class and to `MAIN_EXPORTS` in `module_spec.lua`, which fails
  until you do. A changed *signature* is past what Lua can see at runtime and
  is still read by eye.

Which of the two `main.lua` files wins is a property of the absolute path this
tree sits at, and it comes out the same way here and on CI. Nothing about
writing a spec turns on it;
`annotate-supaline/references/main-collision.md` has the mechanism, what was
measured, and what to re-run when a checkout, a pin, or the upstream issue
moves.

## Planting a value that is wrong on purpose

If a spec's assertions about a module look suspiciously cheap, plant a wrong
argument rather than a misspelled field before believing them: a misspelled
field bites only on a value carrying a declared class, and a module table has
none until someone gives it one. `column.normalizze({}, {})` passed on the line
above a refused `column.normalize(42, {})` for as long as `column.lua` declared
no class for the table it returns. It declares `supaline.ColumnModule` now, on
the table rather than by hand, so the fields are whatever the file assigns and
no spec has to claim it. What is left is `th`: no class at all, so it takes
whatever name a spec spells.

Plant it below the line that binds the value. Above it the checker reports
`undefined-global` at the planted line — still a refusal, but of the probe and
not of the misspelling, which a harness grepping for the field name scores as a
module that refuses nothing.

Deliberately wrong values are a spec's stock in trade, and they now cost
something: a class on the configuration means `column.normalize(42, ...)` and
`{ linemodes = { detail = "size" } }` are refused by the checker as well as by
the code under test. Suppress those on the line, with
`---@diagnostic disable-next-line`, and never at the top of the file — a
blanket disable there grows to cover code nobody meant to exempt. The two that
were here were measured before being replaced: one covered a single site and
the other covered nothing at all, so neither bought what its position implied.

## What the unit suite can prove

Pure logic — normalisation, layout, the ratio contract, the built-in
formatters — and, through the stub's fidelity, most of the constraints in the
`yazi-platform-traps` skill. It says nothing about rendering or fetchers.

It also proves nothing about code that does not exist yet: a spec pins the
implementation it was written against, so a *new* column can repeat a trap and
keep the suite green. That is why some constraints are CI spelling checks
rather than tests.

Write the test code for **Lua 5.5**, the version Yazi runs: `%z` in a pattern
means the NUL byte on 5.1 and the letter `z` from 5.2 on, and `utf8` arrived in
5.3. `test/run.lua` refuses any other version and says where to get one, so
this needs no remembering.

## The fixture, shared by both harnesses

`e2e.sh` and `manual.sh` both build their configuration and fixture with
`test/setup.sh`, so what a person looks at and what the headless run asserts on
cannot drift apart.

The fixture opens on a directory carrying the cases that break width
arithmetic — CJK, emoji, an over-long name, sizes either side of the 1K
boundary — with siblings above it and a subdirectory below, so all three panes
have rows. `m0` to `m9` switch between the linemodes, one per decision worth
looking at, and `test/MANUAL.md` says what to look for in each. Yazi's own
`m s` and `m n` still work, which is what makes them worth comparing against.

```sh
test/e2e.sh --keep          # leave the scratch directory behind
test/manual.sh --clean      # discard the manual fixture
```

## A headless run is not a terminal

- A detached tmux never answers the terminal probe, so `rt.term.light()` stays
  `nil` and a flavor that varies by terminal background cannot resolve. The
  user's `theme.toml` is applied regardless: 26.9.1 fires `theme` by itself a
  couple of milliseconds after `init.lua`, probe or no probe. `e2e.sh` used to
  send `app:theme` by hand before capturing and no longer needs to; the first
  half of its theme check would catch the day that changes back.
- Yazi queries the terminal on startup and aborts if nothing answers, so
  `script`-style pseudo-terminals do not work. Use tmux, which is a real
  terminal emulator.

Both are already handled inside `e2e.sh`. They matter when you change it.
