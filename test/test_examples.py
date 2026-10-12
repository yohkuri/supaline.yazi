"""The pictures in `docs/examples/`, against the blocks above them.

`examples.py` needs a real Yazi to draw a picture and none to read what one
says it was drawn from, so that is checked here, in CI: a configuration edited
without its picture being redrawn fails here rather than being published
beside a picture of something else.

    python3 -m unittest discover -s test -p 'test_*.py'
"""

from __future__ import annotations

import re
import tempfile
import unittest
from pathlib import Path

import examples
import screen as sc
from gallery import Scheme

INIT = "```lua\n-- ~/.config/yazi/init.lua\nrequire('supaline'):setup {}\n```\n"
THEME = '```toml\n# ~/.config/yazi/theme.toml\n[supaline]\nsize = "red"\n```\n'
IMAGE = "![A picture](images/a-picture.svg)\n"

#: Any reference to a picture, an image line's or a linked one's.
SHOWN = re.compile(r"\]\((images/[^)]+\.svg)\)")


class ThePages(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.pages = sorted(examples.PAGES.glob("*.md"))
        cls.found = examples.gathered(cls.pages)
        cls.drawn = {example.image for example in cls.found}

    def test_every_picture_was_drawn_from_the_blocks_above_it(self):
        # Guarded, so pages whose image lines stopped matching are not a
        # sweep over nothing.
        self.assertTrue(self.found, "no picture found in docs/examples/")
        for example in self.found:
            with self.subTest(example.image):
                path = examples.PAGES / example.image
                self.assertTrue(
                    path.exists(), f"{example.image}: run test/examples.py"
                )
                self.assertEqual(
                    examples.drawn_from(path.read_text()),
                    example.digest,
                    f"{example.image} was drawn from other blocks than the "
                    "ones above it: run test/examples.py",
                )

    def test_every_picture_on_disk_is_on_a_page(self):
        # A picture whose image line was removed or renamed is otherwise kept
        # and published, a picture of nothing on any page.
        for path in (examples.PAGES / "images").glob("*.svg"):
            with self.subTest(path.name):
                self.assertIn(f"images/{path.name}", self.drawn)

    def test_every_picture_shown_is_drawn_by_an_example(self):
        # The index shows pictures as links to the example under them, which
        # are not image lines: nothing else would notice one naming a file
        # no example draws.
        for page in self.pages:
            for shown in SHOWN.findall(page.read_text()):
                with self.subTest(page=page.name, image=shown):
                    self.assertIn(shown, self.drawn)


class Reading(unittest.TestCase):
    def test_a_picture_takes_the_blocks_above_it(self):
        [found] = examples.examples(INIT + THEME + IMAGE)
        self.assertEqual(found.image, "images/a-picture.svg")
        self.assertEqual(found.alt, "A picture")
        self.assertIn("setup {}", found.init)
        self.assertIn('size = "red"', found.theme)

    def test_a_block_belongs_to_one_picture_only(self):
        [first, second] = examples.examples(INIT + THEME + IMAGE + INIT + IMAGE)
        self.assertNotEqual(first.theme, "")
        self.assertEqual(second.theme, "")

    def test_a_block_naming_no_file_is_prose(self):
        [found] = examples.examples("```lua\n{ 'size' }\n```\n" + INIT + IMAGE)
        self.assertNotIn("{ 'size' }", found.init)

    def test_a_picture_with_nothing_to_draw_is_refused(self):
        with self.assertRaisesRegex(ValueError, "no `-- ~/.config/yazi"):
            examples.examples(THEME + IMAGE)

    def test_one_picture_on_two_pages_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            pages = [Path(tmp) / "a.md", Path(tmp) / "b.md"]
            for page in pages:
                page.write_text(INIT + IMAGE)
            with self.assertRaisesRegex(ValueError, "b.md: .* by a.md"):
                examples.gathered(pages)

    def test_a_linked_picture_is_not_an_example(self):
        linked = "[![A picture](images/a-picture.svg)](page.md)\n"
        self.assertEqual(examples.examples(linked), [])

    def test_a_block_does_not_cross_a_heading(self):
        # Carried on, the theme would be drawn into the next section's
        # picture, and its digest would agree.
        with self.assertRaisesRegex(ValueError, "line 7: .* no picture"):
            examples.examples(THEME + "\n## Next\n" + INIT + IMAGE)

    def test_a_block_left_at_the_end_is_refused(self):
        with self.assertRaisesRegex(ValueError, "end of the page"):
            examples.examples(INIT + IMAGE + THEME)

    def test_every_ground_left_alone_is_refused(self):
        with self.assertRaisesRegex(ValueError, "no picture"):
            examples.examples(examples.EVERY + "\n## Next\n")

    def test_trailing_space_is_not_read(self):
        [found] = examples.examples(
            INIT + examples.EVERY + "  \n" + IMAGE.replace("\n", " \n")
        )
        self.assertTrue(found.every)

    def test_a_misspelled_ground_comment_is_refused(self):
        with self.assertRaisesRegex(ValueError, "the one way"):
            examples.examples(
                INIT + "<!-- drawn on every grounds -->\n" + IMAGE
            )

    def test_a_longer_fence_holds_a_shorter_one(self):
        quoted = "````md\n```lua\n-- ~/.config/yazi/init.lua\n```\n````\n"
        [found] = examples.examples(quoted + INIT + IMAGE)
        self.assertIn("setup {}", found.init)

    def test_a_theme_that_themes_icons_is_refused(self):
        icons = "```toml\n# ~/.config/yazi/theme.toml\n[icon]\ndirs = []\n```\n"
        with self.assertRaisesRegex(ValueError, "`\\[icon\\]`"):
            examples.examples(INIT + icons + IMAGE)

    def test_a_theme_that_does_not_parse_is_refused(self):
        broken = "```toml\n# ~/.config/yazi/theme.toml\n[supaline\n```\n"
        with self.assertRaisesRegex(ValueError, "does not parse"):
            examples.examples(INIT + broken + IMAGE)

    def test_two_blocks_for_one_file_are_refused(self):
        with self.assertRaisesRegex(ValueError, "a second"):
            examples.examples(INIT + INIT + IMAGE)

    def test_a_picture_is_a_pair_unless_it_asks_for_every_ground(self):
        every = examples.EVERY + "\n"
        [plain, asked, after] = examples.examples(
            INIT + IMAGE + INIT + every + IMAGE + INIT + IMAGE
        )
        self.assertFalse(plain.every)
        self.assertTrue(asked.every)
        # The comment is the next picture's alone.
        self.assertFalse(after.every)

    def test_the_digest_covers_the_grounds_asked_for(self):
        [pair] = examples.examples(INIT + IMAGE)
        [every] = examples.examples(INIT + examples.EVERY + "\n" + IMAGE)
        self.assertNotEqual(pair.digest, every.digest)

    def test_a_pair_is_two_of_the_grounds(self):
        grounds = [("black", "#000000")] + [
            (n, "#111111") for n in examples.PAIR
        ]
        [pair] = examples.examples(INIT + IMAGE)
        self.assertEqual(
            [name for name, _ in examples.drawn_on(pair, grounds)],
            list(examples.PAIR),
        )

    def test_the_digest_covers_the_alt_text(self):
        # The SVG carries it as its title.
        [plain] = examples.examples(INIT + IMAGE)
        [renamed] = examples.examples(INIT + IMAGE.replace("A picture", "B"))
        self.assertNotEqual(plain.digest, renamed.digest)

    def test_the_digest_covers_the_theme_too(self):
        [plain] = examples.examples(INIT + IMAGE)
        [themed] = examples.examples(INIT + THEME + IMAGE)
        self.assertNotEqual(plain.digest, themed.digest)


#: A ground and foreground, and sixteen named colours each its own.
PALETTE = Scheme(
    "#000000", "#ffffff", tuple(f"#0000{n:02x}" for n in range(16))
)


class Waiting(unittest.TestCase):
    def screen(self, entries: int) -> str:
        rows = [f" entry-{n}" for n in range(entries)]
        blank = [""] * (examples.HEIGHT - 2 - entries)
        return "\n".join(["header", *rows, *blank, "status"])

    def test_the_folder_is_listed_once_every_entry_has_a_row(self):
        self.assertTrue(examples.listed(self.screen(len(examples.FOLDER))))

    def test_a_folder_part_drawn_is_not_listed(self):
        self.assertFalse(examples.listed(self.screen(len(examples.FOLDER) - 1)))

    def test_the_folder_fits_the_window(self):
        # Past the window's rows less the header and the status bar, the
        # entries scrolled off are never drawn, and the wait never ends.
        self.assertLessEqual(len(examples.FOLDER), examples.HEIGHT - 2)


class Drawing(unittest.TestCase):
    def test_a_named_colour_is_the_palette_s(self):
        self.assertEqual(
            examples.colours(sc.Pen(fg="p4"), PALETTE), ("#000004", "#000000")
        )

    def test_reverse_swaps_the_ground_in_as_well(self):
        self.assertEqual(
            examples.colours(sc.Pen(reverse=True), PALETTE),
            ("#000000", "#ffffff"),
        )

    def test_a_private_use_glyph_is_refused(self):
        rows = [[("", sc.Pen())]]
        with self.assertRaisesRegex(ValueError, "U\\+F015"):
            examples.tile(rows, "black", PALETTE)

    def test_the_hover_caps_are_shapes(self):
        rows = [[("", sc.Pen(fg="p4")), ("a", sc.Pen())]]
        drawn = "\n".join(examples.tile(rows, "black", PALETTE))
        self.assertIn('<path d="M', drawn)
        self.assertNotIn("", drawn)


if __name__ == "__main__":
    unittest.main()
