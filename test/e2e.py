#!/usr/bin/env python3
"""Render supaline in a real Yazi and check what comes back.

The unit tests stub the Yazi globals, so they can say nothing about rendering.
This can, and it is the only thing that can: both layout bugs found so far were
invisible to the unit tests until something drew them.

    test/e2e.py            run it
    test/e2e.py --keep     leave the scratch directory behind

The configuration and the fixture come from `test/setup.py`, which `manual.py`
also uses, so this and the interactive run cannot drift apart.

Needs tmux. Yazi queries the terminal at startup and aborts if nothing answers,
so a `script`-style pseudo-terminal will not do; tmux is a real terminal
emulator.

Nothing here sleeps for a fixed time. Every wait is either a predicate on the
screen or a settle -- both bounded by a deadline, both adaptive, and both
saying what they were waiting for when they give up.
"""

from __future__ import annotations

import grp
import os
import pwd
import re
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import screen as sc
import setup as fixture
from harness import (
    ROOT,
    Checks,
    Session,
    need,
    require_python,
    run,
    yazi_env,
)

#: The window every capture is taken in. Wide enough that the three panes all
#: have room, and 40 rows so about 37 of `colour/ramp`'s 64 steps reach a
#: capture.
WIDTH, HEIGHT = 170, 40

#: The floor under every ramp check. The window is 40 rows and the header and
#: the folder take some, so about 37 of the 64 steps reach a capture. The floor
#: is well under that: what would drop it is a ramp that stopped drawing, and
#: no terminal this runs in shows fewer.
RAMP_FLOOR = 24

#: The floor under `c_scale`, which reads `colour/scale` rather than
#: `colour/ramp`. That folder holds 21 files and all 21 fit a 40-row window,
#: so this sits well under it: what would drop it is a column that stopped
#: drawing, not a window that got shorter.
SCALE_FLOOR = 16

#: What counts as an error in a Yazi log, on either side of the run.
TROUBLE = re.compile(r"ERROR|WARN|attempt to|error converting", re.IGNORECASE)


class Run:
    """The scratch directory, the session, and the captures taken from it."""

    def __init__(self, keep: bool) -> None:
        # Both names carry the PID, so a run owns everything it touches. A
        # fixed scratch directory is not safe either: `setup.py` refuses one
        # that does not carry its marker file, but a concurrent run of this
        # harness left that marker, so the guard passes and the removal takes
        # the other run's fixture out from under its Yazi.
        pid = os.getpid()
        self.dir = Path(tempfile.gettempdir()) / f"supaline-e2e.{pid}"
        self.session = Session(f"supaline-e2e-{pid}")
        self.keep = keep
        self.shots: dict[str, str] = {}

    # --- the fixture -------------------------------------------------------

    def setup(self) -> None:
        """Imported and called, the way `manual.py` calls it.

        A subprocess would be the same fixture and a worse refusal: `setup.py`
        prints its own sentence and exits 2, and `run` would print a second,
        emptier one over the top of it.
        """
        fixture.main([str(self.dir)])

    def teardown(self) -> None:
        self.session.kill()
        if not self.dir.is_dir():
            return
        if self.keep:
            print(f"kept: {self.dir}")
            return
        fixture.main(["--clean", str(self.dir)])

    # --- driving -----------------------------------------------------------

    def open_yazi(self, state: str) -> None:
        """Start Yazi on `data/`, with a state directory of its own.

        The environment is `harness.yazi_env`, which `manual.py` opens the
        same fixture with; spelled out here as an `env` prefix because what
        tmux takes is a command line rather than a mapping.
        """
        env = " ".join(
            f"{name}='{value}'"
            for name, value in yazi_env(self.dir, state).items()
        )
        self.session.start(
            f"env {env} yazi '{self.dir}/fixture/data'",
            width=WIDTH,
            height=HEIGHT,
        )
        # A name out of the fixture rather than a fixed wait. This is both
        # faster than the four seconds it replaces and stronger: it says Yazi
        # got as far as listing the folder, where a sleep says only that time
        # passed.
        self.session.wait_for(
            lambda s: "exactly-1k.bin" in s,
            "the fixture listed",
            timeout=30,
        )

    def shot(self, label: str) -> None:
        """Keep both captures of the screen as it stands, in memory and on disk.

        On disk because `--keep` is for reading them afterwards, and a check
        that failed is answered by the capture it failed on.
        """
        plain = self.session.capture()
        colour = self.session.capture(colour=True)
        self.shots[label] = plain
        self.shots[f"colour-{label}"] = colour
        (self.dir / f"screen-{label}.txt").write_text(plain)
        (self.dir / f"color-{label}.txt").write_text(colour)

    def goto(self, key: str) -> None:
        """Press a `g` key and wait until the folder it names is on screen.

        The predicate is a name only that folder holds, so this says the `cd`
        arrived rather than that a second went by. Every `g` key in this run
        gets one, and the name comes out of `FOLDERS` rather than from the
        caller: a pair that could disagree is a wait on the wrong folder.
        """
        expect = FOLDERS[key]
        self.session.press(
            "g",
            key,
            until=lambda s: expect in s,
            what=f"`{expect}` after g {key}",
        )


def clean_run(r: Run) -> None:
    """The run that is meant to log nothing, and every capture read below."""
    r.open_yazi("state")

    # Every linemode the manual harness offers, so a broken one cannot hide.
    # `e` is one of them: the digits ran out before the cases did, and `m e` is
    # a key like any other.
    for n in "0123456789e":
        r.session.press("m", n)
        # Switching linemode does not re-peek the preview; move the hover to
        # force one, so the preview pane is drawn under the mode now active.
        r.session.press("j")
        r.session.press("k")
        r.shot(f"m{n}")

    # The colour linemodes, for the reason the loop above exists: an
    # unregistered name is drawn as literal text and one that threw takes the
    # rows with it, and neither surfaces anywhere until a person runs
    # `manual.py`. Each is pressed in the folder it is meant to be read in,
    # because the spread of values in the folder being drawn is what decides
    # what a ramp puts on screen.
    #
    # What this does *not* do is judge any of them. That is the whole point of
    # their existing -- `MANUAL.md` says which questions a reader is the only
    # instrument for, and `c_hue` is there precisely because the ramp check
    # further down would go red on it while it was perfectly correct.
    #
    # The `c` key settles rather than waiting on a name: two colour linemodes
    # over one folder draw the *same text* in different colours, so there is no
    # plain-text predicate to write and the colour capture is what the checks
    # read.
    for folder, key, label in COLOUR_MODES:
        r.goto(folder)
        r.session.press("c", key)
        r.shot(label)

    # m3 states one size column at 10 and measures the other, so the widths
    # have to disagree -- and the measured one has to change when the folder
    # does. `bind`'s per-folder cache key is the piece most likely to get that
    # wrong.
    r.session.press("m", "3")
    r.goto("2")
    r.shot("m3-nested")
    r.goto("1")

    # Last of everything, because it rewrites the theme every capture above was
    # taken under. Back to m1 first, so a `size` column and an `mtime` one are
    # both on screen to be recoloured.
    r.session.press("m", "1")
    r.shots["theme-before"] = r.session.capture(colour=True)

    # Both shapes at once, for the reason `THEME_EDIT` gives: a ramp resolved
    # once and cached past the reload would hold its old endpoints with the
    # flat colour beside it already correct, and the flat half alone would not
    # notice.
    theme = r.dir / "config" / "theme.toml"
    body = theme.read_text()
    for old, new in THEME_EDIT:
        body = body.replace(old, new)
    theme.write_text(body)
    r.session.press("T")
    r.shots["theme-after"] = r.session.capture(colour=True)

    # Last of all, because it replaces `theme.toml` wholesale and every check
    # above reads a capture taken against the file this run had been editing in
    # place.
    #
    # The `c 1` to `c 3` keys are the only part of either harness that leaves
    # Yazi to do its work -- a `shell` template running a script that copies a
    # theme into place -- and a person pressing one sees a colour that did not
    # change, with no way to tell a plugin that ignored the reload from a copy
    # that never ran. So the file is compared as well as the screen.
    r.session.press("c", "2")
    r.shots["theme-swapped"] = r.session.capture(colour=True)

    r.session.press("q")
    # Explicit rather than left to the teardown: the checks read what Yazi
    # wrote, so it has to be gone before they run.
    r.session.kill()


def broken_run(r: Run) -> None:
    """A second Yazi, with a log of its own, for the columns that are wrong.

    The separate log is the whole design rather than a convenience: the check
    below goes on saying that the run above logged no error *at all*,
    unfiltered and unexcused, and the errors this run makes happen in a
    different file that is read for the opposite thing. Neither check learns an
    exception, which is what an allowlist over one log would have been.

    There is a second reason to keep them apart. `g 6` arms a `refresh` that
    throws at every `cd` after it, and `told` reports a column once a session,
    so any capture taken past that point comes from a session that can no
    longer report. Every capture above is left exactly as it was.
    """
    r.open_yazi("state-broken")

    for key in "rswug":
        r.session.press("b", key)

    # `b f` draws the counting pair and breaks nothing by itself; `g 6` is what
    # throws the `refresh`. Last, because every `cd` after it throws again.
    r.session.press("b", "f")
    r.goto("6")

    # A union over many captures, not one capture, because six reports do not
    # fit on the screen at once. Measured on 26.9.1: Yazi draws **three**
    # notifications at a time and queues the rest, each for the twenty seconds
    # `report` asks for, so a fourth takes the first one's place as it expires.
    # A single shot taken here holds the first three and would report the other
    # three as never drawn.
    #
    # So the screen is read until every report has been seen on it, and what is
    # kept is the union rather than a picture -- the claim being made is that
    # each report reached the screen, not that they were ever there together.
    # The deadline is generous against the drain it is waiting for, which is
    # bounded by those twenty seconds.
    wanted = broken_columns()
    seen: list[str] = []
    began = time.monotonic()
    deadline = began + 60
    while time.monotonic() < deadline:
        seen.append(r.session.capture())
        union = "\n".join(seen)
        if all(f"`{c}`" in union for c in wanted):
            break
        time.sleep(0.25)
    waited = time.monotonic() - began
    print(f"e2e: the reports drained to the screen in {waited:.0f}s")
    r.shots["broken"] = "\n".join(seen)
    (r.dir / "screen-broken.txt").write_text(r.shots["broken"])

    # Everything after the capture is there to make one report come back if the
    # gates that hold it down let go. Two more `cd`s, since a `refresh` that
    # throws throws again at every folder walked into; then two `app:theme`
    # presses, since a theme event rebuilds every column and the gate has to
    # survive being recompiled. Nothing here is checked on its own -- it is the
    # same per-column count below that answers all of it, by still being 1.
    r.goto("1")
    r.goto("2")
    r.session.press("T")
    r.session.press("T")

    r.session.press("q")
    r.session.kill()


#: Each colour linemode: the folder it is read in, the `c` key that reaches
#: it, and the label its captures are kept under. One table because two
#: readers need it -- written twice, a mode added to the presses alone would
#: be drawn, asserted on by nobody, and green.
COLOUR_MODES = (
    ("3", "r", "c_ramp"),
    ("3", "b", "c_band"),
    ("3", "h", "c_hue"),
    ("3", "g", "c_bg"),
    ("3", "a", "c_bold"),
    ("4", "s", "c_scale"),
    ("5", "e", "c_edge"),
    ("1", "t", "c_theme"),
)


#: The edit `T` is pressed against, and the colours either side of it. One
#: table because two readers need it -- the rewrite that makes the change and
#: the check that reads it off the screen, nine hundred lines apart -- and a
#: pair written twice is a pair that drifts into asserting on a colour nothing
#: wrote. Both shapes a `[supaline]` value can take are here, because they are
#: rebuilt by different code: a flat colour is one `ui.Style` and a ramp is
#: `STEPS` of them, built from endpoints parsed out of the string. These are
#: the values `themes/default.toml` spells, which says so beside them.
THEME_EDIT = (
    ("#ff8800", "#00ccff"),
    ("#0b3d91 -> #7fd4ff", "#1a5e00 -> #9bff66"),
)

#: A name only the folder behind each `g` key holds, so the press can be waited
#: on rather than slept through.
FOLDERS = {
    "1": "exactly-1k.bin",
    "2": "inner-a.txt",
    "3": "step-00.txt",
    "4": "pow-00.bin",
    "5": "same-a.txt",
    "6": "a-longer-name.txt",
}


def broken_columns() -> list[str]:
    """The columns the fixture registers as wrong on purpose.

    Read out of the fixture rather than written here, the way every colour
    asserted on below is a hex string that file spells verbatim. Register a
    seventh and this run goes red until a key for it is pressed above, which is
    the direction the list has to grow in.
    """
    body = (ROOT / "test" / "fixture" / "init.lua").read_text()
    return re.findall(r'^supaline\.column\("(torn_[a-z]*)"', body, re.MULTILINE)


def lines_with(text: str, needle: str) -> int:
    """Lines of `text` carrying `needle`. What `grep -c` counts, and why.

    A colour appears once per cell that drew in it and a row may hold several,
    so a count of occurrences and a count of rows are different numbers. The
    rows are the one every claim below is written against.
    """
    return sum(1 for line in text.splitlines() if needle in line)


def check_log(k: Checks, path: Path) -> None:
    k.section("log")
    body = path.read_text() if path.is_file() else ""
    bad = [line for line in body.splitlines() if TROUBLE.search(line)]
    if bad:
        for line in bad[:10]:
            print(line, file=sys.stderr)
        k.fail("Yazi logged an error")
    else:
        k.ok("clean")


def check_reports(k: Checks, path: Path, shown: str) -> None:
    """The other half of that check, and why it needed no exception.

    The one above says the run that is meant to be clean logged nothing; this
    says the run that is meant to go wrong logged exactly what it was told to.
    Two logs, two absolute claims, no line filtered out of either.
    """
    k.section("the reports")
    wanted = broken_columns()
    if not wanted:
        # One of the two guards the counts inherit. An empty list makes every
        # one of them pass over nothing, quietly.
        k.fail(
            "no broken column is registered in test/fixture/init.lua; "
            "this check is reading nothing"
        )
        return
    if not path.is_file():
        # The other. There is no log at all unless `YAZI_LOG` was set before
        # Yazi started, and the path is Yazi's to lay out under
        # `XDG_STATE_HOME` -- so this is reachable rather than theoretical, and
        # a missing file has to be said rather than counted as zero.
        k.fail(
            f"the broken run wrote no log at {path}; this check is reading "
            "nothing"
        )
        return

    body = path.read_text()
    errors = [line for line in body.splitlines() if TROUBLE.search(line)]

    # A total beside the per-column counts, so the pair is closed: each name
    # exactly once and this many lines in all leaves no room for a line naming
    # something else, and none of it is spelled as "ignore these".
    if len(errors) != len(wanted):
        # Printed, not asserted on: the counts below name any column that
        # reported twice or not at all, so what is left to show is a line
        # naming no column of ours. Cut short because a report carries its
        # whole traceback on the line with it.
        for line in [e for e in errors if "torn_" not in e][:5]:
            print(line[:120], file=sys.stderr)
        k.fail(
            f"the broken run logged {len(errors)} error line(s), expected "
            f"{len(wanted)} -- one per broken column"
        )
    else:
        k.ok(f"{len(errors)} error lines, one per broken column")

    for column in wanted:
        # Exactly one, which is three claims in one number: the column
        # reported, `told` held it down across two further `cd`s, and it
        # survived two `app:theme` rebuilds without re-arming.
        logged = lines_with(body, f"`{column}`")
        # The half no log can show. `ya.notify` draws a bordered box over the
        # preview pane and tmux captures it like anything else, so a report
        # that reached the log and not the screen is visible here and nowhere
        # else.
        on_screen = lines_with(shown, f"`{column}`")
        if logged != 1:
            k.fail(
                f"{column}: {logged} line(s) in the broken run's log, "
                "expected exactly 1"
            )
        elif on_screen == 0:
            k.fail(f"{column}: reported to the log and not to the screen")
        else:
            k.ok(f"{column} reported once, to the log and to the screen")


def check_rows_present(k: Checks, shots: dict[str, str]) -> None:
    """Yazi is alive and every linemode name resolved.

    An unregistered one is drawn as literal text and a linemode that threw
    takes the rows with it. This does *not* prove any of them drew a column,
    because the file names satisfy it on their own -- m6 to m8 rendering
    nothing in the current pane passed this and every pane check below. The
    columns are what the two sections after it are for.
    """
    k.section("every linemode left the rows on screen")

    def have(summary: str, labels: list[str]) -> None:
        # Row 3 clears the header, and 8 is inside the shortest listing any
        # capture here holds.
        blank = [
            n
            for n in labels
            if not any(
                re.search(r"[A-Za-z0-9]", row)
                for row in sc.rows(shots[n], 3, 8)
            )
        ]
        for n in blank:
            k.fail(f"{n}: the rows came back blank")
        if not blank:
            k.ok(summary)

    have(
        "m0 to m9 and me all have rows",
        [f"m{n}" for n in "0123456789e"],
    )
    # The same for the colour modes, which are reached by two keys rather than
    # one and are read in folders of their own -- so a blank one here is as
    # likely to be the key, or the `cd` behind it, as the linemode. Which of
    # the three it was is not worth telling apart: nothing else in this run
    # visits those folders.
    have(
        f"the {len(COLOUR_MODES)} colour modes all have rows",
        [label for _, _, label in COLOUR_MODES],
    )


def check_columns(k: Checks, shots: dict[str, str]) -> None:
    k.section("columns")
    k.holds(shots["m0"], "87.9M", "m0: size")
    k.holds(shots["m1"], "87.9M 05/06  2024", "m1: size + mtime")
    k.holds(shots["m2"], "drwxr-xr-x", "m2: permissions")

    check_owner(k, shots["m2"])
    check_overflow(k, shots["m4"])

    # m3: `size` stated at 10 beside `size` measured. In `data/` the widest
    # size is "1023.4K", so the measured column is 7 and the two are three
    # spaces apart.
    k.holds(
        shots["m3"],
        "1024B   1024B",
        "m3: a stated width and a measured one differ",
    )
    # ... and in `nested/` the widest is "300K", so it narrows to 4.
    k.holds(
        shots["m3-nested"],
        "      300K 300K",
        "m3: the measured width follows the folder",
    )
    # Neither of those pins the *stated* column: Yazi absorbs whatever the
    # linemode does not use into the file name's padding, so the spaces to the
    # left of the first column stay put however wide it is. The one row that
    # cannot absorb anything is the one whose name Yazi had to truncate --
    # there the name fills its budget exactly, so the gap after it is the
    # stated column's own padding: one space of separator, then 10 less the two
    # cells of "1B".
    k.holds(
        shots["m3"],
        "….txt         1B",
        "m3: a stated width does not shrink to fit",
    )

    # m5: `ext` (5, left), then `size` with `separator = false`, then `mtime`
    # behind the divider.
    k.holds(
        shots["m5"],
        "bin    1024B" + sc.BAR,
        "m5: separator = false and a separator of a column's own",
    )
    # The colour the separator was given, and immediately before the glyph it
    # was given for. Greened anywhere in the capture would pass for a colour
    # that landed on the wrong span.
    k.holds(
        shots["colour-m5"],
        sc.sgr(38, "#a6e3a1") + sc.BAR,
        "m5: that separator is drawn in its own colour",
    )

    # m9: a registered column, one clipped to 8 without an ellipsis, and a bare
    # function in the spec.
    k.holds(shots["m9"], "bin   exactly- file", "m9: user-written columns")
    k.holds(shots["m9"], "never-op ", "m9: a clipped cell carries no ellipsis")


def check_owner(k: Checks, capture: str) -> None:
    """`owner`, `user` and `group` against this machine's own names.

    Those columns hold this machine's `user:group`, so what their cells should
    say cannot be written down here -- it depends on how long that is. The
    cells come off the screen through `screen.owner_cells`, which is where the
    shape of an m2 row is now stated and unit-tested; what is left here is
    holding them against `pwd` and `grp`, which is the half only a real
    machine can answer.
    """
    who = (
        f"{pwd.getpwuid(os.geteuid()).pw_name}:"
        f"{grp.getgrgid(os.getegid()).gr_name}"
    )
    rows = sc.owner_cells(capture)
    if not rows:
        k.fail("m2: no permissions field on screen, and no cells behind one")
        return

    def agreed(what: str, cells: set[str]) -> str:
        """The one cell every m2 row agrees on, or empty with a fault said.

        Every row lists a file this run created, so all of them carry the same
        two names; a set with two things in it is a column reading something
        per row that it should be reading per machine.
        """
        if len(cells) > 1:
            k.fail(
                f"m2: the rows disagree on the {what}: "
                f"{' '.join(sorted(cells))}"
            )
            return ""
        return next(iter(cells))

    seen = agreed("owner cell", {r.owner for r in rows})
    dots = seen.count("…")
    if not seen:
        pass  # `agreed` has already said so
    elif seen == who:
        k.ok(f"m2: the owner column holds `{who}` whole, with no ellipsis")
    elif dots != 1:
        k.fail(
            f"m2: the owner cell carries {dots} ellipses, wanted one -- "
            f"`{seen}`"
        )
    elif sc.is_cut_of(who, seen):
        k.ok(f"m2: the owner column cuts `{who}` with one ellipsis")
    else:
        k.fail(f"m2: the owner cell `{seen}` is not a cut of `{who}`")

    # `user` and `group` draw those same two names again, eight cells each
    # rather than twelve shared, so each is cut on its own length and on most
    # machines the pair comes out whole where `owner` beside it did not. Both
    # halves come off one row of one reader, so the two cannot end up measured
    # against different names -- and each is held against its own half, since
    # either may be the one that had to be cut.
    want_user, want_group = who.split(":", 1)
    got_user = agreed("user cell", {r.user for r in rows})
    got_group = agreed("group cell", {r.group for r in rows})
    if got_user and got_group:
        bad = []
        if not sc.is_cut_of(want_user, got_user):
            bad.append(f"`{got_user}` is not a cut of `{want_user}`")
        if not sc.is_cut_of(want_group, got_group):
            bad.append(f"`{got_group}` is not a cut of `{want_group}`")
        if bad:
            k.fail("m2: " + " ".join(bad))
        else:
            k.ok(f"m2: the user and group columns hold the halves of `{who}`")


def check_overflow(k: Checks, capture: str) -> None:
    """m4 puts one over-long name through ellipsis, clip and grow.

    The same row must carry all four renderings of it. Reading the screen as a
    whole is not enough: Yazi truncates long names in the parent pane by
    itself, and that ellipsis would satisfy a looser check.

    The cells are given as one string, the separators and the padding between
    them included, so this reads the columns' widths as well as where each cut
    landed -- a cell that came back one short moves every space after it and
    the match stops.
    """

    def row(label: str, name: str, cells: str) -> None:
        found = next(
            (line for line in capture.splitlines() if name in line), None
        )
        if found is None:
            k.fail(f"m4: {label} -- no row on screen carries `{name}`")
        elif cells in found:
            k.ok(f"m4: {label}")
        else:
            k.fail(f"m4: {label}")

    # `exactly-1k.bin` is 14 characters against a column of 12, and short
    # enough that all four cells stay on screen. The two clips have to agree: a
    # column that hands back a renderable is not a narrower column, and
    # `Line:truncate` drops the character that lands exactly on the width, so
    # the second of them read "exactly-1k." until `cell` asked for that cell
    # back. Nothing else in the fixture takes the renderable path.
    row(
        "ellipsis, clip, a clipped renderable and grow, on one row",
        "exactly-1k",
        "exactly-1k.… exactly-1k.b exactly-1k.b exactly-1k.bin",
    )
    # The same four against a name of wide characters, where a cut can land
    # between a character's two cells and leave the column a cell short. Both
    # of Yazi's truncations count characters where the screen counts cells,
    # which is the trap `truncate_spec.lua` pins in the arithmetic; this is the
    # one place it is read off a screen.
    #
    # The name is 13 characters and 22 cells against a column of 12. Five of
    # them and an ellipsis come to 11, so the ellipsis cell pads to 12 -- that
    # pad is the second space, and it is what a cut landing mid character would
    # take away. The two clips take six characters for 12 exactly.
    row(
        "a wide name is cut between characters, and the cell still fills",
        "日本語",
        "日本語のフ…  日本語のファ 日本語のファ 日本語のファイル名.txt",
    )
    # And the same where the wide character is four bytes rather than three.
    # Not one case twice: the emoji and the kanji are both one character of two
    # cells, so a cut that measured bytes can be right about one name and wrong
    # about the other. The emoji is in the fixture because `unicode-width`
    # gives emoji presentation two cells, which `truncate_spec.lua` pins the
    # stub against. The name is 20 cells: four characters come to 10 and the
    # ellipsis to 11, then the pad, and the clips take five for 12 exactly.
    row(
        "a four-byte character is cut and measured like any other",
        "絵文字",
        "絵文字🎨の…  絵文字🎨のな 絵文字🎨のな 絵文字🎨のなまえ.txt",
    )


def check_panes(k: Checks, shots: dict[str, str]) -> None:
    """m6 asks for the current pane alone, so its edges are the baseline.

    Comparing whole panes rather than grepping for a column keeps this
    independent of which columns the fixture happens to use.
    """
    k.section("panes")
    bare_parent = sc.parent_of(shots["m6"])
    bare_preview = sc.preview_of(shots["m6"])

    # All three ask for the current pane, and nothing else here looks at it:
    # the section above matches the file names, and everything below compares
    # the other two panes against m6. A `pane_cur`, `pane_par` and `pane_prev`
    # drawing nothing where they were asked to would pass the rest of the run.
    for n in "678":
        drew = sc.marked(sc.current_of(shots[f"m{n}"]))
        rows = sc.drawn(sc.current_of(shots[f"m{n}"]))
        k.same(
            drew,
            rows,
            f"m{n}: every current-pane row carries the marker "
            f"({drew} of {rows})",
        )

    # And the same claim of the pane m7 is *for*, which had been the weak half
    # of this section: `differs` against m6's bare pane passes on any
    # difference at all -- a hover that moved, a name Yazi truncated
    # differently, a pane drawing nothing but the file names it draws anyway.
    # The parent pane is where that costs most. A linemode child being called
    # for parent-pane rows is one of the four traps `AGENTS.md` says nothing
    # pins, and this is the row window where it would show.
    drew = sc.marked(sc.parent_of(shots["m7"]))
    rows = sc.drawn(sc.parent_of(shots["m7"]))
    k.same(
        drew,
        rows,
        f"m7: every parent-pane row carries the marker ({drew} of {rows})",
    )

    # The pass and fail arms are inverted between neighbouring checks here,
    # which is exactly the shape that hides a mistake when it is spelled out
    # five times.
    k.same(sc.parent_of(shots["m8"]), bare_parent, "m8: parent pane left alone")
    k.same(
        sc.preview_of(shots["m7"]), bare_preview, "m7: preview pane left alone"
    )

    # A pane key has to hold for every row of the preview pane, not just the
    # one Yazi marks `in_preview` -- it sets that on the previewed folder's
    # cursor row alone, so a check that passes on one row proves nothing about
    # the second.
    drew = sc.marked(sc.preview_of(shots["m8"]))
    k.same(drew, 2, f"m8: preview pane drawn, both rows (drew {drew})")

    # Both of them, now that one reader answers either pane. The label had
    # claimed both edges while reading the right-hand one alone.
    k.same(
        sc.marked(sc.parent_of(shots["m6"]))
        + sc.marked(sc.preview_of(shots["m6"])),
        0,
        "m6: both edges left alone",
    )

    # `me` names the same two panes as m7 and gives each a list of its own.
    # Read against m7, which hands one list to both, so it says the two agree
    # about the parent pane and disagree about the middle one -- which is the
    # whole of what a list per pane adds.
    k.same(
        sc.parent_of(shots["me"]),
        sc.parent_of(shots["m7"]),
        "me: the parent pane draws what m7 drew",
    )
    # A pane drawing nothing at all would satisfy `differs` too -- strip the
    # columns and Yazi's own file names are left, and those differ from a
    # marked row. The line after it is the other half: the cells that pane was
    # actually given. `ext` then `size`, on the one file in the fixture whose
    # size is written to be read: five cells left-aligned, a separator, seven
    # right-aligned.
    k.differs(
        sc.current_of(shots["me"]),
        sc.current_of(shots["m7"]),
        "me: the current pane draws columns of its own",
    )
    k.that(
        any("bin     1024B" in row for row in sc.current_of(shots["me"])),
        "me: ... and they are the ext and size it was given",
    )
    k.same(
        sc.preview_of(shots["me"]),
        bare_preview,
        "me: the pane nobody named is bare",
    )


def check_ramp(k: Checks, shots: dict[str, str], init: str) -> None:
    k.section("the ramp")

    # The ends and the steps between them are read in different folders,
    # because no one folder shows both well.
    #
    # The ends are read off `m 1` in `data/`, where the ramp is the *themed*
    # one: `[supaline] mtime` is `#0b3d91 -> #7fd4ff`, and the fixture's mtimes
    # run from 2020 to today, so the oldest row draws the low end and a file
    # the fixture just created draws the high one. A column that resolved the
    # ramp string as a flat colour, or failed to resolve it at all, can only
    # put one colour on screen, and this is where that is caught.
    #
    # `colour/ramp` cannot do it: 64 rows, a window that shows the first 37 of
    # them, and the high end at the bottom.
    k.holds(
        shots["colour-m1"],
        sc.sgr(38, "#0b3d91"),
        "a themed ramp draws its low end",
    )
    k.holds(shots["colour-m1"], sc.sgr(38, "#7fd4ff"), "... and its high end")

    def rows_hold(label: str, ramp: list[sc.RampRow], monotone: bool) -> None:
        """Enough rows, and no fault in the sequence."""
        faults = sc.ramp_faults(ramp, monotone)
        if len(ramp) < RAMP_FLOOR:
            k.fail(
                f"{label}: only {len(ramp)} row(s) carried a ramp colour, "
                f"wanted {RAMP_FLOOR}"
            )
        elif faults:
            k.fail(f"{label}: {';'.join(faults[:3])}")
        else:
            k.ok(f"{label} ({len(ramp)} consecutive steps)")

    # One file per step, so consecutive rows are consecutive steps and this is
    # the only place the quantisation itself is read. What it still cannot ask
    # is whether a reader can see one step from the next; `MANUAL.md` keeps
    # that.
    rows_hold(
        "every step climbs, and none repeats the one above",
        sc.ramp_rows(shots["colour-c_ramp"]),
        True,
    )
    # The same rows on a band, whose endpoints were derived rather than
    # written. Monotone is asked of it for a reason of its own: every step of a
    # band is the same colour at another exposure, so all three channels move
    # together by construction -- measured over the 64 steps, zero reversals
    # and zero identical adjacent pairs. A band that came back flat, or that
    # turned on the way, is a derivation that went wrong rather than a ramp a
    # user wrote.
    rows_hold(
        "a band climbs too, on endpoints nobody wrote",
        sc.ramp_rows(shots["colour-c_band"]),
        True,
    )
    # The same rows on a ramp that turns in hue. Only half the question can be
    # put to it, and that half is put here so the shape is not left with
    # nothing.
    rows_hold(
        "a ramp that turns still draws a step per row",
        sc.ramp_rows(shots["colour-c_hue"]),
        False,
    )

    check_bands(k, shots["colour-c_bg"], init)

    rows_hold(
        "c_bg: a ramp under `bg` climbs a step per row",
        sc.background_rows(shots["colour-c_bg"]),
        True,
    )
    check_bold(k, shots)
    check_scale(k, shots["colour-c_scale"], init)
    check_edge(k, shots["colour-c_edge"], init)


def ground_hex(init: str, name: str) -> str:
    """The flat colour a name in `init.lua` is bound to, or empty.

    Anchored on both sides, so a name bound to anything but one flat colour
    answers nothing. `ratio` writes `bg = COOL` and `COOL` is a ramp: that is
    not a ground, and this is what tells them apart rather than a list.
    """
    found = re.search(
        rf'^local {name} = "(#[0-9a-fA-F]{{6}})"$', init, re.MULTILINE
    )
    return found.group(1) if found else ""


def ramp_ends(init: str, name: str) -> tuple[str, str]:
    """The two endpoints of a ramp `init.lua` binds to a name, or two empties.

    Read out of the fixture for the reason `ground_hex` is read out of it: a
    hex written here as well is the copy that goes stale, and a recoloured
    ramp would then report as a plugin that stopped drawing.
    """
    found = re.search(
        rf'^local {name} = "(#[0-9a-fA-F]{{6}}) -> (#[0-9a-fA-F]{{6}})"$',
        init,
        re.MULTILINE,
    )
    return (found.group(1), found.group(2)) if found else ("", "")


def band_width(init: str, name: str) -> int:
    """The width a `c_bg` column states beside the ground it names, or 0.

    A trailing space, comma or close brace, because a style writes the name
    with one of the three after it. It costs nothing and it is what a ground
    named after another one would need.
    """
    found = re.search(rf".*bg = {name}[ ,}}].*width = (\d+)", init)
    return int(found.group(1)) if found else 0


def c_bg_grounds(init: str) -> list[str] | None:
    """Every name `c_bg` writes under a `bg`, or `None` if the block is gone.

    The two answers are different failures and the caller says so differently.
    A block with no grounds in it is a fixture nobody has given one; a block
    this cannot find at all is a sweep that would pass over nothing while
    looking exactly like one that swept -- and the pattern is anchored on
    stylua's indentation, so re-nesting that table is all it takes.
    """
    block = re.search(r"c_bg = \{.*?\n\t\t\},", init, re.DOTALL)
    if not block:
        return None
    return re.findall(r"bg = ([A-Z_]+)[ ,}]", block.group(0))


def check_bands(k: Checks, capture: str, init: str) -> None:
    """`c_bg` draws the same ramp over a ground, and over nothing.

    Three things have to hold of a grounded column, and a reader can check none
    of them against their own terminal's ground -- that ground is the very
    thing a band has to be told apart from, so both of the ones here are
    measured to sit clear of the common ones in Oklab rather than picked.

      - the `bg` is there on every row
      - it covers the cells the stated width pads with, rather than stopping at
        the text, which is what padding before the style is applied is for
      - no second column picked that ground up, which is what the ungrounded
        column is beside it to make answerable

    Both numbers come out of the fixture, addressed by the name it binds them
    to. A width stated twice is the one that goes stale quietly -- widen a
    `c_bg` column for a reason to do with the manual case and a literal here
    would report it as padding applied in the wrong order, the fixture moved
    rather than the plugin. The colour has the same failure and a louder one:
    recolour a ground and a literal here finds no band at all, which reads as a
    plugin that stopped drawing.
    """
    asked: list[str] = []

    def band(label: str, name: str) -> None:
        # Recorded before anything can fail, so the sweep below reads what was
        # asked for rather than what passed.
        asked.append(name)
        want = band_width(init, name)
        hexes = ground_hex(init, name)
        if not want or not hexes:
            k.fail(
                f"{label}: the fixture's init.lua has no flat `local {name}` "
                "under a `bg` with a stated width, so there is no band to "
                "measure"
            )
            return
        got = sc.bands(capture, sc.escaped(48, hexes), want)
        if got.drawn < RAMP_FLOOR:
            k.fail(
                f"{label}: only {got.drawn} row(s) carried a background, "
                f"wanted {RAMP_FLOOR}"
            )
        elif got.narrow:
            k.fail(
                f"{label}: {got.narrow} band(s) were not {want} cells wide -- "
                "the padding is where to look"
            )
        elif got.drawn != got.lines:
            k.fail(
                f"{label}: {got.drawn} band(s) across {got.lines} row(s), so a "
                "row carries more than one"
            )
        else:
            k.ok(f"{label} ({got.drawn} rows, {want} cells)")

    band("a background survives the ramp, padding included", "GROUND")
    # The half of `cell` no test reached until this column carried a ground. It
    # had been read off `yazi-binding` and found consistent, which is not the
    # same as having been drawn.
    band("a background covers a pad beside a nested Line", "LINE_GROUND")

    # And a sweep, because the two calls above are a list and a list goes stale
    # in one direction: a grounded column added to `c_bg` would be drawn, read
    # by nobody, and green. Every flat ground the fixture writes there has to
    # have been asked for by name, and the refusal says what to write.
    grounds = c_bg_grounds(init)
    if grounds is None:
        k.fail(
            "c_bg: the fixture's init.lua has no `c_bg` block this sweep can "
            "find, so a ground added there would be read by nobody"
        )
        return
    for name in grounds:
        if not ground_hex(init, name):
            continue
        if name not in asked:
            k.fail(
                f"c_bg: `{name}` is a ground nothing reads -- write "
                f'`band("<what it claims>", "{name}")` beside the two above'
            )


def check_bold(k: Checks, shots: dict[str, str]) -> None:
    """`c_bold` draws the same ratio twice on one ramp, the left one bold."""
    agreed, disagreed = sc.bold_pairs(shots["colour-c_bold"])
    if agreed < RAMP_FLOOR:
        k.fail(
            f"c_bold: only {agreed} row(s) had a bold cell beside an unbold "
            f"one of the same colour, wanted {RAMP_FLOOR}"
        )
    elif disagreed:
        k.fail(
            f"c_bold: {disagreed} row(s) disagreed -- a colour that moved, or "
            "a bold on the wrong side"
        )
    else:
        k.ok(
            f"c_bold: bold on one column, the ramp's colour on both "
            f"({agreed} rows)"
        )

    # Both of these read an escape rather than a parsed cell, and both are in
    # `screen.py` for it: an escape is the one thing a hand-written capture can
    # state exactly, so the pattern is pinned in CI where the run around it
    # cannot go. `bold_over_paint` is the column that paints per character and
    # `bold_over_ramp` the spec's weight over the theme's colour; each
    # docstring says what its two halves discriminate between. Scoped to the
    # current pane, like every other colour claim in this run.
    k.that(
        sc.bold_over_paint(shots["colour-c_bold"]) > 0,
        "c_bold: the bold reaches the characters permissions paints, "
        "colours kept",
    )
    k.that(
        sc.bold_over_ramp(shots["colour-c_theme"]) > 0,
        "c_theme: a spec's bold over the theme's ramp",
    )


def cool_ends(k: Checks, init: str, who: str) -> tuple[str, str]:
    """The ramp `c_scale` and `c_edge` are both measured against, or empties.

    Shared because both want it and a guard written twice is two sentences
    that drift apart; `who` is what makes the one sentence say which check
    went looking, which neither copy of it did.
    """
    low, high = ramp_ends(init, "COOL")
    if not low:
        k.fail(
            f"{who}: the fixture's init.lua binds no `local COOL` to a "
            "two-ended ramp, so there is nothing to measure against"
        )
    return low, high


def check_scale(k: Checks, capture: str, init: str) -> None:
    """`c_scale` draws one folder's sizes twice, log then linear.

    The numbers are identical -- one `size` column written twice, differing in
    `scale` and in nothing else -- so anything that differs on screen is the
    scale, and that is the whole of what can be asserted here. Whether the
    left column reads as a gradient *to a reader* is `MANUAL.md`'s question
    and stays there.
    """
    low, _ = cool_ends(k, init, "c_scale")
    if not low:
        return
    rows = sc.scale_rows(capture)
    if len(rows) < SCALE_FLOOR:
        k.fail(
            f"c_scale: only {len(rows)} row(s) carried a pair either side of "
            f"the seam, wanted {SCALE_FLOOR}"
        )
        return

    # The premise under both checks below. A row whose halves read differently
    # is a fixture that moved, and the colours would then be two scales
    # compared over two different numbers -- which is not a comparison at all.
    drifted = [r for r in rows if r.log_text != r.linear_text]
    if drifted:
        k.fail(
            f"c_scale: {len(drifted)} row(s) draw a different number either "
            f"side of the seam -- `{drifted[0].log_text}` against "
            f"`{drifted[0].linear_text}`"
        )
        return
    k.ok(f"c_scale: the two scales draw one number ({len(rows)} rows)")

    # The sizes double down the folder, so a log ratio spaces them evenly and
    # a linear one cannot. Said as the two extremes rather than as a
    # threshold on the difference: log takes a step it has not taken before on
    # every row.
    steps = len({r.log_colour for r in rows})
    k.same(
        steps,
        len(rows),
        f"c_scale: log takes a step per row ({steps} of {len(rows)})",
    )

    # ... and linear leaves most of them on the ramp's own low end. Not a
    # number picked to pass: with sizes at 2^0 to 2^20 and the ramp in 38
    # steps, a linear ratio rounds to step 0 for every size under 2^14, which
    # is 14 of the folder's 21 files. A majority is that with room, and what
    # would break it is a ratio that stopped being linear.
    floor = sum(1 for r in rows if r.linear_colour == sc.rgb(low))
    if floor * 2 <= len(rows):
        k.fail(
            f"c_scale: linear holds only {floor} of {len(rows)} rows at the "
            "low end -- it should hold most of them there"
        )
    else:
        k.ok(
            f"c_scale: linear holds {floor} of {len(rows)} at the low end, "
            "where log holds one"
        )


def check_edge(k: Checks, capture: str, init: str) -> None:
    """`c_edge` draws a folder in which every value is the same.

    `hi == lo`, so `ratio` answers 1 rather than dividing by nothing, and
    every row with a value draws the ramp's **high** end -- not its low one,
    and not the flat ground underneath it. A directory has no size, so its
    cell draws the low end instead, which puts both rules on one screen.

    What nothing here should draw is a step in between: a gradient over this
    folder is a ratio that divided by a range of zero.
    """
    low, high = cool_ends(k, init, "c_edge")
    if not low:
        return
    rows = sc.edge_rows(capture)

    # Told apart by what the cell reads rather than by where it sits, which is
    # `sc.is_size`'s claim and is pinned in CI beside it.
    files = [r for r in rows if sc.is_size(r.size)]
    dirs = [r for r in rows if not sc.is_size(r.size)]
    if not files or not dirs:
        # Both kinds are the point: one of them alone leaves half the claim
        # passing over nothing, quietly.
        k.fail(
            f"c_edge: {len(files)} row(s) with a size and {len(dirs)} "
            "without, wanted some of each; this check is reading nothing"
        )
        return

    bad = [
        r for r in files if {r.size_colour, r.ratio_colour} != {sc.rgb(high)}
    ]
    if bad:
        k.fail(
            f"c_edge: {len(bad)} of {len(files)} row(s) with a value did not "
            f"draw the ramp's high end -- `{bad[0].size}` at {bad[0].size_colour}"
        )
    else:
        k.ok(
            f"c_edge: every row with a value is at the high end ({len(files)})"
        )

    astray = [r for r in dirs if r.size_colour != sc.rgb(low)]
    if astray:
        k.fail(
            f"c_edge: {len(astray)} of {len(dirs)} directory row(s) did not "
            f"draw the low end -- `{astray[0].size}` at {astray[0].size_colour}"
        )
    else:
        k.ok(f"c_edge: a directory draws the low end ({len(dirs)} rows)")

    # And the claim the two above cannot make between them: nothing anywhere
    # drew a step. Read over all three cells of every row, so a column that
    # started interpolating is caught even where the two ends are still right.
    seen = {
        c for r in rows for c in (r.size_colour, r.ratio_colour, r.date_colour)
    }
    between = seen - {sc.rgb(low), sc.rgb(high)}
    if between:
        k.fail(
            f"c_edge: {len(between)} colour(s) on screen are neither end of "
            f"the ramp -- {' '.join(sorted(between))}"
        )
    else:
        k.ok("c_edge: the two ends and no step between them")


def check_theme(k: Checks, shots: dict[str, str], dir: Path) -> None:
    k.section("theme")

    (flat_old, flat_new), (ramp_old, ramp_new) = THEME_EDIT
    old_ends = ramp_old.split(" -> ")
    new_ends = ramp_new.split(" -> ")

    def cells(shot: str, *hexes: str) -> list[int]:
        """Cells of one capture drawn in each colour, in the order asked."""
        return [lines_with(shots[shot], sc.sgr(38, h)) for h in hexes]

    # `[supaline] size` is the flat half of the rewrite `clean_run` made.
    #
    # Both halves are needed, and only the second discriminates. Until 26.9.1
    # the user's theme was merged inside the `app:theme` actor alone, so a
    # capture taken before it proved a colour resolved at `setup` was the
    # preset's; 26.9.1 has `th.supaline` populated before `setup` runs, and
    # that capture now proves nothing. A reload still does: it is
    # `ps.sub("theme", build)` that repaints what is already on screen, and a
    # plugin without it holds the old colour.
    (before,) = cells("theme-before", flat_old)
    stale, after = cells("theme-after", flat_old, flat_new)
    if before > 0:
        k.ok(f"the themed base colour is drawn ({before} cells)")
    else:
        k.fail("the themed base colour never reached the screen")
    if after > 0 and stale == 0:
        k.ok(f"a theme reload rebuilds the columns ({after} cells recoloured)")
    else:
        k.fail(
            f"a theme reload did not rebuild the columns "
            f"(old={stale} new={after})"
        )

    # The ramp beside it is the other half, and a different piece of code
    # reloading: a flat colour is one `ui.Style` resolved from the value, a
    # ramp is `STEPS` of them built by `colour.styles` from endpoints parsed
    # out of the string. Both new ends have to be on screen and neither old one
    # left anywhere -- a ramp cached past the reload would keep its old
    # endpoints with the flat colour beside it already correct.
    old = cells("theme-after", *old_ends)
    new = cells("theme-after", *new_ends)
    if min(new) > 0 and max(old) == 0:
        k.ok("... and rebuilds a ramp, not only a flat colour")
    else:
        k.fail(f"a theme reload did not rebuild the ramp (old={old} new={new})")

    # `c 2` should have put `themes/alt.toml` where Yazi reads its theme from.
    # This is the fixture's own plumbing rather than the plugin's, and it is
    # checked here because nothing else can: the key leaves Yazi to run a
    # script through a `shell` template, so it is the one path in either
    # harness that can be broken by a quoting mistake, and what a person sees
    # when it breaks is a colour that did not change -- indistinguishable from
    # the plugin ignoring the reload.
    #
    # `themes/alt.toml` puts the ramp at `#5d0b91 -> #ffb37f`, where the reload
    # above had left `THEME_EDIT`'s new one. Both halves are asked, because they
    # fail separately: the file says the key reached the disk, and the screen
    # says the reload that followed it was not lost on the way.
    #
    # The second half is not hypothetical. Spelled as a keymap `run` of
    # [ "shell ... --confirm", "app:theme" ] the two race and the reload wins
    # -- measured on 26.9.1, `theme.toml` ends up correct on disk with the old
    # colours still on screen, and `--block` does not change it.
    swapped, kept = cells("theme-swapped", "#5d0b91", new_ends[0])
    placed = (dir / "config" / "theme.toml").read_bytes() == (
        dir / "themes" / "alt.toml"
    ).read_bytes()
    if not placed:
        k.fail("c 2 did not put themes/alt.toml in place")
    elif swapped == 0 or kept > 0:
        k.fail(
            "c 2 swapped the file but the screen kept the old ramp "
            f"(new={swapped} old={kept})"
        )
    else:
        k.ok("a theme key swaps the file and the screen follows")


def yazi_version() -> str:
    """Which Yazi this run actually proves anything about.

    Every platform claim in AGENTS.md was established against one build, and
    Yazi is on CalVer: it changes the plugin API between releases, sometimes
    without saying so. A mismatch against what the plugin annotates is the
    signal to go back and re-verify the constraints, not a reason to stop --
    running against a newer Yazi is how you would find out.
    """
    said = run(["yazi", "--version"], timeout=30).stdout
    found = re.search(r"^\s*Version:\s*(.+)$", said, re.MULTILINE)
    version = found.group(1).strip() if found else said.replace("\n", " ")

    pinned = re.match(r"--- @since (.+)", (ROOT / "main.lua").read_text())
    if pinned and not version.startswith(pinned.group(1).strip()):
        print(
            f"e2e: note: Yazi is {version}, the plugin annotates "
            f"{pinned.group(1).strip()}"
        )
    return version


def main(argv: list[str]) -> int:
    require_python()
    need("tmux", "yazi")

    r = Run(keep=argv[:1] == ["--keep"])
    version = yazi_version()
    began = time.monotonic()
    try:
        r.setup()
        (r.dir / "yazi-version.txt").write_text(f"{version}\n")
        clean_run(r)
        broken_run(r)

        k = Checks()
        init = (r.dir / "config" / "init.lua").read_text()
        check_log(k, r.dir / "state" / "yazi" / "yazi.log")
        check_reports(
            k, r.dir / "state-broken" / "yazi" / "yazi.log", r.shots["broken"]
        )
        check_rows_present(k, r.shots)
        check_columns(k, r.shots)
        check_panes(k, r.shots)
        check_ramp(k, r.shots, init)
        check_theme(k, r.shots, r.dir)

        print()
        for row in sc.rows(r.shots["m7"], 2, 7):
            print(row)
        print()

        took = time.monotonic() - began
        if k.failed:
            print(
                f"e2e: {len(k.failed)} check(s) failed on Yazi {version} "
                f"in {took:.0f}s",
                file=sys.stderr,
            )
            return 1
        print(f"e2e: ok on Yazi {version} in {took:.0f}s")
        return 0
    finally:
        # Leave nothing behind when a check fails, or when the run is
        # interrupted part-way -- the scratch directory carries the PID, so one
        # left lying around is one nothing will ever reuse.
        r.teardown()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
