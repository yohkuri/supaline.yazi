# What was measured about the route

Three claims in `SKILL.md` are measurements rather than facts, and each is
here with the date, the method and where it stops. A different GitHub, a
different commitlint or a different Claude Code is a reason to run them again
rather than to trust the sentence.

## Contents

- Branch protection is not available while the repository is private
- commitlint reads a merge commit and says nothing
- An `ask` rule stops a call an `allow` rule covers

## Branch protection is not available while the repository is private

Measured 2026-09-08, against this repository, through `gh api`. Both the
branch-protection endpoint and the ruleset endpoint that replaced it answered:

```text
Upgrade to GitHub Pro or make this repository public
```

So there is no server-side refusal to be had here at any price short of
opening the repository, and the three checks in `SKILL.md` are the whole of
what stands between a mistake and `main`. Two of them live in a clone's
untracked `.git/hooks`, which is the part worth remembering: the protection
is opt-in per clone until the day this is turned on.

Where it stops: the answer was read for this repository only. Whether a
private repository in an organisation with a paid plan answers differently
was never tested, and the message implies it would.

## commitlint reads a merge commit and says nothing

Measured on @commitlint/cli 21 with @commitlint/config-conventional 21, the
pair `.commitlintrc.yml` and CI both pin.

`Merge branch 'main' into a-branch` was accepted without a word. A plain
`Bad subject here` put through the same invocation was refused with two
problems. So the silence is commitlint's own reading of a merge commit and
not a range that missed it.

`Commit messages` walks `git rev-list --no-merges` on top of that, so a merge
commit is skipped twice over. That is why the rule is that merge commits do
not exist here rather than that their messages have to be good: a message
nothing reads cannot be held to a standard.

## An `ask` rule stops a call an `allow` rule covers

Measured here on 2026-09-13, on Claude Code, with a `claude -p` session.

The session was given `Bash(gh pr merge *)` on the command line as an allow
rule, and was refused anyway by the `ask` entry in `.claude/settings.json`.
The control ran in the same shape: a `gh` subcommand the `ask` entry does not
name was allowed on the command line the same way, and ran. So the refusal is
the precedence — deny, then ask, then allow — and not a session that had
been refused everything.

Where it stops: that an `ask` rule also prompts inside a `&&` chain, and under
a permission mode that otherwise stops prompting, is read from Claude Code's
permissions documentation and was **not** measured here.

What was not tested at all, because it does not need testing, is the way
past it: a Bash permission rule matches the text of the command, so the same
call spelled through a script or an absolute path is a different text.
