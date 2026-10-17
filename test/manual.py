#!/usr/bin/env python3
"""Open the test fixture in a real, interactive Yazi, to look at yourself.

    test/manual.py          build the fixture and open it
    test/manual.py --clean  throw the fixture away and stop

The configuration and the fixture come from `test/setup.py`, which `e2e.py`
also uses, so what you see here is what the headless run asserts on. Your own
Yazi configuration is not touched, and its `[flavor]` is the one thing read
from it -- `carry_flavor` says why.

What you answer on the walk is printed when Yazi quits, because the next run
rebuilds the directory it was written in.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import setup as fixture
from harness import (
    ROOT,
    begin_verdicts,
    need,
    print_verdicts,
    yazi_data,
    yazi_env,
    yazi_log,
)

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
    # terminal. Without it the ramps come out above the text they are meant to
    # follow, which only shows up when somebody pipes this to a pager.
    sys.stdout.flush()
    done = subprocess.run(
        ["lua", str(ROOT / "test" / "ramp.lua"), *ramps], check=False
    )
    if done.returncode != 0:
        print(
            "  note: a ramp above could not be resolved -- "
            "the message says which"
        )


def your_config() -> Path:
    """Where your own Yazi reads its configuration from.

    The order 26.9.1's `yazi-fs/src/xdg.rs` resolves it in: `YAZI_CONFIG_HOME`,
    then `XDG_CONFIG_HOME`, each only when absolute, then `~/.config`.
    """
    for name, under in (("YAZI_CONFIG_HOME", ""), ("XDG_CONFIG_HOME", "yazi")):
        value = Path(os.environ.get(name, ""))
        if value.is_absolute():
            return value / under
    return Path.home() / ".config" / "yazi"


#: What 26.9.1's dark preset, `yazi-config/preset/theme-dark.toml`, colours
#: the file rows and the `permissions` column with, by table: the colours a
#: headless run draws them in.
PRESET_ROWS = {
    "filetype": """
[filetype]
rules = [
\t{ mime = "**/image/*", fg = "yellow" },
\t{ mime = "**/{audio,video}/*", fg = "magenta" },
\t{ mime = "**/application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}", fg = "red" },
\t{ mime = "**/application/{pdf,doc,rtf}", fg = "cyan" },
\t{ mime = "vfs/{absent,stale}", fg = "gray" },
\t{ url = "*", is = "orphan", bg = "red" },
\t{ url = "*", is = "exec", fg = "green" },
\t{ url = "*", is = "dummy", bg = "red" },
\t{ url = "*/", is = "dummy", bg = "red" },
\t{ url = "*/", fg = "blue" },
]
""",
    "status": """
[status]
perm_sep = { fg = "darkgray" }
perm_type = { fg = "green" }
perm_read = { fg = "yellow" }
perm_write = { fg = "red" }
perm_exec = { fg = "cyan" }
""",
}


def carry_flavor(target: Path) -> str:
    """Your own `[flavor]`, put under every theme the fixture can switch to,
    and the line the verdicts' header says it with.

    The fixture's themes carry no `[flavor]`, so Yazi draws what is around the
    file rows -- the walk's guide and the status bar under it among them --
    from its preset, which names its colours rather than spelling them: what
    they look like is the terminal's palette. Your own `[flavor]` is what your
    own Yazi draws that chrome with in the same terminal. The headless
    harnesses stay on the preset, so this is for the run a person looks at and
    no other.

    Only the chrome. A flavor colours the rows too, and a column with no style
    of its own is drawn in its row's colour (`docs/configuration.md`), so each
    theme also gets `PRESET_ROWS`. A theme's own tables are laid over its
    flavor's, and a `[filetype]`'s rules replace the flavor's whole, read off
    26.9.1's `yazi-config/src/lib.rs`, so the rows keep the colours they have
    headless.

    Every theme, because a `c` key copies one over `theme.toml` and a theme
    without the tables takes them away with it. A table a theme already has is
    left as it is, since a second one would be a parse error and Yazi would
    discard the whole file for it. Nothing else is carried: the `[supaline]`
    styles under it are the fixture's, and they are what the walk is about. A
    flavor named but not installed is left out, since one Yazi cannot read
    fails the whole theme, read off the same file.
    """
    source = your_config()
    try:
        flavor = tomllib.loads((source / "theme.toml").read_text()).get(
            "flavor", {}
        )
    except (OSError, tomllib.TOMLDecodeError):
        flavor = {}
    if not isinstance(flavor, dict):
        flavor = {}
    slots = {}
    for slot in ("dark", "light"):
        name = flavor.get(slot)
        if not isinstance(name, str) or not name:
            continue
        found = source / "flavors" / f"{name}.yazi"
        if not (found / "flavor.toml").is_file():
            print(
                f"  note: your {slot} flavor `{name}` is not in {found.parent}"
            )
            continue
        slots[slot] = name
        dest = target / "config" / "flavors" / found.name
        if not dest.exists():
            shutil.copytree(found, dest)
    if not slots:
        return "flavor   none, Yazi's preset"

    tables = {
        "flavor": "\n[flavor]\n"
        + "".join(
            f"{slot} = {fixture.toml_string(name)}\n"
            for slot, name in slots.items()
        ),
        **PRESET_ROWS,
    }
    for theme in (target / "themes").glob("*.toml"):
        has = tomllib.loads(theme.read_text())
        with theme.open("a") as out:
            out.write("".join(t for k, t in tables.items() if k not in has))
    fixture.put_theme(target, "default")
    return "flavor   " + ", ".join(f"{s} {n}" for s, n in slots.items())


def main(argv: list[str]) -> int:
    if argv[:1] == ["--clean"]:
        # `setup.py` owns the marker file and the "is this ours" guard, so it
        # owns the removal too.
        fixture.main(["--clean", str(DIR)])
        print(f"manual: removed {DIR}")
        return 0

    need("yazi")
    fixture.main([str(DIR)])
    flavor = carry_flavor(DIR)
    verdicts = DIR / fixture.VERDICTS
    # The terminal, which is the one thing a headless run never has and the
    # reason the walk exists.
    term = " ".join(
        os.environ.get(name, "")
        for name in ("TERM_PROGRAM", "TERM_PROGRAM_VERSION")
    ).strip()
    begin_verdicts(
        verdicts,
        "supaline manual walk: step, case, theme, verdict, and a note on a no",
        f"terminal {term or 'unknown'} (TERM={os.environ.get('TERM', '')})",
        flavor,
    )

    # Where to start and where the rest is written down, and no list of keys:
    # `MANUAL.md` is the one place that names them, and a second list printed
    # here would be the copy that falls behind. The log's path is printed rather
    # than described, because the half of a report that never reaches the
    # screen is the half a reader has to be told where to find.
    rule = "─" * 76
    print("supaline manual test")
    print(rule)
    print("  W n starts the walk through the cases only a real terminal can")
    print("  judge, one question each, asked in a guide above the status bar")
    print("  with what to look at. Why is in test/MANUAL.md, and so is every")
    print("  key; the guide's own are on its last row.")
    print()
    print("  What a report says past its one sentence -- what the fault cost,")
    print("  and the whole of what was thrown -- goes to the log rather than")
    print("  to the screen. This run keeps one:")
    print(f"  {yazi_log(DIR, 'state')}")
    print("  And the walk's verdicts go to:")
    print(f"  {verdicts}")
    print(rule)

    print_ramps(DIR)

    print("Press Enter to open Yazi... ", end="", flush=True)
    try:
        # Tolerate a closed stdin, so this can be driven by something else.
        input()
    except EOFError:
        print()

    # The environment is `harness.yazi_env` and the folder is `yazi_data`,
    # which say why each is what it is. Here rather than written out, so what
    # a person opens and what `e2e.py` asserts on are the same Yazi, but for
    # the runtime directory `yazi_env` says it keeps for a person. A child
    # rather than an `execve`, so this is still here to print the verdicts once
    # Yazi has gone; and with no deadline, because a person is driving it.
    yazi = shutil.which("yazi")
    assert yazi is not None  # `need` above has already said so
    done = subprocess.run(
        [yazi, str(yazi_data(DIR))],
        env={**os.environ, **yazi_env(DIR, "state", headless=False)},
        check=False,
    )
    print_verdicts(verdicts, "manual")
    return done.returncode


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
