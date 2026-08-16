#!/usr/bin/env bash
#
# Build a throwaway Yazi configuration, and optionally a fixture directory, for
# testing supaline. Shared by e2e.sh (headless) and manual.sh (interactive) so
# the two cannot drift apart.
#
#   test/setup.sh <config-dir> [fixture-dir]
#
# Set SUPALINE_ASCII_SIGNS=1 for ASCII Git signs, which a text capture can read;
# the Nerd Font defaults are what a user actually sees.
#
# Your own configuration is never touched: the plugin is symlinked into the
# config directory given here, and nothing else is written outside it.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:?usage: setup.sh <config-dir> [fixture-dir]}"
FIXTURE="${2:-}"

# Both directories are rewritten wholesale, so refuse to touch anything this
# script did not create. A stray argument would otherwise overwrite a real
# Yazi configuration, or delete real data.
claim() {
	local dir="$1" marker="$1/$2" what="$3"
	if [ -e "$dir" ] && [ ! -f "$marker" ]; then
		echo "setup: refusing to use $dir as the $what directory:" >&2
		echo "       it exists and has no $2 marker, so it is not ours to rewrite." >&2
		exit 1
	fi
	mkdir -p "$dir"
	: >"$marker"
}

claim "$CONFIG" .supaline-test-config "configuration"

mkdir -p "$CONFIG/plugins"
rm -f "$CONFIG/plugins/supaline.yazi"
ln -s "$ROOT" "$CONFIG/plugins/supaline.yazi"

cat >"$CONFIG/yazi.toml" <<'EOF'
[mgr]
linemode    = "supaline"
show_hidden = true

[[plugin.prepend_fetchers]]
url   = "*"
run   = "supaline git"
group = "supaline-git"

[[plugin.prepend_fetchers]]
url   = "*/"
run   = "supaline git"
group = "supaline-git"

[[plugin.prepend_fetchers]]
url   = "*"
run   = "supaline chezmoi"
group = "supaline-chezmoi"

[[plugin.prepend_fetchers]]
url   = "*/"
run   = "supaline chezmoi"
group = "supaline-chezmoi"
EOF

# Several linemodes, so the interesting comparisons are a keystroke apart:
# log against linear, gradient against flat, ours against Yazi's own.
cat >"$CONFIG/init.lua" <<'EOF'
require("supaline"):setup {
	gradient = { colors = "truecolor" },
	linemodes = {
		supaline = {
			{ "chezmoi" },
			{ "git" },
			{ "size", scale = "log" },
			{ "mtime" },
		},
		["supaline-log"] = {
			{ "size", scale = "log" },
		},
		["supaline-linear"] = {
			{ "size", scale = "linear" },
		},
		["supaline-flat"] = {
			{ "size", scale = "log", gradient = "off" },
		},
		["supaline-times"] = {
			{ "mtime" },
			{ "btime" },
			{ "atime" },
		},
		["supaline-wide"] = {
			{ "permissions" },
			{ "owner" },
			{ "size", scale = "log" },
			{ "btime" },
		},
	},
}
EOF

# Yazi already uses `m` as the linemode leader (m s, m m, m p, ...), so the
# digits extend that rather than inventing a second convention. Press `m` to
# see them all in the which menu.
cat >"$CONFIG/keymap.toml" <<'EOF'
[[mgr.prepend_keymap]]
on   = [ "m", "1" ]
run  = "linemode supaline"
desc = "Linemode: supaline (chezmoi + git + size + mtime)"

[[mgr.prepend_keymap]]
on   = [ "m", "2" ]
run  = "linemode supaline-log"
desc = "Linemode: size, log scale"

[[mgr.prepend_keymap]]
on   = [ "m", "3" ]
run  = "linemode supaline-linear"
desc = "Linemode: size, linear scale (compare with 2)"

[[mgr.prepend_keymap]]
on   = [ "m", "4" ]
run  = "linemode supaline-flat"
desc = "Linemode: size, no gradient (compare with 2)"

[[mgr.prepend_keymap]]
on   = [ "m", "5" ]
run  = "linemode supaline-times"
desc = "Linemode: mtime + btime + atime"

[[mgr.prepend_keymap]]
on   = [ "m", "6" ]
run  = "linemode supaline-wide"
desc = "Linemode: permissions + owner + size + btime"

# Rebuilds the gradient ramps through supaline's `theme` subscription. Nothing
# else exercises that path.
[[mgr.prepend_keymap]]
on   = [ "m", "t" ]
run  = "app:theme"
desc = "Reload the theme (rebuilds supaline's ramps)"
EOF

if [ "${SUPALINE_ASCII_SIGNS:-0}" = "1" ]; then
	cat >"$CONFIG/theme.toml" <<'EOF'
[git]
modified_sign  = "M"
added_sign     = "A"
untracked_sign = "?"
deleted_sign   = "D"
ignored_sign   = "I"
updated_sign   = "U"
EOF
else
	rm -f "$CONFIG/theme.toml"
fi

[ -n "$FIXTURE" ] || exit 0

# ---------------------------------------------------------------------------
# Fixture: sizes spanning six orders of magnitude, timestamps spanning years,
# every Git state, and names that stress the width maths.

claim "$FIXTURE" .supaline-fixture "fixture"
rm -rf "$FIXTURE"
mkdir -p "$FIXTURE/src" "$FIXTURE/docs" "$FIXTURE/build" "$FIXTURE/empty"
cd "$FIXTURE"
: >.supaline-fixture
git init -q .
printf 'build/\n*.log\n' >.gitignore

: >empty.bin
head -c 300 /dev/urandom >tiny.bin
head -c 40000 /dev/urandom >small.bin
dd if=/dev/zero of=medium.bin bs=1m count=3 2>/dev/null
dd if=/dev/zero of=large.bin bs=1m count=90 2>/dev/null

echo tracked >src/tracked.txt
echo untracked >src/new.txt
echo staged >src/staged.txt
echo doomed >src/doomed.txt
echo doc >docs/readme.md
echo gone >docs/gone.md
echo noise >build/artifact.o
echo noise >debug.log

# Names that exercise the padding: CJK is double-width, and the long one
# should push the columns rather than be silently cut.
echo "日本語のファイル名" >"日本語ファイル.txt"
echo long >"a-deliberately-long-file-name-to-watch-the-columns-move.txt"
ln -sf tiny.bin link-to-tiny.bin

# Plain `--porcelain` C-quotes these, so their status would be lost against the
# real path. They must show as untracked like anything else.
printf 'x' >'back\slash.txt'
printf 'x' >'quote"name.txt'

git add .gitignore .supaline-fixture tiny.bin small.bin empty.bin \
	src/tracked.txt src/doomed.txt docs/readme.md docs/gone.md "日本語ファイル.txt"
git -c user.email=test@localhost -c user.name=test commit -qm "fixture"

echo changed >>src/tracked.txt # modified
git add src/staged.txt         # added, staged
rm src/doomed.txt              # deleted

# A deleted file is not in the listing, so `deleted` is only ever visible on
# the directory above it. docs/ has nothing else going on, so it shows it.
rm docs/gone.md

# Timestamps: today, this year, and several years back.
touch -t 202301150900 tiny.bin
touch -t 202411031530 small.bin
touch -t "$(date +%Y)06201200" medium.bin 2>/dev/null || true
