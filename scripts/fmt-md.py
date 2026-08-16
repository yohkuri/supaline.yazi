#!/usr/bin/env python3
"""Format the ```lua blocks of a Markdown file with stylua.

    scripts/fmt-md.py README.md            # rewrite in place
    scripts/fmt-md.py --check README.md    # fail if anything would change

Two deliberate differences from how the .lua files themselves are formatted:

  * Indentation is forced to spaces. The .lua files use tabs, matching upstream
    Yazi, but a tab inside a fenced code block renders at the viewer's tab
    width -- 8 by default on GitHub and per the CSS initial value -- which makes
    a four-level example look absurdly indented. `indent_width` from
    stylua.toml still applies, so the width is the intended one.

  * stylua only formats whole chunks, so a block that is a bare expression (a
    column spec shown on its own, say) is wrapped in an assignment, formatted,
    and unwrapped again. A block that parses as neither is reported and left
    alone -- usually it means the snippet is not valid Lua and should be fixed.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FENCE = re.compile(r"(^```lua\n)(.*?)(^```$)", re.MULTILINE | re.DOTALL)
WRAP = "local _ = "


def run_stylua(stylua, config, code):
    try:
        r = subprocess.run(
            [stylua, "--config-path", str(config), "--indent-type", "Spaces", "-"],
            input=code,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError:
        sys.exit(f"error: {stylua} not found; install StyLua or pass --stylua")
    return (r.stdout, None) if r.returncode == 0 else (None, r.stderr.strip())


def format_block(stylua, config, code, where, problems):
    out, err = run_stylua(stylua, config, code)
    if out is not None:
        return out

    # Retry as an expression rather than a statement.
    out, _ = run_stylua(stylua, config, WRAP + code)
    if out is None or not out.startswith(WRAP):
        problems.append(f"{where}: not valid Lua\n    {err}")
        return code
    return out[len(WRAP) :]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("paths", nargs="+", type=Path)
    ap.add_argument("--check", action="store_true", help="report instead of rewriting")
    ap.add_argument("--stylua", default="stylua", help="stylua binary (default: on PATH)")
    ap.add_argument("--config", type=Path, default=ROOT / "stylua.toml")
    args = ap.parse_args()

    problems, changed = [], []
    for path in args.paths:
        src = path.read_text()
        count = [0]

        def repl(m):
            count[0] += 1
            body = format_block(args.stylua, args.config, m.group(2), f"{path} block {count[0]}", problems)
            return m.group(1) + (body if body.endswith("\n") else body + "\n") + m.group(3)

        out = FENCE.sub(repl, src)
        if out == src:
            print(f"{path}: {count[0]} lua blocks, already formatted")
            continue

        changed.append(path)
        if args.check:
            print(f"{path}: {count[0]} lua blocks, NEEDS FORMATTING")
        else:
            path.write_text(out)
            print(f"{path}: {count[0]} lua blocks, reformatted")

    for p in problems:
        print(f"error: {p}", file=sys.stderr)

    if problems:
        return 2
    if args.check and changed:
        print("\nrun `scripts/fmt-md.py " + " ".join(str(p) for p in changed) + "` to fix", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
