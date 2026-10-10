#!/usr/bin/env python3
"""Draw the pictures in `docs/examples.md`, by running the configuration above
each of them in a real Yazi.

    test/examples.py          draw every picture
    test/examples.py --clean  throw the scratch directory away

`docs/examples.md` is the source: a picture is an image line, and what it is a
picture of is the `init.lua` block above it, with a `theme.toml` block if the
example has one -- each fenced block naming its file on its first line, the
way the README spells them. This opens a Yazi on that configuration and on a
folder built here, captures it the way `e2e.py` does, and writes the file list
as an SVG: on one dark terminal and one light, or on every ground `gallery.py`
draws on where the picture says so.

Each SVG carries a digest of the blocks it was drawn from, and
`test_examples.py` holds every image line to it in CI, so a configuration
edited without its picture being redrawn fails there rather than being
published beside a picture of something else. Drawing needs a Yazi and a
terminal, and is not in CI, for the reason `e2e.py` is not.

The pictures switch Yazi's file icons off. They are Nerd Font glyphs, which an
SVG cannot draw unless its viewer has the font, and a picture full of empty
boxes says the plugin is broken. The two half-discs Yazi draws at either end of
the hovered row are drawn as shapes instead, since they are the cursor.
"""

from __future__ import annotations

import hashlib
import re
import sys
import tempfile
import time
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from xml.sax.saxutils import escape, quoteattr

sys.path.insert(0, str(Path(__file__).resolve().parent))

# First, because importing it is what refuses too old a Python, and `screen`
# cannot be read by one.
import harness  # noqa: F401
import screen as sc
import setup as fixture
from e2e import TROUBLE
from gallery import SCHEMES, Scheme, scheme
from harness import ROOT, Session, catch_term, need, refuse, yazi_env, yazi_log

EXAMPLES = ROOT / "docs" / "examples.md"

DIR = Path(tempfile.gettempdir()) / "supaline-examples"

#: The window a picture is taken in. Narrower than the harnesses' own, because
#: a picture holds one pane and is read at the width of a page.
WIDTH, HEIGHT = 64, 16

#: What Yazi is told besides the example: the linemode every example is
#: written to define, and the current pane alone, so the file list is the
#: whole window and nothing either side of it is drawn half-cut.
YAZI_TOML = """\
[mgr]
linemode = "detail"
ratio    = [0, 1, 0]
"""

#: Put before the example's own `theme.toml`, so the icons are switched off
#: however the example themes the rest. Measured on 26.9.1, the five lists
#: written empty leave no icon drawn: they replace the preset's rather than
#: adding to it.
NO_ICONS = """\
[icon]
globs = []
dirs  = []
files = []
exts  = []
conds = []
"""

#: The two grounds a picture is drawn on unless it asks for every one: a
#: dark terminal and a light one, out of the seven `gallery.py` draws on.
#: Both, rather than the one matching the reader's page, because a reader on
#: a dark page may well run a light terminal -- and a configuration tuned for
#: one ground is worth seeing on the other.
PAIR = ("Catppuccin Mocha", "Solarized light")

#: A line above an image asking for every ground instead, for a picture whose
#: point is how the columns follow the terminal's palette. A comment, so the
#: page shows nothing of it and markdownlint asks for no exemption.
EVERY = "<!-- drawn on every ground -->"

#: The first line of a block, naming the file it belongs in.
INIT = "-- ~/.config/yazi/init.lua"
THEME = "# ~/.config/yazi/theme.toml"

IMAGE = re.compile(r"^!\[([^\]]+)\]\((examples/[a-z0-9-]+\.svg)\)$")
FENCE = re.compile(r"^```")

#: The attribute the digest is written in, on the SVG's root element.
SOURCE = "data-source"


@dataclass(frozen=True)
class Example:
    """One picture, and the blocks above it that it is a picture of."""

    image: str
    alt: str
    init: str
    theme: str = ""
    every: bool = False

    @property
    def digest(self) -> str:
        """What the picture was drawn from, so a block edited since says so --
        and the grounds it was asked for, since those change the picture as
        much."""
        body = f"{self.init}\0{self.theme}\0{self.every}".encode()
        return hashlib.sha256(body).hexdigest()


def examples(text: str) -> list[Example]:
    """Every picture in `docs/examples.md`, with its blocks.

    A block belongs to the next image below it, and so does `EVERY`. An image
    with no `init.lua` block since the one before it is refused, since there
    would be nothing to draw, and so is a second block for one file: which of
    the two is the picture's would be a guess.
    """
    found: list[Example] = []
    blocks: dict[str, str] = {}
    every = False
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if FENCE.match(line):
            end = next(
                (j for j in range(i + 1, len(lines)) if FENCE.match(lines[j])),
                None,
            )
            if end is None:
                raise ValueError(f"line {i + 1}: a block that never closes")
            body = lines[i + 1 : end]
            if body and body[0] in (INIT, THEME):
                if body[0] in blocks:
                    raise ValueError(
                        f"line {i + 1}: a second `{body[0]}` block before "
                        "the picture the first one is for"
                    )
                blocks[body[0]] = "\n".join(body) + "\n"
            i = end + 1
            continue
        if line == EVERY:
            every = True
        image = IMAGE.match(line)
        if image:
            if INIT not in blocks:
                raise ValueError(
                    f"line {i + 1}: {image.group(2)} has no `{INIT}` block "
                    "above it"
                )
            found.append(
                Example(
                    image.group(2),
                    image.group(1),
                    blocks[INIT],
                    blocks.get(THEME, ""),
                    every,
                )
            )
            blocks, every = {}, False
        i += 1
    return found


def drawn_on(
    example: Example, grounds: list[tuple[str, str]]
) -> list[tuple[str, str]]:
    """The grounds `example` is drawn on, out of every one there is."""
    if example.every:
        return grounds
    return [(name, hex) for name, hex in grounds if name in PAIR]


def drawn_from(svg: str) -> str | None:
    """The digest an SVG this wrote says it was drawn from."""
    found = re.search(rf'{SOURCE}="([0-9a-f]+)"', svg)
    return found.group(1) if found else None


# --- the folder every picture is of -----------------------------------------

#: The folder's entries: a size each, `None` for a directory, and the date it
#: carries as `MMDDhhmm` of this year. This year's because `mtime` draws one as
#: a time of day, which is the form most of a real listing is in, and the year
#: itself never reaches the screen -- so the picture is the same whichever year
#: it is redrawn in.
FOLDER: dict[str, tuple[int | None, str]] = {
    "assets": (None, "09141802"),
    "docs": (None, "10021133"),
    "src": (None, "10091947"),
    "backup.tar.gz": (48_000_000, "06300200"),
    "cover.png": (2_100_000, "09141758"),
    "demo.mp4": (180_000_000, "08221510"),
    "install.sh": (3_200, "03110921"),
    "LICENSE": (1_070, "01050000"),
    "notes.md": (6_100, "10101026"),
    "README.md": (12_000, "10091952"),
    "report.pdf": (860_000, "07180845"),
}

#: The executables, so `permissions` has an `x` to draw.
EXECUTABLE = {"install.sh"}

#: The name the screen is waited on, which sorts last.
LANDMARK = "report.pdf"


def build_folder(root: Path) -> Path:
    """The folder a picture is taken in, under `root`.

    A directory holds a few files, so the hovered one -- which Yazi lists, and
    `size` then counts -- has entries to count. Sizes are sparse, as
    `setup.sized` says why.
    """
    folder = root / "project"
    year = time.localtime().tm_year
    for name, (size, _) in FOLDER.items():
        path = folder / name
        if size is None:
            path.mkdir(parents=True)
            for n in range(3):
                (path / f"{name}-{n}").write_bytes(b"x")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            fixture.sized(path, size)
        if name in EXECUTABLE:
            path.chmod(0o755)
    # After everything is created, because creating an entry moves its
    # directory's mtime.
    for name, (_, when) in FOLDER.items():
        fixture.stamp(folder / name, fixture.epoch(f"{year}{when}"))
    return folder


# --- taking the picture ------------------------------------------------------


def capture(root: Path, folder: Path, example: Example) -> str:
    """The screen a Yazi draws on `folder` under `example`, with its colours.

    Refused when Yazi logged an error, since a column that failed has drawn a
    picture of the failure -- and a notification over the list would be in
    the picture besides.
    """
    config = root / "config"
    config.mkdir(exist_ok=True)
    (config / "yazi.toml").write_text(YAZI_TOML)
    (config / "init.lua").write_text(example.init)
    (config / "theme.toml").write_text(NO_ICONS + "\n" + example.theme)
    plugin = config / "plugins" / "supaline.yazi"
    if not plugin.is_symlink():
        plugin.parent.mkdir(parents=True, exist_ok=True)
        plugin.symlink_to(ROOT)

    state = f"state-{Path(example.image).stem}"
    session = Session(f"supaline-examples-{Path(example.image).stem}")
    session.start(
        ["yazi", str(folder)],
        env=yazi_env(root, state),
        width=WIDTH,
        height=HEIGHT,
    )
    try:
        session.wait_for(lambda s: LANDMARK in s, "the folder listed")
        screen = session.settle(colour=True)
    finally:
        session.kill()

    log = yazi_log(root, state)
    trouble = [
        line
        for line in (log.read_text() if log.exists() else "").splitlines()
        if TROUBLE.search(line)
    ]
    if trouble:
        refuse(
            f"examples: Yazi logged trouble drawing {example.image}:\n"
            + "\n".join(f"  {line.strip()}" for line in trouble[:5])
        )
    return screen


def file_rows(screen: str) -> list[list[sc.Cell]]:
    """The file list: every row between the header and the status bar, less
    the empty ones under the last entry."""
    rows = sc.pens(screen.rstrip("\n"))[1:-1]
    while rows and all(ch == " " and pen == sc.Pen() for ch, pen in rows[-1]):
        rows.pop()
    return rows


# --- drawing it --------------------------------------------------------------

#: A cell, and the font it is drawn in: 0.6em across, the advance most
#: monospace faces have. Each run is placed at its own column, so a face that
#: is narrower or wider is off within a word and never past one.
CELL_W, CELL_H, FONT = 8.4, 18, 14
FAMILY = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace"

#: Around a tile's rows, the strip its name is written in, and between tiles.
PAD, TITLE, GAP = 12, 26, 16

#: Tiles to a row. One, so a tile is drawn at its own size: GitHub fits an
#: image to the page's text column, and two across were shrunk to about two
#: thirds there, measured in Chrome, with the text the size of a footnote.
ACROSS = 1

#: The glyphs drawn as shapes rather than text: the half-discs either side of
#: the hovered row, U+E0B6 and U+E0B4, open towards the row. Any other
#: private-use character is refused, because the viewer has no font for it.
CAPS = {"\ue0b6": "left", "\ue0b4": "right"}


def label(name: str) -> str:
    """What a tile is called: its scheme, or the terminal nobody themed."""
    return name if name in SCHEMES else f"xterm, {name} ground"


def mix(a: str, b: str) -> str:
    """Halfway between two hexes, which is what a terminal dims towards."""
    pa = [int(a[i : i + 2], 16) for i in (1, 3, 5)]
    pb = [int(b[i : i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{(x + y) // 2:02x}" for x, y in zip(pa, pb))


def colours(pen: sc.Pen, palette: Scheme) -> tuple[str, str]:
    """A pen's foreground and background, as hexes in `palette`."""

    def resolve(value: str, default: str) -> str:
        if value.startswith("p"):
            return palette.named[int(value[1:])]
        return value or default

    fg = resolve(pen.fg, palette.fg)
    bg = resolve(pen.bg, palette.ground)
    if pen.reverse:
        fg, bg = bg, fg
    if pen.dim:
        fg = mix(fg, bg)
    return fg, bg


def width(ch: str) -> int:
    """The cells a character takes, as the terminal gave them."""
    return 2 if unicodedata.east_asian_width(ch) in "WF" else 1


def cap(side: str, x: float, y: float, fill: str) -> str:
    """A half-disc filling one cell, its flat side towards the row."""
    if side == "left":
        start, sweep = x + CELL_W, 0
    else:
        start, sweep = x, 1
    return (
        f'<path d="M{start:g},{y:g} A{CELL_W:g},{CELL_H / 2:g} 0 0 {sweep} '
        f'{start:g},{y + CELL_H:g} Z" fill="{fill}"/>'
    )


def runs(row: list[sc.Cell]) -> list[tuple[int, str, sc.Pen]]:
    """A row as its runs of one pen, each with the column it starts at. A cap
    is a run of its own, since it is drawn as a shape."""
    found: list[tuple[int, str, sc.Pen]] = []
    col = 0
    for ch, pen in row:
        if ch not in CAPS and (
            0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000
        ):
            raise ValueError(
                f"U+{ord(ch):04X}: a private-use glyph no viewer has a font for"
            )
        last = found[-1] if found else None
        if last and last[2] == pen and CAPS.keys().isdisjoint({ch, last[1]}):
            found[-1] = (last[0], last[1] + ch, pen)
        else:
            found.append((col, ch, pen))
        col += width(ch)
    return found


def drawn_run(
    at: int, text: str, pen: sc.Pen, y: float, palette: Scheme
) -> list[str]:
    """One run, at column `at` of the row whose top is `y`: its background
    where it has one of its own, then its text or its cap."""
    fg, bg = colours(pen, palette)
    x = PAD + at * CELL_W
    out = []
    if bg != palette.ground:
        cells = sum(width(ch) for ch in text)
        out.append(
            f'<rect x="{x:g}" y="{y:g}" width="{cells * CELL_W:g}" '
            f'height="{CELL_H}" fill="{bg}"/>'
        )
    if text in CAPS:
        out.append(cap(CAPS[text], x, y, fg))
    elif not pen.hidden:
        # A word at a time, each at its own column: a browser drawing an SVG
        # as an image collapses a run of spaces whatever `xml:space` says,
        # measured in Chrome on GitHub, and a right-aligned column is spaces
        # first.
        attrs = [f'fill="{fg}"']
        if pen.bold:
            attrs.append('font-weight="bold"')
        if pen.italic:
            attrs.append('font-style="italic"')
        for word in re.finditer(r"\S+", text):
            wx = x + sum(width(ch) for ch in text[: word.start()]) * CELL_W
            out.append(
                f'<text x="{wx:g}" y="{y + CELL_H * 0.72:g}" {" ".join(attrs)}>'
                f"{escape(word.group())}</text>"
            )
        # Lines as shapes, for the same reason: a terminal draws them under
        # the spaces too, and there are no spaces left to draw them under.
        cells = sum(width(ch) for ch in text)
        for level, on in ((0.86, pen.underline), (0.5, pen.crossed)):
            if on:
                out.append(
                    f'<rect x="{x:g}" y="{y + CELL_H * level:g}" '
                    f'width="{cells * CELL_W:g}" height="1" fill="{fg}"/>'
                )
    return out


def tile(rows: list[list[sc.Cell]], name: str, palette: Scheme) -> list[str]:
    """One ground's tile, at the origin: its ground, its name, and the rows."""
    cols = max((sum(width(ch) for ch, _ in row) for row in rows), default=0)
    w = cols * CELL_W + 2 * PAD
    h = TITLE + len(rows) * CELL_H + PAD
    # Edged in grey, so a tile on the ground of the page it sits on still has
    # a shape: GitHub draws a light page white and a dark one near black, the
    # two xterm grounds.
    out = [
        (
            f'<rect width="{w:g}" height="{h:g}" rx="8" '
            f'fill="{palette.ground}" stroke="#8888" stroke-width="1"/>'
        ),
        (
            f'<text x="{PAD}" y="{TITLE - 9}" font-size="12" '
            f'fill="{mix(palette.fg, palette.ground)}">'
            f"{escape(label(name))}</text>"
        ),
    ]
    for r, row in enumerate(rows):
        for at, text, pen in runs(row):
            out.extend(drawn_run(at, text, pen, TITLE + r * CELL_H, palette))
    return out


def svg(
    rows: list[list[sc.Cell]],
    grounds: list[tuple[str, str]],
    example: Example,
) -> str:
    """The picture: a tile per ground, `ACROSS` to a row."""
    cols = max((sum(width(ch) for ch, _ in row) for row in rows), default=0)
    tw = cols * CELL_W + 2 * PAD
    th = TITLE + len(rows) * CELL_H + PAD
    down = -(-len(grounds) // ACROSS)
    w = ACROSS * tw + (ACROSS - 1) * GAP
    h = down * th + (down - 1) * GAP
    body = []
    for i, (name, hex) in enumerate(grounds):
        x, y = (i % ACROSS) * (tw + GAP), (i // ACROSS) * (th + GAP)
        body.append(f'<g transform="translate({x:g},{y:g})">')
        body.extend(tile(rows, name, scheme(name, hex)))
        body.append("</g>")
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:g}" height="{h:g}" '
        f'viewBox="0 0 {w:g} {h:g}" role="img" {SOURCE}="{example.digest}" '
        f'font-family={quoteattr(FAMILY)} font-size="{FONT}">\n'
        f"<title>{escape(example.alt)}</title>\n"
        + "\n".join(body)
        + "\n</svg>\n"
    )


# --- the run -----------------------------------------------------------------

USAGE = "test/examples.py [--clean]"


def main(argv: list[str]) -> int:
    if argv not in ([], ["--clean"]):
        refuse(f"usage: {USAGE}")
    if argv == ["--clean"]:
        fixture.clear(DIR)
        print(f"examples: removed {DIR}")
        return 0

    need("tmux", "yazi")
    catch_term()
    grounds = fixture.terminal_grounds(
        (fixture.FIXTURE / "init.lua").read_text()
    )
    if not grounds:
        refuse(
            "examples: no ground in the comment above `GROUND` in "
            "test/fixture/init.lua -- a name and a backticked hex each"
        )
    try:
        found = examples(EXAMPLES.read_text())
    except ValueError as error:
        refuse(f"examples: {EXAMPLES.relative_to(ROOT)}: {error}")
    if not found:
        refuse(f"examples: no picture in {EXAMPLES.relative_to(ROOT)}")

    fixture.clear(DIR)
    DIR.mkdir()
    (DIR / fixture.MARKER).touch()
    missing = set(PAIR) - {name for name, _ in grounds}
    if missing:
        refuse(
            f"examples: {', '.join(sorted(missing))} is not among the grounds "
            "test/fixture/init.lua names"
        )
    folder = build_folder(DIR)
    for example in found:
        rows = file_rows(capture(DIR, folder, example))
        if not rows:
            refuse(f"examples: {example.image} drew no rows")
        try:
            picture = svg(rows, drawn_on(example, grounds), example)
        except ValueError as error:
            refuse(f"examples: {example.image}: {error}")
        target = EXAMPLES.parent / example.image
        target.parent.mkdir(exist_ok=True)
        target.write_text(picture)
        print(f"examples: drew {target.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
