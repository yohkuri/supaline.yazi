#!/usr/bin/env python3
"""The colour steps of the walk, drawn on seven terminal grounds at once.

    test/gallery.py          capture them, and serve the page to judge them on
    test/gallery.py --clean  throw the gallery away

The walk in `manual.py` asks its questions on one ground, the reader's own, and
a colour readable there may not be on the next reader's. So this takes the
walk's steps that say `gallery = true`, captures each the way `e2e.py` does,
and draws the current pane of every capture on each ground `init.lua` measures
`GROUND` against, side by side, under the step's question.

Only the ground is a terminal's. The default foreground is black on a light
ground and white on a dark one, the sixteen named colours are xterm's on every
tile, and the font, the bold and the width of a wide character are the
browser's -- which is why a step about any of those is the walk's alone.

The page is served by this process, on localhost, because a verdict given on it
is written to `verdicts.txt` beside it, under the same header as the walk's.
Ctrl-C stops it and prints them, since the next run rebuilds the directory they
are in.
"""

from __future__ import annotations

import html
import itertools
import json
import shutil
import sys
import tempfile
import unicodedata
import webbrowser
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import screen as sc
import setup as fixture
from e2e import Run
from harness import begin_verdicts, catch_term, need, print_verdicts, refuse

DIR = Path(tempfile.gettempdir()) / "supaline-gallery"

#: xterm's sixteen named colours, which every tile draws `p0` to `p15` in. A
#: palette per ground would be truer to each terminal, and would be seven
#: palettes to get right for what on these screens is Yazi's colour rather
#: than supaline's.
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

#: A gallery step with its number on the walk, which is what both files of
#: verdicts call it by.
Shown = tuple[int, fixture.Step]


def capture(r: Run, shown: list[Shown]) -> dict[int, str]:
    """Each step's colour capture, by its number, out of a Yazi per theme.

    A Yazi per theme rather than the theme's key, because a theme changes the
    colours alone and `settle` reads plain text, so it would return before the
    repaint as readily as after it. A Yazi opened on a theme draws in it from
    its first frame, which the first half of `e2e.py`'s theme check holds every
    run. The copy is the one `theme-key.py` makes, without the reload it
    emits to a Yazi that is not running yet.
    """
    shots: dict[int, str] = {}
    for theme in dict.fromkeys(step.theme for _, step in shown):
        shutil.copyfile(
            r.dir / "themes" / f"{theme}.toml", r.dir / "config" / "theme.toml"
        )
        r.open_yazi("state")
        for n, step in shown:
            if step.theme == theme:
                r.show(r.listing.cases[step.case])
                shots[n] = r.session.capture(colour=True)
        r.session.quit("q")
    return shots


def foreground(ground: str) -> str:
    """The default foreground on `ground`: black on a light one, white on a
    dark one, by the mean of its channels -- the seven are nowhere near the
    middle."""
    return "#000000" if sum(bytes.fromhex(ground[1:])) > 3 * 127 else "#ffffff"


def css(pen: sc.Pen) -> str:
    """A pen as an inline style, empty for the tile's own colours.

    The tile carries the ground and its foreground as `--bg` and `--fg`, and
    the named colours as `--p0` to `--p15`, so one rendering of a capture
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


def drawn(rows: list[list[tuple[str, sc.Pen]]]) -> str:
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
    header: list[str],
    shown: list[Shown],
    keys: dict[int, str],
    panes: dict[int, str],
    grounds: list[tuple[str, str]],
) -> str:
    """The whole page: the header the verdicts are under, then a section per
    step, its question and its buttons above a tile per ground."""
    palette = ";".join(f"--p{i}:{hex}" for i, hex in enumerate(XTERM))
    sections = []
    for n, step in shown:
        tiles = "".join(
            f'<figure style="--bg:{hex};--fg:{foreground(hex)}">'
            f'<figcaption><label><input type="checkbox" value="{html.escape(name)}">'
            f" {html.escape(name)} <code>{hex}</code></label></figcaption>"
            f"<pre>{panes[n]}</pre></figure>"
            for name, hex in grounds
        )
        sections.append(
            f'<section id="step-{n}" data-step="{n}">'
            f"<h2>step {n} · <code>{keys[n]}</code> · "
            f"{step.case} under {step.theme}</h2>"
            f'<p class="ask">{html.escape(step.ask)}</p>'
            '<p><button data-said="yes">looks right</button> '
            '<button data-said="no">looks wrong on the ticked</button> '
            '<span class="said"></span></p>'
            f'<div class="tiles">{tiles}</div></section>'
        )
    return PAGE.format(
        palette=palette,
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
:root {{ {palette}; }}
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
<p>Only the ground is a terminal's here. The default foreground is black or
white, the sixteen named colours are xterm's on every tile, and the font is the
browser's. Tick the grounds a step looks wrong on, then say so; answering a
step again replaces the answer.</p>
{sections}
<script>
for (const section of document.querySelectorAll("section[data-step]")) {{
  const said = section.querySelector(".said");
  for (const button of section.querySelectorAll("button")) {{
    button.addEventListener("click", async () => {{
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
      }}
    }});
  }}
}}
</script>
</body>
</html>
"""


def verdict_line(body: bytes, shown: list[Shown], names: set[str]) -> str:
    """The line a verdict the page posted is written as, or `ValueError`.

    The walk's four fields, then the grounds a `no` was given on. Refused
    rather than written when it is anything the page does not send, since
    `print_verdicts` trusts the file it reads.
    """
    said = json.loads(body)
    n = said.get("step") if isinstance(said, dict) else None
    step = dict(shown).get(n) if type(n) is int else None
    if step is None:
        raise ValueError("not a step the gallery shows")
    verdict, grounds = said.get("said"), said.get("grounds")
    if verdict not in ("yes", "no"):
        raise ValueError("a verdict is yes or no")
    if not isinstance(grounds, list) or not set(grounds) <= names:
        raise ValueError("not a list of the gallery's grounds")
    if verdict == "yes" and grounds:
        raise ValueError("a yes names no ground")
    return "\t".join(
        [str(n), step.case, step.theme, verdict, ", ".join(grounds)]
    )


def serve(
    body: str, shown: list[Shown], names: set[str], verdicts: Path
) -> None:
    """Serve the page, and write each verdict posted to it, until Ctrl-C."""

    class Handler(BaseHTTPRequestHandler):
        def reply(self, code: int, text: str, kind: str = "text/plain") -> None:
            sent = text.encode()
            self.send_response(code)
            self.send_header("Content-Type", f"{kind}; charset=utf-8")
            self.send_header("Content-Length", str(len(sent)))
            self.end_headers()
            self.wfile.write(sent)

        def do_GET(self) -> None:
            if self.path == "/":
                self.reply(200, body, "text/html")
            else:
                self.reply(404, "only / is here")

        def do_POST(self) -> None:
            if self.path != "/verdict":
                self.reply(404, "only /verdict takes a verdict")
                return
            length = int(self.headers.get("Content-Length", 0))
            try:
                line = verdict_line(self.rfile.read(length), shown, names)
            except ValueError as error:
                self.reply(400, str(error))
                return
            with verdicts.open("a") as file:
                file.write(line + "\n")
            self.reply(200, "recorded")

        def log_message(self, format: str, *args: object) -> None:
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    url = f"http://127.0.0.1:{server.server_port}/"
    print(f"gallery: {url} -- Ctrl-C when you are done")
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
    finally:
        server.server_close()


def main(argv: list[str]) -> int:
    if argv[:1] == ["--clean"]:
        # `setup.py` owns the marker file and the "is this ours" guard, so it
        # owns the removal too.
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

    r = Run(keep=True, dir=DIR)
    shown = [(n, step) for n, step in enumerate(r.steps, 1) if step.gallery]
    if not shown:
        refuse(
            "gallery: no step in test/fixture/walk.toml says `gallery = true`"
        )
    try:
        r.setup()
        shots = capture(r, shown)
    finally:
        r.session.kill()

    verdicts = DIR / fixture.VERDICTS
    begin_verdicts(
        verdicts,
        "supaline gallery: step, case, theme, verdict, grounds",
        "grounds  " + ", ".join(f"{name} {hex}" for name, hex in grounds),
    )
    header = [
        line.removeprefix("# ") for line in verdicts.read_text().splitlines()
    ]
    keys = {n: r.listing.cases[step.case].key for n, step in shown}
    panes = {n: drawn(sc.current_cells(shot)) for n, shot in shots.items()}
    body = page(header, shown, keys, panes, grounds)
    (DIR / "index.html").write_text(body)
    for n, shot in shots.items():
        (DIR / f"step-{n}.txt").write_text(shot)

    try:
        serve(body, shown, {name for name, _ in grounds}, verdicts)
    finally:
        # On a SIGTERM as well, which `catch_term` turns into an exit.
        print_verdicts(verdicts, "gallery")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
