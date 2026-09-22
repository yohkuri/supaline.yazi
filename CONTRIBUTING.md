# Contributing

Bug reports and pull requests are welcome. This page is the whole of what is
expected of one, and assumes you have read nothing else here.

`AGENTS.md` is the same route written for an AI agent, at length and with the
reasoning behind each part. You do not need it to contribute.

## What you need

Yazi **26.9.1**. Yazi enforces the `--- @since` annotation and refuses to load
an older one, and 26.9.1 is the version every measurement in this repository
was taken on. Yazi is on CalVer and breaks the plugin API between releases, so
a newer one may work and nothing here checks that it does — no CI job starts a
Yazi at all. Say which one you ran when you report what the screen did.

`mise.toml` pins the rest for whoever uses mise, and nothing here requires a
version manager:

| For | Version |
| --- | ------- |
| the unit suite | Lua 5.5, the one Yazi embeds |
| `skills.py` | uv 0.11.19 |
| the harnesses | Python 3.14 |
| formatting and types | stylua, lua-language-server |
| Markdown and commit messages | Node, through `npx` |
| `test/e2e.py`, `test/manual.py` | tmux, and a real terminal |

## Install the hooks

`.git/hooks` is not tracked, so each clone installs them itself. They refuse
two mistakes locally rather than in CI, which is quicker than hearing it from
a red check. These two lines work from a linked worktree as well as from the
clone:

```sh
common=$(git rev-parse --path-format=absolute --git-common-dir)
ln -sf "${common%/.git}/.githooks"/* "$common/hooks/"
```

## Run the checks

CI runs all of these on every pull request. Running them first costs less than
a round trip:

```sh
lua test/run.lua                  # unit tests, over the plugin
lua test/run.lua column           # ... just the specs matching "column"
stylua --check .                  # Lua formatting
lua-language-server --check .     # Lua types
npx --yes markdownlint-cli2@0.19  # Markdown
uv run .github/scripts/skills.py  # the instruction documents' budgets

python3 -m unittest discover -s test -p 'test_*.py'  # the screen parsers

uvx ruff@0.16.7 check test .github/scripts           # the Python lint
uvx ruff@0.16.7 format --check test .github/scripts  # ... and its shape
```

One of them goes quiet when it is under-equipped. `lua-language-server
--check .` compares the plugin against Yazi's own annotations, which
`.luarc.json` expects at `~/.config/yazi/plugins/types.yazi/` and
`ya pkg add yazi-rs/plugins:types` installs. Without that directory the check
still runs and still finds nothing, having stopped comparing the plugin
against anything but this repository.

`test/e2e.py` renders in a real Yazi under tmux and `test/manual.py` does the
same for a human to look at. Both need a real terminal and are deliberately
not in CI, so run them yourself before claiming anything about the screen —
and trust the exit status over the screen looking right, because a broken
fetcher shows up nowhere on it.

## Commit messages

[Conventional Commits], and three rules on top of it that CI enforces:

- The header — the whole first line — is **72 characters or fewer**. That
  limit is hard.
- Do not capitalise the first letter of the subject. Proper nouns carrying
  their own capitals, such as `GitHub` or `API`, are fine.
- No emoji in the header, and no Gitmoji shortcode anywhere in the message.

A subject of 50 characters or fewer is preferred; going over is a warning
rather than a refusal. Read yours back before pushing:

```sh
npx -p @commitlint/cli@21 -p @commitlint/config-conventional@21 \
  commitlint --from origin/main --to HEAD
```

Everything tracked here is written in English — code, comments, documentation,
user-facing error messages, and commit messages alike.

## Opening a pull request

`main` takes no direct pushes. Work reaches it through a pull request, and a
ruleset on the server refuses every other route.

A pull request lands by **rebase**, so `main` stays a line with no merge
commit on it. Bring your branch up to date with `git fetch origin` and then
`git rebase origin/main`, force-pushed. Merging `main` into your branch
instead takes that away, and a check will tell you so.

Because a rebase gives your commits new hashes, each one lands on `main` as
you wrote it — which is why the message rules above are checked rather than
tidied up afterwards.

Every check on the pull request has to pass. The maintainer merges.

## What a change may be about

A new built-in column is an ordinary change: the registry gives built-in and
user-written columns the same path, and neither is privileged.

Whether supaline ships status columns of its own — version control, dotfile
management — is **undecided**. A pull request adding one is a proposal rather
than a fix, so say that it is, and say what it asks of the column registry.

If your change touches `README.md`, read `AGENTS.md`'s `What this is` first.
It lists three things about this plugin that get described wrongly by default,
and where the reasoning for each of them lives.

## License

By contributing, you agree that your contributions are licensed under the MIT
License, as `LICENSE` states.

[Conventional Commits]: https://www.conventionalcommits.org/
