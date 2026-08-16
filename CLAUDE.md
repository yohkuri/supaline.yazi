# CLAUDE.md

Working notes for this repository. [README.md](README.md) is the user-facing
documentation — don't duplicate it here. This file records the things that are
not obvious from reading the code, especially the Yazi platform constraints that
the structure exists to satisfy.

## What this is

A Yazi plugin that replaces the linemode with a configurable set of columns:
sizes and timestamps coloured on an eza-style gradient, plus Git and chezmoi
status. Built-in columns and user-written ones go through the same interface.

Targets **Yazi 26.8.15+** (`--- @since` at the top of each file, which Yazi
enforces: an older Yazi refuses to load the plugin outright). Yazi is on CalVer
and breaks the plugin API freely between releases — 26.8.15 changed the fetcher
calling convention and renamed a DDS event, so anything written for 26.5.6, let
alone 0.4.x, will not run.

## Layout

```
main.lua       setup, linemode registration, per-folder stats cache, ya.sync proxies, fetcher dispatch
column.lua     column registry, spec normalisation, padding, the ctx object
gradient.lua   sRGB <-> Oklab, the eza lightness curve, ramp construction
builtin.lua    size / mtime / btime / atime / permissions / owner / count
git.lua        Git status: parsing, repo discovery, bubble-up; column + fetcher
chezmoi.lua    chezmoi status across both the source and destination trees
scripts/       fmt-md.py — formats ```lua blocks in Markdown
test/          run.lua + *_spec.lua (unit), e2e.sh (real Yazi via tmux)
```

## Yazi constraints this design exists to satisfy

These were each found by instrumenting a running Yazi. None are in the official
docs. Changing the structure without accounting for them will break things
silently — no error, just an empty column.

**A plugin's sync state is scoped to the *file* the `ya.sync` call is written
in.** Not per plugin, not per entry point. A `ya.sync` closure written in
`git.lua` writes to a different state table than the one `setup` (running in
`main.lua`) populates, so the render closure never sees the fetched data. This
holds whether the fetcher is declared as a separate entry (`supaline.git`) or
dispatched through `main.lua`.

So: **every `ya.sync` call lives in `main.lua`.** Providers export plain
reducers (`git.reduce_add`, `chezmoi.reduce_commit`, …) that `main.lua` wraps
and passes back into `fetch`. If you add a provider, follow that shape.

**`ya.sync` calls are matched between the async and sync sides by position.**
Yazi re-executes the file in the sync VM and pairs the calls up in order. So the
wrapping in `main.lua` is unconditional and in a fixed order — never inside an
`if`, never in a `pairs` loop, whose order is unspecified.

**Fetcher providers are selected by argument, not by entry.** `run = "supaline
git"`, read from `job.args[1]`. `run = "supaline.git"` loads `git.lua` as its
own entry and loses the shared state.

`setup` declares those rules itself through `rt.plugin.fetchers:insert()`, so
the user writes no `[[plugin.prepend_fetchers]]`. It runs early enough that the
first directory is already covered. Yazi caps the list at 16 and matches only
the first rule per `group`, so a user who also declares them by hand gets no
double fetch — only wasted slots. `test/setup.sh` deliberately writes no
fetcher blocks, which is what proves the registration works.

**`fetch` returns a function, not a boolean.** Since 26.8.15 Yazi calls what
`fetch` returns, repeatedly, and expects `file, { retry = …, error = … }` each
time — nil ends it. Returning the old boolean fails with "error converting Lua
boolean to function", and the failure is invisible: the side effects already ran
so the column still fills in, and the error is written only to the *task* log,
not `yazi.log`. Look for a stuck "N left" in the status bar.

Every file in `job.files` must be reported exactly once. Omitting one gets it
retried and logs the fetcher as having quit early; reporting one twice is a hard
error. `retry = true` is the old `return false`: clear the loaded bit and run
again on the next visit, which is what keeps the Git column fresh.

**The theme is not loaded when `setup` runs.** 26.8.15 starts on the preset
theme and merges `theme.toml` and the flavor only after the asynchronous
terminal probe answers, then fires the new `theme` DDS event. So anything that
reads `th.*` must also re-read it on that event — `git.lua`, `chezmoi.lua` and
`build()` in `main.lua` each do. This is also why `test/e2e.sh` sends `app:theme`
before capturing: a detached tmux has no client to answer the probe.

**DDS event names are not all in the changelog.** 26.8.15 renamed `bulk` to
`bulk-rename` silently. `ps.sub` accepts any string, so a stale name is a
subscription that simply never fires. The kinds actually published live in
`pub_after!` in `yazi-dds/src/pubsub.rs`; read them there rather than trusting
the changelog.

**Every module must return a table.** Yazi wraps each module in a state table;
`return true` from a side-effect-only file fails with "error converting Lua
boolean to table". `builtin.lua` returns `{}` for this reason.

**Linemode dispatch.** `Linemode:solo()` reads `cx.active.pref.linemode` and
calls `self[mode](self)`, so registering is just `Linemode[name] = fn`. `solo`
already guards `in_current`, which is why the render path can assume
`cx.active.current` is the right folder, and prepends a space — but only to a
line that `:visible()` says has width, so returning `""` costs nothing. An
unknown mode name renders as literal text (`" " .. mode`), so a name registered
late shows up on screen.

## Rendering rules

`render(file, ctx)` runs for every visible row on every frame. It must be O(1)
and allocate as little as possible:

- Gradient ramps are built once at setup and quantised into `steps` buckets, so
  no colour maths and no `ui.Style` allocation happens per row.
- Anything needing the whole folder goes in `stats(files)`, computed once per
  folder in `main.lua` and cached.
- `render` may return `text, style` instead of an `AsLine`, which skips building
  an intermediate Line. The built-ins use this.

The stats cache key is `linemode name + cwd + file count`. The file count
catches adds and removes; DDS `rename`/`bulk`/`move`/`delete`/`trash` drop it
too. An in-place write that leaves the count unchanged keeps stale extremes
until you leave the directory — a deliberate trade, documented in the README.

`ui.Style` is immutable as of 26.5.6, so `style:fg(c)` returns a new style.

## Gradients

Modelled on eza's `--color-scale-mode=gradient`: normalise a value against the
extremes of the current listing, then drive only the Oklab **lightness** of the
base colour, leaving hue and chroma to the theme.

```
L = min_l + (1 - min_l) * exp(-4 * (1 - ratio))
```

Two knowing deviations from eza, both documented in the README:

- eza feeds gamma-encoded bytes into a linear-sRGB constructor; we do a
  gamma-correct round trip. Same ramp shape, truer hue.
- eza only normalises linearly. `scale = "log"` is available because a listing
  spanning 1 KiB–1 GiB puts a 1 MiB file at ratio 0.001 under linear
  normalisation. `linear` stays the default for fidelity.

## chezmoi

chezmoi's source tree encodes attributes in filenames (`dot_`, `private_`,
`run_once_`, `.tmpl`, …). Do **not** reimplement that decoding — it will rot.
Ask chezmoi instead:

```
chezmoi status  --path-style absolute         changes, by target path
chezmoi managed --path-style absolute         managed set, target side
chezmoi managed --path-style source-relative  managed set, source side
chezmoi source-path <targets...>              changes, by source path (batched)
```

`--path-style all` returns a JSON map of both, but there is no JSON parser in
the plugin sandbox, and the plain `absolute` and `source-relative` listings sort
differently so they cannot be zipped. Hence the four calls above. Each runs in
~40ms and the result is cached behind a claim/commit pair with a 3s floor.

## Formatting

**You do not need to run a formatter.** The `PostToolUse` hook in
`.claude/settings.json` runs `scripts/format-file.sh` on every file written or
edited, which formats `.lua` with stylua and the ```lua blocks of `.md` with
`scripts/fmt-md.py`. CI checks both, so the hook is fast feedback rather than
the gate. What follows is why the rules are what they are — worth knowing before
you "fix" a config that looks wrong.

`stylua.toml` and `.luarc.json` are copied verbatim from
[yazi-rs/plugins](https://github.com/yazi-rs/plugins). Keep them that way.

`indent_width = 2` does **not** mean two spaces. `indent_type` defaults to
`Tabs`, so the `.lua` files are tab-indented (as upstream Yazi's are);
`indent_width` is the assumed display width of a tab when measuring against
`column_width` (120).

Markdown code blocks are the exception: `scripts/fmt-md.py` forces
`--indent-type Spaces`, because a tab in a fenced block renders at the viewer's
tab width — 8 by default on GitHub and per the CSS initial value — which makes a
four-level example look absurd. Keep docs on spaces, `.lua` on tabs.

If a Markdown block fails to format, it is almost always because the snippet is
not valid Lua. `... ` inside a non-vararg function is the usual culprit. Fix the
snippet rather than excluding it; every example in the docs should be real code.

## Commands

```sh
lua test/run.lua                    # unit tests (pure logic, stubbed globals)
test/e2e.sh                         # render in a real Yazi, headless
test/e2e.sh ~/.local/share/chezmoi  # …against a specific directory
test/e2e.sh ~/src color             # …keeping ANSI escapes, to check gradients
test/e2e.sh ~/src plain lua         # …searching for "lua" rather than "txt"
test/manual.sh                      # the same, but interactive, for a human
test/manual.sh --clean              # discard its scratch config and fixture

# Formatting is automatic (see above); these are for CI parity and repair.
stylua --check .
scripts/fmt-md.py --check README.md CLAUDE.md
scripts/format-file.sh <path>       # what the hook runs, on one file
```

Requires `stylua` on PATH (`brew install stylua`). Without it the hook warns
once per edit and formats nothing, and CI is left as the only gate.

`test/setup.sh` writes the configuration and builds the fixture; `e2e.sh` and
`manual.sh` both call it, so the headless and interactive runs cannot drift
apart. Neither touches your own configuration — the plugin is symlinked into a
throwaway `YAZI_CONFIG_HOME`, and `XDG_STATE_HOME` is redirected too so the log
`e2e.sh` greps holds only this run.

Both scripts rewrite whole directories, so they refuse any directory that
exists without the marker file they leave behind (`.supaline-test-config`,
`.supaline-fixture`, `.supaline-manual`). Keep that guard if you touch them: a
mistyped argument would otherwise overwrite a real Yazi configuration.

The configuration defines six linemodes bound under Yazi's own `m` linemode
leader (`m 1` … `m 6`), so log-vs-linear and gradient-vs-flat are one keystroke
apart. The fixture spans 0B–90M and 2023–today, carries every Git state, and
includes CJK and over-long filenames to stress the width maths.

`e2e.sh` needs `tmux`: Yazi queries the terminal on startup and aborts if
nothing answers, so `script`-style pseudo-terminals do not work, whereas tmux is
a real terminal emulator.

CI runs stylua, the Markdown check and the unit tests. **`e2e.sh` is not in CI**
— it needs a real Yazi binary — so run it locally before claiming that anything
about rendering, fetchers or state works.

## Verification expectations

The unit tests cover pure logic only: colour maths, normalisation, padding, the
ratio contract, the built-in formatters. They stub the Yazi globals, so they can
say nothing about rendering, fetchers or `ya.sync`. Every bug found in this
project so far lived in exactly that untested gap. Run `test/e2e.sh` and read
the output before reporting that something works.

`e2e.sh` exits non-zero on a Lua error in the log *and* on a task that never
succeeded — the latter because a broken fetcher shows up nowhere else, and the
26.8.15 change slipped past an earlier version of this script that only looked
at the log and the screen. A green exit is worth more than the screen looking
right; the screen looked right while all four fetchers were failing.

Local `lua` may be 5.1, CI uses 5.4, Yazi runs 5.5. Keep the test code within
the common subset.

## Known gaps

- `types.yazi` does not describe everything the runtime provides, so LuaLS
  flags correct code. Undefined globals: `Err`, `Linemode`, `Entity`. Undefined
  fields: `Url.spec`, `ya.co`, `ya.dict_merge`, and every custom theme section
  (`th.git`, `th.chezmoi`, `th.supaline`). None of these are declared at
  upstream HEAD either, so upgrading the package does not help and other plugin
  authors see the same. Adding the globals to `diagnostics.globals` in
  `.luarc.json` would silence half of it but would diverge from the upstream
  config, which we are keeping verbatim.
- Gradients are relative to the current directory only; there is no absolute
  mode.
- Cells wider than their `width` are not truncated.
- Fetchers skip virtual files (`sftp://`, `trash://`), so those rows carry no
  Git or chezmoi state. `search://` is not virtual and does work — see
  `local_url` in `git.lua`.
- Browsing the trash bin at all needs Full Disk Access on macOS; without it
  Yazi cannot list `~/.Trash` and `test/e2e.sh` cannot reach that path.
