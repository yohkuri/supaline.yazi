---
paths:
  - "test/**"
---

This is the test harness. Read `.agents/skills/verify-supaline/SKILL.md` first
if the change adds or alters a stub, edits one of the shell harnesses, or has a
spec hand the code a value that is wrong on purpose: a stub is worth exactly
its fidelity, the two ways a headless tmux differs from a real terminal are not
guessable, and a deliberately wrong value is refused by the type checker now
too — suppressed on its own line, never at the top of the file.

Running the suite needs nothing from it, and neither does a spec that only
feeds the code values it accepts. The commands are in `AGENTS.md`, and
`test/run.lua` refuses the wrong Lua version by itself. One habit from the
skill is worth carrying regardless: if a spec's assertions about a module look
cheap, plant a misspelled field before believing them.
