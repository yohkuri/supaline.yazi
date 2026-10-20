"""`.claude/hooks/format-lua.sh`, against a stylua that only records.

The hook formats with whatever stylua is on `PATH` and refuses when that is
not the one `mise.toml` pins, so what is worth holding is where it looks for
the pin, which files it takes, and the directory and arguments stylua gets.
A stand-in on `PATH` answers `--version` with what a test asks for and writes
down the rest, so none of this needs a real stylua.

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

REPO = Path(__file__).resolve().parent.parent
HOOK = REPO / ".claude/hooks/format-lua.sh"

#: Answers `--version` with $VERSION, and otherwise records where it ran and
#: what it was given.
STYLUA = """#!/bin/sh
[ "$1" = --version ] && { echo "stylua $VERSION"; exit; }
printf '%s\\n' "$(pwd -P)" "$*" > "$CALLED"
"""

PIN = 'stylua = "9.9.9"\n'


@unittest.skipUnless(shutil.which("jq") and shutil.which("git"), "needs both")
class TheHook(unittest.TestCase):
    def setUp(self) -> None:
        made = tempfile.TemporaryDirectory()
        self.addCleanup(made.cleanup)
        self.tmp = Path(made.name).resolve()
        # No global or system configuration, so a template, a hook or an
        # `excludesFile` of whoever runs this cannot reach the repositories.
        self.env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.tmp),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
        }
        self.root = self.repository("repo")
        self.called = self.tmp / "called"
        bin_ = self.tmp / "bin"
        bin_.mkdir()
        (bin_ / "stylua").write_text(STYLUA)
        (bin_ / "stylua").chmod(0o755)
        self.path = f"{bin_}{os.pathsep}{os.environ['PATH']}"

    def repository(self, name: str) -> Path:
        root = self.tmp / name
        (root / "sub").mkdir(parents=True)
        self.git(root, "init", "--quiet")
        (root / "sub/a.lua").write_text("return 1\n")
        return root

    def git(self, root: Path, *args: str) -> None:
        subprocess.run(
            ["git", "-C", str(root), *args],
            env=self.env,
            check=True,
            capture_output=True,
        )

    def hook(
        self,
        file: Path,
        version: str = "9.9.9",
        pins: str | None = PIN,
        payload: str = "tool_input",
        path: str | None = None,
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
        )
        # From somewhere else, as a session working in another checkout is.
        return subprocess.run(
            ["sh", str(HOOK)],
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
            pins=(REPO / "mise.toml").read_text(),
        )
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertRegex(
            result.stderr,
            r"stylua 0\.0\.0 is installed, but CI runs \d+\.\d+\.\d+,",
        )
        self.assertIsNone(self.stylua_got())

    def test_formats_from_the_file_checkout_when_the_pin_matches(self):
        for pins in [PIN, 'stylua="9.9.9"  # the formatter\n']:
            for payload in ["tool_input", "tool_response"]:
                with self.subTest(pins=pins, payload=payload):
                    result = self.hook(
                        self.root / "sub/a.lua", pins=pins, payload=payload
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(
                        self.stylua_got(),
                        [
                            str(self.root),
                            "--config-path stylua.toml -- sub/a.lua",
                        ],
                    )

    def test_refuses_without_a_pin(self):
        for pins in ['lua = "5.5.1"\n', '# stylua = "9.9.9"\n']:
            with self.subTest(pins=pins):
                result = self.hook(self.root / "sub/a.lua", pins=pins)
                self.assertEqual(result.returncode, 2)
                self.assertIn(
                    "could not read the stylua version", result.stderr
                )
                self.assertIsNone(self.stylua_got())

    def test_refuses_without_a_stylua(self):
        # jq and git and nothing else, so no stylua the machine has is found.
        bare = self.tmp / "bare"
        bare.mkdir()
        for tool in ["jq", "git"]:
            (bare / tool).symlink_to(shutil.which(tool))
        path = f"{bare}{os.pathsep}/usr/bin{os.pathsep}/bin"
        if shutil.which("stylua", path=path):
            self.skipTest("a stylua is installed under /usr/bin or /bin")
        result = self.hook(self.root / "sub/a.lua", path=path)
        self.assertEqual(result.returncode, 2)
        self.assertIn(
            "stylua is not installed; mise.toml pins 9.9.9", result.stderr
        )

    def test_formats_in_a_linked_worktree(self):
        (self.root / "mise.toml").write_text(PIN)
        self.git(self.root, "add", ".")
        self.git(
            self.root,
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.com",
            "commit",
            "--quiet",
            "-m",
            "t",
        )
        tree = self.tmp / "tree"
        self.git(self.root, "worktree", "add", "--quiet", str(tree))
        result = self.hook(tree / "sub/a.lua", pins=None)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.stylua_got(),
            [str(tree), "--config-path stylua.toml -- sub/a.lua"],
        )

    def test_leaves_alone_what_stylua_check_does_not_look_at(self):
        other = self.repository("other")
        (other / "mise.toml").write_text(PIN)
        for name in [".hidden/a.lua", "ignored/a.lua", "sub/a.txt"]:
            (self.root / name).parent.mkdir(exist_ok=True)
            (self.root / name).write_text("return 1\n")
        (self.root / ".gitignore").write_text("ignored/\n")
        for file in [
            other / "sub/a.lua",
            self.root / ".hidden/a.lua",
            self.root / "ignored/a.lua",
            self.root / "sub/a.txt",
            self.root / "sub/gone.lua",
        ]:
            with self.subTest(file=file.relative_to(self.tmp)):
                # A version CI does not run, so taking the file at all exits 2.
                result = self.hook(file, version="0.0.0")
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIsNone(self.stylua_got())


if __name__ == "__main__":
    unittest.main()
