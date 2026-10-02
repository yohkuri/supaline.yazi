#!/usr/bin/env python3
"""Render supaline in a real Yazi and check what comes back.

The unit tests stub the Yazi globals, so they can say nothing about rendering.
This can, and it is the only thing that can.

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
from collections.abc import Callable
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import screen as sc
import setup as fixture
from harness import (
    ROOT,
    Checks,
    Session,
    catch_term,
    need,
    run,
    yazi_data,
    yazi_env,
    yazi_log,
)

#: The window every capture is taken in. Wide enough that the three panes all
#: have room, and 40 rows so about 37 of `colour/ramp`'s 64 steps reach a
#: capture.
WIDTH, HEIGHT = 170, 40

#: The floor under every ramp check, well under the 37 steps a capture holds:
#: what would drop it is a ramp that stopped drawing, and no terminal this runs
#: in shows fewer.
RAMP_FLOOR = 24

#: The floor under `c_scale`, whose folder holds 21 files that all fit a
#: 40-row window: what would drop it is a column that stopped drawing.
SCALE_FLOOR = 16

#: What counts as an error in a Yazi log, on either side of the run.
TROUBLE = re.compile(r"ERROR|WARN|attempt to|error converting", re.IGNORECASE)


class Run:
    """The scratch directory, the session, and the captures taken from it."""

    def __init__(self, keep: bool) -> None:
        # Both names carry the PID, so a run owns everything it touches: a
        # concurrent run leaves the marker `setup.py` guards removal with, so a
        # fixed directory would pass the guard and lose its fixture.
        pid = os.getpid()
        self.dir = Path(tempfile.gettempdir()) / f"supaline-e2e.{pid}"
        self.session = Session(f"supaline-e2e-{pid}")
        self.keep = keep
        self.shots: dict[str, str] = {}
        # Every key this presses is one `cases.toml` binds, found by what it
        # does rather than by how it is spelled.
        self.listing = fixture.read_cases()

    # --- the fixture -------------------------------------------------------

    def setup(self) -> None:
        """Imported and called rather than run, so its own refusal is the one
        printed rather than `run`'s emptier one over the top of it."""
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
        """Start Yazi on `data/`, with a state directory of its own."""
        self.session.start(
            ["yazi", str(yazi_data(self.dir))],
            env=yazi_env(self.dir, state),
            width=WIDTH,
            height=HEIGHT,
        )
        # A name out of the fixture rather than a fixed wait: it says Yazi got
        # as far as listing the folder, where a sleep says only that time
        # passed.
        landmark = self.listing.folders["data"].landmark
        self.session.wait_for(
            lambda s: landmark in s,
            "the fixture listed",
            timeout=30,
        )

    def store(self, label: str, plain: str, colour: str = "") -> None:
        """Hold a capture under `label`, in memory and on disk.

        On disk because `--keep` is for reading them afterwards, and a check
        that failed is answered by the capture it failed on. Apart from `shot`
        for the one capture that is not a single tmux call: the broken run's
        union of screens.
        """
        self.shots[label] = plain
        (self.dir / f"screen-{label}.txt").write_text(plain)
        if colour:
            self.shots[f"colour-{label}"] = colour
            (self.dir / f"color-{label}.txt").write_text(colour)

    def shot(self, label: str) -> None:
        """Keep both captures of the screen as it stands."""
        self.store(
            label,
            self.session.capture(),
            self.session.capture(colour=True),
        )

    def here(self, path: str) -> Callable[[str], bool]:
        """Whether a screen's current pane is the folder `path`.

        Read off the folder's landmark in `cases.toml`, a name only that
        folder holds, in the **current pane**: the panes either side draw the
        neighbouring folders, so a name they hold is on screen before the `cd`
        that makes it current. Measured on 26.9.1, `inner-a.txt` is in the
        preview pane throughout `data/`.
        """
        expect = self.listing.folders[path].landmark
        return lambda s: any(expect in f for f in sc.current_fields(s))

    def goto(self, path: str) -> None:
        """Go to a folder `cases.toml` lists, by its key."""
        self.session.press(
            *self.listing.folders[path].key.split(" "),
            until=self.here(path),
            what=f"{path}/ in the current pane",
        )

    def show(self, case: fixture.Case) -> None:
        """Press a case's key, and wait for the state it names.

        Its folder's landmark first, which a case pressed in the folder it is
        already in has on screen at once. What follows is the whole settle
        rather than the short one after a `goto`, because the same press
        switched the linemode and forced a peek, and either can repaint after
        the listing lands.
        """
        self.session.keys(*case.key.split(" "))
        self.session.wait_for(
            self.here(case.folder),
            f"{case.folder}/ in the current pane after {case.key}",
        )
        self.session.settle()

    def theme(self, name: str) -> None:
        """Put a theme `cases.toml` lists in place, by its key."""
        self.session.press(*self.listing.themes[name].key.split(" "))


def clean_run(r: Run) -> None:
    """The run that is meant to log nothing, and every capture read below."""
    r.open_yazi("state")

    # Every case a person can press, so a broken one cannot hide, each put in
    # place by its own key and kept under its own name. The key is what forces
    # the preview to peek under the new linemode, and the settle after it
    # covers that landing. What this does *not* do is judge them: `MANUAL.md`
    # says which questions a reader is the only instrument for.
    for case in r.listing.clean:
        r.show(case)
        r.shot(case.id)

    # Late, because it rewrites the theme every capture above was taken under,
    # and on `default` so a `size` and an `mtime` column are both there to
    # recolour.
    r.show(r.listing.cases["default"])
    r.shot("theme-before")
    theme = r.dir / "config" / "theme.toml"
    body = theme.read_text()
    for old, new in zip(fixture.theme_values(r.dir, "default"), THEME_NEW):
        body = body.replace(old, new)
    theme.write_text(body)
    r.session.press("T")
    r.shot("theme-after")

    # Last, because it replaces `theme.toml` wholesale. A theme key runs a
    # script through a `shell` template, the one part of either harness that
    # leaves Yazi to do its work, so the file is compared as well as the screen.
    r.theme("alt")
    r.shot("theme-swapped")

    # Explicit rather than left to the teardown: the checks read what Yazi
    # wrote, so it has to be gone before they run.
    r.session.quit("q")


def broken_run(r: Run, init: str) -> None:
    """A second Yazi, with a log of its own, for the columns that are wrong.

    The separate log is the design: the clean run's log is held to no error at
    all, unfiltered, and the errors this run makes land in a different file
    read for the opposite claim, so neither check learns an exception. And
    `broken/` arms a `refresh` that throws at every `cd` after it, which no
    capture of the clean run should be taken past.
    """
    r.open_yazi("state-broken")

    # In the case list's order, which ends on `b_tick`: it draws the counting
    # pair and breaks nothing by itself, and `broken/` is what throws its
    # `refresh`. Last, because every `cd` after it throws again.
    for case in r.listing.broken:
        r.show(case)
    r.goto("broken")

    # A union of many captures rather than one: measured on 26.9.1, Yazi draws
    # three notifications at a time and queues the rest, each for the twenty
    # seconds `tell` asks for. The claim is that each report reached the
    # screen, not that they were ever there together. A quarter-second between
    # captures, because that interval is also the lag on the answer.
    wanted = [f"`{column}`" for column in fixture.broken_columns(init)]
    began = time.monotonic()
    union = r.session.gather(
        wanted, "every report on the screen", every=0.25, timeout=60
    )
    waited = time.monotonic() - began
    if all(report in union for report in wanted):
        print(f"e2e: the reports drained to the screen in {waited:.0f}s")
    r.store("broken", union)

    # What follows would make a report come back if the gates holding it down
    # let go: two more `cd`s, since a throwing `refresh` throws at every folder,
    # and two `app:theme`s, since a rebuild must not re-arm the gate. The
    # per-column count below answers all of it by still being 1.
    r.goto("data")
    r.goto("data/nested")
    r.session.press("T")
    r.session.press("T")

    r.session.quit("q")


#: What `T` is pressed against: the flat colour and the ramp the rewrite puts
#: in place of the theme's own, read by the rewrite and by the check. Both
#: shapes a `[supaline]` value can take, because different code rebuilds them:
#: a flat colour is one `ui.Style` and a ramp is `STEPS` of them.
THEME_NEW = ("#00ccff", "#1a5e00 -> #9bff66")


def lines_with(text: str, needle: str) -> int:
    """Lines of `text` carrying `needle`.

    A colour appears once per cell that drew in it and a row may hold several,
    so rows rather than occurrences are what every claim below counts.
    """
    return sum(1 for line in text.splitlines() if needle in line)


def troubles(body: str) -> list[str]:
    """The lines of a log that report an error."""
    return [line for line in body.splitlines() if TROUBLE.search(line)]


def check_log(k: Checks, path: Path) -> None:
    k.section("log")
    bad = troubles(path.read_text() if path.is_file() else "")
    for line in bad[:10]:
        print(line, file=sys.stderr)
    k.verdict("clean", bad and "Yazi logged an error")


def check_reports(k: Checks, path: Path, shown: str, init: str) -> None:
    """The broken run logged exactly what it was told to, and showed it.

    Two logs, two absolute claims, no line filtered out of either.
    """
    k.section("the reports")
    wanted = fixture.broken_columns(init)
    # The two guards the counts inherit, since either empty would let every
    # count pass over nothing. There is no log at all unless `YAZI_LOG` was set
    # before Yazi started, so a missing file is reachable.
    if not wanted or not path.is_file():
        k.fail(
            "no broken column in test/fixture/init.lua"
            if not wanted
            else f"the broken run wrote no log at {path}"
        )
        return

    body = path.read_text()
    errors = troubles(body)
    # A total beside the per-column counts closes the pair: each name exactly
    # once and this many lines in all leaves no room for a line naming
    # something else. What is printed is a line naming no column of ours.
    if len(errors) != len(wanted):
        for line in [e for e in errors if "torn_" not in e][:5]:
            print(line[:120], file=sys.stderr)
    k.verdict(
        f"{len(errors)} error lines, one per broken column",
        len(errors) != len(wanted)
        and f"the broken run logged {len(errors)} error line(s), expected "
        f"{len(wanted)} -- one per broken column",
    )

    for column in wanted:
        # Exactly one is three claims: the column reported, `told` held it
        # down across two more `cd`s, and two `app:theme` rebuilds did not
        # re-arm it. `ya.notify` draws a box tmux captures, so the screen's
        # half is read here and nowhere else.
        logged = lines_with(body, f"`{column}`")
        k.verdict(
            f"{column} reported once, to the log and to the screen",
            logged != 1
            and f"{column}: {logged} line(s) in the broken run's log, "
            "expected exactly 1",
            f"`{column}`" not in shown
            and f"{column}: reported to the log and not to the screen",
        )


def check_rows_present(
    k: Checks, shots: dict[str, str], listing: fixture.Cases
) -> None:
    """Yazi is alive and every case's linemode name resolved.

    An unregistered one is drawn as literal text and a linemode that threw
    takes the rows with it. This does *not* prove any of them drew a column,
    because the file names satisfy it on their own; the sections after it are
    for the columns.
    """
    k.section("every case left the rows on screen")
    labels = [c.id for c in listing.clean]
    # Row 3 clears the header and is inside the shortest listing, the two
    # files of `nested/`. A whole line is read, so the panes beside it count.
    blank = [
        n
        for n in labels
        if not any(
            re.search(r"[A-Za-z0-9]", row) for row in sc.rows(shots[n], 3, 8)
        )
    ]
    k.verdict(
        f"the {len(labels)} cases all have rows",
        blank and f"{', '.join(blank)}: the rows came back blank",
    )


def check_columns(k: Checks, shots: dict[str, str]) -> None:
    k.section("columns")
    k.holds(shots["plain"], "87.9M", "plain: size")
    k.holds(shots["default"], "87.9M 05/06  2024", "default: size + mtime")
    k.holds(shots["everything"], "drwxr-xr-x", "everything: permissions")

    check_owner(k, shots["everything"])
    check_overflow(k, shots["overflow"])

    # widths: `size` stated at 10 beside `size` measured. In `data/` the widest
    # size is "1023.4K", so the measured column is 7; in `nested/` it is
    # "300K", so it narrows to 4.
    k.holds(
        shots["widths"],
        "1024B   1024B",
        "widths: a stated width and a measured one differ",
    )
    k.holds(
        shots["widths_nested"],
        "      300K 300K",
        "widths_nested: the measured width follows the folder",
    )
    # Yazi absorbs what the linemode does not use into the file name's padding,
    # so the one row that pins the *stated* column is the one whose name Yazi
    # had to truncate: there the gap after it is one space of separator, then
    # 10 less the two cells of "1B".
    k.holds(
        shots["widths"],
        "….txt         1B",
        "widths: a stated width does not shrink to fit",
    )

    # seps: `ext` (5, left), then `size` with `separator = false`, then `mtime`
    # behind the divider, in the colour it was given and just before its glyph.
    k.holds(
        shots["seps"],
        "bin    1024B" + sc.BAR,
        "seps: separator = false and a separator of a column's own",
    )
    k.holds(
        shots["colour-seps"],
        sc.sgr(38, "#a6e3a1") + sc.BAR,
        "seps: that separator is drawn in its own colour",
    )

    # custom: a registered column, one clipped to 8 without an ellipsis, and a bare
    # function in the spec.
    k.holds(
        shots["custom"], "bin   exactly- file", "custom: user-written columns"
    )
    k.holds(
        shots["custom"],
        "never-op ",
        "custom: a clipped cell carries no ellipsis",
    )


def check_owner(k: Checks, capture: str) -> None:
    """`owner`, `user` and `group` against this machine's own names.

    What their cells should say depends on how long `user:group` is here, so
    the cells come off the screen through `screen.owner_cells` and are held
    against `pwd` and `grp`, the half only a real machine can answer.
    """
    who = (
        f"{pwd.getpwuid(os.geteuid()).pw_name}:"
        f"{grp.getgrgid(os.getegid()).gr_name}"
    )
    rows = sc.owner_cells(capture)
    if not rows:
        k.fail(
            "everything: no permissions field on screen, and no cells behind one"
        )
        return

    def agreed(what: str, cells: set[str]) -> str:
        """The one cell every `everything` row agrees on, or empty with a fault said.

        Every row lists a file this run created, so all of them carry the same
        two names; two answers is a column reading per row what it should read
        per machine.
        """
        if len(cells) > 1:
            k.fail(
                f"everything: the rows disagree on the {what}: {' '.join(sorted(cells))}"
            )
            return ""
        return next(iter(cells))

    seen = agreed("owner cell", {r.owner for r in rows})
    if seen == who:
        k.ok(
            f"everything: the owner column holds `{who}` whole, with no ellipsis"
        )
    elif seen:
        dots = seen.count("…")
        k.verdict(
            f"everything: the owner column cuts `{who}` with one ellipsis",
            dots != 1
            and f"everything: the owner cell carries {dots} ellipses, wanted one -- `{seen}`",
            not sc.is_cut_of(who, seen)
            and f"everything: the owner cell `{seen}` is not a cut of `{who}`",
        )

    # `user` and `group` draw the same two names in eight cells each, so each
    # is cut on its own length and held against its own half.
    want_user, want_group = who.split(":", 1)
    got_user = agreed("user cell", {r.user for r in rows})
    got_group = agreed("group cell", {r.group for r in rows})
    if got_user and got_group:
        k.verdict(
            f"everything: the user and group columns hold the halves of `{who}`",
            not sc.is_cut_of(want_user, got_user)
            and f"everything: `{got_user}` is not a cut of `{want_user}`",
            not sc.is_cut_of(want_group, got_group)
            and f"everything: `{got_group}` is not a cut of `{want_group}`",
        )


def check_overflow(k: Checks, capture: str) -> None:
    """`overflow` puts one over-long name through ellipsis, clip and grow.

    The same row must carry all four renderings of it -- Yazi truncates long
    names in the parent pane by itself, and that ellipsis would satisfy a
    looser check -- and the cells are matched as one string, padding and all,
    so a cell that came back one short moves every space after it.
    """

    def row(label: str, name: str, cells: str) -> None:
        found = next(
            (line for line in capture.splitlines() if name in line), None
        )
        k.verdict(
            f"overflow: {label}",
            found is None
            and f"overflow: {label} -- no row on screen carries `{name}`",
            cells not in (found or "") and f"overflow: {label}",
        )

    # `exactly-1k.bin` is 14 characters against a column of 12. The two clips
    # have to agree: `Line:truncate` drops the character that lands exactly on
    # the width, so a renderable takes a path of its own through `cell`.
    row(
        "ellipsis, clip, a clipped renderable and grow, on one row",
        "exactly-1k",
        "exactly-1k.… exactly-1k.b exactly-1k.b exactly-1k.bin",
    )
    # The same four against wide characters, where a cut can land between a
    # character's two cells; both of Yazi's truncations count characters, the
    # trap `stub_spec.lua` pins in the arithmetic. 13 characters, 22 cells:
    # five and an ellipsis are 11, so the ellipsis cell pads to 12, and that
    # pad is what a cut landing mid character would take away.
    row(
        "a wide name is cut between characters, and the cell still fills",
        "日本語",
        "日本語のフ…  日本語のファ 日本語のファ 日本語のファイル名.txt",
    )
    # And where the wide character is four bytes rather than three, so a cut
    # that measured bytes cannot be right about both.
    row(
        "a four-byte character is cut and measured like any other",
        "絵文字",
        "絵文字🎨の…  絵文字🎨のな 絵文字🎨のな 絵文字🎨のなまえ.txt",
    )


def check_panes(k: Checks, shots: dict[str, str]) -> None:
    """`pane_cur` asks for the current pane alone, so its edges are the baseline.

    Whole panes are compared rather than a column grepped for, which keeps this
    independent of which columns the fixture happens to use.
    """
    k.section("panes")
    bare_parent = sc.parent_of(shots["pane_cur"])
    bare_preview = sc.preview_of(shots["pane_cur"])

    def all_marked(
        label: str, pane: list[str], rows: int | None = None
    ) -> None:
        """Every drawn row of `pane` carries the marker -- counted against
        `rows` where the pane being read is not the one that says how many."""
        drew = sc.marked(pane)
        want = sc.drawn(pane) if rows is None else rows
        k.same(drew, want, f"{label} ({drew} of {want})")

    # A pane drawing nothing where it was asked to would pass everything else
    # in this section, so each asked-for pane is held to every row. The parent
    # pane is where a linemode child being called for parent rows would show,
    # and the preview's row count comes off `pane_cur`'s bare preview -- the same
    # folder under a mode that draws nothing into it.
    for id in ("pane_cur", "pane_par", "pane_prev"):
        all_marked(
            f"{id}: every current-pane row carries the marker",
            sc.current_of(shots[id]),
        )
    all_marked(
        "pane_par: every parent-pane row carries the marker",
        sc.parent_of(shots["pane_par"]),
    )
    all_marked(
        "pane_prev: every preview-pane row carries the marker",
        sc.preview_of(shots["pane_prev"]),
        sc.drawn(bare_preview),
    )

    k.same(
        sc.parent_of(shots["pane_prev"]),
        bare_parent,
        "pane_prev: parent pane left alone",
    )
    k.same(
        sc.preview_of(shots["pane_par"]),
        bare_preview,
        "pane_par: preview pane left alone",
    )
    k.same(
        sc.marked(bare_parent) + sc.marked(bare_preview),
        0,
        "pane_cur: both edges left alone",
    )

    # `pane_each` names the same two panes as `pane_par` and gives each a list
    # of its own, so it agrees with `pane_par` about the parent pane and disagrees about the middle
    # one. `differs` alone would pass on a pane drawing nothing, so the cells it
    # was given are asked for too: `ext` then `size`, five cells left-aligned,
    # a separator, seven right-aligned.
    k.same(
        sc.parent_of(shots["pane_each"]),
        sc.parent_of(shots["pane_par"]),
        "pane_each: the parent pane draws what pane_par drew",
    )
    k.differs(
        sc.current_of(shots["pane_each"]),
        sc.current_of(shots["pane_par"]),
        "pane_each: the current pane draws columns of its own",
    )
    k.that(
        any(
            "bin     1024B" in row for row in sc.current_of(shots["pane_each"])
        ),
        "pane_each: ... and they are the ext and size it was given",
    )
    k.same(
        sc.preview_of(shots["pane_each"]),
        bare_preview,
        "pane_each: the pane nobody named is bare",
    )


def check_ramp(k: Checks, shots: dict[str, str], init: str, dir: Path) -> None:
    k.section("the ramp")

    # The ends are read off `m 1` in `data/`, where the ramp is the themed one:
    # the fixture's mtimes run from 2020 to today, so the oldest row draws the
    # low end and a file just created the high one. A column that drew the ramp
    # as a flat colour can only put one of them on screen. `colour/ramp` cannot
    # do it: its high end is below the window.
    low, high = fixture.theme_ends(dir, "default")
    k.holds(
        shots["colour-default"],
        sc.sgr(38, low),
        "a themed ramp draws its low end",
    )
    k.holds(shots["colour-default"], sc.sgr(38, high), "... and its high end")

    def rows_hold(label: str, ramp: list[sc.RampRow], monotone: bool) -> None:
        """Enough rows, and no fault in the sequence."""
        faults = sc.ramp_faults(ramp, monotone)
        k.verdict(
            f"{label} ({len(ramp)} consecutive steps)",
            len(ramp) < RAMP_FLOOR
            and f"{label}: only {len(ramp)} row(s) carried a ramp colour, "
            f"wanted {RAMP_FLOOR}",
            faults and f"{label}: {';'.join(faults[:3])}",
        )

    # One file per step, so consecutive rows are consecutive steps and this is
    # the only place the quantisation itself is read. A band is asked to climb
    # monotonically as well -- every step is one colour at another exposure,
    # measured to move all three channels together -- and a ramp that turns in
    # hue only half the question.
    rows_hold(
        "every step climbs, and none repeats the one above",
        sc.ramp_rows(shots["colour-c_ramp"]),
        True,
    )
    rows_hold(
        "a band climbs too, on endpoints nobody wrote",
        sc.ramp_rows(shots["colour-c_band"]),
        True,
    )
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


def check_bands(k: Checks, capture: str, init: str) -> None:
    """`c_bg` draws the same ramp over a ground, and over nothing.

    Of a grounded column: the `bg` is on every row; it covers the cells the
    stated width pads with, which is what padding before the style is applied
    is for; and no second column picked the ground up, which the ungrounded
    column beside it makes answerable. Both the colour and the width come out
    of the fixture by name, so recolouring or widening a column there does not
    read as a plugin fault here.
    """
    asked: list[str] = []

    def band(label: str, name: str) -> None:
        # Recorded before anything can fail, so the sweep below reads what was
        # asked for rather than what passed.
        asked.append(name)
        want = fixture.band_width(init, name)
        ground = fixture.binding(init, name)
        if not want or len(ground) != 1:
            k.fail(
                f"{label}: the fixture's init.lua has no flat `local {name}` "
                "under a `bg` with a stated width, so there is no band to "
                "measure"
            )
            return
        got = sc.bands(capture, sc.escaped(48, ground[0]), want)
        k.verdict(
            f"{label} ({got.drawn} rows, {want} cells)",
            got.drawn < RAMP_FLOOR
            and f"{label}: only {got.drawn} row(s) carried a background, "
            f"wanted {RAMP_FLOOR}",
            got.narrow
            and f"{label}: {got.narrow} band(s) were not {want} cells wide -- "
            "the padding is where to look",
            got.drawn != got.lines
            and f"{label}: {got.drawn} band(s) across {got.lines} row(s), so a "
            "row carries more than one",
        )

    band("a background survives the ramp, padding included", "GROUND")
    band("a background covers a pad beside a nested Line", "LINE_GROUND")

    # And a sweep, because a list goes stale in one direction: a grounded
    # column added to `c_bg` would be drawn, read by nobody, and green.
    grounds = fixture.c_bg_grounds(init)
    if grounds is None:
        k.fail(
            "c_bg: the fixture's init.lua has no `c_bg` block this sweep can "
            "find, so a ground added there would be read by nobody"
        )
        return
    for name in grounds:
        if len(fixture.binding(init, name)) == 1 and name not in asked:
            k.fail(
                f"c_bg: `{name}` is a ground nothing reads -- write "
                f'`band("<what it claims>", "{name}")` beside the two above'
            )


def check_bold(k: Checks, shots: dict[str, str]) -> None:
    """`c_bold` draws the same ratio twice on one ramp, the left one bold."""
    agreed, disagreed = sc.bold_pairs(shots["colour-c_bold"])
    k.verdict(
        f"c_bold: bold on one column, the ramp's colour on both ({agreed} rows)",
        agreed < RAMP_FLOOR
        and f"c_bold: only {agreed} row(s) had a bold cell beside an unbold "
        f"one of the same colour, wanted {RAMP_FLOOR}",
        disagreed
        and f"c_bold: {disagreed} row(s) disagreed -- a colour that moved, or "
        "a bold on the wrong side",
    )

    # Each reads an escape rather than a parsed cell, and each is pinned in CI
    # beside itself in `screen.py`, whose docstrings say what their two halves
    # tell apart.
    k.that(
        sc.bold_over_paint(shots["colour-c_bold"]) > 0,
        "c_bold: the bold reaches the characters permissions paints, colours kept",
    )
    k.that(
        sc.bold_over_ramp(shots["colour-c_theme"]) > 0,
        "c_theme: a spec's bold over the theme's ramp",
    )


def cool_ends(k: Checks, init: str, who: str) -> tuple[str, str]:
    """The ramp `c_scale` and `c_edge` are both measured against, or empties."""
    ends = fixture.binding(init, "COOL")
    if len(ends) != 2:
        k.fail(
            f"{who}: the fixture's init.lua binds no `local COOL` to a "
            "two-ended ramp, so there is nothing to measure against"
        )
        return "", ""
    return ends[0], ends[1]


def check_scale(k: Checks, capture: str, init: str) -> None:
    """`c_scale` draws one folder's sizes twice, log then linear.

    One `size` column written twice, differing in `scale` alone, so anything
    that differs on screen is the scale. Whether the left column reads as a
    gradient *to a reader* is `MANUAL.md`'s question.
    """
    low, _ = cool_ends(k, init, "c_scale")
    if not low:
        return
    rows = sc.scale_rows(capture)
    # The premise under both claims: a row whose halves read differently is a
    # fixture that moved, and two scales over two numbers compare nothing.
    drifted = [r for r in rows if r.log_text != r.linear_text]
    if not k.verdict(
        f"c_scale: the two scales draw one number ({len(rows)} rows)",
        len(rows) < SCALE_FLOOR
        and f"c_scale: only {len(rows)} row(s) carried a pair either side of "
        f"the seam, wanted {SCALE_FLOOR}",
        drifted
        and f"c_scale: {len(drifted)} row(s) draw a different number either "
        f"side of the seam -- `{drifted[0].log_text}` against "
        f"`{drifted[0].linear_text}`",
    ):
        return

    # The sizes double down the folder, so log spaces them evenly and takes a
    # new step on every row.
    steps = len({r.log_colour for r in rows})
    k.same(
        steps,
        len(rows),
        f"c_scale: log takes a step per row ({steps} of {len(rows)})",
    )

    # And linear leaves most of them on the low end: with sizes at 2^0 to 2^20
    # and the ramp in 38 steps, a linear ratio rounds to step 0 under 2^14,
    # which is 14 of the 21 files.
    floor = sum(1 for r in rows if r.linear_colour == sc.rgb(low))
    k.verdict(
        f"c_scale: linear holds {floor} of {len(rows)} at the low end, "
        "where log holds one",
        floor * 2 <= len(rows)
        and f"c_scale: linear holds only {floor} of {len(rows)} rows at the "
        "low end -- it should hold most of them there",
    )


def check_edge(k: Checks, capture: str, init: str) -> None:
    """`c_edge` draws a folder in which every value is the same.

    `hi == lo`, so `ratio` answers 1 rather than dividing by nothing, and every
    row with a value draws the ramp's **high** end. A directory has no size, so
    its cell draws the low end instead. No step in between may be drawn: a
    gradient over this folder is a ratio that divided by a range of zero.
    """
    low, high = cool_ends(k, init, "c_edge")
    if not low:
        return
    rows = sc.edge_rows(capture)
    files = [r for r in rows if sc.is_size(r.size)]
    dirs = [r for r in rows if not sc.is_size(r.size)]
    if not files or not dirs:
        # Either kind alone leaves half the claim passing over nothing.
        k.fail(
            f"c_edge: {len(files)} row(s) with a size and {len(dirs)} "
            "without, wanted some of each; this check is reading nothing"
        )
        return

    bad = [
        r for r in files if {r.size_colour, r.ratio_colour} != {sc.rgb(high)}
    ]
    k.verdict(
        f"c_edge: every row with a value is at the high end ({len(files)})",
        bad
        and f"c_edge: {len(bad)} of {len(files)} row(s) with a value did not "
        f"draw the ramp's high end -- `{bad[0].size}` at {bad[0].size_colour}",
    )
    astray = [r for r in dirs if r.size_colour != sc.rgb(low)]
    k.verdict(
        f"c_edge: a directory draws the low end ({len(dirs)} rows)",
        astray
        and f"c_edge: {len(astray)} of {len(dirs)} directory row(s) did not "
        f"draw the low end -- `{astray[0].size}` at {astray[0].size_colour}",
    )
    # Over all three cells of every row, so a column that started interpolating
    # is caught even where the two ends are still right.
    seen = {
        c for r in rows for c in (r.size_colour, r.ratio_colour, r.date_colour)
    }
    between = seen - {sc.rgb(low), sc.rgb(high)}
    k.verdict(
        "c_edge: the two ends and no step between them",
        between
        and f"c_edge: {len(between)} colour(s) on screen are neither end of "
        f"the ramp -- {' '.join(sorted(between))}",
    )


def check_theme(k: Checks, shots: dict[str, str], dir: Path) -> None:
    k.section("theme")

    flat_old = fixture.theme_values(dir, "default")[0]
    old_ends = fixture.theme_ends(dir, "default")
    flat_new, ramp_new = THEME_NEW
    new_ends = ramp_new.split(" -> ")

    def rows(shot: str, *hexes: str) -> list[int]:
        """Rows of one capture drawing each colour, in the order asked."""
        return [lines_with(shots[shot], sc.sgr(38, h)) for h in hexes]

    # `[supaline] size` is the flat half of the rewrite. Only the reload
    # discriminates: 26.9.1 has `th.supaline` populated before `setup` runs, so
    # the first capture proves only that the colour is drawn, and it is
    # `ps.sub("theme", ...)` that repaints what is already on screen.
    (before,) = rows("colour-theme-before", flat_old)
    stale, after = rows("colour-theme-after", flat_old, flat_new)
    k.that(before > 0, f"the themed base colour is drawn ({before} rows)")
    k.that(
        after > 0 and stale == 0,
        f"a theme reload rebuilds the columns (old={stale} new={after})",
    )

    # The ramp is the other half and different code: both new ends on screen
    # and neither old one anywhere, since a ramp cached past the reload keeps
    # its old endpoints beside a flat colour already correct.
    old = rows("colour-theme-after", *old_ends)
    new = rows("colour-theme-after", *new_ends)
    k.that(
        min(new) > 0 and max(old) == 0,
        f"... and rebuilds a ramp, not only a flat colour (old={old} new={new})",
    )

    # The `alt` key puts `themes/alt.toml` in place through a `shell` template,
    # and a colour that did not change looks the same whether the copy never
    # ran or the plugin ignored the reload -- so the file and the screen are
    # asked apart. With the copy and an `app:theme` emitted side by side, the
    # two race and the reload wins, measured on 26.9.1.
    alt_low = fixture.theme_ends(dir, "alt")[0]
    swapped, kept = rows("colour-theme-swapped", alt_low, new_ends[0])
    placed = (dir / "config" / "theme.toml").read_bytes() == (
        dir / "themes" / "alt.toml"
    ).read_bytes()
    k.verdict(
        "a theme key swaps the file and the screen follows",
        not placed and "the alt key did not put themes/alt.toml in place",
        (swapped == 0 or kept > 0)
        and "the alt key swapped the file but the screen kept the old ramp "
        f"(new={swapped} old={kept})",
    )


def yazi_version() -> str:
    """Which Yazi this run actually proves anything about.

    Yazi is on CalVer and changes the plugin API between releases, so a
    version other than the one the plugin annotates is the signal to
    re-verify the constraints, not a reason to stop.
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
    need("tmux", "yazi")
    # Before there is anything to clean up, so the `finally` below runs on a
    # SIGTERM as well.
    catch_term()

    r = Run(keep=argv[:1] == ["--keep"])
    version = yazi_version()
    began = time.monotonic()
    try:
        r.setup()
        # The fixture as Yazi is about to read it, `@DIR@` filled in, rather
        # than the source under `test/fixture/`.
        init = (r.dir / "config" / "init.lua").read_text()
        clean_run(r)
        broken_run(r, init)

        k = Checks()
        check_log(k, yazi_log(r.dir, "state"))
        check_reports(
            k, yazi_log(r.dir, "state-broken"), r.shots["broken"], init
        )
        check_rows_present(k, r.shots, r.listing)
        check_columns(k, r.shots)
        check_panes(k, r.shots)
        check_ramp(k, r.shots, init, r.dir)
        check_theme(k, r.shots, r.dir)

        print()
        for row in sc.rows(r.shots["pane_par"], 2, 7):
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
        # Nothing left behind on a failure or an interruption: the scratch
        # directory carries the PID, so one left lying around is never reused.
        r.teardown()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
