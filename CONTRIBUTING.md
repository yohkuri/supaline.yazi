# Contributing

Thanks for looking! Bug reports and pull requests are both very welcome.

This page is everything you need — you don't have to read anything else
first. (`AGENTS.md` covers the same ground for AI agents, in far more
detail. You can skip it.)

## What you need

**Yazi 26.9.1.** Older versions refuse to load the plugin, and newer ones
are untested — no CI job ever starts a real Yazi. So if you report
something you saw on screen, please mention which version you ran.

Everything else is pinned in `mise.toml`, but you don't need mise:

| For | What |
| --- | ---- |
| unit tests | Lua 5.5, the one Yazi embeds |
| `skills.py` | uv 0.11.19 |
| the test harnesses | Python 3.14 |
| formatting and types | stylua, lua-language-server |
| Markdown and commit messages | Node, via `npx` |
| `test/e2e.py`, `test/manual.py` | tmux and a real terminal |

## Get the code

Fork the repository on GitHub, then clone your fork and point it back at
the original:

```sh
git clone https://github.com/<your-username>/supaline.yazi.git
cd supaline.yazi
git remote add upstream https://github.com/yohkuri/supaline.yazi.git
```

You'll push to `origin` (your fork) and pull from `upstream` to stay in
step with `main`.

## Install the git hooks

Once per clone. They catch two mistakes on your machine instead of making
you wait for a red check:

```sh
common=$(git rev-parse --path-format=absolute --git-common-dir)
ln -sf "${common%/.git}/.githooks"/* "$common/hooks/"
```

They look at which remote you're pushing to first, so your own fork's
`main` is left alone.

## Run the checks

CI runs all of these on your pull request, but catching things here is
faster:

```sh
lua test/run.lua                  # unit tests
lua test/run.lua column           # ... only specs matching "column"
stylua --check .                  # Lua formatting
lua-language-server --check .     # Lua types
npx --yes markdownlint-cli2@0.19  # Markdown
uv run .github/scripts/skills.py  # the instruction docs' length budgets

python3 -m unittest discover -s test -p 'test_*.py'  # the screen parsers

uvx ruff@0.16.7 check test .github/scripts           # Python lint
uvx ruff@0.16.7 format --check test .github/scripts  # Python formatting
```

Two things worth knowing:

- `lua-language-server --check .` passes quietly even when it can't find
  Yazi's own type annotations, which makes it look like it checked more
  than it did. Install them with `ya pkg add yazi-rs/plugins:types`.
- `test/e2e.py` and `test/manual.py` open a real Yazi, so they're not in
  CI. Run them yourself if your change affects what's on screen — and
  trust the exit status over how the screen looks, because a broken
  fetcher still looks fine.

## Commit messages

[Conventional Commits], plus three rules CI checks:

- First line: **72 characters or fewer.** This one is a hard limit.
- Don't capitalise the first word of the subject. Names that carry their
  own capitals, like `GitHub` or `API`, are fine.
- No emoji in the first line, and no `:sparkles:`-style codes anywhere.

Aim for 50 characters in the subject if it fits; going over is only a
warning. You can read yours back before pushing:

```sh
npx -p @commitlint/cli@21 -p @commitlint/config-conventional@21 \
  commitlint --from origin/main --to HEAD
```

Everything here is written in English, commit messages included.

## Open a pull request

For anything bigger than a small fix, please open an issue first so we can
agree on the shape of it. Finding out that a finished change needs redoing
is no fun for anyone. For a typo or an obvious bug, just send the pull
request.

Nobody pushes to `main` — not even the maintainer. The server refuses it.
Everything goes through a pull request:

1. Branch off `main`, commit, and push to your fork.
2. Open the pull request. The template asks you two short questions.
3. To catch up with `main`, use `git fetch upstream` then
   `git rebase upstream/main`, and force-push. Please don't merge `main`
   into your branch — a check will turn red if you do.
4. Once the checks are green, the maintainer merges it.

Your commits land on `main` exactly as you wrote them, which is why the
message rules above are checked rather than tidied up afterwards.

## What to work on

**New built-in columns are welcome.** They go through the same interface
as user-written ones, with no special treatment.

**Status columns — git, dotfile management and so on — aren't decided
yet.** A pull request adding one is a proposal rather than a fix, so it
helps if you say so, and say what it needs from the column registry.

If you're editing `README.md`, skim `AGENTS.md`'s "What this is" section
first. It lists three things about this plugin that are easy to describe
wrongly.

## Using AI

A lot of this repository was written with an AI agent, and the commits say
so — look for the `Co-Authored-By` trailer. It seems only fair to mention
that before saying anything about your tools.

So use whatever helps. The one thing we ask is that you have read what you
send, run it, and can talk it through. A change nobody can explain is hard
to review, whoever or whatever wrote it.

## License

By contributing, you agree your work is licensed under the MIT License,
as `LICENSE` says.

[Conventional Commits]: https://www.conventionalcommits.org/
