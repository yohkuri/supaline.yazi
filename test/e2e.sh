#!/bin/sh
# Render supaline in a real Yazi and check what comes back.
#
# The unit tests stub the Yazi globals, so they can say nothing about
# rendering. This can, and it is the only thing that can: both layout bugs
# found so far were invisible to the unit tests until this script drew them.
#
#     test/e2e.sh            run it
#     test/e2e.sh --keep     leave the scratch config and fixture behind
#
# Needs tmux. Yazi queries the terminal at startup and aborts if nothing
# answers, so a `script`-style pseudo-terminal will not do; tmux is a real
# terminal emulator. A detached tmux has no client to answer the probe either,
# which is why `app:theme` is sent by hand before anything is captured --
# without it the user's theme is never applied and every `th.*` read returns
# preset values.
#
# Neither your own Yazi configuration nor anything outside the scratch
# directory is touched.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRATCH="${TMPDIR:-/tmp}/supaline-e2e"
MARKER=".supaline-e2e"
SESSION="supaline-e2e"
KEEP=""
[ "${1:-}" = "--keep" ] && KEEP=1

for tool in tmux yazi; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "e2e: $tool is not on PATH" >&2
		exit 2
	}
done

# The script rewrites this directory wholesale, so refuse any that it did not
# create itself. A mistyped path would otherwise take a real directory with it.
if [ -e "$SCRATCH" ] && [ ! -f "$SCRATCH/$MARKER" ]; then
	echo "e2e: $SCRATCH exists and is not ours; move it aside" >&2
	exit 2
fi

rm -rf "$SCRATCH"
mkdir -p "$SCRATCH/config/plugins" "$SCRATCH/state" "$SCRATCH/fixture/sub/deep"
: >"$SCRATCH/$MARKER"
ln -sfn "$ROOT" "$SCRATCH/config/plugins/supaline.yazi"

# --- the fixture -----------------------------------------------------------
# Spans four orders of magnitude and three years, and carries a CJK name and an
# over-long one, because that is where the width arithmetic goes wrong.
cd "$SCRATCH/fixture"
: >empty.txt
dd if=/dev/zero of=small.bin bs=1 count=900 2>/dev/null
dd if=/dev/zero of=medium.bin bs=1k count=800 2>/dev/null
dd if=/dev/zero of=large.bin bs=1k count=9000 2>/dev/null
printf 'x' >"日本語のファイル名.txt"
printf 'x' >"a-very-long-file-name-that-yazi-itself-has-to-truncate.txt"
touch -t 202301021504 large.bin
touch -t 202405060708 medium.bin
printf 'x' >sub/inner-a.txt
dd if=/dev/zero of=sub/inner-b.bin bs=1k count=300 2>/dev/null
touch -t 202312250000 sub/inner-a.txt
printf 'x' >sub/deep/deepest.txt
cd "$ROOT"

# --- the configuration -----------------------------------------------------
cat >"$SCRATCH/config/yazi.toml" <<'EOF'
[mgr]
linemode = "current_only"
show_hidden = true
EOF

# One field is a style table and the other a plain string, because the theme
# section accepts either and both have to resolve.
cat >"$SCRATCH/config/theme.toml" <<'EOF'
[supaline]
size  = { fg = "#ff8800" }
mtime = "green"
EOF

cat >"$SCRATCH/config/keymap.toml" <<'EOF'
[[mgr.prepend_keymap]]
on  = "T"
run = "app:theme"

[[mgr.prepend_keymap]]
on  = [ "m", "1" ]
run = "linemode current_only"

[[mgr.prepend_keymap]]
on  = [ "m", "2" ]
run = "linemode every_pane"

[[mgr.prepend_keymap]]
on  = [ "m", "3" ]
run = "linemode measured"
EOF

cat >"$SCRATCH/config/init.lua" <<'EOF'
local supaline = require("supaline")

-- A user column, registered through the same entry point the built-ins use.
supaline.column("ext", {
	width = 5,
	align = "left",
	base = "magenta",
	render = function(file, ctx) return file.url.ext or "", ctx.base end,
})

supaline:setup({
	linemodes = {
		current_only = { "size", "mtime" },
		every_pane = {
			"permissions",
			"owner",
			"size",
			"mtime",
			panes = { "current", "parent", "preview" },
		},
		measured = {
			{ "ext" },
			{ "size", width = "auto", sep = false },
			{ "owner", width = "auto", max_width = 8 },
		},
	},
})
EOF

# --- run -------------------------------------------------------------------
tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" -x 170 -y 40 \
	"env YAZI_CONFIG_HOME=$SCRATCH/config XDG_STATE_HOME=$SCRATCH/state YAZI_LOG=debug yazi '$SCRATCH/fixture/sub'"
sleep 4

# Apply the user's theme. Everything before this point is drawn with preset
# colours, so a capture taken now would prove nothing about `th.supaline`.
tmux capture-pane -t "$SESSION" -p -e >"$SCRATCH/before-theme.txt"
tmux send-keys -t "$SESSION" T
sleep 2

shot() {
	tmux capture-pane -t "$SESSION" -p >"$SCRATCH/screen-$1.txt"
	tmux capture-pane -t "$SESSION" -p -e >"$SCRATCH/color-$1.txt"
}

shot current_only
tmux send-keys -t "$SESSION" m 2
sleep 1
# Switching linemode does not re-peek the preview; move the hover to force one.
tmux send-keys -t "$SESSION" j
sleep 1
tmux send-keys -t "$SESSION" k
sleep 2
shot every_pane

tmux send-keys -t "$SESSION" m 3
sleep 2
shot measured

tmux send-keys -t "$SESSION" q
sleep 1
tmux kill-session -t "$SESSION" 2>/dev/null || true

# --- check -----------------------------------------------------------------
LOG="$SCRATCH/state/yazi/yazi.log"
fails=0

fail() {
	echo "  FAIL $1" >&2
	fails=$((fails + 1))
}

echo "== log =="
if [ -f "$LOG" ] && grep -qiE "ERROR|WARN|attempt to|error converting" "$LOG"; then
	grep -iE "ERROR|WARN|attempt to|error converting" "$LOG" | head -10 >&2
	fail "Yazi logged an error"
else
	echo "  clean"
fi

echo "== rendering =="
# The current pane is the middle column; the parent pane is the left one.
if grep -q "300K" "$SCRATCH/screen-current_only.txt"; then
	echo "  columns drawn in the current pane"
else
	fail "no size column in the current pane"
fi

if grep -q "drwxr-xr-x" "$SCRATCH/screen-every_pane.txt"; then
	echo "  permissions drawn"
else
	fail "no permissions column"
fi

# `every_pane` lists all three, so the parent pane's own rows carry columns;
# `current_only` does not, so the same rows are bare.
parent_row_wide=$(sed -n '4p' "$SCRATCH/screen-every_pane.txt" | cut -c1-20)
parent_row_solo=$(sed -n '4p' "$SCRATCH/screen-current_only.txt" | cut -c1-20)
if echo "$parent_row_wide" | grep -qE "[0-9]"; then
	echo "  parent pane drawn under { current, parent, preview }"
else
	fail "parent pane bare under { current, parent, preview }"
fi
if echo "$parent_row_solo" | grep -qE "[0-9]{2}/[0-9]{2}"; then
	fail "parent pane drawn under the default { current }"
else
	echo "  parent pane left alone by the default"
fi

echo "== theme =="
# `[supaline] size` is #ff8800, which is 255;136;0 once tmux writes it out.
before=$(grep -c '255;136;0' "$SCRATCH/before-theme.txt" || true)
after=$(grep -c '255;136;0' "$SCRATCH/color-current_only.txt" || true)
if [ "$before" -eq 0 ] && [ "$after" -gt 0 ]; then
	echo "  base colour applied on app:theme (before=$before after=$after)"
else
	fail "theme colour did not arrive with app:theme (before=$before after=$after)"
fi

echo
sed -n '2,8p' "$SCRATCH/screen-every_pane.txt"
echo

if [ -z "$KEEP" ]; then
	rm -rf "$SCRATCH"
else
	echo "kept: $SCRATCH"
fi

if [ "$fails" -gt 0 ]; then
	echo "e2e: $fails check(s) failed" >&2
	exit 1
fi
echo "e2e: ok"
