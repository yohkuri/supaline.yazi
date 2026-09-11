#!/bin/sh
# Build the throwaway Yazi configuration and the fixture both test harnesses
# use.
#
#     test/setup.sh <dir>           build the fixture in <dir>
#     test/setup.sh --clean <dir>   throw it away again
#
# `e2e.sh` and `manual.sh` both call this, so what a human looks at and what
# the headless run asserts on cannot drift apart. Nothing outside <dir> is
# touched, and your own Yazi configuration is never read.
#
# Both forms rewrite or remove <dir> wholesale, so both refuse it unless it is
# empty or carries the marker file this script leaves behind. That guard lives
# here alone: a harness that wrote its own `rm -rf` would be the copy that
# forgets it.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
MARKER=".supaline-fixture"

CLEAN=""
if [ "${1:-}" = "--clean" ]; then
	CLEAN=1
	shift
fi
DIR=${1:?usage: setup.sh [--clean] <dir>}
# Resolved before anything below changes directory. The fixture is built by
# `cd`-ing into it and then `cd`-ing again, so a relative <dir> was read against
# whichever directory the previous `cd` had left us in: `setup.sh
# relative-fixture` built half a fixture and then stopped on `cd: No such file
# or directory`. Not `cd "$DIR" && pwd`, which needs it to exist already, and
# this runs before it is created.
case $DIR in
/*) ;;
*) DIR="$PWD/$DIR" ;;
esac

if [ -e "$DIR" ] && [ ! -f "$DIR/$MARKER" ]; then
	echo "setup: $DIR exists and is not ours; move it aside" >&2
	exit 2
fi

rm -rf "$DIR"
[ -z "$CLEAN" ] || exit 0

# Stated, so the fixture carries the same modes whoever builds it. `e2e.sh`
# greps the permissions column for `drwxr-xr-x`, and under `umask 077` the
# directories come out `drwx------` -- the column right, the check failing.
# The files move too, `-rw-r--r--` to `-rw-------`.
umask 022

mkdir -p "$DIR/config/plugins" "$DIR/state"
mkdir -p "$DIR/fixture/data/nested" "$DIR/fixture/data/never-opened"
mkdir -p "$DIR/fixture/sibling-one" "$DIR/fixture/sibling-two"
: >"$DIR/$MARKER"
ln -sfn "$ROOT" "$DIR/config/plugins/supaline.yazi"

# --- fixture ---------------------------------------------------------------
# The harness opens `data/`, so everything worth looking at lives there: the
# current pane is the one that matters. `fixture/` holds a few siblings so the
# parent pane has rows of its own, and `nested/` gives the preview one.
#
# Sizes span five orders of magnitude, times span six years, and the names are
# the ones that break width arithmetic: CJK, emoji, and one far too long.
cd "$DIR/fixture/data"

: >empty.txt
printf 'x' >tiny.txt
dd if=/dev/zero of=under-1k.bin bs=1 count=1023 2>/dev/null
dd if=/dev/zero of=exactly-1k.bin bs=1 count=1024 2>/dev/null
dd if=/dev/zero of=widest-size.bin bs=1 count=1048000 2>/dev/null
dd if=/dev/zero of=medium.bin bs=1k count=800 2>/dev/null
dd if=/dev/zero of=large.bin bs=1k count=9000 2>/dev/null
dd if=/dev/zero of=huge.bin bs=1k count=90000 2>/dev/null

printf 'x' >"日本語のファイル名.txt"
printf 'x' >"絵文字🎨のなまえ.txt"
printf 'x' >"a-very-long-file-name-that-yazi-itself-has-to-truncate-away.txt"

ln -sfn medium.bin link-ok
ln -sfn nowhere-at-all link-broken
# Read-only rather than unreadable: a mode of 000 gives the permissions column
# something to show, but Yazi's own mime fetcher then fails on it and fills the
# log with errors the harness would have to learn to ignore.
printf 'x' >read-only.txt
chmod 400 read-only.txt

touch -t 202001020304 large.bin
touch -t 202312250000 medium.bin
touch -t 202405060708 huge.bin
touch -t 202601010000 under-1k.bin

printf 'x' >nested/inner-a.txt
dd if=/dev/zero of=nested/inner-b.bin bs=1k count=300 2>/dev/null
touch -t 202312250000 nested/inner-a.txt
printf 'x' >never-opened/hidden-away.txt

cd "$DIR/fixture"
printf 'x' >sibling-one/one.txt
dd if=/dev/zero of=sibling-two/two.bin bs=1k count=64 2>/dev/null

# --- the colour fixture ----------------------------------------------------
# A colour case is a *folder*. Where a row lands on a ramp is `ctx.ratio`, and
# that normalises against the extremes of the folder being drawn -- so the
# spread of values in front of you is the whole of what decides which part of a
# ramp reaches the screen, and the only way to choose that spread is to choose
# the folder.
#
# `data/` holds whatever the width cases needed, which makes it a poor
# instrument for looking at colour: its mtimes land on five of the ramp's steps,
# four of them in the top third, and a dozen rows share the highest. Nothing
# there is adjacent, so the question `MANUAL.md` puts to a reader -- can you
# tell one step from the next -- cannot be asked in it at all.
#
# Each folder below is one distribution that question needs, and nothing else
# is in them. A fourth is three edits: a folder here, a linemode in `init.lua`,
# and a key in `keymap.toml`.
mkdir -p colour/ramp colour/scale colour/edge

# One file per ramp step. Read out of `colour.lua` rather than written here: a
# fixture that claimed one row per step while `STEPS` had moved would be a
# quieter kind of wrong than a harness that stops.
STEPS=$(sed -n 's/^local STEPS = \([0-9][0-9]*\)$/\1/p' "$ROOT/colour.lua")
if [ -z "$STEPS" ] || [ "$STEPS" -gt 1440 ]; then
	echo "setup: cannot read a usable STEPS out of colour.lua (got '${STEPS:-nothing}')" >&2
	echo "setup: the ramp folder spaces its files one minute apart, so it needs a day's worth" >&2
	exit 2
fi

# `mtime` is linear -- only `size` sets `scale = "log"` -- so evenly spaced
# minutes are evenly spaced ratios, and consecutive files land on consecutive
# steps.
#
# The year is in the past on purpose. `mtime` draws another year as
# `MM/DD  YYYY`, so every one of these rows carries the *same text* and the only
# thing that differs down the column is the colour, which is the comparison a
# reader is being asked to make. The step number is in the name instead, so a
# row can still be named out loud.
i=0
while [ "$i" -lt "$STEPS" ]; do
	f=$(printf 'step-%02d.txt' "$i")
	: >"colour/ramp/$f"
	touch -t "20200101$(printf '%02d%02d' $((i / 60)) $((i % 60)))" "colour/ramp/$f"
	i=$((i + 1))
done

# Sizes doubling from 1B, which is what makes `scale` visible: under `log` the
# steps come out evenly spaced, and under `linear` everything but the largest
# few collapses into the ramp's bottom step. Twenty-one of them is twenty
# doublings and 2MB on disk, which is enough of both.
i=0
while [ "$i" -le 20 ]; do
	f=$(printf 'pow-%02d.bin' "$i")
	if [ "$i" -lt 10 ]; then
		dd if=/dev/zero of="colour/scale/$f" bs=1 count=$((1 << i)) 2>/dev/null
	else
		dd if=/dev/zero of="colour/scale/$f" bs=1024 count=$((1 << (i - 10))) 2>/dev/null
	fi
	i=$((i + 1))
done

# Both rules a ramp falls back on when it has nothing to spread itself over,
# on one screen.
#
# Every value here is the same -- four files of three bytes, and mtimes stamped
# equal across the lot -- so `hi == lo`, and `ratio` answers 1 rather than
# dividing by nothing. Every row that has a value draws the ramp's *high* end.
# Not its low one, and not the flat ground underneath it.
#
# The two directories are the other rule, and they are a pair because the pair
# is what makes it legible. `size` has nothing to place for either of them:
# `file:size()` is nil for a directory, so the count is drawn as *text* and
# `ctx.base` -- the ramp's low end -- as its colour, and the ratio never hears
# about it. `unlisted-a` is listed the moment the preview reads it, so it shows
# a count; `unlisted-b` is one row further down and never is, so it shows `-`.
# Three entries each, to put that count in the same shape as the `3B` beside
# it: two cells reading nearly the same and coloured from opposite ends is the
# misreading this folder exists to correct.
#
# The directories are stamped along with the files, and after the files inside
# them, which is what moved their mtimes in the first place. A directory
# carries one like anything else, so leaving them at "now" would put a second
# value in that column and leave no `hi == lo` there to look at.
for f in same-a.txt same-b.txt same-c.txt same-d.txt; do
	printf 'xxx' >"colour/edge/$f"
done
for d in unlisted-a unlisted-b; do
	mkdir -p "colour/edge/$d"
	for f in one two three; do
		printf 'x' >"colour/edge/$d/$f.txt"
	done
done
touch -t 202312250000 colour/edge/same-*.txt colour/edge/unlisted-a colour/edge/unlisted-b

cd "$ROOT"

# --- configuration ---------------------------------------------------------
cat >"$DIR/config/yazi.toml" <<'EOF'
[mgr]
linemode    = "default"
show_hidden = true
# Stated rather than left to the default, because `e2e.sh` goes to the top of
# `data/` and presses `l` expecting to land in `nested/`.
sort_dir_first = true
EOF

# Three themes rather than one, because swapping the file under a running Yazi
# is the only way to look at the reload by hand, and editing it in a second
# terminal is enough friction that nobody does. `c 1` to `c 3` copy one of
# these over `config/theme.toml` and send `app:theme`; the harness rebuilds the
# whole directory on every run, so whichever one is left behind costs nothing.
#
# `default.toml` is what Yazi opens with, and `e2e.sh` rewrites it in place --
# it greps for these exact values, so change them there too.
mkdir -p "$DIR/themes"

# One field is a style table and the other three are strings, because the custom
# theme section accepts either shape and both have to resolve. Add a `[flavor]`
# here if you want to see the columns against a real flavour.
#
# `mtime` is a ramp rather than a colour, which a theme can only say as a
# string: Yazi refuses an array in a custom section and takes the whole file
# down with it. The fixture's mtimes span 2020 to today, so both ends of that
# ramp are on screen, which is what `e2e.sh` checks for.
cat >"$DIR/themes/default.toml" <<'EOF'
[supaline]
size  = { fg = "#ff8800" }
mtime = "#0b3d91 -> #7fd4ff"
owner = "blue"
ext   = "magenta"
EOF

# Every field different, and the ramp's endpoints furthest of all: a reload that
# rebuilt the flat colours and kept a cached ramp looks almost right, so what
# tells the two apart is a ramp whose new ends share nothing with its old ones.
cat >"$DIR/themes/alt.toml" <<'EOF'
[supaline]
size  = { fg = "#00ccff" }
mtime = "#5d0b91 -> #ffb37f"
owner = "green"
ext   = "yellow"
EOF

# Backgrounds, and the one thing the theme grammar cannot say. A style table
# carries `bg` through to the column, so `size` and `owner` here are drawn on a
# ground of their own. `mtime` cannot be: a ramp has to be written as a string,
# a string has no room for a second colour, and a themed ramp is patched onto an
# empty ground -- so it comes out with no background at all while the columns
# either side of it have one. A ramp over a background is a `base` in the spec,
# which is what `c g` shows.
cat >"$DIR/themes/bg.toml" <<'EOF'
[supaline]
size  = { fg = "#ffe9d6", bg = "#7a2d00" }
mtime = "#0b3d91 -> #7fd4ff"
owner = { fg = "#d6e9ff", bg = "#00337a" }
ext   = "magenta"
EOF

cp "$DIR/themes/default.toml" "$DIR/config/theme.toml"

# Yazi's own linemode leader is `m`, and it only binds letters, so the digits
# are free. `m s` and `m n` still reach Yazi's built-ins, which is what makes
# them worth comparing against.
#
# The order climbs: m0 to m2 are the built-in columns at increasing richness,
# m3 to m5 the layout decisions, m6 to m8 the panes, and m9 extensibility.
cat >"$DIR/config/keymap.toml" <<'EOF'
[[mgr.prepend_keymap]]
on   = "T"
run  = "app:theme"
desc = "Reload the theme"

[[mgr.prepend_keymap]]
on   = [ "m", "0" ]
run  = "linemode plain"
desc = "supaline: one column, to compare against m s"

[[mgr.prepend_keymap]]
on   = [ "m", "1" ]
run  = "linemode default"
desc = "supaline: size + mtime"

[[mgr.prepend_keymap]]
on   = [ "m", "2" ]
run  = "linemode everything"
desc = "supaline: every built-in column"

[[mgr.prepend_keymap]]
on   = [ "m", "3" ]
run  = "linemode widths"
desc = "supaline: fixed vs auto width"

[[mgr.prepend_keymap]]
on   = [ "m", "4" ]
run  = "linemode overflow"
desc = "supaline: ellipsis / clip / grow"

[[mgr.prepend_keymap]]
on   = [ "m", "5" ]
run  = "linemode seps"
desc = "supaline: separators"

[[mgr.prepend_keymap]]
on   = [ "m", "6" ]
run  = "linemode pane_cur"
desc = "supaline: panes = current"

[[mgr.prepend_keymap]]
on   = [ "m", "7" ]
run  = "linemode pane_par"
desc = "supaline: panes = current + parent"

[[mgr.prepend_keymap]]
on   = [ "m", "8" ]
run  = "linemode pane_prev"
desc = "supaline: panes = current + preview"

[[mgr.prepend_keymap]]
on   = [ "m", "9" ]
run  = "linemode custom"
desc = "supaline: user-written columns"
EOF

# The colour keys, in a heredoc of their own because these need `$DIR`
# expanded and the block above must not be.
#
# Two leaders, because a colour case has two halves that move independently.
# `g` says **where you are**, which is the spread of values a ramp is stretched
# over; `c` says **how it is coloured**, which is the linemode or the theme. A
# treatment key deliberately does not move you, so flipping between two of them
# holds the folder, the scroll position and the hover still and changes exactly
# one thing -- which is the whole of what comparing two colour treatments is.
#
# `g` and `c` are both Yazi's own leaders and both bind only letters under
# themselves, so the digits are free the way they are under `m`. The four
# letters `c` does take -- `c c`, `c d`, `c f`, `c n`, all of them copying a
# path to the clipboard -- are avoided rather than shadowed, since there is no
# reason to spend them; `prepend_keymap` would win if they were.
#
# Absolute paths, so `cd` lands the same way wherever the key is pressed from.
# That is the point of binding navigation at all: `e2e.sh` used to reach
# `nested/` by going to the top of the listing and pressing `l`, which quietly
# made every check that needed that folder depend on what else happened to sort
# above it in `data/`.
cat >>"$DIR/config/keymap.toml" <<EOF

[[mgr.prepend_keymap]]
on   = [ "g", "1" ]
run  = "cd $DIR/fixture/data"
desc = "supaline: go to the layout fixture"

[[mgr.prepend_keymap]]
on   = [ "g", "2" ]
run  = "cd $DIR/fixture/data/nested"
desc = "supaline: go to a folder whose widest size differs"

[[mgr.prepend_keymap]]
on   = [ "g", "3" ]
run  = "cd $DIR/fixture/colour/ramp"
desc = "supaline: go to one file per ramp step"

[[mgr.prepend_keymap]]
on   = [ "g", "4" ]
run  = "cd $DIR/fixture/colour/scale"
desc = "supaline: go to sizes doubling from 1B"

[[mgr.prepend_keymap]]
on   = [ "g", "5" ]
run  = "cd $DIR/fixture/colour/edge"
desc = "supaline: go to the degenerate distributions"

[[mgr.prepend_keymap]]
on   = [ "c", "r" ]
run  = "linemode c_ramp"
desc = "supaline: a ramp that climbs in every channel"

[[mgr.prepend_keymap]]
on   = [ "c", "h" ]
run  = "linemode c_hue"
desc = "supaline: a ramp that turns in hue"

[[mgr.prepend_keymap]]
on   = [ "c", "g" ]
run  = "linemode c_bg"
desc = "supaline: a ramp over a background"

[[mgr.prepend_keymap]]
on   = [ "c", "s" ]
run  = "linemode c_scale"
desc = "supaline: log beside linear"

[[mgr.prepend_keymap]]
on   = [ "c", "e" ]
run  = "linemode c_edge"
desc = "supaline: a ramp with nothing to spread over"

[[mgr.prepend_keymap]]
on   = [ "c", "t" ]
run  = "linemode c_theme"
desc = "supaline: the colours the theme decides"

[[mgr.prepend_keymap]]
on   = [ "c", "1" ]
run  = "shell '$DIR/test-theme.sh default' --confirm"
desc = "supaline: theme -- the default [supaline]"

[[mgr.prepend_keymap]]
on   = [ "c", "2" ]
run  = "shell '$DIR/test-theme.sh alt' --confirm"
desc = "supaline: theme -- every field moved"

[[mgr.prepend_keymap]]
on   = [ "c", "3" ]
run  = "shell '$DIR/test-theme.sh bg' --confirm"
desc = "supaline: theme -- flat colours with backgrounds"
EOF

# The copy is a script rather than a `cp` spelled out three times in the
# keymap, because the keymap is TOML inside a shell heredoc inside a `shell`
# template: a path with a space in it -- `$TMPDIR` on a Mac is under
# `/var/folders/`, but `--clean` takes any directory a person names -- would
# have to survive all three quotings, and one of them is Yazi's own template
# parser rather than a shell's. One `"$@"` here, and the keymap carries a name.
#
# The reload is emitted from in here, and that is not a preference. A keymap
# `run` of `[ "shell ... --confirm", "app:theme" ]` does not wait: measured on
# 26.9.1, the copy lands on disk and `app:theme` has already re-read the file
# before it, so the screen keeps the theme it had and `theme.toml` on disk says
# otherwise -- which looks exactly like a plugin that ignored the reload.
# `--block` does not fix it either; the theme stayed unapplied there too.
# `ya emit` after the copy does, because then the ordering is this script's.
cat >"$DIR/test-theme.sh" <<EOF
#!/bin/sh
# Put one of the fixture's themes where Yazi reads it, and ask for a reload.
# Called from the \`c 1\` to \`c 3\` keys.
set -eu
cp "$DIR/themes/\$1.toml" "$DIR/config/theme.toml"
ya emit app:theme
EOF
chmod +x "$DIR/test-theme.sh"

cat >"$DIR/config/init.lua" <<'EOF'
local supaline = require("supaline")

-- The ramp the colour linemodes below reach for when nothing else is the
-- point. It climbs in all three channels at once, which is what `e2e.sh` reads
-- it for; `c_hue` is the one that deliberately does not.
local COOL = "#0b3d91 -> #7fd4ff"

-- The background `c_bg` puts under that ramp. Picked by measurement rather
-- than taste, because it has to answer to two things at once: the terminal
-- ground it is *seen* against, which is the reader's and unknown here, and the
-- ramp steps that have to stay *readable* on it.
--
-- In Oklab it sits 0.21 from the nearest of seven common terminal grounds --
-- black, Mocha, One Dark, Gruvbox dark, Solarized dark, white, Solarized
-- light -- and 0.24 from the nearest of the sixty-four steps above. The value
-- that was here before, `#241a33`, was 0.02 from Mocha's `#1e1e2e`: a correct
-- background, drawn on every row, and invisible to anyone reading on one.
--
-- A near-neutral colour cannot win that, whatever its lightness, because every
-- terminal ground is near-neutral too and the distance has to come from
-- somewhere. So the candidates were saturated ones, and this is the one whose
-- two numbers above were both the largest.
local GROUND = "#8b0045"

-- User columns, registered through the same entry point the built-ins use.
supaline.column("ext", {
	width = 5,
	align = "left",
	base = "magenta",
	render = function(file, ctx) return file.url.ext or "", ctx.base end,
})

-- A one-cell marker. Every built-in is 5 to 12 cells wide and the parent pane
-- is an eighth of the terminal, so none of them can demonstrate `panes` there
-- without swallowing the file name; what fits at the edges is a marker.
supaline.column("mark", {
	width = 1,
	align = "left",
	base = "green",
	render = function(file, ctx) return file.cha.is_dir and "d" or "f", ctx.base end,
})

-- Names vary in length, which is what makes the overflow modes legible.
supaline.column("name", {
	width = 12,
	align = "left",
	render = function(file, ctx) return file.name, ctx.base end,
})

-- Where a row sits on the ramp, as a number, so a reader can name a row
-- instead of pointing at one. "The 0.50 row should look halfway between the
-- ends" is a judgement a person can make and report; "the middle one looks off"
-- is not, and that is the difference between a manual test and an impression.
--
-- Its own `stats`, over mtime, because `ctx` is per column: a column cannot
-- read the ratio of the one beside it, and this exists to say what the `mtime`
-- column next to it is doing. The two agree because the value and the scale
-- are the same, not because anything passes between them.
supaline.column("ratio", {
	width = 4,
	align = "right",
	stats = function(files)
		local min, max
		for i = 1, #files do
			local t = files[i].cha.mtime
			if t and t > 0 then
				if not min or t < min then
					min = t
				end
				if not max or t > max then
					max = t
				end
			end
		end
		return min and { min = min, max = max } or nil
	end,
	render = function(file, ctx)
		local r = ctx.ratio(file.cha.mtime)
		return r and string.format("%.2f", r) or "-", ctx.style(r)
	end,
})

-- The same name handed back as a renderable rather than a string, so the cut
-- goes through `Line:truncate` instead of `ui.truncate`. The two count
-- differently, and nothing else here takes that path.
supaline.column("name_line", {
	width = 12,
	align = "left",
	render = function(file, ctx) return ui.Line { ui.Span(file.name) }, ctx.base end,
})

supaline:setup({
	linemodes = {
		-- m0: one column, so `m s` is a fair comparison.
		plain = { "size" },

		-- m1: the everyday case, and the one the README opens with.
		default = { "size", "mtime" },

		-- m2: every built-in column at its own default width.
		everything = { "permissions", "owner", "size", "mtime", "count" },

		-- m3: the same value stated, measured, and measured with a cap. The
		-- stated width is deliberately wider than any size in the fixture, so the
		-- measured column beside it is visibly narrower from the first frame.
		widths = {
			{ "size", width = 10 },
			{ "size", width = "auto" },
			{ "owner", width = "auto", max_width = 8 },
		},

		-- m4: one name, four ways. Only the first should show "…", and the two
		-- clipped cells have to come out identical -- one is cut as a string and
		-- the other as a Line.
		overflow = {
			{ "name", overflow = "ellipsis" },
			{ "name", overflow = "clip" },
			{ "name_line", overflow = "clip" },
			{ "name", overflow = "grow" },
		},

		-- m5: the default separator, none at all, and one of your own.
		seps = {
			{ "ext" },
			{ "size", sep = false },
			{ "mtime", sep = "│" },
		},

		-- m6 to m8: the panes. The difference shows in the left and right
		-- panes, never in the middle one.
		-- `mark`, not `size` and `mtime`: Yazi gives the linemode priority
		-- over the file name, and those two are 19 cells against a parent
		-- pane 21 wide, so the names vanish entirely. What fits at the edges
		-- is a marker, which is what these panes are for.
		pane_cur = { "mark", panes = { "current" } },
		pane_par = { "mark", panes = { "current", "parent" } },
		pane_prev = { "mark", panes = { "current", "preview" } },

		-- m9: a registered user column, and an inline function.
		custom = {
			{ "ext" },
			{ "name", width = 8, overflow = "clip" },
			function(file, ctx) return file.cha.is_dir and "dir" or "file", ctx.base end,
		},

		-- The colour cases, `c r` to `c t`. Each is meant to be read in one of
		-- the folders under `colour/`, because the spread of values in the
		-- folder being drawn is what decides which part of a ramp reaches the
		-- screen; `MANUAL.md` says which goes with which.
		--
		-- Four of the five write their endpoints here rather than taking them
		-- from the theme, and that is the point: a spec's `base` or `ramp` wins
		-- over `[supaline]`, so these hold still while `c 1` to `c 3` swap the
		-- theme underneath them. `c_theme` colours nothing in the spec and is
		-- the one that moves. Two code paths, told apart by pressing a key.

		-- c r, in `colour/ramp`: one row per ramp step. Both columns carry the
		-- same ramp, so the number and the date are drawn in the same step and
		-- a disagreement between them is visible rather than inferred.
		c_ramp = {
			{ "ratio", ramp = COOL },
			{ "mtime", ramp = COOL },
		},

		-- c h, in `colour/ramp`: the same rows, on a ramp that turns in hue.
		-- `e2e.sh` reads a ramp per channel, which is a property of one that
		-- climbs in all three at once rather than of ramps in general -- navy to
		-- yellow drops the blue channel on the way through. So this is not
		-- merely a case nothing checks, it is the shape that check cannot be
		-- pointed at without going red on a correct gradient, and a reader is
		-- the only instrument left.
		c_hue = {
			{ "ratio", ramp = "#0b3d91 -> #ffd400" },
			{ "mtime", ramp = "#0b3d91 -> #ffd400" },
		},

		-- c g, in `colour/ramp`: a ramp over a ground carrying a background,
		-- beside the same ramp over no ground at all. `colour.styles` patches
		-- every step onto the ground and `patch` is field-wise, so the `bg` is
		-- meant to survive under sixty-four colours that know nothing about it.
		-- A theme cannot ask for this -- `themes/bg.toml` is where that runs
		-- out.
		--
		-- Two columns rather than one because the question is whether the `bg`
		-- is still there, and against a single band the only reference a reader
		-- has is their own terminal's ground. That is unknown from here, and
		-- for the value this used to carry it was the same colour.
		--
		-- The stated width is three cells wider than a date, and `fit` pads
		-- before the style is applied, so the band has to cover cells that
		-- carry no text. At its own width the column is exactly full on every
		-- row and that half of it could not be looked at: `mtime` is eleven
		-- wide in both of the formats it picks between.
		c_bg = {
			{ "mtime", ramp = COOL, width = 14 },
			{ "mtime", base = ui.Style():bg(GROUND), ramp = COOL, width = 14 },
		},

		-- c s, in `colour/scale`: the same size twice, log then linear, on one
		-- ramp. The sizes there double, so log spaces them evenly and linear
		-- collapses everything below the largest few onto the bottom step.
		--
		-- The separator is there because the two columns hold the same number
		-- and would otherwise read as one. It goes on the *second* of them: a
		-- `sep` is drawn before its own column, so one on the first is a
		-- separator with nothing on its left and is dropped -- which is what
		-- this linemode did until the screen was read rather than assumed.
		c_scale = {
			{ "size", scale = "log", ramp = COOL },
			{ "size", scale = "linear", ramp = COOL, sep = "│" },
		},

		-- c e, in `colour/edge`: a ramp with nothing to spread over. Every value
		-- there is the same, so `ratio` answers 1 and every row with a value
		-- draws the *high* end -- not the low one, and not the flat ground.
		--
		-- `size` is in this one and not in `c_ramp` because it is the column
		-- that can have no value at all: a directory has no size, so both of
		-- them draw the *low* end while the files beside them are at the high
		-- one. Both rules on one screen, and no step in between anywhere, which
		-- is what the two of them look like when they are working.
		c_edge = {
			{ "size", ramp = COOL },
			{ "ratio", ramp = COOL },
			{ "mtime", ramp = COOL },
		},

		-- c t, in `data/`: nothing coloured in the spec, so all four take
		-- whatever `[supaline]` says. This is the mode `T` and `c 1` to `c 3`
		-- act on, and the only one that does.
		c_theme = { "size", "mtime", "owner", "ext" },
	},
})
EOF
