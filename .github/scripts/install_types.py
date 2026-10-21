"""Yazi's own type annotations, at the revision this plugin is checked against.

`lua-language-server --check .` reads them from where `.luarc.json` points,
`~/.config/yazi/plugins/types.yazi/`, and fails all over the plugin without
them. CI installs them with this script and so does a contributor, so both
check against the same annotations:

    python3 .github/scripts/install_types.py

`yazi-rs/plugins` writes them for Yazi's main branch, with a commit for each
release and nothing that names one, so they are pinned by hash, beside the
Yazi they are for. The script refuses a `YAZI_VERSION` other than the
`@since` `main.lua` declares, so raising `@since` stops here until this file
moves with it. That is all it can say: that `REV` really is
`YAZI_VERSION`'s annotations is the pull request's to judge, by the upstream
commit that last touched `types.yazi` -- printed below on every run -- and
by the check passing on it.

Reading the version off upstream's commit subjects instead does not work.
They spell it `types for v26.9.1`, `type declarations for v26.8.15` and
`bump version to 26.1.22`, and many touch the annotations without naming one,
so a pattern that misses a spelling walks back to an older release and passes
rather than failing.

A directory already there with other contents is refused rather than
replaced. `ya pkg` records a hash of what it installed and refuses to touch a
package whose files no longer match it -- `delete` included, short of
`--discard`, read off 26.9.1's `yazi-cli` -- so overwriting one it manages
leaves it refusing to remove what it put there. Which directory it manages
depends on `YAZI_CONFIG_HOME` and `XDG_CONFIG_HOME`, while `.luarc.json`
reads this one path whatever they say, so the refusal names the path and
leaves the choice to whoever installed it. The one thing the comparison
passes over is `.DS_Store`, which Finder writes into any directory it shows
and no Lua reader looks at; any other extra file is refused, since a `.lua`
there can shadow one of this plugin's modules.

Standard library only, and Python 3.11 or newer, as the harnesses under
`test/` ask.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

YAZI_VERSION = "26.9.1"
REV = "4dc7f1b6458c2578f4494f10d468c68c1082214f"

UPSTREAM = "https://github.com/yazi-rs/plugins"

SINCE = "--- @since "
IGNORED = {".DS_Store"}


class FetchError(Exception):
    pass


def since(main_lua: Path) -> str | None:
    """What follows `--- @since ` on `main_lua`'s first line, as `tag.yml`
    reads it: the rest of the line, whatever it holds, and None for nothing.
    """
    with main_lua.open(encoding="utf-8", newline="") as f:
        line = f.readline().removesuffix("\n")
    if not line.startswith(SINCE):
        return None
    return line.removeprefix(SINCE) or None


def version_error(root: Path = ROOT) -> str | None:
    """Why `YAZI_VERSION` is not the Yazi `root` targets, or None if it is."""
    declared = since(root / "main.lua")
    if declared is None:
        return (
            "main.lua: the first line is not `--- @since <version>`, so the\n"
            "  Yazi these annotations are for cannot be checked against it."
        )
    if declared == YAZI_VERSION:
        return None
    return (
        f"main.lua declares @since {declared!r}, and install_types.py pins\n"
        f"  the annotations for {YAZI_VERSION}. Moving @since moves these\n"
        "  too: set YAZI_VERSION to it and REV to the yazi-rs/plugins commit\n"
        "  whose types.yazi is written for it."
    )


def contents(tree: Path) -> dict[str, bytes | None] | None:
    """Every entry under `tree` by relative path, a file by its bytes.

    A symlink to a file counts as the file, since that is what a reader of it
    gets; anything else that is not a directory -- a broken link, a link to a
    directory -- is None, so it never matches a file. None for `tree` itself
    when it is not a directory at all.
    """
    if not tree.is_dir():
        return None
    found: dict[str, bytes | None] = {}
    for top, dirs, files in os.walk(tree):
        for name in files + [d for d in dirs if Path(top, d).is_symlink()]:
            if name in IGNORED:
                continue
            path = Path(top, name)
            rel = path.relative_to(tree).as_posix()
            found[rel] = path.read_bytes() if path.is_file() else None
    return found


def state(src: Path, dst: Path) -> str:
    """`absent`, `same` or `different`: `dst` against the annotations `src`."""
    if not os.path.lexists(dst):
        return "absent"
    found = contents(dst)
    if found is None or found != contents(src):
        return "different"
    return "same"


def fetch(into: Path) -> Path:
    """`types.yazi` at `REV`, cloned under `into`."""
    clone = into / "plugins"

    def git(*args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(clone), *args],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    subprocess.run(
        ["git", "clone", "-q", "--filter=blob:none", "--no-checkout"]
        + [UPSTREAM, str(clone)],
        check=True,
    )
    git("checkout", "-q", REV)
    src = clone / "types.yazi"
    if not src.is_dir():
        raise FetchError(
            f"{UPSTREAM}@{REV[:7]} has no types.yazi directory, so REV in\n"
            "  install_types.py names the wrong commit. Nothing was installed."
        )
    last = git("log", "-1", "--format=%h %s", REV, "--", "types.yazi")
    print(f"{UPSTREAM}@{REV[:7]}: types.yazi last changed by {last}")
    return src


def install(src: Path, dst: Path) -> None:
    """Copy `src` to `dst` whole or not at all, links read through."""
    dst.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".types.yazi.", dir=dst.parent))
    try:
        shutil.copytree(src, staging, dirs_exist_ok=True)
        staging.rename(dst)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


def main(argv: list[str]) -> int:
    if argv:
        print("usage: install_types.py", file=sys.stderr)
        return 2
    error = version_error()
    if error:
        print(error, file=sys.stderr)
        return 1

    dst = Path.home() / ".config/yazi/plugins/types.yazi"
    with tempfile.TemporaryDirectory() as tmp:
        try:
            src = fetch(Path(tmp))
        except FetchError as e:
            print(e, file=sys.stderr)
            return 1
        found = state(src, dst)
        if found == "absent":
            install(src, dst)
            print(f"{dst}: installed the annotations for Yazi {YAZI_VERSION}.")
            return 0
        if found == "same":
            print(f"{dst}: already matches {REV[:7]}'s contents.")
            return 0
    print(
        f"{dst}: holds something other than {REV[:7]}'s annotations for\n"
        f"  Yazi {YAZI_VERSION}, and is left as it is. If you put it there,\n"
        "  remove it and run this again. If `ya pkg` did, run\n"
        "  `ya pkg delete yazi-rs/plugins:types` under the same\n"
        "  YAZI_CONFIG_HOME and XDG_CONFIG_HOME it was added with, then run\n"
        "  this again.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
