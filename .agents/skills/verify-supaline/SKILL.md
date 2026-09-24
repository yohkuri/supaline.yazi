---
name: verify-supaline
description: >-
  What this plugin's test harness can and cannot say, and the rules for
  changing it. Read when writing or changing anything under `test/` -- a spec,
  a stub, or one of the Python harnesses -- and not for running the tests, which
  AGENTS.md lists and which need nothing from here. Covers stub fidelity and
  why the stubs deliberately fail loudly where Yazi fails silently, what a
  spec's calls into the plugin are actually checked against, how to plant a
  value that is wrong on purpose without the probe being what gets refused,
  what the unit suite can and cannot prove, the fixture the e2e and manual
  runs share, and the three ways a headless tmux behaves unlike a real
  terminal.
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

### What a new stub has to carry

The name is not the whole of it; the parameter list counts too. Write the
parameters the real call takes, `self` included, whether or not the stub reads
them, and set the fields Yazi always sets — `preview.skip` is one nothing here
reads. Where `types.yazi` declares nothing, `stub.lua` is the workspace's only
declaration, so a wrong arity there is reported against the *plugin* file that
makes the call rather than against the stub.

`stub.file` and `stub.folder` claim `supaline.File` and `supaline.Folder`
rather than `table`, and `run.lua` types the global the specs reach them
through, so a spec reading a field Yazi does not have is refused along with the
plugin that would have read it. That is the whole of what it buys: the class is
not `(exact)`, so the stub's own table is accepted however little of it is
filled in. The annotation is a claim about Yazi, not a check on this file —
fidelity is still read against a running Yazi.

## What a spec's calls are checked against

Not `main.lua`. Under `lua-language-server`, `require(".main")` reaches
`types.yazi`'s own annotations instead, so `main.setup(42, ...)` and
`main.columnn(...)` are both accepted unless `main.lua` declares
`supaline.Main` and each spec claims it at the `require`. `annotate-supaline`
has the mechanism, and its `references/main-collision.md` has what to re-run
when a checkout or a pin moves; nothing about writing a spec turns on either.
`.column` is unaffected — it resolves to this tree and is read normally.

Two things follow for anyone writing a spec:

- The cast at a spec's `require` is load-bearing, not decoration. Drop it and
  every call in that file goes unchecked again, silently, with the suite still
  green.
- `supaline.Main` is written by hand, so a new export in `main.lua` has to be
  added to that class and to `MAIN_EXPORTS` in `module_spec.lua`, which fails
  until you do. A changed *signature* is past what Lua can see at runtime and
  is still read by eye.

## Planting a value that is wrong on purpose

If a spec's assertions about a module look suspiciously cheap, plant a wrong
argument rather than a misspelled field before believing them: a misspelled
field bites only on a value carrying a declared class, and a module table has
none until someone gives it one. `column.extremez(42)` passes on the line
above a refused `column.extremes(42)` for any module whose table carries no
class. `column.lua`'s carries `supaline.ColumnModule`; `th` carries nothing at
all, so it takes whatever name a spec spells.

Plant it below the line that binds the value. Above it the checker reports
`undefined-global` at the planted line — still a refusal, but of the probe and
not of the misspelling, which a harness grepping for the field name scores as a
module that refuses nothing.

Deliberately wrong values are a spec's stock in trade, and they cost
something: a class on the configuration means `registry.compile(42, ...)` and
`{ linemodes = { detail = "size" } }` are refused by the checker as well as by
the code under test. Suppress those on the line, with
`---@diagnostic disable-next-line`, and never at the top of the file — a
blanket disable there grows to cover code nobody meant to exempt.

## What the Lua unit suite can prove

Pure logic — normalisation, layout, the ratio contract, the built-in
formatters — and, through the stub's fidelity, most of the constraints in the
`yazi-platform-traps` skill. It says nothing about rendering or fetchers.

It also proves nothing about code that does not exist yet: a spec pins the
implementation it was written against, so a *new* column can repeat a trap and
keep the suite green. That is why some constraints are CI spelling checks
rather than tests.

Write the test code for **Lua 5.5**, the version Yazi runs: `%z` in a pattern
means the NUL byte on 5.1 and the letter `z` from 5.2 on, and `utf8` arrived in
5.3. `test/run.lua` refuses any other version and says where to get one.

## The second unit suite, and where a fact belongs

`AGENTS.md` lists that suite as the screen parsers. What it does not say is
that the purity is a **rule** rather than an accident: a `subprocess` or a
`Path.read_text` added to `screen.py` takes the whole file out of CI with it,
and the arithmetic that decides whether a ramp climbed goes back to being
checked only by a run nobody can make a runner do.

So a change under `test/` has somewhere to go, and it is usually not `e2e.py`:

- A fact about **what the screen looks like** belongs in `screen.py`, with a
  hand-written capture in `test_screen.py` beside it. A raw escape sequence is
  the most worth moving rather than the least: it is the one thing a capture
  written by hand can state exactly.
- A fact about **what the fixture spells** belongs in a reader over
  `test/fixture/init.lua` — `ground_hex`, `ramp_ends`, `broken_columns`,
  `band_width` and `c_bg_grounds` are the five — and `TheFixtureItReads` calls
  those readers rather than re-spelling their patterns. A copy of a pattern
  goes on passing while the reader beside it has quietly stopped matching, and
  `e2e.py` is not in CI to say so — a pattern anchored on stylua's indentation
  most of all, since re-nesting a table leaves the sweep passing over nothing.
- What is left for `e2e.py` is driving Yazi and holding the parsed answer
  against what this machine says: `pwd`, `grp`, a file on disk, a colour read
  out of the fixture.

Two habits the harness keeps throughout. Never `assert`: `Checks` counts named
failures and the run exits once, because a change that moves one column moves a
handful of checks, and the shape of that handful says where to look. And guard
any check an empty list or an unmatched pattern would let pass over nothing — a
sweep that read nothing looks like a sweep that found nothing wrong.

## The fixture, shared by both harnesses

The configuration Yazi is given sits under `test/fixture/` as the files Yazi
reads — `init.lua`, `keymap.toml`, `yazi.toml`, three themes, and
`banner.txt`, which is what `manual.py` prints. `test/setup.py` copies them
into a scratch tree and replaces `@DIR@` with it, and that is the whole of what
it does to them. `e2e.py` and `manual.py` both call it, so what a person looks
at and what the headless run asserts on cannot drift apart.

They are real files rather than heredocs, and that buys three readers the
fixture did not have: `stylua` formats `init.lua`, `lua-language-server`
type-checks it along with the plugin, and `fixture_spec.lua` opens it instead
of pattern-matching somebody else's quoting.

`fixture_spec.lua` puts that `init.lua` through `setup` under the stub, so a
refusal that turns the fixture's own configuration away fails in the unit suite
rather than in a headless Yazi minutes later. It still asserts it found a
`setup` call and a `column` registration rather than trusting the read: a file
that is present and empty compiles, runs and refuses nothing, which is a spec
exiting 0 over a configuration it never saw. And it says nothing about the
screen — `setup` took the configuration is the whole of the claim, and `e2e.py`
is still what says the configuration draws what `MANUAL.md` describes.

### What it puts on the screen, and what holds that together

The fixture opens on a directory carrying the cases that break width
arithmetic — CJK, emoji, an over-long name, sizes either side of the 1K
boundary — with siblings above it and a subdirectory below, so all three panes
have rows. `m0` to `m9`, and `me` once the digits ran out, switch between the
linemodes, one per decision worth looking at, and `test/MANUAL.md` says what to
look for in each. Yazi's own `m s` and `m n` still work, which is what makes
them worth comparing against. A third leader, `b`, draws the columns that are
wrong on purpose, and `e2e.py` presses those in a second Yazi of their own.

The same spec holds the fixture's **key set** together. Four places name that
set — `test/fixture/keymap.toml`, `test/fixture/banner.txt`, `test/MANUAL.md`,
and `e2e.py`'s capture loops — and the banner is the only one whose reader is a
person, so it is the one that can fall behind with everything still green. The
keymap is the authority and the spec names no key of its own: it reads the `on`
lines, then asks whether the banner offers each and whether `MANUAL.md` spells
each.

`references/editing-the-fixture.md` is what to open before changing either
half: what that comparison is shaped against, why the broken columns need a
second Yazi and a second log, and the three things about that run measured on
26.9.1 rather than reasoned about.

What is left for a person is what none of that can judge — whether the
sentence reads correctly against the column it is about, and whether twenty
seconds is long enough to read it. That, `fixture_spec.lua` taking the whole of
`init.lua` through `setup`, and `MANUAL.md` open beside the screen, are what
stands behind the family.

```sh
test/e2e.py --keep          # leave the scratch directory behind
test/manual.py --clean      # discard the manual fixture
```

## A headless run is not a terminal

- A detached tmux never answers the terminal probe, so `rt.term.light()` stays
  `nil` and a flavor that varies by terminal background cannot resolve. The
  user's `theme.toml` is applied regardless: 26.9.1 fires `theme` by itself a
  couple of milliseconds after `init.lua`, probe or no probe, so `e2e.py` does
  not have to send `app:theme` before capturing. The first half of its theme
  check would catch the day that changes back.
- Yazi queries the terminal on startup and aborts if nothing answers, so
  `script`-style pseudo-terminals do not work. Use tmux, which is a real
  terminal emulator.
- The probe nothing answers also holds the exit open. 26.9.1 waits five
  seconds for it after `q` -- 5.02, 5.03 and 5.04s measured -- and only then
  does the process leave and tmux destroy the session with it. So a capture
  taken in that window succeeds, which is a timeout standing in for a
  guarantee rather than one: `Session.quit` waits for the session to go
  instead of the screen to settle, because a `capture-pane` against a session
  that has gone exits non-zero and the harness reports that as a refusal to
  start.

All three are already handled inside `e2e.py`. They matter when you change it.
