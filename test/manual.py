#!/usr/bin/env python3
"""Open the test fixture in a real, interactive Yazi, to look at yourself.

    test/manual.py          build the fixture and open it
    test/manual.py --clean  throw the fixture away and stop

The configuration and the fixture come from `test/setup.py`, which `e2e.py`
also uses, so what you see here is what the headless run asserts on. Your own
Yazi configuration is not read and not touched.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import setup as fixture
from harness import ROOT, need, require_python, yazi_env

DIR = Path(tempfile.gettempdir()) / "supaline-manual"


def print_ramps(target: Path) -> None:
    """Every ramp whole, before Yazi takes the screen.

    A linemode can only show the steps some folder's values land on --
    `colour/ramp` is built to land on all of them and even there you scroll --
    so this is the only place all sixty-four sit side by side, and it is in the
    same terminal, on the same background, as the columns are about to be.

    `setup.py` lists what it wrote, so nothing here has to know how a ramp is
    spelled. A list built by reading this repository's source instead would go
    stale in one of two directions, both quiet: showing a ramp the fixture no
    longer draws, or leaving out one it does.
    """
    ramps = [
        line for line in (target / "ramps.txt").read_text().splitlines() if line
    ]
    if not ramps:
        print("  note: the fixture wrote no ramp, so there is none to print")
        return
    if shutil.which("lua") is None:
        print("  note: lua is not on PATH, so the ramps are not printed here")
        print("        run test/ramp.lua yourself to see them")
        return
    # Flushed first, because `ramp.lua` writes straight to the same descriptor
    # and this script's own `print` is block-buffered whenever stdout is not a
    # terminal. Without it the ramps come out above the banner they are meant
    # to follow, which only shows up when somebody pipes this to a pager.
    sys.stdout.flush()
    done = subprocess.run(
        ["lua", str(ROOT / "test" / "ramp.lua"), *ramps], check=False
    )
    if done.returncode != 0:
        print(
            "  note: a ramp above could not be resolved -- "
            "the message says which"
        )


def main(argv: list[str]) -> int:
    require_python()

    if argv[:1] == ["--clean"]:
        # `setup.py` owns the marker file and the "is this ours" guard, so it
        # owns the removal too.
        fixture.main(["--clean", str(DIR)])
        print(f"manual: removed {DIR}")
        return 0

    need("yazi")
    fixture.main([str(DIR)])

    print((ROOT / "test" / "fixture" / "banner.txt").read_text())

    # The log's path has to be filled in, so it cannot sit in the banner -- and
    # it is worth printing rather than describing, because the half of a report
    # that never reaches the screen is the half a reader has to be told where
    # to find.
    rule = "─" * 76
    print()
    print("  What a report says past its one sentence -- what the fault cost,")
    print("  and the traceback -- goes to the log rather than to the screen.")
    print("  This run keeps one:")
    print(f"  {DIR}/state/yazi/yazi.log")
    print(rule)

    print_ramps(DIR)

    print("Press Enter to open Yazi... ", end="", flush=True)
    try:
        # Tolerate a closed stdin, so this can be driven by something else.
        input()
    except EOFError:
        print()

    # The environment is `harness.yazi_env`, which says why each of the three
    # is set. Here rather than written out, so what a person opens and what
    # `e2e.py` asserts on are the same Yazi in that respect too.
    yazi = shutil.which("yazi")
    assert yazi is not None  # `need` above has already said so
    os.execve(
        yazi,
        [yazi, str(DIR / "fixture" / "data")],
        {**os.environ, **yazi_env(DIR, "state")},
    )
    # `execve` replaces this process, so nothing below it ever runs. The
    # `return` is here because a checker reading the function cannot know that.
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
