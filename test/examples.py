#!/usr/bin/env python3
"""Draw the pictures in `docs/examples/`, by running the configuration above
each of them in a real Yazi.

    test/examples.py  draw every picture

The pages in `docs/examples/` are the source: a picture is an image line, and
what it is a picture of is the `init.lua` block above it, with a `theme.toml`,
a `yazi.toml` or a `keymap.toml` block if the example has one -- each fenced
block naming its file on its first line, the way the README spells them. This
opens a Yazi on that configuration and on a folder built here, captures it the
way `e2e.py` does, and writes the file list as an SVG: on one dark terminal, or
on a light one or every ground `gallery.py` draws on where the picture says
so -- and before and after a key, or in a wider window, where it says that.

Each SVG carries a digest of the blocks it was drawn from and of its alt text,
and `test_examples.py` holds every image line to it in CI, so a configuration
edited without its picture being redrawn fails there rather than being
published beside a picture of something else. What the digest does not cover
is everything the blocks run on -- the plugin, the folder, the window -- since
a picture that went stale with every edit to the plugin would be redrawn
without being looked at. Redraw them after a change that moves what a column
draws. Drawing needs a Yazi and a terminal, and is not in CI, for the reason
`e2e.py` is not.

The pictures switch Yazi's file icons off. They are Nerd Font glyphs, which an
SVG cannot draw unless its viewer has the font, and a picture full of empty
boxes says the plugin is broken. The two half-discs Yazi draws at either end of
the hovered row are drawn as shapes instead, since they are the cursor. The rest
of that row is Yazi's as it draws it: the preset `hovered` style, which no
example overrides, reverses the row on 26.9.1, as `screen.misdrawn` records,
so a separator's colour, an empty `ext` cell and a `bg` gradient turn into
solid blocks there, as the pictures show.

`user` draws the name of whoever redraws the pictures, and the pictures keep
it rather than writing another over the capture, since what they show is what
the column drew. The git.yazi examples stay, for the reader who wants its sign
beside supaline's columns, at a cost: every redraw needs git.yazi installed,
because a missing plugin is refused before any picture is drawn, and git,
which builds the repository those pictures are of.
"""

from __future__ import annotations

import hashlib
import os
import re
import sys
import tempfile
import time
import tomllib
import unittest
from dataclasses import dataclass
from pathlib import Path
from unittest import mock
from xml.sax.saxutils import escape, quoteattr

sys.path.insert(0, str(Path(__file__).resolve().parent))

# First, because importing it is what refuses too old a Python, and `screen`
# cannot be read by one.
import harness  # noqa: F401
import screen as sc
import setup as fixture
from gallery import SCHEMES, Scheme, scheme
from harness import (
    ROOT,
    STARTUP,
    Session,
    catch_term,
    need,
    refuse,
    run,
    troubles,
    yazi_env,
    yazi_log,
    yazi_version,
)

#: The pages, every `*.md` in it, and the pictures under `images/` beside them.
#: One directory for every page, so an image path is the same from each.
PAGES = ROOT / "docs" / "examples"

#: The scratch directory and the tmux session, both named after the run, so
#: a run owns everything it touches -- for the reason `e2e.py` gives -- and
#: removed when it ends.
PID = os.getpid()
DIR = Path(tempfile.gettempdir()) / f"supaline-examples.{PID}"

#: The window a picture is taken in, unless it asks for a wider one.
#: Narrower than the harnesses' own, because a picture holds one pane and is
#: read at the width of a page.
WIDTH, HEIGHT = 64, 16

#: What Yazi is told unless the example has a `yazi.toml` of its own: the
#: linemode every example is written to define, and the current pane alone,
#: so the file list is the whole window and nothing either side of it is
#: drawn half-cut. An example's own replaces it whole, so it names the
#: linemode itself, and shows the reader the panes it draws.
YAZI_TOML = """\
[mgr]
linemode = "detail"
ratio    = [0, 1, 0]
"""

#: Put after the example's own `theme.toml`, so the icons are switched off
#: however the example themes the rest, and a key the example writes before
#: its first table stays at the top level. An example that themes `[icon]`
#: itself is refused, since the two tables could not both be read. Measured
#: on 26.9.1, the five lists written empty leave no icon drawn: they replace
#: the preset's rather than adding to it.
NO_ICONS = """\
[icon]
globs = []
dirs  = []
files = []
exts  = []
conds = []
"""

#: The ground a picture is drawn on unless it asks for others: a dark
#: terminal, out of the seven `gallery.py` draws on. One, because most of what
#: an example shows is where its columns go and what they say, which a second
#: ground draws again unchanged; a picture whose point is the ground asks.
DARK_GROUND = "Catppuccin Mocha"

#: The light terminal a picture may ask for instead. Lighter than `DARK_GROUND`,
#: which `test_examples.py` holds the two to, since a page names the ground
#: each is drawn on.
LIGHT_GROUND = "Solarized light"

#: A line above an image asking for other grounds than `DARK_GROUND`: every one, for
#: a picture whose point is how the columns follow the terminal's palette, or
#: the light one, for a configuration written for a light ground and wrong on
#: a dark one -- a lightness range is a claim about the ground. A comment, so
#: the page shows nothing of it and markdownlint asks for no exemption. Any
#: other comment that names grounds is refused rather than ignored, since a
#: misspelled one would draw on the dark ground without saying so. Each maps
#: to the grounds it draws on, `None` for every one.
EVERY = "<!-- drawn on every ground -->"
LIGHT = "<!-- drawn on the light ground -->"
ASKED: dict[str, tuple[str, ...] | None] = {
    EVERY: None,
    LIGHT: (LIGHT_GROUND,),
}

#: A line above an image asking for its screen to be drawn twice, before a
#: key is pressed and after, for an example whose point is what a key does.
#: The keys are typed one at a time, so each is one character.
PRESSING = "<!-- drawn before and after pressing KEYS -->"

#: A line above an image asking for a wider window than `WIDTH`, for an
#: example whose `yazi.toml` draws the panes either side of the file list.
WIDE = "<!-- drawn N columns wide -->"


def filled(way: str, slot: str, value: str) -> re.Pattern[str]:
    """A way to ask as a page writes it: its spelling, with `slot` filled by
    what `value` matches."""
    return re.compile("^" + re.escape(way).replace(slot, f"({value})") + "$")


#: The ways to ask that carry a value, by the `Example` field each fills,
#: with how a page spells it and how the field reads it.
FILLED = {
    "pressed": (filled(PRESSING, "KEYS", r"(?:\S )*\S"), str),
    "width": (filled(WIDE, "N", r"\d+"), int),
}

#: Every way to ask, for a refusal of a line that is none of them.
WAYS = (*ASKED, PRESSING, WIDE)

#: The first line of a block, naming the file it belongs in.
INIT = "-- ~/.config/yazi/init.lua"
THEME = "# ~/.config/yazi/theme.toml"
YAZI = "# ~/.config/yazi/yazi.toml"
KEYMAP = "# ~/.config/yazi/keymap.toml"
FILES = (INIT, THEME, YAZI, KEYMAP)

IMAGE = re.compile(r"^!\[([^\]]+)\]\((images/[a-z0-9-]+\.svg)\)$")
#: What every way to ask starts with, and the word a ground is asked by, so a
#: line meant as one and spelled as none is refused rather than ignored.
ASKING = re.compile(r"^\s*<!--(?:\s*drawn\b|.*\bground)", re.IGNORECASE)
HEADING = re.compile(r"^#{1,6}\s")

#: The attribute the digest is written in, on the SVG's root element.
SOURCE = "data-source"


@dataclass(frozen=True)
class Example:
    """One picture, and the blocks above it that it is a picture of."""

    image: str
    alt: str
    init: str
    theme: str = ""
    #: Written in place of `YAZI_TOML`, when the example has one.
    yazi: str = ""
    keymap: str = ""
    #: The line in `ASKED` above the image, or nothing for `DARK_GROUND` alone.
    asked: str = ""
    #: The keys `PRESSING` names, as it names them, or nothing for one screen.
    pressed: str = ""
    width: int = 0

    @property
    def grounds(self) -> tuple[str, ...] | None:
        """The grounds the picture is drawn on by name, `None` for every one."""
        return ASKED.get(self.asked, (DARK_GROUND,))

    @property
    def digest(self) -> str:
        """What the picture was drawn from, so a block edited since says so --
        and what the lines above it asked, since those change the picture as
        much, and the alt text the SVG carries as its title. The grounds by
        name rather than by the line asking for them, so a picture drawn on
        another default than `DARK_GROUND` says so with no line moved."""
        fields = (
            self.alt,
            self.init,
            self.theme,
            self.yazi,
            self.keymap,
            "every" if self.grounds is None else "\n".join(self.grounds),
            self.pressed,
            str(self.width),
        )
        return hashlib.sha256("\0".join(fields).encode()).hexdigest()


def file_block(lines: list[str], i: int) -> tuple[int, str, str] | None:
    """The fenced block opening on line `i`, if one does: the line it closes
    on, the file its first line names -- empty when it names none of
    `FILES` -- and its text, that first line included. Refused when it never
    closes, since everything after it would be read as its body."""
    fence = fixture.FENCE.match(lines[i].rstrip())
    if not fence:
        return None
    end = fixture.closing(lines, i, fence.group(1))
    if end is None:
        raise ValueError(f"line {i + 1}: a block that never closes")
    body = lines[i + 1 : end]
    if not body or body[0] not in FILES:
        return end, "", ""
    return end, body[0], "\n".join(body) + "\n"


def toml_problem(block: str, line: int = 1) -> str | None:
    """Why a `.toml` block cannot set up a Yazi that draws the columns, if it
    cannot. `readme.py` asks it of the README's blocks as well.

    One that does not parse is refused because Yazi meets it by discarding
    the whole file and running on its preset, after a prompt -- measured on
    26.9.1 for a `theme.toml`. `line` is where the block's first line sits
    on its page, so a parse error names the line there rather than one
    counted from the block.
    """
    try:
        parsed = tomllib.loads("\n" * (line - 1) + block)
    except tomllib.TOMLDecodeError as error:
        return f"does not parse: {error}"
    # `mgr = 1` parses too, and `in` would raise on it rather than refuse.
    mgr = parsed.get("mgr")
    if block.startswith(YAZI) and (
        not isinstance(mgr, dict) or "linemode" not in mgr
    ):
        return (
            "sets no `[mgr] linemode`, which leaves Yazi's preset `none`, "
            "so nothing would be drawn in the columns"
        )
    return None


def picture_problem(block: str, line: int = 1) -> str | None:
    """Why a `.toml` block cannot be drawn, if it cannot: what `toml_problem`
    says, or a theme with `[icon]`, which only the pictures refuse -- the
    README's is taken with a Nerd Font, icons and all."""
    if problem := toml_problem(block, line):
        return problem
    if block.startswith(THEME) and "icon" in tomllib.loads(block):
        return "themes `[icon]`, which the pictures switch off themselves"
    return None


def asking(line: str) -> tuple[str, str | int] | None:
    """What a line above an image asks of its picture, if it asks anything:
    the `Example` field it fills, which one picture fills once, and the
    value."""
    if line in ASKED:
        return "asked", line
    for field, (pattern, read) in FILLED.items():
        if found := pattern.match(line):
            return field, read(found.group(1))
    return None


def examples(text: str) -> list[Example]:
    """Every picture on one page, with its blocks.

    A block belongs to the next image below it, and so does a line asking
    something of the picture, indented or not. An image with no `init.lua`
    block since the one before it is refused, since there would be nothing to
    draw, and so is a second block for one file, or a second line asking the
    same thing: which of the two is the picture's would be a guess. So is a
    block or an asking line with no image under it before the next heading or
    the end of the page: carried on, it would be drawn into the next section's
    picture, and the digest would agree with it.
    """
    found: list[Example] = []
    blocks: dict[str, str] = {}
    asks: dict[str, tuple[str, str | int]] = {}

    def nothing_left(at: str) -> None:
        left = [*blocks, *(line for line, _ in asks.values())]
        if left:
            named = ", ".join(f"`{name}`" for name in left)
            raise ValueError(f"{at}: {named} with no picture under it")

    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i].rstrip()
        if fenced := file_block(lines, i):
            end, name, block = fenced
            if name:
                if name in blocks:
                    raise ValueError(
                        f"line {i + 1}: a second `{name}` block before "
                        "the picture the first one is for"
                    )
                if name != INIT and (problem := picture_problem(block, i + 2)):
                    raise ValueError(f"line {i + 1}: the block {problem}")
                blocks[name] = block
            i = end + 1
            continue
        if HEADING.match(line):
            nothing_left(f"line {i + 1}")
        if ask := asking(line.lstrip()):
            kind, value = ask
            if kind in asks:
                raise ValueError(
                    f"line {i + 1}: {line.lstrip()} after `{asks[kind][0]}`, "
                    "for one picture"
                )
            asks[kind] = (line.lstrip(), value)
        elif ASKING.match(line):
            ways = ", ".join(f"`{way}`" for way in WAYS)
            raise ValueError(
                f"line {i + 1}: {line} is none of {ways}, the ways to ask "
                "something of a picture"
            )
        image = IMAGE.match(line)
        if image:
            if INIT not in blocks:
                raise ValueError(
                    f"line {i + 1}: {image.group(2)} has no `{INIT}` block "
                    "above it"
                )
            found.append(
                Example(
                    image.group(2),
                    image.group(1),
                    blocks[INIT],
                    blocks.get(THEME, ""),
                    blocks.get(YAZI, ""),
                    blocks.get(KEYMAP, ""),
                    **{field: value for field, (_, value) in asks.items()},
                )
            )
            blocks, asks = {}, {}
        i += 1
    nothing_left("the end of the page")
    return found


def gathered(pages: list[Path]) -> list[Example]:
    """Every picture on every page.

    Refused when two image lines name one file, wherever they are: each would
    be drawn over the other, and the page that lost would show a picture of
    the other's blocks.
    """
    found: list[Example] = []
    where: dict[str, str] = {}
    for page in pages:
        try:
            on_page = examples(page.read_text())
        except ValueError as error:
            raise ValueError(f"{page.name}: {error}") from None
        for example in on_page:
            if example.image in where:
                raise ValueError(
                    f"{page.name}: {example.image} is drawn by "
                    f"{where[example.image]} already"
                )
            where[example.image] = page.name
        found.extend(on_page)
    return found


def drawn_on(
    example: Example, grounds: list[tuple[str, str]]
) -> list[tuple[str, str]]:
    """The grounds `example` is drawn on, out of every one there is."""
    wanted = example.grounds
    if wanted is None:
        return grounds
    return [(name, hex) for name, hex in grounds if name in wanted]


def drawn_from(svg: str) -> str | None:
    """The digest an SVG this wrote says it was drawn from."""
    found = re.search(rf'{SOURCE}="([0-9a-f]+)"', svg)
    return found.group(1) if found else None


# --- the folder every picture is of -----------------------------------------

#: The folder's entries: a size each, `None` for a directory, and the date it
#: carries as `MMDDhhmm` of this year. This year's because `mtime` draws one as
#: a time of day, which is the form most of a real listing is in. The year
#: reaches the screen only where an example's `format` asks for it, and is
#: then whichever year the picture was redrawn in, so no name here carries a
#: date for it to contradict. Another year moves the dates apart only by where
#: a leap day or a clock change falls: far less than one of a gradient's 64
#: steps, though a file sitting on a step's edge can still cross it.
#:
#: One name is long, so a picture shows what a wide linemode costs: Yazi takes
#: the room out of the name rather than the columns. Long enough to be cut
#: beside `ls -l`'s four columns, and no longer, since a column measuring the
#: names spreads them between the shortest and this one.
FOLDER: dict[str, tuple[int | None, str]] = {
    "assets": (None, "09141802"),
    "docs": (None, "10021133"),
    "src": (None, "10091947"),
    "backup.tar.gz": (48_000_000, "06300200"),
    "cover.png": (2_100_000, "09141758"),
    "demo.mp4": (180_000_000, "08221510"),
    "holiday-photo-edited.jpg": (3_400_000, "10041432"),
    "install.sh": (3_200, "03110921"),
    "LICENSE": (1_070, "01050000"),
    "notes.md": (6_100, "10101026"),
    "README.md": (12_000, "10091952"),
    "report.pdf": (860_000, "07180845"),
}

#: The executables, so `permissions` has an `x` to draw.
EXECUTABLE = {"install.sh"}

#: The folder's name, which the parent pane draws among its siblings.
PROJECT = "project"

#: The folder's own folder, which a picture of three panes draws on the left:
#: the folder and the directories beside it, dated the same way.
SIBLINGS: dict[str, str] = {
    "dotfiles": "08300915",
    PROJECT: "10101026",
    "scratch": "10111710",
    "website": "05221340",
}

#: The entry git says each state of, for those not committed and clean, so
#: git.yazi has a sign to draw for each kind a folder usually holds.
GIT = {
    "staged": "README.md",
    "unstaged": "notes.md",
    "untracked": "report.pdf",
    "ignored": "backup.tar.gz",
}


def listed(screen: str) -> bool:
    """Whether the whole folder is on `screen`: a row for every entry.

    Counted rather than waited on by name, so no entry's name or place in the
    sort is load-bearing, and a name a wide linemode cuts short counts the
    same. At least as many rows rather than exactly, since a notification
    reaching below the last entry adds rows without taking any away, and what
    it says is the log's to report. It holds while `FOLDER` fits in the
    window's `HEIGHT` less the header and the status bar; past that, the rows
    scrolled off are never seen.
    """
    return len(file_rows(screen)) >= len(FOLDER)


def build_folder(root: Path) -> Path:
    """The folder a picture is taken in, under `root`.

    A directory holds a few files, so the hovered one -- which Yazi lists, and
    `size` then counts, and the preview pane draws -- has entries to count.
    Sizes are sparse, as `setup.sized` says why. Built under the umask
    `setup.build` states, so `permissions` draws the same modes whoever
    redraws the picture, and a repository, as `repository` says.
    """
    folder = root / "work" / PROJECT
    year = time.localtime().tm_year
    dated: dict[Path, str] = {}
    was = os.umask(0o022)
    try:
        for name, when in SIBLINGS.items():
            (folder.parent / name).mkdir(parents=True)
            dated[folder.parent / name] = when
        for name, (size, when) in FOLDER.items():
            path = folder / name
            if size is None:
                path.mkdir()
                for n in range(3):
                    (path / f"{name}-{n}").write_bytes(b"x")
                    dated[path / f"{name}-{n}"] = when
            else:
                fixture.sized(path, size)
            if name in EXECUTABLE:
                path.chmod(0o755)
            dated[path] = when
        repository(folder)
    finally:
        os.umask(was)
    # After everything is created, because creating an entry moves its
    # directory's mtime: the deepest first, for the same reason.
    for path, when in sorted(dated.items(), key=lambda kv: -len(kv[0].parts)):
        fixture.stamp(path, fixture.epoch(f"{year}{when}"))
    # Every mtime moved since the index recorded it, so a `git status` would
    # hash every file again -- 0.24s a call, measured, against 0.01s once
    # refreshed -- and git.yazi runs it with `--no-optional-locks`, which never
    # writes the refresh back. Its signs would then land after the screen had
    # already held still long enough to be taken.
    git(folder, "update-index", "-q", "--refresh")
    return folder


#: Git run with nobody's configuration, so a redraw does not depend on whose
#: machine it is on: a global hook or signing would fail the commit. The
#: ignore and attributes files are named too, because git reads the default
#: ones under `~/.config/git` with `GIT_CONFIG_GLOBAL` set, measured on git
#: 2.54 -- so whoever redraws would decide which files are committed, and
#: which sign git.yazi draws beside each.
GIT_ENV = {
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_NOSYSTEM": "1",
    "GIT_CONFIG_COUNT": "2",
    "GIT_CONFIG_KEY_0": "core.excludesFile",
    "GIT_CONFIG_VALUE_0": os.devnull,
    "GIT_CONFIG_KEY_1": "core.attributesFile",
    "GIT_CONFIG_VALUE_1": os.devnull,
}


def as_nobody(case: unittest.TestCase) -> None:
    """Run the rest of `case` with every git it starts as nobody.

    No GIT_DIR, GIT_INDEX_FILE or the like from whatever ran the suite, or
    that git would work on that repository instead, and `GIT_ENV` over the
    rest, so a hook, a template or an ignore file of whoever runs it cannot
    reach one either. HOME stays, because a git that is a mise shim finds
    its installs through it. Undone when `case` ends.
    """
    environ = mock.patch.dict(os.environ)
    environ.start()
    case.addCleanup(environ.stop)
    for key in [key for key in os.environ if key.startswith("GIT_")]:
        del os.environ[key]
    os.environ.update(GIT_ENV)


def git(folder: Path, *args: str) -> None:
    """Run git on `folder`'s repository, as nobody."""
    run(
        [
            "git",
            "-C",
            str(folder),
            "-c",
            "user.name=supaline",
            "-c",
            "user.email=supaline@example.invalid",
            *args,
        ],
        env=GIT_ENV,
    )


def repository(folder: Path, states: dict[str, str] = GIT) -> None:
    """Make `folder` a repository holding `states`: everything else
    committed, an ignored file written into `.gitignore`, a file `added` if
    one is named, and each change one byte, so no size moves. Hidden files
    are not listed, so `.git` and `.gitignore` are on no picture."""

    def touched(name: str) -> None:
        with (folder / name).open("r+b") as f:
            f.write(b"x")

    added = [states["added"]] if "added" in states else []
    (folder / ".gitignore").write_text(states["ignored"] + "\n")
    git(folder, "init", "-q")
    git(
        folder,
        "add",
        "--all",
        "--",
        ".",
        *(f":!{name}" for name in [states["untracked"], *added]),
    )
    git(folder, "commit", "-q", "-m", "the folder")
    touched(states["unstaged"])
    touched(states["staged"])
    git(folder, "add", "--", states["staged"], *added)


# --- taking the picture ------------------------------------------------------


#: Where a plugin an example requires besides supaline is linked from: where
#: `ya pkg add` puts it, and where `.luarc.json` already reads `types.yazi`.
#: Whatever revision is installed there is what the picture draws.
PLUGINS = Path.home() / ".config" / "yazi" / "plugins"
REQUIRE = re.compile(r"""\brequire\s*\(?\s*["']([\w.-]+)["']""")


def installed(name: str) -> Path:
    """Where `ya pkg add` puts the plugin `name`."""
    return PLUGINS / f"{name}.yazi"


def required(*inits: str) -> set[str]:
    """The plugins these `init.lua`s require besides supaline.

    Read before any Yazi starts, so a plugin missing from `PLUGINS` is
    refused rather than drawn without. A plugin named only in a `run =` of
    `yazi.toml` or the keymap, or required only by another plugin, is not
    found this way and is not linked.

    Each text is its own argument, since a bare `str` in place of a list
    of them would be read a character at a time, and require nothing.
    """
    return {name for init in inits for name in REQUIRE.findall(init)} - {
        "supaline"
    }


def configure(root: Path, plugins: set[str]) -> None:
    """What every picture's Yazi shares under `root/config`: the plugin,
    linked to this checkout, and `plugins`, linked from `PLUGINS`. `capture`
    writes the rest."""
    config = root / "config"
    (config / "plugins").mkdir(parents=True)
    (config / "plugins" / "supaline.yazi").symlink_to(ROOT)
    for name in plugins:
        (config / "plugins" / f"{name}.yazi").symlink_to(installed(name))


def capture(
    root: Path, folder: Path, example: Example
) -> list[tuple[str, str]]:
    """The screens a Yazi draws on `folder` under `example`, with their
    colours, each with what to call it: one, or the one before the keys the
    example presses and the one after.

    Refused when Yazi logged an error, since a column that failed has drawn a
    picture of the failure -- and a notification over the list would be in
    the picture besides. Refused too when the folder never appeared, since
    what is on the screen then is a picture of Yazi starting, and when the
    keys changed nothing, since the two screens would be one picture twice.
    """
    config = root / "config"
    (config / "init.lua").write_text(example.init)
    (config / "theme.toml").write_text(example.theme + "\n" + NO_ICONS)
    (config / "yazi.toml").write_text(example.yazi or YAZI_TOML)
    (config / "keymap.toml").write_text(example.keymap)

    state = f"state-{Path(example.image).stem}"
    session = Session(f"supaline-examples-{PID}")
    session.start(
        ["yazi", str(folder)],
        # Git with nobody's configuration, for git.yazi's `git status`.
        env={**yazi_env(root, state, headless=True), **GIT_ENV},
        width=example.width or WIDTH,
        height=HEIGHT,
    )
    changed = True
    try:
        # What `wait_for` returns is the last screen it read, met or not.
        first = session.wait_for(listed, "the folder listed", timeout=STARTUP)
        shown = session.settle(colour=True)
        if example.pressed:
            session.keys(*example.pressed.split())
            session.wait_for(
                lambda screen: screen != shown,
                f"{example.pressed} pressed",
                colour=True,
            )
            # The settled screens compared, not the first that differed: a
            # which-key popup comes and goes between the keys of one press.
            after = session.settle(colour=True)
            changed = after != shown
            screens = [
                (f"before {example.pressed}", shown),
                (f"after {example.pressed}", after),
            ]
        else:
            screens = [("", shown)]
        # Quit rather than kill, so Yazi has the grace `quit` gives to finish
        # the log read below.
        session.quit("q")
    finally:
        session.kill()

    # The log first, since what it says is why the folder never appeared as
    # often as not, and is worth more than saying that it did not.
    log = yazi_log(root, state)
    trouble = troubles(log.read_text()) if log.exists() else []
    if trouble:
        refuse(
            f"examples: Yazi logged trouble drawing {example.image}:\n"
            + "\n".join(f"  {line.strip()}" for line in trouble[:5])
        )
    if not listed(first):
        refuse(
            f"examples: the folder's {len(FOLDER)} entries never all appeared "
            f"drawing {example.image}, in {STARTUP}s"
        )
    if not changed:
        refuse(
            f"examples: pressing {example.pressed} changed nothing on the "
            f"screen drawing {example.image}"
        )
    if not log.exists():
        refuse(
            f"examples: Yazi wrote no log drawing {example.image}, so nothing "
            "says the columns drew without error"
        )
    return screens


def file_rows(screen: str) -> list[list[sc.Cell]]:
    """The file list: every row between the header and the status bar, less
    the empty ones under the last entry -- empty but for the borders between
    the panes, where there are three."""
    rows = sc.pens(screen.rstrip("\n"))[1:-1]
    while rows and all(
        ch == sc.BAR or (ch == " " and pen == sc.Pen()) for ch, pen in rows[-1]
    ):
        rows.pop()
    return rows


# --- drawing it --------------------------------------------------------------

#: A cell, and the font it is drawn in: 0.6em across, the advance most
#: monospace faces have. Each run is placed at its own column, so a face that
#: is narrower or wider is off within a word and never past one.
CELL_W, CELL_H, FONT = 8.4, 18, 14
FAMILY = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace"

#: Around a tile's rows, the strip its name is written in, and between tiles.
#: The tiles are stacked one to a row, so each is drawn at its own size:
#: GitHub fits an image to the page's text column, and two across were shrunk
#: to about two thirds there, measured in Chrome, with the text the size of a
#: footnote.
PAD, TITLE, GAP = 12, 26, 16

#: The glyphs drawn as shapes rather than text: the half-discs either side of
#: the hovered row, U+E0B6 and U+E0B4, open towards the row. Any other
#: private-use character is refused, because the viewer has no font for it.
CAPS = {"\ue0b6": "left", "\ue0b4": "right"}


def label(name: str) -> str:
    """What a tile is called: its scheme, or the terminal nobody themed."""
    return name if name in SCHEMES else f"xterm, {name} ground"


def mix(a: str, b: str) -> str:
    """Halfway between two hexes, which is what a terminal dims towards."""
    pa = [int(a[i : i + 2], 16) for i in (1, 3, 5)]
    pb = [int(b[i : i + 2], 16) for i in (1, 3, 5)]
    return "#" + "".join(f"{(x + y) // 2:02x}" for x, y in zip(pa, pb))


def colours(pen: sc.Pen, palette: Scheme) -> tuple[str, str]:
    """A pen's foreground and background, as hexes in `palette`."""

    def resolve(value: str, default: str) -> str:
        if value.startswith("p"):
            return palette.named[int(value[1:])]
        return value or default

    fg = resolve(pen.fg, palette.fg)
    bg = resolve(pen.bg, palette.ground)
    if pen.reverse:
        fg, bg = bg, fg
    if pen.dim:
        fg = mix(fg, bg)
    return fg, bg


def cap(side: str, x: float, y: float, fill: str) -> str:
    """A half-disc filling one cell, its flat side towards the row."""
    if side == "left":
        start, sweep = x + CELL_W, 0
    else:
        start, sweep = x, 1
    return (
        f'<path d="M{start:g},{y:g} A{CELL_W:g},{CELL_H / 2:g} 0 0 {sweep} '
        f'{start:g},{y + CELL_H:g} Z" fill="{fill}"/>'
    )


def runs(row: list[sc.Cell]) -> list[tuple[int, str, sc.Pen]]:
    """A row as its runs of one pen, each with the column it starts at. A cap
    is a run of its own, since it is drawn as a shape."""
    found: list[tuple[int, str, sc.Pen]] = []
    col = 0
    for ch, pen in row:
        if ch not in CAPS and (
            0xE000 <= ord(ch) <= 0xF8FF or ord(ch) >= 0xF0000
        ):
            raise ValueError(
                f"U+{ord(ch):04X}: a private-use glyph no viewer has a font for"
            )
        last = found[-1] if found else None
        if last and last[2] == pen and CAPS.keys().isdisjoint({ch, last[1]}):
            found[-1] = (last[0], last[1] + ch, pen)
        else:
            found.append((col, ch, pen))
        col += sc.width(ch)
    return found


def drawn_run(
    at: int, text: str, pen: sc.Pen, y: float, palette: Scheme
) -> list[str]:
    """One run, at column `at` of the row whose top is `y`: its background
    where it has one of its own, then its text or its cap."""
    fg, bg = colours(pen, palette)
    x = PAD + at * CELL_W
    cells = sum(sc.width(ch) for ch in text)
    out = []
    if bg != palette.ground:
        out.append(
            f'<rect x="{x:g}" y="{y:g}" width="{cells * CELL_W:g}" '
            f'height="{CELL_H}" fill="{bg}"/>'
        )
    if text in CAPS:
        out.append(cap(CAPS[text], x, y, fg))
    elif not pen.hidden:
        # A word at a time, each at its own column: a browser drawing an SVG
        # as an image collapses a run of spaces whatever `xml:space` says,
        # measured in Chrome on GitHub, and a right-aligned column is spaces
        # first.
        attrs = [f'fill="{fg}"']
        if pen.bold:
            attrs.append('font-weight="bold"')
        if pen.italic:
            attrs.append('font-style="italic"')
        for word in re.finditer(r"\S+", text):
            wx = x + sum(sc.width(ch) for ch in text[: word.start()]) * CELL_W
            out.append(
                f'<text x="{wx:g}" y="{y + CELL_H * 0.72:g}" {" ".join(attrs)}>'
                f"{escape(word.group())}</text>"
            )
        # Lines as shapes, for the same reason: a terminal draws them under
        # the spaces too, and there are no spaces left to draw them under.
        for level, on in ((0.86, pen.underline), (0.5, pen.crossed)):
            if on:
                out.append(
                    f'<rect x="{x:g}" y="{y + CELL_H * level:g}" '
                    f'width="{cells * CELL_W:g}" height="1" fill="{fg}"/>'
                )
    return out


def tile_size(rows: list[list[sc.Cell]]) -> tuple[float, float]:
    """How wide and tall a tile of `rows` is, which every ground's is."""
    cols = max((sum(sc.width(ch) for ch, _ in row) for row in rows), default=0)
    return cols * CELL_W + 2 * PAD, TITLE + len(rows) * CELL_H + PAD


def tile(
    rows: list[list[sc.Cell]], name: str, palette: Scheme, shot: str = ""
) -> list[str]:
    """One ground's tile, at the origin: its ground, its name and which
    screen it is, and the rows."""
    w, h = tile_size(rows)
    # Edged in grey, so a tile on the ground of the page it sits on still has
    # a shape: GitHub draws a light page white and a dark one near black, the
    # two xterm grounds.
    out = [
        (
            f'<rect width="{w:g}" height="{h:g}" rx="8" '
            f'fill="{palette.ground}" stroke="#8888" stroke-width="1"/>'
        ),
        (
            f'<text x="{PAD}" y="{TITLE - 9}" font-size="12" '
            f'fill="{mix(palette.fg, palette.ground)}">'
            f"{escape(', '.join(filter(None, (label(name), shot))))}</text>"
        ),
    ]
    for r, row in enumerate(rows):
        for at, text, pen in runs(row):
            out.extend(drawn_run(at, text, pen, TITLE + r * CELL_H, palette))
    return out


def svg(
    shots: list[tuple[str, list[list[sc.Cell]]]],
    grounds: list[tuple[str, str]],
    example: Example,
) -> str:
    """The picture: a tile per ground and screen, stacked, each ground's
    screens together."""
    w = max(tile_size(rows)[0] for _, rows in shots)
    y = 0.0
    body = []
    for name, hex in grounds:
        for shot, rows in shots:
            body.append(f'<g transform="translate(0,{y:g})">')
            body.extend(tile(rows, name, scheme(name, hex), shot))
            body.append("</g>")
            y += tile_size(rows)[1] + GAP
    h = y - GAP
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w:g}" height="{h:g}" '
        f'viewBox="0 0 {w:g} {h:g}" role="img" {SOURCE}="{example.digest}" '
        f'font-family={quoteattr(FAMILY)} font-size="{FONT}">\n'
        f"<title>{escape(example.alt)}</title>\n"
        + "\n".join(body)
        + "\n</svg>\n"
    )


# --- the run -----------------------------------------------------------------

USAGE = "test/examples.py"


def main(argv: list[str]) -> int:
    if argv:
        refuse(f"usage: {USAGE}")

    need("tmux", "yazi", "git")
    catch_term()
    grounds = fixture.terminal_grounds(
        (fixture.FIXTURE / "init.lua").read_text()
    )
    if not grounds:
        refuse(
            "examples: no ground in the comment above `GROUND` in "
            "test/fixture/init.lua -- a name and a backticked hex each"
        )
    missing = {DARK_GROUND, LIGHT_GROUND} - {name for name, _ in grounds}
    if missing:
        refuse(
            f"examples: {', '.join(sorted(missing))} is not among the grounds "
            "test/fixture/init.lua names"
        )
    pages = sorted(PAGES.glob("*.md"))
    try:
        found = gathered(pages)
    except ValueError as error:
        refuse(f"examples: {PAGES.relative_to(ROOT)}/{error}")
    if not found:
        refuse(f"examples: no picture in {PAGES.relative_to(ROOT)}")
    plugins = required(*(example.init for example in found))
    for name in sorted(plugins):
        if not installed(name).is_dir():
            refuse(
                f"examples: an example requires {name}, and there is no "
                f"{installed(name)} to link it from: `ya pkg add` it"
            )

    print(f"examples: Yazi {yazi_version()}")

    fixture.clear(DIR)
    DIR.mkdir()
    (DIR / fixture.MARKER).touch()
    try:
        configure(DIR, plugins)
        folder = build_folder(DIR)
        for example in found:
            draw(DIR, folder, example, grounds)
    finally:
        fixture.clear(DIR)
    return 0


def draw(
    root: Path, folder: Path, example: Example, grounds: list[tuple[str, str]]
) -> None:
    """Take `example`'s picture and write it where its image line says."""
    screens = capture(root, folder, example)
    try:
        shots = [(shot, file_rows(screen)) for shot, screen in screens]
        if not all(rows for _, rows in shots):
            refuse(f"examples: {example.image} drew no rows")
        picture = svg(shots, drawn_on(example, grounds), example)
    except ValueError as error:
        refuse(f"examples: {example.image}: {error}")
    target = PAGES / example.image
    target.parent.mkdir(exist_ok=True)
    target.write_text(picture)
    print(f"examples: drew {target.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
