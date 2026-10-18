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
from harness import (
    REFUSED,
    SUN_PATH,
    Session,
    own_socket,
    read_log,
    troubles,
    yazi_env,
)

#: What `own_socket` puts after the scratch directory for its first Yazi, as
#: long as what it puts there for any of its first thousand.
TAIL = f"/000/yazi+{os.getuid()}/.dds.sock"


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
        # Joining an empty name leaves the directory as it was, so a pad of
        # none or less leaves every spec below about a path it does not say.
        self.assertGreater(pad, 0, "the temp directory is too long")
        return self.dir / ("d" * pad)

    def claimed(self, dir: Path, count: int) -> Path:
        """`dir`, with the first `count` runtime directories already taken."""
        # Made here rather than claimed through `own_socket`, whose scan from
        # zero would make a thousand claims take seconds.
        for n in range(count):
            (dir / f"{n:03}").mkdir(parents=True)
        return dir

    def refused(self, dir: Path) -> str:
        """What `own_socket` said, having refused `dir` as a harness does."""
        with (
            contextlib.redirect_stderr(io.StringIO()) as said,
            self.assertRaises(SystemExit) as stopped,
        ):
            own_socket(dir)
        self.assertEqual(stopped.exception.code, REFUSED)
        self.assertIn("shorter TMPDIR", said.getvalue())
        return said.getvalue()

    def test_every_yazi_gets_a_runtime_directory_of_its_own(self) -> None:
        dirs = {own_socket(self.dir)["XDG_RUNTIME_DIR"] for _ in range(3)}
        self.assertEqual(len(dirs), 3)

    def test_a_directory_still_there_is_not_handed_out(self) -> None:
        # The claim is read off the disk, as `own_socket` says: a count kept
        # in this process passes the spec above and fails this one.
        runtime = own_socket(self.claimed(self.dir, 1))["XDG_RUNTIME_DIR"]
        self.assertEqual(runtime, str(self.dir / "001"))

    def test_a_relative_scratch_directory_is_made_absolute(self) -> None:
        # Yazi ignores a relative `XDG_RUNTIME_DIR` and goes back to the
        # shared socket under the temp directory.
        with contextlib.chdir(self.dir):
            runtime = own_socket(Path("s"))["XDG_RUNTIME_DIR"]
        self.assertTrue(os.path.isabs(runtime))

    def test_a_path_past_sun_path_is_refused_at_the_first_yazi(self) -> None:
        # At the first Yazi, whose path is as long as the thousandth's.
        said = self.refused(self.padded(SUN_PATH))
        self.assertIn("/000/yazi+", said)

    def test_a_path_inside_sun_path_is_handed_over(self) -> None:
        # A byte short, so a first directory named `0000` would refuse it.
        dir = self.padded(SUN_PATH - 1)
        runtime = own_socket(dir)["XDG_RUNTIME_DIR"]
        self.assertEqual(runtime, str(dir / "000"))

    def test_the_thousandth_yazi_fits_where_the_first_did(self) -> None:
        dir = self.claimed(self.padded(SUN_PATH - 1), 999)
        runtime = own_socket(dir)["XDG_RUNTIME_DIR"]
        self.assertEqual(runtime, str(dir / "999"))

    def test_the_1001st_yazi_is_measured_at_its_own_number(self) -> None:
        # Past three digits the path grows, so the number itself has to fit.
        said = self.refused(self.claimed(self.padded(SUN_PATH - 1), 1000))
        self.assertIn("/1000/yazi+", said)

    def test_a_headless_yazi_never_shares_the_users_socket(self) -> None:
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/1"}):
            env = yazi_env(self.dir, "state", headless=True)
        self.assertEqual(env["XDG_RUNTIME_DIR"], str(self.dir / "000"))

    def test_a_persons_yazi_keeps_the_users_runtime_directory(self) -> None:
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": "/run/user/1"}):
            env = yazi_env(self.dir, "state", headless=False)
        self.assertNotIn("XDG_RUNTIME_DIR", env)

    def test_only_a_headless_yazi_has_less_options_taken_away(self) -> None:
        with mock.patch.dict(os.environ, {"LESS": "-N"}):
            self.assertEqual(
                yazi_env(self.dir, "state", headless=True)["LESS"], ""
            )
            self.assertNotIn(
                "LESS", yazi_env(self.dir, "state", headless=False)
            )

    def test_a_persons_yazi_with_none_to_keep_gets_its_own(self) -> None:
        with mock.patch.dict(os.environ):
            os.environ.pop("XDG_RUNTIME_DIR", None)
            env = yazi_env(self.dir, "state", headless=False)
        self.assertEqual(env["XDG_RUNTIME_DIR"], str(self.dir / "000"))


class Targets(unittest.TestCase):
    def test_a_session_is_named_exactly_and_as_a_pane(self) -> None:
        # A bare name is a prefix to tmux, and `send-keys` and `capture-pane`
        # refuse `=name` without the `:`, measured on tmux 3.8.
        self.assertEqual(
            Session("supaline-e2e-123").target, "=supaline-e2e-123:"
        )


#: Lines as 26.9.1 logged them in Ubuntu 24.04 under Docker, one of each
#: `MACHINE` names, with the line after each.
MACHINE_LOG = """\
  2026-10-18T13:38:24.531263Z ERROR yazi_fs::mounts::linux: Cannot read /dev/disk/by-label
    at yazi-fs/src/mounts/linux.rs:147

  2026-10-18T13:38:24.533541Z ERROR yazi_emulator::mux: Failed to configure tmux passthrough and input buffer: status ExitStatus(unix_wait_status(256)), stderr: invalid option: input-buffer-size

    at yazi-emulator/src/mux.rs:40

  2026-10-18T13:38:24.590666Z ERROR yazi_scheduler::fetch::fetch: Error when running fetcher 'mime.local':
Custom { kind: Other, code: None, message: "Failed to determine MIME type for `/tmp/supaline-e2e.1/fixture/data/link-broken`" }
    at yazi-scheduler/src/fetch/fetch.rs:39
"""


class Logs(unittest.TestCase):
    def test_what_yazi_logs_about_the_machine_is_set_apart(self) -> None:
        kept, machine = read_log(MACHINE_LOG)
        self.assertEqual(kept, [])
        self.assertEqual(len(machine), 3)

    def test_a_plugins_error_is_kept_beside_them(self) -> None:
        mine = (
            "  2026-10-18T13:39:05.440974Z ERROR yazi_plugin::utils::log: "
            '"supaline: column `torn_render` threw from its `render`."'
        )
        self.assertEqual(troubles(f"{MACHINE_LOG}{mine}\n"), [mine])

    def test_a_mime_failure_on_any_other_file_is_kept(self) -> None:
        # The pattern names the fixture's one link to nothing, so the fetcher
        # failing on a file that exists still fails the run.
        other = MACHINE_LOG.replace("link-broken", "large.bin")
        self.assertEqual(len(troubles(other)), 1)

    def test_a_fetcher_of_another_name_is_kept(self) -> None:
        # A plugin's fetcher is logged under its own name, so one that fails
        # on the same file is never taken for Yazi's.
        other = MACHINE_LOG.replace("mime.local", "supaline")
        self.assertEqual(len(troubles(other)), 1)


if __name__ == "__main__":
    unittest.main()
