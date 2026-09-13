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

# Every linemode the manual harness offers, so a broken one cannot hide. `e` is
# one of them: the digits ran out before the cases did, and `m e` is a key like
# any other.
for n in 0 1 2 3 4 5 6 7 8 9 e; do
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

# The colour linemodes, for the reason the loop above exists: an unregistered
# name is drawn as literal text and one that threw takes the rows with it, and
# neither of those surfaces anywhere until a person runs `manual.sh`. Each is
# pressed in the folder it is meant to be read in, because the spread of values
# in the folder being drawn is what decides what a ramp puts on screen.
#
# What this does *not* do is judge any of them. That is the whole point of
# their existing -- `MANUAL.md` says which questions a reader is the only
# instrument for, and `c_hue` is there precisely because the ramp check further
# down would go red on it while it was perfectly correct.
colour_shot() { # <g-key> <c-key> <label>
	tmux send-keys -t "$SESSION" g "$1"
	sleep 1
	tmux send-keys -t "$SESSION" c "$2"
	sleep 1
	shot "$3"
}
colour_shot 3 r c_ramp
colour_shot 3 b c_band
colour_shot 3 h c_hue
colour_shot 3 g c_bg
colour_shot 4 s c_scale
colour_shot 5 e c_edge
colour_shot 1 t c_theme

# m3 states one size column at 10 and measures the other, so the widths have to
# disagree -- and the measured one has to change when the folder does. `bind`'s
# per-folder cache key is the piece most likely to get that wrong.
#
# `g 2` rather than going to the top of the listing and pressing `l`, which is
# how this reached `nested/` until it did not have to. That spelling quietly
# made a check about per-folder width measurement depend on which entry sorted
# first in `data/`, so anything added to the fixture -- for a reason with
# nothing to do with widths -- could break it. The key `cd`s by absolute path.
tmux send-keys -t "$SESSION" m 3
sleep 1
tmux send-keys -t "$SESSION" g 2
sleep 2
shot "m3-nested"
tmux send-keys -t "$SESSION" g 1
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

# Last of all, because it replaces `theme.toml` wholesale and every check above
# reads a capture taken against the file this run had been editing in place.
#
# The `c 1` to `c 3` keys are the only part of either harness that leaves Yazi
# to do its work -- a `shell` template running a script that copies a theme into
# place -- and a person pressing one sees a colour that did not change, with no
# way to tell a plugin that ignored the reload from a `cp` that never ran. So
# the file is compared rather than the screen: this says the key reached the
# disk, and the check above already says a reload repaints.
tmux send-keys -t "$SESSION" c 2
sleep 2
tmux capture-pane -t "$SESSION" -p -e >"$DIR/theme-swapped.txt"

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
# A truecolor escape as tmux writes it, built from the colour as `setup.sh`
# writes it. Every colour asserted on below is a hex string that appears in
# `setup.sh` verbatim, so the two files can be grepped against each other;
# converting one by hand is how an assertion goes stale, and a stale one here
# reports a fixture edit as a plugin that stopped drawing.
sgr() { # <38|48> <#rrggbb>
	_h=${2#\#}
	_g=${_h#??}
	printf '%s;2;%d;%d;%dm' "$1" "$((0x${_h%????}))" "$((0x${_g%??}))" "$((0x${_h#????}))"
}

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
# Where the rows are, and what counts as one, in the single place that knows:
# row 3 clears the header, and 8 is inside the shortest listing any capture
# here holds.
have_rows() { # <summary> <capture>...
	summary=$1
	shift
	was=$fails
	for n in "$@"; do
		if ! sed -n '3,8p' "$DIR/screen-$n.txt" | grep -qE "[A-Za-z0-9]"; then
			fail "$n: the rows came back blank"
		fi
	done
	# An `if` rather than `[ ... ] && echo`, which every other check in this
	# file can spell that way and this one cannot. A failing `&&` list is exempt
	# from `set -e` where it stands on its own, but as the last command of a
	# function its status becomes the function's, and `have_rows` is then a
	# simple command that returned 1 -- so a single blank capture would take the
	# whole run down here, before the columns, the panes, the ramp or the theme
	# were looked at, and before the count at the bottom was printed.
	if [ "$fails" -eq "$was" ]; then
		echo "  $summary"
	fi
}
have_rows "m0 to m9 and me all have rows" m0 m1 m2 m3 m4 m5 m6 m7 m8 m9 me

# The same for the colour modes, which are reached by two keys rather than one
# and are read in folders of their own -- so a blank one here is as likely to be
# the key, or the `cd` behind it, as the linemode. Which of the three it was is
# not worth telling apart: nothing else in this run visits those folders, so
# without this the first person to find out would be a human at `manual.sh`.
have_rows "the seven colour modes all have rows" c_ramp c_band c_hue c_bg c_scale c_edge c_theme

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

# The owner column holds this machine's own `user:group`, so what its cell
# should say cannot be written down here -- it depends on how long that is.
# Read the cell off the screen and hold it against `id` instead: the text is
# whatever fits, and an ellipsis is there exactly when something was dropped.
# Two of them in a row was a real bug, and it can only appear on a machine whose
# name has to be cut, which is why this counts them rather than looking for one.
#
# The permissions field the search anchors on is a pattern rather than a
# literal, because a different umask draws a different one. What follows it is
# the owner text: a `user:group` carries no space, so the column's own padding
# delimits it, and no width arithmetic is needed to find where the text ends.
who="$(id -un):$(id -gn)"

# The one cell every m2 row agrees on, answered in `$cell` and empty when there
# was none or the rows disagreed -- `fail` has said which by then. A function
# rather than the triage written once per column, and not a subshell: `fail`
# counts in the shell it runs in, and a `$(...)` would throw that count away
# along with the shell.
cell_of() { # <label> <sed expression>
	cell=$(current_of m2 | sed -n "$2" | sort -u)
	if [ -z "$cell" ]; then
		fail "m2: no $1 on screen"
	elif [ "$(printf '%s\n' "$cell" | wc -l | tr -d ' ')" -ne 1 ]; then
		fail "m2: the rows disagree on the $1: $(printf '%s' "$cell" | tr '\n' ' ')"
		cell=""
	fi
}

# Whether a cell is what is left of a name once the column cut it: the text up
# to the ellipsis has to be a prefix of what `id` says, and a cell that fits
# carries no ellipsis to strip.
is_cut_of() { # <name> <cell>
	case $1 in "${2%…}"*) return 0 ;; esac
	return 1
}

cell_of "owner cell behind a permissions field" \
	's/^.*[-dl][rwxsStT-]\{9\} \([^ ][^ ]*\) .*$/\1/p'
seen=$cell
dots=$(printf '%s' "$seen" | grep -o '…' | wc -l | tr -d ' ')
if [ -z "$seen" ]; then
	: # `cell_of` has already said so
elif [ "$seen" = "$who" ]; then
	echo "  m2: the owner column holds \`$who\` whole, with no ellipsis"
elif [ "$dots" -ne 1 ]; then
	fail "m2: the owner cell carries $dots ellipses, wanted one -- \`$seen\`"
elif is_cut_of "$who" "$seen"; then
	echo "  m2: the owner column cuts \`$who\` with one ellipsis"
else
	fail "m2: the owner cell \`$seen\` is not a cut of \`$who\`"
fi

# `user` and `group` draw those same two names again, eight cells each rather
# than twelve shared, so each is cut on its own length and on most machines the
# pair comes out whole where `owner` beside it did not. Read as one capture --
# they are adjacent, and a pattern that found only one of them would not say
# which -- and held against `id` half by half, since either may be the one that
# had to be cut. The halves come off `$who` rather than a second `id`, so the
# two blocks cannot end up measuring against different names.
cell_of "user and group cells behind the owner one" \
	's/^.*[-dl][rwxsStT-]\{9\} [^ ][^ ]*  *\([^ ][^ ]*\)  *\([^ ][^ ]*\)  *.*$/\1:\2/p'
pair=$cell
if [ -n "$pair" ]; then
	bad=""
	is_cut_of "${who%%:*}" "${pair%%:*}" || bad="$bad \`${pair%%:*}\` is not a cut of \`${who%%:*}\`"
	is_cut_of "${who#*:}" "${pair#*:}" || bad="$bad \`${pair#*:}\` is not a cut of \`${who#*:}\`"
	if [ -n "$bad" ]; then
		fail "m2:$bad"
	else
		echo "  m2: the user and group columns hold the halves of \`$who\`"
	fi
fi

# m4 puts one over-long name through ellipsis, clip and grow, so the same row
# must carry all four renderings of it. Grepping the screen as a whole is not
# enough: Yazi truncates long names in the parent pane by itself, and that
# ellipsis would satisfy a looser check.
#
# The cells are given as one pattern, the separators and the padding between
# them included, so this reads the columns' widths as well as where each cut
# landed -- a cell that came back one short moves every space after it and the
# pattern stops matching.
overflow_row() { # <label> <name> <cells>
	n=$(grep -n "$2" "$DIR/screen-m4.txt" | head -1 | cut -d: -f1)
	if [ -z "$n" ]; then
		fail "m4: $1 -- no row on screen carries \`$2\`"
	elif sed -n "${n}p" "$DIR/screen-m4.txt" | grep -q "$3"; then
		echo "  m4: $1"
	else
		fail "m4: $1"
	fi
}

# `exactly-1k.bin` is 14 characters against a column of 12, and short enough
# that all four cells stay on screen. The two clips have to agree: a column that
# hands back a renderable is not a narrower column, and `Line:truncate` drops
# the character that lands exactly on the width, so the second of them read
# "exactly-1k." until `cell` asked for that cell back. Nothing else in the
# fixture takes the renderable path.
overflow_row "ellipsis, clip, a clipped renderable and grow, on one row" \
	"exactly-1k" "exactly-1k.… exactly-1k.b exactly-1k.b exactly-1k.bin"

# The same four against a name of wide characters, where a cut can land between
# a character's two cells and leave the column a cell short. Both of Yazi's
# truncations count characters where the screen counts cells, which is the trap
# `truncate_spec.lua` pins in the arithmetic; this is the one place it is read
# off a screen.
#
# "日本語のファイル名.txt" is 13 characters and 22 cells against a column of 12.
# Five of them and an ellipsis come to 11, so the ellipsis cell pads to 12 --
# that pad is the second space in the pattern, and it is what a cut landing mid
# character would take away. The two clips take six characters for 12 exactly
# and pad with none.
overflow_row "a wide name is cut between characters, and the cell still fills" \
	"日本語" "日本語のフ…  日本語のファ 日本語のファ 日本語のファイル名.txt"

# And the same again where the wide character is four bytes rather than three.
# Not one case twice: `🎨` and `日` are both one character of two cells, so a
# cut that measured bytes can be right about one name and wrong about the other.
# The emoji is in the fixture because `unicode-width` gives emoji presentation
# two cells, which `truncate_spec.lua` pins the stub against -- this is the same
# name read off a screen. "絵文字🎨のなまえ.txt" is 20 cells: four characters
# come to 10 and the ellipsis to 11, then the pad, and the clips take five for
# 12 exactly.
overflow_row "a four-byte character is cut and measured like any other" \
	"絵文字" "絵文字🎨の…  絵文字🎨のな 絵文字🎨のな 絵文字🎨のなまえ.txt"

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
# A separator that carries a colour is the one that goes in as a `ui.Span`, and
# `ui.Line` consumes a Span rather than copying it: one built while the linemode
# was compiled draws the first row and then stops the pane, which is a failure
# the text above cannot tell from a colour that never arrived.
check "m5: ... and that separator carries a colour" "$(sgr 38 '#ff00aa')" "$DIR/color-m5.txt"

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
# `differs` says a pane is not the one it is read against, which a pane drawing
# nothing at all satisfies too -- strip the columns and Yazi's own file names
# are left, and those differ from a marked row. This is the other half: the
# cells that pane was actually given.
current_holds() { # <label> <capture> <pattern>
	if current_of "$2" | grep -q "$3"; then
		echo "  $1"
	else
		fail "$1"
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

# A pane key has to hold for every row of the preview pane, not just the one Yazi
# marks `in_preview` -- it sets that on the previewed folder's cursor row alone,
# so a check that passes on one row proves nothing about the second.
drew=$(drawn_in_preview m8)
same "m8: preview pane drawn, both rows (drew $drew)" "$drew" "2"
same "m6: both edges left alone" "$(drawn_in_preview m6)" "0"

# `me` names the same two panes as m7 and gives each a list of its own. Read
# against m7, which hands one list to both, so it says the two agree about the
# parent pane and disagree about the middle one -- which is the whole of what a
# list per pane adds.
same "me: the parent pane draws what m7 drew" "$(parent_of me)" "$(parent_of m7)"
differs "me: the current pane draws columns of its own" "$(current_of me)" "$(current_of m7)"
# `ext` then `size`, on the one file in the fixture whose size is written to be
# read: five cells left-aligned, a separator, seven right-aligned.
current_holds "me: ... and they are the ext and size it was given" me "bin     1024B"
same "me: the pane nobody named is bare" "$(preview_of me)" "$bare_preview"

echo "== the ramp =="
# The ends and the steps between them are read in different folders, because no
# one folder shows both well.
#
# The ends are read off `m 1` in `data/`, where the ramp is the *themed* one:
# `[supaline] mtime` is `#0b3d91 -> #7fd4ff`, and the fixture's mtimes run from
# 2020 to today, so the oldest row draws the low end and a file the fixture just
# created draws the high one. tmux writes both out as truecolor. A column that
# resolved the ramp string as a flat colour, or failed to resolve it at all, can
# only put one colour on screen, and this is where that is caught.
#
# `colour/ramp` cannot do it: 64 rows, a window that shows the first 37 of them,
# and the high end at the bottom.
check "a themed ramp draws its low end" "$(sgr 38 '#0b3d91')" "$DIR/color-m1.txt"
check "... and its high end" "$(sgr 38 '#7fd4ff')" "$DIR/color-m1.txt"

# The steps between are read off `colour/ramp`, which exists for this. They used
# to be read off `data/` too, and that was as much as `data/` could give: its
# five distinct mtimes land on steps 1, 38, 42, 57 and 64 -- five colours out of
# 64, nothing at all in the bottom half, and no two of them adjacent. Ordering
# five scattered steps was the whole of what it proved, and it needed each row's
# date built into a sort key to do even that.
#
# In `colour/ramp` the rows *are* the ramp. One file per step with the mtimes a
# minute apart, named in the same order, so screen order is the sort key and
# every step from the first to wherever the window cuts off comes back.
#
# Each row carries the same ratio twice: once as the number, placed by a `stats`
# closure written in the fixture's own `init.lua`, and once as the date, placed
# by the built-in `mtime` column's. Two `stats` functions, two `ctx` tables, one
# step -- so the two cells agreeing is a check rather than a restatement.
ramp_rows() { # <label>
	# One pass, splitting on the divider itself: `$2` is the current pane, the
	# same field `current_of` takes. `E` is the truecolor escape both cells open
	# with, held in one place because what tells them apart is what follows it.
	awk -F"$BAR" '
		BEGIN { E = "38;2;[0-9]+;[0-9]+;[0-9]+m" }
		{
			ratio = ""
			when = ""
			text = ""
			# The ratio cell: an escape followed straight away by a number
			# between 0.00 and 1.00. A file name cannot match it -- digit, dot,
			# two digits -- and neither can the date beside it.
			if (match($2, E " *[01]\\.[0-9][0-9]")) {
				cell = substr($2, RSTART, RLENGTH)
				p = index(cell, "m")
				ratio = substr(cell, 6, p - 6)
				text = substr(cell, p + 1)
				gsub(/ /, "", text)
			}
			# The mtime cell, the same way `m 1` is read: an escape and then a
			# date, which nothing else on the row is.
			if (match($2, E "[0-9][0-9]/[0-9][0-9]")) {
				cell = substr($2, RSTART, RLENGTH)
				p = index(cell, "m")
				when = substr(cell, 6, p - 6)
			}
			if (ratio != "" && when != "") {
				print ratio, when, text
			}
		}
	' "$DIR/color-$1.txt"
}

# `monotone` is asked of one ramp and not the other, and which is which is a
# property of the ramp rather than of the plugin. `#0b3d91 -> #7fd4ff` climbs in
# all three channels at once and was measured to hold that across all 64 steps;
# `#0b3d91 -> #ffd400` turns in hue and reverses a channel on 49 of its 63
# transitions, so asking it here would go red on a gradient that is correct.
#
# What both are asked is that no step repeats the one above it. That holds for
# any ramp whose quantisation is doing anything at all -- measured, zero
# identical adjacent pairs on both of these -- and it is what fails when a ratio
# never reaches the ramp, or reaches only its ends.
ramp_faults() { # <rows> <monotone>
	printf '%s\n' "$1" | awk -v monotone="$2" '
		{
			n++
			if ($1 != $2) {
				print "row " n " drew its two cells in different colours (" $1 " and " $2 ")"
			}
			if (n > 1) {
				if ($1 == prev) {
					print "row " n " is the same colour as the row above it (" $1 ")"
				}
				if (monotone == 1) {
					split($1, c, ";")
					split(prev, q, ";")
					if (c[1] + 0 < q[1] + 0 || c[2] + 0 < q[2] + 0 || c[3] + 0 < q[3] + 0) {
						print "row " n " goes backwards (" prev " then " $1 ")"
					}
				}
				if ($3 + 0 < pt + 0) {
					print "row " n " has a smaller ratio than the row above it (" pt " then " $3 ")"
				}
			}
			prev = $1
			pt = $3
		}
	'
}

# The window is 40 rows and the header and the folder take some, so about 37 of
# the 64 reach a capture. The floor is well under that: what would drop it is a
# ramp that stopped drawing, and no terminal this runs in shows fewer.
RAMP_FLOOR=24

check_ramp() { # <label> <capture> <monotone>
	rows=$(ramp_rows "$2")
	count=$(printf '%s\n' "$rows" | grep -c '[^ ]' || true)
	faults=$(ramp_faults "$rows" "$3")
	if [ "$count" -lt "$RAMP_FLOOR" ]; then
		fail "$1: only $count row(s) carried a ramp colour, wanted $RAMP_FLOOR"
	elif [ -n "$faults" ]; then
		fail "$1: $(printf '%s' "$faults" | head -3 | tr '\n' ';')"
	else
		echo "  $1 ($count consecutive steps)"
	fi
}

# One file per step, so consecutive rows are consecutive steps and this is the
# only place the quantisation itself is read. What it still cannot ask is
# whether a reader can see one step from the next; `MANUAL.md` keeps that.
check_ramp "every step climbs, and none repeats the one above" c_ramp 1
# The same rows on a band, whose endpoints were derived rather than written.
# Monotone is asked of it for a reason of its own: every step of a band is the
# same colour at another exposure, so all three channels move together by
# construction -- measured over the 64 steps of `#0b3d91 <->`, zero reversals
# and zero identical adjacent pairs. A band that came back flat, or that turned
# on the way, is a derivation that went wrong rather than a ramp a user wrote.
check_ramp "a band climbs too, on endpoints nobody wrote" c_band 1
# The same rows on a ramp that turns in hue. Only half the question can be put
# to it, and that half is put here so the shape is not left with nothing.
check_ramp "a ramp that turns still draws a step per row" c_hue 0

# `c_bg` draws the same ramp twice: over a ground carrying `bg = #8b0045`, and
# over nothing. Three things have to hold, and a reader can check none of them
# against their own terminal's ground -- that ground is the very thing the band
# has to be told apart from, and until this fixture was measured the background
# it used was 0.02 away from a common one in Oklab.
#
#   - the `bg` survived `patch` under all sixty-four foregrounds
#   - it covers the cells the stated width pads with, rather than stopping at
#     the text, which is what `fit` padding before the style is applied is for
#   - the ungrounded column beside it did not pick one up
#
# A band that is missing and a band that is short are different bugs, so the
# width is measured rather than the rows counted. A band runs to the next escape
# of any kind: there is none inside one today, and one put there later would
# read here as a band that came back short.
ESC=$(printf '\033')
# Read off the fixture rather than written here, for the reason `sgr` exists:
# every other number this block asserts on is a hex string that appears in
# `setup.sh` verbatim, and a width stated twice is the one that goes stale
# quietly. Widen `c_bg`'s columns there for a reason to do with the manual case
# and, spelled as a literal, this would report it as `fit` padding in the wrong
# order -- the fixture moved, not the plugin.
BAND_CELLS=$(sed -n 's/.*base = ui\.Style():bg(GROUND).*width = \([0-9][0-9]*\).*/\1/p' "$DIR/config/init.lua")
# Splitting on the opening escape leaves one piece per band; a band runs to the
# next escape of any kind, which `sub` takes off the end of the piece. All three
# numbers come out of the one pass, so none of them is a count of lines that a
# `printf` invented.
counts=$(awk -v esc="$ESC" -v bg="$(sgr 48 '#8b0045')" -v want="$BAND_CELLS" '
	BEGIN {
		open = esc "\\[" bg
		tail = esc ".*"
	}
	{
		n = split($0, seg, open)
		if (n > 1) {
			rows++
		}
		for (i = 2; i <= n; i++) {
			sub(tail, "", seg[i])
			bands++
			if (length(seg[i]) != want) {
				narrow++
			}
		}
	}
	END { print bands + 0, rows + 0, narrow + 0 }
' "$DIR/color-c_bg.txt")
IFS=' ' read -r banded lines narrow <<EOF
$counts
EOF
if [ -z "$BAND_CELLS" ]; then
	fail "c_bg: no grounded column with a stated width in the fixture's init.lua, so there is no band to measure"
elif [ "$banded" -lt "$RAMP_FLOOR" ]; then
	fail "c_bg: only $banded row(s) carried a background, wanted $RAMP_FLOOR"
elif [ "$narrow" -gt 0 ]; then
	fail "c_bg: $narrow band(s) were not $BAND_CELLS cells wide -- the padding is where to look"
elif [ "$banded" -ne "$lines" ]; then
	fail "c_bg: $banded band(s) across $lines row(s), so a row carries more than one"
else
	echo "  a background survives the ramp, padding included ($banded rows)"
fi

echo "== theme =="
# `[supaline] size` starts at #ff8800 and the reload above made it #00ccff.
#
# Both halves are needed, and only the second discriminates. Until 26.9.1 the
# user's theme was merged inside the `app:theme` actor alone, so a capture
# taken before it proved a colour resolved at `setup` was the preset's; 26.9.1
# has `th.supaline` populated before `setup` runs, and that capture now proves
# nothing. A reload still does: it is `ps.sub("theme", build)` that repaints
# what is already on screen, and a plugin without it holds the old colour.
before=$(grep -c "$(sgr 38 '#ff8800')" "$DIR/theme-before.txt" || true)
stale=$(grep -c "$(sgr 38 '#ff8800')" "$DIR/theme-after.txt" || true)
after=$(grep -c "$(sgr 38 '#00ccff')" "$DIR/theme-after.txt" || true)
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
old_lo=$(grep -c "$(sgr 38 '#0b3d91')" "$DIR/theme-after.txt" || true)
old_hi=$(grep -c "$(sgr 38 '#7fd4ff')" "$DIR/theme-after.txt" || true)
new_lo=$(grep -c "$(sgr 38 '#1a5e00')" "$DIR/theme-after.txt" || true)
new_hi=$(grep -c "$(sgr 38 '#9bff66')" "$DIR/theme-after.txt" || true)
if [ "$new_lo" -gt 0 ] && [ "$new_hi" -gt 0 ] && [ "$old_lo" -eq 0 ] && [ "$old_hi" -eq 0 ]; then
	echo "  ... and rebuilds a ramp, not only a flat colour"
else
	fail "a theme reload did not rebuild the ramp (old=$old_lo/$old_hi new=$new_lo/$new_hi)"
fi

# `c 2` should have put `themes/alt.toml` where Yazi reads its theme from. This
# is the fixture's own plumbing rather than the plugin's, and it is checked here
# because nothing else can: the key leaves Yazi to run a script through a
# `shell` template, so it is the one path in either harness that can be broken
# by a quoting mistake, and what a person sees when it breaks is a colour that
# did not change -- indistinguishable from the plugin ignoring the reload.
# `themes/alt.toml` puts the ramp at `#5d0b91 -> #ffb37f`, where the reload
# above had left `#1a5e00 -> #9bff66`. Both halves are asked, because they fail
# separately: the file says the key reached the disk, and the screen says the
# reload that followed it was not lost on the way.
#
# The second half is not hypothetical. Spelled as a keymap `run` of
# [ "shell ... --confirm", "app:theme" ] the two race and the reload wins --
# measured on 26.9.1, `theme.toml` ends up correct on disk with the old colours
# still on screen, and `--block` does not change it. The emit comes from inside
# the script for that reason, and this is the check that would notice it going
# back.
swapped=$(grep -c "$(sgr 38 '#5d0b91')" "$DIR/theme-swapped.txt" || true)
stale=$(grep -c "$(sgr 38 '#1a5e00')" "$DIR/theme-swapped.txt" || true)
if ! cmp -s "$DIR/config/theme.toml" "$DIR/themes/alt.toml"; then
	fail "c 2 did not put themes/alt.toml in place"
elif [ "$swapped" -eq 0 ] || [ "$stale" -gt 0 ]; then
	fail "c 2 swapped the file but the screen kept the old ramp (new=$swapped old=$stale)"
else
	echo "  a theme key swaps the file and the screen follows"
fi

echo
sed -n '2,7p' "$DIR/screen-m7.txt"
echo

if [ "$fails" -gt 0 ]; then
	echo "e2e: $fails check(s) failed on Yazi $YAZI_VERSION" >&2
	exit 1
fi
echo "e2e: ok on Yazi $YAZI_VERSION"
