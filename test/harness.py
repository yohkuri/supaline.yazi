"""Driving a real Yazi under tmux, and counting what came back.

Yazi queries the terminal at startup and aborts if nothing answers, so a
`script`-style pseudo-terminal will not do; tmux is a real terminal emulator.
A detached tmux never answers that probe, so `rt.term.light()` stays nil for
the whole run -- 26.9.1 applies the user's theme anyway, a couple of
milliseconds after `init.lua` and without being asked, which the first half of
`e2e.py`'s theme check confirms every run.
"""

from __future__ import annotations

import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from collections.abc import Callable, Iterable, Sequence
from pathlib import Path
from types import FrameType
from typing import NoReturn

#: The oldest Python these harnesses are written for. A version older than this
#: is refused rather than left to fail somewhere further in, the way
#: `test/run.lua` refuses the wrong Lua: the message is the point.
MINIMUM = (3, 11)

ROOT = Path(__file__).resolve().parent.parent

#: What a harness exits with when it refused to start, as against 1 for a check
#: that failed: "there is no tmux here" and "the columns came out wrong" are
#: answered by different people.
REFUSED = 2

#: What it exits with when something outside it asked it to stop -- what a
#: shell reports for a process SIGTERM ended.
TERMINATED = 143


def refuse(message: str) -> NoReturn:
    """Stop before doing anything, saying what was missing.

    `NoReturn` rather than `None`, because every caller depends on it raising:
    the line after a `refuse` reads a name the arm before it never bound, and
    annotated as returning it looks like a bug to be repaired with a fallback.
    """
    print(message, file=sys.stderr)
    raise SystemExit(REFUSED)


def _require_python() -> None:
    """Stop with a sentence rather than a traceback on too old a Python.

    At import rather than from each `main`, because a `main` runs after its own
    module's imports: `e2e.py` reads the themes with `tomllib`, which is 3.11's.
    Importing this module is the one moment every entry here has in common,
    `test_screen.py` included, which has no `main` and is the one CI runs.
    """
    if sys.version_info < MINIMUM:
        want = ".".join(str(n) for n in MINIMUM)
        have = ".".join(str(n) for n in sys.version_info[:3])
        refuse(f"this harness needs Python {want} or newer, and this is {have}")


_require_python()


def _terminated(number: int, frame: FrameType | None) -> NoReturn:
    raise SystemExit(TERMINATED)


def catch_term() -> None:
    """Make a SIGTERM raise, so the teardown a `finally` holds still runs.

    Python's default handling ends the process without raising, so the
    `finally` never runs, and a tmux session and a scratch directory named
    after this run's PID are left for nothing to clear. SIGINT needs nothing:
    Python raises `KeyboardInterrupt` for it already.
    """
    signal.signal(signal.SIGTERM, _terminated)


def run(
    args: list[str],
    *,
    timeout: float = 20,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    """A subprocess with a deadline on it, and its output captured.

    The deadline is the whole reason this is a function rather than a call:
    every external command either answers or the run stops with a message
    naming it, where a wedged `tmux` would otherwise wait for ever. A non-zero
    exit is a refusal too, unless `check` is off because the exit status is
    the answer being asked for.
    """
    try:
        done = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        refuse(f"{args[0]}: no answer in {timeout}s -- {' '.join(args)}")
    if check and done.returncode != 0:
        refuse(
            f"{args[0]} exited {done.returncode}: {' '.join(args)}\n"
            f"{done.stderr.strip()}"
        )
    return done


def yazi_version() -> str:
    """Which Yazi a run actually proves anything about, or a person looked at.

    Yazi is on CalVer and changes the plugin API between releases, so a
    version other than the one the plugin annotates is the signal to
    re-verify the constraints, not a reason to stop.
    """
    said = run(["yazi", "--version"], timeout=30).stdout
    found = re.search(r"^\s*Version:\s*(.+)$", said, re.MULTILINE)
    version = found.group(1).strip() if found else said.replace("\n", " ")

    pinned = re.match(r"--- @since (.+)", (ROOT / "main.lua").read_text())
    if pinned and not version.startswith(pinned.group(1).strip()):
        print(
            f"note: Yazi is {version}, the plugin annotates "
            f"{pinned.group(1).strip()}"
        )
    return version


def yazi_env(dir: Path, state: str) -> dict[str, str]:
    """The environment both harnesses open the fixture's Yazi in.

    `YAZI_LOG` because a report is two halves and only the shorter one is a
    notification, and there is no log at all unless this is set before Yazi
    starts; `debug` costs three lines over `error` across a short run, measured
    on 26.9.1. `XDG_STATE_HOME` is under the scratch directory, so `--clean`
    takes the log with it, and it is named because `e2e.py` gives its two runs
    one each: the clean run's log is read for the absence of the errors the
    broken run is full of.
    """
    return {
        "YAZI_CONFIG_HOME": str(dir / "config"),
        "XDG_STATE_HOME": str(dir / state),
        "YAZI_LOG": "debug",
    }


def yazi_log(dir: Path, state: str) -> Path:
    """Where Yazi writes its log under the state directory `yazi_env` names."""
    return dir / state / "yazi" / "yazi.log"


def yazi_data(dir: Path) -> Path:
    """The folder both harnesses open that Yazi on, inside the fixture."""
    return dir / "fixture" / "data"


def need(*tools: str) -> None:
    """Refuse to start without every binary the run is about to reach for."""
    missing = [tool for tool in tools if shutil.which(tool) is None]
    if missing:
        refuse(f"not on PATH: {', '.join(missing)}")


class Checks:
    """Named claims, counted rather than raised.

    A bare `assert` would stop at the first failure, and what a broken build
    has to say is *which* of these went wrong -- a change that moves one column
    moves a handful of checks, and the shape of that handful says where to
    look. So every check runs, each says one thing, and the count decides the
    exit status.

    None of them answers a verdict: a returned bool invites `if k.that(...)`,
    and a check that doubles as a branch is an assert again.
    """

    def __init__(self) -> None:
        self.failed: list[str] = []

    def ok(self, label: str) -> None:
        print(f"  {label}")

    def fail(self, label: str) -> None:
        print(f"  FAIL {label}", file=sys.stderr)
        self.failed.append(label)

    def verdict(self, label: str, *faults: str | None) -> bool:
        """Fail on the first fault that is a message, or pass as `label`, and
        say which, so a check that reads further returns on the same guards
        rather than spelling them twice.

        Every fault is evaluated before the call, so none may lean on another:
        written `bad and f"...{bad[0]}..."`, each is built only when it holds
        and indexes only what it has just found is there.
        """
        for fault in faults:
            if fault:
                self.fail(fault)
                return False
        self.ok(label)
        return True

    def that(self, held: bool, label: str) -> None:
        """`label` states what is true when it passes, so it reads either way."""
        if held:
            self.ok(label)
        else:
            self.fail(label)

    def same(self, got: object, want: object, label: str) -> None:
        self.that(got == want, label)

    def differs(self, got: object, unwanted: object, label: str) -> None:
        self.that(got != unwanted, label)

    def holds(self, text: str, pattern: str, label: str) -> None:
        """A literal substring, which is what every screen claim here wants."""
        self.that(pattern in text, label)

    def section(self, name: str) -> None:
        print(f"== {name} ==")


class Session:
    """One detached tmux session, and the screen it is drawing.

    The session name carries the PID, so a run owns everything it touches: a
    fixed name would have to be cleared before `new-session` could take it,
    and clearing one this run did not start kills whatever was inside it.
    """

    #: How often the screen is re-read while waiting. A `capture-pane` costs a
    #: few milliseconds, so this is chosen for how finely a change should be
    #: noticed rather than to keep a cost down.
    POLL = 0.1

    def __init__(self, name: str) -> None:
        self.name = name
        self.started = False

    def tmux(
        self, *args: str, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        return run(["tmux", *args], check=check)

    def start(
        self,
        argv: Sequence[str],
        *,
        env: dict[str, str],
        width: int,
        height: int,
    ) -> None:
        """Open the session on `argv`, in `env`.

        Taken apart rather than as the one string tmux wants, so this is the
        one place that knows a shell is involved and quotes for it -- the
        scratch path is `tempfile.gettempdir()`'s to choose.
        """
        command = shlex.join(
            ["env", *(f"{name}={value}" for name, value in env.items()), *argv]
        )
        self.tmux(
            "new-session",
            "-d",
            "-s",
            self.name,
            "-x",
            str(width),
            "-y",
            str(height),
            command,
        )
        self.started = True

    def kill(self) -> None:
        """Tear the session down, if this run ever got as far as starting one.

        Asked of the run rather than of the name, because a PID comes round
        again and a session a previous run left behind is not this run's.
        """
        if not self.started:
            return
        self.tmux("kill-session", "-t", self.name, check=False)
        self.started = False

    def alive(self) -> bool:
        """Whether tmux still holds this session.

        A session that has gone is the answer here rather than a failure, so
        the exit status is read rather than refused.
        """
        done = self.tmux("has-session", "-t", self.name, check=False)
        return done.returncode == 0

    def quit(self, *keys: str, grace: float = 1.0) -> None:
        """Send the keys that end the program, and take the session down.

        Not `press`: what is sent here ends the only window in the session, and
        a `capture-pane` against a session that has gone exits non-zero, which
        `run` reports as a harness that could not start. So this waits for the
        session to go rather than for the screen to settle. 26.9.1 waits five
        seconds for the terminal probe on the way out -- 5.02, 5.03 and 5.04s
        measured -- which is a timeout, not a guarantee to lean on.

        `grace` is what the program gets to finish writing the log the checks
        read; a session that goes sooner ends the wait at once.
        """
        self.keys(*keys)
        deadline = time.monotonic() + grace
        while self.alive() and time.monotonic() < deadline:
            time.sleep(self.POLL)
        self.kill()

    def capture(self, *, colour: bool = False) -> str:
        args = ["capture-pane", "-t", self.name, "-p"]
        if colour:
            args.append("-e")
        return self.tmux(*args).stdout

    def keys(self, *keys: str) -> None:
        """Send keys literally, so a `-` or a digit is a keystroke not a flag."""
        self.tmux("send-keys", "-t", self.name, "-l", *keys)

    def wait_for(
        self,
        predicate: Callable[[str], bool],
        what: str,
        *,
        timeout: float = 15,
    ) -> str:
        """Poll the screen until it satisfies `predicate`.

        What replaces a fixed sleep wherever the run knows what it is waiting
        **for**: it returns as soon as the screen says so, and goes on waiting
        past any sleep if the screen is slow. A deadline it reaches is not a
        failure of its own -- the check that wanted the screen is still ahead,
        and fails naming what it wanted.
        """
        deadline = time.monotonic() + timeout
        screen = self.capture()
        while not predicate(screen):
            if time.monotonic() > deadline:
                print(
                    f"  note: waited {timeout}s and never saw {what}",
                    file=sys.stderr,
                )
                return screen
            time.sleep(self.POLL)
            screen = self.capture()
        return screen

    def gather(
        self,
        needles: Iterable[str],
        what: str,
        *,
        every: float | None = None,
        timeout: float = 15,
    ) -> str:
        """Collect screens until each of `needles` has been on one of them.

        For what the screen cannot hold at once: Yazi draws three notifications
        at a time and queues the rest, so what says six arrived is the union of
        the screens taken while they drained. A needle is looked for once, on
        the capture it could first appear in, so the work stays linear.

        A deadline it reaches returns what it has, with a note -- the one thing
        that tells a report that never came from a wait that ran out.
        """
        wait = self.POLL if every is None else every
        missing = set(needles)
        seen: list[str] = []
        deadline = time.monotonic() + timeout
        while True:
            screen = self.capture()
            seen.append(screen)
            missing -= {n for n in missing if n in screen}
            if not missing:
                break
            if time.monotonic() > deadline:
                print(
                    f"  note: waited {timeout}s and never saw {what}",
                    file=sys.stderr,
                )
                break
            time.sleep(wait)
        return "\n".join(seen)

    def settle(self, *, stable: float = 0.4, timeout: float = 15) -> str:
        """Poll until the screen has held still for `stable` seconds.

        The fallback for a press whose effect has no name worth waiting on. It
        is adaptive: a screen already done costs one stable window, and one
        still moving -- a fetcher landing late, a preview re-peeked -- resets
        the window and is waited out.

        A screen that never holds still is returned anyway, with a note: the
        broken run draws notifications over the preview pane, and a check that
        aborted there would take the others with it.
        """
        deadline = time.monotonic() + timeout
        was = self.capture()
        quiet = 0.0
        while quiet < stable:
            time.sleep(self.POLL)
            now = self.capture()
            if now == was:
                quiet += self.POLL
            else:
                quiet = 0.0
                was = now
            if time.monotonic() > deadline:
                print(
                    f"  note: the screen never held still for {stable}s",
                    file=sys.stderr,
                )
                break
        return was

    def press(
        self,
        *keys: str,
        until: Callable[[str], bool] | None = None,
        what: str = "",
    ) -> None:
        """Send keys and wait for the screen to answer.

        `until` where the run knows what the press should produce, and the
        settle otherwise. After an `until` the settle is the short one: the
        screen has said what was waited for, and what is left is the repaint.
        """
        self.keys(*keys)
        if until is not None:
            self.wait_for(until, what or "the screen to answer")
            self.settle(stable=0.2)
        else:
            self.settle()
