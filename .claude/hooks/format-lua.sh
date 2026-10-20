#!/bin/sh
# Format the Lua file a Write or an Edit just touched, with the stylua
# `mise.toml` pins. `.claude/settings.json` runs this after either, and only
# when this file is there: a session can go on running the hook it started
# with after a switch to a branch that has no such file, and calling it
# regardless would fail every edit there, Lua or not.
#
# Every refusal exits 2, which hands stderr back to the agent: a missing tool,
# a stylua CI does not run, or a file stylua cannot parse is dealt with in the
# session that caused it rather than in a red check later. Swallowing the
# failure instead, as an `|| true` would, leaves the file unformatted and says
# nothing.
#
# A file is formatted only where `stylua --check .` in CI looks: inside a
# checkout of this repository, a linked worktree included, outside every hidden
# path and outside what a `.gitignore` matches, tracked or not. Measured on
# stylua 2.6.0, whose walk from `.` skips a hidden directory, and an ignored
# one inside a Git repository even when a file in it is tracked -- it reads the
# rules and never the index. Only `.gitignore` counts, because
# `.git/info/exclude` and `core.excludesFile` are one contributor's and CI's
# checkout has neither.
set -u

fail() {
	printf 'format-lua: %s\n' "$1" >&2
	exit 2
}

input=$(cat)
# Most edits are not Lua; let them through before asking for jq.
case "$input" in
*'.lua"'*) ;;
*) exit 0 ;;
esac
command -v jq >/dev/null 2>&1 || fail 'jq is not installed'
file=$(printf '%s' "$input" |
	jq -r '.tool_response.filePath? // .tool_input.file_path? // empty') ||
	fail 'jq could not read the hook input'
case "$file" in
*.lua) ;;
*) exit 0 ;;
esac
project=${CLAUDE_PROJECT_DIR:-}
[ -n "$project" ] && [ -f "$file" ] || exit 0
command -v git >/dev/null 2>&1 || fail 'git is not installed'

# A session working in a linked worktree can have CLAUDE_PROJECT_DIR at
# another checkout, so the checkout is found from the file, and taken when it
# shares the project's repository. Git resolves a symlinked path, such as
# macOS's /tmp, on both sides.
dir=$(dirname -- "$file")
# One line each, in the order asked for; at the top of the checkout the
# prefix is an empty line, which `$(...)` drops, and `read` leaves it empty.
found=$(git -C "$dir" rev-parse --path-format=absolute --show-toplevel \
	--git-common-dir --show-prefix 2>/dev/null) || exit 0
{
	IFS= read -r top
	IFS= read -r common
	IFS= read -r prefix
} <<EOF
$found
EOF
ours=$(git -C "$project" rev-parse --path-format=absolute --git-common-dir \
	2>/dev/null) || exit 0
[ "$common" = "$ours" ] || exit 0

rel=$prefix$(basename -- "$file")
case "/$rel" in
*/.*) exit 0 ;;
esac
# Tracked and untracked alike, against the `.gitignore` files alone: a path
# printed is one they match. Measured on Git 2.54, where neither
# `.git/info/exclude` nor `core.excludesFile` makes this print a path.
ignored=$(git -C "$top" ls-files --ignored --cached --others \
	--exclude-per-directory=.gitignore -- "$rel") ||
	fail "git ls-files could not say whether $file is ignored"
[ -z "$ignored" ] || exit 0

# Read from the file's own checkout, which may be on a branch pinning another
# version than the project's, and from `[tools]` alone, where a `stylua` key
# under any other table is not a pin. Spaces around `=` and a trailing comment
# are what a person writes; the anchor keeps a commented-out pin from being
# read.
# A checkout with no `mise.toml` predates the pin -- a worktree on an older
# main, say -- and has nothing to compare with, so it is left alone. One that
# has the file and no readable pin in it is refused.
pins=$top/mise.toml
[ -f "$pins" ] || exit 0
want=$(sed -n '/^\[tools\]/,/^\[/s/^stylua[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' \
	"$pins")
[ -n "$want" ] || fail "could not read the stylua version from $pins"

# mise's shims pick a version by the working directory, so stylua runs from
# the checkout whose `mise.toml` applies. A PATH that `mise activate` set does
# not follow the change of directory, which is what the comparison below is
# still for. `$(...)` takes stdout alone, so what mise says on stderr while it
# installs a missing version does not reach the comparison.
cd "$top" || fail "could not enter $top"
command -v stylua >/dev/null 2>&1 ||
	fail "stylua is not installed; mise.toml pins $want, which is what CI runs"
have=$(stylua --version) || fail 'stylua --version failed'
have=${have#stylua }
[ "$have" = "$want" ] ||
	fail "$file was not formatted: stylua $have is installed, but CI runs \
$want, which mise.toml pins. To format it, install $want, with \
\`mise install\` in $top if you use mise."

# `--respect-ignores` because a path named outright is formatted whatever a
# `.styluaignore` says, where `stylua --check .` skips what it lists. Measured
# on stylua 2.6.0.
out=$(stylua --config-path stylua.toml --respect-ignores -- "$rel" 2>&1) ||
	fail "stylua could not format $file:
$out"
