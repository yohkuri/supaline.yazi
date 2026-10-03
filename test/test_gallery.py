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

#: The two grounds `NAMES` names, on their hexes.
GROUNDS = [("black", "#000000"), ("Solarized light", "#fdf6e3")]

#: A digest for each step of `SHOWN`.
DIGESTS = {3: "3" * 64, 11: "b" * 64}


def posted(**said: object) -> bytes:
    return json.dumps(said).encode()


def cells(current: str) -> list[list[sc.Cell]]:
    return sc.current_cells(capture(row(current=current)))


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
        rows = cells("\x1b[31mab\x1b[0mc")
        self.assertEqual(
            gallery.drawn(rows), '<span style="color:var(--p1)">ab</span>c'
        )

    def test_the_page_carries_every_ground_and_every_question_escaped(self):
        body = gallery.page(
            ("commit x",),
            SHOWN,
            {3: "c r", 11: "c t"},
            {3: "three", 11: "eleven"},
            GROUNDS,
        )
        # A tile per ground per step, each in its ground's scheme.
        self.assertEqual(body.count('<figure class="g0">'), 2)
        self.assertEqual(body.count('<figure class="g1">'), 2)
        self.assertIn(".g0 { --bg:#000000;--fg:#ffffff;--p0:#000000;", body)
        self.assertIn("--p4:#0000ee;", body)
        self.assertIn(".g1 { --bg:#fdf6e3;--fg:#657b83;--p0:#073642;", body)
        self.assertIn("--p4:#268bd2;", body)
        # Each pane once, for the page to copy into every tile.
        self.assertEqual(body.count("three"), 1)
        self.assertIn("size &amp; owner on &lt;grounds&gt;?", body)
        self.assertIn('<section id="step-11" data-step="11">', body)


class Schemes(unittest.TestCase):
    def test_every_scheme_is_a_ground_init_lua_names_on_the_same_hex(self):
        # Keyed by name, so a ground renamed in the comment would otherwise
        # fall back to xterm's colours without a word.
        grounds = dict(
            fixture.terminal_grounds((fixture.FIXTURE / "init.lua").read_text())
        )
        for name, scheme in gallery.SCHEMES.items():
            with self.subTest(name):
                self.assertEqual(grounds.get(name), scheme.ground)

    def test_every_scheme_names_sixteen_colours(self):
        for name, scheme in gallery.SCHEMES.items():
            with self.subTest(name):
                self.assertEqual(len(scheme.named), 16)
                for hex in (scheme.ground, scheme.fg, *scheme.named):
                    self.assertRegex(hex, r"^#[0-9a-f]{6}$")

    def test_a_ground_with_no_scheme_is_xterm_s_in_black_or_white(self):
        self.assertEqual(
            gallery.scheme("black", "#000000"),
            gallery.Scheme("#000000", "#ffffff", gallery.XTERM),
        )
        self.assertEqual(gallery.scheme("white", "#ffffff").fg, "#000000")


class Posted(unittest.TestCase):
    def test_a_yes_and_a_no_are_the_walk_s_fields_then_the_grounds(self):
        self.assertEqual(
            gallery.verdict(
                posted(step=3, said="yes", grounds=[]), SHOWN, NAMES
            ).line(),
            "3\tc_ramp\tdefault\tyes\t",
        )
        self.assertEqual(
            gallery.verdict(
                posted(
                    step=11, said="no", grounds=["black", "Solarized light"]
                ),
                SHOWN,
                NAMES,
            ).line(),
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
                gallery.verdict(body, SHOWN, NAMES)


class Approved(unittest.TestCase):
    def test_a_digest_moves_with_a_cell_a_pen_a_ground_or_the_question(self):
        drawn = cells("\x1b[31mab\x1b[0mc")
        said = gallery.digest(drawn, GROUNDS, "right?")
        self.assertRegex(said, gallery.DIGEST)
        # Pinned: a digest spelled any other way, of the same pane, takes back
        # every approval in `approved.toml` without a word.
        self.assertEqual(
            said,
            "210fb157b23e0890dc3e0fb2b2dc27180655aa370a0aeb83f8c264b42d073ec8",
        )
        self.assertEqual(gallery.digest(drawn, GROUNDS, "right?"), said)
        moved = {
            "a cell": (cells("\x1b[31mab\x1b[0md"), GROUNDS, "right?"),
            "a pen": (cells("\x1b[32mab\x1b[0mc"), GROUNDS, "right?"),
            "a ground": (drawn, GROUNDS[:1], "right?"),
            "the question": (drawn, GROUNDS, "wrong?"),
        }
        for reason, seen in moved.items():
            with self.subTest(reason):
                self.assertNotEqual(gallery.digest(*seen), said)

    def test_the_file_is_read_back_as_it_was_written(self):
        found = {("c_theme", "bg"): "b" * 64, ("c_ramp", "default"): "3" * 64}
        text = gallery.approvals_text(found)
        self.assertEqual(gallery.approvals(text), found)
        # A line per step, sorted, under the header.
        self.assertTrue(
            text.endswith(
                f'\nc_ramp.default = "{"3" * 64}"\nc_theme.bg = "{"b" * 64}"\n'
            )
        )
        self.assertEqual(gallery.approvals(gallery.approvals_text({})), {})

    def test_a_file_that_is_not_digests_by_case_and_theme_is_refused(self):
        spoiled = {
            "not toml": "c_ramp.default =",
            "a case with no theme": f'c_ramp = "{"3" * 64}"',
            "an empty case": "[c_ramp]",
            "a digest cut short": 'c_ramp.default = "333"',
            "a digest in capitals": f'c_ramp.default = "{"B" * 64}"',
            "a digest that is not a string": "c_ramp.default = 3",
        }
        for reason, text in spoiled.items():
            with self.subTest(reason), self.assertRaises(ValueError):
                gallery.approvals(text)

    def test_only_a_step_with_no_yes_on_its_digest_is_pending(self):
        found = {("c_ramp", "default"): "3" * 64, ("c_theme", "bg"): "a" * 64}
        self.assertEqual(
            gallery.pending(SHOWN, DIGESTS, found), {11: SHOWN[11]}
        )
        self.assertEqual(gallery.pending(SHOWN, DIGESTS, {}), SHOWN)

    def test_a_yes_writes_the_step_s_digest_and_a_no_takes_it_out(self):
        dir = tempfile.TemporaryDirectory()
        self.addCleanup(dir.cleanup)
        path = Path(dir.name) / "approved.toml"
        found = {("c_theme", "bg"): "a" * 64}
        approved = gallery.Approvals(path, found, DIGESTS)
        approved.record(
            gallery.verdict(
                posted(step=3, said="yes", grounds=[]), SHOWN, NAMES
            )
        )
        approved.record(
            gallery.verdict(
                posted(step=11, said="no", grounds=["black"]), SHOWN, NAMES
            )
        )
        self.assertEqual(
            gallery.read_approvals(path), {("c_ramp", "default"): "3" * 64}
        )
        # What the run was handed is left as it was.
        self.assertEqual(found, {("c_theme", "bg"): "a" * 64})

    def test_a_verdict_whose_write_failed_is_written_when_sent_again(self):
        dir = tempfile.TemporaryDirectory()
        self.addCleanup(dir.cleanup)
        path = Path(dir.name) / "approved.toml"
        path.write_text(
            gallery.approvals_text({("c_ramp", "default"): "3" * 64})
        )
        approved = gallery.Approvals(
            path, gallery.read_approvals(path), DIGESTS
        )
        no = gallery.verdict(
            posted(step=3, said="no", grounds=["black"]), SHOWN, NAMES
        )
        with (
            mock.patch.object(Path, "write_text", side_effect=PermissionError),
            self.assertRaises(PermissionError),
        ):
            approved.record(no)
        approved.record(no)
        self.assertEqual(gallery.read_approvals(path), {})

    def test_with_none_written_nothing_is_approved(self):
        with tempfile.TemporaryDirectory() as dir:
            path = Path(dir) / "approved.toml"
            self.assertEqual(gallery.read_approvals(path), {})

    def test_every_approval_tracked_names_a_gallery_step(self):
        # A step taken out of the gallery, or moved to another case or theme,
        # would leave a line nothing reads, approving a pane nobody draws.
        steps = fixture.read_walk(fixture.read_cases())
        keys = {(step.case, step.theme) for step in steps if step.gallery}
        for key in gallery.read_approvals():
            with self.subTest(key):
                self.assertIn(
                    key,
                    keys,
                    "names no gallery step: delete its line from "
                    "test/approved.toml -- taking one out claims nothing",
                )

    def test_an_approved_step_says_so_on_the_page(self):
        body = gallery.page(
            ("commit x",),
            SHOWN,
            {3: "c r", 11: "c t"},
            {3: "three", 11: "eleven"},
            GROUNDS,
            {3},
        )
        self.assertEqual(body.count(" · approved</h2>"), 1)
        self.assertIn("c_ramp under default · approved</h2>", body)


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
