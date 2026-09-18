#!/bin/sh
# Open the test fixture in a real, interactive Yazi, so you can look at the
# columns yourself.
#
#     test/manual.sh          build the fixture and open it
#     test/manual.sh --clean  throw the fixture away and stop
#
# The configuration and the fixture come from `test/setup.sh`, which `e2e.sh`
# also uses, so what you see here is what the headless run asserts on. Your own
# Yazi configuration is not read and not touched.

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DIR="${TMPDIR:-/tmp}/supaline-manual"

if [ "${1:-}" = "--clean" ]; then
	# `setup.sh` owns the marker file and the "is this ours" guard, so it owns
	# the removal too.
	"$ROOT/test/setup.sh" --clean "$DIR"
	echo "manual: removed $DIR"
	exit 0
fi

command -v yazi >/dev/null 2>&1 || {
	echo "manual: yazi is not on PATH" >&2
	exit 2
}

"$ROOT/test/setup.sh" "$DIR"

cat <<'EOF'
supaline manual test
────────────────────────────────────────────────────────────────────────────
  m 0   one column                      press against m s to compare
  m 1   size + mtime                    the everyday case
  m 2   every built-in column           widths and alignment at a glance

  m 3   fixed vs auto width             column 2 fits the folder, 3 caps at 8
  m 4   ellipsis / clip / grow          one name, three ways
  m 5   separators                      default, none, and "│"

  m 6   the current pane alone          the other two panes stay bare
  m 7   current + parent                the left pane fills in
  m 8   current + preview               the right pane fills in
  m e   a column set per pane           each pane draws columns of its own

  m 9   user-written columns            a registered one and an inline one

  m s   Yazi's own size linemode        m n turns the linemode off
──── colour ────────────────────────────────────────────────────────────────
  Two halves, because they move apart. `g` is where you are, which is the
  spread of values a ramp gets stretched over; `c` is how it is coloured. A
  `c` key holds your folder, your scroll and your hover still, so two of them
  pressed one after the other differ in exactly one thing.

  g 1   the layout fixture              g 2   a folder of other widths
  g 3   one file per ramp step          g 4   sizes doubling from 1B
  g 5   hi == lo, and no value at all

  c r   a ramp that climbs              in g 3 -- one step per row
  c b   a band with no ends written     in g 3 -- the same navy, derived
  c h   a ramp that turns in hue        in g 3 -- what e2e cannot check
  c g   a ramp over, and as, a ground   in g 3 -- beside one with none
  c a   a bold beside a ramp's colour   in g 3 -- the pair must agree
  c s   log beside linear               in g 4
  c e   a ramp with nothing to spread   in g 5
  c t   whatever [supaline] says        in g 1 -- the only themed one

  c 1   theme: the default              c 2   theme: every field moved
  c 3   theme: backgrounds              T     reload without changing it
──── broken on purpose ─────────────────────────────────────────────────────
  A third leader. `b` is what is broken, and each key draws one column
  that is wrong in one way between a size and an mtime that are not.
  Every report supaline can put on a screen is one of these, and `told`
  says each of them once a session -- so read the notification, which
  lands over the preview pane a moment late, before pressing the next.

  b r   a render that throws            in g 1
  b s   a stats that throws             in g 1 -- the line says nothing
  b w   a width that throws             in g 1 -- press b u straight after
  b u   a width that returns 0          in g 1 -- same cells, other words
  b g   a ramp with no extremes         in g 3 -- beside one that climbs
  b f   two refresh counters            in g 1 -- g 6 breaks the left one

  g 6   the folder that arms it -- walk in and b f's left column stops
────────────────────────────────────────────────────────────────────────────
  You start in `data/`, which carries the awkward cases: CJK and emoji names,
  one far too long, and sizes either side of the 1K boundary. `sibling-one`
  and `sibling-two` give the parent pane rows; hover `nested` to give the
  preview pane a folder.

  `never-opened` is the directory the size and count columns have no entry
  count for until you have been inside it.

  The preview pane keeps its last peek, so m 6 to m 8 only reach it once the
  hover has moved.

  Quit with q. `test/manual.sh --clean` throws the fixture away.
  What to look for: test/MANUAL.md
EOF

# The log's path has to be expanded, so it cannot sit in the quoted heredoc
# above -- and it is worth printing rather than describing, because the half of
# a report that never reaches the screen is the half a reader has to be told
# where to find.
cat <<EOF

  What a report says past its one sentence -- what the fault cost, and the
  traceback -- goes to the log rather than to the screen. This run keeps one:
  $DIR/state/yazi/yazi.log
────────────────────────────────────────────────────────────────────────────
EOF

# Every ramp whole, before Yazi takes the screen. A linemode can only show the
# steps some folder's values land on -- `colour/ramp` is built to land on all
# of them and even there you scroll -- so this is the only place all sixty-four
# sit side by side, and it is in the same terminal, on the same background, as
# the columns are about to be.
#
# `setup.sh` lists what it wrote, so nothing here has to know how a ramp is
# spelled. A list built by reading this repository's source instead would go
# stale in one of two directions, both quiet: showing a ramp the fixture no
# longer draws, or leaving out one it does.
ramps=$(cat "$DIR/ramps.txt")
if [ -z "$ramps" ]; then
	echo "  note: the fixture wrote no ramp, so there is none to print"
elif ! command -v lua >/dev/null 2>&1; then
	echo "  note: lua is not on PATH, so the ramps are not printed here"
	echo "        run test/ramp.lua yourself to see them"
elif ! (
	# A subshell, so the word splitting this needs is scoped to the one call:
	# newlines alone, since a ramp has spaces in it, and globbing off so nothing
	# in a colour string is taken for a pattern. `set --` would do it too, and
	# would overwrite the arguments this script reads at the top -- the
	# caller's, when it is sourced.
	set -f
	IFS='
'
	# shellcheck disable=SC2086 # splitting on the IFS above is the point
	exec lua "$ROOT/test/ramp.lua" $ramps
); then
	echo "  note: a ramp above could not be resolved -- the message says which"
fi

printf 'Press Enter to open Yazi... '
# Tolerate a closed stdin, so the script can be sourced by something else.
read -r _ || true

# `YAZI_LOG` because a report is two halves and only the shorter one is a
# notification -- and there is no log at all unless this is set before Yazi
# starts, so without it the reports point at a file that was never written.
# `debug` is the spelling `e2e.sh` uses, and measured on 26.9.1 it costs three
# lines over `error` across a short run. `XDG_STATE_HOME` is the throwaway
# directory, so `--clean` takes the log with it.
YAZI_CONFIG_HOME="$DIR/config" XDG_STATE_HOME="$DIR/state" YAZI_LOG=debug \
	exec yazi "$DIR/fixture/data"
