---
# Root-level Lua only, and the leading slash is what says so. Claude Code
# matches `paths` by gitignore's rules, so a bare `*.lua` reaches every
# directory, whatever its own documentation says of `*.md`. Measured on Claude
# Code 2.1.306, one fresh `claude -p` session per file read: `*.lua` attached
# this rule to `test/run.lua`, and `/*.lua` attached it to `main.lua` but not
# to `test/run.lua` or `test/fixture/init.lua`. Not run in an interactive
# session.
paths:
  - "/*.lua"
---

This is plugin Lua. If the change resolves a colour or reads the theme, writes
a fetcher, touches the parent- or preview-pane child, or adds a call into a
function a column wrote, read
`.agents/skills/yazi-platform-traps/SKILL.md` first: those are the four
constraints of Yazi 26.9.1 that no check here catches, and each one fails
silently. Otherwise carry on — the other seven are refused by a test or a CI
job that says what to write instead, so a rename or a format string needs
nothing from the skill.

If the change declares or edits a class or a field annotation instead, or casts
a value taken off `cx`, read `.agents/skills/annotate-supaline/SKILL.md`: how
far the type check reaches, where it stops, and why a difference from
`types.yazi` is declared by inheriting from Yazi's class rather than re-opening
it.

Root-level `.lua` only — the plugin itself. The stubs and specs under `test/`
model these traps rather than falling into them, and the fixture there that
Yazi does run is `verify-supaline`'s.

This rule is a pointer, not a gate. A skill loads when the model decides it is
relevant, and the whole point of a trap is that it is a surprise; a path-scoped
rule fires on the file instead, so the offer arrives whether or not anything
thought to ask for it. Whether to take it is still a judgement about the
change. Claude Code reads this; other agents get the skill's description and
the Traps list in `AGENTS.md`.
