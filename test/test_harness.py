"""What the harness hands tmux and Yazi, held where CI can see it.

`e2e.py` and `examples.py` are not in CI, and neither breaks loudly when what
is below drifts: a shared socket fails one run in several, and a session
named by prefix only reaches another run's when two are alive at once.

    python3 -m unittest discover -s test -p 'test_*.py'
"""

from __future__ import annotations

import contextlib
import io
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

# First, because importing it is what refuses too old a Python.
import harness  # noqa: F401
from harness import SUN_PATH, Session, own_socket, yazi_env

#: What `own_socket` puts after the scratch directory, at the three digits it
#: measures the path at.
TAIL = f"/run/000/yazi+{os.getuid()}/.dds.sock"


class Sockets(unittest.TestCase):
    def setUp(self) -> None:
        # A directory of the test's own, since `own_socket` claims what it
        # hands out with `mkdir`.
        made = tempfile.TemporaryDirectory()
        self.addCleanup(made.cleanup)
        self.dir = Path(made.name)

    def padded(self, length: int) -> Path:
        """A scratch directory that puts the socket's path at `length` bytes."""
        pad = length - len(os.fsencode(self.dir)) - len(TAIL) - 1
        return self.dir / ("d" * pad)

    def test_every_yazi_gets_a_runtime_directory_of_its_own(self) -> None:
        dirs = {own_socket(self.dir)["XDG_RUNTIME_DIR"] for _ in range(3)}
        self.assertEqual(len(dirs), 3)

    def test_a_directory_another_run_left_is_not_handed_out(self) -> None:
        # `gallery.py` and `manual.py` keep one scratch directory between runs.
        (self.dir / "run" / "0").mkdir(parents=True)
        runtime = own_socket(self.dir)["XDG_RUNTIME_DIR"]
        self.assertEqual(runtime, str(self.dir / "run" / "1"))

    def test_a_relative_scratch_directory_is_made_absolute(self) -> None:
        # Yazi ignores a relative `XDG_RUNTIME_DIR` and goes back to the
        # shared socket under the temp directory.
        with contextlib.chdir(self.dir):
            runtime = own_socket(Path("s"))["XDG_RUNTIME_DIR"]
        self.assertTrue(os.path.isabs(runtime))

    def test_a_path_past_sun_path_is_refused_at_the_first_yazi(self) -> None:
        # At the first Yazi's one digit the path is two bytes short of this,
        # and still refused, rather than at the tenth.
        with (
            contextlib.redirect_stderr(io.StringIO()) as said,
            self.assertRaises(SystemExit),
        ):
            own_socket(self.padded(SUN_PATH))
        self.assertIn("shorter TMPDIR", said.getvalue())

    def test_a_path_inside_sun_path_is_handed_over(self) -> None:
        dir = self.padded(SUN_PATH - 1)
        runtime = own_socket(dir)["XDG_RUNTIME_DIR"]
        self.assertEqual(runtime, str(dir / "run" / "0"))

    def test_a_headless_yazi_never_shares_the_users_socket(self) -> None:
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/1"}):
            env = yazi_env(self.dir, "state", headless=True)
        self.assertEqual(env["XDG_RUNTIME_DIR"], str(self.dir / "run" / "0"))

    def test_a_persons_yazi_keeps_the_users_runtime_directory(self) -> None:
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/1"}):
            env = yazi_env(self.dir, "state", headless=False)
        self.assertNotIn("XDG_RUNTIME_DIR", env)

    def test_a_persons_yazi_with_none_to_keep_gets_its_own(self) -> None:
        with mock.patch.dict(os.environ):
            os.environ.pop("XDG_RUNTIME_DIR", None)
            env = yazi_env(self.dir, "state", headless=False)
        self.assertEqual(env["XDG_RUNTIME_DIR"], str(self.dir / "run" / "0"))


class Targets(unittest.TestCase):
    def test_a_session_is_named_exactly_and_as_a_pane(self) -> None:
        # A bare name is a prefix to tmux, and `send-keys` and `capture-pane`
        # refuse `=name` without the `:`, measured on tmux 3.8.
        self.assertEqual(
            Session("supaline-e2e-123").target, "=supaline-e2e-123:"
        )


if __name__ == "__main__":
    unittest.main()
