"""What `manual.py` carries over from your own configuration, held where CI
can see it.

`manual.py` is not in CI, and a flavor cut wrongly does not break loudly: the
rows it was meant to leave alone are coloured, or the chrome it was meant to
keep is gone, and Yazi starts either way.

    python3 -m unittest discover -s test -p 'test_*.py'
"""

from __future__ import annotations

import tomllib
import unittest

# First, because importing it is what refuses too old a Python.
import harness  # noqa: F401
import manual

#: A flavor in miniature: a table for the chrome on each side of the two that
#: colour the rows, one of them with a sub-table and a multi-line array.
FLAVOR = """\
# : Manager {{{
[mgr]
cwd = { fg = "#94e2d5" }

[filetype]
rules = [
	{ url = "*", fg = "#cdd6f4" },
]

[icon]
dirs = [ { name = ".git", text = "x" } ]

[icon.extra]
size = 1

[status]
sep_left = { open = "", close = "" }
"""


class Flavor(unittest.TestCase):
    def test_a_flavor_keeps_its_chrome_and_loses_what_colours_the_rows(self):
        cut = manual.chrome_only(FLAVOR)
        self.assertIsNotNone(cut)
        self.assertEqual(
            tomllib.loads(cut or ""),
            {
                "mgr": {"cwd": {"fg": "#94e2d5"}},
                "status": {"sep_left": {"open": "", "close": ""}},
            },
        )

    def test_a_flavor_that_cannot_be_cut_cleanly_is_none(self):
        spoiled = {
            # A header this reads no name from, so the table is kept whole.
            "a quoted header": FLAVOR.replace("[filetype]", '["filetype"]'),
            "a flavor that does not parse": FLAVOR + "[mgr\n",
        }
        for reason, text in spoiled.items():
            with self.subTest(reason):
                self.assertIsNone(manual.chrome_only(text))


if __name__ == "__main__":
    unittest.main()
