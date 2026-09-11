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
# terminal emulator. A detached tmux never answers that probe, so
# `rt.term.light()` stays nil for the whole run -- 26.9.1 applies the user's
# theme anyway, a couple of milliseconds after `init.lua` and without being
# asked, which the first half of the theme check below confirms every run.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# Both names carry the PID, so a run owns everything it touches.
#
# A fixed session name would have to be cleared before `new-session` could take
# it, and clearing one this script did not start kills whatever was running
# inside it -- a concurrent run of this same script, or a session a person
# happened to name the same, along with its unsaved work. If the name is
# somehow taken, `new-session` fails and `set -e` stops the run.
#
# That is not enough on its own: the run is torn down from an EXIT trap, which
# is armed before the session exists and fires on that failure too. So the
# teardown asks whether this run got as far as starting one, rather than
# trusting the name -- a PID comes round again, and a session left behind by a
# previous run carries a name a later one is entitled to.
#
# A fixed scratch directory is no safer. `setup.sh` refuses one that does not
# carry its marker file, but a concurrent run of this script left that marker,
# so the guard passes and `rm -rf` takes the other run's fixture out from under
# its Yazi.
RUN=$$
DIR="${TMPDIR:-/tmp}/supaline-e2e.$RUN"
SESSION="supaline-e2e-$RUN"
KEEP=""
[ "${1:-}" = "--keep" ] && KEEP=1

for tool in tmux yazi; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "e2e: $tool is not on PATH" >&2
		exit 2
	}
done

# Every platform claim in AGENTS.md was established against one Yazi build, and
# Yazi is on CalVer: it changes the plugin API between releases, sometimes
# without saying so. Record which build this run actually proves anything
# about, and say so when it is not the one the plugin annotates itself for --
# that mismatch is the signal to go back and re-verify the constraints, not a
# reason to stop, since running against a newer Yazi is how you would find out.
YAZI_VERSION=$(yazi --version | sed -n 's/^[[:space:]]*Version:[[:space:]]*//p')
[ -n "$YAZI_VERSION" ] || YAZI_VERSION=$(yazi --version | tr '\n' ' ')
PINNED=$(sed -n '1s/^--- @since //p' "$ROOT/main.lua")
case "$YAZI_VERSION" in
"$PINNED"*) ;;
*) echo "e2e: note: Yazi is $YAZI_VERSION, the plugin annotates $PINNED" ;;
esac

STARTED=""
stop() {
	[ -n "$STARTED" ] || return 0
	tmux kill-session -t "$SESSION" 2>/dev/null || true
}

# Leave nothing behind when a check fails, or when the run is interrupted
# part-way -- the scratch directory now carries the PID, so one left lying
# around is one nothing will ever reuse. `exit` from a signal trap runs the
# EXIT one too, so this is the only place the run is torn down.
cleanup() {
	stop
	if [ -n "$KEEP" ]; then
		[ ! -d "$DIR" ] || echo "kept: $DIR"
	elif [ -d "$DIR" ]; then
		"$ROOT/test/setup.sh" --clean "$DIR"
	fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

"$ROOT/test/setup.sh" "$DIR"
echo "$YAZI_VERSION" >"$DIR/yazi-version.txt"

# --- run -------------------------------------------------------------------
tmux new-session -d -s "$SESSION" -x 170 -y 40 \
	"env YAZI_CONFIG_HOME='$DIR/config' XDG_STATE_HOME='$DIR/state' YAZI_LOG=debug yazi '$DIR/fixture/data'"
STARTED=1
sleep 4

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

# Last of everything, because it rewrites the theme that every capture above
# was taken under. Back to m1 first, so a `size` column and an `mtime` one are
# both on screen to be recoloured.
tmux send-keys -t "$SESSION" m 1
sleep 1
tmux capture-pane -t "$SESSION" -p -e >"$DIR/theme-before.txt"
# Both shapes a `[supaline]` value can take, because they are rebuilt by
# different code: a flat colour is one `ui.Style` and a ramp is `STEPS` of them,
# built from endpoints parsed out of the string. A ramp resolved once and cached
# past the reload would hold its old endpoints with the flat colour beside it
# already correct, and the flat half alone would not notice.
#
# Not `sed -i`: the two seds spell that flag differently and this is /bin/sh.
sed -e 's/#ff8800/#00ccff/' \
	-e 's/#0b3d91 -> #7fd4ff/#1a5e00 -> #9bff66/' \
	"$DIR/config/theme.toml" >"$DIR/theme-next.toml"
mv "$DIR/theme-next.toml" "$DIR/config/theme.toml"
tmux send-keys -t "$SESSION" T
sleep 2
tmux capture-pane -t "$SESSION" -p -e >"$DIR/theme-after.txt"

tmux send-keys -t "$SESSION" q
sleep 1
# Explicit rather than left to the trap: the checks below read what Yazi wrote,
# so it has to be gone before they run. The scratch directory stays until the
# trap fires.
stop

# --- check -----------------------------------------------------------------
LOG="$DIR/state/yazi/yazi.log"
fails=0

fail() {
	echo "  FAIL $1" >&2
	fails=$((fails + 1))
}

# The current pane is the middle column, so the parent pane is everything
# before the first divider and the preview pane everything past the last one.
# Both start on row 2, the first row under the header: the parent pane's first
# row is its hovered one, and a check that skipped it would be blind to exactly
# the single-row mistakes this suite exists to catch.
# Whole panes rather than a fixed column count: `cut -c` counts bytes here, and
# a row opening with a three-byte icon pushes a one-cell column past any window
# that looks wide enough. The preview's rows are `nested/`, two files.
parent_of() { sed -n '2,8p' "$DIR/screen-$1.txt" | sed 's/\xe2\x94\x82.*//'; }
preview_of() { sed -n '2,8p' "$DIR/screen-$1.txt" | sed 's/.*\xe2\x94\x82//'; }
# The current pane is the field between the two dividers, which neither `sed`
# above can take: each anchors on one divider and the middle needs both. `awk`
# splitting on the divider does, and reading it out of a variable keeps this
# file ASCII like the escapes above.
BAR=$(printf '\xe2\x94\x82')
current_of() { sed -n '2,8p' "$DIR/screen-$1.txt" | awk -F"$BAR" '{ print $2 }'; }
# A row that drew ends in the trio's one column: `mark`, a single "d" or "f"
# after the name. A bare row ends in the name itself.
drawn_in_preview() { preview_of "$1" | grep -cE " [df]$" || true; }
# The same, in the current pane, where the marker is not the last thing on the
# row: the hovered row carries a powerline glyph after it, and the others a
# space before the divider. Anything but a letter or a digit may follow, which
# still refuses a row ending in a file name.
drawn_in_current() { current_of "$1" | grep -cE " [df][^A-Za-z0-9]*$" || true; }
rows_in_current() { current_of "$1" | grep -c '[^ ]' || true; }

echo "== log =="
if [ -f "$LOG" ] && grep -qiE "ERROR|WARN|attempt to|error converting" "$LOG"; then
	grep -iE "ERROR|WARN|attempt to|error converting" "$LOG" | head -10 >&2
	fail "Yazi logged an error"
else
	echo "  clean"
fi

# What this proves is that Yazi is alive and every linemode name resolved: an
# unregistered one is drawn as literal text and a linemode that threw takes the
# rows with it. It does *not* prove any of them drew a column, because the file
# names satisfy it on their own -- m6 to m8 rendering nothing in the current
# pane passed this and every pane check below. The columns are what the two
# sections after it are for, and each mode has one.
echo "== every linemode left the rows on screen =="
for n in 0 1 2 3 4 5 6 7 8 9; do
	if sed -n '3,8p' "$DIR/screen-m$n.txt" | grep -qE "[A-Za-z0-9]"; then
		:
	else
		fail "m$n: the rows came back blank"
	fi
done
[ "$fails" -eq 0 ] && echo "  m0 to m9 all have rows"

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
	# The clipped string, the clipped Line, and the name whole. The two clips
	# have to agree: a column that hands back a renderable is not a narrower
	# column, and `Line:truncate` drops the character that lands exactly on the
	# width, so the second of them read "exactly-1k." until `cell` asked for
	# that cell back. Nothing else in the fixture takes the renderable path.
	echo "$row" | grep -q "exactly-1k.b exactly-1k.b exactly-1k.bin" || ok=""
	if [ -n "$ok" ]; then
		echo "  m4: ellipsis, clip, a clipped renderable and grow, on one row"
	else
		fail "m4: the overflow modes did not render as they should"
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
#
# The pass and fail arms are inverted between neighbouring checks here, which
# is exactly the shape that hides a mistake when it is spelled out five times.
# `same` and `differs` are the `check` of this section.
same() { # <label> <actual> <expected>
	if [ "$2" = "$3" ]; then
		echo "  $1"
	else
		fail "$1"
	fi
}
differs() { # <label> <actual> <unwanted>
	if [ "$2" = "$3" ]; then
		fail "$1"
	else
		echo "  $1"
	fi
}

bare_parent=$(parent_of m6)
bare_preview=$(preview_of m6)

# All three ask for the current pane, and until this check nothing looked at
# it: the loop above matches the file names, and everything below compares the
# other two panes against m6. A `pane_cur`, `pane_par` and `pane_prev` drawing
# nothing where they were asked to passed the whole suite.
for n in 6 7 8; do
	drew=$(drawn_in_current "m$n")
	rows=$(rows_in_current "m$n")
	same "m$n: every current-pane row carries the marker ($drew of $rows)" "$drew" "$rows"
done

differs "m7: parent pane drawn" "$(parent_of m7)" "$bare_parent"
same "m8: parent pane left alone" "$(parent_of m8)" "$bare_parent"
same "m7: preview pane left alone" "$(preview_of m7)" "$bare_preview"

# `panes` has to hold for every row of the preview pane, not just the one Yazi
# marks `in_preview` -- it sets that on the previewed folder's cursor row alone,
# so a check that passes on one row proves nothing about the second.
drew=$(drawn_in_preview m8)
same "m8: preview pane drawn, both rows (drew $drew)" "$drew" "2"
same "m6: both edges left alone" "$(drawn_in_preview m6)" "0"

echo "== the ramp =="
# `[supaline] mtime` is `#0b3d91 -> #7fd4ff`, and the fixture's mtimes run from
# 2020 to today, so the oldest row draws the ramp's low end and a file the
# fixture just created draws its high one. tmux writes those out as truecolor.
#
# Both ends together are the first check: a column that resolved the ramp string
# as a flat colour, or failed to resolve it at all, can only put one colour on
# screen.
check "a themed ramp draws its low end" "38;2;11;61;145" "$DIR/color-m1.txt"
check "... and its high end" "38;2;127;212;255" "$DIR/color-m1.txt"

# The rows *between* the ends are the half those two say nothing about: both of
# them land on screen whether or not anything in between does. Their colours
# cannot be pinned by value -- the top of the range is whenever the fixture was
# built, so every ratio but the lowest moves as the fixture ages -- but their
# order can be, and the order is what a reader sees as a gradient.
#
# Each mtime cell opens with a truecolor escape followed straight away by the
# date, which nothing else on the row does, so one pass picks up every row the
# column drew. The date becomes a sort key: `MM/DD  YYYY` for a file from
# another year and `MM/DD HH:MM` for one from this one, which is the choice
# `mtime` makes per file.
ramp_rows=$(awk -v year="$(date +%Y)" '
	{
		rest = $0
		while (match(rest, /38;2;[0-9]+;[0-9]+;[0-9]+m[0-9][0-9]\/[0-9][0-9] [ 0-9][0-9][0-9:][0-9][0-9]/)) {
			cell = substr(rest, RSTART, RLENGTH)
			rest = substr(rest, RSTART + RLENGTH)
			m = index(cell, "m")
			rgb = substr(cell, 6, m - 6)
			when = substr(cell, m + 1)
			tail = substr(when, 7)
			if (index(tail, ":") > 0) {
				print year substr(when, 1, 2) substr(when, 4, 2) substr(tail, 1, 2) substr(tail, 4, 2), rgb
			} else {
				sub(/ /, "", tail)
				print tail substr(when, 1, 2) substr(when, 4, 2) "0000", rgb
			}
		}
	}
' "$DIR/color-m1.txt" | sort -u)

# Per channel, which is a property of *this* ramp rather than of ramps in
# general: `#0b3d91 -> #7fd4ff` climbs in all three channels at once, and its 64
# steps were measured to hold that the whole way. Point the fixture at a ramp
# that turns in hue -- navy to yellow drops the blue channel -- and this check
# starts failing on a gradient that is perfectly correct. It fails loudly rather
# than quietly, so the fixture's ramp is free to move; this comment is the note
# saying what moves with it.
backwards=$(printf '%s\n' "$ramp_rows" | awk -F'[ ;]' '
	NR > 1 && ($2 < r || $3 < g || $4 < b) { print $1 }
	{ r = $2; g = $3; b = $4 }
')
steps=$(printf '%s\n' "$ramp_rows" | cut -d' ' -f2 | sort -u | wc -l | tr -d ' ')
if [ -z "$ramp_rows" ]; then
	fail "no row carried a ramp colour beside its date"
elif [ -n "$backwards" ]; then
	fail "the ramp goes backwards at $(printf '%s\n' "$backwards" | tr '\n' ' ')"
elif [ "$steps" -lt 3 ]; then
	# One colour means the ratio never reached the ramp; two means it reached
	# only the ends. Three is the least that says a middle step was drawn, and
	# the fixture's five distinct mtimes currently give five.
	fail "the ramp drew no step between its ends ($steps colour(s))"
else
	echo "  the steps between climb with the date ($steps distinct colours)"
fi

echo "== theme =="
# `[supaline] size` starts at #ff8800 and the reload above made it #00ccff.
# tmux writes those out as 255;136;0 and 0;204;255.
#
# Both halves are needed, and only the second discriminates. Until 26.9.1 the
# user's theme was merged inside the `app:theme` actor alone, so a capture
# taken before it proved a colour resolved at `setup` was the preset's; 26.9.1
# has `th.supaline` populated before `setup` runs, and that capture now proves
# nothing. A reload still does: it is `ps.sub("theme", build)` that repaints
# what is already on screen, and a plugin without it holds the old colour.
before=$(grep -c '255;136;0' "$DIR/theme-before.txt" || true)
stale=$(grep -c '255;136;0' "$DIR/theme-after.txt" || true)
after=$(grep -c '0;204;255' "$DIR/theme-after.txt" || true)
if [ "$before" -gt 0 ]; then
	echo "  the themed base colour is drawn ($before cells)"
else
	fail "the themed base colour never reached the screen"
fi
if [ "$after" -gt 0 ] && [ "$stale" -eq 0 ]; then
	echo "  a theme reload rebuilds the columns ($after cells recoloured)"
else
	fail "a theme reload did not rebuild the columns (old=$stale new=$after)"
fi

# The ramp beside it went from `#0b3d91 -> #7fd4ff` to `#1a5e00 -> #9bff66`.
# That is a different piece of code reloading: a flat colour is one `ui.Style`
# resolved from the value, a ramp is `STEPS` of them built by `colour.styles`
# from endpoints parsed out of the string. Both new ends have to be on screen
# and neither old one left anywhere -- a ramp cached past the reload would keep
# its old endpoints with the flat colour beside it already correct.
old_lo=$(grep -c '38;2;11;61;145m' "$DIR/theme-after.txt" || true)
old_hi=$(grep -c '38;2;127;212;255m' "$DIR/theme-after.txt" || true)
new_lo=$(grep -c '38;2;26;94;0m' "$DIR/theme-after.txt" || true)
new_hi=$(grep -c '38;2;155;255;102m' "$DIR/theme-after.txt" || true)
if [ "$new_lo" -gt 0 ] && [ "$new_hi" -gt 0 ] && [ "$old_lo" -eq 0 ] && [ "$old_hi" -eq 0 ]; then
	echo "  ... and rebuilds a ramp, not only a flat colour"
else
	fail "a theme reload did not rebuild the ramp (old=$old_lo/$old_hi new=$new_lo/$new_hi)"
fi

echo
sed -n '2,7p' "$DIR/screen-m7.txt"
echo

if [ "$fails" -gt 0 ]; then
	echo "e2e: $fails check(s) failed on Yazi $YAZI_VERSION" >&2
	exit 1
fi
echo "e2e: ok on Yazi $YAZI_VERSION"
