"""The screen parsers, against captures written here rather than drawn.

`e2e.py` is not in CI -- it needs a real Yazi and a real terminal -- and a
parser that quietly stopped matching would report every ramp as correct there:
`ramp_faults` over no rows finds no faults. These run anywhere Python does, so
they *are* in CI. What they cannot say is whether a capture like the ones below
is what Yazi draws; `e2e.py` keeps that.

    python3 -m unittest discover -s test -p 'test_*.py'
"""

from __future__ import annotations

import contextlib
import io
import re
import unittest

# First, because importing it is what refuses too old a Python, and `screen`
# cannot be read by one.
import harness  # noqa: F401
import screen as sc
import setup as fixture
from harness import Checks


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
        # The pane `pane_par` exists for. Its rows end the way the current
        # pane's do -- a trailing space, or a powerline glyph on the hovered
        # one -- so a pattern anchored on the letter would read them as bare.
        shot = capture(
            row(parent="sibling-one    d "),
            row(parent="data           d"),
            row(parent="untouched.txt"),
        )
        self.assertEqual(sc.marked(sc.parent_of(shot)), 2)

    def test_an_empty_pane_row_is_not_a_row(self):
        shot = capture(row(current="   "), row(current="a"), "no divider")
        self.assertEqual(sc.drawn(sc.current_of(shot)), 1)


class Signs(unittest.TestCase):
    """The sign `m h` hides, read at the end of a row like a marker."""

    def test_a_row_is_signed_when_it_ends_in_the_sign(self):
        # The hovered row carries a powerline glyph after it, the others a
        # space.
        shot = capture(
            row(current="huge.bin   87.9M @ "),
            row(current="tiny.txt      1B @"),
            row(current="nested         1"),
        )
        self.assertEqual(sc.signed(sc.current_of(shot), "@"), 2)

    def test_a_name_holding_the_glyph_is_not_a_sign(self):
        shot = capture(row(current="a @b.txt      1B"))
        self.assertEqual(sc.signed(sc.current_of(shot), "@"), 0)

    def test_the_glyph_is_matched_literally(self):
        # A sign is the fixture's to choose, and one that is a pattern's
        # metacharacter would otherwise match any row ending in anything.
        shot = capture(row(current="tiny.txt      1B x"))
        self.assertEqual(sc.signed(sc.current_of(shot), "."), 0)


class Owners(unittest.TestCase):
    """m2's three name columns, read off one row rather than grepped for."""

    def line(
        self,
        perm: str = "-rw-r--r--",
        owner: str = "me:mine",
        user: str = "me",
        group: str = "mine",
    ) -> str:
        # The padding is the fixture's: the three name columns are twelve,
        # eight and eight cells, and it is that padding rather than any width
        # arithmetic that delimits them.
        return row(
            " broken",
            f" name.txt   {perm} {owner:<12} {user:<8} {group:<8}"
            "      1B 09/19 22:55  ",
            " inner-a.txt",
        )

    def test_the_four_cells_come_off_one_row(self):
        (got,) = sc.owner_cells(capture(self.line()))
        self.assertEqual(got.permissions, "-rw-r--r--")
        self.assertEqual(
            (got.owner, got.user, got.group), ("me:mine", "me", "mine")
        )

    def test_a_directory_field_is_found_as_readily_as_a_file_one(self):
        # `[-dl]` then nine of `rwxsStT-`: the shape, not the value, because a
        # different umask draws a different field.
        rows = sc.owner_cells(capture(self.line(perm="drwxr-sr-t")))
        self.assertEqual([r.permissions for r in rows], ["drwxr-sr-t"])

    def test_a_cut_cell_is_read_whole_with_its_ellipsis(self):
        # The branch this machine happens not to run: whether the owner cell
        # fits depends on how long `$USER:$GROUP` is, so without this only one
        # of the two ever gets read anywhere.
        rows = sc.owner_cells(capture(self.line(owner="yohkuri:sta…")))
        self.assertEqual([r.owner for r in rows], ["yohkuri:sta…"])

    def test_a_row_with_no_permissions_field_is_skipped(self):
        shot = capture(row(current=" name.txt   1B 09/19 22:55"))
        self.assertEqual(sc.owner_cells(shot), [])

    def test_a_field_in_another_pane_is_not_read(self):
        # Yazi draws none there on 26.9.1.
        shot = capture(
            row(" -rw-r--r-- root:wheel   root     wheel   ", " name.txt", "v")
        )
        self.assertEqual(sc.owner_cells(shot), [])


class Cuts(unittest.TestCase):
    """What `check_owner` holds a cell against, once it has one."""

    def test_a_cell_that_fitted_is_a_cut_of_its_name(self):
        self.assertTrue(sc.is_cut_of("me:mine", "me:mine"))

    def test_a_cell_cut_with_an_ellipsis_is_too(self):
        self.assertTrue(sc.is_cut_of("yohkuri:staff", "yohkuri:sta…"))

    def test_a_different_name_is_not(self):
        self.assertFalse(sc.is_cut_of("yohkuri:staff", "root:wheel"))

    def test_it_says_nothing_about_the_ellipsis_being_there(self):
        # Which is why the check counts them as well: a column that cut
        # without marking the cut answers true here, and that is a fault.
        self.assertTrue(sc.is_cut_of("yohkuri:staff", "yohkuri:sta"))


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
        # Like every other colour claim in the run: read over the whole
        # capture they would be satisfied by the parent pane, the header or
        # the status line.
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
    a plugin that stopped drawing. It calls the readers `e2e.py` calls, rather
    than re-spelling their patterns.
    """

    HEX = rf"^{fixture.HEX}$"

    @classmethod
    def setUpClass(cls):
        cls.fixture = fixture.FIXTURE
        cls.init = (cls.fixture / "init.lua").read_text()

    def test_both_grounds_are_flat_colours_with_a_width_beside_them(self):
        # `check_bands` measures a band of this colour against this width.
        for name in ("GROUND", "LINE_GROUND"):
            with self.subTest(ground=name):
                (ground,) = fixture.binding(self.init, name)
                self.assertRegex(ground, self.HEX)
                self.assertGreater(fixture.band_width(self.init, name), 0)

    def test_cool_is_the_two_ended_ramp_c_scale_and_c_edge_read(self):
        low, high = fixture.binding(self.init, "COOL")
        self.assertRegex(low, self.HEX)
        self.assertRegex(high, self.HEX)

    def test_the_columns_broken_on_purpose_are_found_by_name(self):
        # The quietest empty answer: a run that found no broken column presses
        # no `b` key and reads a log it expected to be empty.
        self.assertTrue(fixture.broken_columns(self.init))

    def test_the_sign_toggle_hides_is_found_by_name(self):
        # `e2e.py` counts the rows carrying the sign, and an empty one is
        # carried by every row: the run would fail on the reader and read as
        # a `toggle` that hid nothing.
        self.assertTrue(fixture.sign(self.init))

    def test_the_theme_is_a_flat_colour_and_a_ramp_under_the_names_read(self):
        # `clean_run` rewrites the theme by replacing what this answers, and
        # the theme and ramp checks read the screen against it. Both themes,
        # because the swap to `alt` is read the same way.
        for name in ("default", "alt"):
            with self.subTest(theme=name):
                flat = fixture.theme_values(self.fixture, name)[0]
                for colour in (flat, *fixture.theme_ends(self.fixture, name)):
                    self.assertRegex(colour, self.HEX)

    def test_e2e_presses_every_case_the_list_holds(self):
        # `e2e.py` presses what this answers, so an empty one would press
        # nothing and pass; both runs have cases to press; and the case that
        # draws `b_tick` is read in `broken/`, whose `cd` throws its `refresh`
        # -- in the broken run alone, since nothing else goes there.
        listing = fixture.read_cases()
        self.assertTrue(listing.clean)
        self.assertTrue(listing.broken)
        ticks = [c for c in listing.cases.values() if c.linemode == "b_tick"]
        self.assertEqual(
            [(c.folder, c.broken) for c in ticks], [("broken", True)]
        )
        # The folders and the case `e2e.py` names outright.
        self.assertLessEqual({"data", "data/nested"}, listing.folders.keys())
        self.assertEqual(listing.cases["default"].folder, "data")
        self.assertIn("alt", listing.themes)

    def test_every_theme_file_is_a_theme_the_list_holds(self):
        # Both ways. A listed theme with no file is a key whose script fails
        # inside Yazi's `shell`, where nothing reads the error; a file with no
        # entry is a theme no key puts in place and no run draws.
        files = {path.stem for path in (self.fixture / "themes").glob("*.toml")}
        self.assertTrue(files)
        self.assertEqual(set(fixture.read_cases().themes), files)

    def test_the_manual_sends_each_case_to_the_folder_its_key_goes_to(self):
        # Nothing a run presses reads that column, so this is all that holds it
        # to `cases.toml`. Every `c` and `b` case has a row, because a key
        # dropped from the table is still spelled in the section under it, and
        # the key-set check in `fixture_spec.lua` passes on that alone.
        listing = fixture.read_cases()
        sent = fixture.goes_to(fixture.MANUAL.read_text())
        tabled = {
            case.key: case
            for case in listing.cases.values()
            if case.key.split(" ")[0] in ("c", "b")
        }
        self.assertTrue(tabled)
        self.assertEqual(set(sent), set(tabled))
        for key, folder_key in sent.items():
            with self.subTest(case=key):
                self.assertEqual(
                    listing.folders[tabled[key].folder].key, folder_key
                )

    def test_a_case_the_manual_sends_to_two_folders_is_refused(self):
        row = "| `c r` | a ramp | `g {}` |\n"
        self.assertEqual(fixture.goes_to(row.format(3)), {"c r": "g 3"})
        with self.assertRaises(ValueError):
            fixture.goes_to(row.format(3) + row.format(4))

    @staticmethod
    def one_case(
        path="a",
        folder_key="g 1",
        folder="a",
        theme="t",
        theme_key="c 1",
        case="one",
        extra="",
    ) -> str:
        """A `cases.toml` of one folder, one theme and one case, with a part
        swapped. `extra` lands in the case."""
        return (
            f'[[folder]]\npath = "{path}"\nkey = "{folder_key}"\n'
            'landmark = "x"\ndesc = "a"\n'
            f'[[theme]]\nname = "{theme}"\nkey = "{theme_key}"\ndesc = "t"\n'
            f'[[case]]\nid = "{case}"\nkey = "m 0"\nfolder = "{folder}"\n'
            f'linemode = "plain"\ndesc = "{case}"\n{extra}'
        )

    def test_the_list_of_one_case_is_read_whole(self):
        # The premise under the refusals below: the list they each spoil in
        # one place is one this reads.
        listing = fixture.cases(self.one_case(extra='hover = "x"\n'))
        self.assertEqual(listing.folders["a"].key, "g 1")
        self.assertEqual(listing.themes["t"], fixture.Theme("t", "c 1", "t"))
        self.assertEqual(
            listing.cases["one"],
            fixture.Case("one", "m 0", "a", "plain", "one", "x", False),
        )

    def test_a_list_spoiled_in_one_place_is_refused(self):
        spoiled = {
            "a case in a folder nobody lists": self.one_case(folder="b"),
            "a key two entries bind": self.one_case(folder_key="m 0"),
            "a key a theme and a case both bind": self.one_case(
                theme_key="m 0"
            ),
            # A misspelled `hover` read past would be a case that never moves it.
            "a field the list does not define": self.one_case(
                extra='hovre = "x"\n'
            ),
            # A folder's path goes into a keymap `run` unquoted.
            "a name that would need quoting": self.one_case(
                path="a b", folder="a b"
            ),
            # A theme's name goes into a `shell` template unquoted.
            "a theme name that would need quoting": self.one_case(theme="a b"),
            # A hover goes into the plugin's table as a Lua string, unescaped.
            "a hover that would need escaping": self.one_case(
                extra='hover = "a\\"b"\n'
            ),
            "a hover that is not a name in its folder": self.one_case(
                extra='hover = "a/b"\n'
            ),
            "a list with no case": self.one_case().split("[[case]]")[0],
            "a list with no theme": self.one_case().replace(
                '[[theme]]\nname = "t"\nkey = "c 1"\ndesc = "t"\n', ""
            ),
        }
        for reason, text in spoiled.items():
            with self.subTest(reason), self.assertRaises(ValueError):
                fixture.cases(text)

    def test_the_walk_the_fixture_offers_is_read(self):
        self.assertTrue(fixture.read_walk(fixture.read_cases()))

    #: A list of one folder, one theme, one working case and one broken one,
    #: which the walk below is read against.
    LISTED = one_case(theme="default", case="ok") + (
        '[[case]]\nid = "bad"\nkey = "b r"\nfolder = "a"\n'
        'linemode = "b_render"\ndesc = "bad"\nbroken = true\n'
    )

    @staticmethod
    def step(case="ok", ask="is it right?", extra="") -> str:
        """A `walk.toml` step, with a part swapped."""
        return f'[[step]]\ncase = "{case}"\nask = "{ask}"\n{extra}'

    def test_a_walk_of_two_steps_is_read_whole(self):
        # The premise under the refusals below.
        listing = fixture.cases(self.LISTED)
        steps = fixture.walk(
            self.step(extra="gallery = true\n") + self.step("bad"), listing
        )
        self.assertEqual(
            steps,
            [
                fixture.Step("ok", "default", "is it right?", True),
                fixture.Step("bad", "default", "is it right?", False),
            ],
        )

    def test_a_walk_spoiled_in_one_place_is_refused(self):
        listing = fixture.cases(self.LISTED)
        spoiled = {
            "a case the list does not hold": self.step("gone"),
            "a theme the list does not hold": self.step(
                extra='theme = "alt"\n'
            ),
            "a field the walk does not define": self.step(extra='them = "x"\n'),
            # Caught where it is read, not as a traceback where it is used.
            "a field that is not a string": self.step(
                extra='theme = ["alt"]\n'
            ),
            # Drawn in the status bar, cut off at its edge.
            "a question too long to draw": self.step(ask="x" * 51),
            # Written into a Lua string, unescaped.
            "a question that would need escaping": self.step(ask='a\\"b'),
            # The character `e2e.py` splits a line on to find the panes.
            "a question carrying a pane divider": self.step(ask="a │ b"),
            "a flag that is not a boolean": self.step(
                extra='gallery = "yes"\n'
            ),
            # Its report lands after the capture rather than in it.
            "a broken case in the gallery": self.step(
                "bad", extra="gallery = true\n"
            ),
            "a broken case shown twice": self.step("bad") * 2,
            # `gallery.py` keeps a yes by the two.
            "two gallery steps on one case and theme": self.step(
                extra="gallery = true\n"
            )
            * 2,
            "a working case after a broken one": self.step("bad") + self.step(),
            "no step at all": "",
        }
        for reason, text in spoiled.items():
            with self.subTest(reason), self.assertRaises(ValueError):
                fixture.walk(text, listing)

    def test_the_terminal_grounds_are_read_off_the_comment_above_ground(self):
        # The comment says seven, and the gallery draws a tile per ground.
        grounds = fixture.terminal_grounds(self.init)
        self.assertEqual(len(grounds), 7)
        self.assertIn(("Catppuccin Mocha", "#1e1e2e"), grounds)
        self.assertIn(("Solarized light", "#fdf6e3"), grounds)

    def test_a_ground_wrapped_over_two_comment_lines_keeps_its_name(self):
        init = (
            "-- the nearest of two terminal grounds -- black `#000000`, Gruvbox\n"
            "-- dark `#282828` -- and so on\n"
            'local GROUND = "#8b0045"\n'
        )
        self.assertEqual(
            fixture.terminal_grounds(init),
            [("black", "#000000"), ("Gruvbox dark", "#282828")],
        )

    def test_a_comment_rewritten_into_another_shape_answers_nothing(self):
        init = '-- black `#000000`\nlocal GROUND = "#8b0045"\n'
        self.assertEqual(fixture.terminal_grounds(init), [])

    def test_grounds_in_a_comment_above_anything_else_are_not_read(self):
        # The comment above `GROUND` is where they were measured; the same
        # words over another binding are not that list.
        init = (
            "-- two terminal grounds -- black `#000000` -- here\n"
            'local HUE = "#0b3d91"\n\nlocal GROUND = "#8b0045"\n'
        )
        self.assertEqual(fixture.terminal_grounds(init), [])

    def test_a_name_no_column_writes_under_a_bg_answers_zero(self):
        # `HUE` is bound and drawn, and nothing writes it under a `bg`.
        self.assertEqual(fixture.band_width(self.init, "HUE"), 0)

    def test_the_c_bg_block_is_found_and_names_both_grounds(self):
        # The sweep that catches a ground added to `c_bg` and read by nobody.
        grounds = fixture.c_bg_grounds(self.init)
        assert grounds is not None
        self.assertLessEqual({"GROUND", "LINE_GROUND"}, set(grounds))

    def test_a_file_with_no_c_bg_block_is_told_from_one_with_no_grounds(self):
        self.assertIsNone(fixture.c_bg_grounds('local GROUND = "#112233"\n'))

    def test_c_attrs_names_every_attribute_a_capture_is_read_for(self):
        # The other half of the chain `fixture_spec.lua` starts: that spec holds
        # the block to `style.lua`'s list, and this holds `DRAWN_AS` to the
        # block, so an attribute added to the plugin is one `e2e.py` reads.
        words = fixture.attribute_words(self.init)
        assert words is not None
        self.assertEqual(sorted(words), sorted(sc.DRAWN_AS))
        self.assertIsNone(
            fixture.attribute_words(self.init.replace("c_attrs", "c_x"))
        )

    def test_a_binding_is_one_colour_or_two_ends_and_nothing_else(self):
        init = 'local A = "#112233"\nlocal B = "#112233 -> #445566"\n'
        init += 'local C = "#112233 <->"\nlocal D = "#112233 -> #445566 -> #778899"\n'
        self.assertEqual(fixture.binding(init, "A"), ("#112233",))
        self.assertEqual(fixture.binding(init, "B"), ("#112233", "#445566"))
        self.assertEqual(fixture.binding(init, "C"), ())
        self.assertEqual(fixture.binding(init, "D"), ())


class Cells(unittest.TestCase):
    """`pens` and `current_cells`, which the gallery draws every tile from."""

    def test_each_parameter_tmux_writes_sets_the_pen_it_names(self):
        ((cell,),) = sc.pens("\x1b[1;3;4;7;31;48;2;17;34;51mx")
        self.assertEqual(
            cell,
            ("x", sc.Pen("p1", "#112233", True, True, True, True)),
        )

    def test_every_attribute_a_style_takes_reaches_a_pen(self):
        # What tmux writes for each of `style.lua`'s attributes, read off a
        # capture of `c_attrs` on 26.9.1: one parameter apiece, and 5 for both
        # blinks. A field `DRAWN_AS` names that no parameter sets would be an
        # attribute `e2e.py` asks for and could never find.
        line = "".join(f"\x1b[{p}m{p}\x1b[0m" for p in (1, 2, 3, 4, 5, 7, 8, 9))
        drawn = {
            name
            for _, pen in sc.pens(line)[0]
            for name, on in vars(pen).items()
            if on is True
        }
        self.assertEqual(drawn, set(sc.DRAWN_AS.values()))

    def test_one_parameter_takes_bold_and_dim_off_together(self):
        line = "\x1b[1;2ma\x1b[22mb\x1b[25;28;29mc"
        pens = [pen for _, pen in sc.pens(line)[0]]
        self.assertEqual(pens[0], sc.Pen(bold=True, dim=True))
        self.assertEqual(pens[1:], [sc.Pen(), sc.Pen()])

    def test_a_reset_and_a_default_colour_put_the_terminal_back(self):
        line = cell("#010203", "a") + "\x1b[39mb\x1b[1mc\x1b[0md"
        pens = [pen for _, pen in sc.pens(line)[0]]
        self.assertEqual(
            pens,
            [sc.Pen(fg="#010203"), sc.Pen(), sc.Pen(bold=True), sc.Pen()],
        )

    def test_a_bright_colour_and_an_index_are_named_or_fixed(self):
        line = "\x1b[90ma\x1b[103mb\x1b[38;5;16mc\x1b[38;5;231md\x1b[38;5;244me"
        self.assertEqual(
            [(pen.fg, pen.bg) for _, pen in sc.pens(line)[0]],
            [
                ("p8", ""),
                ("p8", "p11"),
                ("#000000", "p11"),
                ("#ffffff", "p11"),
                ("#808080", "p11"),
            ],
        )

    def test_the_pen_carries_into_the_next_line(self):
        _, second = sc.pens("\x1b[32ma\nb")
        self.assertEqual(second, [("b", sc.Pen(fg="p2"))])

    def test_what_this_cannot_draw_is_refused(self):
        for line in (
            "\x1b[53mx",
            "\x1b[38;2;1;2mx",
            "\x1b[4:3mx",
            "\x1b]0;t\x07",
        ):
            with self.subTest(line=line), self.assertRaises(ValueError):
                sc.pens(line)

    def test_the_current_pane_is_the_cells_between_the_dividers(self):
        text = capture(
            row("p", "\x1b[31mab\x1b[0m", "x"),
            row("q", "cd"),
            "status bar",
        )
        rows = sc.current_cells(text)
        self.assertEqual(
            [[ch for ch, _ in cells] for cells in rows],
            [["a", "b"], ["c", "d"]],
        )
        self.assertEqual(rows[0][0][1], sc.Pen(fg="p1"))

    def test_the_cells_of_a_pane_spell_the_field_plain_text_finds(self):
        # Two readings of one rule, `field_of` over plain text and this over
        # cells, held to the same answer on a row with and without colour.
        text = capture(
            row("p", cell("#112233", "ab") + "\x1b[39m c", "x"), row("q", "de")
        )
        plain = sc.OPEN + r"[0-9;]*m"
        self.assertEqual(
            [
                "".join(ch for ch, _ in cells)
                for cells in sc.current_cells(text)
            ],
            [
                field
                for field in sc.current_fields(re.sub(plain, "", text))
                if field
            ],
        )


def worded(text: str, words: list[str]) -> list[sc.WordRow]:
    return sc.word_pens(sc.current_cells(text), words)


class Words(unittest.TestCase):
    """`word_pens`, `misdrawn` and `leaked`, which `c_attrs` is read by."""

    def test_each_word_on_its_own_attribute_is_drawn_and_leaks_nothing(self):
        text = capture(
            row("p", "name \x1b[1mbold\x1b[0m \x1b[3mitalic\x1b[0m ", "x"),
            row(
                "q",
                "\x1b[7mname \x1b[1mbold\x1b[0;7m \x1b[3mitalic\x1b[0m\ue0b4",
                "y",
            ),
        )
        rows = worded(text, ["bold", "italic"])
        plain, hovered = rows
        self.assertEqual(plain.ground, sc.Pen())
        self.assertEqual(plain.words["bold"], {sc.Pen(bold=True)})
        self.assertEqual(plain.rest, {sc.Pen()})
        self.assertEqual(hovered.ground, sc.Pen(reverse=True))
        for word in ("bold", "italic"):
            with self.subTest(word=word):
                self.assertEqual(sc.misdrawn(rows, word), 0)
        # The hovered row's closing glyph is drawn outside the reverse, which
        # is a colour of the row's own and not a leak.
        self.assertEqual(sc.leaked(rows), 0)

    def test_a_reversed_word_on_the_hovered_row_is_the_row(self):
        text = capture(row("p", "\x1b[7mname reversed\x1b[0m", "x"))
        rows = worded(text, ["reversed"])
        self.assertEqual(sc.misdrawn(rows, "reversed"), 0)

    def test_an_attribute_left_on_is_refused_however_it_spreads(self):
        # Nothing taken off between columns: each word wears every attribute
        # before it, and so does the separator after it. Measured against the
        # cell beside it, every word here is that cell plus its own attribute
        # and passes; against the row's ground, only the first one does.
        words = ["bold", "dim", "italic", "hidden", "crossed"]
        drawn = "".join(
            f"\x1b[{p}m{word} " for p, word in zip((1, 2, 3, 8, 9), words)
        )
        rows = worded(capture(row("p", " " + drawn, "x")), words)
        self.assertEqual(
            [sc.misdrawn(rows, word) for word in words], [0, 1, 1, 1, 1]
        )
        self.assertEqual(sc.leaked(rows), 1)

    def test_a_leak_into_the_separator_alone_is_refused(self):
        # Taken off again before the next word, so every word reads right and
        # the separator is the only cell that says so.
        text = capture(row("p", " \x1b[1mbold \x1b[0;2mdim\x1b[0m", "x"))
        rows = worded(text, ["bold", "dim"])
        self.assertEqual(
            [sc.misdrawn(rows, w) for w in ("bold", "dim")], [0, 0]
        )
        self.assertEqual(sc.leaked(rows), 1)

    def test_a_leak_past_the_last_word_is_refused(self):
        # The last column has no word after it to inherit the leak, so only
        # the cells after it can say so.
        text = capture(row("p", " \x1b[1mbold\x1b[0m \x1b[9mcrossed   ", "x"))
        rows = worded(text, ["bold", "crossed"])
        self.assertEqual(sc.misdrawn(rows, "crossed"), 0)
        self.assertEqual(sc.leaked(rows), 1)

    def test_a_name_that_spells_a_word_is_not_read_as_its_column(self):
        text = capture(
            row(
                "p",
                " hidden-away.txt \x1b[1mbold\x1b[0m \x1b[8mhidden\x1b[0m",
                "x",
            )
        )
        (got,) = worded(text, ["bold", "hidden"])
        self.assertEqual(got.words["hidden"], {sc.Pen(hidden=True)})
        self.assertEqual(got.ground, sc.Pen())

    def test_a_word_is_matched_whole(self):
        # `blink` would otherwise be read out of `blink_rapid`, in its pen.
        text = capture(
            row("p", " \x1b[5;3mblink_rapid\x1b[0m \x1b[5mblink\x1b[0m", "x")
        )
        (got,) = worded(text, ["blink_rapid", "blink"])
        self.assertEqual(got.words["blink"], {sc.Pen(blink=True)})

    def test_a_row_missing_a_word_is_left_out(self):
        text = capture(row("p", " bold italic", "x"), row("q", " bold", "y"))
        self.assertEqual(len(worded(text, ["bold", "italic"])), 1)
        self.assertEqual(worded(text, ["dim"]), [])


class Sizes(unittest.TestCase):
    """`is_size` tells a size cell from a directory's, which `c_edge` needs.

    The two draw different ends of the ramp, so a cell sorted into the wrong
    half is compared against the wrong colour -- and `check_edge`'s guard that
    it saw some of each goes on passing while it does.
    """

    def test_a_size_carries_its_unit(self):
        for cell in ("1024B", "1.5K", "12.3M", "9G"):
            with self.subTest(cell=cell):
                self.assertTrue(sc.is_size(cell))

    def test_a_directory_count_is_a_bare_number(self):
        self.assertFalse(sc.is_size("2"))
        self.assertFalse(sc.is_size("64"))

    def test_a_cell_the_preview_has_not_read_yet_is_a_dash(self):
        self.assertFalse(sc.is_size("-"))

    def test_an_empty_cell_is_not_a_size(self):
        self.assertFalse(sc.is_size(""))

    def test_a_name_that_happens_to_end_in_a_letter_is_not_one(self):
        # `fullmatch` rather than a search: a size cell is the whole cell.
        self.assertFalse(sc.is_size("step-00.txt"))
        self.assertFalse(sc.is_size("1024B  "))


class Verdicts(unittest.TestCase):
    """`Checks.verdict`, which most of `e2e.py`'s claims go through."""

    def test_the_first_fault_that_holds_is_the_one_failed(self):
        k = Checks()
        empty: list[str] = []
        with (
            contextlib.redirect_stdout(io.StringIO()),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            held = k.verdict("fine", empty and f"{empty[0]}", "second", "third")
        self.assertEqual((k.failed, held), (["second"], False))

    def test_no_fault_passes_as_the_label(self):
        k = Checks()
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            held = k.verdict("fine", None, False, "")
        self.assertEqual(
            (k.failed, out.getvalue(), held), ([], "  fine\n", True)
        )


if __name__ == "__main__":
    unittest.main()
