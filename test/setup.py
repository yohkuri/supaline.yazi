#!/usr/bin/env python3
"""Build the throwaway Yazi configuration and the fixture both harnesses use.

    test/setup.py <dir>           build the fixture in <dir>
    test/setup.py --clean <dir>   throw it away again

`e2e.py` and `manual.py` both call this, so what a human looks at and what the
headless run asserts on cannot drift apart. Nothing outside <dir> is touched,
and your own Yazi configuration is never read.

Both forms rewrite or remove <dir> wholesale, so both refuse it unless it is
empty or carries the marker file this script leaves behind. That guard lives
here alone: a harness that wrote its own `rmtree` would be the copy that
forgets it.

The configuration itself is not written from here. It sits under
`test/fixture/` as the files Yazi reads -- an `init.lua` that stylua formats
and `lua-language-server` type-checks along with the plugin, and TOML that is
TOML rather than a heredoc. `@DIR@` in any of them is replaced with the
scratch directory as it is copied, which is the whole of what this script does
to them.
"""

from __future__ import annotations

import os
import re
import shutil
import stat
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import ROOT, refuse, require_python

#: Left behind in a directory this script built, and asked for before anything
#: is removed.
MARKER = ".supaline-fixture"

#: The configuration Yazi reads, before `@DIR@` is filled in.
FIXTURE = ROOT / "test" / "fixture"

#: A placeholder rather than a format string: `init.lua` is full of braces, and
#: a substitution that had to be escaped past them would be a second grammar
#: over a file three other readers parse.
DIR_TOKEN = "@DIR@"


def owned(path: Path) -> bool:
    """Whether this script built `path`, and may therefore remove it.

    `lstat` rather than `exists`, so a symlink pointing at somebody's home
    directory is refused here rather than followed. The marker has to be a
    regular file for the same reason -- a directory or a link of that name is
    not something this script left.
    """
    try:
        here = path.lstat()
    except FileNotFoundError:
        return True
    if not stat.S_ISDIR(here.st_mode):
        return False
    try:
        return stat.S_ISREG((path / MARKER).lstat().st_mode)
    except (FileNotFoundError, NotADirectoryError):
        return False


def clear(path: Path) -> None:
    """Remove the fixture, having asked whether it is ours to remove."""
    if not owned(path):
        refuse(f"setup: {path} exists and is not ours; move it aside")
    shutil.rmtree(path, ignore_errors=True)


def stamp(path: Path, when: str) -> None:
    """Set an mtime, spelled the way `touch -t` spells one: CCYYMMDDhhmm.

    Local time, because that is what `touch -t` reads and what the fixture was
    built with -- `mktime` over a naive `struct_time` is the same arithmetic.
    A timezone-aware reading would move every stamped mtime by the offset, and
    `colour/ramp` places one file per ramp step by exactly these minutes.
    """
    at = time.mktime(time.strptime(when, "%Y%m%d%H%M"))
    os.utime(path, (at, at))


def sized(path: Path, length: int) -> None:
    """A file of exactly `length` bytes.

    Sparse rather than `length` zeroes actually written: what every column
    here reads is the size in the metadata, and `huge.bin` alone is 88MB of
    nothing worth putting on a disk.
    """
    with path.open("wb") as f:
        f.truncate(length)


def steps() -> int:
    """How many steps a ramp is quantised into, read out of `colour.lua`.

    Read rather than written here: a fixture that claimed one row per step
    while `STEPS` had moved would be a quieter kind of wrong than a harness
    that stops.
    """
    found = re.search(
        r"^local STEPS = (\d+)$",
        (ROOT / "colour.lua").read_text(),
        re.MULTILINE,
    )
    if not found or int(found.group(1)) > 1440:
        refuse(
            "setup: cannot read a usable STEPS out of colour.lua "
            f"(got {found.group(1) if found else 'nothing'})\n"
            "setup: the ramp folder spaces its files one minute apart, so it "
            "needs a day's worth"
        )
    return int(found.group(1))


def build_fixture(root: Path) -> None:
    """The files every column is read against.

    The harness opens `data/`, so everything worth looking at lives there: the
    current pane is the one that matters. `fixture/` holds a few siblings so
    the parent pane has rows of its own, and `nested/` gives the preview one.

    Sizes span five orders of magnitude, times span six years, and the names
    are the ones that break width arithmetic: CJK, emoji, and one far too long.
    """
    data = root / "data"
    (data / "nested").mkdir(parents=True)
    (data / "never-opened").mkdir(parents=True)

    (data / "empty.txt").write_bytes(b"")
    (data / "tiny.txt").write_bytes(b"x")
    sized(data / "under-1k.bin", 1023)
    sized(data / "exactly-1k.bin", 1024)
    sized(data / "widest-size.bin", 1048000)
    sized(data / "medium.bin", 800 * 1024)
    sized(data / "large.bin", 9000 * 1024)
    sized(data / "huge.bin", 90000 * 1024)

    (data / "日本語のファイル名.txt").write_bytes(b"x")
    (data / "絵文字🎨のなまえ.txt").write_bytes(b"x")
    long_name = "a-very-long-file-name-that-yazi-itself-has-to-truncate-away"
    (data / f"{long_name}.txt").write_bytes(b"x")

    (data / "link-ok").symlink_to("medium.bin")
    (data / "link-broken").symlink_to("nowhere-at-all")

    # Read-only rather than unreadable: a mode of 000 gives the permissions
    # column something to show, but Yazi's own mime fetcher then fails on it
    # and fills the log with errors the harness would have to learn to ignore.
    read_only = data / "read-only.txt"
    read_only.write_bytes(b"x")
    read_only.chmod(0o400)

    stamp(data / "large.bin", "202001020304")
    stamp(data / "medium.bin", "202312250000")
    stamp(data / "huge.bin", "202405060708")
    stamp(data / "under-1k.bin", "202601010000")

    (data / "nested" / "inner-a.txt").write_bytes(b"x")
    sized(data / "nested" / "inner-b.bin", 300 * 1024)
    stamp(data / "nested" / "inner-a.txt", "202312250000")
    (data / "never-opened" / "hidden-away.txt").write_bytes(b"x")

    (root / "sibling-one").mkdir()
    (root / "sibling-two").mkdir()
    (root / "sibling-one" / "one.txt").write_bytes(b"x")
    sized(root / "sibling-two" / "two.bin", 64 * 1024)


def build_colour(root: Path) -> None:
    """One folder per distribution a ramp has to be looked at over.

    A colour case is a *folder*. Where a row lands on a ramp is `ctx.ratio`,
    and that normalises against the extremes of the folder being drawn -- so
    the spread of values in front of you is the whole of what decides which
    part of a ramp reaches the screen, and the only way to choose that spread
    is to choose the folder.

    `data/` holds whatever the width cases needed, which makes it a poor
    instrument for looking at colour: its mtimes land on five of the ramp's
    steps, four of them in the top third, and a dozen rows share the highest.
    Nothing there is adjacent, so the question `MANUAL.md` puts to a reader --
    can you tell one step from the next -- cannot be asked in it at all.

    Each folder here is one distribution that question needs, and nothing else
    is in them. A fourth is three edits: a folder here, a linemode in
    `init.lua`, and a key in `keymap.toml`.
    """
    ramp = root / "colour" / "ramp"
    scale = root / "colour" / "scale"
    edge = root / "colour" / "edge"
    for folder in (ramp, scale, edge):
        folder.mkdir(parents=True)

    # One file per ramp step. `mtime` is linear -- only `size` sets
    # `scale = "log"` -- so evenly spaced minutes are evenly spaced ratios, and
    # consecutive files land on consecutive steps.
    #
    # The year is in the past on purpose. `mtime` draws another year as
    # `MM/DD  YYYY`, so every one of these rows carries the *same text* and the
    # only thing that differs down the column is the colour, which is the
    # comparison a reader is being asked to make. The step number is in the
    # name instead, so a row can still be named out loud.
    for i in range(steps()):
        f = ramp / f"step-{i:02d}.txt"
        f.write_bytes(b"")
        stamp(f, f"20200101{i // 60:02d}{i % 60:02d}")

    # Sizes doubling from 1B, which is what makes `scale` visible: under `log`
    # the steps come out evenly spaced, and under `linear` everything but the
    # largest few collapses into the ramp's bottom step. Twenty-one of them is
    # twenty doublings and 2MB on disk, which is enough of both.
    for i in range(21):
        sized(scale / f"pow-{i:02d}.bin", 1 << i)

    # Both rules a ramp falls back on when it has nothing to spread itself
    # over, on one screen.
    #
    # Every value here is the same -- four files of three bytes, and mtimes
    # stamped equal across the lot -- so `hi == lo`, and `ratio` answers 1
    # rather than dividing by nothing. Every row that has a value draws the
    # ramp's *high* end. Not its low one, and not the flat ground underneath it.
    #
    # The two directories are the other rule, and they are a pair because the
    # pair is what makes it legible. `size` has nothing to place for either of
    # them: `file:size()` is nil for a directory, so the count is drawn as
    # *text* and `ctx.style` -- the ramp's low end -- as its colour, and the
    # ratio never hears about it. `unlisted-a` is listed the moment the preview
    # reads it, so it shows a count; `unlisted-b` is one row further down and
    # never is, so it shows `-`. Three entries each, to put that count in the
    # same shape as the `3B` beside it: two cells reading nearly the same and
    # coloured from opposite ends is the misreading this folder exists to
    # correct.
    #
    # The directories are stamped along with the files, and after the files
    # inside them, which is what moved their mtimes in the first place. A
    # directory carries one like anything else, so leaving them at "now" would
    # put a second value in that column and leave no `hi == lo` there to look
    # at.
    same = [edge / f"same-{n}.txt" for n in "abcd"]
    for f in same:
        f.write_bytes(b"xxx")
    unlisted = [edge / "unlisted-a", edge / "unlisted-b"]
    for d in unlisted:
        d.mkdir()
        for n in ("one", "two", "three"):
            (d / f"{n}.txt").write_bytes(b"x")
    for f in same + unlisted:
        stamp(f, "202312250000")


def build_broken(root: Path) -> None:
    """The folder that arms the broken `refresh`.

    Walking in here arms the `refresh` of `torn_tick`, and nothing else does.
    Why that is a folder rather than a key is beside the column, with the code
    that reads the cwd.

    Three entries, so the counter that stops climbing is read down a column
    rather than off a single row.
    """
    broken = root / "broken"
    broken.mkdir()
    (broken / "one.txt").write_bytes(b"x")
    (broken / "a-longer-name.txt").write_bytes(b"xx")
    sized(broken / "some.bin", 4 * 1024)


def copy_config(target: Path) -> None:
    """Put `test/fixture/` where Yazi reads it, filling in `@DIR@`."""
    config = target / "config"
    themes = target / "themes"
    (config / "plugins").mkdir(parents=True)
    themes.mkdir()

    def place(source: Path, dest: Path) -> None:
        dest.write_text(source.read_text().replace(DIR_TOKEN, str(target)))

    place(FIXTURE / "yazi.toml", config / "yazi.toml")
    place(FIXTURE / "keymap.toml", config / "keymap.toml")
    place(FIXTURE / "init.lua", config / "init.lua")
    for theme in sorted((FIXTURE / "themes").glob("*.toml")):
        place(theme, themes / theme.name)

    # `default.toml` is what Yazi opens with, and `e2e.py` rewrites this copy
    # in place -- it greps for the values that file spells, so change them
    # there too.
    shutil.copyfile(themes / "default.toml", config / "theme.toml")

    (config / "plugins" / "supaline.yazi").symlink_to(ROOT)

    # The copy is a script rather than a `cp` spelled out three times in the
    # keymap, because the keymap is TOML inside a `shell` template: a path with
    # a space in it -- `TMPDIR` on a Mac is under `/var/folders/`, and `--clean`
    # takes any directory a person names -- would have to survive both
    # quotings, and one of them is Yazi's own template parser. One `argv` here,
    # and the keymap carries a name.
    #
    # The reload is emitted from in there, and that is not a preference. A
    # keymap `run` of [ "shell ... --confirm", "app:theme" ] does not wait:
    # measured on 26.9.1, the copy lands on disk and `app:theme` has already
    # re-read the file before it, so the screen keeps the theme it had and
    # `theme.toml` on disk says otherwise -- which looks exactly like a plugin
    # that ignored the reload. `--block` does not fix it either. `ya emit`
    # after the copy does, because then the ordering is that script's.
    key = target / "theme-key.py"
    key.write_text(
        # The interpreter this harness is itself running under, rather than a
        # `env python3` that would resolve against whatever PATH Yazi's `shell`
        # template happens to hand it.
        f"#!{sys.executable}\n"
        '"""Put one of the fixture\'s themes where Yazi reads it, and reload.\n'
        "\n"
        "Called from the `c 1` to `c 3` keys.\n"
        '"""\n'
        "\n"
        "import shutil\n"
        "import subprocess\n"
        "import sys\n"
        "from pathlib import Path\n"
        "\n"
        "here = Path(__file__).resolve().parent\n"
        'shutil.copyfile(here / "themes" / f"{sys.argv[1]}.toml",\n'
        '                here / "config" / "theme.toml")\n'
        'subprocess.run(["ya", "emit", "app:theme"], check=True)\n'
    )
    key.chmod(0o755)


def write_ramps(target: Path) -> None:
    """Every ramp the fixture can draw, one per line, for `manual.py`.

    Read out of what was just *written* rather than out of this script, so the
    list cannot be narrower than the fixture: a ramp with three stops is one
    string in `init.lua` and would come back as its first two under a two-stop
    pattern, which is a gradient the fixture does not draw offered as one it
    does. Both places a ramp can live are covered -- a spec in `init.lua`, and
    a `[supaline]` field in any of the themes.
    """
    sources = [target / "config" / "init.lua"]
    sources += sorted((target / "themes").glob("*.toml"))
    bodies = {path: path.read_text() for path in sources}

    # Two alternatives, because a band is not a short ramp: it has one colour
    # and the marker sits beside it rather than between two of them. The band
    # first, so the arrow inside the marker cannot be matched as a ramp with an
    # empty end.
    #
    # The band alternative takes an optional name after the marker, which is
    # what a marked colour writes when it wants a band other than the one its
    # key is called. The name is not resolved here and does not have to be:
    # `ramp.lua` answers every name with the pair it was given, because what it
    # is for is looking at a pair rather than at a `setup`.
    hex6 = "#[0-9a-fA-F]{6}"
    pattern = re.compile(
        rf'"({hex6}\s*<->(\s*[a-z][a-z0-9_]*)?|{hex6}(\s*->\s*{hex6})+)"'
    )
    found = sorted(
        {m.group(1) for body in bodies.values() for m in pattern.finditer(body)}
    )
    (target / "ramps.txt").write_text("".join(f"{r}\n" for r in found))

    # And a second, looser search saying the first one caught everything.
    # Nothing reads `ramps.txt` but `manual.py`, which prints it and is not in
    # CI, so a pattern that started missing a ramp would show up as a quieter
    # list and nothing else -- the exact drift reading the written files
    # instead of this source was meant to avoid.
    #
    # The arrow is what a flat colour can never contain -- a band carries one
    # inside its marker, which is why it is spelled that way -- and that makes
    # "a line with an arrow in it" a test that does not share the pattern
    # above's assumptions: a single-quoted TOML string, an unusual spacing, a
    # third stop. A line whose ramp was caught is excluded whatever surrounds
    # it, and an empty manifest leaves every one of them behind.
    missed = [
        line
        for body in bodies.values()
        for line in body.splitlines()
        if "->" in line and not any(r in line for r in found)
    ]
    if missed:
        print(
            "setup: a ramp reached the fixture without reaching ramps.txt:",
            file=sys.stderr,
        )
        for line in missed:
            print(f"  {line}", file=sys.stderr)
        refuse(
            "setup: widen the pattern in setup.py, or manual.py prints a list "
            "short of what is drawn"
        )


def build(target: Path) -> None:
    # Stated, so the fixture carries the same modes whoever builds it. `e2e.py`
    # greps the permissions column for `drwxr-xr-x`, and under `umask 077` the
    # directories come out `drwx------` -- the column right, the check failing.
    # The files move too, `-rw-r--r--` to `-rw-------`.
    was = os.umask(0o022)
    try:
        target.mkdir(parents=True)
        (target / MARKER).write_bytes(b"")
        (target / "state").mkdir()
        copy_config(target)
        build_fixture(target / "fixture")
        build_colour(target / "fixture")
        build_broken(target / "fixture")
        write_ramps(target)
    finally:
        os.umask(was)


def main(argv: list[str]) -> None:
    require_python()

    clean = argv[:1] == ["--clean"]
    rest = argv[1:] if clean else argv
    if len(rest) != 1:
        refuse("usage: setup.py [--clean] <dir>")

    # Resolved before anything else, so a relative <dir> is read against the
    # directory the caller was in rather than against wherever the build has
    # got to. Not `resolve()` alone, which would follow a symlink the guard
    # above is there to refuse -- `absolute()` makes it absolute and nothing
    # more.
    target = Path(rest[0]).absolute()

    clear(target)
    if clean:
        return
    build(target)


if __name__ == "__main__":
    # Nothing is printed on success; both harnesses say what they are doing.
    main(sys.argv[1:])
