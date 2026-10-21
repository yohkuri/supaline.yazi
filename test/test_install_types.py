"""`.github/scripts/install_types.py`, with the clone stood in for.

The script writes into a directory this repository does not own, so what is
worth holding is when it refuses to: a `YAZI_VERSION` other than the `@since`
a tree declares, and a directory whose Lua is anything but the annotations it
would put there -- left exactly as it was found. `fetch` is the one part that
needs the network: the tests of `main` replace it, and its own are given a
repository on disk in place of yazi-rs/plugins.

    python3 -m unittest discover -s test -p 'test_*.py'
"""

from __future__ import annotations

import contextlib
import importlib.util
import io
import os
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from examples import GIT_ENV, git
from harness import ROOT, run

_spec = importlib.util.spec_from_file_location(
    "install_types", ROOT / ".github/scripts/install_types.py"
)
assert _spec and _spec.loader
it = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(it)

ANNOTATIONS = {
    "main.lua": b"---@class (exact) Url\n",
    "README.md": b"# types.yazi\n",
    "LICENSE": b"MIT\n",
}


def write(tree: Path, files: dict[str, bytes]) -> Path:
    for rel, body in files.items():
        (tree / rel).parent.mkdir(parents=True, exist_ok=True)
        (tree / rel).write_bytes(body)
    return tree


def snapshot(tree: Path) -> list[tuple[str, bool, bytes | str | None]]:
    """Every entry under `tree`, links unread, to see that nothing moved."""
    found = []
    for path in sorted(tree.rglob("*")):
        rel = path.relative_to(tree).as_posix()
        if path.is_symlink():
            found.append((rel, True, os.readlink(path)))
        elif path.is_file():
            found.append((rel, False, path.read_bytes()))
        else:
            found.append((rel, False, None))
    return found


class Scratch(unittest.TestCase):
    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.tmp = Path(tmp.name)
        self.src = write(self.tmp / "upstream/types.yazi", ANNOTATIONS)
        self.dst = self.tmp / "home/.config/yazi/plugins/types.yazi"

    def siblings(self) -> list[str]:
        """What sits beside the annotations, to see nothing was left there."""
        return [p.name for p in self.dst.parent.iterdir()]


class TheVersion(Scratch):
    def error(self, first_line: str) -> str:
        (self.tmp / "main.lua").write_text(first_line + "\nreturn {}\n")
        error = it.version_error(self.tmp)
        self.assertIsNotNone(error)
        return error

    def test_another_since_names_both(self) -> None:
        error = self.error("--- @since 99.1.1")
        self.assertIn("@since '99.1.1'", error)
        self.assertIn(f"annotations for {it.YAZI_VERSION}", error)
        self.assertIn("REV", error)

    def test_the_rest_of_the_line_is_the_version(self) -> None:
        error = self.error(f"--- @since {it.YAZI_VERSION}\r")
        self.assertIn(repr(f"{it.YAZI_VERSION}\r"), error)

    def test_an_empty_since_is_refused(self) -> None:
        self.assertIn("first line", self.error("--- @since "))

    def test_a_first_line_without_since_is_refused(self) -> None:
        self.assertIn("first line", self.error("-- not an annotation"))

    def test_the_same_since_passes(self) -> None:
        (self.tmp / "main.lua").write_text(f"--- @since {it.YAZI_VERSION}\n")
        self.assertIsNone(it.version_error(self.tmp))

    def test_rev_is_a_full_hash(self) -> None:
        self.assertRegex(it.REV, r"\A[0-9a-f]{40}\Z")


class TheComparison(Scratch):
    def copy(self) -> Path:
        shutil.copytree(self.src, self.dst)
        return self.dst

    def test_nothing_there_is_absent(self) -> None:
        self.assertEqual(it.state(self.src, self.dst), "absent")

    def test_a_copy_is_the_same(self) -> None:
        self.copy()
        self.assertEqual(it.state(self.src, self.dst), "same")

    def test_a_link_to_the_same_bytes_is_the_same(self) -> None:
        (self.copy() / "main.lua").unlink()
        (self.dst / "main.lua").symlink_to(self.src / "main.lua")
        self.assertEqual(it.state(self.src, self.dst), "same")

    def test_what_no_lua_reader_reads_is_passed_over(self) -> None:
        write(self.copy(), {"README.md": b"other\n", ".DS_Store": b"\0"})
        (self.dst / "LICENSE").unlink()
        self.assertEqual(it.state(self.src, self.dst), "same")

    def test_other_bytes_are_different(self) -> None:
        write(self.copy(), {"main.lua": b"---@class (exact) Uri\n"})
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_lua_file_more_is_different(self) -> None:
        write(self.copy(), {"nested/column.lua": b""})
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_hidden_lua_file_more_is_different(self) -> None:
        write(self.copy(), {".column.lua": b""})
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_lua_file_fewer_is_different(self) -> None:
        (self.copy() / "main.lua").unlink()
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_broken_link_is_not_a_file(self) -> None:
        (self.copy() / "main.lua").unlink()
        (self.dst / "main.lua").symlink_to(self.tmp / "nowhere")
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_broken_link_more_is_different(self) -> None:
        (self.copy() / "column.lua").symlink_to(self.tmp / "nowhere")
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_link_to_a_directory_more_is_different(self) -> None:
        (self.copy() / "nested").symlink_to(self.tmp / "upstream")
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_nothing_fetched_never_matches(self) -> None:
        self.dst.parent.mkdir(parents=True)
        self.dst.write_bytes(b"")
        self.assertEqual(it.state(self.tmp / "missing", self.dst), "different")

    def test_a_file_in_its_place_is_different(self) -> None:
        self.dst.parent.mkdir(parents=True)
        self.dst.write_bytes(b"")
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_broken_link_in_its_place_is_different(self) -> None:
        self.dst.parent.mkdir(parents=True)
        self.dst.symlink_to(self.tmp / "nowhere")
        self.assertEqual(it.state(self.src, self.dst), "different")


class TheInstall(Scratch):
    def run_main(
        self, *argv: str, failure: BaseException | None = None
    ) -> tuple[int, str, mock.Mock]:
        out = io.StringIO()
        with (
            mock.patch.dict(os.environ, {"HOME": str(self.tmp / "home")}),
            mock.patch.object(
                it, "fetch", return_value=self.src, side_effect=failure
            ) as fetch,
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(out),
        ):
            code = it.main(list(argv))
        return code, out.getvalue(), fetch

    def test_installs_where_luarc_looks_under_home(self) -> None:
        code, _, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(it.state(self.src, self.dst), "same")
        self.assertEqual(self.siblings(), ["types.yazi"])

    def test_a_matching_directory_is_left_alone(self) -> None:
        shutil.copytree(self.src, self.dst)
        before = snapshot(self.dst)
        code, out, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertIn("already matches", out)
        self.assertEqual(snapshot(self.dst), before)

    def test_a_different_directory_is_refused_and_left_alone(self) -> None:
        shutil.copytree(self.src, self.dst)
        (self.dst / "main.lua").write_bytes(b"-- an older release\n")
        before = snapshot(self.dst)
        code, out, _ = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn(str(self.dst), out)
        self.assertIn("ya pkg delete yazi-rs/plugins:types", out)
        self.assertEqual(snapshot(self.dst), before)
        self.assertEqual(self.siblings(), ["types.yazi"])

    def test_a_failed_copy_leaves_nothing(self) -> None:
        with (
            mock.patch.object(it.shutil, "copytree", side_effect=OSError),
            self.assertRaises(OSError),
        ):
            self.run_main()
        self.assertEqual(self.siblings(), [])

    def test_a_wrong_version_stops_before_fetching(self) -> None:
        with mock.patch.object(it, "version_error", return_value="no"):
            code, out, fetch = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("no", out)
        fetch.assert_not_called()
        self.assertFalse(os.path.lexists(self.dst))

    def test_a_failed_fetch_installs_nothing(self) -> None:
        shutil.copytree(self.src, self.dst)
        before = snapshot(self.dst)
        with self.assertRaises(SystemExit):
            self.run_main(failure=SystemExit("gone"))
        self.assertEqual(snapshot(self.dst), before)

    def test_an_argument_is_a_usage_error(self) -> None:
        code, out, fetch = self.run_main("--replace")
        self.assertEqual(code, 2)
        self.assertIn("usage", out)
        fetch.assert_not_called()


class TheFetch(Scratch):
    """`fetch` against a repository on disk standing in for yazi-rs/plugins."""

    def setUp(self) -> None:
        super().setUp()
        # No GIT_DIR or the like from whatever ran the suite, a hook included.
        env = mock.patch.dict(os.environ)
        env.start()
        self.addCleanup(env.stop)
        for key in [key for key in os.environ if key.startswith("GIT_")]:
            del os.environ[key]

    def upstream(self, files: dict[str, bytes]) -> tuple[str, str]:
        repo = write(self.tmp / "remote", files)
        git(repo, "init", "-q", "-b", "main")
        git(repo, "config", "uploadpack.allowFilter", "true")
        git(repo, "add", "-A")
        git(repo, "commit", "-q", "-m", "feat: types for v0.0.0")
        rev = run(["git", "-C", str(repo), "rev-parse", "HEAD"], env=GIT_ENV)
        return repo.as_uri(), rev.stdout.strip()

    def fetch(self, url: str, rev: str) -> Path:
        with (
            mock.patch.object(it, "UPSTREAM", url),
            mock.patch.object(it, "REV", rev),
            contextlib.redirect_stdout(io.StringIO()),
        ):
            return it.fetch(self.tmp / "work")

    def test_takes_types_yazi_at_rev(self) -> None:
        url, rev = self.upstream(
            {f"types.yazi/{k}": v for k, v in ANNOTATIONS.items()}
            | {"git.yazi/main.lua": b"return {}\n"}
        )
        src = self.fetch(url, rev)
        self.assertEqual(snapshot(src), snapshot(self.src))

    def test_a_rev_without_types_yazi_is_refused(self) -> None:
        url, rev = self.upstream({"git.yazi/main.lua": b"return {}\n"})
        with self.assertRaises(SystemExit) as caught:
            self.fetch(url, rev)
        self.assertIn("no types.yazi", str(caught.exception.code))


if __name__ == "__main__":
    unittest.main()
