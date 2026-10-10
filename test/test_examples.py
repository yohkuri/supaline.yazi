"""The pictures in `docs/examples.md`, against the blocks above them.

`examples.py` needs a real Yazi to draw a picture and none to read what one
says it was drawn from, so that is checked here, in CI: a configuration edited
without its picture being redrawn fails here rather than being published
beside a picture of something else.

    python3 -m unittest discover -s test -p 'test_*.py'
"""

from __future__ import annotations

import unittest

import examples
import screen as sc
from gallery import Scheme

INIT = "```lua\n-- ~/.config/yazi/init.lua\nrequire('supaline'):setup {}\n```\n"
THEME = '```toml\n# ~/.config/yazi/theme.toml\n[supaline]\nsize = "red"\n```\n'
IMAGE = "![A picture](examples/a-picture.svg)\n"


class ThePage(unittest.TestCase):
    def test_every_picture_was_drawn_from_the_blocks_above_it(self):
        found = examples.examples(examples.EXAMPLES.read_text())
        # Guarded, so a page whose image lines stopped matching is not a
        # sweep over nothing.
        self.assertTrue(found, "no picture found in docs/examples.md")
        for example in found:
            with self.subTest(example.image):
                path = examples.EXAMPLES.parent / example.image
                self.assertTrue(
                    path.exists(), f"{example.image}: run test/examples.py"
                )
                self.assertEqual(
                    examples.drawn_from(path.read_text()),
                    example.digest,
                    f"{example.image} was drawn from other blocks than the "
                    "ones above it: run test/examples.py",
                )


class Reading(unittest.TestCase):
    def test_a_picture_takes_the_blocks_above_it(self):
        [found] = examples.examples(INIT + THEME + IMAGE)
        self.assertEqual(found.image, "examples/a-picture.svg")
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

    def test_the_digest_covers_the_theme_too(self):
        [plain] = examples.examples(INIT + IMAGE)
        [themed] = examples.examples(INIT + THEME + IMAGE)
        self.assertNotEqual(plain.digest, themed.digest)


#: A ground and foreground, and sixteen named colours each its own.
PALETTE = Scheme(
    "#000000", "#ffffff", tuple(f"#0000{n:02x}" for n in range(16))
)


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
