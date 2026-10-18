"""Driving a real Yazi under tmux, and counting what came back.

Yazi queries the terminal at startup and aborts if nothing answers, so a
`script`-style pseudo-terminal will not do; tmux is a real terminal emulator.
A detached tmux never answers that probe, so `rt.term.light()` stays nil for
the whole run -- 26.9.1 applies the user's theme anyway, a couple of
milliseconds after `init.lua` and without being asked, which the first half of
`e2e.py`'s theme check confirms every run.
"""

from __future__ import annotations

import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import threading
import time
from collections.abc import Callable, Iterable, Iterator, Sequence
from contextlib import contextmanager
from pathlib import Path
from types import FrameType
from typing import TYPE_CHECKING, NoReturn

if TYPE_CHECKING:
    # For the annotations alone: `setup.py` imports this module, so it cannot
    # import that one back, and `Driver` is handed what it reads instead.
    from setup import Case, Cases

#: The oldest Python these harnesses are written for. A version older than this
#: is refused rather than left to fail somewhere further in, the way
#: `test/run.lua` refuses the wrong Lua: the message is the point.
MINIMUM = (3, 11)

ROOT = Path(__file__).resolve().parent.parent

#: The window every capture is taken in. Wide enough that the three panes all
#: have room, and 40 rows so about 37 of `colour/ramp`'s 64 steps reach a
#: capture.
WIDTH, HEIGHT = 170, 40

#: What a harness exits with when it refused to start, as against 1 for a check
#: that failed: "there is no tmux here" and "the columns came out wrong" are
#: answered by different people.
REFUSED = 2

#: How long a Yazi just started gets to list its folder, longer than any other
#: wait here because a cold start can be slow.
STARTUP = 30


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

    A refusal rather than a `unittest.SkipTest`, though `unittest discover`
    prints an `ImportError` traceback under the sentence: a suite that skips
    itself on an old Python is a green run over nothing.
    """
    if sys.version_info < MINIMUM:
        want = ".".join(str(n) for n in MINIMUM)
        have = ".".join(str(n) for n in sys.version_info[:3])
        refuse(f"this harness needs Python {want} or newer, and this is {have}")


_require_python()

# Below the check rather than with the imports above it, because importing this
# module is what refuses too old a Python, and `screen.py` cannot be read by
# one: its `tuple[str, Pen]` is a `TypeError` before 3.9, measured on 3.8.20.
import screen as sc


def _terminated(number: int, frame: FrameType | None) -> NoReturn:
    """Exit as a process the signal `number` ended does, as a shell reports
    it: 128 plus the signal, so 143 for a SIGTERM and 129 for a SIGHUP.
    Both are ignored from here on, so a second one -- a terminal can send a
    SIGTERM after its SIGHUP -- does not cut the teardown short."""
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    raise SystemExit(128 + number)


def catch_term() -> None:
    """Make a SIGTERM or a SIGHUP raise, so the teardown a `finally` holds
    still runs.

    Python's default handling ends the process without raising, so the
    `finally` never runs, and a tmux session and a scratch directory named
    after this run's PID are left for nothing to clear. A SIGHUP is what
    closing the terminal a run is in sends, unless the run was started under
    `nohup`, which ignores it and is left to. SIGINT needs nothing: Python
    raises `KeyboardInterrupt` for it already.
    """
    signal.signal(signal.SIGTERM, _terminated)
    if signal.getsignal(signal.SIGHUP) is not signal.SIG_IGN:
        signal.signal(signal.SIGHUP, _terminated)


def run(
    args: list[str],
    *,
    timeout: float = 20,
    check: bool = True,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """A subprocess with a deadline on it, and its output captured, in this
    environment with `env` set over it.

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
            env={**os.environ, **env} if env else None,
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


def yazi_env(dir: Path, state: str, *, headless: bool) -> dict[str, str]:
    """The environment every harness opens a Yazi in, under the scratch
    directory `dir`.

    `YAZI_LOG` because a report is two halves and only the shorter one is a
    notification, and there is no log at all unless this is set before Yazi
    starts; `debug` costs three lines over `error` across a short run, measured
    on 26.9.1. `XDG_STATE_HOME` is under the scratch directory, so `--clean`
    takes the log with it, and it is named because `e2e.py` gives its two runs
    one each: the clean run's log is read for the absence of the errors the
    broken run is full of.

    `XDG_RUNTIME_DIR` is `own_socket`'s, for a headless Yazi always. A Yazi
    opened for a person keeps the user's when there is one, because what that
    Yazi starts -- an editor, a clipboard -- finds the session's own sockets
    through it, Wayland's on Linux among them; with none to keep,
    as on macOS, it is given one of its own too. `headless` has no default, so
    a harness says which it is rather than getting the shared socket by
    leaving it out.

    `LESS` is emptied for a headless Yazi, because `e2e.py` reads the walk's
    `W d` by the first row `less` draws, and an option such as `-N` moves it.
    A person keeps their own.
    """
    env = {
        "YAZI_CONFIG_HOME": str(dir / "config"),
        "XDG_STATE_HOME": str(dir / state),
        "YAZI_LOG": "debug",
    }
    if headless:
        env["LESS"] = ""
    if headless or "XDG_RUNTIME_DIR" not in os.environ:
        env |= own_socket(dir)
    return env


#: The most a socket's path may hold, the NUL after it included: the size of
#: `sun_path`, 108 bytes on Linux and 104 on macOS and the BSDs.
SUN_PATH = 108 if sys.platform.startswith("linux") else 104


def own_socket(dir: Path) -> dict[str, str]:
    """`XDG_RUNTIME_DIR`, a directory under `dir` that no other Yazi is given.

    Yazi binds its DDS socket under that directory, or under the temp
    directory when it is unset or relative, read off 26.9.1's
    `yazi-fs/src/xdg.rs` and `yazi-dds/src/stream.rs`. Two Yazis alive at once
    with the same one race to bind it, and the loser logs `Could not connect to
    or start a new DDS server`, which `e2e.py`, `examples.py` and `readme.py`
    count as a failure. They are alive at once more often than they look:
    26.9.1 outlives `kill-session` by the rest of its five seconds after `q`,
    measured, so consecutive Yazis of one run overlap, besides two runs at once
    and a Yazi open elsewhere. One directory per run is not enough for the
    first of those, which is why it is one per Yazi.

    The first number directly under `dir` that `mkdir` can take, so the claim
    is the directory itself and no count in this process has to agree with
    the disk. A count would do as well for every harness today, since each
    clears `dir` before its first Yazi. Directly under `dir` rather than in a
    `run/` inside it, since those four bytes are what lets `examples.py` and
    `readme.py` fit a ten-digit uid under macOS's default TMPDIR, computed
    rather than run under one; nothing else a harness puts in `dir` is named
    with digits alone. Under `dir` at all rather than in a short directory of
    their own under `/tmp`, which would take TMPDIR out of the length, since
    `--clean` and each harness's clearing of `dir` take these with the rest:
    one outside it would need removing by every harness on every way out.

    A path too long for `sun_path` is refused here rather than left to Yazi,
    which logs only `path must be shorter than SUN_LEN`, measured, and only
    once the run has waited out its startup. The number has three digits at
    least, so the first thousand Yazis share a length and a run near the limit
    is refused at its first. Named with the bare number, the eleventh's path
    would be a byte longer than the first's, and a run that fitted ten would
    stop there with their pictures written.
    """
    dir = dir.absolute()
    n = 0
    while True:
        runtime = dir / f"{n:03}"
        try:
            runtime.mkdir(parents=True)
            break
        except FileExistsError:
            n += 1
    socket = runtime / f"yazi+{os.getuid()}" / ".dds.sock"
    if len(os.fsencode(socket)) >= SUN_PATH:
        refuse(
            f"{socket} is longer than the {SUN_PATH - 1} bytes a socket's path "
            "may be: run this with a shorter TMPDIR"
        )
    return {"XDG_RUNTIME_DIR": str(runtime)}


def yazi_log(dir: Path, state: str) -> Path:
    """Where Yazi writes its log under the state directory `yazi_env` names."""
    return dir / state / "yazi" / "yazi.log"


#: What counts as an error in a Yazi log, on either side of the run.
TROUBLE = re.compile(r"ERROR|WARN|attempt to|error converting", re.IGNORECASE)

#: What Yazi logs about the machine rather than about a plugin, matched on a
#: troubled line and the one after it, since a fetcher's error names its file
#: only there. 26.9.1 logged each in Ubuntu 24.04 under Docker and none on
#: macOS. Each names Yazi's own source and message, and a plugin's error is
#: logged by `yazi_plugin`, or a fetcher's under its own name, so none of
#: these can match one.
MACHINE = (
    # A container has no `/dev/disk`.
    re.compile(r"yazi_fs::mounts::linux: Cannot read /dev/disk/by-label\n"),
    # tmux 3.4 has no `input-buffer-size`; 3.8 does.
    re.compile(r"yazi_emulator::mux: .*invalid option: input-buffer-size\n"),
    # `file -bL --mime-type` 5.45 answers `cannot open` for a link to nothing,
    # where 5.41 on macOS answers `inode/symlink`, and the fixture holds one.
    re.compile(r"fetcher 'mime\.local':\n.*MIME type for `[^`]*/link-broken`"),
)


def read_log(body: str) -> tuple[list[str], list[str]]:
    """The lines of a log that report an error, and apart from them the ones
    `MACHINE` names, so a run can say how many it left out."""
    lines = body.splitlines()
    kept: list[str] = []
    machine: list[str] = []
    for line, after in zip(lines, [*lines[1:], ""]):
        if TROUBLE.search(line):
            about = any(p.search(f"{line}\n{after}") for p in MACHINE)
            (machine if about else kept).append(line)
    return kept, machine


def troubles(body: str) -> list[str]:
    """The lines of a log that report an error, less what `MACHINE` names."""
    return read_log(body)[0]


def yazi_data(dir: Path) -> Path:
    """The folder both harnesses open that Yazi on, inside the fixture."""
    return dir / "fixture" / "data"


def begin_verdicts(path: Path, title: str, *notes: str) -> tuple[str, ...]:
    """Start a file of a reader's verdicts, for `manual.py` or `gallery.py`,
    and answer the header it wrote.

    The header is what a verdict is about besides the step: the code it was
    given on, the Yazi that drew it, and whatever `notes` the caller can add.
    Written by the harness rather than by what records a verdict, which can ask
    none of it.
    """
    commit = run(
        ["git", "-C", str(ROOT), "describe", "--always", "--dirty"], check=False
    ).stdout.strip()
    header = (
        title,
        f"commit   {commit or 'unknown'}",
        f"yazi     {yazi_version()}",
        *notes,
        f"started  {time.strftime('%Y-%m-%d %H:%M:%S %z')}",
    )
    path.write_text("".join(f"# {line}\n" for line in header))
    return header


def print_verdicts(path: Path, who: str) -> None:
    """What a reader said, once they are done, latest answer per step.

    A line is the step, then its case, its theme and `yes` or `no`, each after
    a tab, and whatever the caller writes after those. The step is what a
    later answer replaces.
    """
    lines = path.read_text().splitlines() if path.exists() else []
    said = {
        line.split("\t")[0]: line for line in lines if not line.startswith("#")
    }
    if not said:
        print(f"{who}: no verdict was given")
        return
    print(f"{who}: the verdicts, also in {path}")
    for line in (
        *(line for line in lines if line.startswith("#")),
        *said.values(),
    ):
        print(f"  {line}")
    wrong = sum(line.split("\t")[3] == "no" for line in said.values())
    print(f"{who}: {len(said)} step(s) answered, {wrong} of them looking wrong")


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
        #: What every command after `new-session` names it by. A bare name is a
        #: prefix to tmux, so `supaline-e2e-123` reaches `supaline-e2e-1234` once
        #: its own session has gone; `=` makes it exact, and the `:` lets
        #: `send-keys` and `capture-pane` take it too, which refuse `=name`
        #: alone with `can't find pane`, measured on tmux 3.8.
        self.target = f"={name}:"
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
        self.tmux("kill-session", "-t", self.target, check=False)
        self.started = False

    def alive(self) -> bool:
        """Whether tmux still holds this session.

        A session that has gone is the answer here rather than a failure, so
        the exit status is read rather than refused.
        """
        done = self.tmux("has-session", "-t", self.target, check=False)
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
        read; a session that goes sooner ends the wait at once. Waiting the
        five seconds out instead would add about eight to an `e2e.py` run,
        which quits twice, for no claim the checks make.
        """
        self.keys(*keys)
        deadline = time.monotonic() + grace
        while self.alive() and time.monotonic() < deadline:
            time.sleep(self.POLL)
        self.kill()

    def capture(self, *, colour: bool = False) -> str:
        """The screen, by a `tmux` process per read: `settle` says what a
        persistent `tmux -C` client would cost it."""
        args = ["capture-pane", "-t", self.target, "-p"]
        if colour:
            args.append("-e")
        return self.tmux(*args).stdout

    def keys(self, *keys: str) -> None:
        """Send keys literally, so a `-` or a digit is a keystroke not a flag."""
        self.tmux("send-keys", "-t", self.target, "-l", *keys)

    def wait_for(
        self,
        predicate: Callable[[str], bool],
        what: str,
        *,
        timeout: float = 15,
        colour: bool = False,
    ) -> str:
        """Poll the screen until it satisfies `predicate`.

        What replaces a fixed sleep wherever the run knows what it is waiting
        **for**: it returns as soon as the screen says so, and goes on waiting
        past any sleep if the screen is slow. A deadline it reaches is not a
        failure of its own -- the check that wanted the screen is still ahead,
        and fails naming what it wanted.

        `colour` hands `predicate` the screen with its escapes, for a change
        that recolours and rewrites nothing.
        """
        deadline = time.monotonic() + timeout
        screen = self.capture(colour=colour)
        while not predicate(screen):
            if time.monotonic() > deadline:
                print(
                    f"  note: waited {timeout}s and never saw {what}",
                    file=sys.stderr,
                )
                return screen
            time.sleep(self.POLL)
            screen = self.capture(colour=colour)
        return screen

    @contextmanager
    def gather(
        self,
        needles: Iterable[str],
        what: str,
        *,
        every: float | None = None,
        timeout: float = 15,
    ) -> Iterator[list[str]]:
        """Collect screens, from the block's first key on, until each of
        `needles` has been on one of them.

        For what the screen cannot hold at once: Yazi draws three notifications
        at a time and queues the rest, so what says six arrived is the union of
        the screens taken while they drained. A needle is looked for once, on
        the capture it could first appear in, so the work stays linear.

        From a thread, beside the keys the block presses rather than after
        them, because what it looks for can come and go while they are made.
        The deadline counts from the end of the block, and the list it yields
        is whole once the block has left.

        A deadline it reaches leaves what it has, with a note -- the one thing
        that tells a report that never came from a wait that ran out.
        """
        wait = self.POLL if every is None else every
        missing = set(needles)
        seen: list[str] = []
        # Unbounded while the block runs, `timeout` past its end once it has
        # finished.
        deadline = float("inf")
        stopped = threading.Event()
        # What ended the thread early, raised again once the block has left:
        # `run` refuses with `SystemExit`, which a thread drops without a word,
        # and the screens it leaves would read as reports that never came.
        failed: BaseException | None = None

        def collect() -> None:
            nonlocal failed
            try:
                while not stopped.is_set():
                    screen = self.capture()
                    if not seen or screen != seen[-1]:
                        seen.append(screen)
                        missing.difference_update(
                            {n for n in missing if n in screen}
                        )
                    if not missing:
                        return
                    if time.monotonic() > deadline:
                        print(
                            f"  note: waited {timeout}s and never saw {what}",
                            file=sys.stderr,
                        )
                        return
                    stopped.wait(wait)
            # Every kind, since it is raised again rather than handled here.
            except BaseException as error:  # noqa: BLE001
                failed = error

        thread = threading.Thread(target=collect, daemon=True)
        thread.start()
        try:
            yield seen
            deadline = time.monotonic() + timeout
        except BaseException:
            stopped.set()
            raise
        finally:
            thread.join()
        if failed is not None:
            raise failed

    def settle(
        self, *, stable: float = 0.4, timeout: float = 15, colour: bool = False
    ) -> str:
        """Poll until the screen has held still for `stable` seconds.

        The fallback for a press whose effect has no name worth waiting on. It
        is adaptive: a screen already done costs one stable window, and one
        still moving -- a fetcher landing late, a preview re-peeked -- resets
        the window and is waited out.

        A screen that never holds still is returned anyway, with a note: the
        broken run draws notifications over the preview pane, and a check that
        aborted there would take the others with it.

        `colour` compares the screens with their escapes, so a repaint that
        recolours alone resets the window too.

        The window is counted in `POLL`s rather than by the clock, and each
        iteration also costs a capture and whatever the sleep overshoots, so
        0.4s is about 0.45s of wall clock -- a margin every wait here relies
        on. A cheaper capture, such as a persistent `tmux -C` client,
        would shrink it without a word: write the margin into `stable` first.
        """
        deadline = time.monotonic() + timeout
        was = self.capture(colour=colour)
        quiet = 0.0
        while quiet < stable:
            time.sleep(self.POLL)
            now = self.capture(colour=colour)
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
        colour: bool = False,
    ) -> None:
        """Send keys and wait for the screen to answer.

        `until` where the run knows what the press should produce, and the
        settle otherwise. After an `until` the settle is the short one: the
        screen has said what was waited for, and what is left is the repaint.

        `colour` waits on the screen with its escapes, both for `until` and
        for the settle. A press that recolours and rewrites nothing needs it
        and an `until` besides: the plain settle cannot see that repaint, so
        it returns one window after the key whether the repaint landed or not.
        """
        self.keys(*keys)
        if until is not None:
            self.wait_for(until, what or "the screen to answer", colour=colour)
            self.settle(stable=0.2, colour=colour)
        else:
            self.settle(colour=colour)


class Driver:
    """A Yazi on the fixture `setup.py` built, pressed by the keys `cases.toml`
    binds, and the captures taken from it.

    Where the fixture lives and how long it outlives the run is the caller's,
    and so is building it: `e2e.py` gives each run a directory of its own and
    `gallery.py` one a person can find again.
    """

    def __init__(self, dir: Path, session: str, listing: Cases) -> None:
        self.dir = dir
        self.session = Session(session)
        # Every key this presses is one `cases.toml` binds, found by what it
        # does rather than by how it is spelled.
        self.listing = listing
        self.shots: dict[str, str] = {}

    def open_yazi(self, state: str) -> None:
        """Start Yazi on `data/`, with a state directory of its own."""
        self.session.start(
            ["yazi", str(yazi_data(self.dir))],
            env=yazi_env(self.dir, state, headless=True),
            width=WIDTH,
            height=HEIGHT,
        )
        # A name out of the fixture rather than a fixed wait: it says Yazi got
        # as far as listing the folder, where a sleep says only that time
        # passed.
        landmark = self.listing.folders["data"].landmark
        self.session.wait_for(
            lambda s: landmark in s,
            "the fixture listed",
            timeout=STARTUP,
        )

    def store(self, label: str, plain: str, colour: str = "") -> None:
        """Hold a capture under `label`, in memory and on disk.

        On disk because a kept directory is for reading them afterwards, and a
        check that failed is answered by the capture it failed on. Apart from
        `shot` for the one capture that is not a single tmux call: the broken
        run's union of screens.
        """
        self.shots[label] = plain
        (self.dir / f"screen-{label}.txt").write_text(plain)
        if colour:
            self.shots[f"colour-{label}"] = colour
            (self.dir / f"color-{label}.txt").write_text(colour)

    def shot(self, label: str) -> None:
        """Keep both captures of the screen as it stands."""
        self.store(
            label,
            self.session.capture(),
            self.session.capture(colour=True),
        )

    def here(self, path: str) -> Callable[[str], bool]:
        """Whether a screen's current pane is the folder `path`.

        Read off the folder's landmark in `cases.toml`, a name only that
        folder holds, in the **current pane**: the panes either side draw the
        neighbouring folders, so a name they hold is on screen before the `cd`
        that makes it current. Measured on 26.9.1, `inner-a.txt` is in the
        preview pane throughout `data/`.
        """
        expect = self.listing.folders[path].landmark
        return lambda s: any(expect in f for f in sc.current_fields(s))

    def goto(self, path: str) -> None:
        """Go to a folder `cases.toml` lists, by its key."""
        self.session.press(
            *self.listing.folders[path].key.split(" "),
            until=self.here(path),
            what=f"{path}/ in the current pane",
        )

    def show(self, case: Case) -> bool:
        """Press a case's key, wait for the state it names, and say whether
        the screen moved off the one before the press.

        Its folder's landmark first, which a case pressed in the folder it is
        already in has on screen at once, so the coloured screen has to move
        as well: `c_ramp`, `c_spread` and `c_hue` draw the same text in other
        colours, and a plain capture holds still on the case before as readily
        as on this one. What follows is the whole settle rather than the short
        one after a `goto`, because the same press switched the linemode and
        forced a peek, and either can repaint after the listing lands.

        Not for a `broken` case, which is pressed for its report rather than
        its screen, and whose screen can be the one before it: measured on
        26.9.1 with Yazi slowed, `b_zero` drew what `b_width` had drawn in
        nine presses of twelve, and each wait for it to move ran out.
        """
        was = self.session.capture(colour=True)
        self.session.keys(*case.key.split(" "))
        arrived = self.session.wait_for(
            self.here(case.folder),
            f"{case.folder}/ in the current pane after {case.key}",
            colour=True,
        )
        if not case.broken and arrived == was:
            self.session.wait_for(
                lambda s: s != was, f"{case.id} drawn", colour=True
            )
        return self.session.settle(colour=True) != was

    def theme(self, name: str, drawn: str) -> None:
        """Put a theme `cases.toml` lists in place, by its key, and wait for
        `drawn` -- an SGR body only that theme puts on the screen.

        A colour rather than a settle, because a theme rewrites no text. The
        key runs a script, and measured on 26.9.1 the first run of it from a
        fresh fixture lands its reload 0.23-0.74s after the key, against a
        plain settle that returns at about 0.57s whatever happened.
        """
        self.session.press(
            *self.listing.themes[name].key.split(" "),
            until=lambda s: drawn in s,
            what=f"{name}'s colours",
            colour=True,
        )
