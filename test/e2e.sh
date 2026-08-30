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
	"env YAZI_CONFIG_HOME='$DIR/config' XDG_STATE_HOME='$DIR/state' YAZI_LOG=debug yazi '$DIR/fixture/data'"
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

# m3 states one size column at 10 and measures the other, so the widths have to
# disagree -- and the measured one has to change when the folder does. Nothing
# else in this run crosses a folder boundary, and `bind`'s per-folder cache key
# is the piece most likely to get it wrong.
tmux send-keys -t "$SESSION" m 3
sleep 1
tmux send-keys -t "$SESSION" g g
sleep 1
tmux send-keys -t "$SESSION" l
sleep 2
shot "m3-nested"
tmux send-keys -t "$SESSION" h
sleep 1

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

# The current pane is the middle column, so the parent pane is everything
# before the first divider and the preview pane everything past the last one.
# Whole panes rather than a fixed column count: `cut -c` counts bytes here, and
# a row opening with a three-byte icon pushes a one-cell column past any window
# that looks wide enough. The preview's rows are `nested/`, two files.
parent_of() { sed -n '3,8p' "$DIR/screen-$1.txt" | sed 's/\xe2\x94\x82.*//'; }
preview_of() { sed -n '2,8p' "$DIR/screen-$1.txt" | sed 's/.*\xe2\x94\x82//'; }
# A row that drew ends in the trio's one column: `mark`, a single "d" or "f"
# after the name. A bare row ends in the name itself.
drawn_in_preview() { preview_of "$1" | grep -cE " [df]$" || true; }

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

# m3: `size` stated at 10 beside `size` measured. In `data/` the widest size is
# "1023.4K", so the measured column is 7 and the two are three spaces apart.
check "m3: a stated width and a measured one differ" "1024B   1024B" "$DIR/screen-m3.txt"
# ... and in `nested/` the widest is "300K", so the measured column narrows to 4.
check "m3: the measured width follows the folder" "      300K 300K" "$DIR/screen-m3-nested.txt"
# Neither of those pins the *stated* column: Yazi absorbs whatever the linemode
# does not use into the file name's padding, so the spaces to the left of the
# first column stay put however wide it is. The one row that cannot absorb
# anything is the one whose name Yazi had to truncate -- there the name fills
# its budget exactly, so the gap after it is the stated column's own padding:
# one space of separator, then 10 less the two cells of "1B".
check "m3: a stated width does not shrink to fit" "….txt         1B" "$DIR/screen-m3.txt"

# m5: `ext` (5, left), then `size` with `sep = false`, then `mtime` behind "│".
check "m5: sep = false and a separator of one's own" "bin    1024B│" "$DIR/screen-m5.txt"

# m9: a registered column, one clipped to 8 without an ellipsis, and a bare
# function in the spec.
check "m9: user-written columns" "bin   exactly- file" "$DIR/screen-m9.txt"
check "m9: a clipped cell carries no ellipsis" "never-op " "$DIR/screen-m9.txt"

echo "== panes =="
# m6 asks for the current pane alone, so its edges are exactly what Yazi draws
# with no linemode at all -- the baseline for the other two. Comparing whole
# panes rather than grepping for a column keeps this independent of which
# columns the fixture happens to use.
bare_parent=$(parent_of m6)
bare_preview=$(preview_of m6)

if [ "$(parent_of m7)" = "$bare_parent" ]; then
	fail "m7: the parent pane stayed bare under panes = { current, parent }"
else
	echo "  m7: parent pane drawn"
fi
if [ "$(parent_of m8)" = "$bare_parent" ]; then
	echo "  m8: parent pane left alone"
else
	fail "m8: the parent pane drew under panes = { current, preview }"
fi
if [ "$(preview_of m7)" = "$bare_preview" ]; then
	echo "  m7: preview pane left alone"
else
	fail "m7: the preview pane drew under panes = { current, parent }"
fi

# `panes` has to hold for every row of the preview pane, not just the one Yazi
# marks `in_preview` -- it sets that on the previewed folder's cursor row alone,
# so a check that passes on one row proves nothing about the second.
if [ "$(drawn_in_preview m8)" -eq 2 ]; then
	echo "  m8: preview pane drawn, both rows"
else
	fail "m8: the preview pane drew $(drawn_in_preview m8) of 2 rows"
fi
if [ "$(drawn_in_preview m6)" -eq 0 ]; then
	echo "  m6: both edges left alone"
else
	fail "m6: the preview pane drew under panes = { current }"
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
