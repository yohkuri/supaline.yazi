#!/usr/bin/env bash
#
# Render supaline in a real Yazi and print the resulting screen.
#
#   test/e2e.sh                   # a generated fixture directory
#   test/e2e.sh ~/some/dir        # any directory
#   test/e2e.sh ~/some/dir color  # keep the ANSI escapes, to inspect gradients
#
# This is the headless counterpart to manual.sh: same configuration, no
# keyboard. Yazi queries the terminal for its capabilities on startup and
# refuses to run if nothing answers, so `script`-style pseudo-terminals are not
# enough. tmux is a real terminal emulator, which makes this work.
#
# Nothing here touches your own configuration; the throwaway one is removed on
# exit.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-}"
MODE="${2:-plain}"
SESSION="supaline-e2e-$$"

for cmd in tmux yazi git; do
	command -v "$cmd" >/dev/null || {
		echo "e2e: $cmd is required" >&2
		exit 1
	}
done

WORK="$(mktemp -d)"
cleanup() {
	tmux kill-session -t "$SESSION" 2>/dev/null || true
	rm -rf "$WORK"
}
trap cleanup EXIT

# ASCII Git signs: the Nerd Font defaults are invisible in a text capture.
if [ -n "$TARGET" ]; then
	SUPALINE_ASCII_SIGNS=1 "$ROOT/test/setup.sh" "$WORK/config"
else
	TARGET="$WORK/fixture"
	SUPALINE_ASCII_SIGNS=1 "$ROOT/test/setup.sh" "$WORK/config" "$TARGET"
fi

# XDG_STATE_HOME too, so the log we grep below is this run's and not a shared
# one carrying errors from weeks ago.
tmux new-session -d -s "$SESSION" -x 120 -y 32 \
	"YAZI_CONFIG_HOME='$WORK/config' XDG_STATE_HOME='$WORK/state' COLORTERM=truecolor YAZI_LOG=debug yazi '$TARGET' 2>'$WORK/stderr'"

# Yazi negotiates with the terminal and the fetchers shell out; give it time.
sleep 5

# Since 26.8.15 Yazi starts on the *preset* theme and only merges theme.toml
# once the asynchronous terminal probe answers, at which point it fires the
# `theme` DDS event. A detached tmux session has no client to answer that probe,
# so the merge never happens on its own and the ASCII Git signs set up above
# would be left at their invisible Nerd Font defaults. `m t` is bound to
# `app:theme` by setup.sh; sending it forces the merge, and incidentally is the
# only thing that exercises supaline's `theme` subscription.
tmux send-keys -t "$SESSION" m
sleep 1
tmux send-keys -t "$SESSION" t
sleep 2

# The status bar carries a task counter, and it counts everything that has not
# *succeeded* -- so anything still running keeps it open too. Give the slow ones
# a moment to drain before reading it.
tasks_left() { grep -oE '[1-9][0-9]* left' "$WORK/screen" | head -1 || true; }

for _ in 1 2 3 4 5; do
	tmux capture-pane -p -t "$SESSION" >"$WORK/screen"
	[ -n "$(tasks_left)" ] || break
	sleep 1
done

# The plain capture above is what the checks below read; the escapes `color`
# mode keeps would only get in their way.
if [ "$MODE" = "color" ]; then
	tmux capture-pane -p -e -t "$SESSION"
else
	cat "$WORK/screen"
fi

log="$WORK/state/yazi/yazi.log"
if [ -f "$log" ] && grep -qiE '\blua\b.*(error|failed)' "$log"; then
	echo
	echo "=== Lua errors from this run ===" >&2
	grep -iE '\blua\b.*(error|failed)' "$log" >&2
	exit 1
fi

# A failing fetcher never reaches that log: Yazi keeps the reason in the task's
# own log, which nothing outside the `w` pane can read. The counter above is the
# only signal that escapes, which is why the 26.8.15 fetcher change sailed
# through this script rendering a plausible-looking screen.
remaining="$(tasks_left)"
if [ -n "$remaining" ]; then
	echo
	echo "=== $remaining: a task never succeeded ===" >&2
	echo "    Run test/manual.sh and press 'w' to read the reason." >&2
	exit 1
fi
