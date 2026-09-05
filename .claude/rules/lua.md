---
paths:
  - "*.lua"
---

This is plugin Lua. If the change resolves a colour or reads the theme, writes
a fetcher, or touches the parent- or preview-pane child, read
`.agents/skills/yazi-platform-traps/SKILL.md` first: those are the three
constraints of Yazi 26.9.1 that no check here catches, and each one fails
silently. Otherwise carry on — the other five are refused by a test or a CI job
that says what to write instead, so a rename or a format string needs nothing
from the skill.

Root-level `.lua` only — the plugin itself. The test harness under `test/`
models these traps rather than falling into them.

This rule is a pointer, not a gate. A skill loads when the model decides it is
relevant, and the whole point of a trap is that it is a surprise; a path-scoped
rule fires on the file instead, so the offer arrives whether or not anything
thought to ask for it. Whether to take it is still a judgement about the
change. Claude Code reads this; other agents get the skill's description and
the Traps list in `AGENTS.md`.
