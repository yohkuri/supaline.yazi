# Editing the fixture

Two halves of `test/fixture/` cost more to change than they look like they do.
`verify-supaline` says what they are for; this says what they are shaped
against, which is what a change to either has to keep.

## Contents

- The key set, and why the keymap is the only side that proves it was read
- The broken columns, and why they run in a second Yazi
- Three things measured on 26.9.1

## The key set, and why the keymap is the only side that proves it was read

The authority is the only side that has to prove it was read. A reader side
that comes back empty fails loudly with every bound key named at once, while an
empty authority would let all three comparisons pass over nothing. So it is
checked against the keymap's own shape — one `on` line per
`[[mgr.prepend_keymap]]` block — rather than against a count written in the
spec, which would be a fifth place holding the size of the set.

A key the banner offers and nothing binds is refused as well, unless
`NOT_BOUND` says whose it is — `m s` is Yazi's — and an entry there has to
still be offered, so that table cannot fill up with keys the banner has
dropped.

`e2e.py` is left out of that comparison on purpose. It presses `c 2` and
neither `c 1` nor `c 3`, because that key replaces `theme.toml` wholesale and
one swap is all a run whose earlier captures were taken against that file can
afford. Comparing against it would need a list of which keys are exempt, and
that list is the fifth place again.

## The broken columns, and why they run in a second Yazi

The `b` leader draws the columns that are wrong on purpose, one per report
supaline can put on a screen, and `e2e.py` presses all of them in a **second
Yazi with a log of its own**, started once the first has been torn down.

The shape is decided by what it must not be. `report` writes to `yazi.log` as
well as to the screen, and `e2e.py` fails a run in which Yazi logged an error,
so pressing a `b` key in *that* run turns the suite red. The repair is not to
teach the log check an exception — an allowlist there is the one check that
reads the log learning to ignore the errors it was written to find. Two logs
and two absolute claims cost one more Yazi and no exception at all: the clean
run's log check stays unfiltered and still says that run logged no error, and
the second log is read for the opposite thing — one line per broken column, and
that many lines in all, so a line naming anything else has nowhere to sit.

The per-column count of exactly 1 is three claims in one number: the column
reported, `told` held it down across two further `cd`s, and it survived two
`app:theme` rebuilds without re-arming. The run presses all four for that
reason and checks none of them separately.

## Three things measured on 26.9.1

Each of these is why some of `e2e.py` is shaped the way it is, and each was
measured rather than reasoned about.

- `ya.notify` does reach a `tmux capture-pane`, drawn as a bordered box over
  the preview pane. That is the half of a report no log can show, and until
  this run existed nothing outside the stub looked at it.
- Yazi draws **three** notifications at a time and queues the rest, each for
  the twenty seconds `report` asks for. Six reports therefore never share a
  screen, so the check reads the screen until every one has been seen on it
  rather than taking a single shot. The file it builds is a union, and the
  claim is that each report reached the screen — not that they were ever there
  together.
- The box title carries a Nerd Font icon between `╭` and the word, so a
  matcher written as `╭ supaline` matches nothing. What the check anchors on
  is the column name in backticks, which the first line of the box carries.
