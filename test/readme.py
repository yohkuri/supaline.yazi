#!/usr/bin/env python3
"""Open the Yazi the README's picture is taken from, in this terminal.

    test/readme.py  build the folder, wait for the window, and open it

The configuration is the README's own: the blocks under `Recommended setup`,
each naming its file on its first line the way the pages in `docs/examples/`
spell them, written out as they stand. The folder is built here, under a
scratch home that Yazi is given as `HOME`, so its header reads
`~/work/project` and nothing of your own configuration reaches it -- Yazi's
or git's. supaline is this checkout; every other plugin its `init.lua`
requires, and every flavor its `theme.toml` names, is linked from where
`ya pkg add` put yours. A plugin named only in `yazi.toml` or `keymap.toml`
is not found that way, and Yazi would run without it.

Nothing here sets the terminal up, since nothing could for every terminal:
take the picture on the flavor's background, `#1e1e2e` for Catppuccin Mocha,
with a Nerd Font, and at a font size that gives the picture its resolution --
the PNG in `docs/images/` is 1967 pixels wide. This waits for the window to
reach the width the README says the picture is, and the height that holds the
folder, then opens Yazi with `assets` hovered. Take the screenshot, quit,
and the scratch home is removed.

Not in CI, for the reason `e2e.py` is not, and not checked against the PNG:
retake the picture when what the setup draws changes.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import time
import tomllib
from datetime import datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

# First, because importing it is what refuses too old a Python.
import harness  # noqa: F401
import setup as fixture
from examples import (
    FILES,
    GIT_ENV,
    INIT,
    PLUGINS,
    THEME,
    file_block,
    git,
    installed,
    repository,
    required,
    toml_problem,
)
from examples import configure as examples_configure
from harness import (
    ROOT,
    catch_term,
    need,
    refuse,
    troubles,
    yazi_env,
    yazi_log,
    yazi_version,
)

README = ROOT / "README.md"
SECTION = "## Recommended setup"
#: A heading that ends the section: one at its own level or above, so a
#: `###` inside it does not cut its blocks off.
ENDS = re.compile(r"^#{1,2}\s")

#: The width the section says the picture is.
COLS = 140

#: The scratch home, named after the run, so a second run started while one
#: is open builds its own rather than clearing the first one's.
DIR = Path(tempfile.gettempdir()) / f"supaline-readme.{os.getpid()}"

#: Where a flavor the setup names is linked from: where `ya pkg add` puts it,
#: beside the plugins `examples.installed` links.
FLAVORS = PLUGINS.parent / "flavors"

HOUR = 3600
DAY = 24 * HOUR

#: The folder's files: path under the project, size in bytes, and age in
#: seconds. The ages run from minutes to over a year, so each gradient spans
#: its whole range, and `assets` -- the entry Yazi hovers first -- holds sizes
#: and ages as far apart as the list's, for the preview pane to show them too.
#: Sparse, as `setup.sized` says why. The ages count back from `TAKEN` rather
#: than from now: `mtime` draws a date of this year with its time of day and
#: an older one with its year, so counted from now, a picture retaken in
#: February would show years where the PNG shows times.
FILES_BY_AGE = [
    ("assets/hero.png", 1_468_006, 2 * HOUR),
    ("assets/logo.svg", 6_349, 3 * DAY),
    ("assets/intro.mp4", 39_845_888, 21 * DAY),
    ("assets/favicon.ico", 15_086, 64 * DAY),
    ("assets/font.woff2", 98_304, 150 * DAY),
    ("docs/guide.md", 8_192, 5 * DAY),
    ("docs/api.md", 14_336, 9 * DAY),
    ("src/main.rs", 3_072, 1 * HOUR),
    ("src/lib.rs", 12_288, 30 * HOUR),
    ("backup.tar.gz", 48_024_780, 105 * DAY),
    ("CHANGELOG.md", 2_150, 20 * 60),
    ("cover.png", 2_097_152, 29 * DAY),
    ("demo.mp4", 180_040_499, 52 * DAY),
    ("holiday-photo.jpg", 3_355_443, 9 * DAY),
    ("install.sh", 3_174, 216 * DAY),
    ("LICENSE", 1_067, 400 * DAY),
    ("notes.md", 6_144, 40 * 60),
    ("README.md", 11_980, 4 * HOUR),
    ("report.pdf", 860_160, 87 * DAY),
]

#: The moment the ages count back from, as `MMDDhhmm` of this year: when the
#: PNG was taken.
TAKEN = "10131319"

#: The executables, so `permissions` has an `x` to draw.
EXECUTABLE = {"install.sh"}

#: The project's siblings, for the parent pane's dots, with their ages.
SIBLINGS = {"dotfiles": 2 * DAY, "scratch": 300 * DAY, "website": 33 * DAY}

#: The window's height: a row for each of the project's entries, with the
#: header and the status bar, so none of them scrolls off the picture.
ROWS = len({name.split("/")[0] for name, _, _ in FILES_BY_AGE}) + 2

#: The entry git says each state of, for those not committed and clean, so
#: git.yazi has a sign to draw for each one it has.
GIT = {
    "added": "CHANGELOG.md",
    "staged": "README.md",
    "unstaged": "notes.md",
    "untracked": "report.pdf",
    "ignored": "backup.tar.gz",
}


def setup_blocks(text: str) -> dict[str, str]:
    """The blocks under `SECTION` in the README, by the file each names.

    Refused when the section is missing, lacks a block for any of `FILES` --
    one whose first line is misspelled is read as prose, and the setup would
    open without it -- or holds two blocks for one file, since which of them
    is the setup would be a guess; and when `examples.toml_problem` refuses
    a `.toml` block, saying why.
    """
    lines = text.splitlines()
    try:
        i = lines.index(SECTION) + 1
    except ValueError:
        raise ValueError(f"no `{SECTION}` heading") from None
    blocks: dict[str, str] = {}
    while i < len(lines) and not ENDS.match(lines[i]):
        found = file_block(lines, i)
        if not found:
            i += 1
            continue
        end, name, block = found
        if name:
            if name in blocks:
                raise ValueError(f"line {i + 1}: a second `{name}` block")
            if name != INIT and (problem := toml_problem(block, i + 2)):
                raise ValueError(f"line {i + 1}: the block {problem}")
            blocks[name] = block
        i = end + 1
    if missing := [name for name in FILES if name not in blocks]:
        named = ", ".join(f"`{name}`" for name in missing)
        raise ValueError(f"no {named} block under `{SECTION}`")
    return blocks


def flavors(theme: str) -> set[str]:
    """The flavors a `theme.toml` block names, in either slot."""
    named = tomllib.loads(theme).get("flavor", {})
    if isinstance(named, dict):
        return {n for n in named.values() if isinstance(n, str) and n}
    raise ValueError("`flavor` in the `theme.toml` block is not a table")


def flavor(name: str) -> Path:
    """Where `ya pkg add` puts the flavor `name`."""
    return FLAVORS / f"{name}.yazi"


def configure(
    home: Path, blocks: dict[str, str], plugins: set[str], named: set[str]
) -> None:
    """The setup's files under `home/config`, with the plugins linked as
    `examples.configure` links them, and the `named` flavors from yours."""
    examples_configure(home, plugins)
    config = home / "config"
    (config / "flavors").mkdir()
    for header, block in blocks.items():
        (config / header.split("/")[-1]).write_text(block)
    for name in named:
        (config / "flavors" / f"{name}.yazi").symlink_to(flavor(name))


def stamp(path: Path, age: int, now: datetime) -> None:
    """Date `path` `age` seconds back on the wall clock, plus a few minutes
    taken from its name, so the ages above do not all print the same minute.
    The wall clock, so a clock change between the two dates moves nothing
    `mtime` draws."""
    age += sum(path.name.encode()) % 47 * 60
    fixture.stamp(path, (now - timedelta(seconds=age)).timestamp())


def build_folder(home: Path) -> Path:
    """The folder the picture is of, under `home`, as a repository holding
    `GIT`'s states. Built under the umask `setup.build` states, so
    `permissions` draws the same modes whoever retakes the picture."""
    work = home / "work"
    folder = work / "project"
    was = os.umask(0o022)
    try:
        for name in SIBLINGS:
            (work / name).mkdir(parents=True)
            (work / name / "README.md").write_text(f"# {name}\n")
        for name, size, _ in FILES_BY_AGE:
            path = folder / name
            path.parent.mkdir(parents=True, exist_ok=True)
            fixture.sized(path, size)
            if name in EXECUTABLE:
                path.chmod(0o755)
        repository(folder, GIT)
    finally:
        os.umask(was)

    # After everything is created, because creating an entry moves its
    # directory's mtime: the deepest first, for the same reason. A directory,
    # the project included, takes the age of its newest entry, and the
    # minutes `stamp` adds from its own name.
    # Naive on purpose: the arithmetic in `stamp` is on the wall clock.
    taken = f"{time.localtime().tm_year}{TAKEN}"
    now = datetime.strptime(taken, "%Y%m%d%H%M")  # noqa: DTZ007
    newest: dict[Path, int] = {}
    for name, _, age in FILES_BY_AGE:
        stamp(folder / name, age, now)
        for parent in (folder / name).parents:
            if parent == folder.parent:
                break
            newest[parent] = min(newest.get(parent, age), age)
    for path in sorted(newest, key=lambda path: -len(path.parts)):
        stamp(path, newest[path], now)
    for name, age in SIBLINGS.items():
        stamp(work / name / "README.md", age, now)
        stamp(work / name, age, now)
    # For the reason `examples.build_folder` gives.
    git(folder, "update-index", "-q", "--refresh")
    return folder


def wait_for_window() -> None:
    """Return once the terminal is `COLS` x `ROWS`, saying how far off it is
    until then: no terminal can be sized in cells from in here."""
    while True:
        size = os.get_terminal_size()
        if (size.columns, size.lines) == (COLS, ROWS):
            print()
            return
        print(
            f"\rResize the window to {COLS}x{ROWS} "
            f"(now {size.columns}x{size.lines}), or Ctrl-C to quit.   ",
            end="",
            flush=True,
        )
        time.sleep(0.2)


def main(argv: list[str]) -> int:
    if argv:
        refuse("usage: test/readme.py")
    if not sys.stdout.isatty():
        refuse("readme: run this in the terminal the picture is taken in")

    need("yazi", "git")
    try:
        blocks = setup_blocks(README.read_text())
        named = flavors(blocks.get(THEME, ""))
    except ValueError as error:
        refuse(f"readme: README.md: {error}")
    plugins = required(blocks[INIT])
    for name in sorted(plugins):
        if not installed(name).is_dir():
            refuse(
                f"readme: the setup requires {name}, and there is no "
                f"{installed(name)} to link it from: `ya pkg add` it"
            )
    for name in sorted(named):
        if not flavor(name).is_dir():
            refuse(
                f"readme: the setup names the flavor {name}, and there is no "
                f"{flavor(name)} to link it from: `ya pkg add` it"
            )
    if os.environ.get("TMUX"):
        print("readme: inside tmux -- its status bar would be in the picture")

    print(f"readme: Yazi {yazi_version()}")
    catch_term()

    fixture.clear(DIR)
    DIR.mkdir()
    (DIR / fixture.MARKER).touch()
    try:
        configure(DIR, blocks, plugins, named)
        folder = build_folder(DIR)
        try:
            wait_for_window()
        except KeyboardInterrupt:
            print()
            return 130
        env = {
            **os.environ,
            **yazi_env(DIR, "state", headless=False),
            **GIT_ENV,
            "HOME": str(DIR),
            "XDG_CONFIG_HOME": str(DIR / ".config"),
        }
        done = subprocess.run(
            ["yazi", str(folder)], cwd=folder, env=env, check=False
        )
        # Read before the scratch home goes, and every line of it, since the
        # log goes with it.
        log = yazi_log(DIR, "state")
        if not log.exists():
            print(
                "readme: Yazi wrote no log, so nothing says the columns drew "
                "without error",
                file=sys.stderr,
            )
            return 1
        if trouble := troubles(log.read_text()):
            print(
                "readme: Yazi logged trouble, which the picture may show:\n"
                + "\n".join(f"  {line.strip()}" for line in trouble),
                file=sys.stderr,
            )
            return 1
        if done.returncode != 0:
            print(f"readme: Yazi exited {done.returncode}", file=sys.stderr)
            return 1
    finally:
        fixture.clear(DIR)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
