"""The screen parsers, against captures written here rather than drawn.

`e2e.py` is not in CI -- it needs a real Yazi and a real terminal -- so until
this file the arithmetic that decides whether a ramp climbed was checked by
nothing at all. It was three `awk` programs then, and a parser that quietly
stopped matching would have reported every ramp as correct: `ramp_faults` over
no rows finds no faults, and the row count beside it was the only thing
standing between that and a green run.

These run anywhere Python does, so they *are* in CI. What they cannot say is
whether a capture like the ones below is what Yazi draws; `e2e.py` keeps that,
and the fixture's colours are read out of `test/fixture/` by both.

    python3 -m unittest discover -s test -p 'test_*.py'
"""

from __future__ import annotations

import unittest
from pathlib import Path

import e2e
import screen as sc


#: A row of a capture as tmux writes one: three panes, two dividers.
def row(parent: str = "", current: str = "", preview: str = "") -> str:
    return f"{parent}{sc.BAR}{current}{sc.BAR}{preview}"


def capture(*rows: str) -> str:
    """Rows 2 onward of a capture; row 1 is the header nothing here reads."""
    return "\n".join(["header", *rows])


def cell(colour: str, text: str, layer: int = 38) -> str:
    return sc.escaped(layer, colour) + text


class Colours(unittest.TestCase):
    def test_sgr_is_the_body_tmux_writes(self):
        self.assertEqual(sc.sgr(38, "#112233"), "38;2;17;34;51m")
        self.assertEqual(sc.sgr(48, "8b0045"), "48;2;139;0;69m")

    def test_escaped_opens_it(self):
        self.assertEqual(sc.escaped(38, "#000000"), "\x1b[38;2;0;0;0m")

    def test_rgb_is_the_triple_a_parsed_cell_carries(self):
        self.assertEqual(sc.rgb("#0b3d91"), "11;61;145")
        # And it agrees with `sgr` by construction, which is what lets a check
        # hold a cell this module parsed against a colour the fixture spells.
        self.assertEqual(sc.sgr(38, "#7fd4ff"), f"38;2;{sc.rgb('#7fd4ff')}m")


class Panes(unittest.TestCase):
    def setUp(self):
        self.shot = capture(row("par", "cur", "pre"), row("a", "b", "c"))

    def test_each_pane_is_its_own_field(self):
        self.assertEqual(sc.parent_of(self.shot)[:2], ["par", "a"])
        self.assertEqual(sc.current_of(self.shot)[:2], ["cur", "b"])
        self.assertEqual(sc.preview_of(self.shot)[:2], ["pre", "c"])

    def test_the_header_is_not_a_row(self):
        self.assertNotIn("header", sc.parent_of(self.shot))

    def test_a_row_with_no_divider_has_no_current_pane(self):
        self.assertEqual(sc.field_of("just a line"), "")
        # And a bare row answers itself for the parent, the way a `sed` that
        # found nothing to cut leaves the line alone.
        self.assertEqual(sc.parent_of(capture("bare"))[0], "bare")

    def test_a_divider_inside_a_column_would_move_the_split(self):
        # Why `c_scale` and `c_bold` draw U+250A instead. Pinned so the day
        # somebody writes the other glyph into a separator, this says what it
        # costs rather than a ramp check silently measuring half a row.
        self.assertEqual(sc.field_of(row("p", f"a{sc.BAR}b", "v")), "a")


class Ramps(unittest.TestCase):
    def climbing(self, count: int = 30) -> str:
        rows = []
        for i in range(count):
            colour = f"#{i:02x}{i:02x}{i:02x}"
            rows.append(
                row(
                    current=cell(colour, f" {i / 100:.2f}")
                    + " "
                    + cell(colour, "01/02  2020")
                )
            )
        return capture(*rows)

    def test_a_clean_ramp_has_no_faults(self):
        ramp = sc.ramp_rows(self.climbing())
        self.assertEqual(len(ramp), 30)
        self.assertEqual(sc.ramp_faults(ramp, monotone=True), [])

    def test_a_row_missing_its_date_is_not_read(self):
        # The pair is what the check is about, so half a row is no row. A
        # parser that took it would compare a cell against itself and pass.
        shot = capture(row(current=cell("#111111", " 0.50")))
        self.assertEqual(sc.ramp_rows(shot), [])

    def test_cells_in_different_colours_are_a_fault(self):
        shot = capture(
            row(
                current=cell("#111111", " 0.10")
                + cell("#222222", "01/02  2020")
            )
        )
        faults = sc.ramp_faults(sc.ramp_rows(shot), monotone=False)
        self.assertIn("different colours", faults[0])

    def test_a_repeated_colour_is_a_fault(self):
        one = row(
            current=cell("#111111", " 0.10") + cell("#111111", "01/02  2020")
        )
        faults = sc.ramp_faults(sc.ramp_rows(capture(one, one)), False)
        self.assertIn("same colour as the row above", faults[0])

    def test_a_channel_going_backwards_is_a_fault_only_when_asked(self):
        shot = capture(
            row(
                current=cell("#222222", " 0.10")
                + cell("#222222", "01/02  2020")
            ),
            row(
                current=cell("#111111", " 0.20")
                + cell("#111111", "01/02  2020")
            ),
        )
        ramp = sc.ramp_rows(shot)
        self.assertIn("goes backwards", " ".join(sc.ramp_faults(ramp, True)))
        # A ramp that turns in hue reverses a channel on most of its steps, so
        # this question is not put to one. `c_hue` is exactly that case.
        self.assertEqual(sc.ramp_faults(ramp, False), [])

    def test_a_ratio_going_backwards_is_always_a_fault(self):
        shot = capture(
            row(
                current=cell("#111111", " 0.90")
                + cell("#111111", "01/02  2020")
            ),
            row(
                current=cell("#222222", " 0.10")
                + cell("#222222", "01/02  2020")
            ),
        )
        faults = sc.ramp_faults(sc.ramp_rows(shot), monotone=False)
        self.assertIn("smaller ratio", " ".join(faults))

    def test_a_background_ramp_reads_one_cell_as_both(self):
        shot = capture(
            row(current=cell("#111111", " 0.10", layer=48)),
            row(current=cell("#222222", " 0.20", layer=48)),
        )
        ramp = sc.background_rows(shot)
        self.assertEqual(len(ramp), 2)
        self.assertEqual(ramp[0].ratio_colour, ramp[0].date_colour)
        self.assertEqual(sc.ramp_faults(ramp, monotone=True), [])

    def test_a_foreground_reader_does_not_see_a_background_ramp(self):
        shot = capture(row(current=cell("#111111", " 0.10", layer=48)))
        self.assertEqual(sc.ramp_rows(shot), [])


class Bands(unittest.TestCase):
    GROUND = "#8b0045"

    def test_a_full_width_band_is_neither_short_nor_doubled(self):
        opening = sc.escaped(48, self.GROUND)
        shot = capture(
            row(current=opening + "01/02  2020  " + "\x1b[0m"),
            row(current=opening + "03/04  2021  " + "\x1b[0m"),
        )
        got = sc.bands(shot, opening, want=13)
        self.assertEqual((got.drawn, got.lines, got.narrow), (2, 2, 0))

    def test_a_band_that_stopped_at_the_text_is_narrow(self):
        # The padding applied after the style rather than before it, which is
        # the bug a stated width exists to make visible.
        opening = sc.escaped(48, self.GROUND)
        shot = capture(row(current=opening + "01/02  2020" + "\x1b[0m"))
        self.assertEqual(sc.bands(shot, opening, want=13).narrow, 1)

    def test_two_bands_on_one_row_are_counted_apart_from_the_rows(self):
        opening = sc.escaped(48, self.GROUND)
        shot = capture(
            row(
                current=opening
                + "aaa"
                + "\x1b[0m"
                + opening
                + "bbb"
                + "\x1b[0m"
            )
        )
        got = sc.bands(shot, opening, want=3)
        self.assertEqual((got.drawn, got.lines), (2, 1))

    def test_a_band_runs_to_the_next_escape_of_any_kind(self):
        # Including the reset tmux writes before the divider. There is no
        # escape inside a band today, and one put there later reads here as a
        # band that came back short -- which is the sentence the check prints.
        opening = sc.escaped(48, self.GROUND)
        shot = capture(row(current=opening + "abc" + sc.ESC + "[0m"))
        self.assertEqual(sc.bands(shot, opening, want=3).narrow, 0)
        self.assertEqual(sc.bands(shot, opening, want=4).narrow, 1)


class Bold(unittest.TestCase):
    def pair(self, left_bold: bool, right_bold: bool, same: bool) -> str:
        left = sc.BOLD if left_bold else ""
        right = sc.BOLD if right_bold else ""
        return row(
            current=left
            + cell("#111111", " 0.10")
            + " "
            + right
            + cell("#111111" if same else "#222222", " 0.10")
        )

    def test_bold_on_the_left_of_one_colour_agrees(self):
        shot = capture(self.pair(True, False, same=True))
        self.assertEqual(sc.bold_pairs(shot), (1, 0))

    def test_bold_on_both_disagrees(self):
        shot = capture(self.pair(True, True, same=True))
        self.assertEqual(sc.bold_pairs(shot), (0, 1))

    def test_bold_on_neither_disagrees(self):
        shot = capture(self.pair(False, False, same=True))
        self.assertEqual(sc.bold_pairs(shot), (0, 1))

    def test_a_colour_that_moved_disagrees(self):
        shot = capture(self.pair(True, False, same=False))
        self.assertEqual(sc.bold_pairs(shot), (0, 1))

    def test_a_row_with_one_cell_is_not_a_pair(self):
        shot = capture(row(current=cell("#111111", " 0.10")))
        self.assertEqual(sc.bold_pairs(shot), (0, 0))


class Markers(unittest.TestCase):
    """One reader over any pane's rows, because m6 to m8 ask all three."""

    def test_a_preview_row_is_marked_when_it_ends_in_the_letter(self):
        shot = capture(row(preview=" inner-a.txt   d"), row(preview=" bare"))
        self.assertEqual(sc.marked(sc.preview_of(shot)), 1)

    def test_a_row_may_carry_a_glyph_after_the_marker(self):
        # The hovered row carries a powerline glyph and the others a space, so
        # anything but a letter or a digit may follow.
        shot = capture(
            row(current="name d "),
            row(current="name f"),
            row(current="name.txt"),
        )
        self.assertEqual(sc.marked(sc.current_of(shot)), 2)

    def test_the_parent_pane_is_read_by_that_same_reader(self):
        # The pane `pane_par` exists for, and the one that had no reader of
        # its own. Its rows end the way the current pane's do -- a trailing
        # space, or a powerline glyph on the hovered one -- which is why a
        # pattern anchored on the letter read all five of them as bare and
        # left the pane asserted on by nothing but "it changed".
        shot = capture(
            row(parent="sibling-one    d "),
            row(parent="data           d"),
            row(parent="untouched.txt"),
        )
        self.assertEqual(sc.marked(sc.parent_of(shot)), 2)

    def test_an_empty_pane_row_is_not_a_row(self):
        shot = capture(row(current="   "), row(current="a"), "no divider")
        self.assertEqual(sc.drawn(sc.current_of(shot)), 1)


class Scales(unittest.TestCase):
    """`c_scale` draws one size twice, log then linear, either side of U+250A."""

    def pair(self, log: str, linear: str, text: str = "8B") -> str:
        return row(
            "p",
            f"name {cell(log, text)}\x1b[39m{sc.DOTTED}{cell(linear, text)}",
            "v",
        )

    def test_the_cells_either_side_of_the_seam_are_read_as_a_pair(self):
        shot = capture(self.pair("#112233", "#445566"))
        (got,) = sc.scale_rows(shot)
        self.assertEqual(got.log_colour, "17;34;51")
        self.assertEqual(got.linear_colour, "68;85;102")
        self.assertEqual((got.log_text, got.linear_text), ("8B", "8B"))

    def test_a_row_with_no_seam_is_skipped(self):
        shot = capture(row("p", f"name {cell('#112233', '8B')}", "v"))
        self.assertEqual(sc.scale_rows(shot), [])

    def test_halves_that_drifted_apart_are_reported_rather_than_merged(self):
        (got,) = sc.scale_rows(capture(self.pair("#112233", "#112233")))
        self.assertEqual(got.log_text, got.linear_text)
        shot = capture(
            row(
                "p",
                f"name {cell('#112233', '8B')}\x1b[39m"
                f"{sc.DOTTED}{cell('#112233', '9B')}",
                "v",
            )
        )
        (drifted,) = sc.scale_rows(shot)
        self.assertNotEqual(drifted.log_text, drifted.linear_text)

    def test_the_cell_nearest_the_seam_is_the_log_one(self):
        # Two things at once, because one of them alone pins nothing. Yazi
        # colours its own file icon a few cells to the left, and it survives
        # only because no number follows it -- so the row carries a numeric
        # cell further left as well, which is what the fixture would grow if a
        # third scale were ever worth comparing. The log cell is the one
        # against the seam, and neither of those is it.
        shot = capture(
            row(
                "p",
                f"{cell('#ff0000', chr(0xE5FF))} name "
                f"{cell('#010203', '8B')} {cell('#112233', '8B')}"
                f"\x1b[39m{sc.DOTTED}{cell('#445566', '8B')}",
                "v",
            )
        )
        (got,) = sc.scale_rows(shot)
        self.assertEqual(got.log_colour, "17;34;51")
        self.assertEqual(got.linear_colour, "68;85;102")


class Edges(unittest.TestCase):
    """`c_edge` draws a size, a ratio and a date, all off one ratio."""

    def line(self, size_colour: str, rest: str, size: str = "3B") -> str:
        return row(
            "p",
            f"name {cell(size_colour, size)}\x1b[39m "
            f"{cell(rest, '1.00')}\x1b[39m {cell(rest, '12/25  2023')}",
            "v",
        )

    def test_the_three_cells_are_read_as_one_run(self):
        (got,) = sc.edge_rows(capture(self.line("#7fd4ff", "#7fd4ff")))
        self.assertEqual(got.size_colour, "127;212;255")
        self.assertEqual(got.ratio_colour, "127;212;255")
        self.assertEqual(got.date_colour, "127;212;255")
        self.assertEqual(got.size, "3B")

    def test_a_directory_keeps_its_own_colour_on_the_size_cell(self):
        # The rule the whole mode exists for: no value, so the low end, while
        # the ratio and the date beside it are still at the high one.
        (got,) = sc.edge_rows(
            capture(self.line("#0b3d91", "#7fd4ff", size="-"))
        )
        self.assertEqual(got.size_colour, "11;61;145")
        self.assertEqual(got.ratio_colour, "127;212;255")
        self.assertEqual(got.size, "-")

    def test_a_row_missing_one_of_the_three_is_skipped(self):
        # Not half-read: the claim is that one ratio reached three columns,
        # and a row that lost one has nothing to say about it.
        shot = capture(row("p", f"name {cell('#7fd4ff', '3B')}\x1b[39m ", "v"))
        self.assertEqual(sc.edge_rows(shot), [])

    def test_the_file_icon_is_not_the_size_cell(self):
        # The same trap as above, and the reason the run is matched whole: a
        # sweep for `38;2` alone would count Yazi's icon as a column.
        shot = capture(
            row(
                "p",
                f"{cell('#89e051', chr(0xF0219))} name "
                f"{cell('#7fd4ff', '3B')}\x1b[39m "
                f"{cell('#7fd4ff', '1.00')}\x1b[39m "
                f"{cell('#7fd4ff', '12/25  2023')}",
                "v",
            )
        )
        (got,) = sc.edge_rows(shot)
        self.assertEqual(got.size_colour, "127;212;255")


class Bolds(unittest.TestCase):
    """The two claims `c_bold` and `c_theme` make about where a bold landed."""

    #: A run `permissions` painted per character: each one opens a colour of
    #: its own, under a bold that reached them without replacing either.
    PAINTED = f"{sc.BOLD}\x1b[32mr\x1b[33mw"

    #: A date on a ramp step, with the spec's weight in front of the theme's
    #: colour -- the order tmux writes it in.
    DATED = f"{sc.BOLD}{cell('#7fd4ff', '12/25  2023')}"

    def test_a_bold_over_separately_coloured_characters_is_counted(self):
        shot = capture(row("p", f"name {self.PAINTED}", "v"))
        self.assertEqual(sc.bold_over_paint(shot), 1)

    def test_a_bold_that_took_the_colours_with_it_is_not(self):
        # One escape covering the whole run, which is what a cell that stepped
        # aside for the attribute draws. The bold is there either way, so this
        # is the half that discriminates.
        shot = capture(row("p", f"name {sc.BOLD}\x1b[32mrw", "v"))
        self.assertEqual(sc.bold_over_paint(shot), 0)

    def test_the_painted_run_without_its_bold_is_not(self):
        shot = capture(row("p", "name \x1b[32mr\x1b[33mw", "v"))
        self.assertEqual(sc.bold_over_paint(shot), 0)

    def test_neither_reader_leaves_the_current_pane(self):
        # Every other colour claim in the run is scoped to this pane, and these
        # two were the exception: read over the whole capture they are
        # satisfied by the parent pane, the header or the status line.
        painted = capture(row(self.PAINTED, "name", "v"))
        dated = capture(row(self.DATED, "name", "v"))
        self.assertEqual(sc.bold_over_paint(painted), 0)
        self.assertEqual(sc.bold_over_ramp(dated), 0)

    def test_a_bold_before_a_ramps_date_is_counted(self):
        shot = capture(row("p", f"name {self.DATED}", "v"))
        self.assertEqual(sc.bold_over_ramp(shot), 1)

    def test_a_bold_that_landed_after_the_colour_is_not(self):
        shot = capture(
            row("p", f"name {sc.escaped(38, '#7fd4ff')}{sc.BOLD}12/25", "v")
        )
        self.assertEqual(sc.bold_over_ramp(shot), 0)

    def test_the_ramps_date_without_its_bold_is_not(self):
        shot = capture(row("p", f"name {cell('#7fd4ff', '12/25')}", "v"))
        self.assertEqual(sc.bold_over_ramp(shot), 0)


class TheFixtureItReads(unittest.TestCase):
    """The colours `e2e.py` asserts on are the ones the fixture spells.

    Not a parser test. It is here because it is the one claim in this file that
    can go stale without anybody touching Python: recolour a ground in
    `init.lua` and `e2e.py` finds no band at all, which reads on the screen as
    a plugin that stopped drawing.

    It calls `e2e.py`'s own readers rather than re-spelling their patterns. A
    copy here would go on passing against the shape the fixture had when it
    was written while the reader beside it had quietly stopped matching, and
    `e2e.py` is not in CI, so nothing else would have said so.
    """

    HEX = r"^#[0-9a-fA-F]{6}$"

    @classmethod
    def setUpClass(cls):
        cls.init = (
            Path(__file__).resolve().parent / "fixture" / "init.lua"
        ).read_text()

    def test_both_grounds_are_flat_colours_the_fixture_binds(self):
        for name in ("GROUND", "LINE_GROUND"):
            with self.subTest(ground=name):
                self.assertRegex(e2e.ground_hex(self.init, name), self.HEX)

    def test_cool_is_the_two_ended_ramp_c_scale_and_c_edge_read(self):
        # `check_scale` and `check_edge` take both ends out of this line.
        # Written as one colour, or under another name, and each of them
        # refuses rather than measuring against an empty string.
        low, high = e2e.ramp_ends(self.init, "COOL")
        self.assertRegex(low, self.HEX)
        self.assertRegex(high, self.HEX)

    def test_the_columns_broken_on_purpose_are_found_by_name(self):
        # The third reader of that file, and the one whose empty answer is
        # quietest: a run that found no broken column presses no `b` key and
        # reads a log it expected to be empty, which is what a green run looks
        # like.
        self.assertTrue(e2e.broken_columns())


if __name__ == "__main__":
    unittest.main()
