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
makes the call rather than against the stub.

`stub.file` and `stub.folder` claim `supaline.File` and `supaline.Folder`
rather than `table`, and `run.lua` types the global the specs reach them
through, so a spec reading a field Yazi does not have is refused along with the
plugin that would have read it. That is the whole of what it buys: the class is
not `(exact)`, so the stub's own table is accepted however little of it is
filled in. The annotation is a claim about Yazi, not a check on this file —
fidelity is still read against a running Yazi.

## What a spec's calls are checked against

A spec's calls into the plugin are not checked against `main.lua`. Under
`lua-language-server`, `require(".main")` reaches `types.yazi`'s own `main.lua`
instead — annotations with no `return`, sitting on `workspace.library` — so
`main.setup(42, ...)` and `main.columnn(...)` are both accepted unless
`main.lua` declares `supaline.Main` and each spec claims it at the `require`.
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
none until someone gives it one. `column.normalizze({}, {})` passes on the line
above a refused `column.normalize(42, {})` for any module whose table carries no
class. `column.lua`'s carries `supaline.ColumnModule`; `th` carries nothing at
all, so it takes whatever name a spec spells.

Plant it below the line that binds the value. Above it the checker reports
`undefined-global` at the planted line — still a refusal, but of the probe and
not of the misspelling, which a harness grepping for the field name scores as a
module that refuses nothing.

Deliberately wrong values are a spec's stock in trade, and they now cost
something: a class on the configuration means `column.normalize(42, ...)` and
`{ linemodes = { detail = "size" } }` are refused by the checker as well as by
the code under test. Suppress those on the line, with
`---@diagnostic disable-next-line`, and never at the top of the file — a
blanket disable there grows to cover code nobody meant to exempt.

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

The same spec holds the fixture's **key set** together. Four places name that
set — `test/fixture/keymap.toml`, `test/fixture/banner.txt`, `test/MANUAL.md`,
and `e2e.py`'s capture loops — and the banner is the only one whose reader is a
person, so it is the one that can fall behind with everything still green. The
keymap is the authority and the spec names no key of its own: it reads the `on`
lines, then asks whether the banner offers each and whether `MANUAL.md` spells
each. A key the banner offers and nothing binds is refused as well, unless
`NOT_BOUND` says whose it is — `m s` is Yazi's — and an entry there has to
still be offered, so that table cannot fill up with keys the banner has
dropped.

Two things to know before editing that half. The authority is the only side
that has to prove it was read: a reader side that comes back empty fails loudly
with every bound key named at once, while an empty authority would let all
three comparisons pass over nothing. So it is checked against the keymap's own
shape — one `on` line per `[[mgr.prepend_keymap]]` block — rather than against
a count written in the spec, which would be a fifth place holding the size of
the set. And `e2e.py` is left out on purpose: it presses `c 2` and neither
`c 1` nor `c 3`, because that key replaces `theme.toml` wholesale and one swap
is all a run whose earlier captures were taken against that file can afford.
Comparing against it would need a list of which keys are exempt, and that list
is the fifth place again.

The fixture opens on a directory carrying the cases that break width
arithmetic — CJK, emoji, an over-long name, sizes either side of the 1K
boundary — with siblings above it and a subdirectory below, so all three panes
have rows. `m0` to `m9`, and `me` once the digits ran out, switch between the
linemodes, one per decision worth looking at, and `test/MANUAL.md` says what to
look for in each. Yazi's own `m s` and `m n` still work, which is what makes
them worth comparing against.

A third leader, `b`, draws the columns that are wrong on purpose -- one per
report supaline can put on a screen. `e2e.py` presses all of them, in a
**second Yazi with a log of its own**, started once the first has been torn
down. The clean run's log check is untouched and unfiltered: it still says that
run logged no error at all. The second log is read for the opposite thing --
one line per broken column, and that many lines in all, so a line naming
anything else has nowhere to sit.

The shape is decided by what it must not be. `report` writes to `yazi.log` as
well as to the screen, and `e2e.py` fails a run in which Yazi logged an error,
so pressing a `b` key in *that* run turns the suite red. The repair is not to
teach the log check an exception -- an allowlist there is the one check that
reads the log learning to ignore the errors it was written to find. Two logs
and two absolute claims cost one more Yazi and no exception at all.

Three things about that run were measured on 26.9.1 rather than reasoned about,
and each one is why some of the code is shaped the way it is:

- `ya.notify` does reach a `tmux capture-pane`, drawn as a bordered box over
  the preview pane. That is the half of a report no log can show, and until
  this run existed nothing outside the stub looked at it.
- Yazi draws **three** notifications at a time and queues the rest, each for
  the twenty seconds `report` asks for. Six reports therefore never share a
  screen, so the check reads the screen until every one has been seen on it
  rather than taking a single shot. The file it builds is a union, and the
  claim is that each report reached the screen -- not that they were ever
  there together.
- The box title carries a Nerd Font icon between `╭` and the word, so a
  matcher written as `╭ supaline` matches nothing. What the check anchors on
  is the column name in backticks, which the first line of the box carries.

The per-column count of exactly 1 is three claims in one number: the column
reported, `told` held it down across two further `cd`s, and it survived two
`app:theme` rebuilds without re-arming. The run presses all four for that
reason and checks none of them separately.

What is left for a person is what none of that can judge -- whether the
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

Both are already handled inside `e2e.py`. They matter when you change it.
