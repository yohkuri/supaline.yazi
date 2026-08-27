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
MARKER=".supaline-fixture"

if [ "${1:-}" = "--clean" ]; then
	if [ -e "$DIR" ] && [ ! -f "$DIR/$MARKER" ]; then
		echo "manual: $DIR is not ours; leaving it alone" >&2
		exit 2
	fi
	rm -rf "$DIR"
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

  m 6   panes = current                 the other two panes stay bare
  m 7   panes = current + parent        the left pane fills in
  m 8   panes = current + preview       the right pane fills in

  m 9   user-written columns            a registered one and an inline one

  m s   Yazi's own size linemode        m n turns the linemode off
  T     reload the theme                watch [supaline] colours arrive
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
────────────────────────────────────────────────────────────────────────────
EOF

printf 'Press Enter to open Yazi... '
# Tolerate a closed stdin, so the script can be sourced by something else.
read -r _ || true

YAZI_CONFIG_HOME="$DIR/config" XDG_STATE_HOME="$DIR/state" exec yazi "$DIR/fixture/data"
