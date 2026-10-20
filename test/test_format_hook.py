"""`.claude/hooks/format-lua.sh`, against a stylua that only records.

The hook formats with whatever stylua is on `PATH` and refuses when that is
not the one `mise.toml` pins, so what is worth holding is where it looks for
the pin, which files it takes, the directory and arguments stylua gets, and
that every refusal reaches the agent. A stand-in on `PATH` answers `--version`
with what a test asks for and writes down the rest, so none of this needs a
real stylua. Every run goes through the command `.claude/settings.json` gives
Claude Code, so that command is held too.

    python3 -m unittest discover -s test -p 'test_*.py'
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from examples import GIT_ENV, git
from harness import ROOT

HOOK = ROOT / ".claude/hooks/format-lua.sh"

#: What Claude Code runs after a Write or an Edit.
COMMAND = json.loads((ROOT / ".claude/settings.json").read_text())["hooks"][
    "PostToolUse"
][0]["hooks"][0]["command"]

#: Answers `--version` with $VERSION, fails the way a file it cannot parse
#: does when $BROKEN is set, and otherwise records where it ran and each
#: argument it was given on a line of its own.
STYLUA = """#!/bin/sh
[ "$1" = --version ] && { echo "stylua $VERSION"; exit; }
[ -n "${BROKEN:-}" ] && { echo "error: could not parse $*" >&2; exit 1; }
printf '%s\\n' "$(pwd -P)" "$@" > "$CALLED"
"""

#: Git, except that `ls-files` fails the way it does when Git cannot say.
GIT = """#!/bin/sh
[ "$3" = ls-files ] && exit 128
exec {git} "$@"
"""

#: Everything `COMMAND` and the hook run, stylua and the builtins aside.
TOOLS = ["sh", "jq", "git", "cat", "dirname", "basename", "sed"]

PIN = '[tools]\nstylua = "9.9.9"\n'


def args(rel: str) -> list[str]:
    """What stylua is given to format `rel`."""
    return ["--config-path", "stylua.toml", "--respect-ignores", "--", rel]


@unittest.skipUnless(shutil.which("jq") and shutil.which("git"), "needs both")
class TheHook(unittest.TestCase):
    def setUp(self) -> None:
        made = tempfile.TemporaryDirectory()
        self.addCleanup(made.cleanup)
        self.tmp = Path(made.name).resolve()
        # No GIT_DIR, GIT_INDEX_FILE or the like from whatever ran the suite,
        # or the git here would work on that repository instead of these.
        environ = mock.patch.dict(os.environ)
        environ.start()
        self.addCleanup(environ.stop)
        for key in [key for key in os.environ if key.startswith("GIT_")]:
            del os.environ[key]
        # Git as nobody, so a template, a hook or an ignore file of whoever
        # runs this cannot reach the repositories. HOME stays, because a jq or
        # a git that is a mise shim finds its installs through it.
        self.env = dict(os.environ, **GIT_ENV)
        self.root = self.repository("repo")
        # Where `COMMAND` looks for the hook: CLAUDE_PROJECT_DIR is this.
        (self.root / ".claude/hooks").mkdir(parents=True)
        shutil.copy(HOOK, self.root / ".claude/hooks")
        self.called = self.tmp / "called"
        self.path = self.bin("bin")

    def bin(
        self,
        name: str,
        without: tuple[str, ...] = (),
        stand_ins: dict[str, str] | None = None,
    ) -> str:
        """A `PATH` of what the hook runs and nothing else: `TOOLS` and the
        stylua stand-in, less `without`, with `stand_ins` written in place of
        the tools they name."""
        bin_ = self.tmp / name
        bin_.mkdir()
        scripts = {"stylua": STYLUA, **(stand_ins or {})}
        for tool in TOOLS:
            if tool not in without and tool not in scripts:
                (bin_ / tool).symlink_to(shutil.which(tool))
        for tool, script in scripts.items():
            if tool not in without:
                (bin_ / tool).write_text(script)
                (bin_ / tool).chmod(0o755)
        return str(bin_)

    def repository(self, name: str) -> Path:
        root = self.tmp / name
        (root / "sub").mkdir(parents=True)
        git(root, "init", "--quiet")
        (root / "sub/a.lua").write_text("return 1\n")
        return root

    def hook(
        self,
        file: Path,
        version: str = "9.9.9",
        pins: str | None = PIN,
        payload: str = "tool_input",
        path: str | None = None,
        **extra: str,
    ) -> subprocess.CompletedProcess[str]:
        if pins is not None:
            (self.root / "mise.toml").write_text(pins)
        self.called.unlink(missing_ok=True)
        shape = {
            "tool_input": {"tool_input": {"file_path": str(file)}},
            "tool_response": {"tool_response": {"filePath": str(file)}},
        }[payload]
        env = dict(
            self.env,
            CLAUDE_PROJECT_DIR=str(self.root),
            VERSION=version,
            CALLED=str(self.called),
            PATH=self.path if path is None else path,
            **extra,
        )
        # From somewhere else, as a session working in another checkout is.
        return subprocess.run(
            [shutil.which("sh"), "-c", COMMAND],
            check=False,
            cwd=self.tmp,
            env=env,
            input=json.dumps(shape),
            capture_output=True,
            text=True,
            timeout=10,
        )

    def stylua_got(self) -> list[str] | None:
        if not self.called.exists():
            return None
        return self.called.read_text().splitlines()

    def test_reads_this_repository_pin(self):
        result = self.hook(
            self.root / "sub/a.lua",
            version="0.0.0",
            pins=(ROOT / "mise.toml").read_text(),
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertRegex(
            result.stderr,
            r"stylua 0\.0\.0 is installed, but CI runs \d+\.\d+\.\d+,",
        )
        self.assertIsNone(self.stylua_got())

    def test_formats_from_the_file_checkout_when_the_pin_matches(self):
        for pins in [
            PIN,
            '[tools]\nstylua="9.9.9"  # the formatter\n',
            '[tools]\nstylua = "9.9.9"\n[tasks]\nstylua = "stylua ."\n',
        ]:
            for payload in ["tool_input", "tool_response"]:
                with self.subTest(pins=pins, payload=payload):
                    result = self.hook(
                        self.root / "sub/a.lua", pins=pins, payload=payload
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(
                        self.stylua_got(), [str(self.root), *args("sub/a.lua")]
                    )

    def test_formats_wherever_in_the_checkout_the_file_is(self):
        # The top of the checkout, where Git's prefix is an empty line, and
        # names a split on whitespace would get wrong.
        for rel in ["a.lua", "sub dir/a.lua", " sp/a.lua"]:
            with self.subTest(rel=rel):
                (self.root / rel).parent.mkdir(exist_ok=True)
                (self.root / rel).write_text("return 1\n")
                result = self.hook(self.root / rel)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    self.stylua_got(), [str(self.root), *args(rel)]
                )

    def test_formats_what_only_one_contributor_ignores(self):
        # CI's checkout has neither, so `stylua --check .` there reads both.
        (self.root / ".git/info").mkdir(exist_ok=True)
        (self.root / ".git/info/exclude").write_text("local/\n")
        (self.tmp / "excludes").write_text("mine/\n")
        for rel in ["local/a.lua", "mine/a.lua"]:
            with self.subTest(rel=rel):
                (self.root / rel).parent.mkdir(exist_ok=True)
                (self.root / rel).write_text("return 1\n")
                result = self.hook(
                    self.root / rel,
                    GIT_CONFIG_VALUE_0=str(self.tmp / "excludes"),
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(
                    self.stylua_got(), [str(self.root), *args(rel)]
                )

    def test_refuses_without_a_pin(self):
        for pins in [
            '[tools]\nlua = "5.5.1"\n',
            '[tools]\n# stylua = "9.9.9"\n',
            '[tasks]\nstylua = "9.9.9"\n',
        ]:
            with self.subTest(pins=pins):
                result = self.hook(self.root / "sub/a.lua", pins=pins)
                self.assertEqual(result.returncode, 2)
                self.assertIn(
                    "could not read the stylua version", result.stderr
                )
                self.assertIsNone(self.stylua_got())

    def test_refuses_without_a_tool(self):
        cases = {
            "stylua is not installed; mise.toml pins 9.9.9": self.bin(
                "no-stylua", without=("stylua",)
            ),
            "jq is not installed": self.bin("no-jq", without=("jq",)),
        }
        for message, path in cases.items():
            with self.subTest(message):
                result = self.hook(self.root / "sub/a.lua", path=path)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertIn(message, result.stderr)
                self.assertIsNone(self.stylua_got())

    def test_hands_back_what_stylua_and_git_refuse(self):
        result = self.hook(self.root / "sub/a.lua", BROKEN="1")
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("stylua could not format", result.stderr)
        self.assertIn("error: could not parse", result.stderr)

        path = self.bin(
            "bad-git", stand_ins={"git": GIT.format(git=shutil.which("git"))}
        )
        result = self.hook(self.root / "sub/a.lua", path=path)
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("git ls-files could not say", result.stderr)
        self.assertIsNone(self.stylua_got())

    def test_formats_in_a_linked_worktree(self):
        (self.root / "mise.toml").write_text(PIN)
        git(self.root, "add", "mise.toml", "sub")
        git(self.root, "commit", "--quiet", "-m", "t")
        tree = self.tmp / "tree"
        git(self.root, "worktree", "add", "--quiet", str(tree))
        result = self.hook(tree / "sub/a.lua", pins=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.stylua_got(), [str(tree), *args("sub/a.lua")])

    def test_leaves_alone_what_stylua_check_does_not_look_at(self):
        other = self.repository("other")
        (other / "mise.toml").write_text(PIN)
        # Each made, so that what leaves it alone is its path and not its
        # absence -- which `sub/gone.lua` is there for.
        names = [
            ".hidden/a.lua",
            "ignored/a.lua",
            "gen/a.lua",
            "sub/deep/skip.lua",
            "sub/a.txt",
        ]
        for name in names:
            (self.root / name).parent.mkdir(parents=True, exist_ok=True)
            (self.root / name).write_text("return 1\n")
        (self.root / ".gitignore").write_text("ignored/\ngen/\n")
        (self.root / "sub/.gitignore").write_text("skip.lua\n")
        # Tracked and ignored at once, which stylua's walk still skips.
        git(self.root, "add", "--force", "gen/a.lua")
        for file in [
            other / "sub/a.lua",
            *(self.root / name for name in names),
            self.root / "sub/gone.lua",
        ]:
            with self.subTest(file=file.relative_to(self.tmp)):
                # A version CI does not run, so taking the file at all exits 2.
                result = self.hook(file, version="0.0.0")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIsNone(self.stylua_got())

    def test_leaves_alone_a_checkout_with_nothing_to_compare(self):
        # A checkout from before `mise.toml`, and a session still running a
        # hook its checkout no longer has.
        (self.root / "mise.toml").unlink(missing_ok=True)
        result = self.hook(self.root / "sub/a.lua", version="0.0.0", pins=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(self.stylua_got())

        (self.root / ".claude/hooks/format-lua.sh").unlink()
        result = self.hook(self.root / "sub/a.lua", version="0.0.0")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(self.stylua_got())


if __name__ == "__main__":
    unittest.main()
