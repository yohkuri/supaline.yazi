"""`.github/scripts/install_types.py`, with the clone stood in for.

The script writes into a directory this repository does not own, so what is
worth holding is when it refuses to: a `YAZI_VERSION` other than the `@since`
this tree declares, and a directory that holds anything but the annotations
it would put there -- left exactly as it was found. `fetch` is the one part
that needs the network, and every test here replaces it.

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

from harness import ROOT

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


class TheVersion(unittest.TestCase):
    def test_is_the_one_this_tree_declares(self) -> None:
        self.assertIsNone(it.version_error())

    def root(self, first_line: str) -> Path:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        (Path(tmp.name) / "main.lua").write_text(first_line + "\nreturn {}\n")
        return Path(tmp.name)

    def test_another_since_names_both_and_what_to_move(self) -> None:
        error = it.version_error(self.root("--- @since 99.1.1"))
        self.assertIsNotNone(error)
        self.assertIn("@since 99.1.1", error)
        self.assertIn(f"annotations for {it.YAZI_VERSION}", error)
        self.assertIn("REV", error)

    def test_a_first_line_without_since_is_refused(self) -> None:
        error = it.version_error(self.root("-- not an annotation"))
        self.assertIsNotNone(error)
        self.assertIn("first line", error)

    def test_rev_is_a_full_hash(self) -> None:
        self.assertRegex(it.REV, r"\A[0-9a-f]{40}\Z")


class TheComparison(Scratch):
    def test_nothing_there_is_absent(self) -> None:
        self.assertEqual(it.state(self.src, self.dst), "absent")

    def test_a_copy_is_the_same(self) -> None:
        shutil.copytree(self.src, self.dst)
        self.assertEqual(it.state(self.src, self.dst), "same")

    def test_a_link_to_the_same_bytes_is_the_same(self) -> None:
        shutil.copytree(self.src, self.dst)
        (self.dst / "LICENSE").unlink()
        (self.dst / "LICENSE").symlink_to(self.src / "LICENSE")
        self.assertEqual(it.state(self.src, self.dst), "same")

    def test_other_bytes_are_different(self) -> None:
        shutil.copytree(self.src, self.dst)
        (self.dst / "main.lua").write_bytes(b"---@class (exact) Uri\n")
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_file_more_is_different(self) -> None:
        shutil.copytree(self.src, self.dst)
        write(self.dst, {"nested/column.lua": b""})
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_file_fewer_is_different(self) -> None:
        shutil.copytree(self.src, self.dst)
        (self.dst / "README.md").unlink()
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_broken_link_is_not_a_file(self) -> None:
        shutil.copytree(self.src, self.dst)
        (self.dst / "LICENSE").unlink()
        (self.dst / "LICENSE").symlink_to(self.tmp / "nowhere")
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_broken_link_more_is_different(self) -> None:
        shutil.copytree(self.src, self.dst)
        (self.dst / "column.lua").symlink_to(self.tmp / "nowhere")
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_link_to_a_directory_more_is_different(self) -> None:
        shutil.copytree(self.src, self.dst)
        (self.dst / "nested").symlink_to(self.tmp / "upstream")
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_file_in_its_place_is_different(self) -> None:
        self.dst.parent.mkdir(parents=True)
        self.dst.write_bytes(b"")
        self.assertEqual(it.state(self.src, self.dst), "different")

    def test_a_broken_link_in_its_place_is_different(self) -> None:
        self.dst.parent.mkdir(parents=True)
        self.dst.symlink_to(self.tmp / "nowhere")
        self.assertEqual(it.state(self.src, self.dst), "different")


class TheInstall(Scratch):
    def run_main(self, *argv: str) -> tuple[int, str, mock.Mock]:
        out = io.StringIO()
        with (
            mock.patch.dict(os.environ, {"HOME": str(self.tmp / "home")}),
            mock.patch.object(it, "fetch", return_value=self.src) as fetch,
            contextlib.redirect_stdout(out),
            contextlib.redirect_stderr(out),
        ):
            code = it.main(list(argv))
        return code, out.getvalue(), fetch

    def test_puts_the_annotations_where_luarc_looks(self) -> None:
        code, _, _ = self.run_main()
        self.assertEqual(code, 0)
        self.assertEqual(it.state(self.src, self.dst), "same")
        luarc = (ROOT / ".luarc.json").read_text()
        self.assertIn('"~/.config/yazi/plugins/types.yazi/"', luarc)

    def test_leaves_no_staging_beside_it(self) -> None:
        self.run_main()
        self.assertEqual(
            [p.name for p in self.dst.parent.iterdir()], ["types.yazi"]
        )

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
        self.assertEqual(
            [p.name for p in self.dst.parent.iterdir()], ["types.yazi"]
        )

    def test_a_failed_copy_leaves_nothing(self) -> None:
        with (
            mock.patch.object(it.shutil, "copytree", side_effect=OSError),
            self.assertRaises(OSError),
        ):
            self.run_main()
        self.assertEqual(list(self.dst.parent.iterdir()), [])

    def test_a_wrong_version_stops_before_fetching(self) -> None:
        with mock.patch.object(it, "version_error", return_value="no"):
            code, out, fetch = self.run_main()
        self.assertEqual(code, 1)
        self.assertIn("no", out)
        fetch.assert_not_called()
        self.assertFalse(os.path.lexists(self.dst))

    def test_check_alone_fetches_nothing(self) -> None:
        code, _, fetch = self.run_main("--check")
        self.assertEqual(code, 0)
        fetch.assert_not_called()
        self.assertFalse(os.path.lexists(self.dst))

    def test_anything_else_is_a_usage_error(self) -> None:
        code, out, fetch = self.run_main("--replace")
        self.assertEqual(code, 2)
        self.assertIn("usage", out)
        fetch.assert_not_called()


if __name__ == "__main__":
    unittest.main()
