"""The gallery's page, against cells and verdicts written here.

`gallery.py` needs a real Yazi to take its captures, and none to draw them, to
read back what the page posts or to keep a second run off the first one's
directory, so those are checked here, in CI.
Whether the page looks like the terminal it stands in for is a person's call,
which is the point of it.

    python3 -m unittest discover -s test -p 'test_*.py'
"""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import gallery
import screen as sc
import setup as fixture
from test_screen import capture, row

#: Two steps of the walk, numbered as the walk numbers them.
SHOWN = {
    3: fixture.Step("c_ramp", "default", "can you tell rows apart?", True),
    11: fixture.Step("c_theme", "bg", "size & owner on <grounds>?", True),
}
NAMES = {"black", "Solarized light"}


def posted(**said: object) -> bytes:
    return json.dumps(said).encode()


class Styles(unittest.TestCase):
    def test_the_terminal_s_own_colours_need_no_style(self):
        self.assertEqual(gallery.css(sc.Pen()), "")

    def test_a_colour_is_a_hex_or_a_named_one_from_the_tile(self):
        self.assertEqual(
            gallery.css(sc.Pen(fg="#112233", bg="p4", bold=True)),
            "color:#112233;background:var(--p4);font-weight:bold",
        )

    def test_reverse_swaps_the_ground_in_as_well(self):
        # The hovered row: the terminal's foreground becomes the bar, and the
        # ground the text on it.
        self.assertEqual(
            gallery.css(sc.Pen(reverse=True)),
            "color:var(--bg);background:var(--fg)",
        )
        self.assertEqual(
            gallery.css(sc.Pen(fg="#112233", reverse=True)),
            "color:var(--bg);background:#112233",
        )

    def test_a_light_ground_is_read_in_black_and_a_dark_one_in_white(self):
        self.assertEqual(gallery.foreground("#fdf6e3"), "#000000")
        self.assertEqual(gallery.foreground("#282c34"), "#ffffff")


class Drawing(unittest.TestCase):
    def test_a_character_past_ascii_keeps_the_cells_a_terminal_gives_it(self):
        self.assertEqual(gallery.glyph("<"), "&lt;")
        self.assertEqual(gallery.glyph("日"), '<span class="w2">日</span>')
        self.assertEqual(gallery.glyph(""), '<span class="w1"></span>')

    def test_a_run_of_one_pen_is_one_span(self):
        rows = sc.current_cells(capture(row(current="\x1b[31mab\x1b[0mc")))
        self.assertEqual(
            gallery.drawn(rows), '<span style="color:var(--p1)">ab</span>c'
        )

    def test_the_page_carries_every_ground_and_every_question_escaped(self):
        body = gallery.page(
            ("commit x",),
            SHOWN,
            {3: "c r", 11: "c t"},
            {3: "three", 11: "eleven"},
            [("black", "#000000"), ("Solarized light", "#fdf6e3")],
        )
        self.assertEqual(body.count('<figure style="--bg:#000000'), 2)
        self.assertEqual(body.count('<figure style="--bg:#fdf6e3'), 2)
        # Each pane once, for the page to copy into every tile.
        self.assertEqual(body.count("three"), 1)
        self.assertIn("size &amp; owner on &lt;grounds&gt;?", body)
        self.assertIn('<section id="step-11" data-step="11">', body)


class Posted(unittest.TestCase):
    def test_a_yes_and_a_no_are_the_walk_s_fields_then_the_grounds(self):
        self.assertEqual(
            gallery.verdict_line(
                posted(step=3, said="yes", grounds=[]), SHOWN, NAMES
            ),
            "3\tc_ramp\tdefault\tyes\t",
        )
        self.assertEqual(
            gallery.verdict_line(
                posted(
                    step=11, said="no", grounds=["black", "Solarized light"]
                ),
                SHOWN,
                NAMES,
            ),
            "11\tc_theme\tbg\tno\tblack, Solarized light",
        )

    def test_anything_the_page_does_not_send_is_refused(self):
        spoiled = {
            "not json": b"nope",
            "not an object": b"[3]",
            "a step the gallery does not show": posted(
                step=4, said="yes", grounds=[]
            ),
            "a step that is not a number": posted(
                step="3", said="yes", grounds=[]
            ),
            "a verdict that is neither": posted(
                step=3, said="maybe", grounds=[]
            ),
            "a ground the gallery does not draw": posted(
                step=3, said="no", grounds=["mauve"]
            ),
            "a yes that names a ground": posted(
                step=3, said="yes", grounds=["black"]
            ),
        }
        for reason, body in spoiled.items():
            with self.subTest(reason), self.assertRaises(ValueError):
                gallery.verdict_line(body, SHOWN, NAMES)


class Lock(unittest.TestCase):
    def setUp(self):
        dir = tempfile.TemporaryDirectory()
        self.addCleanup(dir.cleanup)
        patched = mock.patch.object(gallery, "LOCK", Path(dir.name) / "lock")
        patched.start()
        self.addCleanup(patched.stop)

    def test_a_second_run_is_refused_while_the_first_holds_it(self):
        with gallery.hold_lock():
            with (
                self.assertRaises(SystemExit),
                contextlib.redirect_stderr(io.StringIO()) as said,
            ):
                gallery.hold_lock()
            self.assertIn("another gallery is running", said.getvalue())

    def test_a_run_that_has_ended_holds_nothing(self):
        with gallery.hold_lock():
            pass
        with gallery.hold_lock():
            pass


if __name__ == "__main__":
    unittest.main()
