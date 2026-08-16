#!/usr/bin/env bash
#
# Launch a real, interactive Yazi with supaline loaded, for looking at it
# yourself.
#
#   test/manual.sh              # against a generated fixture directory
#   test/manual.sh ~/src        # against any directory
#   test/manual.sh --clean      # remove the throwaway config and fixture
#
# Your own ~/.config/yazi is never read or written. Everything lives under a
# scratch directory that is reused between runs, so state such as the linemode
# you last chose survives.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="${SUPALINE_WORK:-${TMPDIR:-/tmp}/supaline-manual}"
CONFIG="$WORK/config"
FIXTURE="$WORK/fixture"
MARKER="$WORK/.supaline-manual"

case "$WORK" in
/ | /* ) ;;
*)
	echo "manual: SUPALINE_WORK must be an absolute path, got '$WORK'" >&2
	exit 1
	;;
esac
if [ "$WORK" = "/" ] || [ "$WORK" = "$HOME" ] || [ "$WORK" = "$ROOT" ]; then
	echo "manual: refusing to use '$WORK' as the scratch directory" >&2
	exit 1
fi

# --clean removes the whole scratch directory, so it only ever touches one this
# script created and marked.
if [ "${1:-}" = "--clean" ]; then
	if [ ! -e "$WORK" ]; then
		echo "nothing to remove at $WORK"
	elif [ ! -f "$MARKER" ]; then
		echo "manual: refusing to remove $WORK: no .supaline-manual marker" >&2
		exit 1
	else
		rm -rf "$WORK"
		echo "removed $WORK"
	fi
	exit 0
fi

command -v yazi >/dev/null || {
	echo "manual: yazi is not on PATH" >&2
	exit 1
}

TARGET="${1:-}"
mkdir -p "$WORK"
: >"$MARKER"

if [ -n "$TARGET" ]; then
	"$ROOT/test/setup.sh" "$CONFIG"
else
	TARGET="$FIXTURE"
	# Rebuild the fixture only when it is missing; otherwise your own poking
	# around in it survives between runs.
	if [ -d "$FIXTURE" ]; then
		"$ROOT/test/setup.sh" "$CONFIG"
	else
		"$ROOT/test/setup.sh" "$CONFIG" "$FIXTURE"
	fi
fi

cat <<EOF

  supaline manual test
  ────────────────────────────────────────────────────────────────────
  config    $CONFIG
  browsing  $TARGET

  Press \`m\` to see every linemode. The ones worth comparing:

    m 1   supaline        chezmoi + git + size + mtime
    m 2   size, log scale        ┐ the same column, two normalisations:
    m 3   size, linear scale     ┘ linear should look nearly flat
    m 4   size, gradient off       what it looks like with no colour
    m 5   mtime + btime + atime
    m 6   permissions + owner + size + btime

    m t   reload the theme (rebuilds the gradient ramps)
    m s   Yazi's own size linemode, for comparison
    m n   none

  The full checklist is in test/README.md.

  Worth checking in the fixture:

    · the CJK and long filenames keep the columns aligned
    · sizes run 0B → 90M, timestamps run today → 2023
    · \`build/\` and \`debug.log\` are ignored; \`src/\` and \`docs/\` inherit
      the worst Git state below them (a deleted file is not in the listing,
      so \`docs/\` is the only place its state can show)
    · inside \`src/\`: untracked, added and modified, one of each

  For chezmoi, browse a managed tree instead:
    test/manual.sh ~
    test/manual.sh ~/.local/share/chezmoi

  Quit with \`q\`. Remove all of this with: test/manual.sh --clean
  ────────────────────────────────────────────────────────────────────

EOF

exec env YAZI_CONFIG_HOME="$CONFIG" yazi "$TARGET"
