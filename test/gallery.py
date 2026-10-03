#!/usr/bin/env python3
"""The colour steps of the walk, drawn on seven terminal grounds at once.

    test/gallery.py          capture them, and serve the ones not yet approved
    test/gallery.py --all    ... every one of them, approved or not
    test/gallery.py --clean  throw the gallery away

The walk in `manual.py` asks its questions on one ground, the reader's own, and
a colour readable there may not be on the next reader's. So this takes the
walk's steps that say `gallery = true`, captures each the way `e2e.py` does,
and draws the current pane of every capture on each ground `init.lua` measures
`GROUND` against, side by side, under the step's question.

Each tile is drawn in the colour scheme its ground is named after: the
ground, the foreground text takes when nothing colours it, and the sixteen
named colours a `blue` or a `magenta` is drawn in, since a terminal draws those
from its own scheme. `black` and `white` stand for a terminal nobody themed,
xterm's named colours under white or black text. The font, the bold and the
width of a wide character are the browser's -- which is why a step about any
of those is the walk's alone.

The page is served by this process, on localhost, because a verdict given on it
is written to `verdicts.txt` beside it, under the same header as the walk's.
Ctrl-C stops it and prints them, since the next run rebuilds the directory they
are in.

A yes is also written to `test/approved.toml`, as a digest of what was shown,
and a no takes it out again. A step whose digest is there is left off the page,
so a run asks only about the steps that moved since someone looked, and opens
no browser at all when none did.
"""

from __future__ import annotations

import fcntl
import hashlib
import html
import itertools
import json
import re
import sys
import tempfile
import threading
import unicodedata
import webbrowser
from collections import defaultdict
from collections.abc import Container
from dataclasses import astuple
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import IO, NamedTuple

sys.path.insert(0, str(Path(__file__).resolve().parent))

import screen as sc
import setup as fixture
from e2e import Run
from harness import begin_verdicts, catch_term, need, print_verdicts, refuse

DIR = Path(tempfile.gettempdir()) / "supaline-gallery"

VERDICTS = DIR / fixture.VERDICTS

#: Beside `DIR` rather than in it, since what it guards is the rebuilding of
#: `DIR` itself.
LOCK = DIR.with_suffix(".lock")

#: The steps a reader said yes to, tracked, so that a change which moves a
#: pane carries the approval of the pane it moved to, or shows it has none.
APPROVED = fixture.ROOT / "test" / "approved.toml"

#: xterm's sixteen named colours, `p0` to `p15`, for a ground `SCHEMES` has
#: no scheme for.
XTERM = (
    "#000000",
    "#cd0000",
    "#00cd00",
    "#cdcd00",
    "#0000ee",
    "#cd00cd",
    "#00cdcd",
    "#e5e5e5",
    "#7f7f7f",
    "#ff0000",
    "#00ff00",
    "#ffff00",
    "#5c5cff",
    "#ff00ff",
    "#00ffff",
    "#ffffff",
)


class Scheme(NamedTuple):
    """A terminal's colours: its ground, the foreground text takes when
    nothing colours it, and the sixteen named colours, `p0` to `p15`."""

    ground: str
    fg: str
    named: tuple[str, ...]


#: The sixteen Solarized draws in both modes, from the `16/8 TERMCOL` column
#: of the table in altercation/solarized's README.
SOLARIZED = (
    "#073642",
    "#dc322f",
    "#859900",
    "#b58900",
    "#268bd2",
    "#d33682",
    "#2aa198",
    "#eee8d5",
    "#002b36",
    "#cb4b16",
    "#586e75",
    "#657b83",
    "#839496",
    "#6c71c4",
    "#93a1a1",
    "#fdf6e3",
)

#: The schemes behind the grounds `init.lua` names, under the same names, so a
#: named colour on a tile is the one that terminal draws: `blue` is `#89b4fa`
#: in Catppuccin Mocha and `#268bd2` in Solarized. Each is copied from a
#: published definition, never recalled, and from the scheme's own wherever
#: its author publishes one, because the ports disagree -- Ghostty's One Dark
#: is on another ground altogether:
#:
#: - Catppuccin Mocha: `ansiColors` in catppuccin/palette's `palette.json`.
#: - One Dark: alacritty/alacritty-theme's `one_dark.toml`. One Dark is Atom's
#:   editor theme, whose author publishes no terminal palette, and this is the
#:   port drawn on the ground `init.lua` names.
#: - Gruvbox dark: morhetz/gruvbox-contrib's `gruvbox-dark.xresources`.
#: - Solarized: `SOLARIZED`, with the README's ground and body text for each
#:   mode, `base03:base0` dark and `base3:base00` light.
SCHEMES = {
    "Catppuccin Mocha": Scheme(
        "#1e1e2e",
        "#cdd6f4",
        (
            "#45475a",
            "#f38ba8",
            "#a6e3a1",
            "#f9e2af",
            "#89b4fa",
            "#f5c2e7",
            "#94e2d5",
            "#a6adc8",
            "#585b70",
            "#f37799",
            "#89d88b",
            "#ebd391",
            "#74a8fc",
            "#f2aede",
            "#6bd7ca",
            "#bac2de",
        ),
    ),
    "One Dark": Scheme(
        "#282c34",
        "#abb2bf",
        (
            "#1e2127",
            "#e06c75",
            "#98c379",
            "#d19a66",
            "#61afef",
            "#c678dd",
            "#56b6c2",
            "#abb2bf",
            "#5c6370",
            "#e06c75",
            "#98c379",
            "#d19a66",
            "#61afef",
            "#c678dd",
            "#56b6c2",
            "#ffffff",
        ),
    ),
    "Gruvbox dark": Scheme(
        "#282828",
        "#ebdbb2",
        (
            "#282828",
            "#cc241d",
            "#98971a",
            "#d79921",
            "#458588",
            "#b16286",
            "#689d6a",
            "#a89984",
            "#928374",
            "#fb4934",
            "#b8bb26",
            "#fabd2f",
            "#83a598",
            "#d3869b",
            "#8ec07c",
            "#ebdbb2",
        ),
    ),
    "Solarized dark": Scheme("#002b36", "#839496", SOLARIZED),
    "Solarized light": Scheme("#fdf6e3", "#657b83", SOLARIZED),
}

#: The gallery's steps by their number on the walk, which is what both files
#: of verdicts call them by.
Shown = dict[int, fixture.Step]


def capture(r: Run, shown: Shown) -> None:
    """Each step's capture, kept by `Run.shot` as `step-<n>`, out of a Yazi
    per theme.

    A Yazi per theme rather than the theme's key, because a theme changes the
    colours alone and `settle` reads plain text, so it would return before the
    repaint as readily as after it. A Yazi opened on a theme draws in it from
    its first frame, which the first half of `e2e.py`'s theme check holds every
    run. Killed rather than quit, since nothing here reads its log.
    """
    by_theme: dict[str, list[tuple[int, fixture.Step]]] = defaultdict(list)
    for n, step in shown.items():
        by_theme[step.theme].append((n, step))
    for theme, steps in by_theme.items():
        fixture.put_theme(r.dir, theme)
        r.open_yazi("state")
        for n, step in steps:
            show(r, r.listing.cases[step.case])
            r.shot(f"step-{n}")
        r.session.kill()


def show(r: Run, case: fixture.Case) -> None:
    """`Run.show`, held to the colours as well as the text.

    Steps in one folder can draw the same text in other colours -- `c_ramp`,
    `c_spread` and `c_hue` are the same two columns on three ramps -- and
    `Run.show` waits on plain captures, which hold still on the step before as
    readily as on this one. So the coloured screen has to move off the one
    before the press, and then hold still. A step that never moves it is
    refused rather than drawn, because its tiles would be the step before's
    under this one's question.
    """
    was = r.session.capture(colour=True)
    r.show(case)
    now = r.session.wait_for(
        lambda s: s != was, f"{case.id} drawn", colour=True
    )
    if now == was:
        refuse(
            f"gallery: {case.key} drew what the step before it drew -- a "
            "gallery step has to differ from the one before it"
        )
    r.session.settle(colour=True)


def foreground(ground: str) -> str:
    """The default foreground on `ground`: black on a light one, white on a
    dark one, by the mean of its channels -- the seven are nowhere near the
    middle."""
    light = sum(int(c) for c in sc.rgb(ground).split(";")) > 3 * 127
    return "#000000" if light else "#ffffff"


def scheme(name: str, ground: str) -> Scheme:
    """The scheme a ground is drawn in: its own, or xterm's named colours
    under black or white text."""
    return SCHEMES.get(name) or Scheme(ground, foreground(ground), XTERM)


def tile_rule(n: int, scheme: Scheme) -> str:
    """The rule `.g<n>` puts a tile in its scheme with."""
    named = ";".join(f"--p{i}:{hex}" for i, hex in enumerate(scheme.named))
    return f".g{n} {{ --bg:{scheme.ground};--fg:{scheme.fg};{named} }}"


def css(pen: sc.Pen) -> str:
    """A pen as an inline style, empty for the tile's own colours.

    The tile carries its scheme's ground and foreground as `--bg` and `--fg`,
    and its named colours as `--p0` to `--p15`, so one rendering of a capture
    serves every ground.
    """

    def colour(value: str, default: str) -> str:
        return f"var(--{value})" if value.startswith("p") else value or default

    fg, bg = colour(pen.fg, "var(--fg)"), colour(pen.bg, "var(--bg)")
    if pen.reverse:
        fg, bg = bg, fg
    return ";".join(
        part
        for part, wanted in (
            (f"color:{fg}", fg != "var(--fg)"),
            (f"background:{bg}", bg != "var(--bg)"),
            ("font-weight:bold", pen.bold),
            ("font-style:italic", pen.italic),
            ("text-decoration:underline", pen.underline),
        )
        if wanted
    )


def glyph(ch: str) -> str:
    """One character, held to the cells a terminal gives it.

    Anything past ASCII is boxed to its width, so a wide character or an icon
    from a font the browser does not have pushes nothing after it out of its
    column.
    """
    if " " <= ch <= "~":
        return html.escape(ch)
    cells = 2 if unicodedata.east_asian_width(ch) in "WF" else 1
    return f'<span class="w{cells}">{html.escape(ch)}</span>'


def drawn(rows: list[list[sc.Cell]]) -> str:
    """The rows `sc.current_cells` read, as HTML: a span per run of one pen."""
    lines = []
    for cells in rows:
        runs = []
        for pen, run in itertools.groupby(cells, key=lambda cell: cell[1]):
            text = "".join(glyph(ch) for ch, _ in run)
            style = css(pen)
            runs.append(
                f'<span style="{style}">{text}</span>' if style else text
            )
        lines.append("".join(runs))
    return "\n".join(lines)


def page(
    header: tuple[str, ...],
    shown: Shown,
    keys: dict[int, str],
    panes: dict[int, str],
    grounds: list[tuple[str, str]],
    approved: Container[int] = frozenset(),
) -> str:
    """The whole page: the header the verdicts are under, then a section per
    step, its question and its buttons above a tile per ground. A step in
    `approved`, which only `--all` shows, says so in its heading.

    Each pane is written once, in a `<template>` the page's script copies into
    every tile: the colour scheme is the tile's, one rule per ground, and not
    the pane's, and seven copies were six sevenths of the page.
    """
    sections = []
    for n, step in shown.items():
        tiles = "".join(
            f'<figure class="g{i}">'
            f'<figcaption><label><input type="checkbox" value="{html.escape(name)}">'
            f" {html.escape(name)} <code>{hex}</code></label></figcaption>"
            "<pre></pre></figure>"
            for i, (name, hex) in enumerate(grounds)
        )
        sections.append(
            f'<section id="step-{n}" data-step="{n}">'
            f"<h2>step {n} · <code>{keys[n]}</code> · "
            f"{step.case} under {step.theme}"
            f"{' · approved' if n in approved else ''}</h2>"
            f'<p class="ask">{html.escape(step.ask)}</p>'
            '<p><button data-said="yes">looks right</button> '
            '<button data-said="no">looks wrong on the ticked</button> '
            '<span class="said"></span></p>'
            f"<template>{panes[n]}</template>"
            f'<div class="tiles">{tiles}</div></section>'
        )
    return PAGE.format(
        schemes="\n".join(
            tile_rule(i, scheme(name, hex))
            for i, (name, hex) in enumerate(grounds)
        ),
        header=html.escape("\n".join(header)),
        sections="\n".join(sections),
    )


PAGE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>supaline gallery</title>
<style>
{schemes}
body {{ margin: 16px; font: 15px/1.4 system-ui, sans-serif;
  background: #d8d8d8; color: #111; }}
section {{ margin: 0 0 40px; }}
h2 {{ font-size: 17px; margin: 0 0 4px; }}
.ask {{ font-size: 17px; margin: 0 0 6px; }}
.tiles {{ display: grid; gap: 12px; font: 11px/1.25 ui-monospace, Menlo,
  "Symbols Nerd Font Mono", monospace;
  grid-template-columns: repeat(auto-fill, minmax(min(100%, 86ch), 1fr)); }}
figure {{ margin: 0; }}
figcaption {{ font: 13px system-ui, sans-serif; margin: 0 0 2px; }}
pre {{ margin: 0; padding: 4px; font: inherit; overflow-x: auto;
  background: var(--bg); color: var(--fg); }}
.w1, .w2 {{ display: inline-block; overflow: hidden; vertical-align: bottom; }}
.w1 {{ width: 1ch; }}
.w2 {{ width: 2ch; }}
</style>
</head>
<body>
<pre>{header}</pre>
<p>Each tile is in the colour scheme it is named after: its ground, its
foreground, and the sixteen named colours a <code>blue</code> is drawn in.
<code>black</code> and <code>white</code> are a terminal nobody themed, in
xterm's. The font is the browser's. Tick the grounds a step looks wrong on, then
say so; answering a step again replaces the answer.</p>
{sections}
<script>
for (const section of document.querySelectorAll("section[data-step]")) {{
  const pane = section.querySelector("template").content;
  for (const tile of section.querySelectorAll("figure pre")) {{
    tile.replaceChildren(pane.cloneNode(true));
  }}
  const said = section.querySelector(".said");
  const buttons = section.querySelectorAll("button");
  // One answer in flight per step: the server writes each on its own thread,
  // so a second sent before the first returned could land before it, and the
  // line that counts would be the earlier answer.
  const busy = (on) => {{ for (const b of buttons) b.disabled = on; }};
  for (const button of buttons) {{
    button.addEventListener("click", async () => {{
      busy(true);
      const verdict = button.dataset.said;
      const grounds = verdict === "no"
        ? [...section.querySelectorAll("input:checked")].map((i) => i.value)
        : [];
      try {{
        const answer = await fetch("verdict", {{
          method: "POST",
          headers: {{ "Content-Type": "application/json" }},
          body: JSON.stringify({{
            step: Number(section.dataset.step), said: verdict, grounds,
          }}),
        }});
        if (!answer.ok) throw new Error(await answer.text());
        said.textContent = grounds.length
          ? `[no: ${{grounds.join(", ")}}]` : `[${{verdict}}]`;
      }} catch (error) {{
        said.textContent = `not recorded: ${{error.message}}`;
      }} finally {{
        busy(false);
      }}
    }});
  }}
}}
</script>
</body>
</html>
"""


class Verdict(NamedTuple):
    """A validated answer to one of the steps shown on the page."""

    n: int
    step: fixture.Step
    said: str
    grounds: list[str]

    def line(self) -> str:
        """The walk's four fields, then the grounds a no was given on."""
        return "\t".join(
            [
                str(self.n),
                self.step.case,
                self.step.theme,
                self.said,
                ", ".join(self.grounds),
            ]
        )


def verdict(body: bytes, shown: Shown, names: set[str]) -> Verdict:
    """The verdict the page posted, validated, or `ValueError`.

    Refused rather than written when it is anything the page does not send,
    since `print_verdicts` trusts the file it reads.
    """
    said = json.loads(body)
    n = said.get("step") if isinstance(said, dict) else None
    step = shown.get(n) if type(n) is int else None
    if step is None:
        raise ValueError("not a step the gallery shows")
    verdict, grounds = said.get("said"), said.get("grounds")
    if verdict not in ("yes", "no"):
        raise ValueError("a verdict is yes or no")
    if not isinstance(grounds, list) or not set(grounds) <= names:
        raise ValueError("not a list of the gallery's grounds")
    if verdict == "yes" and grounds:
        raise ValueError("a yes names no ground")
    return Verdict(n, step, verdict, grounds)


#: A step as `approved.toml` keys it: its case, and the theme it is shown
#: under. Not its number, which every step inserted above it would move.
Key = tuple[str, str]

#: A digest as `approved.toml` holds it.
DIGEST = re.compile(r"[0-9a-f]{64}")

#: What `approved.toml` opens with, since it is written whole when it changes.
APPROVED_HEADER = """\
# The gallery steps a reader said yes to, by case and theme, each with the
# digest of what they were shown: the current pane, cell by cell and pen by
# pen, the grounds and colour schemes it was drawn on, and the question.
#
# `test/gallery.py` writes this file -- a yes adds a step, a no takes it out --
# and shows only the steps whose digest is not here. A line is added only from
# the page: it says a person looked at that pane, and nothing else can say so.
# Taking one out claims nothing, so a line whose step has left the gallery is
# deleted by hand.
"""


def digest(
    cells: list[list[sc.Cell]], grounds: list[tuple[str, str]], ask: str
) -> str:
    """What a yes is a yes to, as a SHA-256.

    The current pane alone, because the header row carries the scratch
    directory, which is under `$TMPDIR` and so differs from one machine to the
    next. The grounds with their schemes, because a named colour on a tile is
    the scheme's. And the question, so a step asked differently is asked again.
    """
    seen = {
        "pane": [[[ch, *astuple(pen)] for ch, pen in row] for row in cells],
        "grounds": [[name, *scheme(name, hex)] for name, hex in grounds],
        "ask": ask,
    }
    return hashlib.sha256(json.dumps(seen).encode()).hexdigest()


def approvals(text: str) -> dict[Key, str]:
    """The digests an `approved.toml` holds, by key, or `ValueError`."""
    # Here rather than at the top, for the reason `setup.theme_values` gives.
    import tomllib

    found: dict[Key, str] = {}
    for case, themes in tomllib.loads(text).items():
        if not isinstance(themes, dict) or not themes:
            raise ValueError(f"`{case}` is not a table of digests by theme")
        for theme, said in themes.items():
            if not isinstance(said, str) or not DIGEST.fullmatch(said):
                raise ValueError(f"`{case}.{theme}` is not a digest")
            found[case, theme] = said
    return found


def approvals_text(found: dict[Key, str]) -> str:
    """`approved.toml` as it is written: a line per step, sorted, so a diff of
    it names the steps a change moved and nothing else."""
    lines = "".join(
        f'{case}.{theme} = "{said}"\n'
        for (case, theme), said in sorted(found.items())
    )
    return APPROVED_HEADER + (f"\n{lines}" if lines else "")


def read_approvals(path: Path = APPROVED) -> dict[Key, str]:
    """`approved.toml` itself -- nothing approved when there is none -- or a
    refusal that says what is wrong with it."""
    try:
        return approvals(path.read_text())
    except FileNotFoundError:
        return {}
    except ValueError as error:
        refuse(f"gallery: {path.relative_to(fixture.ROOT)}: {error}")


def pending(
    steps: Shown, digests: dict[int, str], found: dict[Key, str]
) -> Shown:
    """The steps whose pane, grounds or question moved since the yes recorded
    for them, or that have none."""
    return {
        n: step
        for n, step in steps.items()
        if found.get((step.case, step.theme)) != digests[n]
    }


class Approvals:
    """`approved.toml` as this run holds it, written whole when it changes.

    Held rather than read again at each one, since nothing but this run writes
    it while `hold_lock` is held.
    """

    def __init__(
        self, path: Path, found: dict[Key, str], digests: dict[int, str]
    ) -> None:
        self.path = path
        self.found = dict(found)
        self.digests = digests

    def record(self, verdict: Verdict) -> None:
        """Write the approval a verdict changes, and hold it once written.

        Not before: a write that fails leaves this as the file still is, so
        the same verdict sent again writes it rather than finding nothing to
        change.
        """
        key = verdict.step.case, verdict.step.theme
        found = dict(self.found)
        if verdict.said == "yes":
            found[key] = self.digests[verdict.n]
        else:
            found.pop(key, None)
        if found != self.found:
            self.path.write_text(approvals_text(found))
            self.found = found


def serve(
    body: bytes,
    shown: Shown,
    names: set[str],
    verdicts: Path,
    approved: Approvals,
) -> None:
    """Serve the page, and write each verdict posted to it, until Ctrl-C.

    Threaded, so a connection a browser opens ahead and never uses holds up no
    request behind it. The writes are taken one at a time, since `approved`
    is rewritten whole and two at once would keep whichever finished last.
    """
    writing = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def reply(
            self, code: int, sent: bytes, kind: str = "text/plain"
        ) -> None:
            self.send_response(code)
            self.send_header("Content-Type", f"{kind}; charset=utf-8")
            self.send_header("Content-Length", str(len(sent)))
            self.end_headers()
            self.wfile.write(sent)

        def do_GET(self) -> None:
            if self.path == "/":
                self.reply(200, body, "text/html")
            else:
                self.reply(404, b"only / is here")

        def do_POST(self) -> None:
            if self.path != "/verdict":
                self.reply(404, b"only /verdict takes a verdict")
                return
            length = int(self.headers.get("Content-Length", 0))
            try:
                said = verdict(self.rfile.read(length), shown, names)
            except ValueError as error:
                self.reply(400, str(error).encode())
                return
            with writing:
                with verdicts.open("a") as file:
                    file.write(said.line() + "\n")
                approved.record(said)
            self.reply(200, b"recorded")

        def log_message(self, format: str, *args: object) -> None:
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    url = f"http://127.0.0.1:{server.server_port}/"
    print(f"gallery: {url} -- Ctrl-C when you are done")
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        server.server_close()


def hold_lock() -> IO[str]:
    """Take the gallery for this run, or refuse if another run has it.

    Every run rebuilds the one `DIR`, and a run still serving appends to the
    `verdicts.txt` in it: a second run would delete the first one's verdicts
    and then take its late ones under its own header. Held until the file
    closes, which is what lets go of an `flock`, so `main` holds it across
    the whole run, `--clean` included.
    """
    file = LOCK.open("w")
    try:
        fcntl.flock(file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        file.close()
        refuse(
            "gallery: another gallery is running -- Ctrl-C it first, since "
            "this one would rebuild the directory it writes verdicts to"
        )
    return file


class Prepared(NamedTuple):
    """A page to serve, the steps on it, and the digest of every gallery step
    captured, shown or not."""

    body: bytes
    shown: Shown
    digests: dict[int, str]


def prepare(
    grounds: list[tuple[str, str]], found: dict[Key, str], everything: bool
) -> Prepared:
    """Capture every gallery step and draw the page, of the ones not in
    `found` unless `everything` is asked for.

    Every step is captured either way, since a digest is of the capture.
    """
    r = Run(keep=True, dir=DIR)
    steps = {n: step for n, step in enumerate(r.steps, 1) if step.gallery}
    if not steps:
        refuse(
            "gallery: no step in test/fixture/walk.toml says `gallery = true`"
        )
    try:
        r.setup()
        capture(r, steps)
    finally:
        # Kept, since the verdicts are written beside the captures.
        r.teardown()

    cells = {n: sc.current_cells(r.shots[f"colour-step-{n}"]) for n in steps}
    digests = {n: digest(cells[n], grounds, steps[n].ask) for n in steps}
    moved = pending(steps, digests, found)
    shown = steps if everything else moved
    if not shown:
        return Prepared(b"", {}, digests)

    header = begin_verdicts(
        VERDICTS,
        "supaline gallery: step, case, theme, verdict, grounds",
        "grounds  " + ", ".join(f"{name} {hex}" for name, hex in grounds),
    )
    keys = {n: r.listing.cases[step.case].key for n, step in shown.items()}
    panes = {n: drawn(cells[n]) for n in shown}
    body = page(header, shown, keys, panes, grounds, set(steps) - set(moved))
    return Prepared(body.encode(), shown, digests)


#: What `main` takes, each alone.
USAGE = "test/gallery.py [--all | --clean]"


def main(argv: list[str]) -> int:
    if argv not in ([], ["--all"], ["--clean"]):
        refuse(f"usage: {USAGE}")
    with hold_lock():
        if argv == ["--clean"]:
            # `setup.py` owns the marker file and the "is this ours" guard, so
            # it owns the removal too.
            fixture.main(["--clean", str(DIR)])
            print(f"gallery: removed {DIR}")
            return 0

        need("tmux", "yazi")
        catch_term()
        grounds = fixture.terminal_grounds(
            (fixture.FIXTURE / "init.lua").read_text()
        )
        if not grounds:
            refuse(
                "gallery: no ground in the comment above `GROUND` in "
                "test/fixture/init.lua -- a name and a backticked hex each"
            )

        found = read_approvals()
        ready = prepare(grounds, found, everything=argv == ["--all"])
        if not ready.shown:
            print(
                f"gallery: all {len(ready.digests)} steps are approved as "
                "drawn, so there is nothing to judge -- --all shows them anyway"
            )
            return 0
        print(
            f"gallery: {len(ready.shown)} of {len(ready.digests)} steps shown"
        )
        try:
            serve(
                ready.body,
                ready.shown,
                {name for name, _ in grounds},
                VERDICTS,
                Approvals(APPROVED, found, ready.digests),
            )
        finally:
            # On a SIGTERM as well, which `catch_term` turns into an exit.
            print_verdicts(VERDICTS, "gallery")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
