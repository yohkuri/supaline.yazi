#!/bin/sh
# Render supaline in a real Yazi and check what comes back.
#
# The unit tests stub the Yazi globals, so they can say nothing about
# rendering. This can, and it is the only thing that can: both layout bugs
# found so far were invisible to the unit tests until something drew them.
#
#     test/e2e.sh            run it
#     test/e2e.sh --keep     leave the scratch directory behind
#
# The configuration and the fixture come from `test/setup.sh`, which
# `manual.sh` also uses, so this and the interactive run cannot drift apart.
#
# Needs tmux. Yazi queries the terminal at startup and aborts if nothing
# answers, so a `script`-style pseudo-terminal will not do; tmux is a real
# terminal emulator. A detached tmux has no client to answer the probe either,
# which is why `app:theme` is sent by hand before anything is captured --
# without it the user's theme is never applied and every `th.*` read returns
# preset values.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR="${TMPDIR:-/tmp}/supaline-e2e"
SESSION="supaline-e2e"
KEEP=""
[ "${1:-}" = "--keep" ] && KEEP=1

for tool in tmux yazi; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "e2e: $tool is not on PATH" >&2
		exit 2
	}
done

"$ROOT/test/setup.sh" "$DIR"

# --- run -------------------------------------------------------------------
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -x 170 -y 40 \
	"env YAZI_CONFIG_HOME=$DIR/config XDG_STATE_HOME=$DIR/state YAZI_LOG=debug yazi '$DIR/fixture/data'"
sleep 4

# Everything up to here is drawn with preset colours, so this capture is what
# proves the theme was not applied before `app:theme` ran.
tmux capture-pane -t "$SESSION" -p -e >"$DIR/before-theme.txt"
tmux send-keys -t "$SESSION" T
sleep 2

shot() {
	tmux capture-pane -t "$SESSION" -p >"$DIR/screen-$1.txt"
	tmux capture-pane -t "$SESSION" -p -e >"$DIR/color-$1.txt"
}

# Every linemode the manual harness offers, so a broken one cannot hide.
for n in 0 1 2 3 4 5 6 7 8 9; do
	tmux send-keys -t "$SESSION" m "$n"
	sleep 1
	# Switching linemode does not re-peek the preview; move the hover to force
	# one, so the preview pane is drawn under the mode that is now active.
	tmux send-keys -t "$SESSION" j
	sleep 1
	tmux send-keys -t "$SESSION" k
	sleep 1
	shot "m$n"
done

tmux send-keys -t "$SESSION" q
sleep 1
tmux kill-session -t "$SESSION" 2>/dev/null || true

# --- check -----------------------------------------------------------------
LOG="$DIR/state/yazi/yazi.log"
fails=0

fail() {
	echo "  FAIL $1" >&2
	fails=$((fails + 1))
}

# The current pane is the middle column and the parent pane the left one, so a
# row's leading cells belong to the parent.
parent_of() { sed -n '3,8p' "$DIR/screen-$1.txt" | cut -c1-20; }

echo "== log =="
if [ -f "$LOG" ] && grep -qiE "ERROR|WARN|attempt to|error converting" "$LOG"; then
	grep -iE "ERROR|WARN|attempt to|error converting" "$LOG" | head -10 >&2
	fail "Yazi logged an error"
else
	echo "  clean"
fi

echo "== every linemode drew something =="
for n in 0 1 2 3 4 5 6 7 8 9; do
	if sed -n '3,8p' "$DIR/screen-m$n.txt" | grep -qE "[A-Za-z0-9]"; then
		:
	else
		fail "m$n drew an empty linemode"
	fi
done
[ "$fails" -eq 0 ] && echo "  m0 to m9 all drew"

echo "== columns =="
# `A && B || C` would run C when B fails, and shellcheck is right to say so.
check() { # <label> <pattern> <file>
	if grep -q "$2" "$3"; then
		echo "  $1"
	else
		fail "$1"
	fi
}

check "m0: size" "87.9M" "$DIR/screen-m0.txt"
check "m1: size + mtime" "87.9M 05/06  2024" "$DIR/screen-m1.txt"
check "m2: permissions" "drwxr-xr-x" "$DIR/screen-m2.txt"

# m4 puts one over-long name through ellipsis, clip and grow, so the same row
# must carry all three renderings of it. Grepping the screen as a whole is not
# enough: Yazi truncates long names in the parent pane by itself, and that
# ellipsis would satisfy a looser check.
# `exactly-1k.bin` is 14 characters against a column of 12, and short enough
# that all three cells stay on screen: "exactly-1k.…", "exactly-1k.b", and the
# name whole.
m4row=$(grep -n "exactly-1k" "$DIR/screen-m4.txt" | head -1 | cut -d: -f1)
if [ -z "$m4row" ]; then
	fail "m4: the fixture name to overflow is not on screen"
else
	row=$(sed -n "${m4row}p" "$DIR/screen-m4.txt")
	ok=1
	echo "$row" | grep -q "exactly-1k.…" || ok=""
	echo "$row" | grep -q "exactly-1k.b " || ok=""
	echo "$row" | grep -q "exactly-1k.bin" || ok=""
	if [ -n "$ok" ]; then
		echo "  m4: ellipsis, clip and grow all rendered on one row"
	else
		fail "m4: the three overflow modes did not render differently"
	fi
fi

echo "== panes =="
if parent_of m6 | grep -qE "[0-9]{2}/[0-9]{2}"; then
	fail "m6: the parent pane drew under panes = { current }"
else
	echo "  m6: parent pane left alone"
fi
if parent_of m7 | grep -qE "[0-9]{2}/[0-9]{2}"; then
	echo "  m7: parent pane drawn"
else
	fail "m7: the parent pane stayed bare under panes = { current, parent }"
fi
if parent_of m8 | grep -qE "[0-9]{2}/[0-9]{2}"; then
	fail "m8: the parent pane drew under panes = { current, preview }"
else
	echo "  m8: parent pane left alone"
fi

echo "== theme =="
# `[supaline] size` is #ff8800, which tmux writes out as 255;136;0.
before=$(grep -c '255;136;0' "$DIR/before-theme.txt" || true)
after=$(grep -c '255;136;0' "$DIR/color-m1.txt" || true)
if [ "$before" -eq 0 ] && [ "$after" -gt 0 ]; then
	echo "  base colour arrives with app:theme (before=$before after=$after)"
else
	fail "theme colour did not arrive with app:theme (before=$before after=$after)"
fi

echo
sed -n '2,7p' "$DIR/screen-m7.txt"
echo

if [ -z "$KEEP" ]; then
	rm -rf "$DIR"
else
	echo "kept: $DIR"
fi

if [ "$fails" -gt 0 ]; then
	echo "e2e: $fails check(s) failed" >&2
	exit 1
fi
echo "e2e: ok"
