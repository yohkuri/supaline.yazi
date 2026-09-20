"""Driving a real Yazi under tmux, and counting what came back.

Yazi queries the terminal at startup and aborts if nothing answers, so a
`script`-style pseudo-terminal will not do; tmux is a real terminal emulator.
A detached tmux never answers that probe, so `rt.term.light()` stays nil for
the whole run -- 26.9.1 applies the user's theme anyway, a couple of
milliseconds after `init.lua` and without being asked, which the first half of
`e2e.py`'s theme check confirms every run.
"""

from __future__ import annotations

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

#: And what it exits with when something outside it asked it to stop. 143 is
#: what a shell reports for a process SIGTERM ended, and what the harness this
#: replaced spelled by hand in its own `trap`.
TERMINATED = 143


def refuse(message: str) -> NoReturn:
    """Stop before doing anything, saying what was missing.

    `NoReturn` rather than `None`, because every caller depends on it raising:
    the line after a `refuse` here and in `setup.py` reads a name the arm
    before it never bound, and annotated as returning it looks like a bug to
    be repaired with a fallback -- which is a refusal learning to continue.
    """
    print(message, file=sys.stderr)
    raise SystemExit(REFUSED)


def _require_python() -> None:
    """Stop with a sentence rather than a traceback on too old a Python.

    Called just below rather than from each `main`, because a `main` runs
    after its own module's imports are done: `e2e.py` reads the fixture's
    themes with `tomllib`, which is 3.11's, so on 3.10 a `main` that asked
    first would never be reached at all. Importing this module is the one
    moment every entry here has in common -- both harnesses, `setup.py`, and
    `test_screen.py`, which has no `main` to put a call in and is the one of
    the four that CI runs.

    `test/run.lua` refuses the wrong Lua from its own first lines, and for the
    same reason: a refusal that a later failure can get in front of is not one.
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

    The shell harness this replaced trapped TERM and exited 143 from the trap,
    which put it through the EXIT trap that tore the run down. Python's default
    handling ends the process without raising anything, so the `finally` never
    runs -- and what is left behind is a tmux session and a scratch directory
    both named after this run's PID, which nothing else will ever clear: a
    later run has a different PID, and `Session.kill` refuses on purpose to
    take a name it did not start.

    Not SIGINT, which needs nothing: Python raises `KeyboardInterrupt` for it
    already, and a `finally` runs on the way out.
    """
    signal.signal(signal.SIGTERM, _terminated)


def run(
    args: list[str],
    *,
    timeout: float = 20,
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
    if done.returncode != 0:
        refuse(
            f"{args[0]} exited {done.returncode}: {' '.join(args)}\n"
            f"{done.stderr.strip()}"
        )
    return done


def yazi_env(dir: Path, state: str) -> dict[str, str]:
    """The environment both harnesses open the fixture's Yazi in.

    Here rather than in either of them because they open the same Yazi and had
    said so twice, in two spellings -- a shell string for tmux and a dict for
    `execve` -- with the paths `setup.py` owns written out on both sides.

    `YAZI_LOG` because a report is two halves and only the shorter one is a
    notification, and there is no log at all unless this is set before Yazi
    starts. `debug` costs three lines over `error` across a short run,
    measured on 26.9.1. `XDG_STATE_HOME` is under the scratch directory, so
    `--clean` takes the log with it, and it is named rather than fixed because
    `e2e.py` gives its two runs one each: the clean run's log is read for the
    absence of the errors the broken run is full of.
    """
    return {
        "YAZI_CONFIG_HOME": str(dir / "config"),
        "XDG_STATE_HOME": str(dir / state),
        "YAZI_LOG": "debug",
    }


def yazi_log(dir: Path, state: str) -> Path:
    """Where Yazi writes its log under the state directory `yazi_env` names.

    Beside that function because it is the other half of the same fact: what
    `XDG_STATE_HOME` is set to is here, and so is the path Yazi lays out
    beneath it. Written out by its readers instead, moving the state directory
    would have `manual.py` print a path that does not exist while `e2e.py`
    reported a log the broken run never wrote -- a layout change wearing the
    shape of a plugin fault.
    """
    return dir / state / "yazi" / "yazi.log"


def yazi_data(dir: Path) -> Path:
    """The folder both harnesses open that Yazi on, inside the fixture.

    The third of these and here for the reason the other two are: `setup.py`
    lays the fixture out, this is the one directory in it either harness
    names, and it had been written out on both sides -- in two spellings, one
    of them inside an f-string building a shell command.
    """
    return dir / "fixture" / "data"


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

    def that(self, held: bool, label: str) -> None:
        """`label` states what is true when it passes, so it reads either way.

        None of the four answers a verdict, deliberately. A returned bool is
        an invitation to write `if k.that(...)`, and a check that doubles as a
        branch is this object back to being an assert -- where the whole of
        why it exists is that a change moving one column moves a handful of
        checks, and the shape of that handful is what says where to look.
        """
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

    def tmux(self, *args: str) -> str:
        return run(["tmux", *args]).stdout

    def start(
        self,
        argv: Sequence[str],
        *,
        env: dict[str, str],
        width: int,
        height: int,
    ) -> None:
        """Open the session on `argv`, in `env`.

        `set -e`'s replacement is `run`'s own exit.

        The two are taken apart rather than as the one string tmux wants,
        because putting them together means quoting them, and a caller that
        did that would be the one place outside this file that has to know a
        shell is involved at all. What it would be quoting is the scratch
        path, which is `tempfile.gettempdir()`'s to choose -- the same hazard
        `setup.py` designs around where the keymap's `shell` template names
        that directory, one layer down.
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

    def alive(self) -> bool:
        """Whether tmux still holds this session, asked without refusing.

        `run` is the wrong caller for this one question: a session that has
        gone is the answer here rather than a failure, and `has-session` says
        so with a non-zero exit like any other.
        """
        done = subprocess.run(
            ["tmux", "has-session", "-t", self.name],
            capture_output=True,
            timeout=20,
            check=False,
        )
        return done.returncode == 0

    def quit(self, *keys: str, grace: float = 1.0) -> None:
        """Send the keys that end the program, and take the session down.

        Not `press`: what is sent here ends the only window in the session, so
        the settle behind a press goes on reading a screen tmux may already
        have destroyed -- and a `capture-pane` against a session that has gone
        exits non-zero, which `run` reports as a harness that could not start,
        over a run that in fact passed. Reproduced on its own: a session whose
        command exits on the key refuses the very next capture, 0.02s in, and
        the harness exits 2.

        What has held that off here is a timeout rather than a margin. A
        detached tmux never answers Yazi's terminal probe, and 26.9.1 waits
        five seconds for it on the way out -- measured 5.02, 5.03 and 5.04s
        against the 0.49s the press took, so the race was never close and
        would be lost outright by a Yazi that stopped waiting.

        `grace` is what the program gets to finish writing, since the checks
        read the log it leaves; twice what the settle gave it, and a session
        that goes sooner ends the wait at once. Nothing reads the screen after
        this, which is the other half of why there is no settle here.
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

    def gather(
        self,
        needles: Iterable[str],
        what: str,
        *,
        every: float | None = None,
        timeout: float = 15,
    ) -> str:
        """Collect screens until each of `needles` has been on one of them.

        `wait_for` answers with a single screen, which is the wrong shape for
        anything the screen cannot hold at once -- and Yazi's notifications
        are that: it draws three at a time and queues the rest, so what says
        six of them arrived is the union of the screens taken while they
        drained rather than any one of those screens.

        A needle is looked for once, on the capture it could first appear in,
        and the union is built at the end. Over the union every pass instead,
        the work is quadratic in the captures taken -- for a question every
        earlier pass has already answered.

        `every` for a caller that knows what it is waiting on stays up longer
        than `POLL`; the poll is what a caller with nothing to say gets.

        A deadline it reaches returns what it has, with a note, for the reason
        `wait_for` gives -- and for one of its own here: the checks ahead can
        see that a report is missing from the union and read that as a column
        that never reported, where the wait having run out is the other
        explanation and only this loop can tell them apart.
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
    ) -> None:
        """Send keys and wait for the screen to answer.

        `until` where the run knows what the press should produce, and the
        settle otherwise. Both are bounded, so neither can hang the run.

        The settle after an `until` is the short one on purpose: the screen
        has already said the thing waited for arrived, and what is left is the
        repaint behind it. There is no window to pass in -- a caller that
        could name one silently got 0.2 on this arm, which is a weaker wait
        arriving as a stronger-looking argument.
        """
        self.keys(*keys)
        if until is not None:
            self.wait_for(until, what or "the screen to answer")
            self.settle(stable=0.2)
        else:
            self.settle()
