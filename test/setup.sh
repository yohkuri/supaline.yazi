#!/bin/sh
# Build the throwaway Yazi configuration and the fixture both test harnesses
# use.
#
#     test/setup.sh <dir>
#
# `e2e.sh` and `manual.sh` both call this, so what a human looks at and what
# the headless run asserts on cannot drift apart. Nothing outside <dir> is
# touched, and your own Yazi configuration is never read.
#
# <dir> is rewritten wholesale, so it is refused unless it is empty or carries
# the marker file this script leaves behind.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR=${1:?usage: setup.sh <dir>}
MARKER=".supaline-fixture"

if [ -e "$DIR" ] && [ ! -f "$DIR/$MARKER" ]; then
	echo "setup: $DIR exists and is not ours; move it aside" >&2
	exit 2
fi

rm -rf "$DIR"
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

# One field is a style table and the other a plain string, because the custom
# theme section accepts either and both have to resolve. Add a `[flavor]` here
# if you want to see the columns against a real flavour.
cat >"$DIR/config/theme.toml" <<'EOF'
[supaline]
size  = { fg = "#ff8800" }
mtime = "green"
owner = "blue"
ext   = "magenta"
EOF

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

cat >"$DIR/config/init.lua" <<'EOF'
local supaline = require("supaline")

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

		-- m4: one name, three ways. Only the first should show "…".
		overflow = {
			{ "name", overflow = "ellipsis" },
			{ "name", overflow = "clip" },
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
	},
})
EOF
