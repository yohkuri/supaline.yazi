"""Reading a tmux capture: panes, colours, ramps, bands.

Everything here is a pure function over the text `tmux capture-pane` wrote.
Nothing in this file starts a process, reads a file or touches the clock, which
is the whole of why it is a file: `test_screen.py` beside it can put a capture
in and read an answer out, so the arithmetic that decides whether a ramp
climbed is checked by the unit suite rather than only by the run it is part of.

Until this file that arithmetic was three `awk` programs inside `e2e.sh`, and
nothing tested them. `test/ramp.lua` looks like their test and is not -- it
draws ramps for a person to look at under `manual.py`, and would go on doing
that with every parser here returning nothing.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# The divider Yazi draws between its three panes, U+2502. Held in a name
# because it is what every pane split here anchors on, and because a capture
# that drew one *inside* a column would take the split with it -- which is why
# `c_scale` and `c_bold` in the fixture use U+250A for their separators.
BAR = "│"

# U+250A, which `c_scale` and `c_bold` write between two cells holding one
# number. A separate name from `BAR` because the split it anchors is the
# opposite one: `BAR` finds the pane, this finds the seam inside a column.
DOTTED = "┊"

# What tmux writes an attribute or a colour out as, opened by ESC [ and closed
# by `m`.
ESC = "\x1b"
BOLD = ESC + "[1m"

#: The same opening, as a pattern matches it. Every pattern below starts
#: here, and a `[` left unescaped in one of them opens a character class
#: instead.
OPEN = re.escape(ESC) + r"\["

#: And bold as a pattern matches it, which is not `BOLD` either: read as a
#: regex, `[1m` is a character class and matches one character.
BOLD_OPEN = OPEN + "1m"


def sgr(layer: int, colour: str) -> str:
    """A truecolor SGR body as tmux writes it: `38;2;R;G;Bm`.

    Built from the colour as the fixture spells it, so the two files can be
    grepped against each other. Every colour asserted on in `e2e.py` is a hex
    string that appears verbatim in `test/fixture/`; converting one by hand is
    how an assertion goes stale, and a stale one reports a fixture edit as a
    plugin that stopped drawing.

    `layer` is 38 for a foreground and 48 for a background.
    """
    return f"{layer};2;{rgb(colour)}m"


def rgb(colour: str) -> str:
    """`#0b3d91` -> `11;61;145`, which is how a parsed cell carries it.

    The layer and the closing `m` say where a colour was used, not which one
    it is, so a check comparing a cell this module read against a colour the
    fixture spells wants the triple alone.
    """
    h = colour.lstrip("#")
    return ";".join(str(int(h[i : i + 2], 16)) for i in (0, 2, 4))


def escaped(layer: int, colour: str) -> str:
    """The same, with the ESC [ that opens it -- a literal to split a line on."""
    return ESC + "[" + sgr(layer, colour)


def rows(capture: str, first: int = 2, last: int = 8) -> list[str]:
    """Rows `first` to `last` of a capture, 1-indexed and inclusive.

    Both panes start on row 2, the first row under the header: the parent
    pane's first row is its hovered one, and a check that skipped it would be
    blind to exactly the single-row mistakes this suite exists to catch. 8 is
    inside the shortest listing any capture here holds.
    """
    return capture.splitlines()[first - 1 : last]


def parent_of(capture: str) -> list[str]:
    """Each row up to the first divider.

    Whole panes rather than a fixed column count: a row opening with a
    three-byte icon pushes a one-cell column past any window that looks wide
    enough, so anything counting characters from the left edge is measuring
    somewhere else on every other row.
    """
    return [row.split(BAR)[0] for row in rows(capture)]


def preview_of(capture: str) -> list[str]:
    """Each row past the last divider. The preview's rows are `nested/`."""
    return [row.rsplit(BAR, 1)[-1] for row in rows(capture)]


def current_of(capture: str) -> list[str]:
    """Each row between the two dividers -- the pane that matters.

    A row carrying no divider answers the empty string rather than itself,
    which is what keeps a header or a blank line out of every count below.
    """
    return [field_of(row) for row in rows(capture)]


def field_of(row: str) -> str:
    """The current pane's field of one row, empty when the row has no divider."""
    fields = row.split(BAR)
    return fields[1] if len(fields) > 1 else ""


def current_fields(capture: str) -> list[str]:
    """The current-pane field of **every** line, header and footer included.

    The ramp readers below take this rather than `current_of`: they find their
    cells by what the cell looks like -- an escape and then a ratio, an escape
    and then a date -- so a row that carries none is skipped by the pattern
    and there is nothing for a row window to buy. `colour/ramp` also fills
    more of the screen than rows 2 to 8, and cutting it there would throw away
    most of the steps the check exists to count.
    """
    return [field_of(row) for row in capture.splitlines()]


@dataclass(frozen=True)
class RampRow:
    """One row of a ramp, as two cells that should have landed on one step.

    Each row of `c_ramp` carries the same ratio twice: once as the number,
    placed by a `stats` closure written in the fixture's own `init.lua`, and
    once as the date, placed by the built-in `mtime` column's. Two `stats`
    functions, two `ctx` tables, one step -- so the two cells agreeing is a
    check rather than a restatement.
    """

    #: The `R;G;B` of the cell carrying the ratio, as tmux wrote it.
    ratio_colour: str
    #: The `R;G;B` of the cell carrying the date.
    date_colour: str
    #: The ratio itself, which has to climb down the column.
    ratio: float


def ramp_rows(capture: str) -> list[RampRow]:
    """Every row of a colour capture carrying both a ratio and a date cell.

    A row that carries one and not the other is skipped rather than half-read:
    what this list is for is comparing the two, and a row with one cell has
    nothing to compare.
    """
    ratio_re = _ratio_re(38)
    date_re = re.compile(rf"({_BODY.format(layer=38)})\d\d/\d\d")

    out = []
    for field in current_fields(capture):
        ratio = ratio_re.search(field)
        date = date_re.search(field)
        if not ratio or not date:
            continue
        out.append(
            RampRow(
                ratio_colour=_triple(ratio.group(1)),
                date_colour=_triple(date.group(1)),
                ratio=float(ratio.group(2)),
            )
        )
    return out


def background_rows(capture: str) -> list[RampRow]:
    """The same, for a ramp drawn under `bg` rather than `fg`.

    `ratio` in `c_bg` carries the ramp as its background and nothing sets a
    foreground on the cell, so there is one cell rather than two and the
    colour answers for both. The two-cells question passes by construction
    here; the other three -- a step per row, none repeated, climbing in every
    channel -- are what this is read for, and they are asked of these rows by
    the same `ramp_faults` the foreground ones go through.
    """
    ratio_re = _ratio_re(48)

    out = []
    for field in current_fields(capture):
        ratio = ratio_re.search(field)
        if not ratio:
            continue
        colour = _triple(ratio.group(1))
        out.append(
            RampRow(
                ratio_colour=colour,
                date_colour=colour,
                ratio=float(ratio.group(2)),
            )
        )
    return out


@dataclass(frozen=True)
class ScaleRow:
    """One row of `c_scale`: the same size drawn twice, log then linear."""

    #: The `R;G;B` of the cell `scale = "log"` placed.
    log_colour: str
    #: ... and of the `scale = "linear"` cell beside it.
    linear_colour: str
    #: What the log cell reads. The linear one has to read the same.
    log_text: str
    #: What the linear cell reads.
    linear_text: str


def scale_rows(capture: str) -> list[ScaleRow]:
    """Every current-pane row of `c_scale`, as the pair it draws.

    The two cells hold one number by construction -- one `size` column twice,
    differing in `scale` and nothing else -- so they are read off one row
    rather than swept for separately. Two independent sweeps would pass a
    capture whose halves had drifted onto different rows, and the whole claim
    here is about what two scales did to *one* value.

    The seam is `DOTTED` rather than `BAR`, which is what keeps this inside
    the current pane: see the note on `BAR`.
    """
    cell_re = re.compile(
        rf"{OPEN}({_BODY.format(layer=38)}) *([0-9.]+[A-Za-z]?)"
    )

    out = []
    for field in current_fields(capture):
        left, seam, right = field.partition(DOTTED)
        if not seam:
            continue
        before, after = cell_re.findall(left), cell_re.findall(right)
        if not before or not after:
            continue
        out.append(
            ScaleRow(
                log_colour=_triple(before[-1][0]),
                linear_colour=_triple(after[0][0]),
                log_text=before[-1][1],
                linear_text=after[0][1],
            )
        )
    return out


@dataclass(frozen=True)
class EdgeRow:
    """One row of `c_edge`: a size, a ratio and a date on one ramp."""

    #: The `R;G;B` of the size cell, which is the one that may have no value.
    size_colour: str
    #: ... of the ratio beside it.
    ratio_colour: str
    #: ... and of the date after that.
    date_colour: str
    #: What the size cell reads: a size, a directory's count, or `-`.
    size: str


def edge_rows(capture: str) -> list[EdgeRow]:
    """Every current-pane row of `c_edge`, as its three cells at once.

    Matched as one run rather than three searches, because the cells are
    adjacent and a row is only worth reading if all three are there: the
    claim is that one ratio reached three columns, and a row that lost one of
    them has nothing to say about it.

    Reading the run also keeps Yazi's own file icon out. It carries a
    truecolor escape of its own a few cells to the left, and a sweep for
    `38;2` alone would count it as a column this plugin coloured.
    """
    body = _BODY.format(layer=38)
    gap = rf"{OPEN}[0-9;]*m "
    row_re = re.compile(
        rf"{OPEN}({body}) *([^\x1b ]+)"
        rf"{gap}{OPEN}({body}) *[01]\.\d\d"
        rf"{gap}{OPEN}({body})\d\d/\d\d"
    )

    out = []
    for field in current_fields(capture):
        found = row_re.search(field)
        if not found:
            continue
        out.append(
            EdgeRow(
                size_colour=_triple(found.group(1)),
                ratio_colour=_triple(found.group(3)),
                date_colour=_triple(found.group(4)),
                size=found.group(2),
            )
        )
    return out


#: What tmux writes a truecolor SGR body as, with the layer left to fill in.
_BODY = "{layer};2;\\d+;\\d+;\\d+m"


def _ratio_re(layer: int) -> re.Pattern[str]:
    """A ratio cell: an escape followed by a number between 0.00 and 1.00.

    A file name cannot match it -- digit, dot, two digits -- and neither can
    the date beside it.
    """
    return re.compile(rf"({_BODY.format(layer=layer)}) *([01]\.\d\d)")


def _triple(body: str) -> str:
    """`38;2;17;34;51m` -> `17;34;51`. The layer and the `m` carry nothing."""
    return body.split(";", 2)[2][:-1]


def ramp_faults(ramp: list[RampRow], monotone: bool) -> list[str]:
    """Everything wrong with a sequence of ramp rows, one sentence each.

    `monotone` is asked of one ramp and not another, and which is which is a
    property of the ramp rather than of the plugin. `#0b3d91 -> #7fd4ff`
    climbs in all three channels at once and was measured to hold that across
    all 64 steps; `#0b3d91 -> #ffd400` turns in hue and reverses a channel on
    49 of its 63 transitions, so asking it there would go red on a gradient
    that is correct.

    What both are asked is that no step repeats the one above it. That holds
    for any ramp whose quantisation is doing anything at all -- measured, zero
    identical adjacent pairs on both of these -- and it is what fails when a
    ratio never reaches the ramp, or reaches only its ends.
    """
    faults = []
    for n, row in enumerate(ramp, start=1):
        if row.ratio_colour != row.date_colour:
            faults.append(
                f"row {n} drew its two cells in different colours "
                f"({row.ratio_colour} and {row.date_colour})"
            )
        if n == 1:
            continue
        prev = ramp[n - 2]
        if row.ratio_colour == prev.ratio_colour:
            faults.append(
                f"row {n} is the same colour as the row above it "
                f"({row.ratio_colour})"
            )
        if monotone:
            now = [int(c) for c in row.ratio_colour.split(";")]
            was = [int(c) for c in prev.ratio_colour.split(";")]
            if any(a < b for a, b in zip(now, was)):
                faults.append(
                    f"row {n} goes backwards "
                    f"({prev.ratio_colour} then {row.ratio_colour})"
                )
        if row.ratio < prev.ratio:
            faults.append(
                f"row {n} has a smaller ratio than the row above it "
                f"({prev.ratio} then {row.ratio})"
            )
    return faults


@dataclass(frozen=True)
class Bands:
    """What a background colour covered, counted over a whole capture."""

    #: How many bands were drawn, across every row.
    drawn: int
    #: How many rows carried at least one.
    lines: int
    #: How many of them were not the width the column stated.
    narrow: int


def bands(capture: str, opening: str, want: int) -> Bands:
    """Measure every run of one background colour in a capture.

    A band runs to the next escape of **any** kind: there is none inside one
    today, and one put there later reads here as a band that came back short.

    A band that is missing and a band that is short are different bugs, so the
    width is measured rather than the rows counted -- what a stated width buys
    is padding the style is applied *over*, and a band that stopped at the text
    is the padding applied in the wrong order.
    """
    drawn = lines = narrow = 0
    for line in capture.splitlines():
        pieces = line.split(opening)
        if len(pieces) > 1:
            lines += 1
        for piece in pieces[1:]:
            cell = piece.split(ESC, 1)[0]
            drawn += 1
            if len(cell) != want:
                narrow += 1
    return Bands(drawn=drawn, lines=lines, narrow=narrow)


def bold_pairs(capture: str) -> tuple[int, int]:
    """Rows where a bold ratio cell sits beside an unbold one of one colour.

    What the layers claim is that one column differs from the other in exactly
    one way, so the pair is read off one row rather than grepped for
    separately: two independent checks would pass a build that had lost the
    ramp on both sides and bolded both.

    Bold is read as the escape immediately before the colour, which is where
    tmux puts it and where a `patch` that landed in the wrong order would not.
    The ramp's own escape carries `;` in its body, so a plain numeric SGR
    cannot be confused for one.

    Answers `(agreed, disagreed)`, counted over every row that had two cells.
    """
    cell_re = re.compile(rf"{OPEN}({_BODY.format(layer=38)}) *[01]\.\d\d")

    agreed = disagreed = 0
    for field in current_fields(capture):
        cells = [
            (
                m.group(1),
                m.start() >= len(BOLD)
                and field[m.start() - len(BOLD) : m.start()] == BOLD,
            )
            for m in cell_re.finditer(field)
        ]
        if len(cells) < 2:
            continue
        (left, left_bold), (right, right_bold) = cells[0], cells[1]
        if left == right and left_bold and not right_bold:
            agreed += 1
        else:
            disagreed += 1
    return agreed, disagreed


def bold_over_paint(capture: str) -> int:
    """Current-pane rows where a bold opens two separately-coloured characters.

    `permissions` is the only column that paints its own cells, so a bold
    written for it has to reach those characters *without* replacing the
    colours they already carry: `perm_spans` patches the column's style into
    each character's own, and that style has no colour of its own to overwrite
    them with.

    Both halves are read at once, because neither discriminates alone -- the
    bold opening the run, and two characters after it each opening a colour of
    its own. A cell that had stepped aside for the attribute would draw the
    whole run under one escape, passing the first half and failing the second.
    What it does not ask is that the two colours *differ*; the claim is that
    the column painted per character, not what it painted.

    Those colours are the palette's rather than a ramp's, so the body asked
    for is a plain number -- a truecolor one carries `;` and cannot be read as
    one.
    """
    painted = re.compile(rf"{BOLD_OPEN}{OPEN}\d*m.{OPEN}\d*m.")
    return sum(1 for field in current_fields(capture) if painted.search(field))


def bold_over_ramp(capture: str) -> int:
    """Current-pane rows where a bold sits immediately before a ramp's date.

    `c_theme`'s `mtime` writes `{ bold = true }` in a spec over a ramp the
    theme wrote: the colour is the theme's and the weight the spec's, on one
    cell, which is the case the two layers exist for. Read as the bold
    immediately before a truecolor escape opening a date -- which is where
    tmux puts it, and where a patch that landed in the wrong order would not
    be.
    """
    dated = re.compile(rf"{BOLD_OPEN}{OPEN}{_BODY.format(layer=38)}\d\d/")
    return sum(1 for field in current_fields(capture) if dated.search(field))


def marked_in_preview(capture: str) -> int:
    """Preview rows ending in the trio's one column: a `d` or an `f`."""
    return sum(1 for row in preview_of(capture) if re.search(r" [df]$", row))


def marked_in_current(capture: str) -> int:
    """The same in the current pane, where the marker is not last on the row.

    The hovered row carries a powerline glyph after it and the others a space
    before the divider, so anything but a letter or a digit may follow -- which
    still refuses a row ending in a file name.
    """
    return sum(
        1
        for row in current_of(capture)
        if re.search(r" [df][^A-Za-z0-9]*$", row)
    )


def rows_in_current(capture: str) -> int:
    """Current-pane rows carrying anything at all."""
    return sum(1 for row in current_of(capture) if row.strip(" "))
