---
name: landing-a-change
description: >-
  Why a change reaches `main` the way it does here, for when that route
  refuses something or does something surprising. Read when a commit, a push
  or a merge is refused, when a check about commits, merges or main comes
  back red, when GitHub will not rebase a branch, when a branch is stacked on
  one that is about to land, or when the question is who merges and what
  could refuse a merge at the server. **Not for the ordinary path**, which is
  in `AGENTS.md` and needs nothing from here: opening a pull request, writing
  a commit message, rebasing onto main, and stopping once the checks are
  reported. Covers why the message checks run on a pull request and nowhere
  else, what the three local checks refuse and the one thing none of them
  can and what a ruleset on main adds, why a branch lands by
  rebase and what that costs a branch stacked on it, where an agent's work
  ends, and what stands in for a merge gate in Claude Code's own settings.
  The measurements are in references/measurements.md.
---

# Landing a change

`AGENTS.md` says the route: a pull request, landed by rebase, merged by the
maintainer rather than by the agent that wrote it. Following it needs nothing
from this file. This is why each of those is the way it is, and what happens
when one of them is skipped — which is what you want when something has just
been refused, and not on the way past.

The reason for a check lives beside the check, so `.github/workflows/check.yml`
is the first place to read when one comes back red — every job there carries
its own comment saying what it asks and why. What is here is what no comment
beside a job can hold: the shape of the route itself, and the two places where
nothing checks anything at all.

## Why the message checks run on a pull request and nowhere else

`Commit messages` — commitlint, the ASCII header, the Gitmoji test — is
conditioned on `pull_request`. That is not an oversight to be fixed by running
it on `push` as well. A pull request is the last point at which a message can
still be rewritten; past the merge, fixing one means rewriting published
history, which is a worse outcome than the bad message.

So a commit that reaches main another way is not a commit that failed the
check. It is a commit **nothing read**, and no later run can undo that.

## What holds that up, and the one thing none of it can

Three checks, and they are deliberately not one:

- `.githooks/pre-commit` refuses a commit made on main. This is the spelling
  the mistake is actually made in.
- `.githooks/pre-push` refuses a push that would move main at all. It is the
  one thing a merge, a cherry-pick, a revert and a rebase all have to pass.
- `Commits on main came from a pull request` reads every commit a push
  carried, after the fact, and is what a clone that installed neither hook
  runs into.

`.git/hooks` is not tracked, so the first two are per clone and a fresh clone
has neither. The third is the net under that, which is why it exists at all.

What none of the three can do is **refuse the push at the server**. A ruleset
on `main` does, and it is the one to reach for first. The one here requires a
pull request, allows `rebase` alone, and reads `current_user_can_bypass` as
`never` for the owner, so nothing local is what stands between a mistake and
`main` any more. It requires no approving review: a sole maintainer approving
their own pull request is a form rather than a check, and a rule that asks for
one would have to be bypassed on every change.

That leaves the two hooks the half a server rule has no way to give -- a
refusal before the round trip, and the commands to undo what is already
committed, which GitHub's own refusal does not print. Both read the remote
first and stay out of a fork's `main`, which is the contributor's branch and
not this repository's business. What is on `main` today is
`gh api repos/{owner}/{repo}/rules/branches/main` and not this sentence.

## Why it lands by rebase

`main` is a line with no merge commit on it, and that is worth more than the
shape of a `git log`. `Commit messages` walks `git rev-list --no-merges`, and
commitlint ignores a merge commit by itself — measured, in the reference --
so a merge commit's own message is the one thing here that nothing reads.

Two checks hold it, one on each side: `No merge commit on a branch` refuses a
branch that merged main into itself, and `Commits on main came from a pull
request` refuses a merge commit that reached main. Bring a branch up to date
with `git fetch origin && git rebase origin/main` and a force-push.

What rebasing costs is a branch **stacked** on the one that lands. Replaying
the commits gives them new hashes, so the child's base stops being an ancestor
of main and the child turns `CONFLICTING` the moment the parent merges. A
squash does the same thing for the same reason; a merge commit is the only
method that would not, and it is the one method refused. Rebase the child onto
main and force-push it. Whether there is a child at all is worth knowing
before the merge rather than after: `gh pr list --base <branch>` answers it.

## Where an agent's work ends

With the pull request open and its checks reported. Whether to merge it, and
what to do next, is the maintainer's.

The reason is the first section's: a pull request is the last point at which
anything gets read, so an agent that merges its own has removed the only
reading the change was going to get. Nothing inside the review needs asking
for — another commit on the branch, a correction to one already there,
answering what CI came back with. It is landing the change, and moving on to
the next one, that waits to be asked for.

## What stands in for a merge gate

Nothing local refuses that merge the way `pre-push` refuses a push, because it
happens at GitHub rather than in the clone. What stands in for it is
`.claude/settings.json`, which lists `gh pr merge` under `permissions.ask`
along with the `gh api` calls that spell the same request another way. Rules
are evaluated deny, then ask, then allow, so that entry stops a call an allow
rule covers outright — measured, with its control, in the reference.

Know what it is not. A Bash rule matches the text of the command, so the same
call made from a script or through an absolute path goes straight past it, and
no rule in that file reaches an agent that is not Claude Code. It stops the
spelling the mistake is made in, which is all `pre-commit` does either. The
ruleset above is the one thing that would refuse the merge for everyone.
