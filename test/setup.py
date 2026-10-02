#!/usr/bin/env python3
"""Build the throwaway Yazi configuration and the fixture both harnesses use.

    test/setup.py <dir>           build the fixture in <dir>
    test/setup.py --clean <dir>   throw it away again

`e2e.py`, `manual.py` and `gallery.py` all call this, so what a human looks at
and what the headless run asserts on cannot drift apart. Nothing outside <dir>
is touched, and your own Yazi configuration is never read.

Both forms rewrite or remove <dir> wholesale, so both refuse it unless it is
empty or carries the marker file this script leaves behind. That guard lives
here alone: a harness that wrote its own `rmtree` would be the copy that
forgets it.

The configuration itself is not written from here. It sits under
`test/fixture/` as the files Yazi reads -- an `init.lua` and a `case` plugin
that stylua formats and `lua-language-server` type-checks along with the
plugin, and TOML that is TOML rather than a heredoc, and a `theme-key.py` that
ruff reads along with this file. `@DIR@` in any of them is replaced with the
scratch directory as it is copied, and the script is given a shebang.

The one thing written rather than copied is what `cases.toml` and
`walk.toml` become: a binding per folder, per case and per theme, appended to
the keymap, and the table the `case` and `walk` plugins read. `write_cases`
says why that is generated.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import sys
import time
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from harness import ROOT, refuse

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
    """Remove the fixture, having asked whether it is ours to remove.

    A path that is not there is not a failure: both forms arrive here that
    way, `--clean` twice and every first build. Anything else is -- a
    permission, an immutable flag, a file another process still holds -- and
    `ignore_errors` would swallow all of them, leaving both callers saying the
    opposite of what happened: `--clean` reporting the fixture gone, and a
    build writing into what is left of the last one.
    """
    if not owned(path):
        refuse(f"setup: {path} exists and is not ours; move it aside")
    try:
        shutil.rmtree(path)
    except FileNotFoundError:
        pass
    except OSError as error:
        refuse(f"setup: {path} would not go away: {error}")


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
    does the column climb evenly, with no flat run and no jump -- cannot be
    asked in it at all.

    Each folder here is one distribution that question needs, and nothing else
    is in them. A fourth is three edits: a folder here, a linemode in
    `init.lua`, and a folder and a case in `cases.toml`.
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

    # The table it reads is written beside it by `write_cases`, once the
    # folders it names exist.
    (config / "plugins" / "case.yazi").mkdir()
    place(FIXTURE / "case.lua", config / "plugins" / "case.yazi" / "main.lua")
    (config / "plugins" / "walk.yazi").mkdir()
    place(FIXTURE / "walk.lua", config / "plugins" / "walk.yazi" / "main.lua")

    # `default.toml` is what Yazi opens with, and `e2e.py` rewrites this copy
    # in place -- it greps for the values that file spells, so change them
    # there too.
    put_theme(target, "default")

    (config / "plugins" / "supaline.yazi").symlink_to(ROOT)

    # The copy is a script rather than a `cp` the `case` plugin spells out,
    # because what the plugin emits is a `shell` template: a path with a space
    # in it -- `TMPDIR` on a Mac is under `/var/folders/`, and `--clean` takes
    # any directory a person names -- would have to survive the shell's
    # quoting and Yazi's own template parser, twice over. One `argv` here, and
    # the plugin hands it a name.
    # Why it emits the reload itself is in its own docstring, beside the line
    # that does it.
    #
    # The shebang is the interpreter this harness is itself running under,
    # rather than an `env python3` that would resolve against whatever PATH
    # Yazi's `shell` template happens to hand it. It is prepended here rather
    # than written into the fixture file, which carries none: a shebang there
    # would make ruff ask for the executable bit, and a source file that
    # declares an interpreter nothing can run is worse than one that declares
    # none.
    key = target / "theme-key.py"
    key.write_text(
        f"#!{sys.executable}\n" + (FIXTURE / "theme-key.py").read_text()
    )
    key.chmod(0o755)


def put_theme(target: Path, name: str) -> None:
    """Put one of the scratch tree's themes where Yazi reads it.

    `theme-key.py` makes the same copy from inside Yazi, where it cannot import
    this; a Yazi started after this call opens on the theme instead.
    """
    shutil.copyfile(
        target / "themes" / f"{name}.toml", target / "config" / "theme.toml"
    )


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

    # Two alternatives, because a spread is not a short ramp: it has one colour
    # and the marker sits beside it rather than between two of them. The
    # spread first, so the arrow inside the marker cannot be matched as a ramp
    # with an empty end.
    #
    # The spread alternative takes an optional name after the marker, which is
    # what a marked colour writes when it wants a lightness range other than
    # the one its key is called. The name is not resolved here and does not have to be:
    # `ramp.lua` answers every name with the pair it was given, because what it
    # is for is looking at a pair rather than at a `setup`.
    pattern = re.compile(
        rf'"({HEX}\s*<->(\s*[a-z][a-z0-9_]*)?|{HEX}(\s*->\s*{HEX})+)"'
    )
    found = sorted(
        {m.group(1) for body in bodies.values() for m in pattern.finditer(body)}
    )
    (target / "ramps.txt").write_text("".join(f"{r}\n" for r in found))

    # And a second, looser search saying the first one caught everything.
    # Nothing reads `ramps.txt` but `manual.py`, which is not in CI, so a
    # pattern that started missing a ramp would show up as a quieter list and
    # nothing else.
    #
    # The arrow is what a flat colour can never contain -- a spread carries one
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


def check_cases(target: Path, listing: Cases) -> None:
    """Every folder, landmark and hover `cases.toml` names is on disk.

    The half of the case list `cases` cannot see, asked once the fixture is
    built. A landmark another listed folder holds as well is refused along
    with a missing one: `e2e.py` would find it on screen before the `cd` that
    was meant to put it there.

    A name is on disk when the folder lists it, which `lexists` asks and
    `exists` does not: `exists` follows a symlink, and `data/` holds one that
    points nowhere and that `MANUAL.md` asks a reader to hover.
    """
    root = target / "fixture"
    faults = []
    for folder in listing.folders.values():
        if not os.path.lexists(root / folder.path / folder.landmark):
            faults.append(f"`{folder.landmark}` is not in {folder.path}/")
        also = [
            other.path
            for other in listing.folders.values()
            if other is not folder
            and os.path.lexists(root / other.path / folder.landmark)
        ]
        if also:
            faults.append(
                f"`{folder.landmark}`, the landmark of {folder.path}/, is in "
                f"{', '.join(also)} as well"
            )
    for case in listing.cases.values():
        if case.hover and not os.path.lexists(root / case.folder / case.hover):
            faults.append(
                f"case `{case.id}` hovers `{case.hover}`, not in {case.folder}/"
            )
    if faults:
        for fault in faults:
            print(f"  {fault}", file=sys.stderr)
        refuse(
            "setup: test/fixture/cases.toml names what the fixture did not build"
        )


def toml_string(text: str) -> str:
    """`text` as a TOML basic string. JSON's escapes are a subset of TOML's."""
    return json.dumps(text, ensure_ascii=False)


def write_cases(target: Path, listing: Cases, steps: list[Step]) -> None:
    """The keymap bindings and the plugins' table, out of `cases.toml` and
    `walk.toml`.

    Generated rather than written by hand beside it, because a case is a key,
    a folder and a linemode together, and two files each holding half of that
    is the pair that drifts: a key bound to a case the table no longer has
    presses nothing and says so only on screen.

    The plugin's table is Lua, because Yazi hands a plugin no TOML reader.
    Neither it nor a binding carries the scratch directory: the plugin puts
    that in front of a folder or a theme itself, from the `@DIR@` it was
    copied with, so neither Yazi's own argument parser nor a string written
    here ever has to quote one. What both carry is names `cases` has already
    held to what needs no quoting.
    """
    blocks = [
        "",
        "# --- written by test/setup.py from test/fixture/cases.toml ---",
    ]

    def bind(key: str, run: str, desc: str) -> None:
        on = ", ".join(toml_string(k) for k in key.split(" "))
        blocks.extend(
            [
                "",
                "[[mgr.prepend_keymap]]",
                f"on   = [ {on} ]",
                f"run  = {toml_string(run)}",
                f"desc = {toml_string(desc)}",
            ]
        )

    table = [
        "-- Written by test/setup.py from test/fixture/cases.toml.",
        "return {",
        f'\tverdicts = "{VERDICTS}",',
        "\tcases = {",
    ]
    for folder in listing.folders.values():
        bind(folder.key, f"plugin case -- cd {folder.path}", folder.desc)
    for case in listing.cases.values():
        bind(case.key, f"plugin case -- show {case.id}", case.desc)
        fields = [f'folder = "{case.folder}"', f'linemode = "{case.linemode}"']
        if case.hover:
            fields.append(f'hover = "{case.hover}"')
        table.append(f'\t\t["{case.id}"] = {{ {", ".join(fields)} }},')
    table.extend(["\t},", "\tthemes = {"])
    for theme in listing.themes.values():
        bind(theme.key, f"plugin case -- theme {theme.name}", theme.desc)
        table.append(f'\t\t["{theme.name}"] = true,')
    table.extend(["\t},", "\tsteps = {"])
    for step in steps:
        fields = [
            f'case = "{step.case}"',
            f'key = "{listing.cases[step.case].key}"',
            f'theme = "{step.theme}"',
            f'ask = "{step.ask}"',
        ]
        table.append(f"\t\t{{ {', '.join(fields)} }},")
    table.extend(["\t},", "}"])

    keymap = target / "config" / "keymap.toml"
    keymap.write_text(keymap.read_text() + "\n".join(blocks) + "\n")
    plugin = target / "config" / "plugins" / "case.yazi"
    (plugin / "cases.lua").write_text("\n".join(table) + "\n")


# --- what the fixture spells ------------------------------------------------
#
# Readers over the configuration this script copies, for `e2e.py` to assert
# against and `test_screen.py` to pin in CI. A hex written in a harness as well
# is the copy that goes stale, and a recoloured fixture then reports as a
# plugin that stopped drawing; a pattern copied into the test goes on passing
# while the reader beside it has stopped matching. So both call these.

#: A six-digit hex colour, as `init.lua` writes one.
HEX = "#[0-9a-fA-F]{6}"


def binding(init: str, name: str) -> tuple[str, ...]:
    """The colours `init.lua` binds to `local <name>`, in order.

    One for a flat colour, two for a two-ended ramp, and none for anything
    else -- anchored on both sides, so a name bound to a spread, a style table
    or a three-stop ramp answers nothing rather than half of itself.
    """
    found = re.search(
        rf'^local {name} = "({HEX})(?: -> ({HEX}))?"$', init, re.MULTILINE
    )
    return tuple(c for c in found.groups() if c) if found else ()


def broken_columns(init: str) -> list[str]:
    """The columns `init.lua` registers as wrong on purpose.

    Register another and `e2e.py` goes red until a key for it is pressed, which
    is the direction the list has to grow in.
    """
    return re.findall(r'^supaline\.column\("(torn_[a-z]*)"', init, re.MULTILINE)


#: The fixture's case list, which `cases` reads.
CASES = FIXTURE / "cases.toml"


@dataclass(frozen=True)
class Folder:
    """A `[[folder]]` of `cases.toml`: a directory under `fixture/`, the key
    that goes there, and a name only it holds."""

    path: str
    key: str
    landmark: str
    desc: str


@dataclass(frozen=True)
class Case:
    """A `[[case]]` of `cases.toml`: a state, and the key that puts Yazi in it.

    `hover` is empty for a case that leaves the hover where it is.
    """

    id: str
    key: str
    folder: str
    linemode: str
    desc: str
    hover: str = ""
    broken: bool = False


@dataclass(frozen=True)
class Theme:
    """A `[[theme]]` of `cases.toml`: a file under `themes/`, by the name it is
    named after, and the key that puts it in place."""

    name: str
    key: str
    desc: str


@dataclass(frozen=True)
class Cases:
    """Every folder, by path, every case, by id, and every theme, by name, each
    in the file's order."""

    folders: dict[str, Folder]
    cases: dict[str, Case]
    themes: dict[str, Theme]

    @property
    def clean(self) -> list[Case]:
        """The cases one Yazi presses, logging nothing."""
        return [c for c in self.cases.values() if not c.broken]

    @property
    def broken(self) -> list[Case]:
        """The cases a second Yazi presses, with a log of its own."""
        return [c for c in self.cases.values() if c.broken]


#: What a name in `cases.toml` may be spelled with, by what it names. Each goes
#: into a keymap `run` or a plugin's arguments unquoted, so each is held to what
#: needs no quoting in either.
NAME = re.compile(r"[a-z][a-z0-9_]*")
FOLDER = re.compile(r"[a-z0-9_-]+(/[a-z0-9_-]+)*")
KEY = re.compile(r'[^\s"\\]+( [^\s"\\]+)*')
#: A hover goes into the plugin's table as a Lua string, and names a file rather
#: than a folder, so it is held to one name with nothing that string escapes.
HOVER = re.compile(r'[^/"\\\x00-\x1f\x7f]+')


def fields(
    kind: str, row: dict, want: dict[str, type], may: dict[str, type]
) -> None:
    """A `[[kind]]` of `cases.toml` or `walk.toml`, refused unless it has every
    field in `want`, no field outside `want` and `may`, and each of the type
    either gives it -- a string non-empty -- so a value of the wrong type is a
    refusal rather than a traceback from wherever it is first used."""
    got = set(row)
    if want.keys() - got or got - want.keys() - may.keys():
        raise ValueError(
            f"a [[{kind}]] with {sorted(got)}: it needs {sorted(want)}"
            + (f" and may have {sorted(may)}" if may else "")
        )
    allowed = {**want, **may}
    for name, value in row.items():
        wanted = allowed[name]
        if not isinstance(value, wanted) or value == "":
            raise ValueError(
                f"[[{kind}]] `{name}` is not a "
                + ("boolean" if wanted is bool else "non-empty string")
            )


def cases(text: str) -> Cases:
    """The folders and cases `cases.toml` lists, refused if any is malformed.

    Refused with `ValueError` rather than read past, because every reader of
    the answer trusts it: a case whose folder is misspelled would be a key that
    goes nowhere, and `e2e.py` would wait out its whole deadline on a landmark
    that is never coming. What this cannot see is the disk -- whether each
    folder, landmark and hover exists -- and `check_cases` asks that once the
    fixture is built.
    """
    # Here rather than at the top, for the reason `theme_values` gives.
    import tomllib

    data = tomllib.loads(text)
    unknown = set(data) - {"folder", "case", "theme"}
    if unknown:
        raise ValueError(f"unknown table(s): {sorted(unknown)}")

    def spelled(what: str, value: str, pattern: re.Pattern[str]) -> str:
        if not pattern.fullmatch(value):
            raise ValueError(
                f"{what} `{value}` does not match `{pattern.pattern}`"
            )
        return value

    keys: set[str] = set()

    def unique_key(key: str) -> str:
        spelled("key", key, KEY)
        if key in keys:
            raise ValueError(f"two entries bind `{key}`")
        keys.add(key)
        return key

    folders: dict[str, Folder] = {}
    for row in data.get("folder", []):
        fields(
            "folder",
            row,
            dict.fromkeys(("path", "key", "landmark", "desc"), str),
            {},
        )
        path = spelled("folder", row["path"], FOLDER)
        if path in folders:
            raise ValueError(f"two [[folder]]s at `{path}`")
        folders[path] = Folder(
            path, unique_key(row["key"]), row["landmark"], row["desc"]
        )

    listed: dict[str, Case] = {}
    for row in data.get("case", []):
        fields(
            "case",
            row,
            dict.fromkeys(("id", "key", "folder", "linemode", "desc"), str),
            {"hover": str, "broken": bool},
        )
        id = spelled("case", row["id"], NAME)
        if id in listed:
            raise ValueError(f"two [[case]]s called `{id}`")
        if row["folder"] not in folders:
            raise ValueError(
                f"case `{id}` is read in `{row['folder']}`, which no [[folder]] lists"
            )
        hover = row.get("hover", "")
        listed[id] = Case(
            id,
            unique_key(row["key"]),
            row["folder"],
            spelled("linemode", row["linemode"], NAME),
            row["desc"],
            hover and spelled("hover", hover, HOVER),
            row.get("broken", False),
        )

    themes: dict[str, Theme] = {}
    for row in data.get("theme", []):
        fields("theme", row, dict.fromkeys(("name", "key", "desc"), str), {})
        name = spelled("theme", row["name"], NAME)
        if name in themes:
            raise ValueError(f"two [[theme]]s called `{name}`")
        themes[name] = Theme(name, unique_key(row["key"]), row["desc"])

    # The guard every reader inherits: an empty list would press nothing, bind
    # nothing, and pass. No theme is a fault as well, since `copy_config` opens
    # Yazi on one; that it is the files under `themes/` is `test_screen.py`'s.
    if not folders or not listed or not themes:
        raise ValueError("no [[folder]], no [[case]] or no [[theme]] at all")
    return Cases(folders, listed, themes)


def read_cases() -> Cases:
    """`cases.toml` itself, or a refusal that says what is wrong with it."""
    try:
        return cases(CASES.read_text())
    except ValueError as error:
        refuse(f"setup: test/fixture/cases.toml: {error}")


#: The walk `manual.py` offers, which `walk` reads.
WALK = FIXTURE / "walk.toml"

#: Where the `walk` plugin writes a verdict, under the scratch directory. Spelled
#: here alone: `write_cases` hands it to the plugin in its table.
VERDICTS = "verdicts.txt"


@dataclass(frozen=True)
class Step:
    """A `[[step]]` of `walk.toml`: a case, the theme it is shown under, the
    question asked about it, and whether `gallery.py` asks it too."""

    case: str
    theme: str
    ask: str
    gallery: bool


#: What a question may be spelled with. It goes into the plugins' table as a Lua
#: string, so nothing that string escapes; and it is drawn in the status bar,
#: where `e2e.py` splits a line on `│` to find the panes, so not that either.
ASK = re.compile(r'[^"\\│\x00-\x1f\x7f]+')

#: The longest question, in characters. The status bar holds Yazi's own parts
#: either side of it, and a question cut off at the edge is a question unasked.
ASK_LONGEST = 50


def walk(text: str, listing: Cases) -> list[Step]:
    """The steps `walk.toml` lists, in order, refused if any is malformed.

    Refused with `ValueError`, as `cases` refuses, and for the same reason: a
    step naming a case the list does not hold is a key that shows nothing. A
    broken case shown twice is refused as well. `told` reports a column once
    a session, so the second step would ask about a notification that is not
    coming. So is a step that works after one that is broken: a broken case's
    notification lands late and lingers, over whatever the next step draws,
    and the last of them has the reader arm a `refresh` that throws at every
    `cd` after it. And a broken case is refused in the gallery, which shows a
    capture: what a broken step asks about is the notification, which lands
    after the capture rather than in it.
    """
    # Here rather than at the top, for the reason `theme_values` gives.
    import tomllib

    data = tomllib.loads(text)
    if set(data) - {"step"}:
        raise ValueError(f"unknown table(s): {sorted(set(data) - {'step'})}")

    steps: list[Step] = []
    shown: set[str] = set()
    for row in data.get("step", []):
        fields(
            "step",
            row,
            {"case": str, "ask": str},
            {"theme": str, "gallery": bool},
        )
        case, ask = row["case"], row["ask"]
        theme = row.get("theme", "default")
        if case not in listing.cases:
            raise ValueError(f"a step shows `{case}`, which no [[case]] is")
        if theme not in listing.themes:
            raise ValueError(f"a step puts `{theme}` in, which no [[theme]] is")
        if not ASK.fullmatch(ask):
            raise ValueError(
                f"step `{case}` asks {ask!r}, which `{ASK.pattern}` refuses"
            )
        if len(ask) > ASK_LONGEST:
            raise ValueError(
                f"step `{case}` asks {len(ask)} characters, over {ASK_LONGEST}"
            )
        broken = listing.cases[case].broken
        gallery = row.get("gallery", False)
        if broken and case in shown:
            raise ValueError(f"the broken case `{case}` is shown twice")
        if broken and gallery:
            raise ValueError(f"the broken case `{case}` is in the gallery")
        if not broken and steps and listing.cases[steps[-1].case].broken:
            raise ValueError(f"step `{case}` comes after a broken one")
        shown.add(case)
        steps.append(Step(case, theme, ask, gallery))

    if not steps:
        raise ValueError("no [[step]] at all")
    return steps


def read_walk(listing: Cases) -> list[Step]:
    """`walk.toml` itself, or a refusal that says what is wrong with it."""
    try:
        return walk(WALK.read_text(), listing)
    except ValueError as error:
        refuse(f"setup: test/fixture/walk.toml: {error}")


#: What a person reads beside the screen, which `goes_to` reads.
MANUAL = ROOT / "test" / "MANUAL.md"


def goes_to(manual: str) -> dict[str, str]:
    """The folder key `MANUAL.md`'s tables give each case key, by case key.

    A row that ends in a `g` key, which is how the colour and broken tables
    say where a case is drawn. The column is a copy of each case's `folder`
    for a person to read, and nothing a run presses reads it: move a case in
    `cases.toml` and its key goes with it, while the table goes on sending a
    reader to the old folder. A case key found twice is refused rather than
    answered with whichever row came last.
    """
    found: dict[str, str] = {}
    for key, folder in re.findall(
        r"^\| `(\S+ \S+)` \|.*\| `(g \S+)` +\|$", manual, re.MULTILINE
    ):
        if key in found:
            raise ValueError(f"MANUAL.md sends `{key}` to two folders")
        found[key] = folder
    return found


def band_width(init: str, name: str) -> int:
    """The width a `c_bg` column states beside the ground it names, or 0.

    A trailing space, comma or close brace, because a style writes the name
    with one of the three after it -- which is what keeps a ground named after
    another one from matching.
    """
    found = re.search(rf".*bg = {name}[ ,}}].*width = (\d+)", init)
    return int(found.group(1)) if found else 0


def c_bg_grounds(init: str) -> list[str] | None:
    """Every name `c_bg` writes under a `bg`, or `None` if the block is gone.

    The two are different failures: a block with no grounds is a fixture
    nobody gave one, and a block this cannot find is a sweep passing over
    nothing -- the pattern is anchored on stylua's indentation, so re-nesting
    that table is all it takes.
    """
    block = re.search(r"c_bg = \{.*?\n\t\t\},", init, re.DOTALL)
    if not block:
        return None
    return re.findall(r"bg = ([A-Z_]+)[ ,}]", block.group(0))


def terminal_grounds(init: str) -> list[tuple[str, str]]:
    """The terminal grounds `init.lua` measures `GROUND` against, as a name and
    a hex each, in its order -- which `gallery.py` draws every capture on.

    Read off the comment above `GROUND`, which is the one place they are
    written: the distances there were taken against these, and a gallery drawn
    on a list of its own would show the reader grounds nobody measured. A
    comment rewritten into another shape answers nothing, and `gallery.py`
    refuses that rather than drawing on no ground.
    """
    block = re.search(r"((?:^--.*\n)+)^local GROUND = ", init, re.MULTILINE)
    if not block:
        return []
    prose = " ".join(
        line.removeprefix("--").strip() for line in block.group(1).splitlines()
    )
    found = re.search(r"terminal grounds -- (.*?) -- ", prose)
    if not found:
        return []
    return re.findall(rf"(?:^|, )([^,`]+) `({HEX})`", found.group(1))


def theme_values(dir: Path, name: str) -> tuple[str, str]:
    """`size`'s flat colour and `mtime`'s ramp, out of one of the themes.

    `dir` holds a `themes/` of them: the scratch copy, where the `c` keys put
    their themes, or `test/fixture/` itself.
    """
    # Here rather than at the top: `tomllib` is 3.11's, and `harness` has to be
    # imported first to refuse an older Python with a sentence.
    import tomllib

    theme = tomllib.loads((dir / "themes" / f"{name}.toml").read_text())
    return theme["supaline"]["size"]["fg"], theme["supaline"]["mtime"]


def theme_ends(dir: Path, name: str) -> tuple[str, str]:
    """`mtime`'s ramp in one of the themes, as its low and high end."""
    low, high = theme_values(dir, name)[1].split(" -> ")
    return low, high


def build(target: Path) -> None:
    # Read before anything is built, so a malformed list stops the build with
    # its own sentence rather than half a fixture.
    listing = read_cases()
    steps = read_walk(listing)

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
        check_cases(target, listing)
        write_cases(target, listing, steps)
    finally:
        os.umask(was)


def main(argv: list[str]) -> None:
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
