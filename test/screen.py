"""Reading a tmux capture: panes, colours, ramps, bands.

Everything here is a pure function over the text `tmux capture-pane` wrote.
Nothing in this file starts a process, reads a file or touches the clock, which
is the whole of why it is a file: `test_screen.py` beside it can put a capture
in and read an answer out, so the arithmetic that decides whether a ramp
climbed is checked by the unit suite rather than only by the run it is part of.

`test/ramp.lua` looks like their test and is not -- it draws ramps for a
person to look at under `manual.py`, and would go on doing that with every
parser here returning nothing.
"""

from __future__ import annotations

import re
from collections.abc import Iterator
from dataclasses import dataclass, replace

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
        rf"{gap}{OPEN}({body}) *{_RATIO}"
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


@dataclass(frozen=True)
class OwnerRow:
    """The four cells `permissions`, `owner`, `user` and `group` put on a row.

    Read as one row rather than four greps, because the three name columns
    say the same two names in different widths and the interesting claim is
    how each of them *cut* them -- which cannot be asked of a cell found on
    its own.
    """

    #: The permissions field, which is what the row is found by.
    permissions: str
    #: `user:group` in one twelve-cell column, cut if it did not fit.
    owner: str
    #: The same two names again, eight cells each, cut on their own lengths.
    user: str
    group: str


def owner_cells(capture: str) -> list[OwnerRow]:
    """Every current-pane row m2 drew those four columns on.

    Anchored on the permissions field, as a pattern rather than a literal:
    a different umask draws a different one, and `[-dl]` then nine of
    `rwxsStT-` is the shape rather than the value. What follows it is the
    three name cells, delimited by the columns' own padding -- none of the
    three can hold a space, so no width arithmetic is needed and none is
    done.

    The current pane alone: Yazi draws no permissions field in the parent
    pane, measured on 26.9.1.
    """
    found_re = re.compile(r"([-dl][rwxsStT-]{9}) +([^ ]+) +([^ ]+) +([^ ]+) +")
    out = []
    for row in current_of(capture):
        found = found_re.search(row)
        if not found:
            continue
        out.append(
            OwnerRow(
                permissions=found.group(1),
                owner=found.group(2),
                user=found.group(3),
                group=found.group(4),
            )
        )
    return out


def is_cut_of(name: str, cell: str) -> bool:
    """Whether `cell` is what a column left of `name` after cutting it.

    The text up to the ellipsis has to be a prefix of the name, and a cell
    that fitted carries no ellipsis to strip -- so a whole cell answers true
    as well, and so does a bare prefix that was cut without being marked.
    That last one is why the caller counts the ellipses too: this says the
    text is consistent with the name, not that the cut was declared.
    """
    return name.startswith(cell.removesuffix("…"))


def is_size(cell: str) -> bool:
    """Whether a size cell holds a size, as against a count or a `-`.

    What tells the two apart is the unit rather than where the cell sits: a
    size carries one, and a directory's cell holds the count of what is in it
    -- or the `-` it shows until the preview has read it, which is the same
    row either way. Here rather than beside the check that partitions on it,
    because it is a claim about what the screen reads and `test_screen.py` can
    put both kinds through it.
    """
    return re.fullmatch(r"[0-9.]+[A-Za-z]", cell) is not None


#: What tmux writes a truecolor SGR body as, with the layer left to fill in.
_BODY = "{layer};2;\\d+;\\d+;\\d+m"

#: And a ratio cell's number, between 0.00 and 1.00. Three readers match it
#: and each captures it differently, so it is the number alone that is held
#: here -- a file name cannot match it, and neither can the date beside it.
_RATIO = r"[01]\.\d\d"


def _ratio_re(layer: int) -> re.Pattern[str]:
    """A ratio cell: an escape followed by the number, captured separately."""
    return re.compile(rf"({_BODY.format(layer=layer)}) *({_RATIO})")


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
    cell_re = re.compile(rf"{OPEN}({_BODY.format(layer=38)}) *{_RATIO}")

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


def marked(rows: list[str], marks: tuple[str, ...] = ("d", "f")) -> int:
    """Rows of one pane ending in one of `marks` -- by default the trio's one
    column, a `d` or an `f`. Each is matched literally.

    Given a pane's rows rather than the capture, because the claim is the same
    in all three and the trio exists to ask it of each -- `pane_cur` of the
    middle pane, `pane_par` of the left, `pane_prev` of the right. One pattern
    for all three, so no pane is asked something weaker than the others -- that
    it had merely *changed*, say, which a hover that moved would satisfy.

    The marker is not always last on the row. The hovered row carries a
    powerline glyph after it and the others a space before the divider, in the
    parent pane as much as in the current one, so anything but a letter or a
    digit may follow -- which still refuses a row ending in a file name.

    Measured across all three panes of m6, m7, m8 and me on 26.9.1: this
    counts every row the stricter `[df]$` counted in the preview pane, and the
    five parent rows it read as unmarked.
    """
    either = "|".join(re.escape(mark) for mark in marks)
    tail = re.compile(rf" (?:{either})[^A-Za-z0-9]*$")
    return sum(1 for row in rows if tail.search(row))


def drawn(rows: list[str]) -> int:
    """Rows of one pane carrying anything at all.

    The denominator under `marked`: a pane where nothing was drawn has no
    marked rows either, and `0 == 0` is a claim about nothing.
    """
    return sum(1 for row in rows if row.strip(" "))


def signed(rows: list[str], sign: str) -> int:
    """Rows of one pane ending in `sign`, the child `toggle` hides.

    `marked`'s reading, because a child at 1500 lands where the marker does:
    after the linemode's columns, and before only the padding Yazi draws at
    2000 -- a space, or a powerline glyph on the hovered row. So a name that
    held the glyph would not be counted.
    """
    return marked(rows, (sign,))


# --- every cell, for the gallery ---------------------------------------------


@dataclass(frozen=True)
class Pen:
    """What a cell was drawn in, as far as tmux writes it down.

    A colour is `""` for the terminal's own, `#rrggbb`, or `p0` to `p15` for
    one of the sixteen named colours, whose value is the terminal's to choose.
    An index past those is fixed by the 256-colour cube and comes back as a hex.
    """

    fg: str = ""
    bg: str = ""
    bold: bool = False
    italic: bool = False
    underline: bool = False
    reverse: bool = False
    dim: bool = False
    blink: bool = False
    hidden: bool = False
    crossed: bool = False


_DEFAULT_PEN = Pen()


#: One cell of a capture: the character drawn, and what it was drawn in.
Cell = tuple[str, Pen]

#: The attributes each SGR parameter turns on or off. `22` is one parameter
#: for two: a terminal takes bold and dim off together.
_SWITCHES = {
    1: {"bold": True},
    2: {"dim": True},
    22: {"bold": False, "dim": False},
    3: {"italic": True},
    23: {"italic": False},
    4: {"underline": True},
    24: {"underline": False},
    5: {"blink": True},
    25: {"blink": False},
    7: {"reverse": True},
    27: {"reverse": False},
    8: {"hidden": True},
    28: {"hidden": False},
    9: {"crossed": True},
    29: {"crossed": False},
}

#: The `Pen` field each style attribute arrives in. Spelled apart from the
#: style keys in two places: `reversed` is `reverse` here, after the SGR, and
#: `blink_rapid` arrives as `blink`. Measured on 26.9.1 under tmux 3.8, both
#: blinks reach a capture as parameter 5, so a capture cannot tell them apart
#: and the most a check can ask of `blink_rapid` is that it blinks.
DRAWN_AS = {
    "bold": "bold",
    "dim": "dim",
    "italic": "italic",
    "underline": "underline",
    "blink": "blink",
    "blink_rapid": "blink",
    "reversed": "reverse",
    "hidden": "hidden",
    "crossed": "crossed",
}

#: An escape of any kind, and the parameters when it is an SGR.
_SEQUENCE = re.compile(rf"{OPEN}([0-9;:]*)m|{re.escape(ESC)}")


def _hex(r: int, g: int, b: int) -> str:
    """Three channels as a hex, which is how a `Pen` carries a colour."""
    return f"#{r:02x}{g:02x}{b:02x}"


def _indexed(n: int) -> str:
    """Colour `n` of 256: a named one, or a hex off the cube or the greys."""
    if n < 16:
        return f"p{n}"
    if n < 232:
        levels = (0, 95, 135, 175, 215, 255)
        n -= 16
        return _hex(levels[n // 36], levels[n // 6 % 6], levels[n % 6])
    return _hex(*[8 + 10 * (n - 232)] * 3)


def _drawn_after(pen: Pen, body: str) -> Pen:
    """`pen` once one SGR's parameters have been applied to it.

    Refused rather than passed over when a parameter is one this does not
    know, since a cell drawn without it is a cell the terminal never showed --
    and so is a colon, the other spelling of a colour, which tmux does not
    write today.
    """
    if ":" in body:
        raise ValueError(f"an SGR with colons, `{body}m`, is not read here")
    params = [int(p) if p else 0 for p in body.split(";")]
    changes = {}
    i = 0
    while i < len(params):
        p = params[i]
        layer = "fg" if p < 40 or 90 <= p < 100 else "bg"
        if p == 0:
            pen = _DEFAULT_PEN
            changes.clear()
        elif p in _SWITCHES:
            changes.update(_SWITCHES[p])
        elif 30 <= p <= 37 or 40 <= p <= 47:
            changes[layer] = f"p{p % 10}"
        elif 90 <= p <= 97 or 100 <= p <= 107:
            changes[layer] = f"p{p % 10 + 8}"
        elif p in (39, 49):
            changes[layer] = ""
        elif (
            p in (38, 48)
            and params[i + 1 : i + 2] == [5]
            and i + 2 < len(params)
        ):
            changes[layer] = _indexed(params[i + 2])
            i += 2
        elif (
            p in (38, 48)
            and params[i + 1 : i + 2] == [2]
            and i + 4 < len(params)
        ):
            changes[layer] = _hex(*params[i + 2 : i + 5])
            i += 4
        else:
            raise ValueError(f"SGR `{body}m` sets {p}, which is not read here")
        i += 1
    return replace(pen, **changes) if changes else pen


def _cell_rows(capture: str) -> Iterator[list[Cell]]:
    """Every line of a colour capture, as each character and its pen.

    The pen carries from one line into the next, as it would in a terminal
    reading the same bytes. It decides nothing on 26.9.1: every line of
    `e2e.py`'s 32 colour captures, 1312 of them, reads the same parsed alone.

    An escape that is not an SGR is refused rather than drawn as text, and so
    is an SGR this cannot read: either would put a cell on the page in a
    colour the terminal never showed.
    """
    pen = _DEFAULT_PEN
    for line in capture.split("\n"):
        cells: list[Cell] = []
        at = 0
        for found in _SEQUENCE.finditer(line):
            cells.extend((ch, pen) for ch in line[at : found.start()])
            if found.group(1) is None:
                raise ValueError(
                    f"an escape that is not an SGR: {line[found.start() :][:8]!r}"
                )
            pen = _drawn_after(pen, found.group(1))
            at = found.end()
        cells.extend((ch, pen) for ch in line[at:])
        yield cells


def pens(capture: str) -> list[list[Cell]]:
    """Every line of a colour capture, as each character and its pen."""
    return list(_cell_rows(capture))


def current_cells(capture: str) -> list[list[Cell]]:
    """The current pane of a colour capture, row by row, as `pens` reads it.

    The cells after a row's first divider and before its next, which is the
    field `field_of` takes out of plain text; a row with no divider -- the
    header, the status bar -- is left out rather than answered empty.
    """
    rows: list[list[Cell]] = []
    for cells in _cell_rows(capture):
        bars = [i for i, (ch, _) in enumerate(cells) if ch == BAR]
        if bars:
            rows.append(cells[bars[0] + 1 : bars[1] if len(bars) > 1 else None])
    return rows


@dataclass(frozen=True)
class WordRow:
    """One row as `word_pens` reads it.

    `ground` is the pen of the cell before the first word, which is the row's
    own: nothing on most rows, and the hover's reverse on the hovered one.
    `words` is every pen each word's characters were drawn in, and `between`
    every pen of the cells between the words that no word covers.
    """

    ground: Pen
    words: dict[str, frozenset[Pen]]
    between: frozenset[Pen]


def word_pens(capture: str, words: list[str]) -> list[WordRow]:
    """Current-pane rows that hold every word, each with how it was drawn.

    A word is matched whole, so `blink` is not read out of `blink_rapid`. A
    row missing a word is left out rather than answered in part, so a caller
    holds the count against the pane.
    """
    out: list[WordRow] = []
    for cells in current_cells(capture):
        text = "".join(ch for ch, _ in cells)
        spans: dict[str, tuple[int, int]] = {}
        for word in words:
            found = re.search(rf"(?<!\w){re.escape(word)}(?!\w)", text)
            if not found or found.start() == 0:
                break
            spans[word] = found.span()
        else:
            first = min(at for at, _ in spans.values())
            last = max(end for _, end in spans.values())
            covered = {i for at, end in spans.values() for i in range(at, end)}
            out.append(
                WordRow(
                    ground=cells[first - 1][1],
                    words={
                        word: frozenset(pen for _, pen in cells[at:end])
                        for word, (at, end) in spans.items()
                    },
                    between=frozenset(
                        cells[i][1]
                        for i in range(first, last)
                        if i not in covered
                    ),
                )
            )
    return out


def misdrawn(rows: list[WordRow], word: str) -> int:
    """Rows where `word` is not its row's ground with its own attribute alone.

    Held to the ground rather than to the cell beside the word, because an
    attribute a column failed to take off carries into the separator after
    it, and a word measured against that separator would inherit the leak and
    pass. On the hovered row a `reversed` word is the ground itself, measured
    on 26.9.1: the row is reversed already.
    """
    field = DRAWN_AS[word]
    return sum(
        row.words[word] != {replace(row.ground, **{field: True})}
        for row in rows
    )


def leaked(rows: list[WordRow]) -> int:
    """Rows where a cell between the words is drawn in more than the ground.

    The other half of `misdrawn`: a column that left its attribute on after
    its last cell shows first in the separator after it, and only reaches the
    next word as well when nothing in between takes it off.
    """
    return sum(not row.between <= {row.ground} for row in rows)
