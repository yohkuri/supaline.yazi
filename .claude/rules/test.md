---
paths:
  - "test/**"
---

This is the test harness. If the change adds or alters a stub, or edits one of
the shell harnesses, read `.agents/skills/verify-supaline/SKILL.md` first: a
stub is worth exactly its fidelity, and the two ways a headless tmux differs
from a real terminal are not guessable.

Adding an ordinary spec, or running the suite, needs nothing from it — the
commands are in `AGENTS.md`, and `test/run.lua` refuses the wrong Lua version
by itself.
