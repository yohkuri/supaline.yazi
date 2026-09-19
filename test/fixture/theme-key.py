"""Put one of the fixture's themes where Yazi reads it, and reload.

Called from the `c 1` to `c 3` keys, with the theme's name as its argument.

Copied into the scratch directory by `setup.py`, which prepends the shebang --
this harness's own interpreter rather than an `env python3` that would resolve
against whatever PATH Yazi's `shell` template hands it. A file under
`test/fixture/` rather than a string built in `setup.py` for the reason the
TOML beside it is one: it is the file Yazi runs, so ruff reads it.

The reload is emitted from in here, and that is not a preference. A keymap
`run` of [ "shell ... --confirm", "app:theme" ] does not wait: measured on
26.9.1, the copy lands on disk and `app:theme` has already re-read the file
before it, so the screen keeps the theme it had while `theme.toml` says
otherwise -- which looks exactly like a plugin that ignored the reload.
`--block` does not fix it either. Emitting after the copy does, because then
the ordering is this script's.
"""

import shutil
import subprocess
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
shutil.copyfile(
    here / "themes" / f"{sys.argv[1]}.toml", here / "config" / "theme.toml"
)
subprocess.run(["ya", "emit", "app:theme"], check=True)
