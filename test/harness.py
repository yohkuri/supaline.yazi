"""Driving a real Yazi under tmux, and counting what came back.

Yazi queries the terminal at startup and aborts if nothing answers, so a
`script`-style pseudo-terminal will not do; tmux is a real terminal emulator.
A detached tmux never answers that probe, so `rt.term.light()` stays nil for
the whole run -- 26.9.1 applies the user's theme anyway, a couple of
milliseconds after `init.lua` and without being asked, which the first half of
`e2e.py`'s theme check confirms every run.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import time
from collections.abc import Callable
from pathlib import Path

#: The oldest Python these harnesses are written for. Nothing here needs a
#: newer one, and a version older than this is refused rather than left to
#: fail somewhere further in -- `test/run.lua` refuses the wrong Lua the same
#: way, and for the same reason: the message is the point.
MINIMUM = (3, 11)

ROOT = Path(__file__).resolve().parent.parent

#: What a harness exits with when it refused to start, as against 1 for a check
#: that failed. The shell harnesses this replaced spelled the same distinction,
#: and it is worth keeping: "there is no tmux here" and "the columns came out
#: wrong" are answered by different people.
REFUSED = 2


def refuse(message: str) -> None:
    """Stop before doing anything, saying what was missing."""
    print(message, file=sys.stderr)
    raise SystemExit(REFUSED)


def require_python() -> None:
    """Stop with a sentence rather than a traceback on too old a Python."""
    if sys.version_info < MINIMUM:
        want = ".".join(str(n) for n in MINIMUM)
        have = ".".join(str(n) for n in sys.version_info[:3])
        refuse(f"this harness needs Python {want} or newer, and this is {have}")


def run(
    args: list[str],
    *,
    timeout: float = 20,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    """A subprocess with a deadline on it, and its output captured.

    The deadline is the whole reason this is a function rather than a call.
    Every external command either answers or the run stops with a message
    naming it -- a `tmux` that wedged, a `yazi --version` that hung on a probe
    -- where the same command from a shell script waits for ever and the
    person watching sees nothing at all.
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


def need(*tools: str) -> None:
    """Refuse to start without every binary the run is about to reach for."""
    missing = [tool for tool in tools if shutil.which(tool) is None]
    if missing:
        refuse(f"not on PATH: {', '.join(missing)}")


class Checks:
    """Named claims, counted rather than raised.

    A bare `assert` would stop at the first failure, and the information a
    broken build has to give is *which* of these went wrong -- a change that
    moves one column moves a handful of checks, and the shape of that handful
    is what says where to look. So every check runs, each says one thing, and
    the count is what decides the exit status.

    One claim per line, deliberately. A line bundling three of them cannot say
    which of the three failed.
    """

    def __init__(self) -> None:
        self.failed: list[str] = []

    def ok(self, label: str) -> None:
        print(f"  {label}")

    def fail(self, label: str) -> None:
        print(f"  FAIL {label}", file=sys.stderr)
        self.failed.append(label)

    def that(self, held: bool, label: str) -> bool:
        """`label` states what is true when it passes, so it reads either way."""
        if held:
            self.ok(label)
        else:
            self.fail(label)
        return held

    def same(self, got: object, want: object, label: str) -> bool:
        return self.that(got == want, label)

    def differs(self, got: object, unwanted: object, label: str) -> bool:
        return self.that(got != unwanted, label)

    def holds(self, text: str, pattern: str, label: str) -> bool:
        """A literal substring, which is what every screen claim here wants."""
        return self.that(pattern in text, label)

    def section(self, name: str) -> None:
        print(f"== {name} ==")


class Session:
    """One detached tmux session, and the screen it is drawing.

    Both the session name and the scratch directory carry the PID, so a run
    owns everything it touches. A fixed session name would have to be cleared
    before `new-session` could take it, and clearing one this run did not start
    kills whatever was inside it -- a concurrent run of this same harness, or a
    session a person happened to name the same, along with its unsaved work.
    """

    #: How often the screen is re-read while waiting. A `capture-pane` costs a
    #: few milliseconds, so this is chosen for how finely a change should be
    #: noticed rather than to keep a cost down.
    POLL = 0.1

    def __init__(self, name: str) -> None:
        self.name = name
        self.started = False

    def tmux(self, *args: str, timeout: float = 20) -> str:
        return run(["tmux", *args], timeout=timeout).stdout

    def start(
        self, command: str, *, width: int = 170, height: int = 40
    ) -> None:
        """Open the session. `set -e`'s replacement is `run`'s own exit."""
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
        again: a session left behind by a previous run carries a name a later
        one is entitled to, and killing it would be this harness doing the very
        thing the PID is there to prevent.
        """
        if not self.started:
            return
        subprocess.run(
            ["tmux", "kill-session", "-t", self.name],
            capture_output=True,
            timeout=20,
            check=False,
        )
        self.started = False

    def capture(self, *, colour: bool = False) -> str:
        args = ["capture-pane", "-t", self.name, "-p"]
        if colour:
            args.append("-e")
        return self.tmux(*args)

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

        This is what replaces a fixed sleep wherever the run knows what it is
        waiting **for**, and it is both faster and stronger than one: it
        returns as soon as the screen says so, and it goes on waiting past any
        sleep that would have been written here if the screen is slow.

        A deadline it reaches is not a failure of its own. The check that
        wanted the screen is still ahead, and it fails naming what it wanted --
        which is a better sentence than this function could write.
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

    def settle(self, *, stable: float = 0.4, timeout: float = 15) -> str:
        """Poll until the screen has held still for `stable` seconds.

        The fallback for a press whose effect has no name worth waiting on --
        a linemode whose columns this run is about to read rather than predict.

        What it buys over the fixed sleep it replaces is that it is
        **adaptive**. A screen that is already done costs one stable window; a
        screen that is still moving -- a fetcher landing late, a preview being
        re-peeked -- resets the window and is waited out, past the second a
        sleep would have given it. The guarantee is different rather than
        strictly larger: a sleep covers a fixed second from the keypress, and
        this covers every gap shorter than `stable` for as long as the screen
        keeps moving.

        A screen that never holds still is returned anyway, with a note. The
        broken run draws notifications over the preview pane, and a check that
        aborted there would take the other fifty with it.
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
        stable: float = 0.4,
    ) -> str:
        """Send keys and wait for the screen to answer.

        `until` where the run knows what the press should produce, and the
        settle otherwise. Both are bounded, so neither can hang the run.
        """
        self.keys(*keys)
        if until is not None:
            self.wait_for(until, what or "the screen to answer")
            return self.settle(stable=0.2)
        return self.settle(stable=stable)
