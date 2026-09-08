---
paths:
  - "AGENTS.md"
  - ".agents/skills/**"
  - ".claude/rules/**"
---

This is one of the instruction documents. Before changing what it says, read
`.agents/skills/document-supaline/SKILL.md`: why a check is worth more than a
paragraph, how to decide which one a rule can be and why one has to be seen
failing before it is believed, where a rule has to live to reach the agent it
is for, what a description owes a reader who has not opened the skill and the
limits the Agent Skills specification puts on it, the three questions that
decide whether a paragraph belongs in a skill or in a reference beside it, the
standard a claim about the platform has to meet, and the places one change has
to land in step.

Not style — `.markdownlint-cli2.yaml` holds the wrap, the bullet and the fence
language, and CI runs it, so a clean lint is the whole of the form. And not
`README.md` or `test/MANUAL.md`, which are written for people; this rule does
not fire on them.

Fixing a typo needs nothing from the skill. Adding a rule, moving one, or
changing a count does, because nothing visible from inside the file you are
editing says that the same sentence lives in two others.
