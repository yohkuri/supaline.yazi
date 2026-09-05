---
name: verify-supaline
description: >-
  What this plugin's test harness can and cannot say, and the rules for
  changing it. Read when writing or changing anything under `test/` -- a spec,
  a stub, or one of the shell harnesses -- and not for running the tests, which
  AGENTS.md lists and which need nothing from here. Covers stub fidelity and
  why the stubs deliberately fail loudly where Yazi fails silently, what the
  unit suite can and cannot prove, the fixture the e2e and manual runs share,
  and the two ways a headless tmux behaves unlike a real terminal.
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

## What the unit suite can prove

Pure logic — normalisation, layout, the ratio contract, the built-in
formatters — and, through the stub's fidelity, most of the constraints in the
`yazi-platform-traps` skill. It says nothing about rendering or fetchers.

It also proves nothing about code that does not exist yet: a spec pins the
implementation it was written against, so a *new* column can repeat a trap and
keep the suite green. That is why some constraints are CI spelling checks
rather than tests.

Write the test code for **Lua 5.5**. `test/run.lua` refuses any other version
and says so, and `mise.toml` pins 5.5.1, so this needs no remembering.

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
