#!/usr/bin/env bash
#
# Format one file the way this repository wants it:
#
#   *.lua  -> stylua, tabs (see stylua.toml)
#   *.md   -> the ```lua blocks only, via fmt-md.py, spaces
#
# Driven by the PostToolUse hook in .claude/settings.json, and safe to run by
# hand. The repository root comes from this script's own location, so it does
# not care what the working directory is.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
file="${1:-}"

[ -n "$file" ] && [ -f "$file" ] || exit 0

# Only ever touch files inside this repository. The hook fires for every edit
# in the session, including ones in other checkouts entirely, and this repo's
# formatting rules have no business being applied to them.
abs="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
case "$abs" in
"$ROOT"/*) ;;
*) exit 0 ;;
esac

# Without stylua there is nothing to do; say so once rather than failing on
# every edit.
if ! command -v stylua >/dev/null 2>&1; then
	echo "format-file: stylua not found; skipping ${file##*/}" >&2
	exit 0
fi

case "$file" in
*.lua)
	stylua --config-path "$ROOT/stylua.toml" "$file"
	;;
*.md)
	python3 "$ROOT/scripts/fmt-md.py" "$file" >/dev/null
	;;
esac
